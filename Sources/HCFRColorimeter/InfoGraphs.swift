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
                    ForEach(InfoGraph.allCases) { Text(tr($0.rawValue)).tag($0) }
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
            if session.infoGraph == .auto && autoGraphs.count > 1 {
                HStack(spacing: 8) {
                    ForEach(autoGraphs, id: \.self) { g in
                        graph(g).frame(maxWidth: .infinity)
                            .contextMenu { graphMenu(g) }
                    }
                }
            } else {
                graph(shownGraph)
                    .contextMenu { graphMenu(shownGraph) }
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        .sheet(isPresented: Binding(get: { session.editingScaleKey != nil }, set: { if !$0 { session.editingScaleKey = nil } })) {
            GraphScaleValuesSheet(session: session)
        }
    }

    private var shownGraph: InfoGraph { session.infoGraph == .auto ? autoGraph : session.infoGraph }

    /// HCFR's right-click menu of a graph: its options and Save….
    @ViewBuilder private func graphMenu(_ g: InfoGraph) -> some View {
        GraphOptionsItems(session: session, graph: g)
        Divider()
        Button("Save…") { GraphExport.save(graph(g), name: g.rawValue, session: session) }
    }

    /// Auto with several tabs open (as HCFR for Windows): the graphs of up to three of them — the
    /// table shown and the last used — in the order of the tabs, without repeating a graph.
    private var autoGraphs: [InfoGraph] {
        let recent = Array(session.tabUse.filter { session.openTabs.contains($0) }.prefix(3))
        var out: [InfoGraph] = []
        for v in session.openTabs where recent.contains(v) {
            let g = Self.autoGraph(for: v)
            if !out.contains(g) { out.append(g) }
        }
        return out
    }

    private var autoGraph: InfoGraph { Self.autoGraph(for: session.view) }

    /// Auto: the graph that goes with a table.
    static func autoGraph(for view: MeasureView) -> InfoGraph {
        switch view {
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
            Text(tr(title)).font(.callout.bold()).foregroundStyle(ChartInk.accent)
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            content.frame(maxHeight: .infinity)
        }
        .padding(6)
        .background(ChartInk.paper)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Colors of the graphs: HCFR's dark graphs, or white ones (Appearance → "Display charts with a
/// white background"; "Save chart files with a white background" forces them while saving).
enum ChartInk {
    static var whiteDisplay = false
    static var forced: Bool?
    static var white: Bool { forced ?? whiteDisplay }
    static var ink: Color { white ? Color(white: 0.1) : .white }
    static var accent: Color { white ? Color(red: 0.85, green: 0.45, blue: 0) : .yellow }
    static var paper: Color { white ? .white : Color(white: 0.12) }
    static var plot: Color { white ? Color(white: 0.96) : Color(white: 0.2) }
}

let grayRamp = LinearGradient(colors: [Color(white: 0.12), Color(white: 0.95)], startPoint: .leading, endPoint: .trailing)

/// HCFR's "10% White … 90% White" axis; every other label when the graph is narrow.
func whiteLevelAxis(width: CGFloat) -> some AxisContent {
    let step = width < 760 ? 20 : 10
    return AxisMarks(values: Array(stride(from: 10, through: 90, by: step))) { v in
        AxisGridLine().foregroundStyle(.teal.opacity(0.5))
        AxisValueLabel { Text("\(v.as(Int.self) ?? 0)% White").font(.caption2.monospaced()).foregroundStyle(ChartInk.ink).fixedSize() }
    }
}

private func levelAxis(step: Int = 10) -> some AxisContent {
    AxisMarks(values: Array(stride(from: step, through: 100, by: step))) { v in
        AxisGridLine().foregroundStyle(.teal.opacity(0.5))
        AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.caption2.monospaced()).foregroundStyle(ChartInk.ink) }
    }
}

/// HCFR's Red / Green / Blue curves: each channel of the gray scale relative to the same channel
/// of white (1 = white), from the RGB rows of the table.
@MainActor
func channelCurves(_ session: Session) -> [(name: String, color: Color, values: [(level: Double, rel: Double)])] {
    let o = session.graphOptions
    guard let white = session.results.first(where: { $0.level == 100 })?.rgb else { return [] }
    var out: [(String, Color, [(Double, Double)])] = []
    for (c, on, name, color) in [(0, o.curveR, "Red", Color.red), (1, o.curveG, "Green", Color.green), (2, o.curveB, "Blue", Color.blue)] where on {
        guard white[c] > 0 else { continue }
        let v = session.results.compactMap { r -> (Double, Double)? in r.rgb.map { (r.level, $0[c] / white[c]) } }
        out.append((name, color, v))
    }
    return out.map { (name: $0.0, color: $0.1, values: $0.2.map { (level: $0.0, rel: $0.1) }) }
}

/// Measured curve style (Graphs parameters: thickness and dots).
@MainActor
func measuredStroke(_ session: Session) -> StrokeStyle { StrokeStyle(lineWidth: session.graphOptions.lineWidth) }
@MainActor
func dotSize(_ session: Session, _ size: CGFloat = 24) -> CGFloat { session.graphOptions.showDots ? size : 0 }

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
        let lux = Self.luxRelative(session)
        let luxMode = session.appPrefs.luxCurves
        let measured: [LevelPoint] = white.map { w in
            session.results.compactMap { r -> LevelPoint? in
                // Advanced → Luxmeter: "Prefer luxmeter value when available"
                if luxMode == .preferLuxmeter, let l = lux[r.level] {
                    return LevelPoint(level: r.level, value: shown(l), series: "Measured")
                }
                return r.xyz.map { LevelPoint(level: r.level, value: shown($0.Y / w), series: "Measured") }
            }
        } ?? []
        // "Display two separate luminance curves": the luxmeter's as a second curve
        let luxCurve: [LevelPoint] = luxMode == .both
            ? lux.keys.sorted().map { LevelPoint(level: $0, value: shown(lux[$0]!), series: "Luxmeter") } : []
        let o = session.graphOptions
        let target = !o.showReference ? [] : stride(from: 0.0, through: 100, by: 2.5).map {
            LevelPoint(level: $0, value: shown(session.targetRelative(level: $0)), series: "Reference")
        }
        let compared: [LevelPoint] = (o.showRefMeasure ? session.refData : nil).map { d in
            d.gray.keys.sorted().compactMap { l in d.gray[l].map { LevelPoint(level: l, value: shown($0.Y / d.whiteY), series: "Compared") } }
        } ?? []
        let channels = channelCurves(session).map { c in
            (c.color, c.values.map { LevelPoint(level: $0.level, value: shown($0.rel), series: c.name) })
        }
        let measuredY = o.curveY ? measured : []
        let top: Double = mode == .absolute ? max(w, measured.map(\.value).max() ?? 0) * 1.05 : mode == .log ? 2.05 : 105
        let bottom: Double = mode == .log ? -2 : 0
        DarkGraph(title: mode == .relative ? "Luminance" : "Luminance — \(mode.rawValue)" + (mode == .absolute ? " (cd/m²)" : "")) {
            Chart {
                ForEach(target) { p in
                    LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("S", p.series))
                        .foregroundStyle(ChartInk.ink.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                ForEach(compared) { p in
                    LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("S", p.series))
                        .foregroundStyle(.cyan.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
                ForEach(luxCurve) { p in
                    LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("S", p.series))
                        .foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 3]))
                }
                ForEach(Array(channels.enumerated()), id: \.offset) { _, ch in
                    ForEach(ch.1) { p in
                        LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("S", p.series))
                            .foregroundStyle(ch.0).lineStyle(measuredStroke(session))
                    }
                }
                ForEach(measuredY) { p in
                    LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("S", p.series))
                        .foregroundStyle(ChartInk.accent).lineStyle(measuredStroke(session))
                    PointMark(x: .value("Level", p.level), y: .value("%", p.value)).foregroundStyle(ChartInk.accent).symbolSize(dotSize(session))
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: session.graphOptions.y("luminance", bottom...top))
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel {
                    let d = v.as(Double.self) ?? 0
                    Text(mode == .relative ? "\(Int(d))%" : mode == .log ? String(format: "%.1f", d) : "\(Int(d))").foregroundStyle(ChartInk.ink)
                }
            } }
            .chartXAxis { levelAxis(step: 20) }
            .chartPlotStyle { $0.background(grayRamp) }
            .overlay(alignment: .topLeading) { legend(white == nil ? "Measure 100% white first" : nil) }
        }
    }

    /// Luxmeter readings of the gray scale relative to the one at 100% (empty without a luxmeter).
    static func luxRelative(_ session: Session) -> [Double: Double] {
        guard let top = session.lux(.gray(100)), top > 0 else { return [:] }
        var d: [Double: Double] = [:]
        for l in session.allLevels { if let v = session.lux(.gray(l)) { d[l] = v / top } }
        return d
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
        let o = session.graphOptions
        let measured = !o.curveY ? [] : session.results.compactMap { r in r.gamma.map { LevelPoint(level: r.level, value: $0, series: "Measured") } }
        let channels = channelCurves(session).map { c in
            (c.color, c.values.compactMap { v -> LevelPoint? in
                let x = session.ref.offsetSignal(Reference.grayProp(v.level))
                guard v.rel > 0, x > 0, x < 1, v.level >= 5 else { return nil }
                return LevelPoint(level: v.level, value: log(v.rel) / log(x), series: c.name)
            })
        }
        let compared: [LevelPoint] = (o.showRefMeasure ? session.refData : nil).map { d in
            d.gray.keys.sorted().compactMap { l -> LevelPoint? in
                guard let c = d.gray[l], l >= 5, l < 100 else { return nil }
                let rel = c.Y / d.whiteY, x = session.ref.offsetSignal(Reference.grayProp(l))
                guard rel > 0, x > 0, x < 1 else { return nil }
                return LevelPoint(level: l, value: log(rel) / log(x), series: "Compared")
            }
        } ?? []
        let target = !o.showReference ? [] : session.allLevels.compactMap { l -> LevelPoint? in
            let v = Reference.grayProp(l), t = session.targetRelative(level: l)
            guard t > 0, v > 0, v < 1 else { return nil }
            return LevelPoint(level: l, value: log(t) / log(session.ref.offsetSignal(v)), series: "Reference")
        }
        let values = measured.map(\.value) + target.map(\.value)
        let lo = min(1.1, (values.min() ?? 2) - 0.1), hi = max(2.9, (values.max() ?? 2.4) + 0.1)
        DarkGraph(title: "EOTF(Gamma)" + (session.averageGamma.map { String(format: " — average %.2f", $0) } ?? "")) {
            GeometryReader { geo in
                Chart {
                    ForEach(target) { p in
                        LineMark(x: .value("Level", p.level), y: .value("Gamma", p.value), series: .value("S", p.series))
                            .foregroundStyle(ChartInk.ink.opacity(0.9)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        PointMark(x: .value("Level", p.level), y: .value("Gamma", p.value))
                            .symbol(.square).foregroundStyle(ChartInk.ink).symbolSize(22)
                    }
                    if session.graphOptions.showAverage, let avg = session.averageGamma {
                        RuleMark(y: .value("Average", avg))
                            .foregroundStyle(.yellow.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    }
                    ForEach(compared) { p in
                        LineMark(x: .value("Level", p.level), y: .value("Gamma", p.value), series: .value("S", p.series))
                            .foregroundStyle(.cyan.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }
                    ForEach(Array(channels.enumerated()), id: \.offset) { _, ch in
                        ForEach(ch.1) { p in
                            LineMark(x: .value("Level", p.level), y: .value("Gamma", p.value), series: .value("S", p.series))
                                .foregroundStyle(ch.0).lineStyle(measuredStroke(session))
                        }
                    }
                    ForEach(measured) { p in
                        LineMark(x: .value("Level", p.level), y: .value("Gamma", p.value), series: .value("S", p.series))
                            .foregroundStyle(ChartInk.accent).lineStyle(measuredStroke(session))
                        PointMark(x: .value("Level", p.level), y: .value("Gamma", p.value)).foregroundStyle(ChartInk.accent).symbolSize(dotSize(session))
                    }
                }
                .chartXScale(domain: 0...100)
                .chartYScale(domain: session.graphOptions.y("gamma", lo...hi))
                .chartYAxis { AxisMarks(position: .leading, values: Array(stride(from: (session.graphOptions.y("gamma", lo...hi).lowerBound * 10).rounded() / 10, through: session.graphOptions.y("gamma", lo...hi).upperBound, by: geo.size.height < 300 ? 0.2 : 0.1))) { v in
                    AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                    AxisValueLabel { Text(String(format: "%.1f", v.as(Double.self) ?? 0)).font(.caption.monospaced()).foregroundStyle(ChartInk.ink) }
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
        let compared: [LevelPoint] = (session.graphOptions.showRefMeasure ? session.refData : nil).map { d in
            d.gray.keys.sorted().filter { $0 > 0 }.compactMap { l in d.gray[l].flatMap(ColorMath.cct).map { LevelPoint(level: l, value: min(max($0, lo), hi), series: "Compared") } }
        } ?? []
        DarkGraph(title: "Color temperature (K)") {
            Chart {
                if session.graphOptions.showReference {
                    RuleMark(y: .value("Ref", refK)).foregroundStyle(ChartInk.ink.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                ForEach(compared) { p in
                    LineMark(x: .value("Level", p.level), y: .value("K", p.value), series: .value("S", p.series))
                        .foregroundStyle(.cyan.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
                ForEach(shown) { p in
                    LineMark(x: .value("Level", p.level), y: .value("K", p.value), series: .value("S", "Measured")).foregroundStyle(.orange).lineStyle(measuredStroke(session))
                    PointMark(x: .value("Level", p.level), y: .value("K", p.value)).foregroundStyle(.orange).symbolSize(dotSize(session))
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: session.graphOptions.y("temperature", lo...hi))
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))").foregroundStyle(ChartInk.ink) }
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
            Text(tr(title)).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(tr(row.0)).foregroundStyle(.secondary)
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
        Text(tr(message)).font(.caption).foregroundStyle(ChartInk.ink.opacity(0.8))
            .padding(6).background(.black.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 4)).padding(8)
    }
}

// MARK: - Near black / near white

/// Luminance of the near black or near white scale against its target (cd/m²).
struct NearScaleChart: View {
    @ObservedObject var session: Session
    let view: MeasureView

    /// HCFR's modes: Absolute Y (cd/m²), luminance % of white or L*; "Logarithmic mode" on top.
    static func shown(_ y: Double, white: Double, options o: GraphOptions) -> Double {
        var v: Double
        switch o.nearMode {
        case .absolute: v = y
        case .relative: v = y / white * 100
        case .lStar: v = LuminanceChart.value(y / white, mode: .lStar, white: white)
        }
        if o.nearLog { v = log10(max(v, 1e-4)) }
        return v
    }

    var body: some View {
        let o = session.graphOptions
        let results = session.seriesResults(view)
        let levels = results.indices.map { session.seriesLevel(view, $0) }
        let white = session.whiteY ?? 1
        let shown: (Double) -> Double = { Self.shown($0, white: white, options: o) }
        let measured = !o.curveY ? [] : zip(levels, results).compactMap { l, r in r.xyz.map { LevelPoint(level: l, value: shown($0.Y), series: "Measured") } }
        let target = !o.showReference ? [] : zip(levels, results).compactMap { l, r in r.targetY.map { LevelPoint(level: l, value: shown($0), series: "Reference") } }
        // Red / Green / Blue: each channel's share of the measure, as luminance of that channel
        let whiteRGB = session.results.first { $0.level == 100 }?.rgb
        let channels: [(Color, [LevelPoint])] = [(0, o.curveR, Color.red), (1, o.curveG, Color.green), (2, o.curveB, Color.blue)].compactMap { c, on, color in
            guard on, let w = whiteRGB, w[c] > 0 else { return nil }
            return (color, zip(levels, results).compactMap { l, r in r.rgb.map { LevelPoint(level: l, value: shown($0[c] / w[c] * white), series: "C\(c)") } })
        }
        let lo = levels.first ?? 0, hi = max(levels.last ?? 1, lo + 1)
        let unit = o.nearLog ? "log " : ""
        let title = (view == .nearBlack ? "Near Black" : "Near White") + " — " + unit
            + (o.nearMode == .absolute ? "cd/m²" : o.nearMode == .relative ? "%" : "L*")
        DarkGraph(title: title) {
            Chart {
                ForEach(target) { p in
                    LineMark(x: .value("Level", p.level), y: .value("Y", p.value), series: .value("S", p.series))
                        .foregroundStyle(ChartInk.ink.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    PointMark(x: .value("Level", p.level), y: .value("Y", p.value))
                        .foregroundStyle(ChartInk.ink.opacity(0.8)).symbol(.square).symbolSize(20)
                }
                ForEach(Array(channels.enumerated()), id: \.offset) { _, ch in
                    ForEach(ch.1) { p in
                        LineMark(x: .value("Level", p.level), y: .value("Y", p.value), series: .value("S", p.series))
                            .foregroundStyle(ch.0).lineStyle(measuredStroke(session))
                    }
                }
                ForEach(measured) { p in
                    LineMark(x: .value("Level", p.level), y: .value("Y", p.value), series: .value("S", p.series))
                        .foregroundStyle(ChartInk.accent).lineStyle(measuredStroke(session))
                    PointMark(x: .value("Level", p.level), y: .value("Y", p.value)).foregroundStyle(ChartInk.accent).symbolSize(dotSize(session))
                }
            }
            .chartXScale(domain: lo...hi)
            .chartXAxis { AxisMarks(values: levels) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text("\(Reference.label(v.as(Double.self) ?? 0))%").font(.caption2.monospaced()).foregroundStyle(ChartInk.ink) }
            } }
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text(String(format: "%.3g", v.as(Double.self) ?? 0)).foregroundStyle(ChartInk.ink) }
            } }
            .chartPlotStyle { $0.background(grayRamp) }
            .overlay(alignment: .topLeading) { legend(measured.isEmpty && channels.isEmpty ? "Measure → \(view == .nearBlack ? "Near black" : "Near white")" : nil) }
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
        let o = session.graphOptions
        let points: [LevelPoint] = MeasureView.saturations.flatMap { v -> [LevelPoint] in
            let results = session.seriesResults(v)
            let n = results.count
            guard n > 1, let color = v.saturationColor else { return [] }
            // HCFR's "Primary colors" / "Secondary colors" (luminance graph) and color list (shifts graph)
            let primary = [PatchColor.red, .green, .blue].contains(color)
            if shift ? o.satHidden.contains(color.rawValue) : (primary ? !o.satPrimaries : !o.satSecondaries) { return [] }
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
                if o.showReference {
                    RuleMark(y: .value("Ref", 0)).foregroundStyle(ChartInk.ink.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                ForEach(points) { p in
                    LineMark(x: .value("Sat", p.level), y: .value("%", p.value), series: .value("Color", p.series))
                        .foregroundStyle(CIEChart.markerColor(PatchColor(rawValue: p.series) ?? .white))
                        .lineStyle(measuredStroke(session))
                    PointMark(x: .value("Sat", p.level), y: .value("%", p.value))
                        .foregroundStyle(CIEChart.markerColor(PatchColor(rawValue: p.series) ?? .white)).symbolSize(dotSize(session, 20))
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: session.graphOptions.y("saturation", -maxAbs...maxAbs))
            .chartXAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)% Sat").font(.caption2.monospaced()).foregroundStyle(ChartInk.ink) }
            } }
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text(String(format: "%.0f", v.as(Double.self) ?? 0)).foregroundStyle(ChartInk.ink) }
            } }
            .chartPlotStyle { $0.background(ChartInk.plot) }
            .overlay(alignment: .topLeading) { legend(points.isEmpty ? "Measure → saturations" : nil) }
        }
    }
}

// MARK: - Free measures

/// HCFR's "Combined histogram for free measures": Y, x and y of every free measure in order.
struct FreeMeasuresChart: View {
    @ObservedObject var session: Session

    var body: some View {
        let o = session.graphOptions
        let all = session.seriesResults(.freeMeasures)
        // HCFR's "10 / 20 / 50 measure points": the last ones only
        let shownResults = o.freePoints > 0 ? Array(all.suffix(o.freePoints)) : all
        let first = shownResults.first?.index ?? 0
        let m = shownResults.compactMap { r in r.xyz.map { (r.index, $0, r) } }
        VStack(spacing: 6) {
            if o.freeLuminance { series("Y (cd/m²)", m.map { ($0.0, $0.1.Y) }, .yellow, start: first) }
            if o.freeXY {
                series("x", m.map { ($0.0, $0.1.x) }, .pink, start: first)
                series("y", m.map { ($0.0, $0.1.y) }, .green, start: first)
            }
            if o.freeDeltaE { series("Delta E", m.compactMap { r in r.2.deltaE.map { (r.0, $0) } }, .red, start: first) }
            if o.freeTemperature { series("Color temperature (K)", m.compactMap { r in r.2.cct.map { (r.0, $0) } }, .orange, start: first) }
        }
    }

    private func series(_ title: String, _ values: [(Int, Double)], _ color: Color, start: Int) -> some View {
        DarkGraph(title: title) {
            Chart {
                ForEach(values, id: \.0) { i, v in
                    LineMark(x: .value("#", i + 1), y: .value(title, v)).foregroundStyle(color).lineStyle(measuredStroke(session))
                    PointMark(x: .value("#", i + 1), y: .value(title, v)).foregroundStyle(color).symbolSize(dotSize(session, 14))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.3))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.caption2).foregroundStyle(ChartInk.ink) }
            } }
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.3))
                AxisValueLabel { Text(String(format: "%.4g", v.as(Double.self) ?? 0)).font(.caption2).foregroundStyle(ChartInk.ink) }
            } }
            .chartPlotStyle { $0.background(ChartInk.plot) }
            .overlay(alignment: .topLeading) { legend(values.isEmpty ? "Measure → Free measure" : nil) }
        }
    }
}

// MARK: - Graph options and saving (HCFR's graph right-click menus)

/// Scale / display options of the graph shown (the menu button and the graph's right-click menu,
/// as HCFR's graph menus).
struct GraphOptionsMenu: View {
    @ObservedObject var session: Session
    let graph: InfoGraph

    var body: some View {
        Menu {
            GraphOptionsItems(session: session, graph: graph)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Graph scales and options")
    }
}

/// The items of a graph's menu.
struct GraphOptionsItems: View {
    @ObservedObject var session: Session
    let graph: InfoGraph

    /// Graphs with HCFR's Scale menu (zoom, shift, values).
    private var scaleKeys: [String] {
        switch graph {
        case .luminanceGamma: return ["luminance", "gamma"]
        case .rgbLevels, .rgbGamma, .targetRGBGamma, .auto: return ["rgb"]
        case .colorTemperature: return ["temperature"]
        case .saturationShift: return ["saturation"]
        default: return []
        }
    }

    var body: some View {
        let o = $session.graphOptions
        switch graph {
        case .luminanceGamma:
            Toggle("Display reference", isOn: o.showReference)
            Toggle("Display reference measure", isOn: o.showRefMeasure)
            Toggle("Display average gamma", isOn: o.showAverage)
            Divider()
            channelToggles
            Divider()
            Picker("Luminance", selection: o.luminance) {
                ForEach(LuminanceMode.allCases) { Text(tr($0.rawValue)).tag($0) }
            }
        case .rgbLevels, .rgbGamma, .targetRGBGamma, .auto:
            Toggle("w/Gamma", isOn: Binding(
                get: { session.prefs.grayDeltaE == GrayDeltaEMode.absoluteYWithGamma.rawValue },
                set: { session.prefs.grayDeltaE = ($0 ? GrayDeltaEMode.absoluteYWithGamma : .absoluteYWithoutGamma).rawValue }))
                .help("As HCFR's RGB graph \"w/Gamma\": the channels against the target luminance (shows the gamma error too) instead of the measured luminance. It is the same as Preferences → References → dE gray: Absolute Y w/gamma.")
            Toggle("Delta E curve", isOn: o.showDeltaECurve)
            Toggle("Display reference measure", isOn: o.showRefMeasure)
            if graph != .rgbLevels && graph != .auto {
                Toggle("Display reference", isOn: o.showReference)
                Toggle("Display average gamma", isOn: o.showAverage)
                Menu("Gamma curves") { channelToggles }
            }
            Picker("RGB scale", selection: o.rgbScale) {
                Text("0-200%").tag(0); Text("60-140%").tag(1); Text("50-150%").tag(2); Text("80-120%").tag(3)
            }
            Picker("Delta E scale", selection: o.deltaEMax) {
                Text("0-5").tag(5.0); Text("0-10").tag(10.0); Text("0-20").tag(20.0)
            }
        case .colorTemperature:
            Toggle("Display reference", isOn: o.showReference)
            Toggle("Display reference measure", isOn: o.showRefMeasure)
            Picker("Temperature scale", selection: o.tempScale) {
                Text("Auto-adjust").tag(0); Text("2000K-10000K").tag(1); Text("4000K-8000K").tag(2)
            }
        case .cie, .targetCIE:
            Toggle("Display grays", isOn: $session.cieShowGrays)
            Toggle("Display saturations", isOn: o.cieSaturations)
            Toggle("Display saturations targets", isOn: o.cieSaturationTargets)
            Toggle("Display color checker measures", isOn: o.cieCCMeasures)
            Toggle("Display color checker targets", isOn: o.cieCCTargets)
            Toggle("Display free measures", isOn: o.cieFree)
            Toggle("Display references", isOn: $session.cieShowReferences)
            Toggle("Display Delta E = 3 and 10", isOn: o.cieDeltaE)
            Toggle("Worst 10%", isOn: o.cieWorst10)
            Toggle("CIE u'v' mode", isOn: $session.cieUV)
            Toggle("CIE a*b* mode", isOn: o.cieAB)
        case .nearBlackWhite:
            Toggle("Display reference", isOn: o.showReference)
            Toggle("Logarithmic mode", isOn: o.nearLog)
            Divider()
            channelToggles
            Divider()
            Picker("Luminance", selection: o.nearMode) {
                ForEach(NearMode.allCases) { Text(tr($0.rawValue)).tag($0) }
            }
        case .saturationShift:
            Toggle("Display reference", isOn: o.showReference)
            Toggle("Primary colors", isOn: o.satPrimaries)
            Toggle("Secondary colors", isOn: o.satSecondaries)
            Menu("Saturation shifts") {
                ForEach([PatchColor.red, .green, .blue, .yellow, .cyan, .magenta]) { c in
                    Toggle(tr(c.rawValue), isOn: Binding(
                        get: { !session.graphOptions.satHidden.contains(c.rawValue) },
                        set: { on in
                            session.graphOptions.satHidden.removeAll { $0 == c.rawValue }
                            if !on { session.graphOptions.satHidden.append(c.rawValue) }
                        }))
                }
            }
        case .freeHistogram:
            Toggle("Display luminance", isOn: o.freeLuminance)
            Toggle("Display x, y", isOn: o.freeXY)
            Toggle("Display Delta E", isOn: o.freeDeltaE)
            Toggle("Display color temperature", isOn: o.freeTemperature)
            Picker("Measure points", selection: o.freePoints) {
                Text("All").tag(0); Text("10 measure points").tag(10); Text("20 measure points").tag(20); Text("50 measure points").tag(50)
            }
        case .summary, .spectrum:
            Text("No options for this graph")
        }
        ForEach(scaleKeys, id: \.self) { key in
            Menu(tr("Scale") + " — " + tr(GraphScaleMenu.titles[key] ?? key)) { GraphScaleMenu(session: session, key: key) }
        }
        Divider()
        Menu("Parameters") {
            Picker("Thickness", selection: o.lineWidth) {
                Text("1").tag(1.0); Text("2").tag(2.0); Text("3").tag(3.0); Text("4").tag(4.0)
            }
            Toggle("Display dots", isOn: o.showDots)
            Toggle("Display charts with a white background", isOn: $session.appPrefs.whiteCharts)
        }
    }

    @ViewBuilder private var channelToggles: some View {
        let o = $session.graphOptions
        Toggle("Luminance", isOn: o.curveY)
        Toggle("Red", isOn: o.curveR)
        Toggle("Green", isOn: o.curveG)
        Toggle("Blue", isOn: o.curveB)
    }
}

@MainActor
enum GraphExport {
    /// HCFR's Save graph dialog: the file format and the image size.
    static let formats: [(id: String, title: String)] = [("png", "PNG"), ("jpeg", "JPEG"), ("bmp", "BMP")]
    static let sizes: [(w: CGFloat, h: CGFloat)] = [(1400, 800), (1920, 1080), (1280, 720), (1024, 768), (800, 600), (640, 480)]

    static func save<V: View>(_ view: V, name: String, session: Session) {
        let panel = NSSavePanel()
        panel.title = tr("Save graph")
        // Format and size, remembered between saves
        let format = NSPopUpButton(frame: .zero, pullsDown: false)
        format.addItems(withTitles: formats.map(\.title))
        format.selectItem(at: max(formats.firstIndex { $0.id == session.graphOptions.saveFormat } ?? 0, 0))
        let size = NSPopUpButton(frame: .zero, pullsDown: false)
        size.addItems(withTitles: sizes.map { "\(Int($0.w)) × \(Int($0.h))" })
        size.selectItem(at: min(max(session.graphOptions.saveSize, 0), sizes.count - 1))
        let row = NSStackView(views: [NSTextField(labelWithString: tr("Format:")), format,
                                      NSTextField(labelWithString: tr("Size:")), size])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        row.frame = NSRect(x: 0, y: 0, width: 420, height: 40)
        panel.accessoryView = row
        func applyType() {
            let id = formats[max(format.indexOfSelectedItem, 0)].id
            let type: UTType = id == "jpeg" ? .jpeg : id == "bmp" ? .bmp : .png
            panel.allowedContentTypes = [type]
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = base + "." + (type.preferredFilenameExtension ?? id)
        }
        panel.nameFieldStringValue = "\(session.projectName) - \(tr(name))"
        applyType()
        let target = FormatTarget(apply: applyType)
        format.target = target
        format.action = #selector(FormatTarget.changed)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = target
        let fi = max(format.indexOfSelectedItem, 0), si = max(size.indexOfSelectedItem, 0)
        session.graphOptions.saveFormat = formats[fi].id
        session.graphOptions.saveSize = si
        let dim = sizes[si]

        // Appearance → "Save chart files with a white background"
        ChartInk.forced = session.appPrefs.saveChartsWhite
        defer { ChartInk.forced = nil }
        let content = view.frame(width: dim.w - 16, height: dim.h - 16).padding(8).background(ChartInk.paper)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let fileType: NSBitmapImageRep.FileType = formats[fi].id == "jpeg" ? .jpeg : formats[fi].id == "bmp" ? .bmp : .png
        let props: [NSBitmapImageRep.PropertyKey: Any] = fileType == .jpeg ? [.compressionFactor: 0.92] : [:]
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: fileType, properties: props) else {
            session.errorMessage = "Could not render the graph."
            return
        }
        do {
            try data.write(to: url)
            session.status = tr("Graph saved: ") + url.lastPathComponent
        } catch {
            session.errorMessage = "Could not save the graph: \(error.localizedDescription)"
        }
    }

    /// Target of the format menu (changes the file extension).
    final class FormatTarget: NSObject {
        let apply: () -> Void
        init(apply: @escaping () -> Void) { self.apply = apply }
        @objc func changed() { apply() }
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
        // Area colored by wavelength (the gradient spans the measured range)
        let lo = pts.first?.0 ?? 380, hi = pts.last?.0 ?? 780
        let gradient = LinearGradient(stops: stride(from: lo, through: hi, by: max((hi - lo) / 40, 1)).map {
            Gradient.Stop(color: Self.color($0), location: (hi - lo) > 0 ? ($0 - lo) / (hi - lo) : 0)
        }, startPoint: .leading, endPoint: .trailing)
        DarkGraph(title: "Spectrum" + (session.spectra[target.id] != nil ? " — \(session.title(for: target))" : "")) {
            Chart {
                ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("nm", p.0), y: .value("Relative", p.1 / peak))
                        .foregroundStyle(gradient)
                }
                ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("nm", p.0), y: .value("Relative", p.1 / peak), series: .value("S", "Spectrum"))
                        .foregroundStyle(ChartInk.ink).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXScale(domain: 380...780)
            .chartYScale(domain: 0...1.05)
            .chartXAxis { AxisMarks(values: Array(stride(from: 400, through: 780, by: 50))) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.3))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0) nm").font(.caption2).foregroundStyle(ChartInk.ink) }
            } }
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.3))
                AxisValueLabel { Text(String(format: "%.1f", v.as(Double.self) ?? 0)).foregroundStyle(ChartInk.ink) }
            } }
            .chartPlotStyle { $0.background(ChartInk.plot) }
            .overlay(alignment: .topLeading) {
                legend(pts.isEmpty ? "No spectrum: measure with a spectrophotometer (colorimeters give no spectrum)" : nil)
            }
        }
    }
}


/// HCFR's Scale submenu of a graph: Auto-adjust, Zoom +, Zoom −, Shift Up, Shift Down, Values…
struct GraphScaleMenu: View {
    @ObservedObject var session: Session
    let key: String
    static let titles = ["luminance": "Luminance", "gamma": "Gamma", "rgb": "RGB", "temperature": "Temperature", "saturation": "Saturation"]

    /// HCFR's fixed scales of each graph's Scale menu.
    static let presets: [String: [(String, Double, Double)]] = [
        "luminance": [("0-100%", 0, 100)],
        "gamma": [("1-3", 1, 3)],
        "saturation": [("0% / +100%", 0, 100), ("-100% / +100%", -100, 100), ("-20% / +20%", -20, 20)],
    ]

    var body: some View {
        Button("Auto-adjust") { session.graphOptions.customY[key] = nil }
        ForEach(Self.presets[key] ?? [], id: \.0) { p in
            Button(p.0) { session.graphOptions.customY[key] = [p.1, p.2] }
        }
        Button("Zoom +") { change { r in let c = (r.lowerBound + r.upperBound) / 2, h = (r.upperBound - r.lowerBound) / 4; return (c - h)...(c + h) } }
        Button("Zoom −") { change { r in let c = (r.lowerBound + r.upperBound) / 2, h = r.upperBound - r.lowerBound; return (c - h)...(c + h) } }
        Button("Shift Up") { change { r in let d = (r.upperBound - r.lowerBound) / 5; return (r.lowerBound + d)...(r.upperBound + d) } }
        Button("Shift Down") { change { r in let d = (r.upperBound - r.lowerBound) / 5; return (r.lowerBound - d)...(r.upperBound - d) } }
        Button("Values…") {
            let r = current
            session.scaleDraft = [r.lowerBound, r.upperBound]
            session.editingScaleKey = key
        }
    }

    private var current: ClosedRange<Double> {
        if let r = session.graphOptions.customY[key], r.count == 2 { return r[0]...r[1] }
        return GraphScale.last[key] ?? 0...100
    }

    private func change(_ f: (ClosedRange<Double>) -> ClosedRange<Double>) {
        let r = f(current)
        session.graphOptions.customY[key] = [r.lowerBound, r.upperBound]
    }
}

/// Scale → Values…: minimum and maximum of a graph's Y axis.
struct GraphScaleValuesSheet: View {
    @ObservedObject var session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Scale") + " — " + tr(GraphScaleMenu.titles[session.editingScaleKey ?? ""] ?? "")).font(.title3.bold())
            HStack {
                Text("Minimum").frame(width: 80, alignment: .leading)
                TextField("", value: $session.scaleDraft[0], format: .number).frame(width: 100)
            }
            HStack {
                Text("Maximum").frame(width: 80, alignment: .leading)
                TextField("", value: $session.scaleDraft[1], format: .number).frame(width: 100)
            }
            HStack {
                Spacer()
                Button("Cancel") { session.editingScaleKey = nil }
                Button("OK") {
                    if let k = session.editingScaleKey, session.scaleDraft[1] > session.scaleDraft[0] {
                        session.graphOptions.customY[k] = session.scaleDraft
                    }
                    session.editingScaleKey = nil
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}
