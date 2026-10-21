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
    /// Kind of display, technology, brand and model of a CCSS, from its description
    /// ("LG C3 (WRGB OLED) - JETI 1501 HiRes 2nm"), cached. nil for HCFR's own families.
    static func entry(_ descriptor: String) -> CCSSEntry? { cache.entry(descriptor) }

    private final class Cache: @unchecked Sendable {
        private var d: [String: CCSSEntry?] = [:]
        private let lock = NSLock()
        func entry(_ s: String) -> CCSSEntry? {
            lock.lock(); defer { lock.unlock() }
            if let e = d[s] { return e }
            let e = CCSSLibrary.classify(s)
            d[s] = e
            return e
        }
    }
    private static let cache = Cache()

    /// Only CCSS of a display library: "<model> (<detail>) - <instrument>"; HCFR's families
    /// ("CRT", "WLED Family 07Feb11"…) are not classified.
    static func classify(_ d: String) -> CCSSEntry? {
        guard d.contains(" - ") else { return nil }
        let parts = d.components(separatedBy: " - ")
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        let instrument = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        var model = name, detail = ""
        if let open = name.firstIndex(of: "("), name.hasSuffix(")") {
            model = String(name[..<open]).trimmingCharacters(in: .whitespaces)
            detail = String(name[name.index(after: open)..<name.index(before: name.endIndex)])
        }
        let low = d.lowercased()
        func has(_ k: String...) -> Bool { k.contains { low.contains($0) } }
        let generic = ["CCFL", "RG Phosphor", "Wide Gamut CCFL", "PFS Phosphor", "RGB LED", "White LED", "Plasma", "Projector"].contains(model)
        let brand = generic ? "Generic" : String(model.split(separator: " ").first ?? Substring(model))
        let display: String
        if has("projector", "hisense c2", "xgimi") { display = "Projectors" }
        else if generic { display = "Generic families" }
        else if has("macbook", "ipad", "surface", "thinkpad", "lenovo", "zbook", "laptop") { display = "Laptops & tablets" }
        else if has("asus pa", "benq", "dell ultrasharp", "eizo", "fsi ", "hp dreamcolor", "nec ", "canon", "aeq kroma", "smallhd",
                    "tvlogic", "sony bvm", "sony pvm", "boland", "lg 32ep950", "pro display xdr", "monitor") && !has("lg c8") {
            display = "Monitors (pro / desktop)"
        } else { display = "TVs" }
        let tech: String
        if display == "Projectors" {
            tech = has("triple laser") || (has("rgb") && has("laser")) ? "RGB laser" : has("laser", "lazer") ? "Laser" : has("lamp") ? "Lamp" : "Projector (generic)"
        } else if has("wrgb", "woled") { tech = "WOLED (WRGB OLED)" }
        else if has("qd-oled") { tech = "QD-OLED" }
        else if has("oled", "ipad pro 2024") { tech = "RGB OLED" }
        else if has("mini") && has("rgb") { tech = "RGB Mini-LED" }
        else if has("mini", "pa32ucg", "pa32ucx", "pro display xdr", "65xr90") { tech = "QD / Mini-LED" }
        else if has("qd-led", "qd led", "ksf", "pfs") { tech = "QD / KSF-PFS LED" }
        else if has("gb-r", "gb-led", "rgb led", "psr led") { tech = "GB-R / RGB LED" }
        else if has("ccfl") { tech = "CCFL" }
        else if has("plasma") { tech = "Plasma" }
        else if has("phosphor") { tech = "Phosphor (CRT)" }
        else { tech = "White LED LCD" }
        return CCSSEntry(file: "", descriptor: d, display: display, technology: tech, brand: brand,
                         model: model.hasPrefix("LG C8") ? "LG C8 / FSI XM" : model, detail: detail, instrument: instrument)
    }

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

    /// Display → "Load display library from a folder…" / "Import CCSS / CCMX files…": copies the
    /// files (a folder: every .ccss / .ccmx inside, subfolders included) to the user's correction
    /// folder, which the meter reads when it connects.
    @MainActor
    static func importFiles(session: Session, folder: Bool) {
        let panel = NSOpenPanel()
        panel.title = tr(folder ? "Choose the folder of your CCSS files" : "Import CCSS / CCMX files")
        panel.canChooseDirectories = folder
        panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = !folder
        if !folder { panel.allowedContentTypes = ["ccss", "ccmx"].compactMap { UTType(filenameExtension: $0) } }
        guard panel.runModal() == .OK else { return }
        var sources: [URL] = []
        let fm = FileManager.default
        for url in panel.urls {
            if folder, let e = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let f as URL in e where ["ccss", "ccmx"].contains(f.pathExtension.lowercased()) { sources.append(f) }
            } else {
                sources.append(url)
            }
        }
        let dir = Session.userCorrectionsDir
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var n = 0
        for url in sources {
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: dest)
            if (try? fm.copyItem(at: url, to: dest)) != nil { n += 1 }
        }
        if folder { UserDefaults.standard.set(panel.urls.first?.path, forKey: "ccssLibraryFolder") }
        session.status = "Loaded \(n) correction files. Reconnecting the colorimeter to list them in Display…"
        if session.meter != nil, session.activity == .idle { session.connect() }
    }
}
}

/// Display type of the colorimeter as a tree: built-in types, HCFR's families, the display library
/// (kind of display → technology → brand) and the user's own files, plus a search window.
struct CorrectionMenu: View {
    @ObservedObject var session: Session

    var body: some View {
        Menu {
            if let m = session.meter {
                let builtIn = m.corrections.filter { !$0.isCCSS }
                let lib = m.corrections.filter { $0.isCCSS && CCSSLibrary.entry($0.name) != nil }
                let other = m.corrections.filter { $0.isCCSS && CCSSLibrary.entry($0.name) == nil }
                Section("Meter types") { ForEach(builtIn) { item($0) } }
                if !other.isEmpty { Section("HCFR and your files") { ForEach(other) { item($0) } } }
                if !lib.isEmpty {
                    Section(tr("Display library") + " (\(lib.count))") {
                        let pairs = lib.compactMap { c in CCSSLibrary.entry(c.name).map { LibItem(c: c, e: $0) } }
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
                Button("Search display…") { session.correctionSearch = ""; session.searchingCorrection = true }
            }
            Button("Load display library from a folder…") { CCSSLibrary.importFiles(session: session, folder: true) }
            Button("Import CCSS / CCMX files…") { CCSSLibrary.importFiles(session: session, folder: false) }
        } label: {
            Text(session.correction.map { CCSSLibrary.entry($0.name)?.title ?? $0.name }
                 ?? tr(session.meter == nil ? "Connect a colorimeter" : "Choose the display"))
                .lineLimit(1)
        }
        .disabled(session.meter == nil || session.activity != .idle)
        .help("Display type of the colorimeter: the meter's own types, HCFR's families and the display library (by kind of display, technology and brand). Search finds any of them by name.")
        .sheet(isPresented: $session.searchingCorrection) { CorrectionSearch(session: session) }
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
    private var text: String { session.correctionSearch }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search display").font(.title3.bold())
            TextField("Brand, model or technology (e.g. LG C3, QD-OLED, NZ9)", text: $session.correctionSearch)
                .textFieldStyle(.roundedBorder)
            List(results, id: \.id) { c in
                Button {
                    session.setCorrection(c)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CCSSLibrary.entry(c.name)?.title ?? c.name)
                        if let e = CCSSLibrary.entry(c.name) {
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
            let e = CCSSLibrary.entry(c.name)
            let hay = ([c.name] + [e?.display, e?.technology].compactMap { $0 }.map(tr)).joined(separator: " ").lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }
}
