// HCFR for macOS
// Copyright (C) 2026 Jorge Velázquez
// Preferences window added in 2026, after HCFR's preference pages (GeneralPropPage.cpp,
// ReferencesPropPage.cpp, AdvancedPropPage.cpp, Sensors/Argyllsensorproppage.cpp, SensorPropPage.cpp).
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI

/// Preferences (⌘,), with HCFR's pages.
struct PreferencesView: View {
    @ObservedObject var session: Session
    @AppStorage("prefsTab") private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            GeneralPage(session: session).tabItem { Label("General", systemImage: "gearshape") }.tag(0)
            ReferencesPage(session: session).tabItem { Label("References", systemImage: "scope") }.tag(1)
            AppearancePage(session: session).tabItem { Label("Appearance", systemImage: "paintpalette") }.tag(2)
            AdvancedPage(session: session).tabItem { Label("Advanced", systemImage: "gearshape.2") }.tag(3)
            SensorPage(session: session).tabItem { Label("Sensor", systemImage: "camera.metering.center.weighted") }.tag(4)
        }
        .frame(width: 680)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Reset to Defaults…") { session.resetPreferences() }
                    .help("All the preferences back to HCFR's default values (the measures are kept)")
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
        .disabled(session.activity != .idle)
    }
}

private func numberField(_ title: String, _ value: Binding<Double>, digits: Int = 2, width: CGFloat = 70) -> some View {
    HStack(spacing: 6) {
        Text(tr(title))
        TextField(title, value: value, format: .number.precision(.fractionLength(0...digits)))
            .labelsHidden()
            .frame(width: width)
            .multilineTextAlignment(.trailing)
    }
}

/// Preferences → References (HCFR's IDD_REFERENCE_PROP_PAGE).
struct ReferencesPage: View {
    @ObservedObject var session: Session
    /// Plain layout (development snapshots, which can't draw grouped forms).
    var plain = false

    var body: some View {
        Form {
            Section("Color Space") {
                Picker("Standard", selection: $session.standard) {
                    ForEach(ColorStandard.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("White", selection: $session.white) {
                    ForEach(WhitePoint.allCases) { Text($0.label).tag($0) }
                }
                let p = session.standard.primaries
                let custom = session.standard == .custom
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        Text("x").bold()
                        Text("y").bold()
                    }
                    xyRow("White", x: $session.prefs.customWhiteX, y: $session.prefs.customWhiteY,
                          shown: session.white.xy, editable: session.white == .custom)
                    xyRow("Red", x: $session.prefs.customRedX, y: $session.prefs.customRedY, shown: p[0], editable: custom)
                    xyRow("Green", x: $session.prefs.customGreenX, y: $session.prefs.customGreenY, shown: p[1], editable: custom)
                    xyRow("Blue", x: $session.prefs.customBlueX, y: $session.prefs.customBlueY, shown: p[2], editable: custom)
                }
                Text("Choose Custom in Standard or White to type your own chromaticities.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Gamma calculation (SDR)") {
                Picker("Target", selection: $session.prefs.gammaMode) {
                    ForEach([GammaMode.powerLaw, .blackCompensation, .cameraStandard, .cameraManual, .bt1886, .lStar]) { Text(tr($0.title)).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup)
                numberField("Camera gamma offset", $session.prefs.cameraOffset, digits: 3, width: 70)
                    .disabled(session.prefs.mode != .cameraManual)
                HStack(spacing: 18) {
                    numberField("Power Law Gamma", $session.gamma)
                    Toggle("Use avg measured gamma", isOn: $session.prefs.useMeasuredGamma)
                    Text("Target Gamma in use: \(String(format: "%.2f", session.ref.gammaInUse))").foregroundStyle(.secondary)
                }
                .disabled(!([GammaMode.powerLaw, .blackCompensation, .cameraStandard, .cameraManual].contains(session.prefs.mode)))
                HStack(spacing: 18) {
                    numberField("Effective @50% [0=Absolute]", $session.prefs.gammaRel)
                    numberField("% input offset", $session.prefs.split, digits: 0)
                }
                .disabled(session.prefs.mode != .bt1886)
                HStack(spacing: 18) {
                    Toggle("Override black", isOn: $session.overrideBlack)
                    numberField("cd/m²", $session.prefs.manualBlack, digits: 4, width: 80)
                        .disabled(!session.overrideBlack)
                }
                Text("Override black: 0% is not measured and black is taken as this luminance (0 = perfect black).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Color Checker Patterns") {
                Picker("Patterns", selection: Binding(get: { session.ccSet }, set: { session.setColorCheckerSet($0) })) {
                    ForEach(ColorCheckerSet.allCases) { s in
                        Text(s == .user && !session.userCCName.isEmpty ? tr("User defined") + " (\(session.userCCName))" : tr(s.title)).tag(s)
                    }
                }
                HStack {
                    Text("\(session.ccPatches.count) patches").foregroundStyle(.secondary)
                    Spacer()
                    Button("Load user file…") { session.loadUserColorChecker() }
                }
            }

            Section("EOTF (HDR)") {
                Picker("HDR", selection: $session.prefs.gammaMode) {
                    ForEach([GammaMode.hlg, .st2084]) { Text(tr($0.title)).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup)
                let hdr = session.prefs.mode.isHDR
                HStack(spacing: 18) {
                    numberField("HLG System Gamma", $session.prefs.hlgSystemGamma).disabled(session.prefs.mode != .hlg)
                    Toggle("Override Targets", isOn: $session.prefs.overrideTargets)
                    Toggle("BT.2390", isOn: $session.prefs.bt2390).disabled(session.prefs.mode != .st2084)
                }
                .disabled(!hdr)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        numberField("Diffuse White [nits]", $session.prefs.diffuseWhite, digits: 4, width: 80)
                        numberField("Target MinL", $session.prefs.targetMinL, digits: 3)
                        numberField("Target MaxL", $session.prefs.targetMaxL, digits: 1)
                    }
                    GridRow {
                        numberField("NB slope", $session.prefs.blackSlope)
                        numberField("NW", $session.prefs.whiteSlope)
                        numberField("NW start %", $session.prefs.whiteSlopeStart, digits: 0)
                    }
                    .disabled(!session.prefs.bt2390)
                    GridRow {
                        numberField("Master MinL", $session.prefs.masterMinL, digits: 3)
                        numberField("Master MaxL", $session.prefs.masterMaxL, digits: 0)
                        numberField("Content MaxL", $session.prefs.contentMaxL, digits: 0)
                    }
                    GridRow {
                        numberField("Frame Avg. MaxL", $session.prefs.frameAvgMaxL, digits: 0)
                    }
                }
                .disabled(!hdr)
                Text("The HDR curve sets the gray scale targets. Set your pattern generator (e.g. PGenerator) to HDR output yourself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .modifier(PrefsFormStyle(plain: plain))
    }

    private func xyRow(_ name: String, x: Binding<Double>, y: Binding<Double>, shown: (x: Double, y: Double), editable: Bool) -> some View {
        GridRow {
            Text(tr(name))
            if editable {
                TextField("x", value: x, format: .number.precision(.fractionLength(0...4))).labelsHidden().frame(width: 72)
                TextField("y", value: y, format: .number.precision(.fractionLength(0...4))).labelsHidden().frame(width: 72)
            } else {
                Text(String(format: "%.4f", shown.x)).font(.callout.monospaced()).foregroundStyle(.secondary)
                Text(String(format: "%.4f", shown.y)).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}

/// Preferences → Advanced (HCFR's IDD_ADVANCED_PROP_PAGE): Delta E options.
struct AdvancedPage: View {
    @ObservedObject var session: Session
    var plain = false

    var body: some View {
        Form {
            Section("Project file format") {
                Picker("Save projects as", selection: $session.appPrefs.projectFormat) {
                    ForEach(ProjectSaveFormat.allCases) { Text(tr($0.title)).tag($0) }
                }
                Text("HCFR (.chc), the default: the format of HCFR for Windows, so the project opens on both. The file also carries everything this app saves (display, meter, spectra, lux, user Color Checker…), so nothing is lost on the Mac. Older .hcfrex projects still open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Calibration files - Advanced use") {
                Toggle("Do not use white in matrix calculus (R1.x)", isOn: $session.appPrefs.matrixOnlyPrimaries)
                Text("Sensor matrix from a reference meter: with white (default) the four-color method; without, red, green and blue only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Luxmeter LX-1108") {
                Picker("Port", selection: $session.appPrefs.luxPort) {
                    Text("none").tag("")
                    ForEach(Luxmeter.ports(), id: \.self) { Text($0).tag($0) }
                    if !session.appPrefs.luxPort.isEmpty && !Luxmeter.ports().contains(session.appPrefs.luxPort) {
                        Text(session.appPrefs.luxPort + " (not connected)").tag(session.appPrefs.luxPort)
                    }
                }
                Toggle("Imperial units (Ft-cd)", isOn: $session.appPrefs.imperialUnits)
                Picker("Luminance curves", selection: $session.appPrefs.luxCurves) {
                    ForEach(LuxCurves.allCases) { Text(tr($0.title)).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Toggle("Compute contrast from luxmeter values", isOn: $session.appPrefs.preferLuxmeter)
                Text(session.luxStatus ?? "The luxmeter is read on its serial port (USB adapter: /dev/cu.usbserial…) during every reading; a Lux row is added to the tables.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Export HCFR sheets (CSV)") {
                ForEach([("GrayScaleSheet", "Gray scale"), ("PrimariesSheet", "Primaries and secondaries"),
                         ("CCSheet", "Color Checker"), ("SpectralSheet", "Spectra"), ("GeneralSheet", "General information")],
                        id: \.0) { item in
                    Toggle(tr(item.1) + "  (.\(item.0).csv)", isOn: Binding(
                        get: { session.appPrefs.exportSheets.contains(item.0) },
                        set: { on in
                            session.appPrefs.exportSheets.removeAll { $0 == item.0 }
                            if on { session.appPrefs.exportSheets.append(item.0) }
                        }))
                }
                Text("Files written by File → Export HCFR sheets (CSV)…, as HCFR for Windows' export. For PCG and other gamma tools only the gray scale is needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Measure launch") {
                Toggle("Confirmation message", isOn: $session.appPrefs.confirmMeasures)
                Text("Asks \"Run … measures?\" before every measurement run.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Delta E") {
                Toggle("Highlight", isOn: $session.appPrefs.highlight)
                Picker("dE formula", selection: $session.prefs.deltaEFormula) {
                    ForEach(DeltaEFormula.allCases) { Text(tr($0.title)).tag($0.rawValue) }
                }
                Picker("dE gray", selection: $session.prefs.grayDeltaE) {
                    ForEach(GrayDeltaEMode.allCases) { Text(tr($0.title)).tag($0.rawValue) }
                }
                Picker("dE weight", selection: $session.prefs.deltaEWeight) {
                    ForEach(DeltaEWeight.allCases) { Text(tr($0.title)).tag($0.rawValue) }
                }
                Text("Recommended: CIE76(uv) for the gray scale and CIE2000 for colors. dE gray sets the luminance of the gray reference: the measured one (w/o gamma, color error only), the target one (w/gamma) or none (relative).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .modifier(PrefsFormStyle(plain: plain))
    }
}

/// Preferences → General (HCFR's IDD_GENERAL_PROP_PAGE).
struct GeneralPage: View {
    @ObservedObject var session: Session
    @StateObject private var language = LanguageChoice()
    var plain = false

    var body: some View {
        Form {
            Section("Application") {
                Toggle("Check for updates", isOn: $session.appPrefs.checkUpdates)
                Text("When the app starts, looks for a newer version (Help → Updates → Check for new software).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("User measures") {
                Toggle("Continuous measuring", isOn: $session.appPrefs.continuousFreeMeasures)
                Toggle("Detect gray/primary colors during user measures", isOn: $session.appPrefs.detectPrimaries)
                Text("User measures are Measure → Free measure: with Continuous measuring they go on until Stop; with Detect, a reading close to a primary or secondary color is also stored in Primaries and secondaries.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dynamic iris") {
                HStack(spacing: 6) {
                    Text("Latency time")
                    TextField("Latency", value: Binding(get: { Int((session.settleSeconds * 1000).rounded()) },
                                                        set: { session.settleSeconds = Double(min(max($0, 0), 30000)) / 1000 }),
                              format: .number)
                        .labelsHidden().frame(width: 70).multilineTextAlignment(.trailing)
                    Text("ms")
                }
                Toggle("RealTime display of measures", isOn: $session.appPrefs.realTimeDisplay)
                Toggle("Bip at the beginning of measure (latency definition help)", isOn: $session.appPrefs.latencyBeep)
                Toggle("Frame insertion", isOn: $session.appPrefs.ablEnabled)
                HStack(spacing: 18) {
                    intField("Frequency", $session.appPrefs.ablFrequency, 1...100)
                    intField("Duration [ms]", $session.appPrefs.ablDuration, 100...10000)
                    intField("Level [%]", $session.appPrefs.ablLevel, 0...100)
                }
                .disabled(!session.appPrefs.ablEnabled)
                Text("Latency: wait after showing each pattern before reading (also in the Generator menu). Frame insertion shows a full-field gray frame every N patterns, so the ABL / dynamic dimming of the display does not drift during long runs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Raspberry Pi (PGenerator)") {
                HStack {
                    TextField("IP address (empty = automatic)", text: $session.piAddressDraft)
                        .frame(width: 200)
                        .onAppear { session.piAddressDraft = session.piAddress }
                    Button("Connect") { session.usePi(at: session.piAddressDraft) }
                        .disabled(session.activity != .idle)
                    if session.patternSource == .raspberryPi, let s = session.piStatus {
                        Text("Raspberry Pi connected: \(s)").font(.caption).foregroundStyle(.green)
                    }
                }
                Text("IP address of the Raspberry Pi running PGenerator (for example 192.168.1.50). Leave it empty to find the Pi automatically on the local network.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Language") {
                Picker("Interface language", selection: $language.value) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                Text("The language changes the next time the app starts.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Colors to add when measuring primaries and secondaries") {
                Picker("Colors to add", selection: $session.appPrefs.colorsToAdd) {
                    ForEach(ColorsToAdd.allCases) { Text(tr($0.title)).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            Section("Gray levels rounding assumption") {
                Toggle("Use round down levels (AVSHD, DVE)", isOn: $session.appPrefs.roundDown)
                Toggle("Use 10 bit targets (HDR10 Blu-ray)", isOn: $session.appPrefs.use10bit)
                    .disabled(session.appPrefs.roundDown)
                Text("How a % gray level becomes a video code: normal rounding (GCD disc, generators), round down (AVSHD, DVE) or 10-bit codes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .modifier(PrefsFormStyle(plain: plain))
    }

    private func intField(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Text(tr(title))
            TextField(title, value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number)
                .labelsHidden().frame(width: 60).multilineTextAlignment(.trailing)
        }
    }
}

/// Preferences → Sensor (HCFR's Argyll meter page and sensor matrix page).
struct SensorPage: View {
    @ObservedObject var session: Session
    var plain = false

    /// Argyll standard observers, as HCFR lists them, when no meter is connected.
    static let defaultObservers: [(Int, String)] = [
        (0, "Default"), (3, "CIE 1931 2 deg"), (4, "CIE 1964 10 deg"), (5, "CIE 2012 2 deg"), (6, "CIE 2012 10 deg"),
        (7, "Stiles&Burch 2 deg"), (8, "Judd&Vos 2 deg"), (9, "CIE 1964 10/2 deg comp"), (10, "Shaw&Fairchild 2 deg"),
        (11, "EBU 2012"),
    ]

    var body: some View {
        let caps = session.meter?.caps
        let known = caps != nil
        Form {
            Section("Meter") {
                Text(session.meter.map { "\($0.name)" + ($0.serial.isEmpty ? "" : " — S/N \($0.serial)") } ?? "No colorimeter connected: the options are applied when one connects.")
                    .foregroundStyle(.secondary)
                Picker("Reading Type", selection: $session.appPrefs.readingType) {
                    ForEach(ReadingType.allCases) { t in
                        Text(tr(t.title) + (known && !available(t, caps!) ? tr(" (not available)") : "")).tag(t)
                    }
                }
                if session.activeReadingType != .display && session.meter != nil {
                    Text("In use: \(session.activeReadingType.title)\(session.activeReadingType == .ambient ? " — values in lux" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Observer", selection: $session.appPrefs.observer) {
                    ForEach(observers, id: \.0) { Text($0.1).tag($0.0) }
                }
                .disabled(known && !caps!.observer)
                Picker("Integration time", selection: $session.appPrefs.integrationTime) {
                    ForEach(IntegrationTime.allCases) { Text(tr($0.title)).tag($0) }
                }
                .disabled(known && !caps!.integrationTime)
                Toggle("Hi-Res", isOn: $session.appPrefs.hiRes)
                    .disabled(known && !caps!.hiRes)
                Toggle("Low light averaging (slow on black)", isOn: $session.appPrefs.lowLightAveraging)
                    .help("HCFR's adaptive averaging: below 10 cd/m² 2 to 5 readings are averaged. Off as in HCFR for Windows: on black every extra reading can take many seconds.")
                Text("As HCFR: the observer applies to CCSS corrections and spectro meters; the integration time to i1 Display Pro / ColorMunki Display (with refresh display types it is rounded to whole refresh periods); Hi-Res to i1Pro / ColorMunki spectros.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Calibrate meter now") { session.calibrateMeterNow() }
                        .disabled(session.meter == nil || session.activity != .idle)
                    Spacer()
                }
            }
            Section("Second meter (simultaneous measures)") {
                HStack {
                    Picker("Meter", selection: $session.selectedPort2) {
                        Text("none").tag(MeterPort?.none)
                        ForEach(session.ports.filter { $0.name != session.connectedPortName }) { Text($0.displayName).tag(MeterPort?.some($0)) }
                    }
                    if session.meter2 == nil {
                        Button("Connect") { session.connectSecondMeter() }.disabled(session.selectedPort2 == nil)
                    } else {
                        Button("Disconnect") { session.disconnectSecondMeter() }
                    }
                }
                Toggle("Simultaneous measures", isOn: $session.simultaneous).disabled(session.meter2 == nil)
                Text(session.meter2.map { "Connected: \($0.name). Every reading is taken with both meters; the second one's values go to the compared data (rows dE / ref, xy / ref), and \"Compute from compared project\" then makes the sensor matrix (HCFR's \"Build using simultaneous measures\")." }
                     ?? "Connect a second meter (e.g. a spectro as reference) to measure with both at once, as HCFR's Simultaneous measures.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Spectral sample") {
                HStack {
                    Button("Build colorimeter calibration spectral sample…") { session.createSpectralSample() }
                        .disabled(session.spectra.isEmpty)
                    Spacer()
                }
                Text("With a spectrophotometer: measure white, red, green and blue, then save them as a CCSS file. Colorimeters then list it in Display, as HCFR's spectral samples.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sensor matrix") {
                Grid(horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(0..<3, id: \.self) { r in
                        GridRow {
                            Text(["X", "Y", "Z"][r]).bold()
                            ForEach(0..<3, id: \.self) { c in
                                TextField("", value: cell(r, c), format: .number.precision(.fractionLength(0...6)))
                                    .labelsHidden().frame(width: 100).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                HStack {
                    Text(session.appPrefs.hasSensorMatrix ? "Correction matrix in use" : "Identity: no correction")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Compute from compared project") { session.computeSensorMatrixFromReference() }
                        .disabled(session.refData == nil)
                        .help("Measure red, green, blue and white with this meter; open (File → Compare with Project…) a project where the same patches were measured with a reference meter (a spectro). The matrix makes this meter read like the reference.")
                    Button("Reference values by hand…") { session.editingManualReference = true }
                        .sheet(isPresented: $session.editingManualReference) {
                            ManualReferenceSheet(session: session, r: session.manualReference)
                        }
                        .help("HCFR's \"Build manually using reference colorimeter\": type the x, y, Y a reference meter read on red, green, blue and white")
                    Button("Reset") { session.appPrefs.sensorMatrix = [1, 0, 0, 0, 1, 0, 0, 0, 1] }
                }
                HStack {
                    Button("Load meter correction file…") { session.loadMeterCorrectionFile() }
                    Button("Save meter correction file…") { session.saveMeterCorrectionFile() }
                        .disabled(!session.appPrefs.hasSensorMatrix)
                    Spacer()
                }
                Text("Every reading (X, Y, Z) is multiplied by this matrix, as HCFR's sensor matrix. Leave the identity unless you have a correction matrix for your meter and display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .modifier(PrefsFormStyle(plain: plain))
    }

    private var observers: [(Int, String)] {
        guard let m = session.meter, !m.observers.isEmpty else { return Self.defaultObservers }
        return m.observers.contains { $0.0 == 0 } ? m.observers : [(0, "Default")] + m.observers
    }

    private func available(_ t: ReadingType, _ caps: MeterCaps) -> Bool {
        switch t {
        case .display: return true
        case .telephoto: return caps.telephoto
        case .ambient: return caps.ambient
        }
    }

    private func cell(_ r: Int, _ c: Int) -> Binding<Double> {
        Binding(get: { session.appPrefs.sensorMatrix[safe: r * 3 + c] ?? (r == c ? 1 : 0) },
                set: { v in
                    var m = session.appPrefs.sensorMatrix
                    if m.count != 9 { m = [1, 0, 0, 0, 1, 0, 0, 0, 1] }
                    m[r * 3 + c] = v
                    session.appPrefs.sensorMatrix = m
                })
    }
}

/// HCFR's Appearance page: on the Mac the windows follow the system appearance; the chart options apply.
struct AppearancePage: View {
    @ObservedObject var session: Session
    var plain = false

    var body: some View {
        Form {
            Section("Charts") {
                Toggle("Display charts with a white background", isOn: $session.appPrefs.whiteCharts)
                Toggle("Save chart files with a white background", isOn: $session.appPrefs.saveChartsWhite)
            }
            Section("Visual style") {
                Text("Windows and colors follow macOS (System Settings → Appearance: light, dark or automatic).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .modifier(PrefsFormStyle(plain: plain))
    }
}

private struct PrefsFormStyle: ViewModifier {
    let plain: Bool
    func body(content: Content) -> some View {
        if plain { content.formStyle(.columns).padding() } else { content.formStyle(.grouped) }
    }
}

/// Development use (Snapshot --prefs): one page without the tab view.
struct PreferencesSnapshot: View {
    @ObservedObject var session: Session
    let page: Int
    var body: some View {
        switch page {
        case 0: ReferencesPage(session: session, plain: true)
        case 1: AdvancedPage(session: session, plain: true)
        case 2: GeneralPage(session: session, plain: true)
        case 4: AppearancePage(session: session, plain: true)
        default: SensorPage(session: session, plain: true)
        }
    }
}


/// Sensor matrix → Reference values by hand: x, y, Y of red, green, blue and white read by a
/// reference meter on the same patches this meter measured.
struct ManualReferenceSheet: View {
    @ObservedObject var session: Session
    @ObservedObject var r: ManualReference
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reference meter values").font(.title3.bold())
            Text("Measure red, green, blue and white with this meter (Measure → Primary colors), then type what the reference meter read on the same patches. White is optional (Y = 0 to leave it out).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Grid(horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow { Text(""); Text("x").bold(); Text("y").bold(); Text("Y (cd/m²)").bold() }
                ForEach(0..<4, id: \.self) { i in
                    GridRow {
                        Text(tr(["Red", "Green", "Blue", "White"][i])).frame(width: 60, alignment: .leading)
                        ForEach(0..<3, id: \.self) { k in
                            TextField("", value: $r.values[i][k], format: .number.precision(.fractionLength(0...4)))
                                .labelsHidden().frame(width: 90).multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Compute matrix") { session.computeSensorMatrixFromManual(); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
