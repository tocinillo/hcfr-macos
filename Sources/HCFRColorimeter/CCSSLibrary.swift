// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Display library (CCSS spectral corrections in a tree) added in 2026.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The CCSS files of the display library (Resources/ccss-library.json): each one with its kind
/// of display, technology and brand, to show them as a tree instead of one long list.
struct CCSSEntry: Codable, Hashable {
    var file: String
    var descriptor: String
    var display: String
    var technology: String
    var brand: String
    var model: String
    var detail: String
    var instrument: String

    /// Menu title: "C3 (WRGB OLED) · JETI 1501 HiRes 2nm".
    var title: String {
        let m = brand != "Generic" && model.hasPrefix(brand + " ") ? String(model.dropFirst(brand.count + 1)) : model
        return m + (detail.isEmpty ? "" : " (\(detail))") + (instrument.isEmpty ? "" : " · \(instrument)")
    }
}

enum CCSSLibrary {
    static let entries: [CCSSEntry] = {
        var urls: [URL] = []
        if let u = Bundle.main.url(forResource: "ccss-library", withExtension: "json") { urls.append(u) }
        if let dir = MeterHelper.correctionsDataDir { urls.append(URL(fileURLWithPath: dir).appendingPathComponent("ccss-library.json")) }
        for u in urls {
            if let d = try? Data(contentsOf: u), let e = try? JSONDecoder().decode([CCSSEntry].self, from: d) { return e }
        }
        return []
    }()

    static let byDescriptor: [String: CCSSEntry] = {
        var d: [String: CCSSEntry] = [:]
        for e in entries { d[e.descriptor] = e }
        return d
    }()

    /// Order of the first two levels of the tree.
    static let displayOrder = ["Projectors", "TVs", "Monitors (pro / desktop)", "Laptops & tablets", "Generic families"]
    static let technologyOrder = ["Laser", "RGB laser", "Lamp", "Projector (generic)", "WOLED (WRGB OLED)", "QD-OLED", "RGB OLED",
                                  "RGB Mini-LED", "QD / Mini-LED", "QD / KSF-PFS LED", "GB-R / RGB LED", "White LED LCD",
                                  "CCFL", "Plasma", "Phosphor (CRT)"]

    static func sorted(_ values: Set<String>, by order: [String]) -> [String] {
        values.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? 999, ib = order.firstIndex(of: b) ?? 999
            return ia != ib ? ia < ib : a < b
        }
    }

    /// File → copied to the user's correction folder; the meter lists it after reconnecting.
    @MainActor
    static func importFiles(session: Session) {
        let panel = NSOpenPanel()
        panel.title = tr("Import CCSS / CCMX files")
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["ccss", "ccmx"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        let dir = Session.userCorrectionsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var n = 0
        for url in panel.urls {
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { n += 1 }
        }
        session.status = "Imported \(n) correction files: connect the colorimeter again to see them in Display"
    }
}

/// Display type of the colorimeter as a tree: built-in types, HCFR's families, the display library
/// (kind of display → technology → brand) and the user's own files, plus a search window.
struct CorrectionMenu: View {
    @ObservedObject var session: Session
    @State private var searching = false

    var body: some View {
        Menu {
            if let m = session.meter {
                let builtIn = m.corrections.filter { !$0.isCCSS }
                let lib = m.corrections.filter { $0.isCCSS && CCSSLibrary.byDescriptor[$0.name] != nil }
                let other = m.corrections.filter { $0.isCCSS && CCSSLibrary.byDescriptor[$0.name] == nil }
                Section("Meter types") { ForEach(builtIn) { item($0) } }
                if !other.isEmpty { Section("HCFR and your files") { ForEach(other) { item($0) } } }
                if !lib.isEmpty {
                    Section(tr("Display library") + " (\(lib.count))") {
                        let pairs = lib.compactMap { c in CCSSLibrary.byDescriptor[c.name].map { LibItem(c: c, e: $0) } }
                        ForEach(CCSSLibrary.sorted(Set(pairs.map(\.e.display)), by: CCSSLibrary.displayOrder), id: \.self) { disp in
                            Menu(tr(disp)) {
                                let inDisp = pairs.filter { $0.e.display == disp }
                                ForEach(CCSSLibrary.sorted(Set(inDisp.map(\.e.technology)), by: CCSSLibrary.technologyOrder), id: \.self) { tech in
                                    Menu(tr(tech)) {
                                        let inTech = inDisp.filter { $0.e.technology == tech }
                                        ForEach(Set(inTech.map(\.e.brand)).sorted(), id: \.self) { brand in
                                            Menu(brand == "Generic" ? tr("Generic") : brand) {
                                                ForEach(inTech.filter { $0.e.brand == brand }.sorted { $0.e.title < $1.e.title }) { pair in
                                                    item(pair.c, title: pair.e.title)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Search display…") { searching = true }
            }
            Button("Import CCSS / CCMX files…") { CCSSLibrary.importFiles(session: session) }
        } label: {
            Text(session.correction.map { CCSSLibrary.byDescriptor[$0.name]?.title ?? $0.name }
                 ?? tr(session.meter == nil ? "Connect a colorimeter" : "Choose the display"))
                .lineLimit(1)
        }
        .disabled(session.meter == nil || session.activity != .idle)
        .help("Display type of the colorimeter: the meter's own types, HCFR's families and the display library (by kind of display, technology and brand). Search finds any of them by name.")
        .sheet(isPresented: $searching) { CorrectionSearch(session: session) }
    }

    @ViewBuilder private func item(_ c: MeterCorrection, title: String? = nil) -> some View {
        Button {
            session.setCorrection(c)
        } label: {
            if session.correction == c { Label(title ?? c.name, systemImage: "checkmark") } else { Text(title ?? c.name) }
        }
    }
}

private struct LibItem: Identifiable {
    let c: MeterCorrection
    let e: CCSSEntry
    var id: Int { c.id }
}

/// "Search display…": every correction of the meter, filtered as you type.
private struct CorrectionSearch: View {
    @ObservedObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search display").font(.title3.bold())
            TextField("Brand, model or technology (e.g. LG C3, QD-OLED, NZ9)", text: $text)
                .textFieldStyle(.roundedBorder)
            List(results, id: \.id) { c in
                Button {
                    session.setCorrection(c)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CCSSLibrary.byDescriptor[c.name]?.title ?? c.name)
                        if let e = CCSSLibrary.byDescriptor[c.name] {
                            Text(tr(e.display) + " · " + tr(e.technology)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 320)
            HStack {
                Text("\(results.count) / \(session.meter?.corrections.count ?? 0)").foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 560, height: 520)
    }

    private var results: [MeterCorrection] {
        let all = session.meter?.corrections ?? []
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return all }
        return all.filter { c in
            let e = CCSSLibrary.byDescriptor[c.name]
            let hay = ([c.name] + [e?.display, e?.technology].compactMap { $0 }.map(tr)).joined(separator: " ").lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }
}
