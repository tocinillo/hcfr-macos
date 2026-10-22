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
/// The reference project set with File → Set as Reference Project, for the windows opened later.
enum ProjectReference {
    @MainActor static var current: (ReferenceData, Session)?
}

struct ReferenceData {
    var name: String

    func renamed(_ n: String) -> ReferenceData { var c = self; c.name = n; return c }
    var gray: [Double: XYZ] = [:]
    var colors: [PatchColor: XYZ] = [:]
    var series: [MeasureView: [Int: XYZ]] = [:]
    var grayCount = Reference.defaultGrayCount

    var whiteY: Double { gray[100]?.Y ?? colors[.white]?.Y ?? baseWhiteY }
    var colorWhiteY: Double { colors[.white]?.Y ?? gray[100]?.Y ?? baseWhiteY }

    static func load(_ url: URL) throws -> ReferenceData {
        let file = try Session.readProjectFile(url)
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
        panel.allowedContentTypes = [.hcfrProject, .hcfrWindows, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            refData = try ReferenceData.load(url)
            status = "Comparing with \(url.lastPathComponent): rows dE / ref and xy / ref"
        } catch {
            errorMessage = "Could not open \(url.lastPathComponent). It is not an HCFR Colorimeter project."
        }
    }

    // MARK: - Reference project (HCFR for Windows: "Set as reference" on an open document)

    /// File → "Set as Reference Project": the measures of the window in front become the
    /// reference of every other open project window (and of the ones opened later), which show
    /// the dE / ref and xy / ref rows against it, as with Compare with Project.
    func setAsReferenceProject() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HCFR reference \(UUID().uuidString).hcfrex")
        saveProject(copyTo: url)
        defer { try? FileManager.default.removeItem(at: url) }
        guard var d = try? ReferenceData.load(url) else {
            errorMessage = "The reference project could not be read."
            return
        }
        d = d.renamed(projectName)
        ProjectReference.current = (d, self)
        isReferenceProject = true
        for s in Session.open where s !== self {
            s.isReferenceProject = false
            s.refData = d
            s.status = "Comparing with \(projectName): rows dE / ref and xy / ref"
        }
        status = "Reference project: \(projectName)"
    }

    /// File → "Clear Reference Project".
    func clearReferenceProject() {
        guard let (d, _) = ProjectReference.current else { return }
        ProjectReference.current = nil
        for s in Session.open {
            s.isReferenceProject = false
            if s.refData?.name == d.name { s.refData = nil }
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

/// HCFR's "Build manually using reference colorimeter": the x, y, Y that a reference meter read on
/// red, green, blue and white, typed by hand.
final class ManualReference: ObservableObject {
    @Published var values: [[Double]] = [[0.640, 0.330, 25.5], [0.300, 0.600, 85.9], [0.150, 0.060, 8.7], [0.3127, 0.3290, 120]]
}

extension Session {
    /// Matrix from this meter's red, green, blue and white (Measure → Primary colors) and the
    /// reference values typed in `manualReference`.
    func computeSensorMatrixFromManual() {
        let rgb: [PatchColor] = [.red, .green, .blue]
        let mine = rgb.compactMap { colorMeasurements[$0] }
        guard mine.count == 3 else {
            errorMessage = "Measure red, green and blue with this meter first (Measure → Primary colors), on the same patches the reference meter read."
            return
        }
        let v = manualReference.values
        let theirs = (0..<3).map { XYZ.fromxyY(x: v[$0][0], y: v[$0][1], Y: v[$0][2]) }
        let wr = v[3][2] > 0 ? XYZ.fromxyY(x: v[3][0], y: v[3][1], Y: v[3][2]) : nil
        let wm = colorMeasurements[.white] ?? measurements[100]
        guard let t = SensorMatrix.compute(measures: mine, references: theirs, whiteMeasure: wm, whiteReference: wr,
                                           onlyPrimaries: appPrefs.matrixOnlyPrimaries || wr == nil) else {
            errorMessage = "The matrix could not be computed (the values are not independent)."
            return
        }
        let old = appPrefs.sensorMatrix.count == 9 ? Mat3(m: [Array(appPrefs.sensorMatrix[0..<3]), Array(appPrefs.sensorMatrix[3..<6]), Array(appPrefs.sensorMatrix[6..<9])])
                                                   : Mat3.diagonal([1, 1, 1])
        appPrefs.sensorMatrix = (t * old).m.flatMap { $0 }
        status = "Sensor matrix computed from the reference values typed by hand. It applies to the next readings: measure again."
    }
}

// MARK: - Meter correction files (HCFR: Advanced → Meter Correction file)

enum MeterCorrectionFile {
    /// Argyll CCMX (CGATS text, the 3×3 matrix by rows) or HCFR .thc (MFC archive whose first object is
    /// the sensor matrix, stored by columns).
    static func read(_ data: Data) -> [Double]? {
        if data.count >= 92, data.prefix(8) == Data("taMCCxir".utf8) {
            let ints = (0..<3).map { i in data.subdata(in: (8 + 4 * i)..<(12 + 4 * i)).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) } }
            guard ints[1] == 3, ints[2] == 3 else { return nil }
            let v = (0..<9).map { i in data.subdata(in: (20 + 8 * i)..<(28 + 8 * i)).withUnsafeBytes { $0.loadUnaligned(as: Double.self) } }
            // column-major -> row-major
            return [v[0], v[3], v[6], v[1], v[4], v[7], v[2], v[5], v[8]]
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let b = text.range(of: "BEGIN_DATA\n") ?? text.range(of: "BEGIN_DATA\r\n") ?? text.range(of: "BEGIN_DATA"),
              let e = text.range(of: "END_DATA", range: b.upperBound..<text.endIndex) else { return nil }
        let nums = text[b.upperBound..<e.lowerBound].split(whereSeparator: { $0.isWhitespace }).compactMap { Double($0) }
        return nums.count >= 9 ? Array(nums.prefix(9)) : nil
    }

    static func ccmx(_ m: [Double], meter: String, display: String) -> String {
        let row = { (r: Int) in (0..<3).map { String(format: "%.10f", m[r * 3 + $0]) }.joined(separator: " ") }
        let f = DateFormatter()
        f.dateFormat = "EEE MMM dd HH:mm:ss yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return """
            CCMX

            DESCRIPTOR "\(display.isEmpty ? "Meter correction" : display)"
            ORIGINATOR "HCFR Colorimeter for macOS"
            CREATED "\(f.string(from: Date()))"
            KEYWORD "INSTRUMENT"
            INSTRUMENT "\(meter)"
            KEYWORD "DISPLAY"
            DISPLAY "\(display)"
            KEYWORD "COLOR_REP"
            COLOR_REP "XYZ"

            NUMBER_OF_FIELDS 3
            BEGIN_DATA_FORMAT
            XYZ_X XYZ_Y XYZ_Z
            END_DATA_FORMAT

            NUMBER_OF_SETS 3
            BEGIN_DATA
            \(row(0))
            \(row(1))
            \(row(2))
            END_DATA

            """
    }
}

extension Session {
    func loadMeterCorrectionFile() {
        let panel = NSOpenPanel()
        panel.title = "Load meter correction file (Argyll .ccmx or HCFR .thc)"
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        guard let m = MeterCorrectionFile.read(data) else {
            errorMessage = "\(url.lastPathComponent) is not a meter correction file (.ccmx or .thc with a 3×3 matrix)."
            return
        }
        appPrefs.sensorMatrix = m
        status = "Meter correction loaded: \(url.lastPathComponent). It applies to the next readings."
    }

    func saveMeterCorrectionFile() {
        let panel = NSSavePanel()
        panel.title = "Save meter correction file"
        panel.nameFieldStringValue = (correction?.name ?? "Meter correction") + ".ccmx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MeterCorrectionFile.ccmx(appPrefs.sensorMatrix, meter: meter?.name ?? "", display: correction?.name ?? "")
                .write(to: url, atomically: true, encoding: .utf8)
            status = "Meter correction saved: \(url.lastPathComponent)"
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}
