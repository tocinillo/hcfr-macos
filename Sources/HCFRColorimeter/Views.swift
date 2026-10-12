// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI
import Charts

private let channelColors: [Color] = [.red, .green, .blue]
/// Delta E cell colors and thresholds of HCFR for CIE2000 (MainView.cpp):
/// green < 2.0, yellow < 3.0, red otherwise — RGB(175,255,175) / (255,255,175) / (255,175,175).
private func deltaEColor(_ dE: Double) -> Color {
    if dE < 2.0 { return Color(red: 175 / 255, green: 1, blue: 175 / 255) }
    if dE < 3.0 { return Color(red: 1, green: 1, blue: 175 / 255) }
    return Color(red: 1, green: 175 / 255, blue: 175 / 255)
}
private let blackCell = Color(red: 1.0, green: 0.85, blue: 0.70)

private func fmt(_ v: Double?, _ digits: Int) -> String {
    guard let v, v.isFinite else { return "" }
    return String(format: "%.\(digits)f", v)
}

private struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }
}

struct ContentView: View {
    @ObservedObject var session: Session
    var autoConnect = true

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ActionsPanel(session: session)
                ViewPanel(session: session)
                SensorPanel(session: session)
            }
            .frame(height: 122)

            if session.view == .grayScale {
                MeasuresGrid(session: session)
            } else {
                PrimariesGrid(session: session)
            }

            HStack(alignment: .top, spacing: 8) {
                SelectedColorPanel(session: session).frame(width: 370)
                Panel(title: "Information") { GrayScaleChart(session: session) }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .bottom) {
            HStack {
                if session.busy || session.scanning { ProgressView().controlSize(.small) }
                Text(session.status).font(.callout)
                Spacer()
                if session.activity != .idle {
                    Text("ESC cancels measuring").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.bar)
        }
        .alert("New project", isPresented: $session.confirmNewProject) {
            Button("Yes, clear everything", role: .destructive) { session.newProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure? All measurements will be deleted and values reset to zero.")
        }
        .sheet(item: $session.prompt) { p in
            PromptSheet(prompt: p, session: session).onAppear { session.promptDidAppear(p.id) }
        }
        .alert("Error", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(session.errorMessage ?? "")
        }
        .onAppear {
            if autoConnect { session.startScanning() }
            // Don't start with the cursor in the Power Law Gamma field (first text field of the window)
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .navigationTitle("HCFR Colorimeter — \(session.projectName)\(session.isDirty ? " (edited)" : "")")
    }
}

private struct PromptSheet: View {
    let prompt: UserPrompt
    @ObservedObject var session: Session

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 34)).foregroundStyle(prompt.style == .position ? .red : .blue)
            VStack(alignment: .leading, spacing: 16) {
                Text(prompt.title).font(.headline)
                Text(prompt.message).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(prompt.style == .yesNo ? "No" : "Cancel") { session.answerPrompt(proceed: false) }
                        .keyboardShortcut(.cancelAction)
                    Button(prompt.style == .yesNo ? "Yes" : prompt.style == .position ? "OK" : "Continue") { session.answerPrompt(proceed: true) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22).frame(width: 440)
        .interactiveDismissDisabled()
    }

    private var icon: String {
        switch prompt.style {
        case .yesNo: return "questionmark.circle.fill"
        case .continueCancel: return "info.circle.fill"
        case .position: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Top bar

private struct ActionsPanel: View {
    @ObservedObject var session: Session

    var body: some View {
        Panel(title: "Actions") {
            VStack(alignment: .leading, spacing: 4) {
            // Row 1: project
            HStack(spacing: 4) {
                ActionButton(title: "New project", symbol: "doc.badge.plus", tint: .primary) {
                    session.confirmNewProject = true
                }
                .disabled(session.activity != .idle)

                ActionButton(title: "Open project", symbol: "folder", tint: .primary) {
                    session.openProjectDialog()
                }
                .disabled(session.activity != .idle)
                .help("Open a saved project (.hcfrex)")

                ActionButton(title: "Save project", symbol: "square.and.arrow.down", tint: .primary) {
                    session.saveProject()
                }
                .disabled(session.activity != .idle || !session.hasMeasurements)
                .help("Save the measurements and settings to a project file (.hcfrex)")

                ActionButton(title: "Print", symbol: "printer", tint: .primary) {
                    Report.printReport(session)
                }
                .disabled(session.activity == .measuring || !session.hasMeasurements)
                .help("Print the gray scale and colors tables (the print dialog can also save a PDF)")
            }
            // Row 2: measuring
            HStack(spacing: 4) {
                if session.activity == .continuous {
                    ActionButton(title: "Stop", symbol: "stop.fill", tint: .red) { session.stop() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    ActionButton(title: "Start", symbol: "play.fill", tint: .green) { session.start() }
                        .disabled(session.busy || session.meter == nil)
                        .help("Continuous reading of the selected column (gray level or color). Click another column to measure it.")
                }

                if session.activity == .measuring {
                    ActionButton(title: "Cancel", symbol: "xmark.octagon.fill", tint: .red) { session.stop() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    ActionButton(title: "Measure", symbol: "checklist", tint: .blue) { MeasureMenu.show(for: session) }
                        .disabled(session.busy || session.meter == nil)
                        .help("Choose the test: Grey scale (\(session.levels.first ?? 10) to 100 IRE), Grey scale and colors, Primary colors, or Primary and secondary colors")
                }

                GeneratorMenu(session: session)
            }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Pattern generator: manual (DVD / external generator) or a display of this Mac, with its options.
private struct GeneratorMenu: View {
    @ObservedObject var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Generator").font(.caption2).foregroundStyle(.secondary)
            Menu {
                Picker("Generator", selection: $session.patternSource) {
                    Text("DVD / external generator (manual)").tag(PatternSource.manual)
                    Text("Raspberry Pi (PGenerator)").tag(PatternSource.raspberryPi)
                    ForEach(session.generatorScreens, id: \.self) { screen in
                        if let id = screen.displayID {
                            Text(session.screenName(screen)).tag(PatternSource.display(id))
                        }
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button(piAddressTitle) {
                    session.piAddressDraft = session.piAddress
                    session.editingPiAddress = true
                }
                if session.patternSource == .raspberryPi {
                    if let s = session.piStatus {
                        Text("Raspberry Pi connected: \(s)")
                    } else {
                        Button("Connect to Raspberry Pi now") { session.connectPi() }
                    }
                }
                Divider()
                Picker("Levels", selection: $session.videoLevels) {
                    ForEach(VideoLevels.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Patch size", selection: $session.patternArea) {
                    Text("Full field").tag(100.0)
                    Text("Window 50%").tag(50.0)
                    Text("Window 25%").tag(25.0)
                    Text("Window 10%").tag(10.0)
                }
                Picker("Wait before reading", selection: $session.settleSeconds) {
                    ForEach([0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { Text(String(format: "%.1f s", $0)).tag($0) }
                }
            } label: {
                Text(label).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(session.activity != .idle)
            .help("Where the patterns come from: your DVD / external generator (the app asks for each one), a Raspberry Pi running PGenerator on your network, or a display connected to this Mac (the app shows each pattern full screen)")
        }
        .padding(.leading, 4)
        .alert("Raspberry Pi address", isPresented: $session.editingPiAddress) {
            TextField("Automatic", text: $session.piAddressDraft)
            Button("OK") { session.setPiAddress(session.piAddressDraft) }
            Button("Automatic") { session.setPiAddress("") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("IP address of the Raspberry Pi running PGenerator (for example 192.168.1.50). Leave it empty to find the Pi automatically on the local network.")
        }
    }

    private var piAddressTitle: String {
        "Raspberry Pi address: " + (session.piAddress.isEmpty ? "automatic" : session.piAddress) + "…"
    }

    private var label: String {
        if session.patternSource == .raspberryPi { return "Raspberry Pi" }
        guard let screen = session.patternScreen else { return "DVD (manual)" }
        let n = (NSScreen.screens.firstIndex(of: screen) ?? 0) + 1
        return "Display \(n)"
    }
}

/// Pop-up menu of the Measure button (Grey scale is the default, first item).
@MainActor
private enum MeasureMenu {
    private final class Target: NSObject {
        var actions: [() -> Void] = []
        @objc func run(_ sender: NSMenuItem) { actions[sender.tag]() }
    }
    private static let target = Target()

    static func show(for session: Session) {
        let menu = NSMenu()
        target.actions = MeasureKind.allCases.map { kind in { session.measure(kind) } }
        for (i, kind) in MeasureKind.allCases.enumerated() {
            let item = NSMenuItem(title: kind.title,
                                  action: #selector(Target.run(_:)), keyEquivalent: "")
            item.target = target
            item.tag = i
            menu.addItem(item)
        }
        menu.popUp(positioning: menu.item(at: 0), at: NSEvent.mouseLocation, in: nil)
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(tint)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: 64, height: 38)
        }
        .buttonStyle(.bordered)
    }
}

private struct ViewPanel: View {
    @ObservedObject var session: Session

    var body: some View {
        Panel(title: "View") {
            HStack(spacing: 8) {
                Picker("View", selection: $session.view) {
                    ForEach(MeasureView.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(session.activity == .measuring)
                Text(infoLine).font(.system(.caption, design: .monospaced)).lineLimit(2)
            }
            HStack(spacing: 14) {
                Picker("Standard", selection: $session.standard) {
                    ForEach(ColorStandard.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(minWidth: 160, maxWidth: 320)
                HStack(spacing: 6) {
                    Text("White").fixedSize().layoutPriority(1)
                    Picker("White", selection: $session.white) {
                        ForEach(WhitePoint.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
            .disabled(session.activity != .idle)
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Text("Power Law Gamma").fixedSize()
                    TextField("", value: $session.gamma, format: .number.precision(.fractionLength(2)))
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $session.gamma, in: 1.0...4.0, step: 0.05).labelsHidden()
                }
                .disabled(session.standard.usesSRGBCurve)
                .help(session.standard.usesSRGBCurve ? "sRGB uses its own tone curve instead of a power law gamma." : "Target gamma (power law). Default 2.3.")
                Toggle("Override black", isOn: $session.overrideBlack)
                    .help("""
                        Override black (0 cd/m²): when on, 0 IRE is not measured and black is taken as a perfect 0 cd/m².                         CRT and LCD displays never reach a true black and colorimeters read such low light poorly,                         so measuring it adds noise to contrast and the low end.                         Turn it off to measure 0 IRE, e.g. on an OLED, whose black is truly black and measures well.
                        """)
                Spacer(minLength: 0)
            }
            .disabled(session.activity != .idle)
        }
    }

    private var infoLine: String {
        let r = session.ref
        var s = "Color Space: \(r.standard.shortName), White Point: \(r.white.rawValue) (\(r.white.kelvin) K), EOTF: SDR, "
        s += r.standard.usesSRGBCurve ? "sRGB" : "Power law w/gamma = \(String(format: "%.2f", r.gamma))"
        let count = session.view == .grayScale
            ? session.measurements.filter { $0.key > 0 || !session.overrideBlack }.count
            : session.colorMeasurements.count
        s += ", # of measures: \(count)"
        if let d = session.lastMeasure {
            s += " [\(d.formatted(date: .omitted, time: .standard))]"
        }
        return s
    }
}

private struct SensorPanel: View {
    @ObservedObject var session: Session

    var body: some View {
        Panel(title: "Sensor") {
            // 1) Colorimeter
            HStack(spacing: 6) {
                Circle().fill(session.meter != nil ? .green : .red).frame(width: 9, height: 9)
                if session.ports.count > 1 {
                    Picker("", selection: Binding(get: { session.selectedPort }, set: { session.selectedPort = $0 })) {
                        ForEach(session.ports) { Text($0.displayName).tag(MeterPort?.some($0)) }
                    }
                    .labelsHidden()
                    .disabled(session.activity != .idle)
                } else {
                    Text(session.selectedPort?.displayName ?? session.meter?.name ?? "No colorimeter")
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            // 2) Search / Connect
            HStack {
                Button("Search") { session.searchForMeters() }
                    .disabled(session.busy || session.scanning)
                    .help("Look for newly connected colorimeters")
                Button("Connect") { session.connect() }
                    .disabled(session.busy || session.selectedPort == nil)
                    .help("Connect to the colorimeter selected above")
                Spacer(minLength: 0)
            }
            // 3) Display
            Picker("Display", selection: Binding(get: { session.correction }, set: { if let c = $0 { session.setCorrection(c) } })) {
                if let m = session.meter {
                    ForEach(m.corrections) { c in Text(c.name).tag(MeterCorrection?.some(c)) }
                } else {
                    Text("Connect a colorimeter").tag(MeterCorrection?.none)
                }
            }
            .disabled(session.meter == nil || session.activity != .idle)
            .help("Display type of the colorimeter, same list and behavior as HCFR for Windows (Non-Refresh, Refresh, CRT, LCD/LED families, OLED, Projector…).")
        }
        .frame(width: 290)
    }
}

// MARK: - Measures table

private struct MeasuresGrid: View {
    @ObservedObject var session: Session

    var body: some View {
        let results = session.results
        VStack(alignment: .leading, spacing: 4) {
            Text(summary).font(.caption.monospaced()).foregroundStyle(.secondary)
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    header("% White", width: 90)
                    ForEach(results) { r in
                        header("\(r.level)", selected: r.level == session.selectedLevel)
                            .onTapGesture { select(r.level) }
                    }
                }
                row("x", results) { r in isOverridden(r) ? "nan" : isBase(r) ? fmt(session.white.x, 4) : fmt(r.xyz?.x, 4) }
                row("y", results) { r in isOverridden(r) ? "nan" : isBase(r) ? fmt(session.white.y, 4) : fmt(r.xyz?.y, 4) }
                row("Y", results) { r in isOverridden(r) ? "0" : isBase(r) ? fmt(baseWhiteY, 3) : fmt(r.xyz?.Y, 3) }
                GridRow {
                    label("Delta E")
                    ForEach(results) { r in
                        let de = isBase(r) ? 0.0 : r.deltaE
                        cell(isOverridden(r) ? "" : fmt(de, 1), level: r.level, bold: true,
                             fill: de.map(deltaEColor))
                    }
                }
                row("delta xy", results) { r in isOverridden(r) ? "" : isBase(r) ? fmt(0, 4) : fmt(r.deltaxy, 4) }
                row("Y target", results) { r in fmt(r.targetY, 3) }
            }
            .font(.system(.body, design: .monospaced))
            .overlay(Rectangle().stroke(.separator))
        }
    }

    private var summary: String {
        "( Average Gamma: \(fmt(session.averageGamma, 2).isEmpty ? "—" : fmt(session.averageGamma, 2)), Contrast: \(contrastText) )  "
        + "( Average dE: \(fmt(session.averageDeltaE, 2).isEmpty ? "—" : fmt(session.averageDeltaE, 2)), max: \(fmt(session.maxDeltaE, 2).isEmpty ? "—" : fmt(session.maxDeltaE, 2)) [CIE2000] )  [Absolute Y w/o gamma]"
    }

    private func select(_ level: Int) { session.select(level: level) }

    private var contrastText: String {
        guard let c = session.contrast else { return "—" }
        return c.isInfinite ? "Infinity:1" : String(format: "%.0f:1", c)
    }

    private func isOverridden(_ r: StepResult) -> Bool { r.level == 0 && session.overrideBlack }

    /// 100% not measured yet: HCFR shows the reference white with Y = 120 cd/m² as the base.
    private func isBase(_ r: StepResult) -> Bool { r.level == 100 && r.xyz == nil }

    private func row(_ title: String, _ results: [StepResult], _ value: @escaping (StepResult) -> String) -> some View {
        GridRow {
            label(title)
            ForEach(results) { r in cell(value(r), level: r.level) }
        }
    }

    private func header(_ text: String, width: CGFloat? = nil, selected: Bool = false) -> some View {
        Text(text).bold()
            .frame(maxWidth: width ?? .infinity, minHeight: 21)
            .frame(width: width)
            .background(selected ? Color.accentColor.opacity(0.35) : Color.gray.opacity(0.35))
            .overlay(Rectangle().stroke(.separator, lineWidth: 0.5))
            .contentShape(Rectangle())
    }

    private func label(_ text: String) -> some View {
        Text(text).bold()
            .frame(width: 90, height: 21)
            .background(Color.gray.opacity(0.15))
            .overlay(Rectangle().stroke(.separator, lineWidth: 0.5))
    }

    private func cell(_ text: String, level: Int, bold: Bool = false, fill: Color? = nil) -> some View {
        let overridden = level == 0 && session.overrideBlack
        let background: Color = fill ?? (overridden ? blackCell : (level == session.selectedLevel ? Color.accentColor.opacity(0.10) : .clear))
        return Text(text)
            .fontWeight(bold ? .bold : .regular)
            .foregroundStyle(fill != nil ? Color.black : (overridden ? Color.blue : Color.primary))
            .frame(maxWidth: .infinity, minHeight: 21, alignment: .trailing)
            .padding(.trailing, 6)
            .background(background)
            .overlay(Rectangle().stroke(.separator, lineWidth: 0.5))
            .contentShape(Rectangle())
            .onTapGesture { select(level) }
    }
}

// MARK: - Primaries and secondaries table

/// HCFR's "Primaries and secondaries" view: Red…Magenta, White and Black columns with
/// x, y, Y, Delta E, delta xy and delta L rows.
private struct PrimariesGrid: View {
    @ObservedObject var session: Session

    private static let headerTint: [PatchColor: Color] = [
        .red: Color(red: 240 / 255, green: 200 / 255, blue: 200 / 255),
        .green: Color(red: 200 / 255, green: 240 / 255, blue: 200 / 255),
        .blue: Color(red: 200 / 255, green: 200 / 255, blue: 240 / 255),
        .yellow: Color(red: 240 / 255, green: 240 / 255, blue: 200 / 255),
        .cyan: Color(red: 200 / 255, green: 240 / 255, blue: 240 / 255),
        .magenta: Color(red: 240 / 255, green: 200 / 255, blue: 240 / 255),
    ]

    var body: some View {
        let results = session.patchResults
        let black = session.overrideBlack ? nil : session.measurements[0]
        VStack(alignment: .leading, spacing: 4) {
            Text(summary).font(.caption.monospaced()).foregroundStyle(.secondary)
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    label("Color")
                    ForEach(results) { r in
                        Text(r.patch.rawValue).bold()
                            .foregroundStyle(Self.headerTint[r.patch] != nil ? Color.black : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 21)
                            .background(Self.headerTint[r.patch] ?? Color.gray.opacity(0.35))
                            .overlay(r.patch == session.selectedPatch ? Rectangle().stroke(Color.accentColor, lineWidth: 2) : nil)
                            .overlay(Rectangle().stroke(.separator, lineWidth: 0.5))
                            .contentShape(Rectangle())
                            .onTapGesture { session.select(patch: r.patch) }
                    }
                    Text("Black").bold()
                        .frame(maxWidth: .infinity, minHeight: 21)
                        .background(Color.gray.opacity(0.35))
                        .overlay(Rectangle().stroke(.separator, lineWidth: 0.5))
                }
                row("x", results, black: black.map { fmt($0.x, 4) } ?? "nan") { r in isBase(r) ? fmt(session.white.x, 4) : fmt(r.xyz?.x, 4) }
                row("y", results, black: black.map { fmt($0.y, 4) } ?? "nan") { r in isBase(r) ? fmt(session.white.y, 4) : fmt(r.xyz?.y, 4) }
                row("Y", results, black: black.map { fmt($0.Y, 3) } ?? "0") { r in isBase(r) ? fmt(session.colorWhiteY, 3) : fmt(r.xyz?.Y, 3) }
                GridRow {
                    label("Delta E")
                    ForEach(results) { r in
                        let de = isBase(r) ? 0.0 : r.deltaE
                        cell(fmt(de, 1), patch: r.patch, bold: true, fill: de.map(deltaEColor))
                    }
                    blackColumnCell("", measured: black != nil)
                }
                row("delta xy", results, black: "") { r in isBase(r) ? fmt(0, 4) : fmt(r.deltaxy, 4) }
                row("delta L", results, black: "") { r in isBase(r) ? "=" : r.deltaLText }
            }
            .font(.system(.body, design: .monospaced))
            .overlay(Rectangle().stroke(.separator))
        }
    }

    private var summary: String {
        let d = session.colorDeltaEs
        let avg = d.isEmpty ? "—" : fmt(d.reduce(0, +) / Double(d.count), 2)
        let mx = d.max().map { fmt($0, 2) } ?? "—"
        return "( Average dE: \(avg), max: \(mx) [CIE2000] )  Reference: \(session.standard.shortName) primaries, 100% saturation"
    }

    /// White not measured (no color run and no gray scale 100%): reference white with the 120 base.
    private func isBase(_ r: PatchResult) -> Bool { r.patch == .white && r.xyz == nil }

    private func row(_ title: String, _ results: [PatchResult], black: String, _ value: @escaping (PatchResult) -> String) -> some View {
        GridRow {
            label(title)
            ForEach(results) { r in cell(value(r), patch: r.patch) }
            blackColumnCell(black, measured: !session.overrideBlack && session.measurements[0] != nil)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).bold()
            .frame(width: 90, height: 21)
            .background(Color.gray.opacity(0.15))
            .overlay(Rectangle().stroke(.separator, lineWidth: 0.5))
    }

    private func cell(_ text: String, patch: PatchColor, bold: Bool = false, fill: Color? = nil) -> some View {
        Text(text)
            .fontWeight(bold ? .bold : .regular)
            .foregroundStyle(fill != nil ? Color.black : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 21, alignment: .trailing)
            .padding(.trailing, 6)
            .background(fill ?? (patch == session.selectedPatch ? Color.accentColor.opacity(0.10) : .clear))
            .overlay(Rectangle().stroke(.separator, lineWidth: 0.5))
            .contentShape(Rectangle())
            .onTapGesture { session.select(patch: patch) }
    }

    /// Black column: gray scale 0% when measured, else HCFR's override look (nan / 0).
    private func blackColumnCell(_ text: String, measured: Bool) -> some View {
        Text(text)
            .foregroundStyle(measured ? Color.primary : Color.blue)
            .frame(maxWidth: .infinity, minHeight: 21, alignment: .trailing)
            .padding(.trailing, 6)
            .background(measured ? Color.clear : blackCell)
            .overlay(Rectangle().stroke(.separator, lineWidth: 0.5))
    }
}

// MARK: - Selected color

private struct SelectedColorPanel: View {
    @ObservedObject var session: Session

    var body: some View {
        let r = session.selectedReading
        Panel(title: "Selected color — \(r.title)") {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RGB Levels").font(.caption)
                    RGBLevels(result: r).frame(height: 100)
                    Swatches(result: r).frame(height: 46)
                    Text("Target").font(.caption)
                    TargetView(result: r).frame(width: 104, height: 78)
                }
                .frame(width: 180)
                CurrentMeasureTable(result: r)
            }
        }
    }
}

private struct RGBLevels: View {
    let result: ColorReading

    var body: some View {
        let values = result.bars
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                bar(value: values?[i], text: values.map { String(format: "%.1f%%", $0[i]) } ?? "0.0%",
                    color: channelColors[i], scale: { max($0, 0) / 140 })
            }
            bar(value: result.deltaE, text: "dE " + (fmt(result.deltaE, 1).isEmpty ? "0.0" : fmt(result.deltaE, 1)),
                color: .yellow, scale: { $0 / 10 })
        }
    }

    private func bar(value: Double?, text: String, color: Color, scale: @escaping (Double) -> Double) -> some View {
        GeometryReader { geo in
            let k = min(max(value.map(scale) ?? 0, 0.02), 1)
            let h = (geo.size.height - 18) * k
            VStack(spacing: 3) {
                Spacer(minLength: 0)
                Text(text).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.6)
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [color.opacity(0.7), color, color.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: h)
            }
        }
    }
}

private struct Swatches: View {
    let result: ColorReading

    var body: some View {
        HStack(spacing: 0) {
            swatch(result.measureRGB, label: "Measure")
            swatch(result.referenceRGB, label: "Reference")
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
    }

    private func swatch(_ rgb: [Int]?, label: String) -> some View {
        let c = rgb ?? [0, 0, 0]
        let bright = c.reduce(0, +) > 380
        return ZStack {
            Color(red: Double(c[0]) / 255, green: Double(c[1]) / 255, blue: Double(c[2]) / 255)
            VStack(spacing: 2) {
                Text(rgb.map { "\($0[0]),\($0[1]),\($0[2])" } ?? "No measure")
                Text(label)
            }
            .font(.caption.bold())
            .foregroundStyle(bright ? .black : .white)
        }
    }
}

/// Chromaticity target: shows where the measurement drifts from its reference (white or color).
private struct TargetView: View {
    let result: ColorReading

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [.green, .cyan, .blue, .purple, .red, .orange, .yellow]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)))
            let inner = rect.insetBy(dx: 14, dy: 12)
            let m = result.measureRGB ?? [0, 0, 0]
            let gray = Double(m.reduce(0, +)) / 765
            ctx.fill(Path(roundedRect: inner, cornerRadius: 10),
                     with: .color(Color(red: Double(m[0]) / 255, green: Double(m[1]) / 255, blue: Double(m[2]) / 255)))
            let c = CGPoint(x: inner.midX, y: inner.midY)
            let lineColor: Color = gray > 0.5 ? .black : .white
            for r in [inner.height * 0.18, inner.height * 0.38] {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 1.4, y: c.y - r, width: r * 2.8, height: r * 2)),
                           with: .color(lineColor.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            var cross = Path()
            cross.move(to: CGPoint(x: inner.minX, y: c.y)); cross.addLine(to: CGPoint(x: inner.maxX, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: inner.minY)); cross.addLine(to: CGPoint(x: c.x, y: inner.maxY))
            ctx.stroke(cross, with: .color(lineColor.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

            guard let xyz = result.xyz, xyz.Y > 0 else { return }
            // Scale: the edge of the box is a deviation of `targetRange` in x/y
            let k = (inner.width / 2) / result.targetRange
            let dx = (xyz.x - result.targetCenter.x) * k, dy = (xyz.y - result.targetCenter.y) * k
            let p = CGPoint(x: c.x + max(min(dx, inner.width / 2), -inner.width / 2),
                            y: c.y - max(min(dy, inner.height / 2), -inner.height / 2))
            var arrow = Path()
            arrow.move(to: c); arrow.addLine(to: p)
            ctx.stroke(arrow, with: .color(.yellow), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(.orange))
        }
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(.separator))
    }
}

private struct CurrentMeasureTable: View {
    let result: ColorReading

    var body: some View {
        let x = result.xyz
        let rows: [(String, String)] = [
            ("Y cd/m²", fmt(x?.Y, 3)), ("Y ftL", fmt(x.map { $0.Y * 0.291864 }, 4)), ("T°", fmt(result.cct, 0)),
            ("X", fmt(x?.X, 2)), ("Y", fmt(x?.Y, 2)), ("Z", fmt(x?.Z, 2)),
            ("R", fmt(result.rgb?[0], 2)), ("G", fmt(result.rgb?[1], 2)), ("B", fmt(result.rgb?[2], 2)),
            ("x", fmt(x?.x, 4)), ("y", fmt(x?.y, 4)), ("z", fmt(x?.z, 4)),
            ("L", fmt(result.lab?[0], 2)), ("a", fmt(result.lab?[1], 2)), ("b", fmt(result.lab?[2], 2)),
            ("C", fmt(result.lch?[1], 2)), ("H", fmt(result.lch?[2], 2)),
        ]
        VStack(spacing: 0) {
            Text("Current Measure").font(.caption.bold()).frame(maxWidth: .infinity).padding(.bottom, 3)
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        GridRow {
                            Text(row.0).bold().frame(width: 56, height: 16)
                                .background(Color.gray.opacity(0.15))
                            Text(row.1).frame(maxWidth: .infinity, minHeight: 16, alignment: .trailing).padding(.trailing, 4)
                                .background((i / 3) % 2 == 0 ? Color.clear : Color.gray.opacity(0.08))
                        }
                        .overlay(Rectangle().stroke(.separator, lineWidth: 0.5))
                    }
                }
            .font(.system(.caption, design: .monospaced))
        }
    }
}

// MARK: - Chart

private struct BalancePoint: Identifiable {
    let level: Int
    let channel: Int
    let value: Double
    var id: Int { level * 10 + channel }
}

/// "Gray Scale Balance w/o gamma": balance RGB arriba (60–140%) y ΔE abajo (0–10), como HCFR.
private struct GrayScaleChart: View {
    @ObservedObject var session: Session

    var body: some View {
        let results = session.results.filter { $0.level > 0 }
        let balance = results.flatMap { r -> [BalancePoint] in
            guard let b = r.balance else { return [] }
            return (0..<3).map { BalancePoint(level: r.level, channel: $0, value: min(max(b[$0], 60), 140)) }
        }
        let de = results.compactMap { r in r.deltaE.map { (r.level, min($0, 10)) } }

        VStack(spacing: 0) {
            Text("Gray Scale Balance w/o gamma").font(.callout.bold()).foregroundStyle(.yellow)
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            Chart {
                RuleMark(y: .value("Ref", 100)).foregroundStyle(.white.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ForEach(balance) { p in
                    LineMark(x: .value("Level", p.level), y: .value("%", p.value), series: .value("Channel", p.channel))
                        .foregroundStyle(channelColors[p.channel])
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Level", p.level), y: .value("%", p.value))
                        .foregroundStyle(channelColors[p.channel])
                        .symbolSize(28)
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: 60...140)
            .chartYAxis { AxisMarks(position: .leading, values: Array(stride(from: 60, through: 140, by: 10))) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").foregroundStyle(.white) }
            } }
            .chartXAxis { levelAxis }
            .chartPlotStyle { $0.background(grayRamp) }
            .frame(maxHeight: .infinity)

            Chart {
                ForEach(de, id: \.0) { p in
                    LineMark(x: .value("Level", p.0), y: .value("dE", p.1)).foregroundStyle(.pink).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Level", p.0), y: .value("dE", p.1)).foregroundStyle(.pink).symbolSize(28)
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: 0...10)
            .chartYAxis { AxisMarks(position: .leading, values: [0, 2, 4, 6, 8, 10]) { v in
                AxisGridLine().foregroundStyle(.teal.opacity(0.4))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").foregroundStyle(.white) }
            } }
            .chartXAxis { levelAxis }
            .chartPlotStyle { $0.background(grayRamp) }
            .frame(height: 90)
        }
        .padding(6)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var levelAxis: some AxisContent {
        AxisMarks(values: Array(stride(from: 10, through: 100, by: 10))) { v in
            AxisGridLine().foregroundStyle(.teal.opacity(0.5))
            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)% White").font(.caption2.monospaced()).foregroundStyle(.white) }
        }
    }

    private var grayRamp: some View {
        LinearGradient(colors: [Color(white: 0.12), Color(white: 0.75)], startPoint: .leading, endPoint: .trailing)
    }
}
