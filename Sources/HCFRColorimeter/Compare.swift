// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Reference document comparison added in 2026 after HCFR for Windows' "data reference"
// (MainView.cpp: "dE / ref" and "xy / ref" rows), GNU GPL.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit

/// Measurements of another project, compared column by column with the current ones.
struct ReferenceData {
    let name: String
    var gray: [Double: XYZ] = [:]
    var colors: [PatchColor: XYZ] = [:]
    var series: [MeasureView: [Int: XYZ]] = [:]
    var grayCount = Reference.defaultGrayCount

    var whiteY: Double { gray[100]?.Y ?? colors[.white]?.Y ?? baseWhiteY }
    var colorWhiteY: Double { colors[.white]?.Y ?? gray[100]?.Y ?? baseWhiteY }

    static func load(_ url: URL) throws -> ReferenceData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(ProjectFile.self, from: Data(contentsOf: url))
        guard ProjectFile.acceptedFormats.contains(file.format) else { throw CocoaError(.fileReadCorruptFile) }
        var d = ReferenceData(name: url.deletingPathExtension().lastPathComponent)
        d.grayCount = file.grayCount ?? Reference.defaultGrayCount
        for (k, v) in file.measurements where v.count == 3 {
            if let l = Double(k) { d.gray[l] = XYZ(X: v[0], Y: v[1], Z: v[2]) }
        }
        for (k, v) in file.colors ?? [:] where v.count == 3 {
            if let p = PatchColor(rawValue: k) { d.colors[p] = XYZ(X: v[0], Y: v[1], Z: v[2]) }
        }
        for (name, cols) in file.series ?? [:] {
            guard let view = MeasureView(rawValue: name) else { continue }
            for (k, v) in cols where v.count == 3 {
                if let i = Int(k) { d.series[view, default: [:]][i] = XYZ(X: v[0], Y: v[1], Z: v[2]) }
            }
        }
        for (i, v) in (file.freeMeasures ?? []).enumerated() where v.count == 3 {
            d.series[.freeMeasures, default: [:]][i] = XYZ(X: v[0], Y: v[1], Z: v[2])
        }
        return d
    }

    func grayXYZ(_ level: Double) -> XYZ? {
        gray.first { abs($0.key - level) < 1e-6 }?.value
    }
}

/// "dE / ref" and "xy / ref" of a column.
struct RefComparison {
    let deltaE: Double?
    let deltaxy: Double?

    static let none = RefComparison(deltaE: nil, deltaxy: nil)

    init(deltaE: Double?, deltaxy: Double?) {
        self.deltaE = deltaE
        self.deltaxy = deltaxy
    }

    /// HCFR's GetDeltaE(YWhite, refDocColor, YWhiteRefDoc, …): both measures relative to their own white.
    init(_ c: XYZ?, whiteY: Double, refXYZ: XYZ?, refWhiteY: Double, isGray: Bool, ref: CalReference) {
        guard let c, let r = refXYZ, c.Y > 0, r.Y > 0, whiteY > 0, refWhiteY > 0 else {
            deltaE = nil; deltaxy = nil
            return
        }
        deltaE = ColorMath.deltaE(c, whiteY: whiteY, reference: r.scaled(1 / refWhiteY), refWhiteY: 1, ref: ref, isGray: isGray)
        deltaxy = hypot(c.x - r.x, c.y - r.y)
    }
}

extension Session {
    /// File → "Compare with project…" (HCFR's data reference).
    func chooseReferenceProject() {
        let panel = NSOpenPanel()
        panel.title = "Compare with project"
        panel.allowedContentTypes = [.hcfrProject, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            refData = try ReferenceData.load(url)
            status = "Comparing with \(url.lastPathComponent): rows dE / ref and xy / ref"
        } catch {
            errorMessage = "Could not open \(url.lastPathComponent). It is not an HCFR Colorimeter project."
        }
    }

    func grayComparison(_ r: StepResult) -> RefComparison {
        guard let d = refData else { return .none }
        return RefComparison(r.xyz, whiteY: grayBaseY, refXYZ: d.grayXYZ(r.level), refWhiteY: d.whiteY, isGray: true, ref: ref)
    }

    func colorComparison(_ r: PatchResult) -> RefComparison {
        guard let d = refData else { return .none }
        return RefComparison(r.xyz, whiteY: colorWhiteY, refXYZ: d.colors[r.patch] ?? (r.patch == .white ? d.grayXYZ(100) : nil),
                             refWhiteY: d.colorWhiteY, isGray: false, ref: ref)
    }

    func seriesComparison(_ v: MeasureView, _ r: SeriesResult) -> RefComparison {
        guard let d = refData else { return .none }
        let gray = v.isGraySeries || v == .freeMeasures
        return RefComparison(r.xyz, whiteY: gray ? grayBaseY : colorWhiteY, refXYZ: d.series[v]?[r.index],
                             refWhiteY: gray ? d.whiteY : d.colorWhiteY, isGray: gray, ref: ref)
    }
}

// MARK: - Sensor matrix from a reference meter (HCFR's ComputeConversionMatrix, libHCFR/Color.cpp)

extension Mat3 {
    static func * (a: Mat3, b: Mat3) -> Mat3 {
        Mat3(m: (0..<3).map { r in (0..<3).map { c in (0..<3).reduce(0) { $0 + a.m[r][$1] * b.m[$1][c] } } })
    }

    static func diagonal(_ d: [Double]) -> Mat3 { Mat3(m: [[d[0], 0, 0], [0, d[1], 0], [0, 0, d[2]]]) }

    var determinant: Double {
        let a = m
        return a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
            + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
    }
}

enum SensorMatrix {
    /// Matrix taking this meter's readings of red, green, blue (and white) to the reference meter's.
    /// With white (HCFR default): the four-color method (white gains on chromaticities, then the
    /// white luminance matched); without: references × measures⁻¹.
    static func compute(measures: [XYZ], references: [XYZ], whiteMeasure: XYZ?, whiteReference: XYZ?,
                        onlyPrimaries: Bool) -> Mat3? {
        func cols(_ v: [XYZ]) -> Mat3 { Mat3.columns([v[0].X, v[0].Y, v[0].Z], [v[1].X, v[1].Y, v[1].Z], [v[2].X, v[2].Y, v[2].Z]) }
        func chroma(_ v: [XYZ]) -> Mat3 { Mat3.columns([v[0].x, v[0].y, v[0].z], [v[1].x, v[1].y, v[1].z], [v[2].x, v[2].y, v[2].z]) }
        guard measures.count == 3, references.count == 3 else { return nil }
        guard !onlyPrimaries, let wm = whiteMeasure, let wr = whiteReference, wm.Y > 0, wr.Y > 0 else {
            let m = cols(measures)
            guard abs(m.determinant) > 1e-12 else { return nil }
            return cols(references) * m.inverse
        }
        let mx = chroma(measures), rx = chroma(references)
        guard abs(mx.determinant) > 1e-12, abs(rx.determinant) > 1e-12 else { return nil }
        let kr = Mat3.diagonal(rx.inverse.apply([wr.x, wr.y, wr.z]))
        let km = Mat3.diagonal(mx.inverse.apply([wm.x, wm.y, wm.z]))
        let n = rx * kr, mm = mx * km
        guard abs(mm.determinant) > 1e-12 else { return nil }
        var t = n * mm.inverse
        let test = t.apply([wm.X, wm.Y, wm.Z])
        guard test[1] != 0 else { return nil }
        let k = wr.Y / test[1]
        t.m = t.m.map { $0.map { $0 * k } }
        return t
    }
}

extension Session {
    /// Sensor → "Compute from the compared project": this meter's red, green, blue and white against the
    /// same patches measured with a reference meter (a spectro) in the compared project.
    func computeSensorMatrixFromReference() {
        guard let d = refData else { errorMessage = "Open the reference meter's project first (File → Compare with Project…)."; return }
        let rgb: [PatchColor] = [.red, .green, .blue]
        let mine = rgb.compactMap { colorMeasurements[$0] }, theirs = rgb.compactMap { d.colors[$0] }
        guard mine.count == 3, theirs.count == 3 else {
            errorMessage = "Both projects need red, green and blue measured (Measure → Primary colors), on the same display and patterns."
            return
        }
        let wm = colorMeasurements[.white] ?? measurements[100], wr = d.colors[.white] ?? d.grayXYZ(100)
        guard let t = SensorMatrix.compute(measures: mine, references: theirs, whiteMeasure: wm, whiteReference: wr,
                                           onlyPrimaries: appPrefs.matrixOnlyPrimaries) else {
            errorMessage = "The matrix could not be computed (the measures are not independent)."
            return
        }
        // These readings already went through the current matrix: chain them
        let old = appPrefs.sensorMatrix.count == 9 ? Mat3(m: [Array(appPrefs.sensorMatrix[0..<3]), Array(appPrefs.sensorMatrix[3..<6]), Array(appPrefs.sensorMatrix[6..<9])])
                                                   : Mat3.diagonal([1, 1, 1])
        let total = t * old
        appPrefs.sensorMatrix = total.m.flatMap { $0 }
        status = "Sensor matrix computed against \(d.name). It applies to the next readings: measure again."
    }
}
