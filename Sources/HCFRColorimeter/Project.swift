// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import UniformTypeIdentifiers

/// HCFR Colorimeter project file (.hcfrex): JSON with the settings and the measurements.
struct ProjectFile: Codable {
    var format = "HCFR Colorimeter project"
    /// Older files were written as "HCFR Colorimeter project".
    static let acceptedFormats: Set<String> = ["HCFR Colorimeter project", "HCFR Colorimeter Express project"]
    var formatVersion = 1
    var appVersion = AboutPanel.version
    var saved = Date()
    var standard: String
    var white: String
    var gamma: Double
    var overrideBlack: Bool
    /// Colorimeter Display (correction) used, and the meter, for reference.
    var display: String?
    var meter: String?
    var meterSerial: String?
    var lastMeasure: Date?
    /// Level (% white, e.g. "10" or "6.25") -> [X, Y, Z] in cd/m².
    var measurements: [String: [Double]]
    /// Number of gray scale points. Absent in older projects (11 points).
    var grayCount: Int? = nil
    /// References / Advanced preferences used. Absent in older projects (kept as they are).
    var references: ReferencePrefs? = nil
    /// Primary/secondary colors ("Red", …, "White") -> [X, Y, Z]. Absent in older projects.
    var colors: [String: [Double]]? = nil
}

extension UTType {
    static let hcfrProject = UTType(exportedAs: "org.hcfr.colorimeterexpress.project", conformingTo: .json)
}

extension Session {
    static let projectExtension = "hcfrex"

    var projectName: String { projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }

    /// Save project: asks for a file the first time, then saves to the same file.
    func saveProject(as saveAs: Bool = false) {
        guard activity == .idle else { return }
        var url = projectURL
        if url == nil || saveAs {
            let panel = NSSavePanel()
            panel.title = "Save project"
            panel.allowedContentTypes = [.hcfrProject]
            panel.nameFieldStringValue = projectURL?.lastPathComponent ?? defaultProjectName()
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        }
        guard let url else { return }
        let file = ProjectFile(
            standard: standard.rawValue, white: white.rawValue, gamma: gamma, overrideBlack: overrideBlack,
            display: correction?.name, meter: meter?.name, meterSerial: meter?.serial, lastMeasure: lastMeasure,
            measurements: Dictionary(uniqueKeysWithValues: measurements.map { (Self.levelKey($0.key), [$0.value.X, $0.value.Y, $0.value.Z]) }),
            grayCount: grayCount,
            references: prefs,
            colors: Dictionary(uniqueKeysWithValues: colorMeasurements.map { ($0.key.rawValue, [$0.value.X, $0.value.Y, $0.value.Z]) }))
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(file).write(to: url, options: .atomic)
            projectURL = url
            isDirty = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            status = "Project saved: \(url.lastPathComponent)"
        } catch {
            errorMessage = "Could not save the project: \(error.localizedDescription)"
        }
    }

    /// Open project: shows the file dialog (warns first if there are unsaved measurements).
    func openProjectDialog() {
        guard activity == .idle, confirmDiscardChanges() else { return }
        let panel = NSOpenPanel()
        panel.title = "Open project"
        panel.allowedContentTypes = [.hcfrProject, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url)
    }

    func openProject(_ url: URL) {
        guard activity == .idle else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(ProjectFile.self, from: Data(contentsOf: url))
            guard ProjectFile.acceptedFormats.contains(file.format) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let s = ColorStandard(rawValue: file.standard) { standard = s }
            if let w = WhitePoint(rawValue: file.white) { white = w }
            gamma = file.gamma
            overrideBlack = file.overrideBlack
            applyGrayCount(file.grayCount ?? Reference.defaultGrayCount)
            if let r = file.references { prefs = r }
            // Keys are matched to this size's levels, so "10" (older files) and "10.0" are the same level
            var m: [Double: XYZ] = [:]
            for (k, v) in file.measurements where v.count == 3 {
                guard let value = Double(k),
                      let level = allLevels.first(where: { abs($0 - value) < 1e-6 }) else { continue }
                m[level] = XYZ(X: v[0], Y: v[1], Z: v[2])
            }
            measurements = m
            var c: [PatchColor: XYZ] = [:]
            for (k, v) in file.colors ?? [:] where v.count == 3 {
                if let patch = PatchColor(rawValue: k) { c[patch] = XYZ(X: v[0], Y: v[1], Z: v[2]) }
            }
            colorMeasurements = c
            view = c.isEmpty || !m.isEmpty ? .grayScale : .primariesSecondaries
            selectedPatch = .red
            lastMeasure = file.lastMeasure
            selectedLevel = 100
            projectURL = url
            isDirty = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            var msg = "Project opened: \(url.lastPathComponent)"
            // Same Display as when it was measured, if the connected meter has it
            if let name = file.display, name != correction?.name {
                if let c = meter?.corrections.first(where: { $0.name == name }) {
                    setCorrection(c)
                } else {
                    msg += " — measured with Display \"\(name)\""
                }
            }
            status = msg
        } catch {
            errorMessage = "Could not open \(url.lastPathComponent). It is not an HCFR Colorimeter project."
        }
    }

    /// Returns false if the user cancels because there are unsaved measurements.
    func confirmDiscardChanges() -> Bool {
        guard isDirty, hasMeasurements else { return true }
        let alert = NSAlert()
        alert.messageText = "Save the current measurements?"
        alert.informativeText = "If you don't save, the current measurements will be lost."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveProject()
            return !isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    /// Level as written in the file: "10" for whole levels, else full precision ("33.333333333333336").
    static func levelKey(_ level: Double) -> String {
        level == level.rounded() ? String(Int(level)) : "\(level)"
    }

    private func defaultProjectName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return "Gray scale \(f.string(from: Date())).\(Self.projectExtension)"
    }
}
