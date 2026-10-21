// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Excel export added in 2026 (HCFR for Windows: Advanced → Export → Measures to xls file).
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import UniformTypeIdentifiers

/// A minimal .xlsx writer (Office Open XML in a ZIP without compression): one worksheet per
/// table, numbers as numbers and the rest as text. Excel, Numbers and LibreOffice open it.
enum XLSXWriter {
    static func make(sheets: [(String, [[String]])]) -> Data {
        var files: [(String, Data)] = []
        func add(_ path: String, _ text: String) { files.append((path, Data(text.utf8))) }
        let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        add("[Content_Types].xml", header + """
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/>\
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
            \(sheets.indices.map { "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined())\
            </Types>
            """)
        add("_rels/.rels", header + """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
            </Relationships>
            """)
        add("xl/workbook.xml", header + """
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\
            \(sheets.enumerated().map { "<sheet name=\"\(esc(String($0.element.0.prefix(31))))\" sheetId=\"\($0.offset + 1)\" r:id=\"rId\($0.offset + 1)\"/>" }.joined())\
            </sheets></workbook>
            """)
        add("xl/_rels/workbook.xml.rels", header + """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            \(sheets.indices.map { "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>" }.joined())\
            </Relationships>
            """)
        for (i, sheet) in sheets.enumerated() {
            var x = header + "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
            for (r, row) in sheet.1.enumerated() {
                x += "<row r=\"\(r + 1)\">"
                for (c, v) in row.enumerated() {
                    let ref = column(c) + String(r + 1)
                    if let d = Double(v), v.rangeOfCharacter(from: .letters) == nil {
                        x += "<c r=\"\(ref)\"><v>\(d)</v></c>"
                    } else {
                        x += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(esc(v))</t></is></c>"
                    }
                }
                x += "</row>"
            }
            x += "</sheetData></worksheet>"
            add("xl/worksheets/sheet\(i + 1).xml", x)
        }
        return zip(files)
    }

    static func column(_ i: Int) -> String {
        var n = i + 1, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }
        return s
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// ZIP with stored (uncompressed) entries.
    static func zip(_ files: [(String, Data)]) -> Data {
        var out = Data(), central = Data()
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: UInt32) -> [UInt8] { MadVRClient.le(v) }
        for (name, data) in files {
            let n = Array(name.utf8), crc = MadVRClient.crc32(Array(data)), size = UInt32(data.count)
            let offset = UInt32(out.count)
            out.append(contentsOf: [0x50, 0x4B, 0x03, 0x04] + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
                       + le32(crc) + le32(size) + le32(size) + le16(n.count) + le16(0) + n)
            out.append(data)
            central.append(contentsOf: [0x50, 0x4B, 0x01, 0x02] + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
                           + le32(crc) + le32(size) + le32(size) + le16(n.count) + le16(0) + le16(0) + le16(0) + le16(0)
                           + le32(0) + le32(offset) + n)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(contentsOf: [0x50, 0x4B, 0x05, 0x06] + le16(0) + le16(0) + le16(files.count) + le16(files.count)
                   + le32(UInt32(central.count)) + le32(cdOffset) + le16(0))
        return out
    }
}

extension Session {
    /// File → "Export to Excel…": HCFR's five sheets (general, gray scale, primaries, Color Checker,
    /// spectra) and the current table, in one workbook.
    func exportExcel() {
        let panel = NSSavePanel()
        panel.title = tr("Export to Excel")
        panel.nameFieldStringValue = projectName + ".xlsx"
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var sheets: [(String, [[String]])] = hcfrSheets().map { suffix, text in
            let rows = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }.map { line in
                line.components(separatedBy: ";").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }
            return (suffix.replacingOccurrences(of: "Sheet", with: ""), rows)
        }
        let table = csvText().components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.components(separatedBy: ",") }
        if !table.isEmpty { sheets.append(("Table", table)) }
        do {
            try XLSXWriter.make(sheets: sheets).write(to: url)
            status = "Exported: \(url.lastPathComponent)"
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}
