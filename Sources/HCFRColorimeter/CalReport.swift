// HCFR for macOS
// Copyright (C) 2026 Jorge Velázquez
// Calibration report in the layout of calibration software reports, added in 2026: one A4 page per
// measurement (pre / post), with the gray scale (ΔE 2000 per level, RGB balance, EOTF) and the color
// space (ΔE 2000 per color, CIE 1976 u'v' diagram) and the gamut coverage.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI
import Charts

/// Everything one report page shows, taken from the session when the measure ends.
struct CalReportPage {
    struct Gray: Identifiable { let level: Double; let dE: Double?; let balance: [Double]?; let eotf: Double?; let eotfTarget: Double?; var id: Double { level } }
    struct Patch: Identifiable { let id: Int; let name: String; let dE: Double?; let swatch: Color; let measured: (Double, Double)?; let target: (Double, Double)? }

    var title: String
    var date = Date()
    var device: String
    var meter: String
    var hdr: Bool
    var gammaFormula: String
    var grayAvg: Double?, grayMax: Double?, cctAvg: Double?, minLum: Double?, maxLum: Double?, totalGamma: Double?
    var gray: [Gray] = []
    var gamut: String
    var colorAvg: Double?, colorMax: Double?
    var patches: [Patch] = []
    var coverage: GamutCoverage.Result?
    var white: (Double, Double)

    @MainActor
    init(_ s: Session, title: String, device: String) {
        self.title = title
        self.device = device
        meter = s.meter?.name ?? ""
        let mode = s.prefs.mode
        hdr = mode == .st2084
        switch mode {
        case .st2084: gammaFormula = "ST 2084 HDR (PQ)"
        case .bt1886: gammaFormula = String(format: "BT.1886 %.1f", s.gamma)
        default: gammaFormula = String(format: "Power %.2g", s.gamma)
        }
        let rs = s.results.filter { $0.xyz != nil }
        let des = rs.compactMap(\.deltaE)
        grayAvg = des.isEmpty ? nil : des.reduce(0, +) / Double(des.count)
        grayMax = des.max()
        let ccts = rs.filter { $0.level > 0 }.compactMap(\.cct)
        cctAvg = ccts.isEmpty ? nil : ccts.reduce(0, +) / Double(ccts.count)
        minLum = rs.first { $0.level == 0 }?.xyz?.Y
        maxLum = rs.first { $0.level == 100 }?.xyz?.Y
        totalGamma = hdr ? nil : s.averageGamma
        let wY = maxLum ?? 1
        let isHDR = hdr
        gray = rs.map { r in
            func enc(_ y: Double?) -> Double? {
                guard let y else { return nil }
                return isHDR ? EOTF.pqInverse(min(max(y, 0) / 10000, 1)) : min(max(y / max(wY, 1e-6), 0), 1.1)
            }
            return Gray(level: r.level, dE: r.deltaE, balance: r.balance, eotf: enc(r.xyz?.Y), eotfTarget: enc(r.targetY))
        }
        gamut = "\(s.white.rawValue), \(s.standard.shortName)" + (hdr ? " · HDR10" : "")
        white = (s.ref.white.x, s.ref.white.y)
        // Colors: the Color Checker when measured (pre / post measures), else the primaries /
        // secondaries. The R, G, B read only for the gamut coverage are not a color check.
        var list: [Patch] = []
        for r in s.seriesResults(.colorChecker) where r.xyz != nil {
            list.append(Patch(id: r.index, name: r.name, dE: r.deltaE, swatch: Self.swatch(r.referenceRGB.map { Double($0) / 255 }),
                              measured: r.xyz.map { ($0.x, $0.y) }, target: r.reference.map { ($0.x, $0.y) }))
        }
        let pr = s.patchResults.filter { $0.xyz != nil }
        if list.isEmpty && pr.count > 1 {
            for (i, p) in pr.enumerated() {
                list.append(Patch(id: i, name: tr(p.patch.rawValue), dE: p.deltaE, swatch: Self.swatch(p.patch.rgb),
                                  measured: p.xyz.map { ($0.x, $0.y) }, target: (p.reference.x, p.reference.y)))
            }
        }
        patches = list
        let pd = list.compactMap(\.dE)
        colorAvg = pd.isEmpty ? nil : pd.reduce(0, +) / Double(pd.count)
        colorMax = pd.max()
        coverage = GamutCoverage.result(red: s.colorMeasurements[.red], green: s.colorMeasurements[.green], blue: s.colorMeasurements[.blue])
    }

    static func swatch(_ rgb: [Double]) -> Color {
        Color(.sRGB, red: rgb.first ?? 0, green: rgb.count > 1 ? rgb[1] : 0, blue: rgb.count > 2 ? rgb[2] : 0, opacity: 1)
    }
}

@MainActor
enum CalReport {
    /// A4 pages (595 × 842 pt), one per page given, as one PDF.
    static func makePDF(_ pages: [CalReportPage]) -> Data? {
        guard !pages.isEmpty else { return nil }
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for p in pages {
            let r = ImageRenderer(content: CalReportPageView(page: p).environment(\.colorScheme, .light).frame(width: 595, height: 842))
            ctx.beginPDFPage(nil)
            r.render { _, draw in draw(ctx) }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    /// Save panel for the report.
    static func save(_ pages: [CalReportPage], name: String, session: Session) {
        guard let pdf = makePDF(pages) else { session.errorMessage = tr("Could not create the report."); return }
        let panel = NSSavePanel()
        panel.title = tr("Create PDF Report")
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = name + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pdf.write(to: url)
            session.status = "Report saved: \(url.lastPathComponent)"
        } catch {
            session.errorMessage = "Could not save the report: \(error.localizedDescription)"
        }
    }
}

private func f(_ v: Double?, _ d: Int = 2) -> String {
    guard let v, v.isFinite else { return "—" }
    return String(format: "%.\(d)f", v)
}

private struct CalReportPageView: View {
    let page: CalReportPage
    private let ink = Color(white: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(tr(page.title)).font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity)
            section("Grayscale")
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    stat("Gamma Formula", page.gammaFormula)
                    stat("Grayscale Avg", f(page.grayAvg))
                    stat("Grayscale Max", f(page.grayMax))
                }
                VStack(alignment: .leading, spacing: 2) {
                    stat("CCT Avg", f(page.cctAvg, 0) + " K")
                    stat("Min Lum", f(page.minLum, 4) + " cd/m²")
                    stat("Max Lum", f(page.maxLum, 1) + " cd/m²")
                    if let g = page.totalGamma { stat("Total Gamma", f(g)) }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 6) {
                    box("ΔE 2000") { grayDE }.frame(height: 120)
                    box("RGB Balance") { balance }.frame(height: 120)
                }
                box("EOTF") { eotf }.frame(height: 246)
            }
            section("Color Space")
            HStack(spacing: 18) {
                stat("Color Space Avg", f(page.colorAvg))
                stat("Color Space Max", f(page.colorMax))
                stat("Color Gamut", page.gamut)
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 6) {
                    box("ΔE 2000") { colorDE }.frame(height: 160)
                    coverageTable
                }
                box("CIE 1976 u'v'") { cie }.frame(height: 246)
            }
            Spacer(minLength: 0)
            Text("HCFR for macOS \(AboutPanel.version) — " + tr("Measured with %@", page.meter.isEmpty ? "—" : page.meter))
                .font(.system(size: 7)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(ink)
        .padding(28)
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 8) {
                RGBCirclesIcon(size: 30)
                    .padding(4).background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.1)))
                VStack(alignment: .leading, spacing: 0) {
                    Text("HCFR for macOS").font(.system(size: 18, weight: .bold))
                    Text(page.device).font(.system(size: 9))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(tr("Measurement Date: %@", page.date.formatted(date: .numeric, time: .shortened))).font(.system(size: 9))
            }
        }
    }

    private func section(_ t: String) -> some View {
        HStack {
            Rectangle().fill(Color(white: 0.8)).frame(height: 1)
            Text(tr(t)).font(.system(size: 14, weight: .semibold)).fixedSize()
            Rectangle().fill(Color(white: 0.8)).frame(height: 1)
        }
    }

    private func stat(_ name: String, _ value: String) -> some View {
        Text(tr(name) + ": " + value).font(.system(size: 9.5))
    }

    private func box<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 2) {
            Text(tr(title)).font(.system(size: 8))
            c().padding(.trailing, 4)
        }
        .padding(4)
        .overlay(Rectangle().stroke(Color(white: 0.7), lineWidth: 0.5))
    }

    private var grayDE: some View {
        Chart(page.gray.filter { $0.dE != nil }) { g in
            BarMark(x: .value("%", Int(g.level)), y: .value("ΔE", min(g.dE ?? 0, 15)), width: .fixed(5))
                .foregroundStyle(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
        }
        .chartYScale(domain: 0...15).chartXScale(domain: -3...103)
        .chartXAxis { AxisMarks(values: .stride(by: 10)) { AxisGridLine(); AxisValueLabel().font(.system(size: 6)) } }
        .chartYAxis { AxisMarks(position: .leading, values: [0, 5, 10, 15]) { AxisGridLine(); AxisValueLabel().font(.system(size: 6)) } }
    }

    private var balance: some View {
        Chart {
            ForEach(Array(["Red", "Green", "Blue"].enumerated()), id: \.0) { c, name in
                ForEach(page.gray.filter { $0.balance != nil && $0.level > 0 }) { g in
                    LineMark(x: .value("%", g.level), y: .value("%", min(max(g.balance![c], 80), 120)), series: .value("c", name))
                        .foregroundStyle([Color.red, Color.green, Color.blue][c]).lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
        }
        .chartYScale(domain: 80...120).chartXScale(domain: 0...100)
        .chartXAxis { AxisMarks(values: .stride(by: 10)) { AxisGridLine(); AxisValueLabel().font(.system(size: 6)) } }
        .chartYAxis { AxisMarks(position: .leading, values: [80, 90, 100, 110, 120]) { AxisGridLine(); AxisValueLabel().font(.system(size: 6)) } }
    }

    private var eotf: some View {
        Chart {
            ForEach(page.gray.filter { $0.eotfTarget != nil }) { g in
                LineMark(x: .value("%", g.level), y: .value("t", g.eotfTarget!), series: .value("s", "Target"))
                    .foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(page.gray.filter { $0.eotf != nil }) { g in
                LineMark(x: .value("%", g.level), y: .value("m", g.eotf!), series: .value("s", "Measured"))
                    .foregroundStyle(Color(white: 0.15)).lineStyle(StrokeStyle(lineWidth: 1.2))
            }
        }
        .chartYScale(domain: 0...1).chartXScale(domain: 0...100)
        .chartXAxis { AxisMarks(values: .stride(by: 10)) { AxisGridLine(); AxisValueLabel().font(.system(size: 6)) } }
        .chartYAxis { AxisMarks(position: .leading, values: .stride(by: 0.1)) { AxisGridLine(); AxisValueLabel().font(.system(size: 6)) } }
    }

    private var colorDE: some View {
        Chart(page.patches) { p in
            BarMark(x: .value("c", p.name), y: .value("ΔE", min(p.dE ?? 0, 15)))
                .foregroundStyle(p.swatch)
        }
        .chartYScale(domain: 0...15)
        .chartXAxis { AxisMarks { AxisValueLabel().font(.system(size: 5)) } }
        .chartYAxis { AxisMarks(position: .leading, values: [0, 2, 4, 6, 8, 10, 12, 14]) { AxisGridLine(); AxisValueLabel().font(.system(size: 6)) } }
    }

    private var coverageTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 2) {
            GridRow {
                Text(tr("Gamut coverage")).font(.system(size: 8, weight: .semibold)).gridColumnAlignment(.leading)
                Text("CIE xy").font(.system(size: 8))
                Text("CIE u'v'").font(.system(size: 8))
            }
            if let c = page.coverage {
                ForEach([("BT.709", c.bt709xy, c.bt709uv, true), ("DCI-P3", c.p3xy, c.p3uv, page.hdr),
                         ("BT.2020", c.bt2020xy, c.bt2020uv, page.hdr)], id: \.0) { n, xy, uv, shown in
                    GridRow {
                        Text(n).font(.system(size: 8))
                        Text(shown ? String(format: "%.1f %%", xy * 100) : "--").font(.system(size: 8).monospacedDigit())
                        Text(shown ? String(format: "%.1f %%", uv * 100) : "--").font(.system(size: 8).monospacedDigit())
                    }
                }
            } else {
                GridRow { Text(tr("Measure red, green and blue for the coverage.")).font(.system(size: 7)).gridCellColumns(3) }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Color(white: 0.7), lineWidth: 0.5))
    }

    private var cie: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let plane = CIEPlane(uv: true)
            Canvas { ctx, size in
                if let img = CIEBackground.image(width: Int(size.width * 2), height: Int(size.height * 2), plane: plane, white: page.white, light: true) {
                    ctx.draw(Image(decorative: img, scale: 2), in: rect)
                }
                for p in page.patches {
                    if let t = p.target {
                        let q = plane.position(xy: t, in: rect)
                        ctx.stroke(Path(CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)), with: .color(.white), lineWidth: 1.2)
                    }
                    if let m = p.measured {
                        let q = plane.position(xy: m, in: rect)
                        let c = Path(ellipseIn: CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5))
                        ctx.fill(c, with: .color(p.swatch))
                        ctx.stroke(c, with: .color(.black), lineWidth: 0.6)
                    }
                }
            }
        }
    }
}
