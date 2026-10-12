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
                Spacer()
            }
            graph(session.infoGraph == .auto ? (session.view == .grayScale ? .rgbLevels : .cie) : session.infoGraph)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }

    @ViewBuilder
    private func graph(_ g: InfoGraph) -> some View {
        switch g {
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
        let white = session.whiteY
        let measured: [LevelPoint] = white.map { w in
            session.results.compactMap { r in r.xyz.map { LevelPoint(level: r.level, value: $0.Y / w * 100, series: "Measured") } }
        } ?? []
        let target = stride(from: 0.0, through: 100, by: 2.5).map {
            LevelPoint(level: $0, value: session.targetRelative(level: $0) * 100, series: "Reference")
        }
        DarkGraph(title: "Luminance") {
            Chart {
                ForEach(target) { p in
                    LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("S", p.series))
                        .foregroundStyle(.white.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                ForEach(measured) { p in
                    LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("S", p.series))
                        .foregroundStyle(.yellow).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Level", p.level), y: .value("%", p.value)).foregroundStyle(.yellow).symbolSize(24)
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: 0...105)
            .chartYAxis { AxisMarks(position: .leading, values: Array(stride(from: 0, through: 100, by: 20))) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").foregroundStyle(.white) }
            } }
            .chartXAxis { levelAxis(step: 20) }
            .chartPlotStyle { $0.background(grayRamp) }
            .overlay(alignment: .topLeading) { legend(white == nil ? "Measure 100% white first" : nil) }
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

    var body: some View {
        let refK = Double(session.white.kelvin)
        let measured = session.results.filter { $0.level > 0 }.compactMap { r in r.cct.map { LevelPoint(level: r.level, value: $0, series: "Measured") } }
        let values = measured.map(\.value) + [refK]
        let lo = min(refK - 1500, (values.min() ?? refK) - 300), hi = max(refK + 1500, (values.max() ?? refK) + 300)
        DarkGraph(title: "Color temperature (K)") {
            Chart {
                RuleMark(y: .value("Ref", refK)).foregroundStyle(.white.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ForEach(measured) { p in
                    LineMark(x: .value("Level", p.level), y: .value("K", p.value)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 2))
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
