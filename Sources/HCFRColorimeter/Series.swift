// HCFR for macOS
// Copyright (C) 2026 Jorge Velázquez
// View modes added in 2026 after HCFR for Windows (Views/MainView.cpp display modes, Measure.cpp
// MeasureNearBlackScale / MeasureNearWhiteScale / Measure…SatScale / MeasureCC24SatScale /
// MeasureContrast, GetRefSat, GetRefCC24Sat; libHCFR/Color.cpp GenerateSaturationColors,
// GenerateCC24Colors), Copyright (c) Association Homecinema Francophone and HCFR contributors, GNU GPL.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import Foundation

/// Table shown in the main grid: HCFR's "View" selector, in HCFR's order.
enum MeasureView: String, CaseIterable, Identifiable {
    case grayScale = "Gray scale"
    case primariesSecondaries = "Primaries and secondaries"
    case freeMeasures = "Free measures"
    case nearBlack = "Near black scale"
    case nearWhite = "Near white scale"
    case redSat = "Red saturation scale"
    case greenSat = "Green saturation scale"
    case blueSat = "Blue saturation scale"
    case yellowSat = "Yellow saturation scale"
    case cyanSat = "Cyan saturation scale"
    case magentaSat = "Magenta saturation scale"
    case colorChecker = "Color Checker"
    case contrast = "Contrast"

    var id: String { rawValue }

    static let saturations: [MeasureView] = [.redSat, .greenSat, .blueSat, .yellowSat, .cyanSat, .magentaSat]

    /// Color of a saturation scale.
    var saturationColor: PatchColor? {
        switch self {
        case .redSat: return .red
        case .greenSat: return .green
        case .blueSat: return .blue
        case .yellowSat: return .yellow
        case .cyanSat: return .cyan
        case .magentaSat: return .magenta
        default: return nil
        }
    }

    /// Near black / near white: gray levels with a luminance target.
    var isGraySeries: Bool { self == .nearBlack || self == .nearWhite }

    /// Views shown with the generic patch table.
    var isSeries: Bool {
        switch self {
        case .grayScale, .primariesSecondaries, .contrast: return false
        default: return true
        }
    }

    /// First column header (HCFR: "% White", "% Sat", "Color Checker"…).
    var columnTitle: String {
        switch self {
        case .freeMeasures, .nearBlack, .nearWhite: return "% White"
        case .colorChecker: return "Color Checker"
        case .contrast: return ""
        default: return saturationColor != nil ? "% Sat" : ""
        }
    }
}

/// HCFR's Color Checker pattern sets ("Color Checker Patterns" of the References preferences).
/// Raw values are HCFR's CCPatterns numbers. The HDR sets (BT2020HDR, LG HDR10 targets) hold PQ
/// signals; HCFR's 2016/2017 LG base tone curve tables are not included.
enum ColorCheckerSet: Int, CaseIterable, Identifiable, Codable {
    case gcd = 0, mcd = 1, pantoneSkin = 2, calmanClassic = 3, calmanSGSkin = 4, chromaPureSkin = 5
    case calmanSG = 6, axis = 7
    case cm4Lum = 8, cm5Lum = 9, cm10Lum = 10
    case cm4Sat = 11, cm4Sat75 = 12, cm5Sat = 13, cm5Sat75 = 14, cm10Sat = 15, cm10Sat75 = 16
    case cm6NearBlack = 17, cmDynamicRange = 18
    case mascior50 = 19, lg540_2016 = 20, lg540_2017 = 21, lg1000_2017 = 22, lg4000_2017 = 23, lgUK65xx = 24, lgOLED2018V1 = 25, lgOLED2018V2 = 26, lgOLED2018V3 = 27
    case lgOLED2019_10 = 28, lgOLED2019_22 = 29, lgOLED2020_10 = 30, lgOLED2020_22 = 31, lgOLED2021_10 = 32, lgOLED2021_22 = 33
    case random250 = 34, random500 = 35, user = 36

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .gcd: return "GCD classic"
        case .mcd: return "MCD classic"
        case .pantoneSkin: return "Pantone skin tones"
        case .calmanClassic: return "CalMAN Classic"
        case .calmanSGSkin: return "CalMAN SG skin tones"
        case .chromaPureSkin: return "ChromaPure skin tones"
        case .calmanSG: return "CalMAN SG"
        case .axis: return "RGB Luminance Axis"
        case .cm4Lum: return "CM 4-Point Luminance"
        case .cm5Lum: return "CM 5-Point Luminance"
        case .cm10Lum: return "CM 10-Point Luminance"
        case .cm4Sat: return "CM 4-Point Saturation (100AMP)"
        case .cm4Sat75: return "CM 4-Point Saturation (75AMP)"
        case .cm5Sat: return "CM 5-Point Saturation (100AMP)"
        case .cm5Sat75: return "CM 5-Point Saturation (75AMP)"
        case .cm10Sat: return "CM 10-Point Saturation (100AMP)"
        case .cm10Sat75: return "CM 10-Point Saturation (75AMP)"
        case .cm6NearBlack: return "CM 6-Point Near Black"
        case .cmDynamicRange: return "CM Dynamic Range (Clipping)"
        case .mascior50: return "BT2020HDR_50_50"
        case .lg540_2016: return "LG_540_2016"
        case .lg540_2017: return "LG_540_2017"
        case .lg1000_2017: return "LG_1000_2017"
        case .lg4000_2017: return "LG_4000_2017"
        case .lgUK65xx: return "LG UK65xx 20-Point"
        case .lgOLED2018V1: return "LG 2018 OLED V1 20-Point"
        case .lgOLED2018V2: return "LG 2018 OLED V2 20-Point"
        case .lgOLED2018V3: return "LG 2018 OLED V3 20-Point"
        case .lgOLED2019_10: return "LG 2019 OLED 10-Point"
        case .lgOLED2019_22: return "LG 2019 OLED 22-Point"
        case .lgOLED2020_10: return "LG 2020 OLED 10-Point"
        case .lgOLED2020_22: return "LG 2020 OLED 22-Point"
        case .lgOLED2021_10: return "LG 2021 OLED 10-Point"
        case .lgOLED2021_22: return "LG 2021 OLED 22-Point"
        case .random250: return "Random 250"
        case .random500: return "Random 500"
        case .user: return "User defined"
        }
    }

    /// Patches of the set: name and signal (0…1 of the video range). `user` = rows of the user's CSV.
    func patches(user: [ColorCheckerData.Row]) -> [SeriesPatch] {
        func pct(_ rows: [(String, Double, Double, Double)]) -> [SeriesPatch] {
            rows.map { SeriesPatch(name: $0.0, signal: [$0.1 / 100, $0.2 / 100, $0.3 / 100]) }
        }
        func csv(_ rows: [ColorCheckerData.Row]) -> [SeriesPatch] {
            rows.enumerated().map { i, r in
                SeriesPatch(name: r.name.isEmpty ? "\(i + 1)" : r.name,
                            signal: [r.r, r.g, r.b].map { min(max(Double($0 - 16) / 219, 0), 1) })
            }
        }
        switch self {
        case .gcd: return pct(ColorCheckerSets.gcd)
        case .mcd: return pct(ColorCheckerSets.mcd)
        case .pantoneSkin: return pct(ColorCheckerSets.pantoneSkin)
        case .calmanClassic: return pct(ColorCheckerSets.calmanClassic)
        case .calmanSGSkin: return pct(ColorCheckerSets.calmanSGSkin)
        case .chromaPureSkin: return pct(ColorCheckerSets.chromaPureSkin)
        case .calmanSG: return pct(ColorCheckerSets.calmanSG)
        case .axis: return pct(ColorCheckerSets.axis)
        case .cm4Lum: return csv(ColorCheckerData.cm4Lum)
        case .cm5Lum: return csv(ColorCheckerData.cm5Lum)
        case .cm10Lum: return csv(ColorCheckerData.cm10Lum)
        case .cm4Sat: return csv(ColorCheckerData.cm4Sat)
        case .cm4Sat75: return csv(ColorCheckerData.cm4Sat75)
        case .cm5Sat: return csv(ColorCheckerData.cm5Sat)
        case .cm5Sat75: return csv(ColorCheckerData.cm5Sat75)
        case .cm10Sat: return csv(ColorCheckerData.cm10Sat)
        case .cm10Sat75: return csv(ColorCheckerData.cm10Sat75)
        case .cm6NearBlack: return csv(ColorCheckerData.cm6NearBlack)
        case .cmDynamicRange: return csv(ColorCheckerData.cmDynamicRange)
        case .mascior50: return csv(ColorCheckerData.mascior50)
        case .lg540_2016: return csv(ColorCheckerData.lg540_2016)
        case .lg540_2017: return csv(ColorCheckerData.lg540_2017)
        case .lg1000_2017: return csv(ColorCheckerData.lg1000_2017)
        case .lg4000_2017: return csv(ColorCheckerData.lg4000_2017)
        case .lgUK65xx: return csv(ColorCheckerData.lgUK65xx)
        case .lgOLED2018V1: return csv(ColorCheckerData.lgOLED2018V1)
        case .lgOLED2018V2: return csv(ColorCheckerData.lgOLED2018V2)
        case .lgOLED2018V3: return csv(ColorCheckerData.lgOLED2018V3)
        case .lgOLED2019_10: return csv(ColorCheckerData.lgOLED2019_10)
        case .lgOLED2019_22: return csv(ColorCheckerData.lgOLED2019_22)
        case .lgOLED2020_10: return csv(ColorCheckerData.lgOLED2020_10)
        case .lgOLED2020_22: return csv(ColorCheckerData.lgOLED2020_22)
        case .lgOLED2021_10: return csv(ColorCheckerData.lgOLED2021_10)
        case .lgOLED2021_22: return csv(ColorCheckerData.lgOLED2021_22)
        case .random250: return csv(ColorCheckerData.random250)
        case .random500: return csv(ColorCheckerData.random500)
        case .user: return csv(user)
        }
    }

    /// HDR10 sets: PQ signals, targets in nits against the measured peak white (HCFR's MASCIOR50…CCMAXHDR).
    var isHDRSet: Bool { (19...33).contains(rawValue) }

    /// LG base tone curve sets: target of step `i` as a fraction of the peak white (HCFR's Measure.cpp).
    func lgToneTarget(_ i: Int, peak: Double) -> Double? {
        func pq(_ l: [Double]) -> Double { i < l.count ? min(l[i] * 10000 / max(peak, 1e-6), 1) : 1 }
        switch self {
        case .lg540_2016: return i < ColorCheckerData.lg540_2016Levels.count ? ColorCheckerData.lg540_2016Levels[i] : 1
        case .lg540_2017: return pq(ColorCheckerData.lg540_2017Levels)
        case .lg1000_2017: return pq(ColorCheckerData.lg1000_2017Levels)
        case .lg4000_2017: return pq(ColorCheckerData.lg4000_2017Levels)
        default: return nil
        }
    }

    /// HCFR's m_bRecalc: in HDR the signals of these sets are recomputed so they give the same colors.
    var recomputedInHDR: Bool {
        switch self {
        case .gcd, .mcd, .pantoneSkin, .calmanClassic, .calmanSGSkin, .chromaPureSkin, .calmanSG,
             .cm4Sat, .cm4Sat75, .cm5Sat, .cm5Sat75, .cm10Sat, .cm10Sat75: return true
        default: return false
        }
    }

    /// HCFR's constant_XYZ: the classic charts are defined in Rec.709, whatever the reference.
    var rec709Colors: Bool {
        switch self {
        case .gcd, .mcd, .pantoneSkin, .calmanClassic, .calmanSGSkin, .chromaPureSkin, .calmanSG: return true
        default: return false
        }
    }

    /// Reads a pattern file in HCFR's format: one patch per line, "R,G,B,name" with 8-bit video codes.
    static func readCSV(_ text: String) -> [ColorCheckerData.Row] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 3, let r = Int(f[0]), let g = Int(f[1]), let b = Int(f[2]) else { return nil }
            return (r, g, b, f.count > 3 ? f[3] : "")
        }
    }
}

/// One pattern of a series: its name and the signal of each channel (0…1 of the video range).
struct SeriesPatch {
    let name: String
    let signal: [Double]
}

/// The four readings of HCFR's Contrast view.
enum ContrastPatch: String, CaseIterable, Identifiable, Codable {
    case black = "Black", white = "White", ansi1 = "ANSI 1", ansi2 = "ANSI 2"
    var id: String { rawValue }
}

/// Analysed result for one column of a series view (near black / white, saturations, Color
/// Checker, free measures, contrast). `reference` is relative (white Y = 1); nil = no reference.
struct SeriesResult: Identifiable, ColorReading {
    let index: Int
    let name: String
    let xyz: XYZ?
    let reference: XYZ?
    let isGray: Bool
    /// Target luminance (cd/m²): gray series, and the reference Y × white for colors.
    let targetY: Double?
    let deltaE: Double?
    let deltaxy: Double?
    let deltaL: Double?
    let bars: [Double]?
    let rgb: [Double]?
    let cct: Double?
    let lab: [Double]?
    let lch: [Double]?
    let measureRGB: [Int]?
    let referenceRGB: [Int]
    let targetCenter: (x: Double, y: Double)
    var id: Int { index }
    var title: String { name }
    var targetRange: Double { isGray || reference == nil ? 0.02 : 0.05 }

    /// Gray level of near black / near white. `showDeltaE` false for near black 0% (as HCFR).
    init(grayIndex index: Int, name: String, signal: Double, xyz: XYZ?, baseY: Double, targetY: Double,
         showDeltaE: Bool, ref: CalReference) {
        self.index = index
        self.name = name
        self.xyz = xyz
        isGray = true
        reference = ref.white.xyz(Y: 1)
        self.targetY = targetY
        targetCenter = (ref.white.x, ref.white.y)
        let code = Int((signal * 255).rounded())
        referenceRGB = [code, code, code]
        deltaL = nil
        guard let xyz else {
            deltaE = nil; deltaxy = nil; bars = nil; rgb = nil; cct = nil; lab = nil; lch = nil; measureRGB = nil
            return
        }
        deltaE = showDeltaE ? ColorMath.grayDeltaE(xyz, whiteY: baseY, targetY: targetY, ref: ref) : nil
        deltaxy = showDeltaE ? ColorMath.deltaxy(xyz, ref: ref) : nil
        bars = ColorMath.rgbBalance(xyz, ref: ref)
        rgb = ColorMath.rgb(xyz, ref: ref)
        cct = ColorMath.cct(xyz)
        let l = ColorMath.lab(xyz, whiteY: baseY, white: ref.white)
        lab = l
        lch = ColorMath.lch(l)
        measureRGB = ColorMath.displayRGB(xyz, whiteY: baseY, ref: ref)
    }

    /// Color patch (saturations, Color Checker) against its reference, or a free measure / contrast
    /// reading without one.
    init(index: Int, name: String, signal: [Double], xyz: XYZ?, reference: XYZ?, whiteY: Double, ref: CalReference) {
        self.index = index
        self.name = name
        self.xyz = xyz
        self.reference = reference
        isGray = false
        targetY = reference.map { $0.Y * whiteY }
        targetCenter = reference.map { ($0.x, $0.y) } ?? (ref.white.x, ref.white.y)
        referenceRGB = signal.map { Int((min(max($0, 0), 1) * 255).rounded()) }
        guard let xyz else {
            deltaE = nil; deltaxy = nil; deltaL = nil; bars = nil; rgb = nil; cct = nil; lab = nil; lch = nil; measureRGB = nil
            return
        }
        let l = ColorMath.lab(xyz, whiteY: whiteY, white: ref.white)
        lab = l
        lch = ColorMath.lch(l)
        let lin = ColorMath.rgb(xyz, ref: ref)
        rgb = lin
        bars = lin.map { $0 / whiteY * 100 }
        cct = ColorMath.cct(xyz)
        measureRGB = ColorMath.displayRGB(xyz, whiteY: whiteY, ref: ref)
        if let reference, whiteY > 0, xyz.Y > 0 {
            deltaE = ColorMath.deltaE(xyz, whiteY: whiteY, reference: reference, refWhiteY: 1, ref: ref,
                                      isGray: false)
            deltaxy = reference.Y > 0 ? hypot(xyz.x - reference.x, xyz.y - reference.y) : nil
            deltaL = reference.Y > 0 ? (xyz.Y / whiteY - reference.Y) / reference.Y : nil
        } else {
            deltaE = nil; deltaxy = nil; deltaL = nil
        }
    }

    var deltaLText: String {
        guard let d = deltaL else { return "" }
        if abs(d) < 0.001 { return "=" }
        return String(format: "%@%.1f %%", d < 0 ? "-" : "+", abs(d) * 100)
    }
}

// MARK: - Patterns and references (HCFR's formulas)

extension CalReference {
    /// Standard used to generate saturation patterns: as HCFR, the 75% / OPT-Plasma references are
    /// generated in Rec.709 (their own primaries are only targets).
    var generationStandard: ColorStandard {
        switch standard {
        case .hdtv75, .colorChecker, .uhdtv709in2020: return .hdtv
        case .uhdtvP3in2020: return .uhdtvP3
        default: return standard
        }
    }

    /// Luminance (white = 1) of the color made of these channels at 100%.
    func luma(_ channels: [Bool], in standard: ColorStandard? = nil) -> Double {
        var r = self
        if let standard { r.standard = standard }
        let m = r.rgbToXYZ
        return (0..<3).reduce(0) { $0 + (channels[$1] ? m.m[1][$1] : 0) }
    }

    /// Relative luminance (0…1) of a quantized signal with the target curve, as HCFR's references
    /// (pow(q, gamma) for the power law modes, getL_EOTF for BT.1886 / L* / sRGB).
    func targetCurve(_ q: Double, whiteY: Double, blackY: Double?) -> Double {
        if q <= 0 || q >= 1 { return min(max(q, 0), 1) }
        if standard.usesSRGBCurve && !gammaMode.isHDR {
            return q <= 0.04045 ? q / 12.92 : pow((q + 0.055) / 1.055, 2.4)
        }
        switch gammaMode {
        case .powerLaw, .blackCompensation: return pow(q, gammaInUse)
        case .cameraStandard, .cameraManual: return pow(offsetSignal(q), gammaInUse)
        case .bt1886, .lStar: return whiteY > 0 ? targetY(signal: q, whiteY: whiteY, blackY: blackY) / whiteY : pow(q, 2.4)
        case .st2084:
            // Absolute: relative to the diffuse white (HCFR: 50% PQ, 94.37844 nits by default)
            let nits = hdr.bt2390 ? EOTF.bt2390(q, hdr: hdr) : min(EOTF.pq(q) * 10000 * hdr.diffuseWhite / 94.37844, hdr.targetMaxL)
            return nits / hdr.diffuseWhite
        case .hlg:
            let peak = whiteY > 0 ? whiteY : hdr.targetMaxL
            return EOTF.hlg(q, systemGamma: hdr.hlgSystemGamma, minTL: hdr.targetMinL, maxTL: hdr.targetMaxL) / peak
        }
    }

    /// Pattern encoding of a linear level (white = 1), as HCFR generates them: 1/2.22 in SDR; in
    /// ST2084 white is the diffuse white (94.37844 nits) PQ-encoded; in HLG the BT.2100 OETF.
    func encodeSignal(_ v: Double) -> Double {
        if v <= 0 { return 0 }
        switch gammaMode {
        case .st2084: return EOTF.pqInverse(v * 94.37844 / 10000)
        case .hlg:
            let a = 0.17883277, b = 1 - 4 * a, c = 0.5 - a * log(4 * a)
            let e = min(v, 1)
            return e <= 1.0 / 12 ? sqrt(3 * e) : a * log(12 * e - b) + c
        default: return v >= 1 ? 1 : pow(v, 1 / 2.22)
        }
    }

    /// HCFR's reference for a pattern sent with 2.22 encoding: the signal is quantized to 8-bit video
    /// and decoded with the target curve, then converted with the standard (GetRefCC24Sat).
    func patternReference(signal: [Double], whiteY: Double, blackY: Double?) -> XYZ {
        let lin = signal.map { targetCurve(Self.quantize219($0), whiteY: whiteY, blackY: blackY) }
        let v = rgbToXYZ.apply(lin)
        return XYZ(X: v[0], Y: v[1], Z: v[2])
    }

    /// HDR: signal of a Color Checker patch recomputed as HCFR's GenerateCC24Colors (SDR signal
    /// linearized with 2.22, in Rec.709 for the classic charts, then encoded with the HDR curve).
    func hdrSignal(_ s: [Double], rec709: Bool) -> [Double] {
        var lin = s.map { $0 <= 0 ? 0 : pow(min($0, 1), 2.22) }
        if rec709 {
            var r709 = self
            r709.standard = .hdtv
            let xyz = r709.rgbToXYZ.apply(lin)
            lin = rgbToXYZ.inverse.apply(xyz)
        }
        return lin.map { Self.quantize219(encodeSignal(min(max($0, 0), 1))) }
    }

    static func quantize219(_ v: Double) -> Double { floor(min(max(v, 0), 1) * 219 + 0.5) / 219 }

    /// Signal of HCFR's saturation patterns (GenerateSaturationColors): each step lies on the line
    /// from white to the 100% color in xy, at the luminance of the 100% color, encoded with 1/2.22.
    func saturationSignals(_ color: PatchColor, steps n: Int) -> [[Double]] {
        let on = color.rgb.map { $0 > 0 }
        var gen = self
        gen.standard = generationStandard
        let m = gen.rgbToXYZ, inv = m.inverse
        let k = gen.luma(on)
        let full = m.apply(color.rgb)
        let end = XYZ(X: full[0], Y: full[1], Z: full[2])
        let w = gen.white
        let active = Double(on.filter { $0 }.count)
        return (0..<n).map { i -> [Double] in
            var clr: Double, comp: Double
            if i == 0 {
                clr = k; comp = k
            } else if i == n - 1 {
                clr = 1; comp = 0
            } else {
                let t = Double(i) / Double(n - 1)
                let c = XYZ.fromxyY(x: w.x + (end.x - w.x) * t, y: w.y + (end.y - w.y) * t, Y: k)
                let rgb = inv.apply([c.X, c.Y, c.Z])
                clr = (0..<3).reduce(0) { $0 + (on[$1] ? rgb[$1] : 0) } / active
                comp = (k - k * clr) / (1 - k)
                clr = min(max(clr, 0), 1)
                comp = min(max(comp, 0), 1)
            }
            return on.map { a in Self.quantize219(gen.encodeSignal(a ? clr : comp)) }
        }
    }

    /// HCFR's saturation reference (GetRefSat): the point at `ratio` from white to the standard's
    /// color in xy, with the luminance of the 100% color; in SDR moved to where a 2.22-encoded,
    /// 8-bit pattern lands with the target curve.
    func saturationReference(_ color: PatchColor, ratio: Double, whiteY: Double, blackY: Double?) -> XYZ {
        let on = color.rgb.map { $0 > 0 }
        let m = rgbToXYZ
        let full = m.apply(color.rgb)
        let end = XYZ(X: full[0], Y: full[1], Z: full[2])
        let c = XYZ.fromxyY(x: white.x + (end.x - white.x) * ratio, y: white.y + (end.y - white.y) * ratio,
                            Y: luma(on))
        let rgb = m.inverse.apply([c.X, c.Y, c.Z])
        let lin = rgb.map { v -> Double in
            targetCurve(Self.quantize219(encodeSignal(min(max(v, 0), 1))), whiteY: whiteY, blackY: blackY)
        }
        let v = m.apply(lin)
        return XYZ(X: v[0], Y: v[1], Z: v[2])
    }
}

/// HCFR's built-in Color Checker sets (libHCFR/Color.cpp GenerateCC24Colors, ManualDVDGenerator.cpp
/// patch names), signals in % of the video range.
enum ColorCheckerSets {
    private static let ccNames = ["Black", "Gray 35", "Gray 50", "Gray 65", "Gray 80", "White", "Dark skin",
                                  "Light skin", "Blue sky", "Foliage", "Blue flower", "Bluish green", "Orange",
                                  "Purplish blue", "Moderate red", "Purple", "Yellow green", "Orange yellow",
                                  "Blue", "Green", "Red", "Yellow", "Magenta", "Cyan"]

    private static func named(_ names: [String], _ values: [(Double, Double, Double)]) -> [(String, Double, Double, Double)] {
        zip(names, values).map { ($0, $1.0, $1.1, $1.2) }
    }

    static let gcd = named(ccNames, [
        (0, 0, 0), (62.1, 62.1, 62.1), (73.06, 73.06, 73.06), (82.19, 82.19, 82.19), (89.95, 89.95, 89.95),
        (100, 100, 100), (45.2, 31.96, 26.03), (75.8, 58.9, 51.14), (36.99, 47.95, 61.19), (35.16, 42.01, 26.03),
        (51.14, 50.23, 68.95), (38.81, 73.97, 66.21), (84.93, 47.03, 15.98), (29.22, 36.07, 63.93),
        (75.80, 32.88, 37.90), (36.07, 24.20, 42.01), (62.10, 73.06, 25.11), (89.95, 63.01, 17.81),
        (20.09, 24.20, 58.90), (27.85, 57.99, 27.85), (68.95, 19.18, 22.83), (93.15, 78.08, 12.79),
        (73.06, 32.88, 57.08), (0, 52.05, 63.93),
    ])

    /// Mascior's disc: the 18 colors first, then the grays from white to black.
    static let mcd = named(Array(ccNames[6...]) + ["White", "Gray 80", "Gray 65", "Gray 50", "Gray 35", "Black"], [
        (44.74, 31.51, 26.03), (75.80, 58.45, 50.68), (36.99, 47.95, 60.73), (34.70, 42.47, 26.48),
        (50.68, 50.22, 68.49), (39.27, 73.97, 66.21), (84.47, 47.49, 16.44), (28.77, 35.62, 64.38),
        (75.80, 33.33, 38.36), (36.07, 24.20, 42.01), (62.10, 73.06, 24.66), (89.95, 63.47, 18.26),
        (19.63, 24.20, 59.36), (28.31, 57.99, 27.85), (68.95, 19.18, 22.83), (93.15, 78.08, 12.79),
        (72.61, 32.42, 57.53), (11.87, 51.60, 59.82),
        (94.98, 94.52, 92.69), (78.54, 78.54, 78.08), (62.56, 62.56, 62.56), (47.49, 47.49, 47.03),
        (32.88, 32.88, 32.88), (21, 20.5, 21),
    ])

    static let calmanClassic = named(
        ["White", "80% Gray", "65% Gray", "50% Gray", "35% Gray", "Black", "Dark Skin", "Light Skin", "Blue Sky",
         "Foliage", "Blue Flower", "Bluish Green", "Orange", "Purplish Blue", "Moderate Red", "Purple",
         "Yellow Green", "Orange Yellow", "Blue", "Green", "Red", "Yellow", "Magenta", "Cyan"], [
        (100, 100, 100), (89.9543379, 89.9543379, 89.9543379), (82.19178082, 82.19178082, 82.19178082),
        (73.05936073, 73.05936073, 73.05936073), (62.10045662, 62.10045662, 62.10045662), (0, 0, 0),
        (45.20547945, 31.96347032, 26.02739726), (75.79908676, 58.90410959, 51.14155251),
        (36.98630137, 47.94520548, 61.18721461), (35.15981735, 42.00913242, 26.02739726),
        (51.14155251, 50.2283105, 68.94977169), (38.81278539, 73.97260274, 66.21004566),
        (84.93150685, 47.03196347, 15.98173516), (29.22374429, 36.07305936, 63.92694064),
        (75.79908676, 32.87671233, 37.89954338), (36.07305936, 24.20091324, 42.00913242),
        (62.10045662, 73.05936073, 25.11415525), (89.9543379, 63.01369863, 17.80821918),
        (20.0913242, 24.20091324, 58.90410959), (27.85388128, 57.99086758, 27.85388128),
        (68.94977169, 19.17808219, 22.83105023), (93.15068493, 78.08219178, 12.78538813),
        (73.05936073, 32.87671233, 57.07762557), (0, 52.05479452, 63.92694064),
    ])

    static let calmanSGSkin = named(
        ["White", "Black", "2E", "2F", "2K", "5D", "7E", "7F", "7G", "7H", "7I", "7J", "8D", "8E", "8F", "8G",
         "8H", "8I", "8J"], [
        (100, 100, 100), (0, 0, 0), (43.83561644, 25.11415525, 15.06849315), (79.9086758, 53.88127854, 40.1826484),
        (100, 78.08219178, 59.8173516), (100, 78.08219178, 67.12328767), (96.80365297, 67.12328767, 48.85844749),
        (78.08219178, 54.79452055, 36.07305936), (56.16438356, 36.07305936, 20.0913242),
        (80.82191781, 58.90410959, 45.20547945), (63.01369863, 33.78995434, 12.78538813),
        (84.01826484, 52.05479452, 36.07305936), (82.19178082, 53.88127854, 41.09589041),
        (98.17351598, 59.8173516, 45.20547945), (78.08219178, 56.16438356, 42.00913242),
        (78.99543379, 54.79452055, 42.00913242), (79.9086758, 56.16438356, 41.09589041),
        (47.94520548, 29.22374429, 15.06849315), (84.93150685, 54.79452055, 36.98630137),
    ])

    static let chromaPureSkin = named(
        ["White", "D7", "D8", "E7", "E8", "F7", "F8", "G7", "G8", "H7", "H8", "I7", "I8", "J7", "J8", "CP-Light",
         "CP-Dark", "Dark Skin", "Light Skin"], [
        (100, 100, 100), (84.47488584, 49.31506849, 34.24657534), (78.99543379, 55.25114155, 48.40182648),
        (93.60730594, 67.57990868, 57.99086758), (94.52054795, 61.18721461, 52.96803653),
        (75.34246575, 56.16438356, 42.92237443), (74.88584475, 57.07762557, 49.31506849),
        (55.25114155, 36.52968037, 24.65753425), (76.25570776, 56.62100457, 49.7716895),
        (75.79908676, 58.90410959, 51.14155251), (77.16894977, 56.62100457, 48.85844749),
        (62.10045662, 34.24657534, 17.80821918), (47.03196347, 29.6803653, 18.72146119),
        (81.73515982, 52.96803653, 42.46575342), (82.64840183, 56.16438356, 43.83561644),
        (93.15068493, 68.49315068, 48.40182648), (81.73515982, 60.2739726, 42.46575342),
        (45.20547945, 31.96347032, 26.48401826), (76.25570776, 58.90410959, 51.14155251),
    ])

    static let pantoneSkin = named(
        ["Skin#FFDFC4", "Skin#F0D5BE", "Skin#EECEB3", "Skin#E1B899", "Skin#E5C298", "Skin#FFDCB2", "Skin#E5B887",
         "Skin#E5A073", "Skin#E79E6D", "Skin#DB9065", "Skin#CE967C", "Skin#C67856", "Skin#BA6C49", "Skin#A57257",
         "Skin#F0C8C9", "Skin#DDA8A0", "Skin#B97C6D", "Skin#A87563", "Skin#AD6452", "Skin#5C3836", "Skin#CB8442",
         "Skin#BD723C", "Skin#704139", "Skin#A3866A"], [
        (100, 87.67123288, 76.71232877), (94.06392694, 83.56164384, 74.42922374), (93.15068493, 80.82191781, 70.3196347),
        (88.12785388, 72.14611872, 59.8173516), (89.9543379, 76.25570776, 59.8173516), (100, 86.30136986, 69.8630137),
        (89.9543379, 72.14611872, 56.16438356), (89.9543379, 62.55707763, 45.20547945), (90.4109589, 62.10045662, 42.92237443),
        (85.84474886, 56.62100457, 39.7260274), (80.82191781, 58.90410959, 48.40182648), (77.62557078, 47.03196347, 33.78995434),
        (73.05936073, 42.46575342, 28.76712329), (64.84018265, 44.74885845, 34.24657534), (94.06392694, 78.53881279, 78.99543379),
        (86.75799087, 65.75342466, 62.55707763), (72.60273973, 48.40182648, 42.92237443), (65.75342466, 45.66210046, 42.46575342),
        (68.03652968, 39.26940639, 31.96347032), (36.07305936, 21.91780822, 21.00456621), (79.45205479, 51.59817352, 26.02739726),
        (73.97260274, 44.74885845, 23.74429224), (43.83561644, 25.57077626, 22.37442922), (63.92694064, 52.51141553, 41.55251142),
    ])

    /// RGB luminance axis: black, then 10…100% of white, red, green, blue, cyan, magenta, yellow.
    static let axis: [(String, Double, Double, Double)] = {
        var rows: [(String, Double, Double, Double)] = [("Black", 0, 0, 0)]
        let series: [(String, [Double])] = [("White", [1, 1, 1]), ("Red", [1, 0, 0]), ("Green", [0, 1, 0]),
                                            ("Blue", [0, 0, 1]), ("Cyan", [0, 1, 1]), ("Magenta", [1, 0, 1]),
                                            ("Yellow", [1, 1, 0])]
        for (name, c) in series {
            for i in 1...10 {
                let v = Double(i * 10)
                rows.append(("\(name) \(i * 10)", c[0] * v, c[1] * v, c[2] * v))
            }
        }
        return rows
    }()

    static let calmanSG: [(String, Double, Double, Double)] = named(
        ["White", "6J", "5F", "6I", "6K", "5G", "6H", "5H", "7K", "6G", "5I", "6F", "8K", "5J", "Black",
         "2B", "2C", "2D", "2E", "2F", "2G", "2H", "2I", "2J", "2K", "2L", "2M",
         "3B", "3C", "3D", "3E", "3F", "3G", "3H", "3I", "3J", "3K", "3L", "3M",
         "4B", "4C", "4D", "4E", "4F", "4G", "4H", "4I", "4J", "4K", "4L", "4M",
         "5B", "5C", "5D", "5K", "5L", "5M", "6B", "6C", "6D", "6L", "6M",
         "7B", "7C", "7D", "7E", "7F", "7G", "7H", "7I", "7J", "7L", "7M",
         "8B", "8C", "8D", "8E", "8F", "8G", "8H", "8I", "8J", "8L", "8M",
         "9B", "9C", "9D", "9E", "9F", "9G", "9H", "9I", "9J", "9K", "9L", "9M"], [
        (100, 100, 100), (87.2146119, 87.2146119, 87.2146119), (77.1689498, 77.1689498, 77.1689498),
        (72.1461187, 72.1461187, 72.1461187), (67.1232877, 67.1232877, 67.1232877), (61.1872146, 61.1872146, 61.1872146),
        (56.1643836, 56.1643836, 56.1643836), (46.1187215, 46.1187215, 46.1187215), (42.0091324, 42.0091324, 42.0091324),
        (36.9863014, 36.9863014, 36.9863014), (32.8767123, 32.8767123, 32.8767123), (29.2237443, 29.2237443, 29.2237443),
        (21.0045662, 21.0045662, 21.0045662), (16.8949772, 16.8949772, 16.8949772), (0, 0, 0),
        (57.0776256, 10.9589041, 32.8767123), (29.2237443, 17.8082192, 27.8538813), (84.9315068, 82.1917808, 75.7990868),
        (43.8356164, 25.1141553, 15.0684932), (79.9086758, 53.8812785, 40.1826484), (35.1598174, 43.8356164, 51.1415525),
        (32.8767123, 37.8995434, 11.8721461), (50.2283105, 46.1187215, 57.0776256), (42.0091324, 70.7762557, 56.1643836),
        (100, 78.0821918, 59.8173516), (38.8127854, 10.9589041, 15.9817352), (74.8858447, 11.8721461, 29.2237443),
        (73.9726027, 50.2283105, 61.1872146), (42.9223744, 35.1598174, 53.8812785), (99.086758, 78.0821918, 70.7762557),
        (90.8675799, 43.8356164, 0), (24.2009132, 31.0502283, 56.1643836), (78.0821918, 25.1141553, 26.9406393),
        (31.9634703, 15.0684932, 31.9634703), (66.2100457, 70.7762557, 0), (91.7808219, 58.9041096, 0),
        (84.0182648, 90.8675799, 70.7762557), (79.9086758, 0, 8.2191781), (33.7899543, 12.7853881, 21.0045662),
        (46.1187215, 11.8721461, 43.8356164), (0, 21.0045662, 35.1598174), (73.9726027, 85.8447489, 72.1461187),
        (5.0228311, 16.8949772, 46.1187215), (26.0273973, 54.7945205, 15.9817352), (69.8630137, 0, 10.0456621),
        (96.803653, 74.8858447, 0), (75.7990868, 26.0273973, 47.9452055), (0, 50.2283105, 54.7945205),
        (90.8675799, 79.9086758, 74.8858447), (84.0182648, 46.1187215, 47.0319635), (74.8858447, 0, 15.0684932),
        (0, 48.8584475, 68.0365297), (32.8767123, 59.8173516, 68.0365297), (100, 78.0821918, 67.1232877),
        (74.8858447, 84.0182648, 75.7990868), (87.2146119, 46.1187215, 40.1826484), (94.0639269, 20.0913242, 15.0684932),
        (19.1780822, 63.0136986, 64.8401826), (0, 22.8310502, 26.9406393), (85.8447489, 83.1050228, 52.0547945),
        (100, 40.1826484, 0), (100, 63.0136986, 0), (0, 22.8310502, 20.0913242),
        (46.1187215, 57.9908676, 68.9497717), (85.8447489, 47.9452055, 27.8538813), (96.803653, 67.1232877, 48.8584475),
        (78.0821918, 54.7945205, 36.0730594), (56.1643836, 36.0730594, 20.0913242), (80.8219178, 58.9041096, 45.2054795),
        (63.0136986, 33.7899543, 12.7853881), (84.0182648, 52.0547945, 36.0730594), (78.0821918, 69.8630137, 0),
        (100, 74.8858447, 0), (0, 63.0136986, 56.1643836), (0, 54.7945205, 46.1187215),
        (82.1917808, 53.8812785, 41.0958904), (98.173516, 59.8173516, 45.2054795), (78.0821918, 56.1643836, 42.0091324),
        (78.9954338, 54.7945205, 42.0091324), (79.9086758, 56.1643836, 41.0958904), (47.9452055, 29.2237443, 15.0684932),
        (84.9315068, 54.7945205, 36.9863014), (72.1461187, 56.1643836, 9.1324201), (73.0593607, 69.8630137, 0),
        (25.1141553, 21.0045662, 14.1552511), (35.1598174, 63.0136986, 35.1598174), (0, 53.8812785, 31.0502283),
        (11.8721461, 25.1141553, 15.9817352), (22.8310502, 63.0136986, 42.9223744), (47.9452055, 61.1872146, 21.9178082),
        (20.0913242, 53.8812785, 10.0456621), (29.2237443, 66.2100457, 15.9817352), (78.9954338, 52.0547945, 16.8949772),
        (62.1004566, 58.9041096, 10.0456621), (64.8401826, 73.0593607, 0), (30.1369863, 16.8949772, 10.0456621),
    ])
}
