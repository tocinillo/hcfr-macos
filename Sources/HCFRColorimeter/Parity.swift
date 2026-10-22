// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// HCFR for Windows features added in 2026: Undo of measures, the Luminance window, the tab menu,
// Duplicate with a choice of data, Excel append, Page Setup and reset of the preferences.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Undo (HCFR's Edit → Undo: measures, edits and deletes)

/// The measured data of a project, as it was before a change.
struct MeasureState {
    var measurements: [Double: XYZ]
    var colors: [PatchColor: XYZ]
    var series: [MeasureView: [Int: XYZ]]
    var free: [XYZ]
    var contrast: [ContrastPatch: XYZ]
    var spectra: [String: Spectrum]
    var lux: [String: Double]
    var grayCount: Int
    var sizes: (Int, Int, Int)
    var view: MeasureView
}

final class MeasureUndo {
    var undo: [MeasureState] = []
    var redo: [MeasureState] = []
    /// While undoing / redoing or opening a project: changes are not recorded.
    var suppressed = false
    /// One change already recorded in this turn of the run loop (a measure changes several tables).
    var pending = false
    static let limit = 100
}

extension Session {
    var measureState: MeasureState {
        MeasureState(measurements: measurements, colors: colorMeasurements, series: seriesMeasurements,
                     free: freeMeasurements, contrast: contrastMeasurements, spectra: spectra, lux: luxValues,
                     grayCount: grayCount, sizes: (nearBlackCount, nearWhiteCount, saturationCount), view: view)
    }

    /// Called before the measured data changes (willSet): keeps the data as it was.
    func noteMeasureChange() {
        let u = measureUndo
        guard !u.suppressed, !u.pending else { return }
        u.pending = true
        u.undo.append(measureState)
        if u.undo.count > MeasureUndo.limit { u.undo.removeFirst(u.undo.count - MeasureUndo.limit) }
        u.redo.removeAll()
        DispatchQueue.main.async { u.pending = false }
    }

    func clearMeasureUndo() {
        measureUndo.undo.removeAll()
        measureUndo.redo.removeAll()
    }

    var canUndoMeasure: Bool { !measureUndo.undo.isEmpty && activity == .idle }
    var canRedoMeasure: Bool { !measureUndo.redo.isEmpty && activity == .idle }

    func undoMeasure() {
        guard canUndoMeasure, let s = measureUndo.undo.popLast() else { return }
        measureUndo.redo.append(measureState)
        apply(s)
        status = tr("Undone")
    }

    func redoMeasure() {
        guard canRedoMeasure, let s = measureUndo.redo.popLast() else { return }
        measureUndo.undo.append(measureState)
        apply(s)
        status = tr("Redone")
    }

    private func apply(_ s: MeasureState) {
        measureUndo.suppressed = true
        defer { measureUndo.suppressed = false }
        if s.grayCount != grayCount { applyGrayCount(s.grayCount) }
        applySeriesSizes(nearBlack: s.sizes.0, nearWhite: s.sizes.1, saturation: s.sizes.2)
        measurements = s.measurements
        colorMeasurements = s.colors
        seriesMeasurements = s.series
        freeMeasurements = s.free
        contrastMeasurements = s.contrast
        spectra = s.spectra
        luxValues = s.lux
        if s.view != view { view = s.view }
        if selectedIndex >= columnCount(view) { selectedIndex = 0 }
        isDirty = true
        objectWillChange.send()
    }

    /// Edit → Undo / Redo: a text field being edited undoes its typing, else the measures.
    static func undoCommand(_ s: Session, redo: Bool) {
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, let um = tv.undoManager,
           redo ? um.canRedo : um.canUndo {
            redo ? um.redo() : um.undo()
            return
        }
        redo ? s.redoMeasure() : s.undoMeasure()
    }
}

// MARK: - View → Luminance (HCFR's floating luxmeter window)

@MainActor
final class LuminanceWindowModel: ObservableObject {
    @Published var text = "—"
    weak var session: Session?
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// As HCFR's OnRefreshLux: "++++" out of range, else the value in Lux or Ft-cd.
    func refresh() {
        guard let s = session else { return }
        let l = s.luxmeter.latest()
        if !l.running { text = tr("No luxmeter"); return }
        if l.overRange { text = "++++"; return }
        guard let v = l.value else { text = "----"; return }
        text = s.appPrefs.imperialUnits ? String(format: "%.5g Ft-cd", v * 0.0929) : String(format: "%.5g Lux", v)
    }
}

struct LuminanceWindowView: View {
    @ObservedObject var model: LuminanceWindowModel

    var body: some View {
        GeometryReader { geo in
            Text(model.text)
                .font(.system(size: max(min(geo.size.height * 0.45, geo.size.width / 7), 12), weight: .semibold, design: .monospaced))
                .minimumScaleFactor(0.3)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .frame(minWidth: 160, minHeight: 60)
    }
}

@MainActor
enum LuminanceWindow {
    private static var panel: NSPanel?
    private static let model = LuminanceWindowModel()

    static var isShown: Bool { panel?.isVisible ?? false }

    static func toggle(_ session: Session) {
        if let p = panel, p.isVisible, model.session === session {
            p.close()
            model.stop()
            return
        }
        model.session = session
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 110),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.title = tr("Luminance")
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.level = .floating
            p.contentView = NSHostingView(rootView: LuminanceWindowView(model: model))
            p.center()
            panel = p
        }
        model.start()
        panel?.orderFront(nil)
    }
}

// MARK: - Tab menu (HCFR's right-click menu of a tab)

struct TabContextMenu: View {
    @ObservedObject var session: Session
    let tab: MeasureView
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Activate tab") { if session.activity != .measuring { session.view = tab } }
        Button("Activate tab on all documents") {
            for s in Session.open where s.activity != .measuring { s.view = tab }
        }
        Button("Duplicate tab") { copy(asTab: true) }
            .help("A copy of the project, showing this table, as a new tab of this window")
        Button("Open tab in a new window") { copy(asTab: false) }
            .help("A copy of the project, showing this table, in a new window")
        Divider()
        Button("Close tab") { session.closeTab(tab) }
            .disabled(session.openTabs.count < 2)
    }

    private func copy(asTab: Bool) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HCFR copy \(UUID().uuidString).hcfrex")
        session.saveProject(copyTo: url)
        if asTab, let w = NSApp.keyWindow { ProjectTabs.prepare(w); ProjectTabs.pendingParent = w }
        openWindow(id: "document", value: DocumentRequest(path: url.path, isCopy: true, view: tab.rawValue))
    }
}

// MARK: - File → Duplicate… (HCFR's Duplicate dialog: which data to copy)

/// The tables a project copy keeps.
@MainActor
enum DuplicateData {
    static func views(of s: Session) -> [MeasureView] {
        var v: [MeasureView] = []
        if !s.measurements.isEmpty { v.append(.grayScale) }
        if !s.colorMeasurements.isEmpty { v.append(.primariesSecondaries) }
        v += MeasureView.allCases.filter { !(s.seriesMeasurements[$0]?.isEmpty ?? true) }
        if !s.contrastMeasurements.isEmpty { v.append(.contrast) }
        if !s.freeMeasurements.isEmpty { v.append(.freeMeasures) }
        return v
    }

    /// Asks which tables to copy; nil if cancelled.
    static func choose(_ s: Session) -> [String]? {
        let views = views(of: s)
        guard !views.isEmpty else { return [] }
        let alert = NSAlert()
        alert.messageText = tr("Duplicate project")
        alert.informativeText = tr("Data to copy to the new project:")
        let boxes = views.map { v -> NSButton in
            let b = NSButton(checkboxWithTitle: tr(v.rawValue), target: nil, action: nil)
            b.state = .on
            b.identifier = NSUserInterfaceItemIdentifier(v.rawValue)
            return b
        }
        let stack = NSStackView(views: boxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: CGFloat(boxes.count) * 22)
        alert.accessoryView = stack
        alert.addButton(withTitle: tr("Duplicate"))
        alert.addButton(withTitle: tr("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return boxes.filter { $0.state == .on }.compactMap { $0.identifier?.rawValue }
    }
}

extension Session {
    /// Removes the tables not kept by File → Duplicate….
    func keepOnly(_ keep: [String]) {
        let kept = Set(keep.compactMap(MeasureView.init(rawValue:)))
        let prefixes: [(MeasureView, String)] = [(.grayScale, "gray:"), (.primariesSecondaries, "patch:"),
                                                  (.contrast, "contrast:"), (.freeMeasures, "free:")]
        func drop(_ prefix: String) {
            spectra = spectra.filter { !$0.key.hasPrefix(prefix) }
            luxValues = luxValues.filter { !$0.key.hasPrefix(prefix) }
        }
        for (v, p) in prefixes where !kept.contains(v) { drop(p) }
        if !kept.contains(.grayScale) { measurements.removeAll() }
        if !kept.contains(.primariesSecondaries) { colorMeasurements.removeAll() }
        if !kept.contains(.contrast) { contrastMeasurements.removeAll() }
        if !kept.contains(.freeMeasures) { freeMeasurements.removeAll() }
        for v in seriesMeasurements.keys where !kept.contains(v) {
            seriesMeasurements[v] = nil
            drop("series:\(v.rawValue):")
        }
        openTabs = openTabs.filter { kept.contains($0) }
        if openTabs.isEmpty { openTabs = [.grayScale] }
        tabUse = openTabs
        if !openTabs.contains(view) { view = openTabs[0] }
    }
}

// MARK: - Excel: add to an existing workbook (HCFR's Excel export "append")

enum XLSXAppend {
    /// Adds the sheets to a workbook (one made by this app or saved by Excel). Uses macOS's
    /// zip / unzip, as the workbook may be compressed.
    static func append(sheets: [(String, [[String]])], to url: URL) throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("HCFR xlsx \(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try run("/usr/bin/unzip", ["-q", "-o", url.path, "-d", dir.path])

        let wbURL = dir.appendingPathComponent("xl/workbook.xml")
        let relsURL = dir.appendingPathComponent("xl/_rels/workbook.xml.rels")
        let typesURL = dir.appendingPathComponent("[Content_Types].xml")
        var wb = try String(contentsOf: wbURL, encoding: .utf8)
        var rels = try String(contentsOf: relsURL, encoding: .utf8)
        var types = try String(contentsOf: typesURL, encoding: .utf8)
        guard wb.contains("</sheets>"), rels.contains("</Relationships>"), types.contains("</Types>") else {
            throw NSError(domain: "HCFR", code: 1, userInfo: [NSLocalizedDescriptionKey: tr("It is not an Excel workbook.")])
        }
        // Names, ids and file numbers already used
        let names = matches(#"<sheet [^>]*name="([^"]*)""#, wb).map { $0.lowercased() }
        var sheetId = (matches(#"sheetId="(\d+)""#, wb).compactMap(Int.init).max() ?? 0) + 1
        let sheetsDir = dir.appendingPathComponent("xl/worksheets")
        try fm.createDirectory(at: sheetsDir, withIntermediateDirectories: true)
        var fileNo = 1
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            .replacingOccurrences(of: ":", with: ".")
        var usedNames = Set(names)
        for (i, sheet) in sheets.enumerated() {
            while fm.fileExists(atPath: sheetsDir.appendingPathComponent("sheet\(fileNo).xml").path) { fileNo += 1 }
            var name = String((sheet.0 + " " + stamp).prefix(31))
            var k = 2
            while usedNames.contains(name.lowercased()) { name = String((sheet.0 + " " + stamp).prefix(27)) + " (\(k))"; k += 1 }
            usedNames.insert(name.lowercased())
            let file = "sheet\(fileNo).xml"
            try XLSXWriter.worksheet(sheet.1).write(to: sheetsDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
            let rid = "rIdHCFR\(sheetId)x\(i)"
            wb = wb.replacingOccurrences(of: "</sheets>",
                                         with: "<sheet name=\"\(XLSXWriter.esc(name))\" sheetId=\"\(sheetId)\" r:id=\"\(rid)\"/></sheets>")
            rels = rels.replacingOccurrences(of: "</Relationships>",
                                             with: "<Relationship Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/\(file)\"/></Relationships>")
            types = types.replacingOccurrences(of: "</Types>",
                                               with: "<Override PartName=\"/xl/worksheets/\(file)\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>")
            sheetId += 1
            fileNo += 1
        }
        // The relationships namespace "r" must be declared in the workbook
        if !wb.contains("xmlns:r=") {
            wb = wb.replacingOccurrences(of: "<workbook ", with: "<workbook xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" ")
        }
        try wb.write(to: wbURL, atomically: true, encoding: .utf8)
        try rels.write(to: relsURL, atomically: true, encoding: .utf8)
        try types.write(to: typesURL, atomically: true, encoding: .utf8)
        let tmp = fm.temporaryDirectory.appendingPathComponent("HCFR \(UUID().uuidString).xlsx")
        try run("/usr/bin/zip", ["-q", "-r", "-X", tmp.path, "."], cwd: dir)
        _ = try fm.replaceItemAt(url, withItemAt: tmp)
    }

    private static func matches(_ pattern: String, _ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap {
            Range($0.range(at: 1), in: s).map { String(s[$0]) }
        }
    }

    private static func run(_ tool: String, _ args: [String], cwd: URL? = nil) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "HCFR", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: tr("Could not read or write the workbook.")])
        }
    }
}

// MARK: - Preferences: reset to the defaults; File → Page Setup…

extension Session {
    func resetPreferences() {
        let alert = NSAlert()
        alert.messageText = tr("Reset all the preferences to their default values?")
        alert.informativeText = tr("General, References, Appearance, Advanced, Sensor and the graph options go back to HCFR's defaults. The measures are kept.")
        alert.addButton(withTitle: tr("Reset"))
        alert.addButton(withTitle: tr("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        appPrefs = AppPrefs()
        prefs = ReferencePrefs()
        graphOptions = GraphOptions()
        status = tr("Preferences reset to their default values")
    }

    static func pageSetup() {
        NSPageLayout().runModal(with: NSPrintInfo.shared)
    }
}
