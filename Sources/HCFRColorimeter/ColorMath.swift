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

    var id: String { rawValue }

    var xy: (x: Double, y: Double) {
        switch self {
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
        case .dci: return Int(ColorMath.cct(XYZ.fromxyY(x: x, y: y, Y: 1))!.rounded())
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

    var id: String { rawValue }

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
        }
    }

    /// sRGB uses the sRGB tone curve instead of a power law (as HCFR does).
    var usesSRGBCurve: Bool { self == .sRGB }
}

/// Measurement reference: color space standard, white point and power law gamma.
struct CalReference: Equatable {
    var standard: ColorStandard = .sdtv
    var white: WhitePoint = .d65
    var gamma: Double = 2.3

    /// Linear RGB -> XYZ matrix normalised so RGB(1,1,1) = white with Y = 1.
    var rgbToXYZ: Mat3 {
        let p = standard.primaries.map { XYZ.fromxyY(x: $0.x, y: $0.y, Y: 1) }
        let raw = Mat3.columns([p[0].X, p[0].Y, p[0].Z], [p[1].X, p[1].Y, p[1].Z], [p[2].X, p[2].Y, p[2].Z])
        let w = white.xyz(Y: 1)
        let s = raw.inverse.apply([w.X, w.Y, w.Z])
        return Mat3(m: raw.m.map { row in [row[0] * s[0], row[1] * s[1], row[2] * s[2]] })
    }

    /// Relative target luminance for a signal level (0...1).
    func eotf(_ v: Double) -> Double {
        if standard.usesSRGBCurve {
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return pow(v, gamma)
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
        (floor(level / 100 * 219 + 16.5) - 16) / 219
    }
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

    /// Gray scale ΔE in "Absolute Y w/o gamma" mode: the reference is the chosen white at the
    /// same relative luminance as the measurement, so it only measures the color error.
    static func grayDeltaE(_ c: XYZ, whiteY: Double, ref: CalReference) -> Double? {
        guard whiteY > 0, c.Y > 0 else { return nil }
        let target = ref.white.xyz(Y: c.Y / whiteY)
        return deltaE2000(ref: lab(target, whiteY: 1, white: ref.white), measured: lab(c, whiteY: whiteY, white: ref.white))
    }

    /// Distancia de cromaticidad al blanco de referencia ("delta xy" de HCFR).
    static func deltaxy(_ c: XYZ, ref: CalReference) -> Double {
        hypot(c.x - ref.white.x, c.y - ref.white.y)
    }

    /// Target luminance: white Y × EOTF(level) (power law gamma, or sRGB curve).
    static func targetY(level: Double, whiteY: Double, ref: CalReference) -> Double {
        whiteY * ref.eotf(Reference.grayProp(level))
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
