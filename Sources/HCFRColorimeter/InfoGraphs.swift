// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Information panel graphs added in 2026, after HCFR's graph views (Views/LuminanceHistoView.cpp,
// GammaHistoView.cpp, ColorTempHistoView.cpp, RGBHistoView.cpp, CIEChartView.cpp).
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI
import Charts
import UniformTypeIdentifiers

/// Information panel: HCFR's graph selector and the chosen graph.
struct InformationPanel: View {
    @ObservedObject var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker("Information", selection: $session.infoGraph) {
                    ForEach(InfoGraph.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                GraphOptionsMenu(session: session, graph: shownGraph)
                Spacer()
                Button {
                    GraphExport.save(graph(shownGraph), name: shownGraph.rawValue, session: session)
                } label: { Image(systemName: "square.and.arrow.down") }
                .buttonStyle(.borderless)
                .help("Save this graph as a PNG image (HCFR's graph Save…)")
            }
            graph(shownGraph)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }

    private var shownGraph: InfoGraph { session.infoGraph == .auto ? autoGraph : session.infoGraph }

    /// Auto: the graph that goes with the table shown.
    private var autoGraph: InfoGraph {
        switch session.view {
        case .grayScale: return .rgbLevels
        case .nearBlack, .nearWhite: return .nearBlackWhite
        case .freeMeasures: return .freeHistogram
        case .contrast: return .summary
        default: return .cie
        }
    }

    @ViewBuilder
    private func graph(_ g: InfoGraph) -> some View {
        switch g {
        case .freeHistogram: FreeMeasuresChart(session: session)
        case .spectrum: SpectrumChart(session: session)
        case .nearBlackWhite:
            HStack(spacing: 8) {
                NearScaleChart(session: session, view: .nearBlack)
                NearScaleChart(session: session, view: .nearWhite)
            }
        case .saturationShift:
            HStack(spacing: 8) {
                SaturationChart(session: session, shift: false)
                SaturationChart(session: session, shift: true)
            }
        case .summary: SummaryView(session: session)
        case .targetCIE:
            HStack(spacing: 8) {
                BigTarget(session: session).frame(width: 240)
                CIEChart(session: session, compact: true)
            }
        case .luminanceGamma:
            HStack(spacing: 8) {
                LuminanceChart(session: session)
                GammaChart(session: session)
            }
        case .rgbGamma:
            HStack(spacing: 8) {
                GrayScaleChart(session: session)
                GammaChart(session: session)
            }
        case .rgbLevels, .auto: GrayScaleChart(session: session)
        case .colorTemperature: ColorTempChart(session: session)
        case .cie: CIEChart(session: session)
        case .targetRGBGamma:
            HStack(spacing: 8) {
                BigTarget(session: session).frame(width: 240)
                GrayScaleChart(session: session)
                GammaChart(session: session)
            }
        }
    }
}

// MARK: - Shared look (dark plot on a gray ramp, yellow title, as HCFR's graphs)

private struct DarkGraph<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.callout.bold()).foregroundStyle(.yellow)
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            content.frame(maxHeight: .infinity)
        }
        .padding(6)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

let grayRamp = LinearGradient(colors: [Color(white: 0.12), Color(white: 0.95)], startPoint: .leading, endPoint: .trailing)

/// HCFR's "10% White … 90% White" axis; every other label when the graph is narrow.
func whiteLevelAxis(width: CGFloat) -> some AxisContent {
    let step = width < 760 ? 20 : 10
    return AxisMarks(values: Array(stride(from: 10, through: 90, by: step))) { v in
        AxisGridLine().foregroundStyle(.teal.opacity(0.5))
        AxisValueLabel { Text("\(v.as(Int.self) ?? 0)% White").font(.caption2.monospaced()).foregroundStyle(.white).fixedSize() }
    }
}

private func levelAxis(step: Int = 10) -> some AxisContent {
    AxisMarks(values: Array(stride(from: step, through: 100, by: step))) { v in
        AxisGridLine().foregroundStyle(.teal.opacity(0.5))
        AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.caption2.monospaced()).foregroundStyle(.white) }
    }
}

private struct LevelPoint: Identifiable {
    let level: Double
    let value: Double
    let series: String
    var id: String { "\(series)-\(level)" }
}

// MARK: - Luminance

/// Luminance in % of white against the target curve (HCFR "Luminance").
struct LuminanceChart: View {
    @ObservedObject var session: Session

    var body: some View {
        let mode = session.graphOptions.luminance
        let white = session.whiteY
        let w = white ?? session.prefs.targetMaxL
        let shown = { (rel: Double) in Self.value(rel, mode: mode, white: w) }
        let measured: [LevelPoint] = white.map { w in
            session.results.compactMap { r in r.xyz.map { LevelPoint(level: r.level, value: shown($0.Y / w), series: "Measured") } }
        } ?? []
        let target = stride(from: 0.0, through: 100, by: 2.5).map {
            LevelPoint(level: $0, value: shown(session.targetRelative(level: $0)), series: "Reference")
        }
        let compared: [LevelPoint] = session.refData.map { d in
            d.gray.keys.sorted().compactMap { l in d.gray[l].map { LevelPoint(level: l, value: shown($0.Y / d.whiteY), series: "Compared") } }
        } ?? []
        let top: Double = mode == .absolute ? max(w, measured.map(\.value).max() ?? 0) * 1.05 : mode == .log ? 2.05 : 105
        let bottom: Double = mode == .log ? -2 : 0
        DarkGraph(title: mode == .relative ? "Luminance" : "Luminance — \(mode.rawValue)" + (mode == .absolute ? " (cd/m²)" : "")) {
            Chart {
                ForEach(target) { p in
                    LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("S", p.series))
                        .foregroundStyle(.white.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                ForEach(compared) { p in
                    LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("S", p.series))
                        .foregroundStyle(.cyan.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
                ForEach(measured) { p in
                    LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("S", p.series))
                        .foregroundStyle(.yellow).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Level", p.level), y: .value("%", p.value)).foregroundStyle(.yellow).symbolSize(24)
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: bottom...top)
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel {
                    let d = v.as(Double.self) ?? 0
                    Text(mode == .relative ? "\(Int(d))%" : mode == .log ? String(format: "%.1f", d) : "\(Int(d))").foregroundStyle(.white)
                }
            } }
            .chartXAxis { levelAxis(step: 20) }
            .chartPlotStyle { $0.background(grayRamp) }
            .overlay(alignment: .topLeading) { legend(white == nil ? "Measure 100% white first" : nil) }
        }
    }

    /// Value shown for a luminance relative to white (1 = white), in HCFR's graph modes.
    static func value(_ rel: Double, mode: LuminanceMode, white w: Double) -> Double {
        switch mode {
        case .relative: return rel * 100
        case .absolute: return rel * w
        case .log: return log10(max(rel * 100, 0.01))
        case .lStar:
            let t = max(rel, 0)
            return t > 216.0 / 24389 ? 116 * cbrt(t) - 16 : 24389.0 / 27 * t
        }
    }
}

// MARK: - Gamma

/// Point gamma per level against the target curve (HCFR "EOTF(Gamma)", GammaHistoView): the target
/// as dotted line with a square at each gray scale step, the measure in yellow, axis 1.1–2.9.
struct GammaChart: View {
    @ObservedObject var session: Session

    var body: some View {
        let measured = session.results.compactMap { r in r.gamma.map { LevelPoint(level: r.level, value: $0, series: "Measured") } }
        let target = session.allLevels.compactMap { l -> LevelPoint? in
            let v = Reference.grayProp(l), t = session.targetRelative(level: l)
            guard t > 0, v > 0, v < 1 else { return nil }
            return LevelPoint(level: l, value: log(t) / log(v), series: "Reference")
        }
        let values = measured.map(\.value) + target.map(\.value)
        let lo = min(1.1, (values.min() ?? 2) - 0.1), hi = max(2.9, (values.max() ?? 2.4) + 0.1)
        DarkGraph(title: "EOTF(Gamma)" + (session.averageGamma.map { String(format: " — average %.2f", $0) } ?? "")) {
            GeometryReader { geo in
                Chart {
                    ForEach(target) { p in
                        LineMark(x: .value("Level", p.level), y: .value("Gamma", p.value), series: .value("S", p.series))
                            .foregroundStyle(.white.opacity(0.9)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        PointMark(x: .value("Level", p.level), y: .value("Gamma", p.value))
                            .symbol(.square).foregroundStyle(.white).symbolSize(22)
                    }
                    ForEach(measured) { p in
                        LineMark(x: .value("Level", p.level), y: .value("Gamma", p.value), series: .value("S", p.series))
                            .foregroundStyle(.yellow).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Level", p.level), y: .value("Gamma", p.value)).foregroundStyle(.yellow).symbolSize(24)
                    }
                }
                .chartXScale(domain: 0...100)
                .chartYScale(domain: lo...hi)
                .chartYAxis { AxisMarks(position: .leading, values: Array(stride(from: (lo * 10).rounded() / 10, through: hi, by: geo.size.height < 300 ? 0.2 : 0.1))) { v in
                    AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                    AxisValueLabel { Text(String(format: "%.1f", v.as(Double.self) ?? 0)).font(.caption.monospaced()).foregroundStyle(.white) }
                } }
                .chartXAxis { whiteLevelAxis(width: geo.size.width) }
                .chartPlotStyle { $0.background(grayRamp) }
            }
        }
    }
}

// MARK: - Color temperature

/// Correlated color temperature per level, with the white point's temperature (HCFR "Color temperature").
struct ColorTempChart: View {
    @ObservedObject var session: Session

    static func range(values: [Double], refK: Double, scale: Int) -> (Double, Double) {
        switch scale {
        case 1: return (2000, 10000)
        case 2: return (4000, 8000)
        default: return (min(refK - 1500, (values.min() ?? refK) - 300), max(refK + 1500, (values.max() ?? refK) + 300))
        }
    }

    var body: some View {
        let refK = Double(session.white.kelvin)
        let measured = session.results.filter { $0.level > 0 }.compactMap { r in r.cct.map { LevelPoint(level: r.level, value: $0, series: "Measured") } }
        let values = measured.map(\.value) + [refK]
        let (lo, hi) = Self.range(values: values, refK: refK, scale: session.graphOptions.tempScale)
        let shown = measured.map { LevelPoint(level: $0.level, value: min(max($0.value, lo), hi), series: $0.series) }
        let compared: [LevelPoint] = session.refData.map { d in
            d.gray.keys.sorted().filter { $0 > 0 }.compactMap { l in d.gray[l].flatMap(ColorMath.cct).map { LevelPoint(level: l, value: min(max($0, lo), hi), series: "Compared") } }
        } ?? []
        DarkGraph(title: "Color temperature (K)") {
            Chart {
                RuleMark(y: .value("Ref", refK)).foregroundStyle(.white.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ForEach(compared) { p in
                    LineMark(x: .value("Level", p.level), y: .value("K", p.value), series: .value("S", p.series))
                        .foregroundStyle(.cyan.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
                ForEach(shown) { p in
                    LineMark(x: .value("Level", p.level), y: .value("K", p.value), series: .value("S", "Measured")).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Level", p.level), y: .value("K", p.value)).foregroundStyle(.orange).symbolSize(24)
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: lo...hi)
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))").foregroundStyle(.white) }
            } }
            .chartXAxis { levelAxis() }
            .chartPlotStyle { $0.background(grayRamp) }
            .overlay(alignment: .topLeading) { legend(measured.isEmpty ? "Measure the gray scale" : nil) }
        }
    }
}

// MARK: - Target (large)

/// The "Target" of the selected color, large, with its numbers (HCFR's Target view).
struct BigTarget: View {
    @ObservedObject var session: Session

    var body: some View {
        let r = session.selectedReading
        VStack(alignment: .leading, spacing: 6) {
            Text("Target — \(r.title)").font(.caption.bold()).foregroundStyle(.secondary)
            TargetView(result: r).aspectRatio(1.33, contentMode: .fit)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                GridRow { Text("x").bold(); Text(r.xyz.map { String(format: "%.4f", $0.x) } ?? "—"); Text("ref").foregroundStyle(.secondary); Text(String(format: "%.4f", r.targetCenter.x)) }
                GridRow { Text("y").bold(); Text(r.xyz.map { String(format: "%.4f", $0.y) } ?? "—"); Text("ref").foregroundStyle(.secondary); Text(String(format: "%.4f", r.targetCenter.y)) }
                GridRow { Text("ΔE").bold(); Text(r.deltaE.map { String(format: "%.2f", $0) } ?? "—") }
            }
            .font(.caption.monospaced())
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Summary

/// Key results at a glance (HCFR "Summary").
struct SummaryView: View {
    @ObservedObject var session: Session

    var body: some View {
        let white = session.measurements[100]
        let black = session.overrideBlack ? nil : session.measurements[0]
        let colorDE = session.colorDeltaEs
        VStack {
            HStack(alignment: .top, spacing: 30) {
                section("Gray scale", [
                    ("Points measured", "\(session.results.filter { $0.xyz != nil }.count) of \(session.allLevels.count)"),
                    ("White Y", white.map { String(format: "%.3f cd/m² (%.2f ftL)", $0.Y, $0.Y * 0.291864) } ?? "—"),
                    ("White x, y", white.map { String(format: "%.4f, %.4f", $0.x, $0.y) } ?? "—"),
                    ("White CCT", white.flatMap { ColorMath.cct($0) }.map { String(format: "%.0f K", $0) } ?? "—"),
                    ("Black Y", black.map { String(format: "%.4f cd/m²", $0.Y) } ?? (session.overrideBlack ? "Override black (0)" : "—")),
                    ("Contrast", session.contrast.map { $0.isInfinite ? "Infinity:1" : String(format: "%.0f:1", $0) } ?? "—"),
                    ("Average gamma", session.averageGamma.map { String(format: "%.2f", $0) } ?? "—"),
                    ("Average ΔE", session.averageDeltaE.map { String(format: "%.2f", $0) } ?? "—"),
                    ("Max ΔE", session.maxDeltaE.map { String(format: "%.2f", $0) } ?? "—"),
                ])
                section("Colors", PatchColor.allCases.map { p in
                    let r = session.patchResults.first { $0.patch == p }
                    return (p.rawValue, r?.deltaE.map { String(format: "ΔE %.2f   x %.4f  y %.4f", $0, r?.xyz?.x ?? 0, r?.xyz?.y ?? 0) } ?? "—")
                } + [
                    ("Average ΔE", colorDE.isEmpty ? "—" : String(format: "%.2f", colorDE.reduce(0, +) / Double(colorDE.count))),
                    ("Max ΔE", colorDE.max().map { String(format: "%.2f", $0) } ?? "—"),
                    ("Gamut (xy area)", session.gamutCoverage.map { String(format: "%.1f %% of %@", $0 * 100, session.standard.shortName) } ?? "—"),
                ])
                section("Reference", [
                    ("Standard", session.standard.rawValue),
                    ("White", session.white.label),
                    ("Gamma", session.gammaDescription),
                    ("Delta E", "\(session.ref.deltaEFormula.title), gray \(session.ref.grayDeltaE.title)"),
                    ("Gray steps", "\(session.grayCount)"),
                    ("Display (meter)", session.correction?.name ?? "—"),
                ])
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.0).foregroundStyle(.secondary)
                        Text(row.1).font(.callout.monospaced())
                    }
                }
            }
        }
    }
}

@ViewBuilder
private func legend(_ message: String?) -> some View {
    if let message {
        Text(message).font(.caption).foregroundStyle(.white.opacity(0.8))
            .padding(6).background(.black.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 4)).padding(8)
    }
}

// MARK: - Near black / near white

/// Luminance of the near black or near white scale against its target (cd/m²).
struct NearScaleChart: View {
    @ObservedObject var session: Session
    let view: MeasureView

    var body: some View {
        let results = session.seriesResults(view)
        let levels = results.indices.map { session.seriesLevel(view, $0) }
        let measured = zip(levels, results).compactMap { l, r in r.xyz.map { LevelPoint(level: l, value: $0.Y, series: "Measured") } }
        let target = zip(levels, results).compactMap { l, r in r.targetY.map { LevelPoint(level: l, value: $0, series: "Reference") } }
        let lo = levels.first ?? 0, hi = max(levels.last ?? 1, lo + 1)
        DarkGraph(title: view == .nearBlack ? "Near Black (cd/m²)" : "Near White (cd/m²)") {
            Chart {
                ForEach(target) { p in
                    LineMark(x: .value("Level", p.level), y: .value("Y", p.value), series: .value("S", p.series))
                        .foregroundStyle(.white.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    PointMark(x: .value("Level", p.level), y: .value("Y", p.value))
                        .foregroundStyle(.white.opacity(0.8)).symbol(.square).symbolSize(20)
                }
                ForEach(measured) { p in
                    LineMark(x: .value("Level", p.level), y: .value("Y", p.value), series: .value("S", p.series))
                        .foregroundStyle(.yellow).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Level", p.level), y: .value("Y", p.value)).foregroundStyle(.yellow).symbolSize(24)
                }
            }
            .chartXScale(domain: lo...hi)
            .chartXAxis { AxisMarks(values: levels) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text("\(Reference.label(v.as(Double.self) ?? 0))%").font(.caption2.monospaced()).foregroundStyle(.white) }
            } }
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text(String(format: "%.3g", v.as(Double.self) ?? 0)).foregroundStyle(.white) }
            } }
            .chartPlotStyle { $0.background(grayRamp) }
            .overlay(alignment: .topLeading) { legend(measured.isEmpty ? "Measure → \(view == .nearBlack ? "Near black" : "Near white")" : nil) }
        }
    }
}

// MARK: - Saturations

/// HCFR's "Saturation Luminance - Shift": luminance error (%) or saturation shift (measured
/// saturation − expected, %) at every step of the six saturation scales.
struct SaturationChart: View {
    @ObservedObject var session: Session
    let shift: Bool

    var body: some View {
        let points: [LevelPoint] = MeasureView.saturations.flatMap { v -> [LevelPoint] in
            let results = session.seriesResults(v)
            let n = results.count
            guard n > 1, let color = v.saturationColor else { return [] }
            let full = session.ref.rgbToXYZ.apply(color.rgb)
            let end = XYZ(X: full[0], Y: full[1], Z: full[2])
            let w = session.ref.white
            let span = hypot(end.x - w.x, end.y - w.y)
            return results.compactMap { r -> LevelPoint? in
                guard let xyz = r.xyz, xyz.Y > 0 else { return nil }
                let pct = Double(r.index) * 100 / Double(n - 1)
                if shift {
                    guard span > 0, let ref = r.reference else { return nil }
                    let measured = hypot(xyz.x - w.x, xyz.y - w.y) / span * 100
                    let expected = hypot(ref.x - w.x, ref.y - w.y) / span * 100
                    return LevelPoint(level: pct, value: measured - expected, series: color.rawValue)
                }
                guard let d = r.deltaL else { return nil }
                return LevelPoint(level: pct, value: d * 100, series: color.rawValue)
            }
        }
        let maxAbs = max(5, (points.map { abs($0.value) }.max() ?? 0) * 1.1)
        DarkGraph(title: shift ? "Saturation shift (%)" : "Saturation luminance (delta %)") {
            Chart {
                RuleMark(y: .value("Ref", 0)).foregroundStyle(.white.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ForEach(points) { p in
                    LineMark(x: .value("Sat", p.level), y: .value("%", p.value), series: .value("Color", p.series))
                        .foregroundStyle(CIEChart.markerColor(PatchColor(rawValue: p.series) ?? .white))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Sat", p.level), y: .value("%", p.value))
                        .foregroundStyle(CIEChart.markerColor(PatchColor(rawValue: p.series) ?? .white)).symbolSize(20)
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: -maxAbs...maxAbs)
            .chartXAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)% Sat").font(.caption2.monospaced()).foregroundStyle(.white) }
            } }
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text(String(format: "%.0f", v.as(Double.self) ?? 0)).foregroundStyle(.white) }
            } }
            .chartPlotStyle { $0.background(Color(white: 0.2)) }
            .overlay(alignment: .topLeading) { legend(points.isEmpty ? "Measure → saturations" : nil) }
        }
    }
}

// MARK: - Free measures

/// HCFR's "Combined histogram for free measures": Y, x and y of every free measure in order.
struct FreeMeasuresChart: View {
    @ObservedObject var session: Session

    var body: some View {
        let m = session.freeMeasurements
        VStack(spacing: 6) {
            series("Y (cd/m²)", m.map(\.Y), .yellow)
            series("x", m.map(\.x), .pink)
            series("y", m.map(\.y), .green)
        }
    }

    private func series(_ title: String, _ values: [Double], _ color: Color) -> some View {
        DarkGraph(title: title) {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("#", i + 1), y: .value(title, v)).foregroundStyle(color)
                    PointMark(x: .value("#", i + 1), y: .value(title, v)).foregroundStyle(color).symbolSize(14)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.3))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.caption2).foregroundStyle(.white) }
            } }
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.3))
                AxisValueLabel { Text(String(format: "%.4g", v.as(Double.self) ?? 0)).font(.caption2).foregroundStyle(.white) }
            } }
            .chartPlotStyle { $0.background(Color(white: 0.2)) }
            .overlay(alignment: .topLeading) { legend(values.isEmpty ? "Measure → Free measure" : nil) }
        }
    }
}

// MARK: - Graph options and saving (HCFR's graph right-click menus)

/// Scale / display options of the graph shown.
struct GraphOptionsMenu: View {
    @ObservedObject var session: Session
    let graph: InfoGraph

    var body: some View {
        let o = $session.graphOptions
        Menu {
            switch graph {
            case .luminanceGamma:
                Picker("Luminance", selection: o.luminance) {
                    ForEach(LuminanceMode.allCases) { Text($0.rawValue).tag($0) }
                }
            case .rgbLevels, .rgbGamma, .targetRGBGamma, .auto:
                Picker("RGB scale", selection: o.rgbScale) {
                    Text("0-200%").tag(0); Text("60-140%").tag(1); Text("50-150%").tag(2); Text("80-120%").tag(3)
                }
                Picker("Delta E scale", selection: o.deltaEMax) {
                    Text("0-5").tag(5.0); Text("0-10").tag(10.0); Text("0-20").tag(20.0)
                }
            case .colorTemperature:
                Picker("Temperature scale", selection: o.tempScale) {
                    Text("Auto-adjust").tag(0); Text("2000K-10000K").tag(1); Text("4000K-8000K").tag(2)
                }
            case .cie, .targetCIE:
                Toggle("Display saturations, color checker and free measures", isOn: o.cieAllSeries)
                Toggle("Display grays", isOn: $session.cieShowGrays)
                Toggle("Display references", isOn: $session.cieShowReferences)
                Toggle("CIE u'v' mode", isOn: $session.cieUV)
            case .saturationShift, .nearBlackWhite, .freeHistogram, .summary, .spectrum:
                Text("No options for this graph")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Graph scales and options")
    }
}

@MainActor
enum GraphExport {
    static func save<V: View>(_ view: V, name: String, session: Session) {
        let content = view.frame(width: 1400, height: 800).padding(8).background(Color(white: 0.12))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            session.errorMessage = "Could not render the graph."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save graph"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(session.projectName) - \(name).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            session.status = "Graph saved: \(url.lastPathComponent)"
        } catch {
            session.errorMessage = "Could not save the graph: \(error.localizedDescription)"
        }
    }
}

// MARK: - Spectrum (spectral meters)

/// HCFR's Spectrum graph: the spectrum of the selected column (spectral meters only).
struct SpectrumChart: View {
    @ObservedObject var session: Session

    /// Approximate color of a wavelength, for the area under the curve.
    static func color(_ nm: Double) -> Color {
        var r = 0.0, g = 0.0, b = 0.0
        switch nm {
        case ..<440: r = -(nm - 440) / 60; b = 1
        case ..<490: g = (nm - 440) / 50; b = 1
        case ..<510: g = 1; b = -(nm - 510) / 20
        case ..<580: r = (nm - 510) / 70; g = 1
        case ..<645: r = 1; g = -(nm - 645) / 65
        default: r = 1
        }
        let f = nm < 420 ? 0.3 + 0.7 * (nm - 380) / 40 : nm > 700 ? 0.3 + 0.7 * (780 - nm) / 80 : 1
        return Color(red: max(r, 0) * max(f, 0.2), green: max(g, 0) * max(f, 0.2), blue: max(b, 0) * max(f, 0.2))
    }

    var body: some View {
        let target = session.selectedTarget
        let sp = session.spectra[target.id] ?? session.spectra.values.first
        let pts: [(Double, Double)] = sp.map { s in s.values.indices.map { (s.wavelength($0), s.values[$0]) } } ?? []
        let peak = max(pts.map(\.1).max() ?? 1, 1e-9)
        DarkGraph(title: "Spectrum" + (session.spectra[target.id] != nil ? " — \(session.title(for: target))" : "")) {
            Chart {
                ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                    BarMark(x: .value("nm", p.0), y: .value("Relative", p.1 / peak), width: .fixed(3))
                        .foregroundStyle(Self.color(p.0))
                }
                ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("nm", p.0), y: .value("Relative", p.1 / peak), series: .value("S", "Spectrum"))
                        .foregroundStyle(.white).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXScale(domain: 380...780)
            .chartYScale(domain: 0...1.05)
            .chartXAxis { AxisMarks(values: Array(stride(from: 400, through: 780, by: 50))) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.3))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0) nm").font(.caption2).foregroundStyle(.white) }
            } }
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.3))
                AxisValueLabel { Text(String(format: "%.1f", v.as(Double.self) ?? 0)).foregroundStyle(.white) }
            } }
            .chartPlotStyle { $0.background(Color(white: 0.15)) }
            .overlay(alignment: .topLeading) {
                legend(pts.isEmpty ? "No spectrum: measure with a spectrophotometer (colorimeters give no spectrum)" : nil)
            }
        }
    }
}
