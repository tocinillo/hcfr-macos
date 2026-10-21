// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Calibration wizard added in 2026: a guided workflow (in the style of commercial calibration
// software) over HCFR's own measures, targets and generators.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import SwiftUI

/// Choices and results of the wizard (kept while the app is open).
@MainActor
final class WizardModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, meter, generator, targets, prepare, before, whiteBalance, colors, after, finish
        var title: String {
            ["Welcome", "Meter", "Pattern generator", "Targets", "Prepare the display", "Initial readings",
             "White balance & gamma", "Colors (CMS)", "Final readings", "Report"][rawValue]
        }
        var symbol: String {
            ["sparkles", "camera.metering.center.weighted", "rectangle.on.rectangle", "scope", "tv",
             "chart.bar.doc.horizontal", "circle.lefthalf.filled", "paintpalette", "checkmark.seal", "doc.richtext"][rawValue]
        }
    }
    enum DisplayKind: Int, CaseIterable { case tv, projector }
    enum Content: Int, CaseIterable { case sdr, hdr10 }

    @Published var step = Step.welcome
    @Published var display = DisplayKind.tv
    @Published var content = Content.sdr
    /// Gamma for SDR: 0 = BT.1886, 1 = 2.2, 2 = 2.4.
    @Published var sdrGamma = 0
    @Published var balanceMultipoint = false
    @Published var before: WizardSummary?
    @Published var after: WizardSummary?
    @Published var piAddressDraft = ""
}

/// Numbers compared before / after calibration.
struct WizardSummary {
    var grayAvgDE: Double?
    var grayMaxDE: Double?
    var gamma: Double?
    var colorAvgDE: Double?
    var colorMaxDE: Double?
    var whiteY: Double?
    var cct: Double?

    @MainActor
    init(_ s: Session) {
        grayAvgDE = s.averageDeltaE
        grayMaxDE = s.maxDeltaE
        gamma = s.averageGamma
        let dEs = s.patchResults.filter { $0.patch != .white }.compactMap(\.deltaE)
        colorAvgDE = dEs.isEmpty ? nil : dEs.reduce(0, +) / Double(dEs.count)
        colorMaxDE = dEs.max()
        whiteY = s.whiteY
        cct = s.measurements[100].flatMap { ColorMath.cct($0) }
    }
}

extension Session {
    func openWizard() {
        guard activity == .idle else { return }
        wizardShown = true
    }

    func closeWizard() {
        if activity != .idle { stop() }
        wizardShown = false
    }

    /// Wizard → Targets: sets HCFR's references from the simple choices.
    func applyWizardTargets(_ w: WizardModel) {
        white = .d65
        switch w.content {
        case .sdr:
            if standard == .uhdtv2020 || standard == .uhdtvP3in2020 || standard == .uhdtvP3 { standard = .hdtv }
            switch w.sdrGamma {
            case 0: prefs.gammaMode = GammaMode.bt1886.rawValue; gamma = 2.4
            case 1: prefs.gammaMode = GammaMode.powerLaw.rawValue; gamma = 2.2
            default: prefs.gammaMode = GammaMode.powerLaw.rawValue; gamma = 2.4
            }
        case .hdr10:
            if standard == .hdtv || standard == .sdtv || standard == .sRGB { standard = .uhdtvP3in2020 }
            prefs.gammaMode = GammaMode.st2084.rawValue
        }
    }

    /// Live reading of one gray level or one color (the wizard's adjustment steps).
    func wizardLive(level: Double? = nil, patch: PatchColor? = nil) {
        if let level {
            view = .grayScale
            if levels.contains(level) { selectedLevel = level }
        }
        if let patch {
            view = .primariesSecondaries
            selectedPatch = patch
        }
        if activity == .idle { start() }
    }
}

// MARK: - View

struct WizardView: View {
    @ObservedObject var session: Session
    @ObservedObject var w: WizardModel
    /// Development snapshots: ImageRenderer doesn't draw scroll views.
    var scrolls = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            HStack(spacing: 0) {
                WizardSidebar(w: w)
                Divider()
                VStack(spacing: 0) {
                    if scrolls {
                        ScrollView { page }
                    } else {
                        page.frame(maxHeight: .infinity, alignment: .top)
                    }
                    Divider()
                    WizardFooter(session: session, w: w)
                }
            }
            .frame(width: 980, height: 660)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        }
    }

    private var page: some View {
        WizardStepView(session: session, w: w)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
    }
}

private struct WizardSidebar: View {
    @ObservedObject var w: WizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Calibration Wizard").font(.headline)
                    Text("HCFR Colorimeter").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 14)
            ForEach(WizardModel.Step.allCases, id: \.rawValue) { s in
                Button { w.step = s } label: { WizardStepRow(step: s, current: w.step) }
                    .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 230)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }
}

private struct WizardStepRow: View {
    let step: WizardModel.Step
    let current: WizardModel.Step

    var body: some View {
        let done = step.rawValue < current.rawValue, on = step == current
        return HStack(spacing: 9) {
            ZStack {
                Circle().fill(on ? Color.accentColor : done ? Color.green : Color.secondary.opacity(0.2)).frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white)
                } else {
                    Text("\(step.rawValue + 1)").font(.caption2.bold()).foregroundStyle(on ? .white : .secondary)
                }
            }
            Text(tr(step.title)).font(on ? .callout.bold() : .callout).foregroundStyle(on ? .primary : .secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor.opacity(0.12) : .clear))
        .contentShape(Rectangle())
    }
}

private struct WizardFooter: View {
    @ObservedObject var session: Session
    @ObservedObject var w: WizardModel

    var body: some View {
        HStack {
            Button("Close wizard") { session.closeWizard() }
            Spacer()
            if w.step != .welcome {
                Button { go(-1) } label: { Label("Back", systemImage: "chevron.left") }
            }
            if w.step == .finish {
                Button("Finish") { session.closeWizard() }.keyboardShortcut(.defaultAction)
            } else {
                Button { go(1) } label: { Label("Next", systemImage: "chevron.right") }
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.activity == .measuring)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func go(_ d: Int) {
        if session.activity == .continuous { session.stop() }
        if w.step == .targets && d > 0 { session.applyWizardTargets(w) }
        if let s = WizardModel.Step(rawValue: w.step.rawValue + d) { w.step = s }
    }
}

private struct WizardStepView: View {
    @ObservedObject var session: Session
    @ObservedObject var w: WizardModel

    var body: some View {
        switch w.step {
        case .welcome: WelcomeStep(w: w)
        case .meter: MeterStep(session: session)
        case .generator: GeneratorStep(session: session, w: w)
        case .targets: TargetsStep(session: session, w: w)
        case .prepare: PrepareStep(w: w)
        case .before: MeasureStep(session: session, w: w, final: false)
        case .whiteBalance: WhiteBalanceStep(session: session, w: w)
        case .colors: ColorsStep(session: session)
        case .after: MeasureStep(session: session, w: w, final: true)
        case .finish: FinishStep(session: session, w: w)
        }
    }
}

// MARK: - Step building blocks

private struct StepHeader: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr(title)).font(.title2.bold())
            Text(tr(text)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 14)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    }
}

private struct ChoiceTile: View {
    let title: String
    let detail: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.title).foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(tr(title)).font(.headline)
                Text(tr(detail)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Green / yellow / red as HCFR's Delta E highlight.
private func dEColor(_ v: Double?) -> Color {
    guard let v else { return .secondary }
    return v < 3 ? .green : v < 5 ? .yellow : .red
}

private func fmt(_ v: Double?, _ d: Int = 2) -> String {
    guard let v, v.isFinite else { return "—" }
    return String(format: "%.\(d)f", v)
}

// MARK: - Steps

private struct WelcomeStep: View {
    @ObservedObject var w: WizardModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Calibrate your display, step by step",
                       text: "The wizard measures the display, guides you while you adjust its picture controls and measures again to show the improvement. Nothing is changed in the display by the app: you make the adjustments with the remote, following the readings.")
            Text("What are you calibrating?").font(.headline)
            HStack(spacing: 12) {
                ChoiceTile(title: "TV", detail: "LCD, LED or OLED television", symbol: "tv", selected: w.display == .tv) { w.display = .tv }
                ChoiceTile(title: "Projector", detail: "Front projector and screen", symbol: "videoprojector", selected: w.display == .projector) { w.display = .projector }
            }
            Text("Which content?").font(.headline).padding(.top, 6)
            HStack(spacing: 12) {
                ChoiceTile(title: "SDR", detail: "Blu-ray, TV, streaming in standard range", symbol: "sun.min", selected: w.content == .sdr) { w.content = .sdr }
                ChoiceTile(title: "HDR10", detail: "UHD Blu-ray, streaming HDR (PQ / ST.2084)", symbol: "sun.max", selected: w.content == .hdr10) { w.content = .hdr10 }
            }
        }
    }
}

private struct MeterStep: View {
    @ObservedObject var session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Connect the meter",
                       text: "Plug in the colorimeter or spectrophotometer. Choose the display type that matches your screen technology: it is the correction the meter applies (spectral sample). For a projector, use a correction for projectors or for your model if you have one.")
            Card {
                HStack {
                    Circle().fill(session.meter != nil ? Color.green : Color.red).frame(width: 10, height: 10)
                    Text(session.meter?.name ?? tr("No colorimeter")).font(.headline)
                    Spacer()
                    Button("Search") { session.searchForMeters() }.disabled(session.busy || session.scanning)
                    Button("Connect") { session.connect() }.disabled(session.busy || session.selectedPort == nil)
                }
                if !session.ports.isEmpty && session.meter == nil {
                    Picker("Meter", selection: $session.selectedPort) {
                        ForEach(session.ports) { Text($0.displayName).tag(MeterPort?.some($0)) }
                    }
                }
                if let m = session.meter {
                    HStack {
                        Text("Display type")
                        CorrectionMenu(session: session)
                    }
                    Text("\(m.corrections.count) display types: the meter's own, HCFR's families and the display library by kind of display, technology and brand, with a search.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Card {
                Label("Place the meter", systemImage: "info.circle").font(.headline)
                Text("TV: on the screen, in the center, with the diffuser closed and the sensor touching the panel (without pressing). Projector: on a tripod facing the screen, about 1 m away, or facing the lens with the diffuser if the meter supports it. Turn off the room lights.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GeneratorStep: View {
    @ObservedObject var session: Session
    @ObservedObject var w: WizardModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Pattern generator",
                       text: "The patterns the meter reads must reach the display through the same path as your films. A Raspberry Pi with PGenerator connected to the TV or projector is the most accurate; a display of this Mac also works.")
            HStack(spacing: 12) {
                ChoiceTile(title: "Raspberry Pi", detail: "PGenerator on your network", symbol: "cpu",
                           selected: session.patternSource == .raspberryPi) { session.patternSource = .raspberryPi }
                ChoiceTile(title: "This Mac", detail: "A display connected to this Mac", symbol: "display",
                           selected: isDisplay) { useFirstDisplay() }
                ChoiceTile(title: "madVR", detail: "madVR Envy or madTPG on your network", symbol: "sparkles.tv",
                           selected: session.patternSource == .madVR) { session.patternSource = .madVR }
                ChoiceTile(title: "Manual", detail: "A calibration disc: the app asks for each pattern", symbol: "opticaldisc",
                           selected: session.patternSource == .manual) { session.patternSource = .manual }
            }
            if session.patternSource == .raspberryPi {
                Card {
                    HStack {
                        TextField("IP address (empty = automatic)", text: $w.piAddressDraft).frame(width: 220)
                            .onAppear { w.piAddressDraft = session.piAddress }
                        Button("Connect") { session.usePi(at: w.piAddressDraft) }
                        if let s = session.piStatus { Label(s, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
            }
            if session.patternSource == .madVR {
                Card {
                    HStack {
                        TextField("IP address of the Envy or of the PC with madTPG", text: $session.madVRAddressDraft).frame(width: 260)
                            .onAppear { session.madVRAddressDraft = session.madVRAddress }
                        Button("Connect") { session.setMadVRAddress(session.madVRAddressDraft) }
                        if let s = session.madVRStatus { Label(s, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
            }
            if isDisplay {
                Card {
                    Picker("Display", selection: $session.patternSource) {
                        ForEach(session.generatorScreens, id: \.self) { screen in
                            if let id = screen.displayID { Text(session.screenName(screen)).tag(PatternSource.display(id)) }
                        }
                    }
                }
            }
            Card {
                Picker("Patch size", selection: $session.patternArea) {
                    Text("Full field").tag(100.0)
                    Text("Window 18%").tag(18.0)
                    Text("Window 10%").tag(10.0)
                }
                .pickerStyle(.segmented)
                Text(w.display == .tv
                     ? "TVs: a 10% window keeps the brightness limiter (ABL) from changing the readings. Recommended for OLED."
                     : "Projectors: full field or 18% window are fine (no ABL).")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Levels", selection: $session.videoLevels) {
                    ForEach(VideoLevels.allCases) { Text(tr($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Video levels (16–235) for TVs and projectors fed by a player or a Raspberry Pi; PC levels only if the display is set to full range.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var isDisplay: Bool {
        if case .display = session.patternSource { return true }
        return false
    }

    private func useFirstDisplay() {
        if let id = session.generatorScreens.compactMap(\.displayID).first { session.patternSource = .display(id) }
    }
}

private struct TargetsStep: View {
    @ObservedObject var session: Session
    @ObservedObject var w: WizardModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Targets",
                       text: "What the display should do. The usual choices are already selected; change them only if you know you need something else.")
            Card {
                Picker("Color space", selection: $session.standard) {
                    Text("Rec.709 (HD, SDR)").tag(ColorStandard.hdtv)
                    Text("DCI-P3 inside Rec.2020 (HDR)").tag(ColorStandard.uhdtvP3in2020)
                    Text("Rec.2020").tag(ColorStandard.uhdtv2020)
                    Text("DCI-P3 D65").tag(ColorStandard.uhdtvP3)
                }
                Text("White point: D65 (6504 K), the standard for video.").font(.caption).foregroundStyle(.secondary)
            }
            if w.content == .sdr {
                Card {
                    Picker("Gamma", selection: $w.sdrGamma) {
                        Text("BT.1886").tag(0)
                        Text("2.2").tag(1)
                        Text("2.4").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Text(w.display == .projector
                         ? "Dark room projector: BT.1886 or 2.4. Use 2.2 if the room has some light."
                         : "BT.1886 for a dark room (follows the black level of the display); 2.2 for a living room with light.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Card {
                    Text("HDR10: ST.2084 (PQ) curve.").font(.headline)
                    Text("The generator must send HDR10 so the display enters its HDR mode: with a Raspberry Pi, HCFR puts PGenerator in HDR10 by itself (Generator → PGenerator output); with madVR, set its HDR output. The peak luminance and roll-off are in Preferences → References.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Card {
                Picker("Gray scale points", selection: Binding(get: { session.grayCount }, set: { session.setGrayCount($0, confirmed: true) })) {
                    Text("11 (every 10%)").tag(11)
                    Text("21 (every 5%)").tag(21)
                }
                .pickerStyle(.segmented)
                Text("11 points for a 2-point white balance; 21 if your display has a 10 or 20-point adjustment.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { session.applyWizardTargets(w) }
        .onChange(of: w.sdrGamma) { _, _ in session.applyWizardTargets(w) }
    }
}

private struct PrepareStep: View {
    @ObservedObject var w: WizardModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Prepare the display",
                       text: "Before measuring, put the display in its most accurate picture mode and turn off everything that changes the image by itself.")
            Card {
                ForEach(tips, id: \.self) { t in
                    Label { Text(tr(t)).fixedSize(horizontal: false, vertical: true) } icon: {
                        Image(systemName: "checkmark.circle").foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var tips: [String] {
        var t = ["Picture mode: Cinema, Movie, Filmmaker, Calibrated or User (the one you will use for films).",
                 "Turn off dynamic contrast, energy saving, light sensor, local dimming 'dynamic' modes and motion processing that changes brightness.",
                 "Color temperature: Warm (or Warm 2 / 6500 K).",
                 "Color space / gamut: Auto or the one that matches the content (Rec.709 for SDR).",
                 "Sharpness at its neutral value; noise reduction off."]
        if w.display == .projector {
            t.append("Let the projector warm up 30 minutes (lamp) or 15 minutes (laser), with the lens and iris as you will use them.")
            t.append("JVC: the user mode you will calibrate, Gamma 2.2 / Normal if you will use PCG custom curves.")
        } else {
            t.append("Let the TV warm up 15–30 minutes, and keep the room dark.")
        }
        return t
    }
}

private struct MeasureStep: View {
    @ObservedObject var session: Session
    @ObservedObject var w: WizardModel
    let final: Bool

    var body: some View {
        let summary = final ? w.after : w.before
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: final ? "Final readings" : "Initial readings",
                       text: final ? "Measure again with the adjustments made, to check the result."
                                   : "The app measures the gray scale and the colors as the display is now. These readings are kept to compare at the end.")
            Card {
                HStack {
                    Button {
                        startMeasure()
                    } label: { Label(final ? "Measure again" : "Measure now", systemImage: "play.fill") }
                        .controlSize(.large)
                        .disabled(session.busy || session.meter == nil)
                    if session.activity == .measuring {
                        ProgressView().controlSize(.small)
                        Text(trMessage(session.status)).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { session.stop() }
                    }
                }
                if session.meter == nil {
                    Text("Connect a meter first (step 2).").font(.caption).foregroundStyle(.red)
                }
            }
            if let summary { SummaryCard(summary: summary, compare: final ? w.before : nil) }
        }
        .onChange(of: session.activity) { old, new in
            if old == .measuring && new == .idle && session.hasMeasurements {
                if final { w.after = WizardSummary(session) } else {
                    w.before = WizardSummary(session)
                    // Kept as the comparison project: rows "dE / ref" and dashed lines in the graphs
                    var d = ReferenceData(name: tr("Before calibration"))
                    d.gray = session.measurements
                    d.colors = session.colorMeasurements
                    session.refData = d
                }
            }
        }
    }

    private func startMeasure() {
        session.wizardSkipConfirm = true
        session.measure(.grayScaleAndColors)
    }
}

private struct SummaryCard: View {
    let summary: WizardSummary
    let compare: WizardSummary?

    var body: some View {
        Card {
            Text(compare == nil ? "Results" : "Before → After").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                row("Gray scale ΔE average", compare?.grayAvgDE, summary.grayAvgDE, dE: true)
                row("Gray scale ΔE maximum", compare?.grayMaxDE, summary.grayMaxDE, dE: true)
                row("Average gamma", compare?.gamma, summary.gamma, dE: false)
                row("Colors ΔE average", compare?.colorAvgDE, summary.colorAvgDE, dE: true)
                row("Colors ΔE maximum", compare?.colorMaxDE, summary.colorMaxDE, dE: true)
                row("White (cd/m²)", compare?.whiteY, summary.whiteY, dE: false, digits: 1)
                row("White CCT (K)", compare?.cct, summary.cct, dE: false, digits: 0)
            }
            Text("ΔE below 3 is not visible; below 1, excellent.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(_ name: String, _ before: Double?, _ now: Double?, dE: Bool, digits: Int = 2) -> some View {
        GridRow {
            Text(tr(name))
            if compare != nil {
                Text(fmt(before, digits)).monospacedDigit().foregroundStyle(dE ? dEColor(before) : .primary)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
            }
            Text(fmt(now, digits)).monospacedDigit().bold().foregroundStyle(dE ? dEColor(now) : .primary)
        }
    }
}

private struct WhiteBalanceStep: View {
    @ObservedObject var session: Session
    @ObservedObject var w: WizardModel

    var body: some View {
        let r = session.results.first { $0.level == session.selectedLevel }
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "White balance & gamma",
                       text: "Adjust the display's white balance while the app reads continuously. Bring the three bars to 100%: high level with the Gain (or 'Contrast' R/G/B) controls, low level with Offset / Bias / Cut. Then check gamma (the luminance against its target).")
            Picker("", selection: $w.balanceMultipoint) {
                Text("2 points").tag(false)
                Text("Multipoint (every level)").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 360)
            Card {
                HStack(spacing: 6) {
                    ForEach(levelsShown, id: \.self) { l in
                        Button("\(Reference.label(l))%") { session.wizardLive(level: l) }
                            .buttonStyle(.bordered)
                            .tint(session.selectedLevel == l && session.view == .grayScale ? .accentColor : .gray)
                    }
                    Spacer()
                    LiveButton(session: session) { session.wizardLive(level: session.selectedLevel) }
                }
                if !w.balanceMultipoint {
                    Text(session.selectedLevel >= 70 ? "High level: adjust Gain R / G / B." : "Low level: adjust Offset (Bias / Cut) R / G / B.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                BalanceBars(values: r?.balance)
                HStack(spacing: 24) {
                    Metric(name: "ΔE", value: fmt(r?.deltaE, 1), color: dEColor(r?.deltaE))
                    Metric(name: "Y (cd/m²)", value: fmt(r?.xyz?.Y, 2), color: .primary)
                    Metric(name: "Y target", value: fmt(r?.targetY, 2), color: .secondary)
                    Metric(name: "Gamma", value: fmt(r?.gamma, 2), color: .primary)
                    Metric(name: "CCT (K)", value: fmt(r?.cct, 0), color: .primary)
                }
            }
            Text("Tip: adjust the high level first, then the low one, and go back to the high one: they affect each other a little.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { session.wizardLive(level: w.balanceMultipoint ? session.selectedLevel : 100) }
    }

    private var levelsShown: [Double] {
        w.balanceMultipoint ? session.levels.filter { $0 > 0 } : [20, 30, 80, 100].filter { session.levels.contains($0) }
    }
}

private struct ColorsStep: View {
    @ObservedObject var session: Session

    var body: some View {
        let p = session.patchResults.first { $0.patch == session.selectedPatch }
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Colors (CMS)",
                       text: "If your display has a color management system (CMS), adjust each color's Hue, Saturation and Luminance until the errors are close to zero. Without a CMS, just look at the readings: they show how accurate the colors are.")
            Card {
                HStack(spacing: 6) {
                    ForEach([PatchColor.red, .green, .blue, .cyan, .magenta, .yellow], id: \.self) { c in
                        Button { session.wizardLive(patch: c) } label: {
                            HStack(spacing: 5) {
                                Circle().fill(CIEChart.markerColor(c)).frame(width: 10, height: 10)
                                Text(tr(c.rawValue))
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(session.selectedPatch == c && session.view == .primariesSecondaries ? .accentColor : .gray)
                    }
                    Spacer()
                    LiveButton(session: session) { session.wizardLive(patch: session.selectedPatch) }
                }
                let e = Self.errors(p, session: session)
                VStack(alignment: .leading, spacing: 10) {
                    ErrorBar(name: "Luminance", value: e.lum, unit: "%", range: 10)
                    ErrorBar(name: "Saturation", value: e.sat, unit: "%", range: 10)
                    ErrorBar(name: "Hue", value: e.hue, unit: "°", range: 10)
                }
                HStack(spacing: 24) {
                    Metric(name: "ΔE", value: fmt(p?.deltaE, 1), color: dEColor(p?.deltaE))
                    Metric(name: "Δxy", value: fmt(p?.deltaxy, 4), color: .primary)
                }
            }
            Text("Measure 100% white first (step 6 or 'Initial readings'): the color luminances are relative to it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { session.wizardLive(patch: session.selectedPatch) }
    }

    /// Luminance (%), saturation (chroma, %) and hue (°) errors against the reference color.
    static func errors(_ p: PatchResult?, session: Session) -> (lum: Double?, sat: Double?, hue: Double?) {
        guard let p, let lch = p.lch else { return (p?.deltaL.map { $0 * 100 }, nil, nil) }
        let refLab = ColorMath.lab(p.reference.scaled(session.colorWhiteY), whiteY: session.colorWhiteY, white: session.ref.white)
        let refLch = ColorMath.lch(refLab)
        let sat = refLch[1] > 0 ? (lch[1] / refLch[1] - 1) * 100 : nil
        var dh = lch[2] - refLch[2]
        if dh > 180 { dh -= 360 }
        if dh < -180 { dh += 360 }
        return (p.deltaL.map { $0 * 100 }, sat, dh)
    }
}

private struct FinishStep: View {
    @ObservedObject var session: Session
    @ObservedObject var w: WizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Done",
                       text: "Save the project to keep the readings, and make a report to see or share the result.")
            if let a = w.after { SummaryCard(summary: a, compare: w.before) }
            HStack(spacing: 10) {
                Button { session.saveProject() } label: { Label("Save project", systemImage: "square.and.arrow.down") }
                Button { session.exportPDFReport() } label: { Label("Create PDF Report…", systemImage: "doc.richtext") }
                Button { session.exportHCFRSheets() } label: { Label("Export HCFR sheets (CSV)…", systemImage: "tablecells") }
            }
            .controlSize(.large)
            .disabled(!session.hasMeasurements)
            Text("The readings stay in the main window: there you can see every graph (CIE, gamma, RGB levels…) and keep measuring.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Small widgets

private struct LiveButton: View {
    @ObservedObject var session: Session
    let start: () -> Void
    var body: some View {
        if session.activity == .continuous {
            Button { session.stop() } label: { Label("Stop", systemImage: "stop.fill") }.tint(.red)
        } else {
            Button(action: start) { Label("Read continuously", systemImage: "play.fill") }
                .disabled(session.busy || session.meter == nil)
        }
    }
}

private struct Metric: View {
    let name: String
    let value: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tr(name)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().bold()).foregroundStyle(color)
        }
    }
}

/// R, G, B balance (100% = exact gray) as three horizontal bars around the center.
private struct BalanceBars: View {
    let values: [Double]?
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                bar(i)
            }
        }
    }

    private func bar(_ i: Int) -> some View {
        let v = values?[safe: i]
        let color: Color = [.red, .green, .blue][i]
        return HStack(spacing: 10) {
            Text(["R", "G", "B"][i]).font(.headline).foregroundStyle(color).frame(width: 18)
            GeometryReader { g in
                let w = g.size.width
                let offset = CGFloat(max(-10, min(10, (v ?? 100) - 100))) / 10 * w / 2
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12))
                    Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 2).offset(x: w / 2 - 1)
                    if v != nil {
                        RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.85))
                            .frame(width: abs(offset), height: 16)
                            .offset(x: offset >= 0 ? w / 2 : w / 2 + offset)
                    }
                }
            }
            .frame(height: 22)
            Text(v.map { String(format: "%.1f%%", $0) } ?? "—").monospacedDigit().frame(width: 64, alignment: .trailing)
        }
    }
}

/// An error (e.g. +2.3 %) as a bar around zero, green when small.
private struct ErrorBar: View {
    let name: String
    let value: Double?
    let unit: String
    let range: Double
    var body: some View {
        HStack(spacing: 10) {
            Text(tr(name)).frame(width: 90, alignment: .leading)
            GeometryReader { g in
                let w = g.size.width
                let v = value ?? 0
                let offset = CGFloat(max(-range, min(range, v)) / range) * w / 2
                let color: Color = abs(v) < 2 ? .green : abs(v) < 5 ? .yellow : .red
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12))
                    Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 2).offset(x: w / 2 - 1)
                    if value != nil {
                        RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.85))
                            .frame(width: abs(offset), height: 14)
                            .offset(x: offset >= 0 ? w / 2 : w / 2 + offset)
                    }
                }
            }
            .frame(height: 20)
            Text(value.map { String(format: "%+.1f%@", $0, unit) } ?? "—").monospacedDigit().frame(width: 64, alignment: .trailing)
        }
    }
}
