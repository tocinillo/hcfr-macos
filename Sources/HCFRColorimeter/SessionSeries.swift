// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Near black / near white / saturation / Color Checker / free measures / contrast views, added in
// 2026 after HCFR for Windows (Measure.cpp), Copyright (c) Association Homecinema Francophone and
// HCFR contributors, GNU GPL.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import UniformTypeIdentifiers

extension Session {
    // MARK: - Columns of each view

    /// Gray level (%) of a near black / near white column (HCFR: i% and (101 − size + i)%).
    func seriesLevel(_ v: MeasureView, _ i: Int) -> Double {
        v == .nearBlack ? Double(i) : Double(101 - nearWhiteCount + i)
    }

    /// Number of points of a series view, as HCFR's Scale sizes.
    func seriesCount(_ v: MeasureView) -> Int {
        switch v {
        case .nearBlack: return nearBlackCount
        case .nearWhite: return nearWhiteCount
        case .colorChecker: return ccPatches.count
        case .freeMeasures: return freeMeasurements.count
        default: return v.saturationColor != nil ? saturationCount : 0
        }
    }

    func columnCount(_ v: MeasureView) -> Int {
        switch v {
        case .grayScale: return allLevels.count
        case .primariesSecondaries: return PatchColor.allCases.count
        case .contrast: return ContrastPatch.allCases.count
        default: return seriesCount(v)
        }
    }

    var ccPatches: [SeriesPatch] { ccSet.patches(user: userCCRows) }

    /// Patterns of a series: name (column header) and signal.
    func seriesPatches(_ v: MeasureView) -> [SeriesPatch] {
        switch v {
        case .nearBlack, .nearWhite:
            return (0..<seriesCount(v)).map { i in
                let level = seriesLevel(v, i)
                return SeriesPatch(name: Reference.label(level), signal: Array(repeating: Reference.grayProp(level), count: 3))
            }
        case .colorChecker:
            return ccPatches
        case .freeMeasures:
            return freeMeasurements.indices.map { SeriesPatch(name: "\($0 + 1)", signal: [0, 0, 0]) }
        default:
            guard let color = v.saturationColor else { return [] }
            let n = saturationCount
            return ref.saturationSignals(color, steps: n).enumerated().map { i, s in
                SeriesPatch(name: "\(i * 100 / (n - 1))", signal: s)
            }
        }
    }

    /// Pattern shown (or asked for) to measure a column.
    func seriesPattern(_ v: MeasureView, _ i: Int) -> TestPattern? {
        switch v {
        case .nearBlack, .nearWhite: return .gray(seriesLevel(v, i))
        case .freeMeasures, .grayScale, .primariesSecondaries, .contrast: return nil
        default:
            let p = seriesPatches(v)
            guard i < p.count else { return nil }
            let codes = p[i].signal.map { VideoLevels.video.code($0) }
            let what = v == .colorChecker ? "Color Checker \"\(p[i].name)\"" : "\(v.saturationColor?.rawValue ?? "") saturation \(p[i].name)%"
            return .custom(p[i].signal, "\(what) (R,G,B video 16-235: \(codes[0]),\(codes[1]),\(codes[2]))")
        }
    }

    // MARK: - Results

    /// White for the target curve of the color references: the gray scale 100%, else Target MaxL.
    private var curveWhiteY: Double { whiteY ?? prefs.targetMaxL }

    func seriesResults(_ v: MeasureView) -> [SeriesResult] {
        let data = seriesMeasurements[v] ?? [:]
        let r = ref
        switch v {
        case .nearBlack, .nearWhite:
            // Near black targets use its own 0% as black (HCFR: GetNearBlack(0)), or the manual black
            let black: Double? = v == .nearBlack && !overrideBlack ? (data[0]?.Y ?? targetBlackY) : targetBlackY
            return seriesPatches(v).enumerated().map { i, p in
                let level = seriesLevel(v, i)
                let overridden = v == .nearBlack && i == 0 && overrideBlack
                return SeriesResult(grayIndex: i, name: p.name, signal: p.signal[0], xyz: overridden ? nil : data[i],
                                    baseY: grayBaseY,
                                    targetY: ColorMath.targetY(level: level, whiteY: grayBaseY, blackY: black, ref: r),
                                    showDeltaE: !(v == .nearBlack && i == 0), ref: r)
            }
        case .freeMeasures:
            return freeMeasurements.enumerated().map { i, xyz in
                SeriesResult(index: i, name: "\(i + 1)", signal: [0, 0, 0], xyz: xyz, reference: nil, whiteY: grayBaseY, ref: r)
            }
        case .colorChecker:
            return ccPatches.enumerated().map { i, p in
                SeriesResult(index: i, name: p.name, signal: p.signal, xyz: data[i],
                             reference: r.patternReference(signal: p.signal, whiteY: curveWhiteY, blackY: targetBlackY),
                             whiteY: colorWhiteY, ref: r)
            }
        case .grayScale, .primariesSecondaries, .contrast:
            return []
        default:
            guard let color = v.saturationColor else { return [] }
            let n = saturationCount
            return seriesPatches(v).enumerated().map { i, p in
                SeriesResult(index: i, name: p.name, signal: p.signal, xyz: data[i],
                             reference: r.saturationReference(color, ratio: Double(i) / Double(n - 1),
                                                              whiteY: curveWhiteY, blackY: targetBlackY),
                             whiteY: colorWhiteY, ref: r)
            }
        }
    }

    /// Contrast view columns: Black, White, ANSI 1, ANSI 2 (no reference).
    var contrastResults: [SeriesResult] {
        ContrastPatch.allCases.enumerated().map { i, p in
            var xyz = contrastMeasurements[p]
            if p == .black && overrideBlack { xyz = prefs.manualBlack > 0 ? ref.white.xyz(Y: prefs.manualBlack) : nil }
            let s: Double = p == .white ? 1 : 0
            return SeriesResult(index: i, name: p.rawValue, signal: [s, s, s], xyz: xyz, reference: nil,
                                whiteY: contrastMeasurements[.white]?.Y ?? grayBaseY, ref: ref)
        }
    }

    /// HCFR's GetOnOffContrast: white / black; infinite with a perfect (0) black, nil if not measured.
    var onOffContrast: Double? {
        guard let w = contrastMeasurements[.white]?.Y else { return nil }
        let b = overrideBlack ? prefs.manualBlack : contrastMeasurements[.black]?.Y
        guard let b else { return nil }
        return b > 0 ? w / b : .infinity
    }

    var ansiContrast: Double? {
        guard let b = contrastMeasurements[.ansi1]?.Y, let w = contrastMeasurements[.ansi2]?.Y else { return nil }
        return b > 0.000001 ? w / b : .infinity
    }

    /// Number of measured columns of the current view (info line).
    var measureCount: Int {
        switch view {
        case .grayScale: return measurements.filter { $0.key > 0 || !overrideBlack }.count
        case .primariesSecondaries: return colorMeasurements.count
        case .contrast: return contrastMeasurements.count
        case .freeMeasures: return freeMeasurements.count
        default: return seriesMeasurements[view]?.count ?? 0
        }
    }

    // MARK: - Selection and sizes

    func select(index: Int) {
        guard activity != .measuring, index >= 0, index < columnCount(view) else { return }
        if view == .nearBlack && index == 0 && overrideBlack { return }
        selectedIndex = index
    }

    /// HCFR's Scale sizes for near black, near white and saturations. Measurements taken with
    /// another size are cleared, asking first.
    func setSeriesCount(_ v: MeasureView, _ n: Int) {
        guard activity == .idle, n != seriesCount(v), n >= 2 else { return }
        let affected: [MeasureView] = v.saturationColor != nil ? MeasureView.saturations : [v]
        guard confirmClear(affected, what: "the number of points") else { return }
        affected.forEach { seriesMeasurements[$0] = nil }
        switch v {
        case .nearBlack: nearBlackCount = n; defaults.set(n, forKey: "nearBlackCount")
        case .nearWhite: nearWhiteCount = n; defaults.set(n, forKey: "nearWhiteCount")
        default: saturationCount = n; defaults.set(n, forKey: "saturationCount")
        }
        if selectedIndex >= columnCount(view) { selectedIndex = 0 }
    }

    /// Color Checker pattern set (References → Color Checker Patterns in HCFR).
    func setColorCheckerSet(_ s: ColorCheckerSet) {
        guard activity == .idle, s != ccSet else { return }
        if s == .user && userCCRows.isEmpty {
            loadUserColorChecker()
            return
        }
        guard confirmClear([.colorChecker], what: "the pattern set") else { return }
        seriesMeasurements[.colorChecker] = nil
        applyColorCheckerSet(s)
    }

    func applyColorCheckerSet(_ s: ColorCheckerSet) {
        ccSet = s
        defaults.set(s.rawValue, forKey: "ccSet")
        if selectedIndex >= columnCount(view) { selectedIndex = 0 }
    }

    /// "User defined": a CSV file in HCFR's format (R,G,B,name per line, 8-bit video codes 16-235).
    func loadUserColorChecker() {
        let panel = NSOpenPanel()
        panel.title = "Color Checker patterns (CSV: R,G,B,name per line, video levels 16-235)"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url,
              let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return }
        let rows = ColorCheckerSet.readCSV(text)
        guard !rows.isEmpty else {
            errorMessage = "No patterns found in \(url.lastPathComponent). Each line must be R,G,B,name with video levels (16-235), as HCFR's usercolors.csv."
            return
        }
        guard confirmClear([.colorChecker], what: "the pattern set") else { return }
        seriesMeasurements[.colorChecker] = nil
        setUserColorChecker(rows, name: url.deletingPathExtension().lastPathComponent)
        applyColorCheckerSet(.user)
    }

    func setUserColorChecker(_ rows: [ColorCheckerData.Row], name: String) {
        userCCRows = rows
        userCCName = name
        defaults.set(rows.map { "\($0.r),\($0.g),\($0.b),\($0.name)" }.joined(separator: "\n"), forKey: "userCCData")
        defaults.set(name, forKey: "userCCName")
    }

    func applySeriesSizes(nearBlack: Int?, nearWhite: Int?, saturation: Int?) {
        if let n = nearBlack, n >= 2 { nearBlackCount = n; defaults.set(n, forKey: "nearBlackCount") }
        if let n = nearWhite, n >= 2 { nearWhiteCount = n; defaults.set(n, forKey: "nearWhiteCount") }
        if let n = saturation, n >= 2 { saturationCount = n; defaults.set(n, forKey: "saturationCount") }
    }

    private func confirmClear(_ views: [MeasureView], what: String) -> Bool {
        guard views.contains(where: { !(seriesMeasurements[$0]?.isEmpty ?? true) }) else { return true }
        let alert = NSAlert()
        alert.messageText = "Clear the measurements?"
        alert.informativeText = "Changing \(what) clears the \(views.count > 1 ? "saturation" : views[0].rawValue.lowercased()) measurements."
        alert.addButton(withTitle: "Change and clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        isDirty = true
        return true
    }

    // MARK: - Measuring

    /// Near black, near white, saturations and Color Checker (HCFR's Measure…Scale).
    func measureSeries(_ kind: MeasureKind) {
        let views = kind.seriesViews
        let total = views.reduce(0) { $0 + seriesCount($1) - ($1 == .nearBlack && overrideBlack ? 1 : 0) }
        view = views[0]
        run(.measuring) {
            try await self.confirmRun("""
                Run \(kind.title.lowercased()) measures on \(total) values\(kind == .colorChecker ? " (\(self.ccSet.title))" : "")?
                Warning: current data will be lost.

                Note: you can cancel measuring using the ESC key.
                """)
            self.isDirty = true
            for v in views {
                self.view = v
                self.seriesMeasurements[v] = [:]
                let first = v == .nearBlack && self.overrideBlack ? 1 : 0
                for i in first..<self.seriesCount(v) {
                    try Task.checkCancellation()
                    guard let pattern = self.seriesPattern(v, i) else { continue }
                    self.selectedIndex = i
                    try await self.present(pattern)
                    self.status = "Measuring \(v.rawValue.lowercased()): \(self.seriesPatches(v)[i].name) (\(i + 1) of \(self.seriesCount(v)))…"
                    let xyz = try await self.readWithCalibration(pattern: pattern)
                    self.seriesMeasurements[v, default: [:]][i] = xyz
                    self.lastMeasure = Date()
                }
            }
            self.selectedIndex = 0
            self.status = "\(kind.title) measurement finished"
            Chime.finished()
        }
    }

    func contrastPattern(_ p: ContrastPatch) -> TestPattern {
        switch p {
        case .black: return .gray(0)
        case .white: return .gray(100)
        case .ansi1: return .ansi(inverted: false)
        case .ansi2: return .ansi(inverted: true)
        }
    }

    /// HCFR's MeasureContrast: black (unless Override black), white, then the two ANSI checkerboards
    /// read at the center (black square, then white square).
    func measureContrast() {
        view = .contrast
        let items = ContrastPatch.allCases.filter { $0 != .black || !overrideBlack }
        run(.measuring) {
            try await self.confirmRun("""
                Run contrast measures (\(items.map(\.rawValue).joined(separator: ", ")))?
                Warning: current data will be lost.

                For ANSI contrast the meter reads the center square of a 5×5 checkerboard: keep it in the center of the screen.
                Note: you can cancel measuring using the ESC key.
                """)
            self.isDirty = true
            self.contrastMeasurements.removeAll()
            for item in items {
                try Task.checkCancellation()
                self.selectedIndex = ContrastPatch.allCases.firstIndex(of: item) ?? 0
                let pattern = self.contrastPattern(item)
                try await self.present(pattern)
                self.status = "Measuring \(item.rawValue)…"
                self.contrastMeasurements[item] = try await self.readWithCalibration(pattern: pattern)
                self.lastMeasure = Date()
            }
            // As HCFR: if the "black" ANSI reading is brighter, the checkerboard was the other way round
            if let b = self.contrastMeasurements[.ansi1], let w = self.contrastMeasurements[.ansi2], b.Y > w.Y {
                self.contrastMeasurements[.ansi1] = w
                self.contrastMeasurements[.ansi2] = b
            }
            self.status = "Contrast measurement finished"
            Chime.finished()
        }
    }

    /// Free measure: one reading of whatever is on screen, added to the Free measures view.
    func measureFree() {
        view = .freeMeasures
        run(.measuring) {
            self.closePattern()
            self.status = "Free measure: reading the screen as it is…"
            self.freeMeasurements.append(try await self.readWithCalibration(pattern: nil))
            self.selectedIndex = self.freeMeasurements.count - 1
            self.lastMeasure = Date()
            self.isDirty = true
            self.status = "Free measure \(self.freeMeasurements.count) added"
        }
    }

    /// One reading of Start in the series, contrast and free views.
    func continuousStep() async throws {
        let v = view, i = selectedIndex
        if v == .freeMeasures {
            status = "Continuous free measures — each reading is added; Stop to finish"
            let xyz = try await readWithCalibration(pattern: nil)
            if view == .freeMeasures {
                freeMeasurements.append(xyz)
                selectedIndex = freeMeasurements.count - 1
                lastMeasure = Date(); isDirty = true
            }
            return
        }
        let pattern: TestPattern?
        let name: String
        if v == .contrast {
            let item = ContrastPatch.allCases[min(i, 3)]
            pattern = contrastPattern(item); name = item.rawValue
        } else {
            pattern = seriesPattern(v, i); name = seriesPatches(v)[safe: i]?.name ?? ""
        }
        guard let pattern else { try await Task.sleep(for: .seconds(0.5)); return }
        status = "Continuous reading of \(v.rawValue.lowercased()) \(name) — click another column to measure it, Stop to finish"
        try await showIfGenerator(pattern)
        let xyz = try await readWithCalibration(pattern: pattern)
        // A reading taken while the column changed belongs to the previous pattern: drop it
        guard view == v, selectedIndex == i else { return }
        if v == .contrast {
            contrastMeasurements[ContrastPatch.allCases[min(i, 3)]] = xyz
        } else {
            seriesMeasurements[v, default: [:]][i] = xyz
        }
        lastMeasure = Date(); isDirty = true
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
