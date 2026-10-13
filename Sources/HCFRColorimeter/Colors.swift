// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.
//
// Primaries/secondaries formulas and measurement order follow HCFR (Views/MainView.cpp,
// Measure.cpp), Copyright (c) Association Homecinema Francophone and HCFR contributors, GNU GPL.

import Foundation

/// Base white luminance used until 100% white is measured (HCFR shows 120 cd/m² in an empty project).
let baseWhiteY = 120.0

/// Color patches of HCFR's primaries / secondaries measurement (100% saturation and level).
enum PatchColor: String, CaseIterable, Identifiable, Codable {
    case red = "Red", green = "Green", blue = "Blue"
    case yellow = "Yellow", cyan = "Cyan", magenta = "Magenta"
    case white = "White"

    var id: String { rawValue }

    /// Linear RGB of the patch (1 = 100%).
    var rgb: [Double] {
        switch self {
        case .red: return [1, 0, 0]
        case .green: return [0, 1, 0]
        case .blue: return [0, 0, 1]
        case .yellow: return [1, 1, 0]
        case .cyan: return [0, 1, 1]
        case .magenta: return [1, 0, 1]
        case .white: return [1, 1, 1]
        }
    }
}

/// What the Measure button can run (HCFR's Measures menu).
enum MeasureKind: Hashable {
    case grayScale, primaries, primariesSecondaries, grayScaleAndColors
    case nearBlack, nearWhite
    case saturation(MeasureView), allSaturations
    case colorChecker, contrast, freeMeasure

    /// Menu groups, separated by a line.
    static let menu: [[MeasureKind]] = [
        [.grayScale, .nearBlack, .nearWhite],
        [.primaries, .primariesSecondaries, .grayScaleAndColors],
        MeasureView.saturations.map { .saturation($0) } + [.allSaturations],
        [.colorChecker, .contrast, .freeMeasure],
    ]

    var title: String {
        switch self {
        case .grayScale: return "Grey scale"
        case .grayScaleAndColors: return "Grey scale and colors"
        case .primaries: return "Primary colors"
        case .primariesSecondaries: return "Primary and secondary colors"
        case .nearBlack: return "Near black"
        case .nearWhite: return "Near white"
        case .saturation(let v): return "\(v.saturationColor?.rawValue ?? "") saturation"
        case .allSaturations: return "All saturations"
        case .colorChecker: return "Color checker"
        case .contrast: return "Contrast (on/off and ANSI)"
        case .freeMeasure: return "Free measure (one reading of the screen as it is)"
        }
    }

    /// Patches measured, in HCFR's order (plus White, as HCFR's default "BWColorsToAdd = 1").
    var patches: [PatchColor] {
        switch self {
        case .grayScaleAndColors: return [.red, .green, .blue, .yellow, .cyan, .magenta, .white]
        case .primaries: return [.red, .green, .blue, .white]
        case .primariesSecondaries: return [.red, .green, .blue, .yellow, .cyan, .magenta, .white]
        default: return []
        }
    }

    /// Series views measured by this kind.
    var seriesViews: [MeasureView] {
        switch self {
        case .nearBlack: return [.nearBlack]
        case .nearWhite: return [.nearWhite]
        case .saturation(let v): return [v]
        case .allSaturations: return MeasureView.saturations
        case .colorChecker: return [.colorChecker]
        default: return []
        }
    }
}

/// Graph shown in the Information panel (HCFR's graph views).
enum InfoGraph: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case targetCIE = "Target - CIE"
    case luminanceGamma = "Luminance - Gamma"
    case rgbGamma = "RGB - Gamma"
    case rgbLevels = "RGB Levels"
    case colorTemperature = "Color temperature"
    case cie = "CIE Diagram"
    case freeHistogram = "Combined histogram for free measures"
    case nearBlackWhite = "NearBlack - NearWhite"
    case saturationShift = "Saturation Luminance - Shift"
    case targetRGBGamma = "Target - RGB - Gamma"
    /// RGB Levels for the gray scale table, CIE Diagram for the colors table.
    case auto = "Auto"
    var id: String { rawValue }
}

/// Values of the first three table rows (HCFR's display types: xyY, XYZ, RGB, xyz).
enum ValueMode: String, CaseIterable, Identifiable {
    case xyY, XYZ, RGB, xyz
    var id: String { rawValue }

    func label(_ k: Int, _ standard: ColorStandard) -> String {
        switch self {
        case .xyY: return ["x", "y", "Y"][k]
        case .XYZ: return ["X", "Y", "Z"][k]
        case .xyz: return ["x", "y", "z"][k]
        case .RGB:
            let tag: String
            switch standard {
            case .sdtv: tag = "601"
            case .palSecam: tag = "pal"
            case .uhdtvP3: tag = "DCI-P3"
            case .uhdtv2020: tag = "2020"
            case .uhdtvP3in2020: tag = "2020P3"
            case .uhdtv709in2020: tag = "2020R709"
            case .custom: tag = "CUSTOM"
            default: tag = "709"
            }
            return ["R", "G", "B"][k] + tag
        }
    }
}

/// What the "Selected color" panel needs, for a gray level or a color patch.
protocol ColorReading {
    var title: String { get }
    var xyz: XYZ? { get }
    /// RGB Levels bars, in %.
    var bars: [Double]? { get }
    var deltaE: Double? { get }
    var cct: Double? { get }
    var rgb: [Double]? { get }
    var lab: [Double]? { get }
    var lch: [Double]? { get }
    var measureRGB: [Int]? { get }
    var referenceRGB: [Int] { get }
    /// Target diagram: reference chromaticity and the x/y deviation shown at the edge.
    var targetCenter: (x: Double, y: Double) { get }
    var targetRange: Double { get }
}

/// Analysed result for one primary/secondary patch, with HCFR's formulas (MainView.cpp):
/// ΔE CIE2000 against the standard's reference color at its relative luminance, delta xy to the
/// reference chromaticity, and delta L = luminance error relative to the reference luminance.
struct PatchResult: Identifiable, ColorReading {
    let patch: PatchColor
    let xyz: XYZ?
    let reference: XYZ          // relative, white Y = 1
    let deltaE: Double?
    let deltaxy: Double?
    let deltaL: Double?         // fraction (0.023 = +2.3 %)
    let bars: [Double]?
    let rgb: [Double]?
    let cct: Double?
    let lab: [Double]?
    let lch: [Double]?
    let measureRGB: [Int]?
    let referenceRGB: [Int]
    var id: PatchColor { patch }
    var title: String { patch.rawValue }
    var targetCenter: (x: Double, y: Double) { (reference.x, reference.y) }
    var targetRange: Double { patch == .white ? 0.02 : 0.05 }

    init(patch: PatchColor, xyz: XYZ?, whiteY: Double, ref: CalReference) {
        self.patch = patch
        self.xyz = xyz
        let r = ref.rgbToXYZ.apply(patch.rgb)
        reference = XYZ(X: r[0], Y: r[1], Z: r[2])
        referenceRGB = patch.rgb.map { Int($0 * 255) }
        guard let xyz, whiteY > 0 else {
            deltaE = nil; deltaxy = nil; deltaL = nil; bars = nil; rgb = nil
            cct = nil; lab = nil; lch = nil; measureRGB = nil
            return
        }
        let l = ColorMath.lab(xyz, whiteY: whiteY, white: ref.white)
        lab = l
        lch = ColorMath.lch(l)
        deltaE = ColorMath.deltaE(xyz, whiteY: whiteY, reference: reference, refWhiteY: 1, ref: ref, isGray: false)
        deltaxy = hypot(xyz.x - reference.x, xyz.y - reference.y)
        deltaL = reference.Y > 0 ? (xyz.Y / whiteY - reference.Y) / reference.Y : nil
        let lin = ColorMath.rgb(xyz, ref: ref)
        rgb = lin
        bars = lin.map { $0 / whiteY * 100 }
        cct = patch == .white ? ColorMath.cct(xyz) : nil
        measureRGB = ColorMath.displayRGB(xyz, whiteY: whiteY, ref: ref)
    }

    /// "+2.3 %", "-1.0 %" or "=" as HCFR shows delta L.
    var deltaLText: String {
        guard let d = deltaL else { return "" }
        if abs(d) < 0.001 { return "=" }
        return String(format: "%@%.1f %%", d < 0 ? "-" : "+", abs(d) * 100)
    }
}
