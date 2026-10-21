// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI

/// Development use: `HCFRColorimeter --snapshot out.png` renders the window with sample data
/// (a real measurement made with HCFR) and quits, to check the layout without a colorimeter.
/// Also `--report out.pdf`, `--project-roundtrip file.hcfrex` and `--levels-test`.
enum Snapshot {
    /// `--appkit`: draws through a real (off-screen) window, so native controls appear (for
    /// screenshots); without it ImageRenderer is used, which leaves native controls out.
    @MainActor
    static func save<V: View>(_ view: V, size: NSSize, to path: String) {
        if CommandLine.arguments.contains("--appkit") {
            let app = NSApplication.shared
            if CommandLine.arguments.contains("--dark") { app.appearance = NSAppearance(named: .darkAqua) }
            else { app.appearance = NSAppearance(named: .aqua) }
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: size)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            win.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
            win.orderOut(nil)
            return
        }
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("-AppleLanguages"), let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            // Development binary (no app bundle): the translations next to it, so a language can be chosen
            for l in ["en", "es"] {
                let dst = exe.appendingPathComponent("\(l).lproj")
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: URL(fileURLWithPath: "Resources/\(l).lproj"), to: dst)
            }
            MessageRules.active = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first?.hasPrefix("es") ?? false
        }
        if args.contains("--pattern-test") {
            // Development check of the built-in pattern generator (codes and drawing)
            for levels in VideoLevels.allCases {
                for p in [TestPattern.gray(0), .gray(10), .gray(50), .gray(100), .color(.red), .color(.cyan)] {
                    let codes = p.rgb.map { levels.code($0) }
                    let full = PatternWindowController.renderTest(rgb: codes, areaPercent: 100)
                    let win = PatternWindowController.renderTest(rgb: codes, areaPercent: 10)
                    print("\(levels.rawValue) \(p.manualName): codes \(codes) drawn \(full.center), 10% window center \(win.center) corner \(win.corner)")
                }
            }
            exit(0)
        }
        if args.contains("--levels-test") {
            // Development check: levels to measure with and without Override black (restores the setting)
            let session = Session()
            let original = session.overrideBlack
            for value in [true, false] {
                session.overrideBlack = value
                print("overrideBlack=\(value): \(session.levels.count) values, \(Reference.label(session.levels.first!)) to 100")
            }
            session.overrideBlack = original
            exit(0)
        }
        if let l = args.firstIndex(of: "--lang-test"), l + 1 < args.count {
            // Development check of the Spanish strings file and the message patterns
            guard let d = NSDictionary(contentsOfFile: args[l + 1]) as? [String: String] else { print("STRINGS FAILED"); exit(1) }
            LocalizationTest.strings = d
            MessageRules.active = true
            print("STRINGS OK \(d.count)")
            for m in ["Run grey scale and colors measures on 18 values (10 to 100 IRE; Red, Green, Blue, Yellow, Cyan, Magenta, Black)?",
                      "Warning: current data will be lost.", "Use 100% Red and press Continue.", "Use 45 IRE and press Continue.",
                      "Measuring red saturation scale: 75% (4 of 5)…", "Measuring 50 IRE…", "Grey scale measurement finished",
                      "Ready — Display: LCD (White LED)", "3 colorimeters found.", "Pattern: Neutral Gradient — ESC or Patterns → Hide pattern to close",
                      "Run color checker measures on 24 values (GCD classic)?", "Something not translated, with a comma"] {
                print(m, "=>", trMessage(m))
            }
            exit(0)
        }
        if let u = args.firstIndex(of: "--url"), u + 1 < args.count, let url = URL(string: args[u + 1]) {
            // Development check of hcfr:// automation (without a meter: status / errors only)
            Session().handleAutomation(url)
            exit(0)
        }
        if let p = args.firstIndex(of: "--prefs"), p + 1 < args.count {
            // Development check: renders the Preferences pages
            let session = Session()
            for (n, page) in [(0, "references"), (1, "advanced"), (2, "general"), (3, "sensor"), (4, "appearance")] {
                save(PreferencesSnapshot(session: session, page: n), size: NSSize(width: 640, height: [1100, 560, 860, 640, 220][n]),
                     to: args[p + 1] + "-\(page).png")
            }
            exit(0)
        }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let session = Session()
        let sample: [(Double, Double, Double, Double)] = [
            (10, 0.2969, 0.3102, 0.880), (20, 0.3067, 0.3219, 3.126), (30, 0.3096, 0.3241, 7.106),
            (40, 0.3108, 0.3255, 13.674), (50, 0.3114, 0.3262, 26.810), (60, 0.3120, 0.3283, 39.654),
            (70, 0.3125, 0.3290, 55.459), (80, 0.3129, 0.3281, 74.584), (90, 0.3130, 0.3287, 97.720),
            (100, 0.3130, 0.3276, 123.189)]
        if args.contains("--primaries") {
            // Example color run: the standard's exact primaries/secondaries, red 3% low and green shifted
            let w = 120.0
            for p in PatchColor.allCases {
                let r = session.ref.rgbToXYZ.apply(p.rgb)
                var xyz = XYZ(X: r[0] * w, Y: r[1] * w, Z: r[2] * w)
                if p == .red { xyz = xyz.scaled(0.97) }
                if p == .green { xyz.X *= 1.04 }
                session.colorMeasurements[p] = xyz
            }
            session.view = .primariesSecondaries
            session.selectedPatch = args.contains("--level10") ? .green : .red
        }
        if let v = args.firstIndex(of: "--view"), v + 1 < args.count,
           let view = MeasureView.allCases.first(where: { "\($0)" == args[v + 1] }) {
            // Synthetic readings for every series view: the references, slightly off
            let w = 120.0
            for sv in MeasureView.allCases where sv.isSeries && sv != .freeMeasures {
                var m: [Int: XYZ] = [:]
                for r in session.seriesResults(sv) {
                    let k = 1 + 0.03 * sin(Double(r.index) * 1.7)
                    if sv.isGraySeries, let t = r.targetY {
                        m[r.index] = session.ref.white.xyz(Y: max(t, 0.01) * k)
                    } else if let ref = r.reference {
                        var xyz = ref.scaled(w * k)
                        xyz.X *= 1 + 0.02 * cos(Double(r.index))
                        m[r.index] = xyz
                    }
                }
                session.seriesMeasurements[sv] = m
            }
            session.freeMeasurements = (0..<12).map { i in XYZ.fromxyY(x: 0.3127 + 0.002 * sin(Double(i)), y: 0.329, Y: 118 + Double(i % 4)) }
            session.contrastMeasurements = [.black: XYZ.fromxyY(x: 0.31, y: 0.32, Y: 0.05), .white: XYZ.fromxyY(x: 0.313, y: 0.329, Y: 121),
                                            .ansi1: XYZ.fromxyY(x: 0.31, y: 0.32, Y: 0.4), .ansi2: XYZ.fromxyY(x: 0.313, y: 0.329, Y: 118)]
            session.view = view
            session.selectedIndex = 2
            session.infoGraph = .auto
        }
        if let r = args.firstIndex(of: "--report"), r + 1 < args.count {
            defer { exit(0) }
            for s in [(10.0, 0.2969, 0.3102, 0.880), (50.0, 0.3114, 0.3262, 26.810), (100.0, 0.3130, 0.3276, 123.189)] {
                session.measurements[s.0] = XYZ.fromxyY(x: s.1, y: s.2, Y: s.3)
            }
            if let pdf = Report.makePDF(session) { try? pdf.write(to: URL(fileURLWithPath: args[r + 1])) }
        }
        let maxLevel: Double = args.contains("--partial") ? 50 : args.contains("--empty") ? -1 : 100
        if let g = args.firstIndex(of: "--grays"), g + 1 < args.count, let n = Int(args[g + 1]) {
            // Gray scale of n points with synthetic readings (gamma 2.3, slightly warm low end)
            session.applyGrayCount(n)
            if maxLevel >= 0 { session.measurements[0] = XYZ.fromxyY(x: 0.30, y: 0.31, Y: 0.012) }
            for level in session.allLevels where level > 0 && level <= maxLevel {
                let v = Reference.grayProp(level)
                session.measurements[level] = XYZ.fromxyY(x: 0.3127 - 0.01 * (1 - v), y: 0.3290 - 0.008 * (1 - v), Y: 120 * pow(v, 2.3))
            }
        } else {
            for s in sample where s.0 <= maxLevel { session.measurements[s.0] = XYZ.fromxyY(x: s.1, y: s.2, Y: s.3) }
        }
        if !args.contains("--view") { session.infoGraph = args.contains("--cie") ? .cie : .rgbLevels }
        if let g = args.firstIndex(of: "--graph"), g + 1 < args.count,
           let graph = InfoGraph.allCases.first(where: { "\($0)" == args[g + 1] }) { session.infoGraph = graph }
        session.cieUV = args.contains("--uv")
        session.selectedLevel = args.contains("--level10") ? 10 : max(maxLevel, 10)
        if args.contains("--cie") { session.infoGraph = .cie; session.cieUV = args.contains("--uv") }
        if args.contains("--project-roundtrip") {
            // Save, clear, reopen and compare (development check of .hcfrex files)
            let url = URL(fileURLWithPath: args[i + 1])
            session.projectURL = url
            session.saveProject()
            let saved = session.measurements
            session.newProject()
            session.openProject(url)
            let same = saved.count == session.measurements.count
                && saved.allSatisfy { session.measurements[$0.key] == $0.value }
            print(same ? "ROUNDTRIP OK (\(saved.count) levels, dirty=\(session.isDirty))" : "ROUNDTRIP FAILED")
            print(session.status)
            exit(same ? 0 : 1)
        }
        if args.contains("--spectrum") {
            // Synthetic white LED-like spectrum for the selected column
            var v: [Double] = []
            for nm in stride(from: 380.0, through: 730.0, by: 10.0) {
                let blue: Double = exp(-pow((nm - 450) / 12, 2))
                let yellow: Double = 0.75 * exp(-pow((nm - 560) / 60, 2))
                v.append(blue + yellow)
            }
            session.spectra[session.selectedTarget.id] = Spectrum(start: 380, end: 730, values: v)
        }
        if args.contains("--lux") {
            for l in session.allLevels where l > 0 { session.luxValues[EditTarget.gray(l).id] = l * 1.3 }
        }
        if args.contains("--compare") {
            // Reference project: the same readings, a little bluer
            func shift(_ c: XYZ) -> XYZ { XYZ(X: c.X * 0.99, Y: c.Y, Z: c.Z * 1.03) }
            var d = ReferenceData(name: "Before calibration")
            d.gray = session.measurements.mapValues(shift)
            d.colors = session.colorMeasurements.mapValues(shift)
            d.series = session.seriesMeasurements.mapValues { $0.mapValues(shift) }
            session.refData = d
        }
        if let h = args.firstIndex(of: "--sheets"), h + 1 < args.count {
            for (suffix, text) in session.hcfrSheets() {
                try? text.write(toFile: args[h + 1] + "." + suffix + ".csv", atomically: true, encoding: .utf8)
            }
            exit(0)
        }
        if let c = args.firstIndex(of: "--csv"), c + 1 < args.count {
            try? session.csvText().write(toFile: args[c + 1], atomically: true, encoding: .utf8)
            if let r = args.firstIndex(of: "--report"), r + 1 < args.count, let pdf = Report.makePDF(session) {
                try? pdf.write(to: URL(fileURLWithPath: args[r + 1]))
            }
            exit(0)
        }
        if let wz = args.firstIndex(of: "--wizard"), wz + 1 < args.count, let n = Int(args[wz + 1]),
           let step = WizardModel.Step(rawValue: n) {
            // Development check of the wizard pages (with the sample readings)
            let w = session.wizardModel
            w.step = step
            w.before = WizardSummary(session)
            w.after = WizardSummary(session)
            let appkit = args.contains("--appkit")
            save(WizardView(session: session, w: w, scrolls: !appkit), size: appkit ? NSSize(width: 1440, height: 810) : NSSize(width: 1040, height: 720),
                 to: args[i + 1])
            exit(0)
        }
        session.status = args.contains("--appkit") ? "Ready — Display: Projector" : "Ready — Display: CRT (Hitachi CM2112MET, Diamond View 1772ie)"
        session.lastMeasure = Date()
        let size = args.contains("--appkit") ? NSSize(width: 1440, height: 810)
            : args.contains("--small") ? NSSize(width: 1180, height: 680) : NSSize(width: 1400, height: 900)
        if args.contains("--pi-output") {
            save(PiOutputSheet(session: session), size: NSSize(width: 520, height: 700), to: args[i + 1])
            exit(0)
        }
        save(ContentView(session: session, autoConnect: false), size: size, to: args[i + 1])
        exit(0)
    }
}
