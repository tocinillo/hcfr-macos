// HCFR for macOS
// Copyright (C) 2026 Jorge Velázquez
// Gamut coverage added in 2026: share of DCI-P3 and BT.2020 covered by the measured primaries,
// in CIE xy and CIE u'v' (the area of the measured triangle inside the reference triangle).
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import Foundation

enum GamutCoverage {
    typealias P = (x: Double, y: Double)

    static let bt709: [P] = [(0.640, 0.330), (0.300, 0.600), (0.150, 0.060)]
    static let dciP3: [P] = [(0.680, 0.320), (0.265, 0.690), (0.150, 0.060)]
    static let bt2020: [P] = [(0.708, 0.292), (0.170, 0.797), (0.131, 0.046)]

    struct Result {
        var bt709xy: Double, bt709uv: Double, p3xy: Double, p3uv: Double, bt2020xy: Double, bt2020uv: Double
    }

    static func uv(_ p: P) -> P {
        let d = -2 * p.x + 12 * p.y + 3
        return d > 0 ? (4 * p.x / d, 9 * p.y / d) : (0, 0)
    }

    static func signedArea(_ poly: [P]) -> Double {
        guard poly.count >= 3 else { return 0 }
        var s = 0.0
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    static func ccw(_ poly: [P]) -> [P] { signedArea(poly) < 0 ? poly.reversed() : poly }

    /// Sutherland–Hodgman: `subject` clipped by the convex polygon `clip` (both counter-clockwise).
    static func intersect(_ subject: [P], _ clip: [P]) -> [P] {
        var out = subject
        for i in clip.indices {
            let a = clip[i], b = clip[(i + 1) % clip.count]
            func inside(_ p: P) -> Bool { (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) >= 0 }
            func cross(_ p: P, _ q: P) -> P {
                let a1 = b.y - a.y, b1 = a.x - b.x, c1 = a1 * a.x + b1 * a.y
                let a2 = q.y - p.y, b2 = p.x - q.x, c2 = a2 * p.x + b2 * p.y
                let det = a1 * b2 - a2 * b1
                guard abs(det) > 1e-15 else { return p }
                return ((b2 * c1 - b1 * c2) / det, (a1 * c2 - a2 * c1) / det)
            }
            let input = out
            out = []
            guard !input.isEmpty else { break }
            var s = input[input.count - 1]
            for e in input {
                if inside(e) {
                    if !inside(s) { out.append(cross(s, e)) }
                    out.append(e)
                } else if inside(s) {
                    out.append(cross(s, e))
                }
                s = e
            }
        }
        return out
    }

    /// Share (0…1) of `target` covered by `measured`.
    static func coverage(_ measured: [P], _ target: [P], uvPlane: Bool) -> Double {
        let m = ccw(uvPlane ? measured.map(uv) : measured), t = ccw(uvPlane ? target.map(uv) : target)
        let at = abs(signedArea(t))
        guard at > 0 else { return 0 }
        return min(abs(signedArea(intersect(m, t))) / at, 1)
    }

    /// From the measured red, green and blue; nil if one is missing.
    static func result(red: XYZ?, green: XYZ?, blue: XYZ?) -> Result? {
        guard let r = red, let g = green, let b = blue, r.sum > 0, g.sum > 0, b.sum > 0 else { return nil }
        let m: [P] = [(r.x, r.y), (g.x, g.y), (b.x, b.y)]
        return Result(bt709xy: coverage(m, bt709, uvPlane: false), bt709uv: coverage(m, bt709, uvPlane: true),
                      p3xy: coverage(m, dciP3, uvPlane: false), p3uv: coverage(m, dciP3, uvPlane: true),
                      bt2020xy: coverage(m, bt2020, uvPlane: false), bt2020uv: coverage(m, bt2020, uvPlane: true))
    }

    /// "BT.709 100.0% xy · 100.0% u'v'   DCI-P3 98.1% xy · …   BT.2020 72.0% xy · …". In SDR the
    /// measured primaries are those of the SDR space, so DCI-P3 and BT.2020 are shown as "--".
    static func summary(red: XYZ?, green: XYZ?, blue: XYZ?, sdr: Bool = false) -> String? {
        guard let c = result(red: red, green: green, blue: blue) else { return nil }
        func pair(_ xy: Double, _ uv: Double) -> String {
            sdr ? "-- xy · -- u'v'" : String(format: "%.1f%% xy · %.1f%% u'v'", xy * 100, uv * 100)
        }
        return String(format: "BT.709 %.1f%% xy · %.1f%% u'v'", c.bt709xy * 100, c.bt709uv * 100)
            + "    DCI-P3 " + pair(c.p3xy, c.p3uv) + "    BT.2020 " + pair(c.bt2020xy, c.bt2020uv)
    }
}
