// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.
//
// Color formulas ported from HCFR (libHCFR/Color.cpp, Views/MainView.cpp, datasetdoc.cpp,
// Export.cpp), Copyright (c) 2005-2007 Association Homecinema Francophone and HCFR contributors,
// GNU GPL.

import Foundation

/// Valor triestimulo CIE 1931 (Y en cd/m²).
struct XYZ: Equatable {
    var X: Double
    var Y: Double
    var Z: Double

    var sum: Double { X + Y + Z }
    var x: Double { sum > 0 ? X / sum : 0 }
    var y: Double { sum > 0 ? Y / sum : 0 }
    var z: Double { sum > 0 ? Z / sum : 0 }

    static func fromxyY(x: Double, y: Double, Y: Double) -> XYZ {
        guard y > 0 else { return XYZ(X: 0, Y: 0, Z: 0) }
        return XYZ(X: x / y * Y, Y: Y, Z: (1 - x - y) / y * Y)
    }

    func scaled(_ k: Double) -> XYZ { XYZ(X: X * k, Y: Y * k, Z: Z * k) }
}

struct Mat3 {
    var m: [[Double]]

    static func columns(_ a: [Double], _ b: [Double], _ c: [Double]) -> Mat3 {
        Mat3(m: [[a[0], b[0], c[0]], [a[1], b[1], c[1]], [a[2], b[2], c[2]]])
    }

    func apply(_ v: [Double]) -> [Double] {
        (0..<3).map { r in m[r][0] * v[0] + m[r][1] * v[1] + m[r][2] * v[2] }
    }

    var inverse: Mat3 {
        let a = m
        let det = a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        let d = 1 / det
        return Mat3(m: [
            [(a[1][1] * a[2][2] - a[1][2] * a[2][1]) * d, (a[0][2] * a[2][1] - a[0][1] * a[2][2]) * d, (a[0][1] * a[1][2] - a[0][2] * a[1][1]) * d],
            [(a[1][2] * a[2][0] - a[1][0] * a[2][2]) * d, (a[0][0] * a[2][2] - a[0][2] * a[2][0]) * d, (a[0][2] * a[1][0] - a[0][0] * a[1][2]) * d],
            [(a[1][0] * a[2][1] - a[1][1] * a[2][0]) * d, (a[0][1] * a[2][0] - a[0][0] * a[2][1]) * d, (a[0][0] * a[1][1] - a[0][1] * a[1][0]) * d],
        ])
    }
}

/// White points of HCFR's "Change White" option (illuminants in libHCFR/Color.cpp), without CUSTOM.
enum WhitePoint: String, CaseIterable, Identifiable {
    case d65 = "D65"
    case d93 = "D93"
    case d75 = "D75"
    case d55 = "D55"
    case d50 = "D50"
    case dci = "DCI"
    case a = "A"
    case b = "B"
    case c = "C"
    case e = "E"
    /// User white point (Preferences → References → Change White → Custom).
    case custom = "Custom"

    var id: String { rawValue }
    /// Chromaticity of the Custom white, set from the preferences.
    static var customXY: (x: Double, y: Double) = (0.3127, 0.3290)

    var xy: (x: Double, y: Double) {
        switch self {
        case .custom: return Self.customXY
        case .d65: return (0.312712, 0.329008)
        case .d93: return (0.284863, 0.293221)
        case .d75: return (0.299023, 0.314963)
        case .d55: return (0.332406, 0.347551)
        case .d50: return (0.345669, 0.358496)
        case .dci: return (0.314, 0.351)
        case .a: return (0.447593, 0.407539)
        case .b: return (0.348483, 0.351747)
        case .c: return (0.310115, 0.316311)
        case .e: return (0.333334, 0.333333)
        }
    }
    var x: Double { xy.x }
    var y: Double { xy.y }

    /// Nominal color temperature (D65/D93 as HCFR names them; the rest are their CIE CCT).
    var kelvin: Int {
        switch self {
        case .d65: return 6504
        case .d93: return 9300
        case .d75: return 7504
        case .d55: return 5503
        case .d50: return 5003
        case .dci, .custom: return Int((ColorMath.cct(XYZ.fromxyY(x: x, y: y, Y: 1)) ?? 6504).rounded())
        case .a: return 2856
        case .b: return 4874
        case .c: return 6774
        case .e: return 5454
        }
    }
    var label: String { "\(rawValue) (\(kelvin) K)" }

    func xyz(Y: Double) -> XYZ { XYZ.fromxyY(x: x, y: y, Y: Y) }
}

/// Color space standards of HCFR (CColorReference in libHCFR/Color.cpp), without CUSTOM.
enum ColorStandard: String, CaseIterable, Identifiable {
    case palSecam = "PAL/SECAM"
    case sdtv = "SDTV - REC 601 (NTSC)"
    case hdtv = "HDTV - REC 709"
    case hdtv75 = "75% HDTV - REC 709"
    case colorChecker = "Color Checker HDTV OPT-Plasma"
    case sRGB = "sRGB"
    case uhdtvP3 = "UHDTV - DCI-P3/D65"
    case uhdtv2020 = "UHDTV - REC 2020"
    case uhdtvP3in2020 = "UHDTV - P3 in REC 2020"
    case uhdtv709in2020 = "UHDTV - REC 709 in REC 2020"
    /// User primaries (Preferences → References → Custom).
    case custom = "Custom"

    var id: String { rawValue }
    /// Red, green and blue chromaticities of the Custom standard, set from the preferences.
    static var customPrimaries: [(x: Double, y: Double)] = [(0.64, 0.33), (0.30, 0.60), (0.15, 0.06)]

    /// Short name for the info line, as HCFR shows it.
    var shortName: String {
        switch self {
        case .palSecam: return "PAL/SECAM"
        case .sdtv: return "SDTV Rec601"
        case .hdtv: return "HDTV Rec709"
        case .hdtv75: return "75% HDTV Rec709"
        case .colorChecker: return "Color Checker HDTV OPT-Plasma"
        case .sRGB: return "sRGB"
        case .uhdtvP3: return "UHDTV DCI-P3/D65"
        case .uhdtv2020: return "UHDTV Rec2020"
        case .uhdtvP3in2020: return "UHDTV P3 in Rec2020"
        case .uhdtv709in2020: return "UHDTV Rec709 in Rec2020"
        case .custom: return "Custom"
        }
    }

    var primaries: [(x: Double, y: Double)] {
        switch self {
        case .palSecam: return [(0.6400, 0.3300), (0.2900, 0.6000), (0.1500, 0.0600)]
        case .sdtv: return [(0.6300, 0.3400), (0.3100, 0.5950), (0.1550, 0.0700)]
        case .hdtv, .sRGB, .uhdtv709in2020: return [(0.6400, 0.3300), (0.3000, 0.6000), (0.1500, 0.0600)]
        case .hdtv75: return [(0.5575, 0.3298), (0.3032, 0.5313), (0.1911, 0.1279)]
        case .colorChecker: return [(0.625, 0.330), (0.303, 0.533), (0.245, 0.217)]
        case .uhdtvP3, .uhdtvP3in2020: return [(0.6800, 0.3200), (0.265, 0.6900), (0.1500, 0.0600)]
        case .uhdtv2020: return [(0.708, 0.292), (0.170, 0.797), (0.131, 0.046)]
        case .custom: return Self.customPrimaries
        }
    }

    /// sRGB uses the sRGB tone curve instead of a power law (as HCFR does).
    var usesSRGBCurve: Bool { self == .sRGB }
}

/// Target luminance curve of the gray scale (HCFR's References → Gamma calculation / EOTF).
/// Raw values are HCFR's m_GammaOffsetType.
enum GammaMode: Int, CaseIterable, Identifiable {
    case powerLaw = 0
    case blackCompensation = 1
    case bt1886 = 4
    case lStar = 6
    case hlg = 7
    case st2084 = 5
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .powerLaw: return "Display Gamma (power law)"
        case .blackCompensation: return "Display Gamma (black compensation)"
        case .bt1886: return "ITU-R BT.1886"
        case .lStar: return "L*"
        case .hlg: return "BBC Hybrid Log-Gamma"
        case .st2084: return "SMPTE 2084 HDR"
        }
    }
    var shortName: String {
        switch self {
        case .powerLaw: return "Power law"
        case .blackCompensation: return "Black compensation"
        case .bt1886: return "BT.1886"
        case .lStar: return "L*"
        case .hlg: return "HLG"
        case .st2084: return "ST2084"
        }
    }
    var isHDR: Bool { self == .hlg || self == .st2084 }
}

/// Delta E formula (HCFR's Advanced → dE formula). Raw values are HCFR's m_dE_form.
enum DeltaEFormula: Int, CaseIterable, Identifiable {
    case cie76uv = 0, cie76ab, cie94, cie2000, cmc, recommended, ictcp
    var id: Int { rawValue }
    var title: String {
        ["CIE76(uv)", "CIE76(ab)", "CIE94", "CIE2000", "CMC", "Recommended", "dICtCp"][rawValue]
    }
}

/// Gray scale Delta E luminance reference (HCFR's Advanced → dE gray). Raw values are m_dE_gray.
enum GrayDeltaEMode: Int, CaseIterable, Identifiable {
    case relativeY = 0, absoluteYWithGamma, absoluteYWithoutGamma
    var id: Int { rawValue }
    var title: String { ["Relative Y", "Absolute Y w/gamma", "Absolute Y w/o gamma"][rawValue] }
}

/// White luminance weighting of Delta E (HCFR's Advanced → dE weight). Raw values are gw_Weight.
enum DeltaEWeight: Int, CaseIterable, Identifiable {
    case standard = 0, grayWorld, dark
    var id: Int { rawValue }
    var title: String { ["Default", "Gray World[15%]", "Dark[5%]"][rawValue] }
    var factor: Double { [1, 0.15, 0.05][rawValue] }
}

/// HDR settings of HCFR's References page (EOTF (HDR) box).
struct HDRSettings: Equatable {
    /// Diffuse white in nits (HCFR default 94.37844, the 50% PQ level of 100 nits).
    var diffuseWhite = 94.37844
    var targetMinL = 0.05
    var targetMaxL = 120.0
    var masterMinL = 0.0
    var masterMaxL = 4000.0
    var contentMaxL = 4000.0
    var frameAvgMaxL = 400.0
    /// HLG system gamma.
    var hlgSystemGamma = 1.2
    /// BT.2390 tone mapping (HCFR "BT.2390").
    var bt2390 = false
    /// HCFR "Override Targets".
    var overrideTargets = false
    /// BT.2390 knee: black slope ("NB slope"), white slope ("NW") and its start in % ("%").
    var blackSlope = 1.0
    var whiteSlope = 0.0
    var whiteSlopeStart = 25.0
}

/// Preferences of HCFR's References and Advanced pages that are not in the main window
/// (standard, white, gamma and Override black are). Saved with the settings and in projects.
struct ReferencePrefs: Codable, Equatable {
    var gammaMode = GammaMode.powerLaw.rawValue
    var gammaRel = 0.0
    var split = 100.0
    var useMeasuredGamma = false
    /// Black luminance used when Override black is on (HCFR "Override black … cd/m^2").
    var manualBlack = 0.0
    var customWhiteX = 0.3127, customWhiteY = 0.3290
    var customRedX = 0.64, customRedY = 0.33
    var customGreenX = 0.30, customGreenY = 0.60
    var customBlueX = 0.15, customBlueY = 0.06
    var diffuseWhite = 94.37844
    var targetMinL = 0.05, targetMaxL = 120.0
    var masterMinL = 0.0, masterMaxL = 4000.0
    var contentMaxL = 4000.0, frameAvgMaxL = 400.0
    var hlgSystemGamma = 1.2
    var bt2390 = false
    var overrideTargets = false
    var blackSlope = 1.0, whiteSlope = 0.0, whiteSlopeStart = 25.0
    var deltaEFormula = DeltaEFormula.cie2000.rawValue
    var grayDeltaE = GrayDeltaEMode.absoluteYWithoutGamma.rawValue
    var deltaEWeight = DeltaEWeight.standard.rawValue

    var mode: GammaMode { GammaMode(rawValue: gammaMode) ?? .powerLaw }

    var hdr: HDRSettings {
        HDRSettings(diffuseWhite: diffuseWhite, targetMinL: targetMinL, targetMaxL: targetMaxL, masterMinL: masterMinL,
                    masterMaxL: masterMaxL, contentMaxL: contentMaxL, frameAvgMaxL: frameAvgMaxL,
                    hlgSystemGamma: hlgSystemGamma, bt2390: bt2390, overrideTargets: overrideTargets,
                    blackSlope: blackSlope, whiteSlope: whiteSlope, whiteSlopeStart: whiteSlopeStart)
    }

    /// Makes the Custom white / primaries available to WhitePoint and ColorStandard.
    func applyCustomColors() {
        WhitePoint.customXY = (customWhiteX, customWhiteY)
        ColorStandard.customPrimaries = [(customRedX, customRedY), (customGreenX, customGreenY), (customBlueX, customBlueY)]
    }
}

/// Measurement reference: color space standard, white point and target luminance curve, and the
/// Delta E options. Mirrors HCFR's References and Advanced preference pages.
struct CalReference: Equatable {
    var standard: ColorStandard = .sdtv
    var white: WhitePoint = .d65
    /// Power law gamma ("Power Law Gamma").
    var gamma: Double = 2.3
    var gammaMode: GammaMode = .powerLaw
    /// BT.1886 "Effective @50%" gamma (0 = absolute BT.1886, exponent 2.4).
    var gammaRel: Double = 0
    /// BT.1886 "% input offset" (HCFR's split, 100 by default).
    var split: Double = 100
    /// "Use avg measured gamma": power law modes use this gamma instead of `gamma` when set.
    var measuredGamma: Double?
    var hdr = HDRSettings()
    var deltaEFormula: DeltaEFormula = .cie2000
    var grayDeltaE: GrayDeltaEMode = .absoluteYWithoutGamma
    var deltaEWeight: DeltaEWeight = .standard

    static func == (a: CalReference, b: CalReference) -> Bool {
        a.standard == b.standard && a.white == b.white && a.gamma == b.gamma && a.gammaMode == b.gammaMode
            && a.gammaRel == b.gammaRel && a.split == b.split && a.measuredGamma == b.measuredGamma && a.hdr == b.hdr
            && a.deltaEFormula == b.deltaEFormula && a.grayDeltaE == b.grayDeltaE && a.deltaEWeight == b.deltaEWeight
    }

    /// Gamma used by the power law modes ("Target Gamma in use").
    var gammaInUse: Double { measuredGamma ?? gamma }

    /// Linear RGB -> XYZ matrix normalised so RGB(1,1,1) = white with Y = 1.
    var rgbToXYZ: Mat3 {
        let p = standard.primaries.map { XYZ.fromxyY(x: $0.x, y: $0.y, Y: 1) }
        let raw = Mat3.columns([p[0].X, p[0].Y, p[0].Z], [p[1].X, p[1].Y, p[1].Z], [p[2].X, p[2].Y, p[2].Z])
        let w = white.xyz(Y: 1)
        let s = raw.inverse.apply([w.X, w.Y, w.Z])
        return Mat3(m: raw.m.map { row in [row[0] * s[0], row[1] * s[1], row[2] * s[2]] })
    }

    /// White used for Lab / Luv in Delta E. As HCFR, the 75% and OPT-Plasma references use Rec.709 D65.
    var deltaEWhite: WhitePoint {
        standard == .hdtv75 || standard == .colorChecker ? .d65 : white
    }

    /// Relative target luminance for a signal level (0...1) in the power law / sRGB sense, used where
    /// no measured white or black exist yet (graph reference curves fall back to it).
    func eotf(_ v: Double) -> Double {
        targetY(signal: v, whiteY: 100, blackY: nil) / 100
    }

    /// Target luminance (cd/m²) of a gray level, from the measured white and black, as HCFR's
    /// MainView / getL_EOTF. `blackY` nil = not measured: HCFR's default on/off black, Target MinL.
    func targetY(signal v0: Double, whiteY: Double, blackY: Double?) -> Double {
        let v = min(max(v0, 0), 1)
        if standard.usesSRGBCurve && !gammaMode.isHDR {
            return whiteY * (v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4))
        }
        switch gammaMode {
        case .powerLaw:
            return whiteY * pow(v, gammaInUse)
        case .blackCompensation:
            let b = blackY ?? 0
            return b + pow(v, gammaInUse) * (whiteY - b)
        case .bt1886:
            return whiteY * EOTF.bt1886(v, maxL: whiteY, minL: blackY ?? hdr.targetMinL, gammaRel: gammaRel, split: split)
        case .lStar:
            return whiteY * EOTF.lStar(v)
        case .hlg:
            return EOTF.hlg(v, systemGamma: hdr.hlgSystemGamma, minTL: hdr.targetMinL, maxTL: hdr.targetMaxL)
        case .st2084:
            if v == 0 { return hdr.bt2390 ? hdr.targetMinL : 0 }
            let nits = hdr.bt2390 ? EOTF.bt2390(v, hdr: hdr) : min(EOTF.pq(v) * 10000 * hdr.diffuseWhite / 94.37844, hdr.targetMaxL)
            return min(nits, hdr.targetMaxL)
        }
    }
}

/// HCFR's getL_EOTF curves (libHCFR/Color.cpp).
enum EOTF {
    static let m1 = 0.1593017578125, m2 = 78.84375, c1 = 0.8359375, c2 = 18.8515625, c3 = 18.6875

    /// SMPTE ST 2084 (PQ) signal -> linear (1 = 10000 nits).
    static func pq(_ v: Double) -> Double {
        let p = pow(v, 1 / m2)
        return pow(max(p - c1, 0) / (c2 - c3 * p), 1 / m1)
    }

    /// Inverse PQ: linear (1 = 10000 nits) -> signal.
    static func pqInverse(_ l: Double) -> Double {
        let p = pow(max(l, 0), m1)
        return pow((c1 + c2 * p) / (1 + c3 * p), m2)
    }

    /// BT.1886, relative to white, with HCFR's effective gamma at 50% and input offset options.
    static func bt1886(_ v: Double, maxL: Double, minL: Double, gammaRel: Double, split: Double) -> Double {
        var exp0 = gammaRel == 0 ? 2.4 : gammaRel
        let offset = split / 100 * minL
        func ab(_ e: Double) -> (Double, Double) {
            let a = pow(pow(maxL, 1 / e) - pow(offset, 1 / e), e)
            let b = pow(offset, 1 / e) / (pow(maxL, 1 / e) - pow(offset, 1 / e))
            return (a, b)
        }
        var (a, b) = ab(exp0)
        if gammaRel != 0 {
            let yh = maxL * pow(0.5, gammaRel)
            exp0 = (log(yh) - log(a)) / log(0.5 + b)
            for _ in 0..<9 {
                (a, b) = ab(exp0)
                exp0 = (log(yh) - log(a)) / log(0.5 + b)
            }
        }
        let lbt = a * pow(max(v + b, 0), exp0)
        return (lbt + minL * (1 - split / 100)) / (maxL + minL * (1 - split / 100))
    }

    /// L* curve, relative to white.
    static func lStar(_ v: Double) -> Double {
        let t = (v * 100 + 16) / 116
        return 29 * t > 6 ? pow(t, 3) : 3 * pow(6.0 / 29, 2) * (t - 4.0 / 29)
    }

    /// HLG (BT.2100) with system gamma, in nits between target min and max luminance.
    static func hlg(_ v: Double, systemGamma: Double, minTL: Double, maxTL: Double) -> Double {
        let a = 0.17883277, b = 1 - 4 * a, c = 0.5 - a * log(4 * a)
        let e = v <= 0.5 ? v * v / 3 : (exp((v - c) / a) + b) / 12
        return (maxTL - minTL) * pow(e, systemGamma - 1) * e + minTL
    }

    /// ST 2084 with BT.2390 tone mapping to the target display (HCFR's mode 10), in nits.
    static func bt2390(_ v: Double, hdr: HDRSettings) -> Double {
        let scale = hdr.diffuseWhite / 94.37844 * 10000
        let minML = min(hdr.masterMinL, hdr.targetMinL)
        let maxML = hdr.masterMaxL * hdr.diffuseWhite / 94.37844
        let pMin = pqInverse(minML / scale), pMax = pqInverse(maxML / scale)
        let d = pMax - pMin
        var e1 = (v - pMin) / d
        let minL = (pqInverse(hdr.targetMinL / scale) - pMin) / d
        let maxL = (pqInverse(hdr.targetMaxL / scale) - pMin) / d
        let ks = 1.5 * maxL - 0.5
        let bb = minL
        var e2 = e1
        let lower = ks, upper = pMax
        let mmaxL = lower + hdr.whiteSlopeStart / 100 * (upper - lower)
        if e1 >= mmaxL && upper > lower {
            let slope = pow(e1 - mmaxL, 2) * pow(1 - e1, 0.75) * hdr.whiteSlope * (2.5 * pow(mmaxL, 2) + 3 * pow(mmaxL, 3)) + 1
            e1 /= slope
        }
        if e1 >= ks && e1 <= 1 {
            let t = (e1 - ks) / (1 - ks)
            e2 = (2 * pow(t, 3) - 3 * pow(t, 2) + 1) * ks + (pow(t, 3) - 2 * pow(t, 2) + t) * (1 - ks) + (-2 * pow(t, 3) + 3 * pow(t, 2)) * maxL
        }
        var out: Double
        if e2 >= 0 && e2 <= 1 {
            let p = min(1 / bb, 4 * hdr.blackSlope)
            var e3 = e2 + bb * pow(1 - e2, p)
            e3 = e3 * d + pMin
            out = pq(e3) * 10000 * hdr.diffuseWhite / 94.37844
        } else {
            out = pq(v) * 10000 * hdr.diffuseWhite / 94.37844
        }
        return min(out, hdr.targetMaxL)
    }
}

enum Reference {
    /// Default gray scale: 11 points, 0 to 100% in steps of 10.
    static let defaultGrayCount = 11
    /// Gray scale sizes offered (number of points, 0 and 100% included). HCFR for Windows
    /// accepts 4 to 100 intervals ("Scale sizes" dialog); these are the usual ones.
    static let grayCounts = [5, 6, 11, 17, 21, 26, 51, 101]

    /// Levels (% white) of a gray scale of `count` points: evenly spaced from 0 to 100, as HCFR's
    /// gray measure array (the signal is quantized to 8-bit video codes by `grayProp`).
    static func levels(count: Int) -> [Double] {
        let n = max(count, 2)
        return (0..<n).map { $0 == n - 1 ? 100 : Double($0) * 100 / Double(n - 1) }
    }

    /// "10", "6.25", "33.3" for column headers and messages.
    static func label(_ level: Double) -> String {
        if abs(level - level.rounded()) < 1e-9 { return String(Int(level.rounded())) }
        let s = String(format: "%.2f", level)
        return s.hasSuffix("0") ? String(s.dropLast()) : s
    }

    /// Gray level of a calibration DVD (8 bit, 16–235, normal rounding; HCFR's GrayLevelToGrayProp).
    static func grayProp(_ level: Double) -> Double {
        if roundDown { return (floor(level / 100 * 219 + 16) - 16) / 219 }
        if use10bit { return (floor(level / 100 * 876 + 64.5) - 64) / 876 }
        return (floor(level / 100 * 219 + 16.5) - 16) / 219
    }

    /// HCFR's "Gray levels rounding assumption" (General preferences): round down levels
    /// (AVSHD, DVE discs) or 10-bit targets (HDR10 Blu-ray). Normal rounding when both are off.
    static var roundDown = false
    static var use10bit = false
}

enum ColorMath {
    /// Linear R, G, B in cd/m² (as HCFR's "Current Measure" table).
    static func rgb(_ c: XYZ, ref: CalReference) -> [Double] {
        ref.rgbToXYZ.inverse.apply([c.X, c.Y, c.Z])
    }

    /// RGB balance in %: 100/100/100 = exact gray of the chosen white.
    static func rgbBalance(_ c: XYZ, ref: CalReference) -> [Double]? {
        guard c.Y > 1e-6 else { return nil }
        return rgb(c, ref: ref).map { $0 / c.Y * 100 }
    }

    /// Temperatura de color correlacionada (aproximacion de McCamy).
    static func cct(_ c: XYZ) -> Double? {
        guard c.sum > 0 else { return nil }
        let n = (c.x - 0.3320) / (0.1858 - c.y)
        return 449 * n * n * n + 3525 * n * n + 6823.3 * n + 5520.33
    }

    /// Lab como ColorLab de HCFR: blanco = cromaticidad de referencia escalada a `whiteY`.
    static func lab(_ c: XYZ, whiteY: Double, white: WhitePoint) -> [Double] {
        let w = white.xyz(Y: whiteY)
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let fx = f(c.X / w.X), fy = f(c.Y / w.Y), fz = f(c.Z / w.Z)
        return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
    }

    static func lch(_ lab: [Double]) -> [Double] {
        var h = atan2(lab[2], lab[1]) * 180 / .pi
        if h < 0 { h += 360 }
        return [lab[0], hypot(lab[1], lab[2]), h]
    }

    /// CIEDE2000, same implementation as HCFR's ColorXYZ::GetDeltaE (dE_form 3).
    static func deltaE2000(ref: [Double], measured: [Double]) -> Double {
        let pi = Double.pi
        let (l1, a1, b1) = (ref[0], ref[1], ref[2])
        let (l2, a2, b2) = (measured[0], measured[1], measured[2])
        let lp = (l1 + l2) / 2
        let c1 = hypot(a1, b1), c2 = hypot(a2, b2)
        let c = (c1 + c2) / 2
        let g = (1 - sqrt(pow(c, 7) / (pow(c, 7) + pow(25, 7)))) / 2
        let a1p = a1 * (1 + g), a2p = a2 * (1 + g)
        let c1p = hypot(a1p, b1), c2p = hypot(a2p, b2)
        let cp = (c1p + c2p) / 2
        let h1p = atan2(b1, a1p) >= 0 ? atan2(b1, a1p) : atan2(b1, a1p) + pi * 2
        let h2p = atan2(b2, a2p) >= 0 ? atan2(b2, a2p) : atan2(b2, a2p) + pi * 2
        let hp = abs(h1p - h2p) > pi ? (h1p + h2p + pi * 2) / 2 : (h1p + h2p) / 2
        let t = 1 - 0.17 * cos(hp - 30 / 180 * pi) + 0.24 * cos(2 * hp) + 0.32 * cos(3 * hp + 6 / 180 * pi) - 0.20 * cos(4 * hp - 63 / 180 * pi)
        let dhp = abs(h2p - h1p) <= pi ? h2p - h1p : (h2p <= h1p ? h2p - h1p + 2 * pi : h2p - h1p - 2 * pi)
        let dLp = l2 - l1
        let dCp = c2p - c1p
        let dHp = 2 * sqrt(c1p * c2p) * sin(dhp / 2)
        let sl = 1 + 0.015 * pow(lp - 50, 2) / sqrt(20 + pow(lp - 50, 2))
        let sc = 1 + 0.045 * cp
        let sh = 1 + 0.015 * cp * t
        let dtheta = 30 * exp(-pow((hp * 180 / pi - 275) / 25, 2))
        let rc = 2 * sqrt(pow(cp, 7) / (pow(cp, 7) + pow(25, 7)))
        let rt = -rc * sin(2 * dtheta / 180 * pi)
        return sqrt(pow(dLp / sl, 2) + pow(dCp / sc, 2) + pow(dHp / sh, 2) + rt * (dCp / sc) * (dHp / sh))
    }

    /// Gray scale ΔE as HCFR (MainView.cpp), with the dE gray mode of the preferences:
    /// - Relative Y: color only (measure and reference both at their own white);
    /// - Absolute Y w/gamma: reference at the target luminance (`targetY`);
    /// - Absolute Y w/o gamma: reference at the measured luminance (color error only, default).
    static func grayDeltaE(_ c: XYZ, whiteY: Double, targetY: Double?, ref: CalReference) -> Double? {
        guard whiteY > 0, c.Y > 0 else { return nil }
        let refY: Double
        var measuredWhite = whiteY
        switch ref.grayDeltaE {
        case .relativeY:
            refY = 1
            measuredWhite = c.Y
        case .absoluteYWithGamma:
            guard let t = targetY else { return nil }
            refY = t / whiteY
        case .absoluteYWithoutGamma:
            refY = c.Y / whiteY
        }
        let target = ref.white.xyz(Y: refY)
        return deltaE(c, whiteY: measuredWhite, reference: target, refWhiteY: 1, ref: ref, isGray: true)
    }

    /// HCFR's ColorXYZ::GetDeltaE with the formula of the preferences. `isGray` picks CIE76(uv) for
    /// the gray scale with the "Recommended" formula (CIE2000 for colors).
    static func deltaE(_ c: XYZ, whiteY: Double, reference: XYZ, refWhiteY: Double, ref: CalReference, isGray: Bool) -> Double {
        let k = ref.deltaEWeight.factor
        let yw = (whiteY > 0 ? whiteY : 120) * k, ywRef = (refWhiteY > 0 ? refWhiteY : 1) * k
        let white = ref.deltaEWhite
        var formula = ref.deltaEFormula
        if formula == .recommended { formula = isGray ? .cie76uv : .cie2000 }
        switch formula {
        case .cie76uv:
            let a = luv(reference, whiteY: ywRef, white: white), b = luv(c, whiteY: yw, white: white)
            return sqrt(pow(b[0] - a[0], 2) + pow(b[1] - a[1], 2) + pow(b[2] - a[2], 2))
        case .ictcp:
            // As HCFR: the measure scaled by the reference white and vice versa
            let a = ictcp(reference, scale: yw, standard: ref.standard), b = ictcp(c, scale: ywRef, standard: ref.standard)
            return sqrt(4 * pow(b[0] - a[0], 2) + 0.25 * pow(b[1] - a[1], 2) + pow(b[2] - a[2], 2)) * 240
        default:
            let a = lab(reference, whiteY: ywRef, white: white), b = lab(c, whiteY: yw, white: white)
            switch formula {
            case .cie76ab:
                return sqrt(pow(b[0] - a[0], 2) + pow(b[1] - a[1], 2) + pow(b[2] - a[2], 2))
            case .cie94:
                let dL2 = pow(a[0] - b[0], 2)
                let c1 = hypot(a[1], a[2]), c2 = hypot(b[1], b[2])
                let dC2 = pow(c1 - c2, 2)
                let dH2 = pow(a[1] - b[1], 2) + pow(a[2] - b[2], 2) - dC2
                return sqrt(dL2 + dC2 / pow(1 + 0.045 * c1, 2) + dH2 / pow(1 + 0.015 * c1, 2))
            case .cmc:
                let (l1, a1, b1) = (a[0], a[1], a[2]), (l2, a2, b2) = (b[0], b[1], b[2])
                let c1 = hypot(a1, b1), c2 = hypot(a2, b2)
                let dC = c1 - c2, dL = l1 - l2
                let dH = sqrt(abs(pow(a1 - a2, 2) + pow(b1 - b2, 2) - dC * dC))
                let sl = l1 < 16 ? 0.511 : 0.040975 * l1 / (1 + 0.01765 * l1)
                let sc = 0.0638 * c1 / (1 + 0.0131 * c1) + 0.638
                let f = sqrt(pow(c1, 4) / (pow(c1, 4) + 1900))
                var h1 = atan2(b1, a1) / .pi * 180
                h1 = h1 < 0 ? h1 + 360 : (h1 >= 360 ? h1 - 360 : h1)
                let t = h1 <= 345 && h1 >= 164 ? 0.56 + abs(0.2 * cos((h1 + 168) / 180 * .pi)) : 0.36 + abs(0.4 * cos((h1 + 35) / 180 * .pi))
                let sh = sc * (f * t + 1 - f)
                return sqrt(pow(dL / sl, 2) + pow(dC / sc, 2) + pow(dH / sh, 2))
            default:
                return deltaE2000(ref: a, measured: b)
            }
        }
    }

    /// Luv as HCFR's ColorLuv (including its u' formula, which uses x in the denominator, so the
    /// values match HCFR for Windows).
    static func luv(_ c: XYZ, whiteY: Double, white: WhitePoint) -> [Double] {
        var y = c.Y / whiteY
        guard y > 0 else { return [0, 0, 0] }
        y = y > 216.0 / 24389 ? cbrt(y) : (24389.0 / 27 * y + 16) / 116
        let l = 116 * y - 16
        let (x0, y0) = (c.x, c.y), (xw, yw) = (white.x, white.y)
        let u = 4 * x0 / (-2 * x0 + 12 * x0 + 3), v = 9 * y0 / (-2 * x0 + 12 * y0 + 3)
        let uw = 4 * xw / (-2 * xw + 12 * xw + 3), vw = 9 * yw / (-2 * xw + 12 * yw + 3)
        return [l, 13 * l * (u - uw), 13 * l * (v - vw)]
    }

    /// ICtCp (BT.2100) as HCFR's ColorICtCp: XYZ scaled to cd/m², LMS (with BT.2020 cross-talk for
    /// the UHDTV references), PQ.
    static func ictcp(_ c: XYZ, scale: Double, standard: ColorStandard) -> [Double] {
        let (x, y, z) = (c.X * scale, c.Y * scale, c.Z * scale)
        var l, m, s: Double
        if [.uhdtv2020, .uhdtvP3in2020, .uhdtv709in2020].contains(standard) {
            l = 0.3592 * x + 0.6976 * y - 0.0358 * z
            m = -0.1922 * x + 1.1004 * y + 0.0755 * z
            s = 0.0070 * x + 0.0749 * y + 0.8434 * z
        } else {
            l = 0.4002 * x + 0.7076 * y - 0.0808 * z
            m = -0.2263 * x + 1.653 * y + 0.0457 * z
            s = 0.9182 * z
        }
        let lp = min(max(EOTF.pqInverse(min(max(l, 0), 10000) / 10000), 0), 1)
        let mp = min(max(EOTF.pqInverse(min(max(m, 0), 10000) / 10000), 0), 1)
        let sp = min(max(EOTF.pqInverse(min(max(s, 0), 10000) / 10000), 0), 1)
        return [0.5 * lp + 0.5 * mp, (6610 * lp - 13613 * mp + 7003 * sp) / 4096, (17933 * lp - 17390 * mp - 543 * sp) / 4096]
    }

    /// Distancia de cromaticidad al blanco de referencia ("delta xy" de HCFR).
    static func deltaxy(_ c: XYZ, ref: CalReference) -> Double {
        hypot(c.x - ref.white.x, c.y - ref.white.y)
    }

    /// Target luminance of a gray level with the reference's curve (power law, BT.1886, L*, HDR…).
    static func targetY(level: Double, whiteY: Double, blackY: Double?, ref: CalReference) -> Double {
        ref.targetY(signal: Reference.grayProp(level), whiteY: whiteY, blackY: blackY)
    }

    /// Gamma puntual (log(Y/Yblanco) / log(nivel)).
    static func pointGamma(_ c: XYZ, whiteY: Double, level: Double) -> Double? {
        guard level > 0, level < 100, whiteY > 0, c.Y > 0 else { return nil }
        return log(c.Y / whiteY) / log(Reference.grayProp(level))
    }

    /// Approximate color to paint the swatch (8-bit RGB, encoded with the reference gamma).
    static func displayRGB(_ c: XYZ, whiteY: Double, ref: CalReference) -> [Int] {
        guard whiteY > 0 else { return [0, 0, 0] }
        return rgb(c, ref: ref).map { v in
            let lin = min(max(v / whiteY, 0), 1)
            return Int((pow(lin, 1 / ref.gamma) * 255).rounded())
        }
    }
}
