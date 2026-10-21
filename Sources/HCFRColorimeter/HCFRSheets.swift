// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// HCFR's CSV export (CExport::SaveSheets, Export.cpp of HCFR for Windows, GNU GPL): five files
// <name>.GeneralSheet.csv, .GrayScaleSheet.csv, .PrimariesSheet.csv, .CCSheet.csv and
// .SpectralSheet.csv, with HCFR's layout (quoted values, ";" separator, "%f", CRLF), so tools
// made for HCFR's files (e.g. JVC gamma tools reading the GrayScaleSheet) can read them.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import UniformTypeIdentifiers

extension Session {
    private static func sheet(_ rows: [[String]]) -> String {
        rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "'") + "\"" }.joined(separator: ";") }
            .joined(separator: "\r\n") + "\r\n"
    }

    private static func num(_ v: Double?) -> String {
        guard let v, v.isFinite else { return String(format: "%f", 0.0) }
        let f = Double(Float(v))
        return String(format: "%f", abs(f) < 5e-7 ? 0 : f)   // no "-0.000000"
    }

    private var generatorName: String {
        switch patternSource {
        case .manual: return "DVD (manual)"
        case .raspberryPi: return "Raspberry Pi (PGenerator)" + (piStatus.map { " \($0)" } ?? "")
        case .display: return patternScreen.map { screenName($0) } ?? "Display"
        }
    }

    /// The five HCFR sheets, by suffix ("GrayScaleSheet" …).
    func hcfrSheets() -> [(String, String)] {
        let r = ref
        // General
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "EEEE, MMMM d, yyyy HH:mm:ss"
        let info = "\(r.standard.rawValue), \(r.white.rawValue), \(gammaDescription)"
            + (correction.map { ", Display: \($0.name)" } ?? "")
        let general = Self.sheet([["Num", "Name", "Export Date", "Sensor", "Generator", "Infos"],
                                  ["1", projectName, date.string(from: Date()), meter?.name ?? "", generatorName, info]])

        // Gray scale: every level of the scale, 0 included (unmeasured = 0, as HCFR's empty colors)
        let res = results
        var gray: [[String]] = [["Measure"] + res.indices.map { String($0) }]
        gray.append(["% White"] + res.map { Self.num(Reference.grayProp($0.level) * 100) })
        let zero = XYZ(X: 0, Y: 0, Z: 0)
        let xyzs = res.map { $0.xyz ?? zero }
        gray.append(["X"] + xyzs.map { Self.num($0.X) })
        gray.append(["Y"] + xyzs.map { Self.num($0.Y) })
        gray.append(["Z"] + xyzs.map { Self.num($0.Z) })
        let rgbs = xyzs.map { ColorMath.rgb($0, ref: r) }
        for k in 0..<3 { gray.append([["R", "G", "B"][k]] + rgbs.map { Self.num($0[k]) }) }
        gray.append(["ColorTemp"] + res.map { Self.num($0.xyz.flatMap { ColorMath.cct($0) }?.rounded()) })
        gray.append(["DeltaE"] + res.map { Self.num($0.deltaE) })

        // Primaries and secondaries
        let order: [PatchColor] = [.red, .green, .blue, .yellow, .cyan, .magenta]
        let pr = patchResults
        func pres(_ p: PatchColor) -> PatchResult? { pr.first { $0.patch == p } }
        var prim: [[String]] = [["Measure", "Red", "Green", "Blue", "Yellow", "Cyan", "Magenta"]]
        let pxyz = order.map { colorMeasurements[$0] ?? zero }
        prim.append(["X"] + pxyz.map { Self.num($0.X) })
        prim.append(["Y"] + pxyz.map { Self.num($0.Y) })
        prim.append(["Z"] + pxyz.map { Self.num($0.Z) })
        let prgb = pxyz.map { ColorMath.rgb($0, ref: r) }
        for k in 0..<3 { prim.append([["R", "G", "B"][k]] + prgb.map { Self.num($0[k]) }) }
        prim.append(["DeltaE"] + order.map { Self.num(pres($0)?.deltaE) })

        // Color checker (-1 for patches not measured, as HCFR)
        var cc: [[String]] = [["Color", "X", "Y", "Z", "R", "G", "B", "deltaE"]]
        for s in seriesResults(.colorChecker) {
            if let c = s.xyz {
                let rgb = ColorMath.rgb(c, ref: r)
                cc.append([s.name, Self.num(c.X), Self.num(c.Y), Self.num(c.Z),
                           Self.num(rgb[0]), Self.num(rgb[1]), Self.num(rgb[2]), Self.num(s.deltaE)])
            } else {
                cc.append([s.name] + Array(repeating: Self.num(-1), count: 7))
            }
        }

        // Spectra of red, green, blue and white (spectral meters)
        var spec: [[String]] = [["Wavelength {nm}", "Red", "Green", "Blue", "White"]]
        if let red = spectra[EditTarget.patch(.red).id] {
            let others = [spectra[EditTarget.patch(.green).id], spectra[EditTarget.patch(.blue).id],
                          spectra[EditTarget.contrast(1).id] ?? spectra[EditTarget.patch(.white).id]
                              ?? spectra[EditTarget.gray(100).id]]
            for i in red.values.indices {
                var row = [Self.num(red.wavelength(i)), Self.num(red.values[i])]
                for o in others { if let o, i < o.values.count { row.append(Self.num(o.values[i])) } }
                spec.append(row)
            }
        }

        return [("GeneralSheet", general), ("GrayScaleSheet", Self.sheet(gray)), ("PrimariesSheet", Self.sheet(prim)),
                ("CCSheet", Self.sheet(cc)), ("SpectralSheet", Self.sheet(spec))]
    }

    /// File → "Export HCFR sheets (CSV)…": the five files of HCFR for Windows' CSV export.
    func exportHCFRSheets() {
        let panel = NSSavePanel()
        panel.title = tr("Export HCFR sheets (CSV)")
        panel.message = tr("Creates the five files of HCFR for Windows' export: name.GeneralSheet.csv, name.GrayScaleSheet.csv, name.PrimariesSheet.csv, name.CCSheet.csv and name.SpectralSheet.csv.")
        panel.nameFieldStringValue = projectName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let base = url.pathExtension.lowercased() == "csv" ? url.deletingPathExtension() : url
        do {
            let chosen = appPrefs.exportSheets.isEmpty ? ["GrayScaleSheet"] : appPrefs.exportSheets
            for (suffix, text) in hcfrSheets() where chosen.contains(suffix) {
                let file = base.deletingLastPathComponent().appendingPathComponent(base.lastPathComponent + "." + suffix + ".csv")
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
            status = "Exported: \(base.lastPathComponent) (\(chosen.count) HCFR sheets)"
        } catch {
            errorMessage = "Could not export: \(error.localizedDescription)"
        }
    }
}
