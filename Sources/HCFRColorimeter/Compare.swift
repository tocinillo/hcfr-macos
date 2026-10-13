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
