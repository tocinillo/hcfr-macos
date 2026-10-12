// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// CIE diagram added in 2026, after HCFR's CIE chart view (Views/CIEChartView.cpp).
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI

/// CIE 1931 2° chromaticity of the spectral colors, 380–700 nm every 5 nm (computed from the
/// CIE 1931 standard observer color matching functions).
enum SpectralLocus {
    static let points: [(nm: Int, x: Double, y: Double)] = [
        (380, 0.17411, 0.00496),
        (385, 0.17401, 0.00498),
        (390, 0.17380, 0.00492),
        (395, 0.17356, 0.00492),
        (400, 0.17334, 0.00480),
        (405, 0.17302, 0.00478),
        (410, 0.17258, 0.00480),
        (415, 0.17209, 0.00483),
        (420, 0.17141, 0.00510),
        (425, 0.17030, 0.00579),
        (430, 0.16888, 0.00690),
        (435, 0.16690, 0.00856),
        (440, 0.16441, 0.01086),
        (445, 0.16110, 0.01379),
        (450, 0.15664, 0.01770),
        (455, 0.15099, 0.02274),
        (460, 0.14396, 0.02970),
        (465, 0.13550, 0.03988),
        (470, 0.12412, 0.05780),
        (475, 0.10959, 0.08684),
        (480, 0.09129, 0.13270),
        (485, 0.06871, 0.20072),
        (490, 0.04539, 0.29498),
        (495, 0.02346, 0.41270),
        (500, 0.00817, 0.53842),
        (505, 0.00386, 0.65482),
        (510, 0.01387, 0.75019),
        (515, 0.03885, 0.81202),
        (520, 0.07430, 0.83380),
        (525, 0.11416, 0.82621),
        (530, 0.15472, 0.80586),
        (535, 0.19288, 0.78163),
        (540, 0.22962, 0.75433),
        (545, 0.26578, 0.72432),
        (550, 0.30160, 0.69231),
        (555, 0.33736, 0.65885),
        (560, 0.37310, 0.62445),
        (565, 0.40874, 0.58961),
        (570, 0.44406, 0.55471),
        (575, 0.47877, 0.52020),
        (580, 0.51249, 0.48659),
        (585, 0.54479, 0.45443),
        (590, 0.57515, 0.42423),
        (595, 0.60293, 0.39650),
        (600, 0.62704, 0.37249),
        (605, 0.64823, 0.35139),
        (610, 0.66576, 0.33401),
        (615, 0.68008, 0.31975),
        (620, 0.69150, 0.30834),
        (625, 0.70061, 0.29930),
        (630, 0.70792, 0.29203),
        (635, 0.71403, 0.28593),
        (640, 0.71903, 0.28093),
        (645, 0.72303, 0.27695),
        (650, 0.72599, 0.27401),
        (655, 0.72827, 0.27173),
        (660, 0.72997, 0.27003),
        (665, 0.73109, 0.26891),
        (670, 0.73199, 0.26801),
        (675, 0.73272, 0.26728),
        (680, 0.73342, 0.26658),
        (685, 0.73405, 0.26595),
        (690, 0.73439, 0.26561),
        (695, 0.73459, 0.26541),
        (700, 0.73469, 0.26531)
    ]
}

/// Chromaticity plane of the diagram: CIE 1931 xy or CIE 1976 u'v'.
struct CIEPlane: Equatable {
    var uv: Bool

    /// Visible range, as HCFR's chart (axes from -0.075 and -0.05).
    var xRange: ClosedRange<Double> { uv ? -0.075...0.725 : -0.075...0.825 }
    var yRange: ClosedRange<Double> { uv ? -0.05...0.75 : -0.05...0.95 }
    var axisNames: (String, String) { uv ? ("u'", "v'") : ("x", "y") }

    /// xy -> plane coordinates.
    func project(_ x: Double, _ y: Double) -> CGPoint {
        guard uv else { return CGPoint(x: x, y: y) }
        let d = -2 * x + 12 * y + 3
        return d == 0 ? .zero : CGPoint(x: 4 * x / d, y: 9 * y / d)
    }

    /// Plane coordinates -> xy.
    func unproject(_ p: CGPoint) -> (x: Double, y: Double) {
        guard uv else { return (p.x, p.y) }
        let d = 6 * p.x - 16 * p.y + 12
        return d == 0 ? (0, 0) : (9 * p.x / d, 4 * p.y / d)
    }
}

/// Colored horseshoe, drawn once per size / plane / standard and kept (the pixel loop is slow).
@MainActor
private enum CIEBackground {
    private static var cache: [String: CGImage] = [:]

    static func image(width: Int, height: Int, plane: CIEPlane, gamut: [(x: Double, y: Double)]) -> CGImage? {
        let key = "\(width)x\(height)-\(plane.uv)-\(gamut.map { "\($0.x),\($0.y)" })"
        if let img = cache[key] { return img }
        guard width > 0, height > 0 else { return nil }
        let locus = SpectralLocus.points.map { plane.project($0.x, $0.y) }
        let tri = gamut.map { plane.project($0.x, $0.y) }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let xr = plane.xRange, yr = plane.yRange
        for py in 0..<height {
            let v = yr.upperBound - (Double(py) + 0.5) / Double(height) * (yr.upperBound - yr.lowerBound)
            for px in 0..<width {
                let u = xr.lowerBound + (Double(px) + 0.5) / Double(width) * (xr.upperBound - xr.lowerBound)
                let p = CGPoint(x: u, y: v)
                guard inside(p, locus) else { continue }
                let (x, y) = plane.unproject(p)
                guard y > 0 else { continue }
                // xyY (Y = 1) -> linear sRGB, desaturated into gamut and normalised to the brightest channel
                let X = x / y, Z = (1 - x - y) / y
                var r = 3.2406 * X - 1.5372 - 0.4986 * Z
                var g = -0.9689 * X + 1.8758 + 0.0415 * Z
                var b = 0.0557 * X - 0.2040 + 1.0570 * Z
                let lo = min(r, g, b)
                if lo < 0 { r -= lo; g -= lo; b -= lo }
                let hi = max(r, g, b)
                guard hi > 0 else { continue }
                // HCFR lightens the reference gamut and dims the rest
                let k = (tri.count == 3 && inside(p, tri)) ? 1.0 : 0.45
                func enc(_ c: Double) -> UInt8 {
                    let l = c / hi
                    let s = l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055
                    return UInt8(max(0, min(255, (s * k * 255).rounded())))
                }
                let i = (py * width + px) * 4
                pixels[i] = enc(r); pixels[i + 1] = enc(g); pixels[i + 2] = enc(b); pixels[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let img = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        if cache.count > 12 { cache.removeAll() }
        cache[key] = img
        return img
    }

    /// Point in polygon (even-odd rule).
    private static func inside(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        var c = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
            j = i
        }
        return c
    }
}

/// HCFR's CIE chart: spectral locus, reference gamut and white point, measured primaries /
/// secondaries (and their gamut) and the gray scale points.
struct CIEChart: View {
    @ObservedObject var session: Session
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Picker("Plane", selection: $session.cieUV) {
                    Text("CIE xy").tag(false)
                    Text("CIE u'v'").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Toggle("Gray scale", isOn: $session.cieShowGrays).toggleStyle(.checkbox)
                Spacer()
                Text(legend).font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                chart(size: geo.size)
            }
        }
    }

    private var legend: String {
        "Reference: \(session.standard.shortName), \(session.white.rawValue)"
    }

    private func chart(size: CGSize) -> some View {
        let plane = CIEPlane(uv: session.cieUV)
        let xr = plane.xRange, yr = plane.yRange
        // Same scale on both axes, centered
        let k = min(size.width / (xr.upperBound - xr.lowerBound), size.height / (yr.upperBound - yr.lowerBound))
        let w = (xr.upperBound - xr.lowerBound) * k, h = (yr.upperBound - yr.lowerBound) * k
        let origin = CGPoint(x: (size.width - w) / 2, y: (size.height - h) / 2)
        let plot = CGRect(origin: origin, size: CGSize(width: w, height: h))
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            let p = plane.project(x, y)
            return CGPoint(x: plot.minX + (p.x - xr.lowerBound) * k, y: plot.maxY - (p.y - yr.lowerBound) * k)
        }
        let refPrimaries = session.standard.primaries
        let bg = CIEBackground.image(width: Int(w * displayScale), height: Int(h * displayScale),
                                     plane: plane, gamut: refPrimaries)
        let patches = session.patchResults
        let grays = session.cieShowGrays ? session.results.filter { $0.xyz != nil && $0.level > 0 } : []
        let selectedPatch = session.view == .primariesSecondaries ? session.selectedPatch : nil
        let selectedLevel = session.view == .grayScale ? session.selectedLevel : nil

        return Canvas { ctx, _ in
            ctx.fill(Path(plot), with: .color(Color(white: 0.08)))
            if let bg { ctx.draw(Image(decorative: bg, scale: displayScale), in: plot) }

            // Grid every 0.1
            var grid = Path()
            for i in stride(from: ceil(xr.lowerBound * 10), through: xr.upperBound * 10, by: 1) {
                let x = plot.minX + (i / 10 - xr.lowerBound) * k
                grid.move(to: CGPoint(x: x, y: plot.minY)); grid.addLine(to: CGPoint(x: x, y: plot.maxY))
                if i > 0 && x < plot.maxX - 26 {
                    ctx.draw(Text(String(format: "%.1f", i / 10)).font(.system(size: 9)).foregroundColor(.white.opacity(0.7)),
                             at: CGPoint(x: x + 2, y: plot.maxY - 2), anchor: .bottomLeading)
                }
            }
            for i in stride(from: ceil(yr.lowerBound * 10), through: yr.upperBound * 10, by: 1) {
                let y = plot.maxY - (i / 10 - yr.lowerBound) * k
                grid.move(to: CGPoint(x: plot.minX, y: y)); grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                if i > 0 && y > plot.minY + 22 {
                    ctx.draw(Text(String(format: "%.1f", i / 10)).font(.system(size: 9)).foregroundColor(.white.opacity(0.7)),
                             at: CGPoint(x: plot.minX + 2, y: y - 1), anchor: .bottomLeading)
                }
            }
            ctx.stroke(grid, with: .color(.white.opacity(0.16)), lineWidth: 0.5)
            ctx.draw(Text(plane.axisNames.0).font(.caption.bold()).foregroundColor(.white),
                     at: CGPoint(x: plot.maxX - 6, y: plot.maxY - 3), anchor: .bottomTrailing)
            ctx.draw(Text(plane.axisNames.1).font(.caption.bold()).foregroundColor(.white),
                     at: CGPoint(x: plot.minX + 6, y: plot.minY + 4), anchor: .topLeading)

            // Spectral locus outline with a few wavelengths
            var locus = Path()
            for (i, s) in SpectralLocus.points.enumerated() {
                i == 0 ? locus.move(to: pt(s.x, s.y)) : locus.addLine(to: pt(s.x, s.y))
            }
            locus.closeSubpath()
            ctx.stroke(locus, with: .color(.white.opacity(0.55)), lineWidth: 1)
            for s in SpectralLocus.points where [460, 480, 500, 520, 540, 560, 580, 600, 620].contains(s.nm) {
                let p = pt(s.x, s.y)
                ctx.draw(Text("\(s.nm)").font(.system(size: 8)).foregroundColor(.white.opacity(0.6)),
                         at: CGPoint(x: p.x + (s.nm < 520 ? -4 : 4), y: p.y), anchor: s.nm < 520 ? .trailing : .leading)
            }

            // Reference gamut and white point
            var refTri = Path()
            refTri.addLines(refPrimaries.map { pt($0.x, $0.y) })
            refTri.closeSubpath()
            ctx.stroke(refTri, with: .color(.white), lineWidth: 1.2)
            for p in patches where p.patch != .white {
                let c = pt(p.reference.x, p.reference.y)
                ctx.stroke(Path(CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.white), lineWidth: 1.2)
            }
            let wp = pt(session.white.x, session.white.y)
            var cross = Path()
            cross.move(to: CGPoint(x: wp.x - 6, y: wp.y)); cross.addLine(to: CGPoint(x: wp.x + 6, y: wp.y))
            cross.move(to: CGPoint(x: wp.x, y: wp.y - 6)); cross.addLine(to: CGPoint(x: wp.x, y: wp.y + 6))
            ctx.stroke(cross, with: .color(.white), lineWidth: 1.2)

            // Measured gamut (R, G, B measured)
            let measured: [PatchColor: CGPoint] = Dictionary(uniqueKeysWithValues: patches.compactMap { p in
                p.xyz.flatMap { $0.Y > 0 ? (p.patch, pt($0.x, $0.y)) : nil }
            })
            if let r = measured[.red], let g = measured[.green], let b = measured[.blue] {
                var tri = Path()
                tri.addLines([r, g, b]); tri.closeSubpath()
                ctx.stroke(tri, with: .color(.yellow), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
            }

            // Gray scale points (white is the 100% one)
            for g in grays {
                guard let xyz = g.xyz else { continue }
                let p = pt(xyz.x, xyz.y)
                let sel = g.level == selectedLevel
                let r: CGFloat = sel ? 5 : 3.5
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                ctx.fill(dot, with: .color(sel ? .orange : Color(white: 0.9)))
                ctx.stroke(dot, with: .color(.black), lineWidth: 1)
                if sel { ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)), with: .color(.orange), lineWidth: 1.5) }
            }

            // Measured primaries / secondaries: line from the target and a dot
            for p in patches where p.patch != .white {
                guard let m = measured[p.patch] else { continue }
                let target = pt(p.reference.x, p.reference.y)
                var line = Path()
                line.move(to: target); line.addLine(to: m)
                ctx.stroke(line, with: .color(.white.opacity(0.7)), lineWidth: 1)
                let sel = p.patch == selectedPatch
                let r: CGFloat = sel ? 6 : 4.5
                ctx.fill(Path(ellipseIn: CGRect(x: m.x - r, y: m.y - r, width: 2 * r, height: 2 * r)), with: .color(Self.dotColor(p.patch)))
                ctx.stroke(Path(ellipseIn: CGRect(x: m.x - r, y: m.y - r, width: 2 * r, height: 2 * r)), with: .color(sel ? .orange : .black), lineWidth: sel ? 2 : 1)
            }
            if session.view == .primariesSecondaries, let w = measured[.white] {
                let sel = selectedPatch == .white
                ctx.fill(Path(ellipseIn: CGRect(x: w.x - 4, y: w.y - 4, width: 8, height: 8)), with: .color(.white))
                ctx.stroke(Path(ellipseIn: CGRect(x: w.x - 4, y: w.y - 4, width: 8, height: 8)), with: .color(sel ? .orange : .black), lineWidth: sel ? 2 : 1)
            }
            ctx.stroke(Path(plot), with: .color(.white.opacity(0.3)), lineWidth: 1)
        }
    }

    private static func dotColor(_ p: PatchColor) -> Color {
        switch p {
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .yellow: return .yellow
        case .cyan: return .cyan
        case .magenta: return Color(red: 1, green: 0, blue: 1)
        case .white: return .white
        }
    }
}

/// Information panel: the graph chosen in its selector (more of HCFR's graphs to come).
struct InformationPanel: View {
    @ObservedObject var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Information").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Picker("Graph", selection: $session.infoGraph) {
                    ForEach(InfoGraph.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            switch session.infoGraph {
            case .grayBalance: GrayScaleChart(session: session)
            case .cie: CIEChart(session: session)
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }
}
