// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import Combine

/// Analysed result for one gray level (table column).
struct StepResult: Identifiable, ColorReading {
    let level: Double
    let xyz: XYZ?
    let targetY: Double?
    let balance: [Double]?
    let rgb: [Double]?
    let cct: Double?
    let gamma: Double?
    let deltaE: Double?
    let deltaxy: Double?
    let lab: [Double]?
    let lch: [Double]?
    let measureRGB: [Int]?
    let referenceRGB: [Int]
    let targetCenter: (x: Double, y: Double)
    var id: Double { level }
    var title: String { "\(Reference.label(level))% White" }
    var bars: [Double]? { balance }
    var targetRange: Double { 0.02 }

    /// `whiteY`: measured 100% white (for gamma). `baseY`: white for Y target, ΔE and Lab — the
    /// measured 100%, or 120 cd/m² until it is measured (as HCFR does in a new project), so ΔE is
    /// shown as values come in.
    init(level: Double, xyz: XYZ?, whiteY: Double?, baseY: Double, blackY: Double?, ref: CalReference) {
        self.level = level
        self.xyz = xyz
        targetCenter = (ref.white.x, ref.white.y)
        // Until 100% is measured only the 100% column shows its base target (120 cd/m²);
        // once it is measured every level gets its target from the real white.
        let target = ColorMath.targetY(level: level, whiteY: baseY, blackY: blackY, ref: ref)
        targetY = whiteY != nil || level == 100 ? target : nil
        let code = Int((Reference.grayProp(level) * 255).rounded())
        referenceRGB = [code, code, code]
        guard let xyz else {
            balance = nil; rgb = nil; cct = nil; gamma = nil; deltaE = nil
            deltaxy = nil; lab = nil; lch = nil; measureRGB = nil
            return
        }
        balance = ColorMath.rgbBalance(xyz, ref: ref)
        rgb = ColorMath.rgb(xyz, ref: ref)
        cct = ColorMath.cct(xyz)
        deltaxy = ColorMath.deltaxy(xyz, ref: ref)
        gamma = whiteY.flatMap { ColorMath.pointGamma(xyz, whiteY: $0, level: level) }
        deltaE = ColorMath.grayDeltaE(xyz, whiteY: baseY, targetY: target, ref: ref)
        let l = ColorMath.lab(xyz, whiteY: baseY, white: ref.white)
        lab = l
        lch = ColorMath.lch(l)
        measureRGB = ColorMath.displayRGB(xyz, whiteY: baseY, ref: ref)
    }
}

/// Modal message: confirmation (Yes/No) or pattern instruction (Continue/Cancel).
struct UserPrompt: Identifiable {
    enum Style { case yesNo, continueCancel, position }
    let id = UUID()
    let title: String
    let message: String
    let style: Style
    fileprivate let continuation: CheckedContinuation<Void, Error>
}

@MainActor
final class Session: ObservableObject {
    enum Activity { case idle, measuring, continuous }

    // Settings (remembered between launches)
    let defaults = UserDefaults.standard
    @Published var standard: ColorStandard { didSet { defaults.set(standard.rawValue, forKey: "standard") } }
    @Published var white: WhitePoint { didSet { defaults.set(white.rawValue, forKey: "white") } }
    @Published var gamma: Double {
        didSet {
            let clamped = min(max(gamma, 1.0), 4.0)
            if clamped != gamma { gamma = clamped; return }
            defaults.set(gamma, forKey: "gamma")
        }
    }
    /// References / Advanced preferences (gamma mode, BT.1886, HDR, custom colors, Delta E).
    @Published var prefs = ReferencePrefs() {
        didSet {
            prefs.applyCustomColors()
            applyStaticOptions()
            if let data = try? JSONEncoder().encode(prefs) { defaults.set(data, forKey: "referencePrefs") }
        }
    }
    /// General / Advanced / sensor options (HCFR's General, Advanced and Argyll meter pages).
    @Published var appPrefs = AppPrefs() {
        didSet {
            if let data = try? JSONEncoder().encode(appPrefs) { defaults.set(data, forKey: "appPrefs") }
            applyStaticOptions()
            let s = (oldValue.readingType, oldValue.observer, oldValue.integrationTime, oldValue.hiRes, oldValue.lowLightAveraging)
            if s != (appPrefs.readingType, appPrefs.observer, appPrefs.integrationTime, appPrefs.hiRes, appPrefs.lowLightAveraging) {
                reapplySensorOptions()
            }
            if oldValue.luxPort != appPrefs.luxPort { applyLuxPort() }
        }
    }
    /// Reading type the meter actually uses (it may not have the one chosen).
    @Published var activeReadingType: ReadingType = .display
    /// Patterns shown since the run started (frame insertion every N patterns).
    var patternCounter = 0
    /// Override black (0 cd/m²): 0 IRE is not measured and black is taken as perfect.
    @Published var overrideBlack: Bool {
        didSet {
            defaults.set(overrideBlack, forKey: "overrideBlack")
            if overrideBlack && selectedLevel == 0 { selectedLevel = 100 }
        }
    }
    @Published var selectedPort: MeterPort?
    /// Display of the colorimeter (built-in or CCSS correction), as in HCFR's sensor settings.
    @Published var correction: MeterCorrection?

    // State
    @Published var ports: [MeterPort] = []
    @Published var meter: ArgyllMeter?
    @Published var connecting = false
    @Published var scanning = false
    @Published var status = "Looking for colorimeters…"
    @Published var activity: Activity = .idle
    /// Gray scale measurements by level (% white).
    @Published var measurements: [Double: XYZ] = [:]
    /// Number of points of the gray scale (11 = 0, 10, … 100%), as HCFR's "Scale sizes" → Gray.
    @Published private(set) var grayCount = Reference.defaultGrayCount
    /// Gray scale size chosen while measurements exist: asks before clearing them.
    @Published var pendingGrayCount: Int?
    @Published var selectedLevel: Double = 100
    /// Primary / secondary color measurements (and the White measured with them).
    @Published var colorMeasurements: [PatchColor: XYZ] = [:]
    @Published var selectedPatch: PatchColor = .red
    /// Near black, near white, saturation and Color Checker measurements: by view, by column.
    @Published var seriesMeasurements: [MeasureView: [Int: XYZ]] = [:]
    /// Free measures, in the order they were taken.
    @Published var freeMeasurements: [XYZ] = []
    /// Contrast view: black, white and the two ANSI checkerboards.
    @Published var contrastMeasurements: [ContrastPatch: XYZ] = [:]
    /// Selected column of the series and contrast views.
    @Published var selectedIndex = 0
    /// HCFR's "Scale sizes": number of near black, near white and saturation points.
    @Published var nearBlackCount = 5
    @Published var nearWhiteCount = 5
    @Published var saturationCount = 5
    /// Color Checker pattern set, and the patches of the user's own file ("User defined").
    @Published var ccSet: ColorCheckerSet = .gcd
    @Published var userCCRows: [ColorCheckerData.Row] = []
    @Published var userCCName = ""
    /// Another project compared with this one (HCFR's data reference): "dE / ref" and "xy / ref" rows.
    @Published var refData: ReferenceData?
    /// Graph scales and display options.
    @Published var graphOptions = GraphOptions() {
        didSet { if let d = try? JSONEncoder().encode(graphOptions) { defaults.set(d, forKey: "graphOptions") } }
    }
    /// Values of the first table rows: xyY (default), XYZ, RGB or xyz.
    @Published var valueMode: ValueMode = .xyY { didSet { defaults.set(valueMode.rawValue, forKey: "valueMode") } }
    /// Table shown (HCFR's "View" selector).
    @Published var view: MeasureView = .grayScale {
        didSet { if selectedIndex >= columnCount(view) { selectedIndex = 0 } }
    }
    /// Graph of the Information panel (HCFR's graph views).
    @Published var infoGraph: InfoGraph = .rgbLevels { didSet { defaults.set(infoGraph.rawValue, forKey: "infoGraph") } }
    /// CIE diagram: show the illuminants and color temperatures (HCFR's "Show references").
    @Published var cieShowReferences = true { didSet { defaults.set(cieShowReferences, forKey: "cieShowReferences") } }
    /// CIE diagram: u'v' (CIE 1976 UCS) instead of xy (CIE 1931), as HCFR's "CIE u'v'" option.
    @Published var cieUV = false { didSet { defaults.set(cieUV, forKey: "cieUV") } }
    /// CIE diagram: show the gray scale points (HCFR's "Show gray scale").
    @Published var cieShowGrays = true { didSet { defaults.set(cieShowGrays, forKey: "cieShowGrays") } }

    // Pattern generator: the user's DVD / external generator (manual) or a display of this Mac
    @Published var patternSource: PatternSource = .manual { didSet { savePatternSource() } }
    @Published var videoLevels: VideoLevels = .full { didSet { defaults.set(videoLevels.rawValue, forKey: "videoLevels") } }
    /// Patch size on the generator display, % of the screen area (100 = full field).
    @Published var patternArea: Double = 100 { didSet { defaults.set(patternArea, forKey: "patternArea") } }
    /// Wait after showing a pattern before reading, so the display settles.
    @Published var settleSeconds: Double = 1.0 { didSet { defaults.set(settleSeconds, forKey: "settleSeconds") } }
    let patternWindow = PatternWindowController()
    /// Spectra (spectral meters) and luxmeter values of the measures, by column (EditTarget id).
    @Published var spectra: [String: Spectrum] = [:]
    @Published var luxValues: [String: Double] = [:]
    var lastSpectrum: Spectrum?
    var lastLux: Double?
    var lastSecondXYZ: XYZ?
    /// Luxmeter (HCFR's LX-1108 on a serial port).
    let luxmeter = Luxmeter()
    @Published var luxStatus: String?
    /// Second meter for simultaneous measures; its readings go to the compared data.
    @Published var meter2: ArgyllMeter?
    @Published var selectedPort2: MeterPort?
    /// Calibration wizard (Wizard.swift): shown over the main window, its choices and results.
    @Published var wizardShown = false
    let wizardModel = WizardModel()
    /// The wizard's measures don't ask "Run … measures?" (one run).
    var wizardSkipConfirm = false
    @Published var simultaneous = false
    /// Column whose values are being edited (grid's right-click → Edit values…).
    @Published var editingMeasure: EditTarget?
    /// Test pattern on the generator from the Patterns menu (nil = none).
    @Published var testPatternShown: String?
    /// Patterns → "Show color…" dialog (HCFR's Test colors window), with the color in %.
    @Published var editingTestColor = false
    @Published var testColorDraft: [Double] = [75, 75, 75]
    var shownPattern: TestPattern?
    /// Raspberry Pi (PGenerator) IP address; empty = find it on the network automatically.
    @Published private(set) var piAddress = ""
    /// Connected Raspberry Pi, shown in the Generator menu (e.g. "192.168.1.50 · 1920×1080").
    @Published private(set) var piStatus: String?
    /// Generator → "Raspberry Pi address…" dialog: shown, and the text being typed.
    /// (Kept here rather than in the view: @State is a macro in the macOS 27 SDK that needs Xcode.)
    @Published var editingPiAddress = false
    /// Generator → "Custom patch size…" dialog: shown, and the % being typed.
    @Published var editingPatchSize = false
    @Published var patchSizeDraft = ""
    @Published var piAddressDraft = ""
    var pi: PGeneratorClient?
    /// PGenerator's HDMI output wanted (Generator → PGenerator output…) and the one it has now.
    @Published var piOutput = PiOutput() {
        didSet { if let d = try? JSONEncoder().encode(piOutput) { defaults.set(d, forKey: "piOutput") } }
    }
    @Published var piCurrentOutput: PiOutput?
    /// Set the Pi to SDR or HDR10 automatically from the reference (Preferences → References).
    @Published var piAutoMode = true { didSet { defaults.set(piAutoMode, forKey: "piAutoMode") } }
    @Published var editingPiOutput = false
    /// Display → "Search display…" window and its text.
    @Published var searchingCorrection = false
    @Published var correctionSearch = ""
    @Published var piApplying = false
    /// madVR Envy / madTPG (MadVR.swift): its IP address, the connection and its description.
    @Published var madVRAddress = ""
    @Published var madVRStatus: String?
    @Published var editingMadVRAddress = false
    @Published var madVRAddressDraft = ""
    var madVR: MadVRClient?
    var madVRConnecting: Task<MadVRClient, Error>?
    private var piConnecting: Task<PGeneratorClient, Error>?
    private var promptPanel: PromptPanelController?
    @Published var lastMeasure: Date?
    @Published var prompt: UserPrompt?
    /// Prompt waiting for an answer (also while its sheet is being re-presented).
    private var pendingPrompt: UserPrompt?
    /// Prompt whose sheet is actually on screen (set by the sheet itself).
    private var promptOnScreen: UUID?
    /// When the last prompt was answered; a new sheet must wait for the old one to finish closing.
    private var promptClosedAt = Date.distantPast
    @Published var errorMessage: String?
    @Published var confirmNewProject = false
    /// Project file currently open/saved (nil = never saved).
    @Published var projectURL: URL?
    /// Measurements changed since the last save/open.
    @Published var isDirty = false

    private var task: Task<Void, Never>?
    private var scanTimer: Timer?
    /// Serial numbers already read, by port name (reading one means opening the meter).
    private var serials: [String: String] = [:]
    /// Port this app has open (it can't be opened again to read its serial).
    var connectedPortName: String?

    init() {
        standard = defaults.string(forKey: "standard").flatMap(ColorStandard.init(rawValue:)) ?? .sdtv
        white = defaults.string(forKey: "white").flatMap(WhitePoint.init(rawValue:)) ?? .d65
        gamma = defaults.object(forKey: "gamma") as? Double ?? 2.3
        let loadedPrefs = ReferencePrefs.decodeMerging(defaults.data(forKey: "referencePrefs"), over: ReferencePrefs())
        prefs = loadedPrefs
        loadedPrefs.applyCustomColors()
        appPrefs = AppPrefs.decodeMerging(defaults.data(forKey: "appPrefs"), over: AppPrefs())
        overrideBlack = defaults.object(forKey: "overrideBlack") as? Bool ?? true
        videoLevels = defaults.string(forKey: "videoLevels").flatMap(VideoLevels.init(rawValue:)) ?? .full
        patternArea = defaults.object(forKey: "patternArea") as? Double ?? 100
        settleSeconds = defaults.object(forKey: "settleSeconds") as? Double ?? 1.0
        piAddress = defaults.string(forKey: "piAddress") ?? ""
        madVRAddress = defaults.string(forKey: "madVRAddress") ?? ""
        if let d = defaults.data(forKey: "piOutput"), let o = try? JSONDecoder().decode(PiOutput.self, from: d) { piOutput = o }
        piAutoMode = defaults.object(forKey: "piAutoMode") as? Bool ?? true
        if let n = defaults.object(forKey: "grayCount") as? Int, n >= 3, n <= 101 { grayCount = n }
        if let n = defaults.object(forKey: "nearBlackCount") as? Int, n >= 2, n <= 101 { nearBlackCount = n }
        if let n = defaults.object(forKey: "nearWhiteCount") as? Int, n >= 2, n <= 101 { nearWhiteCount = n }
        if let n = defaults.object(forKey: "saturationCount") as? Int, n >= 2, n <= 101 { saturationCount = n }
        ccSet = (defaults.object(forKey: "ccSet") as? Int).flatMap(ColorCheckerSet.init(rawValue:)) ?? .gcd
        userCCName = defaults.string(forKey: "userCCName") ?? ""
        userCCRows = ColorCheckerSet.readCSV(defaults.string(forKey: "userCCData") ?? "")
        if ccSet == .user && userCCRows.isEmpty { ccSet = .gcd }
        infoGraph = defaults.string(forKey: "infoGraph").flatMap(InfoGraph.init(rawValue:)) ?? .rgbLevels
        cieShowReferences = defaults.object(forKey: "cieShowReferences") as? Bool ?? true
        cieUV = defaults.bool(forKey: "cieUV")
        cieShowGrays = defaults.object(forKey: "cieShowGrays") as? Bool ?? true
        graphOptions = GraphOptions.decodeMerging(defaults.data(forKey: "graphOptions"), over: GraphOptions())
        valueMode = defaults.string(forKey: "valueMode").flatMap(ValueMode.init(rawValue:)) ?? .xyY
        if defaults.bool(forKey: "patternWindow") {
            patternSource = .window
        } else if let id = defaults.object(forKey: "patternDisplay") as? UInt32,
                  NSScreen.screens.contains(where: { $0.displayID == id }) {
            patternSource = .display(id)
        } else if defaults.bool(forKey: "patternRaspberryPi") {
            patternSource = .raspberryPi
        } else if defaults.bool(forKey: "patternMadVR") {
            patternSource = .madVR
        }
        patternWindow.onEscape = { [weak self] in self?.stop() }
        applyStaticOptions()
        if !appPrefs.luxPort.isEmpty { applyLuxPort() }
        promptPanel = PromptPanelController(session: self)
    }

    /// Options kept in static settings read by the formulas and tables.
    func applyStaticOptions() {
        Reference.roundDown = appPrefs.roundDown
        Reference.use10bit = appPrefs.use10bit && !appPrefs.roundDown
        DeltaEStyle.highlight = appPrefs.highlight
        DeltaEStyle.cie76uv = prefs.deltaEFormula == DeltaEFormula.cie76uv.rawValue
        ChartInk.whiteDisplay = appPrefs.whiteCharts
    }

    /// "Measure launch: Confirmation message" (Advanced preferences).
    func confirmRun(_ message: String) async throws {
        if wizardSkipConfirm { wizardSkipConfirm = false; return }
        guard appPrefs.confirmMeasures else { return }
        try await ask("On measure", message, style: .yesNo)
    }

    /// Sends the sensor options to the meter (before its Display correction, as HCFR).
    func applySensorOptions(_ m: ArgyllMeter, correction c: MeterCorrection?) async {
        do {
            let ms = Int(appPrefs.integrationTime.seconds * 1000)
            let actual = try await m.applyOptions(readingType: appPrefs.readingType.rawValue, observer: appPrefs.observer,
                                                  integrationMs: ms, refresh: c?.refresh ?? false, hiRes: appPrefs.hiRes,
                                                  averaging: appPrefs.lowLightAveraging)
            activeReadingType = ReadingType(rawValue: actual) ?? .display
            if actual != appPrefs.readingType.rawValue {
                errorMessage = "Reading mode \(appPrefs.readingType.title) is not available on this meter, using \(activeReadingType.title)."
            } else if activeReadingType == .ambient {
                status = "Ambient mode set: values are reported in lux"
            }
        } catch {
            status = "Sensor options not applied: \(error.localizedDescription) (rebuild with build-app.sh to update the meter helper)"
        }
    }

    /// Sensor options changed in Preferences: applied now to the connected meter.
    func reapplySensorOptions() {
        guard let m = meter, activity == .idle, !connecting else { return }
        let c = correction
        Task {
            await applySensorOptions(m, correction: c)
            if let c { try? await m.setCorrection(c) }
        }
    }

    /// Sensor → "Calibrate meter now": the meter's own calibration (dark / white reference / refresh).
    func calibrateMeterNow() {
        guard let m = meter else { return }
        run(.measuring) {
            do {
                try await m.calibrate()
            } catch MeterError.needsCalibration(let cond, let msg) {
                try await self.calibrate(meter: m, condition: cond, message: msg)
            }
            self.closePattern()
            self.status = "Meter calibrated. If the meter needs it, put it back in measurement position."
        }
    }

    var ref: CalReference {
        CalReference(standard: standard, white: white, gamma: gamma, gammaMode: prefs.mode, gammaRel: prefs.gammaRel,
                     split: prefs.split, measuredGamma: prefs.useMeasuredGamma ? measuredAverageGamma : nil, hdr: prefs.hdr,
                     deltaEFormula: DeltaEFormula(rawValue: prefs.deltaEFormula) ?? .cie2000,
                     grayDeltaE: GrayDeltaEMode(rawValue: prefs.grayDeltaE) ?? .absoluteYWithoutGamma,
                     deltaEWeight: DeltaEWeight(rawValue: prefs.deltaEWeight) ?? .standard)
    }

    /// Average point gamma of the measurements, 10–80% (HCFR's GammaAvg), for "Use avg measured gamma".
    var measuredAverageGamma: Double? {
        guard let w = whiteY else { return nil }
        let g = measurements.filter { $0.key >= 10 && $0.key <= 80 }.compactMap { ColorMath.pointGamma($0.value, whiteY: w, level: $0.key) }
        return g.isEmpty ? nil : g.reduce(0, +) / Double(g.count)
    }

    /// "Power law 2.30", "BT.1886", "ST2084 (BT.2390)"… for the info lines.
    var gammaDescription: String {
        let r = ref
        if r.standard.usesSRGBCurve && !r.gammaMode.isHDR { return "sRGB" }
        switch r.gammaMode {
        case .powerLaw: return String(format: "Power law w/gamma = %.2f", r.gammaInUse)
        case .blackCompensation: return String(format: "Power law w/gamma = %.2f (black compensation)", r.gammaInUse)
        case .bt1886: return r.gammaRel == 0 ? "BT.1886" : String(format: "BT.1886 (effective %.2f @50%%)", r.gammaRel)
        case .lStar: return "L*"
        case .hlg: return String(format: "HLG (system gamma %.2f)", r.hdr.hlgSystemGamma)
        case .st2084: return "ST2084" + (r.hdr.bt2390 ? " (BT.2390)" : "")
        }
    }

    /// Target luminance of a gray level relative to white (1 = white), with the current curve.
    func targetRelative(level: Double) -> Double {
        // Without measurements HCFR uses its default on/off white, Target MaxL (120 cd/m²)
        let w = whiteY ?? prefs.targetMaxL
        return ref.targetY(signal: Reference.grayProp(level), whiteY: w, blackY: targetBlackY) / w
    }

    /// Black luminance for the targets: measured 0%, or the manual black with Override black.
    var targetBlackY: Double? { overrideBlack ? prefs.manualBlack : measurements[0]?.Y }

    /// All levels of the gray scale, 0 to 100%.
    var allLevels: [Double] { Reference.levels(count: grayCount) }

    /// Levels to measure: 0 IRE only when Override black is off.
    var levels: [Double] { overrideBlack ? allLevels.filter { $0 > 0 } : allLevels }

    /// Changes the number of gray scale points; gray measurements of another size are cleared
    /// (as in HCFR), so with measurements the user is asked first (`pendingGrayCount`).
    func setGrayCount(_ count: Int, confirmed: Bool = false) {
        guard count != grayCount, activity == .idle else { return }
        if !measurements.isEmpty && !confirmed {
            pendingGrayCount = count
            return
        }
        pendingGrayCount = nil
        if !measurements.isEmpty {
            measurements.removeAll()
            isDirty = true
        }
        applyGrayCount(count)
        status = "Gray scale: \(count) points (every \(Reference.label(100 / Double(count - 1)))%)"
    }

    /// Sets the size without touching measurements (opening a project, launch).
    func applyGrayCount(_ count: Int) {
        grayCount = min(max(count, 3), 101)
        defaults.set(grayCount, forKey: "grayCount")
        if !allLevels.contains(selectedLevel) { selectedLevel = 100 }
    }

    /// Black, used for contrast: measured 0%, or the manual black with Override black (none if 0).
    var blackY: Double? { overrideBlack ? (prefs.manualBlack > 0 ? prefs.manualBlack : nil) : measurements[0]?.Y }

    var contrast: Double? {
        let w = grayBaseY
        guard let b = blackY else { return overrideBlack ? .infinity : nil }
        return b > 0 ? w / b : .infinity
    }

    var busy: Bool { activity != .idle || connecting }

    /// Measured 100% white.
    var whiteY: Double? { measurements[100]?.Y }

    /// White for Y target and ΔE: the measured 100%, or the 120 cd/m² base until it is measured.
    var grayBaseY: Double { whiteY ?? baseWhiteY }

    /// White for the color patches: the White of the color run, else the gray scale 100%, else 120.
    var colorWhiteY: Double { colorMeasurements[.white]?.Y ?? whiteY ?? baseWhiteY }

    /// Measurement of a patch; White falls back to the gray scale 100% if no color run measured it.
    func patchXYZ(_ patch: PatchColor) -> XYZ? {
        colorMeasurements[patch] ?? (patch == .white ? measurements[100] : nil)
    }

    var patchResults: [PatchResult] {
        PatchColor.allCases.map { PatchResult(patch: $0, xyz: patchXYZ($0), whiteY: colorWhiteY, ref: ref) }
    }

    var selectedPatchResult: PatchResult {
        PatchResult(patch: selectedPatch, xyz: patchXYZ(selectedPatch), whiteY: colorWhiteY, ref: ref)
    }

    /// Area of the measured R-G-B triangle in CIE xy, as a fraction of the reference triangle.
    var gamutCoverage: Double? {
        func area(_ p: [(Double, Double)]) -> Double {
            abs((p[0].0 * (p[1].1 - p[2].1) + p[1].0 * (p[2].1 - p[0].1) + p[2].0 * (p[0].1 - p[1].1)) / 2)
        }
        let m = [PatchColor.red, .green, .blue].compactMap { colorMeasurements[$0] }.filter { $0.Y > 0 }
        guard m.count == 3 else { return nil }
        let refArea = area(standard.primaries.map { ($0.x, $0.y) })
        return refArea > 0 ? area(m.map { ($0.x, $0.y) }) / refArea : nil
    }

    /// Average / max ΔE of the measured primaries and secondaries (White excluded).
    var colorDeltaEs: [Double] { patchResults.filter { $0.patch != .white }.compactMap(\.deltaE) }

    /// The reading shown in "Selected color" for the current view.
    var selectedReading: ColorReading {
        switch view {
        case .grayScale: return selectedResult
        case .primariesSecondaries: return selectedPatchResult
        case .contrast:
            let r = contrastResults
            return r[min(selectedIndex, r.count - 1)]
        default:
            let r = seriesResults(view)
            if r.isEmpty { return selectedResult }
            return r[min(selectedIndex, r.count - 1)]
        }
    }

    var hasMeasurements: Bool {
        !measurements.isEmpty || !colorMeasurements.isEmpty || seriesMeasurements.values.contains { !$0.isEmpty }
            || !freeMeasurements.isEmpty || !contrastMeasurements.isEmpty
    }

    var results: [StepResult] {
        allLevels.map { result(for: $0) }
    }

    var selectedResult: StepResult { result(for: selectedLevel) }

    private func result(for level: Double) -> StepResult {
        let xyz = level == 0 && overrideBlack ? nil : measurements[level]
        return StepResult(level: level, xyz: xyz, whiteY: whiteY, baseY: grayBaseY, blackY: targetBlackY, ref: ref)
    }

    /// Average gamma as HCFR (ComputeGammaAndOffset): levels 10% to 80%.
    var averageGamma: Double? {
        let g = results.filter { $0.level >= 10 && $0.level <= 80 }.compactMap(\.gamma)
        return g.isEmpty ? nil : g.reduce(0, +) / Double(g.count)
    }

    var deltaEs: [Double] { results.compactMap(\.deltaE) }
    var averageDeltaE: Double? { deltaEs.isEmpty ? nil : deltaEs.reduce(0, +) / Double(deltaEs.count) }
    var maxDeltaE: Double? { deltaEs.max() }

    // MARK: - Colorimeter

    /// Looks for colorimeters now and keeps checking every few seconds while none is connected,
    /// so a meter plugged in after launch is picked up.
    func startScanning() {
        searchForMeters()
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.meter == nil, !self.busy, !self.scanning, self.prompt == nil else { return }
                self.searchForMeters(quiet: true)
            }
        }
    }

    func searchForMeters(quiet: Bool = false) {
        guard !scanning else { return }
        scanning = true
        Task {
            defer { scanning = false }
            do {
                let found = try await ArgyllMeter.listPorts(knownSerials: serials,
                                                            skipIdentify: Set([connectedPortName].compactMap { $0 }))
                for p in found { if let sn = p.serial, !sn.isEmpty { serials[p.name] = sn } }
                let changed = found != ports.filter { !$0.isSimulated }
                ports = found + [MeterPort.simulated]
                if let sel = selectedPort {
                    selectedPort = ports.first { $0 == sel }   // keep selection, with its serial
                }
                if found.isEmpty {
                    if meter == nil { status = "No colorimeter found. Plug one in — it will be detected automatically." }
                } else if found.count == 1 {
                    if selectedPort == nil { selectedPort = found[0] }
                    if meter == nil { connect() }
                } else if meter == nil && (changed || !quiet) {
                    status = "\(found.count) colorimeters found — choose one in Sensor and press Connect."
                    if selectedPort == nil { selectedPort = found.first }
                } else if !quiet {
                    status = "\(found.count) colorimeters found."
                }
            } catch {
                if !quiet { errorMessage = error.localizedDescription }
            }
        }
    }

    /// High resolution (3.3 nm) of spectrometers: the same setting as Preferences → Sensor → Hi-Res
    /// (applied to the meter when it changes).
    var highRes: Bool { appPrefs.hiRes }

    func setHighRes(_ on: Bool) {
        guard activity == .idle else { return }
        appPrefs.hiRes = on
        status = on ? "High resolution (3.3 nm) on — the meter may ask for a new calibration"
                    : "Standard resolution (10 nm)"
    }

    /// The user picked a colorimeter in the list: use it right away (choosing it without pressing
    /// Connect used to keep measuring with the previous meter).
    func choosePort(_ port: MeterPort?) {
        guard let port, port != selectedPort || meter == nil else { return }
        selectedPort = port
        if activity == .idle && !connecting { connect() }
    }

    func connect() {
        guard let port = selectedPort else {
            errorMessage = "Choose a colorimeter first."
            return
        }
        guard activity == .idle, !connecting else { return }
        let old = meter
        meter = nil
        connectedPortName = nil
        correction = nil
        connecting = true
        status = "Connecting to \(port.displayName)…"
        Task {
            defer { connecting = false }
            // Reconnecting: let the previous helper release the meter before opening it again
            await old?.closeAndWait()
            do {
                let m = try await ArgyllMeter.open(port: port)
                connectedPortName = port.name
                if !m.serial.isEmpty {
                    serials[port.name] = m.serial
                    if let i = ports.firstIndex(of: port) { ports[i].serial = m.serial }
                    selectedPort?.serial = m.serial
                }
                // Last Display used, or HCFR's CRT correction the first time
                let saved = defaults.string(forKey: "display")
                let pick = m.corrections.first { $0.name == saved }
                    ?? m.corrections.first { $0.isCCSS && $0.name.hasPrefix("CRT") }
                    ?? m.corrections.first
                await applySensorOptions(m, correction: pick)
                if let pick { try await m.setCorrection(pick) }
                meter = m
                correction = pick
                status = "Check the meter position…"
                // Like HCFR for Windows: don't go on while the meter is in the wrong position
                // (only on tested meter models; see ArgyllMeter.testedSerialPrefixes)
                do {
                    if m.checksDiffuser { try await ensurePosition(m) }
                } catch {
                    m.close()
                    meter = nil
                    connectedPortName = nil
                    correction = nil
                    status = "Not connected — the meter was left in the wrong position"
                    return
                }
                status = "Ready — Display: \(pick?.name ?? "default")"
                    + (m.checksDiffuser ? "" : " · diffuser position not checked (meter model not tested yet)")
            } catch {
                status = "Colorimeter not connected"
                errorMessage = error.localizedDescription
            }
        }
    }

    func setCorrection(_ c: MeterCorrection) {
        guard let meter, activity == .idle, c != correction else { return }
        Task {
            do {
                if c.refresh != correction?.refresh { await applySensorOptions(meter, correction: c) }
                try await meter.setCorrection(c)
                correction = c
                defaults.set(c.name, forKey: "display")
                status = "Display: \(c.name)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Actions

    func newProject() {
        stop()
        measurements.removeAll()
        colorMeasurements.removeAll()
        seriesMeasurements.removeAll()
        freeMeasurements.removeAll()
        contrastMeasurements.removeAll()
        spectra.removeAll()
        luxValues.removeAll()
        lastMeasure = nil
        selectedLevel = 100
        selectedPatch = .red
        selectedIndex = 0
        projectURL = nil
        isDirty = false
        status = meter == nil ? "Colorimeter not connected" : "New project — ready to measure"
    }

    /// Measure button: runs the chosen test.
    func measure(_ kind: MeasureKind = .grayScale) {
        if !kind.seriesViews.isEmpty { measureSeries(kind); return }
        if kind == .contrast { measureContrast(); return }
        if kind == .freeMeasure { measureFree(); return }
        if kind == .fullTiltBoogie { measureFullTiltBoogie(); return }
        let graySteps = kind == .grayScale || kind == .grayScaleAndColors ? levels.count : 0
        // General → "Colors to add when measuring primaries and secondaries": none, white, or
        // white and black (black only when not overridden, and not again after a gray scale)
        var patches = kind.patches
        if appPrefs.colorsToAdd == .none && kind != .grayScaleAndColors { patches.removeAll { $0 == .white } }
        let addBlack = appPrefs.colorsToAdd == .whiteAndBlack && !patches.isEmpty && graySteps == 0 && !overrideBlack
        let total = graySteps + patches.count + (addBlack ? 1 : 0)
        var what: [String] = []
        if graySteps > 0 { what.append("\(Reference.label(levels.first!)) to 100 IRE") }
        if !patches.isEmpty { what.append(patches.map(\.rawValue).joined(separator: ", ") + (addBlack ? ", Black" : "")) }

        view = patches.isEmpty || graySteps > 0 ? .grayScale : .primariesSecondaries
        run(.measuring) {
            try await self.confirmRun("""
                Run \(kind.title.lowercased()) measures on \(total) values (\(what.joined(separator: "; ")))?
                Warning: current data will be lost.

                Note: you can cancel measuring using the ESC key.
                """)
            self.isDirty = true
            if graySteps > 0 {
                self.measurements.removeAll()
                try await self.measureGrayLevels()
            }
            if !patches.isEmpty {
                self.colorMeasurements.removeAll()
                self.view = .primariesSecondaries
                try await self.measurePatches(patches)
                if addBlack {
                    try await self.present(.gray(0))
                    self.status = "Measuring Black…"
                    self.store(try await self.readWithCalibration(pattern: .gray(0)), level: 0)
                }
            }
            self.status = "\(kind.title) measurement finished"
            Chime.finished()
        }
    }

    /// Grey scale: 10%–100% (0% too without Override black), asking for each pattern.
    func measureGrayLevels() async throws {
        for level in levels {
            try Task.checkCancellation()
            if appPrefs.realTimeDisplay { selectedLevel = level }
            try await present(.gray(level))
            status = "Measuring \(Reference.label(level)) IRE…"
            store(try await readWithCalibration(pattern: .gray(level)), level: level)
        }
        selectedLevel = 100
    }

    /// Colors at 100% in HCFR's order (MeasurePrimaries / MeasureSecondaries / MeasureGrayScaleAndColors).
    func measurePatches(_ patches: [PatchColor]) async throws {
        for patch in patches {
            try Task.checkCancellation()
            if appPrefs.realTimeDisplay { selectedPatch = patch }
            try await present(.color(patch))
            status = "Measuring \(patch.rawValue)…"
            colorMeasurements[patch] = try await readWithCalibration(pattern: .color(patch))
            attach(.patch(patch))
            lastMeasure = Date()
        }
        selectedPatch = .red
    }

    /// Start: continuous reading of the selected column (gray level or color). Clicking another
    /// column switches what is being measured without stopping.
    func start() {
        if view == .grayScale && !levels.contains(selectedLevel) { selectedLevel = 100 }
        run(.continuous) {
            while !Task.isCancelled {
                if self.view != .grayScale && self.view != .primariesSecondaries {
                    try await self.continuousStep()
                } else if self.view == .grayScale {
                    let level = self.selectedLevel
                    self.status = "Continuous reading at \(Reference.label(level)) IRE — click another column to measure it, Stop to finish"
                    try await self.showIfGenerator(.gray(level))
                    let xyz = try await self.readWithCalibration(pattern: .gray(level))
                    // If the column changed during the reading, it belongs to the previous pattern: drop it.
                    if self.view == .grayScale && level == self.selectedLevel { self.store(xyz, level: level) }
                } else {
                    let patch = self.selectedPatch
                    self.status = "Continuous reading of \(patch.rawValue) — click another column to measure it, Stop to finish"
                    try await self.showIfGenerator(.color(patch))
                    let xyz = try await self.readWithCalibration(pattern: .color(patch))
                    if self.view == .primariesSecondaries && patch == self.selectedPatch {
                        self.colorMeasurements[patch] = xyz
                        self.attach(.patch(patch))
                        self.lastMeasure = Date()
                        self.isDirty = true
                    }
                }
            }
        }
    }

    func select(patch: PatchColor) {
        guard activity != .measuring else { return }
        selectedPatch = patch
    }

    func select(level: Double) {
        guard levels.contains(level), activity != .measuring else { return }
        selectedLevel = level
    }

    func stop() {
        testPatternShown = nil
        task?.cancel()
        closePattern()
        // A reading in progress can't be interrupted; if it hasn't finished 5 s after Stop/Cancel/ESC
        // (e.g. the driver hung), restart the meter so the app never stays blocked.
        if let running = task, let m = meter {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if self.task == running, self.meter === m { m.abort(reason: "Measurement cancelled") }
            }
        }
        if let p = pendingPrompt ?? prompt {
            prompt = nil
            pendingPrompt = nil
            promptClosedAt = Date()
            p.continuation.resume(throwing: CancellationError())
        }
    }

    func answerPrompt(proceed: Bool) {
        guard let p = pendingPrompt ?? prompt else { return }
        prompt = nil
        pendingPrompt = nil
        promptClosedAt = Date()
        if proceed { p.continuation.resume() } else { p.continuation.resume(throwing: CancellationError()) }
    }

    // MARK: - Measuring

    private func store(_ xyz: XYZ, level: Double) {
        measurements[level] = xyz
        attach(.gray(level))
        lastMeasure = Date()
        isDirty = true
    }

    func run(_ kind: Activity, _ body: @escaping @MainActor () async throws -> Void) {
        guard meter != nil else {
            errorMessage = "Connect a colorimeter first. This program needs a colorimeter to measure."
            return
        }
        guard task == nil else { return }
        activity = kind
        patternCounter = 0
        testPatternShown = nil
        task = Task {
            defer { closePattern() }
            do {
                try await body()
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                if cancelled {
                    status = "Measurement stopped"
                } else {
                    errorMessage = error.localizedDescription
                    status = "Measurement error"
                }
                // The meter helper died, or was stopped because it hung: reconnect automatically
                if let m = meter, !m.isAlive {
                    meter = nil
                    connectedPortName = nil
                    activity = .idle
                    task = nil
                    if !cancelled {
                        errorMessage = error.localizedDescription
                            + "\n\nThe colorimeter is being reconnected. Your measurements are kept; measure again the step that failed."
                    }
                    connect()
                    return
                }
            }
            activity = .idle
            task = nil
        }
    }

    /// Manual generator: asks the user for the pattern. Built-in generator: shows it on the chosen
    /// display and waits for it to settle.
    func present(_ pattern: TestPattern) async throws {
        if !automaticGenerator {
            Chime.request()
            try await ask("Information", "Use \(pattern.manualName) and press Continue.", style: .continueCancel)
        } else {
            try await showIfGenerator(pattern, force: true)
        }
    }

    /// Shows the pattern on the generator display (if one is selected) and waits `settleSeconds`
    /// when it changed.
    func showIfGenerator(_ pattern: TestPattern, force: Bool = false) async throws {
        if patternSource == .madVR {
            guard force || pattern != shownPattern else { return }
            try Task.checkCancellation()
            // madTPG has no ANSI checkerboard: full field of the bright part
            let ansi = pattern.ansiInverted != nil
            let rgb = ansi ? [1.0, 1, 1] : pattern.rgb
            let area = ansi ? 100 : patternArea
            try await madVRSend { try await $0.show(rgb: rgb, background: 0, areaPercent: area) }
            shownPattern = pattern
            try await latencyWait()
            return
        }
        if patternSource == .raspberryPi {
            guard force || pattern != shownPattern else { return }
            try Task.checkCancellation()
            if shownPattern == nil { try await ensurePiMode() }
            try await insertFrameIfDue()
            if let inverted = pattern.ansiInverted {
                try await piSend { $0.ansiMessage(inverted: inverted) }
            } else {
                try await piShow(levels: pattern.rgb)
            }
            shownPattern = pattern
            try await latencyWait()
            return
        }
        guard patternScreen != nil || patternSource == .window else { return }
        let screen = patternScreen
        if force || pattern != shownPattern || !patternWindow.isShowing {
            try await insertFrameIfDue(screen: screen)
            let black = videoLevels.code(0)
            let ansi = pattern.ansiInverted
            let rgb = (ansi != nil ? [1.0, 1, 1] : pattern.rgb).map { videoLevels.code($0) }
            let area = ansi != nil ? 100 : patternArea
            if let screen {
                patternWindow.show(rgb: rgb, background: [black, black, black], areaPercent: area, ansiInverted: ansi, on: screen)
            } else {
                let opening = !patternWindow.isShowing
                patternWindow.showWindowed(rgb: rgb, background: [black, black, black], areaPercent: area, ansiInverted: ansi)
                // A newly opened measurement window must first be placed under the meter
                if opening {
                    Chime.request()
                    try await ask("Measurement window",
                                  "Move the measurement window to the screen you are measuring (and resize it if you want), "
                                  + "place the meter on it, then press Continue to start measuring.",
                                  style: .continueCancel)
                }
            }
            shownPattern = pattern
            try await latencyWait()
        }
    }

    /// Latency time (General → Dynamic iris), with HCFR's optional beep when the reading starts.
    private func latencyWait() async throws {
        try await Task.sleep(for: .seconds(settleSeconds))
        if appPrefs.latencyBeep { NSSound.beep() }
    }

    /// HCFR's "Frame insertion": every `ablFrequency` patterns a full-field gray frame of `ablLevel` %
    /// is shown for `ablDuration` ms, so the display's ABL / dynamic dimming does not drift.
    private func insertFrameIfDue(screen: NSScreen? = nil) async throws {
        patternCounter += 1
        let p = appPrefs
        guard p.ablEnabled, p.ablFrequency > 0, patternCounter % p.ablFrequency == 0 else { return }
        let code = videoLevels.code(Double(p.ablLevel) / 100)
        if patternSource == .raspberryPi {
            try await piSend { $0.rectangleMessage(rgb: [code, code, code], background: [code, code, code], areaPercent: 100) }
        } else if let screen {
            patternWindow.show(rgb: [code, code, code], background: [code, code, code], areaPercent: 100, on: screen)
        }
        try await Task.sleep(for: .milliseconds(p.ablDuration))
    }

    func closePattern() {
        patternWindow.close()
        // Raspberry Pi: back to black, as HCFR for Windows does at the end of a run
        if shownPattern != nil, patternSource == .raspberryPi, let pi {
            Task { try? await pi.send(PGeneratorClient.idleMessage) }
        }
        shownPattern = nil
    }

    /// True when the app shows the patterns itself (a display of this Mac or the Raspberry Pi),
    /// false for the manual DVD / external generator.
    var automaticGenerator: Bool { patternScreen != nil || patternSource == .window || patternSource == .raspberryPi || patternSource == .madVR }

    // MARK: - Raspberry Pi (PGenerator)

    /// Sends a patch to the Raspberry Pi; if the connection was lost (Pi restarted…), reconnects once.
    private func piShow(levels: [Double]) async throws {
        let area = patternArea
        if (piCurrentOutput ?? piOutput).bitDepth == 10 {
            // 10-bit codes (video 64–940 or full 0–1023); PGenerator takes 10-bit backgrounds only in RGB
            func code10(_ v: Double) -> Int {
                videoLevels == .video ? Int((64 + v * 876).rounded()) : Int((v * 1023).rounded())
            }
            let rgb = levels.map(code10)
            let rgbFormat = (piCurrentOutput ?? piOutput).colorFormat == 0
            let bg = rgbFormat ? code10(0) : videoLevels.code(0)
            try await piSend { $0.rectangleMessage10(rgb: rgb, background: [bg, bg, bg], areaPercent: area) }
        } else {
            let black = videoLevels.code(0)
            let rgb = levels.map { videoLevels.code($0) }
            try await piSend { $0.rectangleMessage(rgb: rgb, background: [black, black, black], areaPercent: area) }
        }
    }

    /// Sends a message built for the connected Pi; reconnects once if the connection was lost.
    func piSend(_ message: (PGeneratorClient) -> String) async throws {
        do {
            let c = try await piClient()
            try await c.send(message(c))
        } catch PGeneratorError.communication {
            dropPi()
            let c = try await piClient()
            try await c.send(message(c))
        }
    }

    /// The connected Raspberry Pi, connecting first if needed (only one connection attempt at a time).
    func piClient() async throws -> PGeneratorClient {
        if let pi { return pi }
        if let piConnecting { return try await piConnecting.value }
        let address = piAddress
        let t = Task { @MainActor () throws -> PGeneratorClient in
            var host = address
            if host.isEmpty {
                self.status = "Looking for the Raspberry Pi (PGenerator) on the network…"
                var found: String?
                // As HCFR for Windows: several discovery attempts
                for _ in 0..<5 where found == nil { found = await PGeneratorClient.discover(timeout: 1) }
                guard let ip = found else { throw PGeneratorError.notFound }
                host = ip
            }
            self.status = "Connecting to the Raspberry Pi at \(host)…"
            let c = PGeneratorClient(host: host)
            try await c.connect()
            try? await c.send(PGeneratorClient.textMessage(
                "HCFR Colorimeter for macOS connected - PGenerator at \(host) Res [\(c.width)x\(c.height)]"))
            return c
        }
        piConnecting = t
        defer { piConnecting = nil }
        do {
            let c = try await t.value
            pi = c
            piStatus = "\(c.host) · \(c.width)×\(c.height)"
            if let a = try? await c.get(PiOutput.readCommand), let o = PiOutput.parse(a) {
                piCurrentOutput = o
                piStatus = "\(c.host) · \(c.width)×\(c.height) · \(o.summary)"
            }
            status = "Raspberry Pi connected at \(c.host) (\(c.width)×\(c.height))"
            return c
        } catch {
            piStatus = nil
            status = "Raspberry Pi not connected"
            throw error
        }
    }

    /// Connects now (when the Raspberry Pi is chosen as generator), so problems show up before measuring.
    func connectPi() {
        Task {
            do { _ = try await piClient() } catch { errorMessage = error.localizedDescription }
        }
    }

    /// Closes the connection, leaving the Pi on black.
    func dropPi(goodbye: Bool = false) {
        guard let c = pi else { return }
        pi = nil
        piStatus = nil
        if goodbye { Task { try? await c.send(PGeneratorClient.idleMessage); c.close() } } else { c.close() }
    }

    /// Generator → Raspberry Pi address: an IPv4 address, or empty to find the Pi automatically.
    func setPiAddress(_ text: String) {
        let a = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a.isEmpty || PGeneratorClient.isValidIPv4(a) else {
            errorMessage = PGeneratorError.badAddress(a).localizedDescription
            return
        }
        guard a != piAddress else { return }
        piAddress = a
        defaults.set(a, forKey: "piAddress")
        dropPi(goodbye: true)
        if patternSource == .raspberryPi { connectPi() }
    }

    /// Generator → Custom patch size: any share of the screen area from 1 to 100%.
    func setPatchSize(_ text: String) {
        let t = text.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let v = Double(t), v >= 1, v <= 100 else {
            errorMessage = tr("The patch size must be a number from 1 to 100 (% of the screen area).")
            return
        }
        patternArea = (v * 10).rounded() / 10
    }

    /// Preferences → PGenerator: uses the Pi at this address (or found automatically) as the
    /// pattern generator and connects now.
    func usePi(at text: String) {
        let a = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a.isEmpty || PGeneratorClient.isValidIPv4(a) else {
            errorMessage = PGeneratorError.badAddress(a).localizedDescription
            return
        }
        if a != piAddress {
            piAddress = a
            defaults.set(a, forKey: "piAddress")
            dropPi(goodbye: true)
        }
        patternSource = .raspberryPi
        if pi == nil { connectPi() }
    }

    /// Display used as pattern generator, nil for the manual (DVD) generator or if it was disconnected.

    var patternScreen: NSScreen? {
        guard case .display(let id) = patternSource else { return nil }
        return NSScreen.screens.first { $0.displayID == id }
    }

    /// Displays that can be used as generator: all screens, the one with the app window last.
    var generatorScreens: [NSScreen] {
        let appScreen = NSApp.mainWindow?.screen ?? NSApp.windows.first(where: { $0.isVisible })?.screen
        return NSScreen.screens.sorted { a, _ in a != appScreen }
    }

    func screenName(_ screen: NSScreen) -> String {
        let n = (NSScreen.screens.firstIndex(of: screen) ?? 0) + 1
        let appScreen = NSApp.mainWindow?.screen
        return "Display \(n): \(screen.localizedName)" + (screen == appScreen ? " (this window)" : "")
    }

    private func savePatternSource() {
        if case .display(let id) = patternSource { defaults.set(id, forKey: "patternDisplay") }
        else { defaults.removeObject(forKey: "patternDisplay") }
        defaults.set(patternSource == .raspberryPi, forKey: "patternRaspberryPi")
        defaults.set(patternSource == .window, forKey: "patternWindow")
        defaults.set(patternSource == .madVR, forKey: "patternMadVR")
        if patternSource != .window { patternWindow.close() }
        if patternSource == .manual { closePattern() }
        if patternSource == .raspberryPi {
            patternWindow.close()
            shownPattern = nil
            connectPi()
        } else {
            dropPi(goodbye: true)
        }
        if patternSource == .madVR {
            shownPattern = nil
            connectMadVR()
        } else {
            dropMadVR()
        }
    }

    /// Reads the meter, calibrating it first if it asks; `pattern` (nil for free measures) is shown
    /// again after the calibration.
    func readWithCalibration(pattern: TestPattern?) async throws -> XYZ {
        guard let meter else { throw MeterError.failed("Colorimeter not connected") }
        while true {
            try Task.checkCancellation()
            do {
                // Luxmeter and second meter read during the same pattern (HCFR's simultaneous measures)
                let started = Date()
                let second = simultaneous ? meter2 : nil
                async let other: XYZ? = Self.readIfPresent(second)
                if meter.isSimulated { try await meter.setStimulus((pattern ?? shownPattern)?.rgb ?? [1, 1, 1]) }
                let xyz = appPrefs.correct(try await meter.read())
                lastSecondXYZ = await other
                lastSpectrum = meter.lastSpectrum
                lastLux = luxmeter.value(since: started)
                return xyz
            } catch MeterError.needsCalibration(let cond, let msg) {
                try await calibrate(meter: meter, condition: cond, message: msg)
                if let pattern { try await present(pattern) } else { closePattern() }
            } catch MeterError.incorrectPosition(let msg) {
                try await ask("Incorrect Position", msg, style: .position)
            }
        }
    }

    private static func readIfPresent(_ m: ArgyllMeter?) async -> XYZ? {
        guard let m else { return nil }
        return try? await m.read()
    }

    /// Repeats the "Incorrect Position" message until the meter is in display measurement position.
    private func ensurePosition(_ meter: ArgyllMeter) async throws {
        while true {
            do {
                try await meter.checkPosition()
                return
            } catch MeterError.incorrectPosition(let msg) {
                try await ask("Incorrect Position", msg, style: .position)
            }
        }
    }

    private func calibrate(meter: ArgyllMeter, condition: UInt32, message: String) async throws {
        var cond = condition, msg = message
        while true {
            // 0x100 = 100% white patch, 0x200 = 80% patch (CRT refresh rate); the built-in
            // generator shows them, with the manual generator the user is asked for them
            var text = msg
            let auto = automaticGenerator
            if cond & 0xFF00 == 0x100 {
                if auto { try await showIfGenerator(.gray(100)) } else { text = "Use 100 IRE.\n\n" + msg }
            }
            if cond & 0xFF00 == 0x200 {
                if auto { try await showIfGenerator(.gray(80)) }
                else { text = "Use 80 IRE (the colorimeter measures the CRT refresh rate).\n\n" + msg }
            }
            try await ask("Colorimeter calibration", text, style: .continueCancel)
            do {
                try await meter.calibrate()
                // As HCFR: after a calibration that needed the meter somewhere else (e.g. an i1Pro
                // on its white tile, or a cap on the sensor), ask to put it back on the screen.
                let needsPlacement = cond & 0xFF00 != 0x100 && cond & 0xFF00 != 0x200
                if needsPlacement {
                    try await ask("Calibration complete",
                                  "The device is now calibrated. If the device requires it, return it to the measurement position on the screen and press Continue.",
                                  style: .continueCancel)
                }
                return
            } catch MeterError.needsCalibration(let c, let m) {
                cond = c; msg = m
            }
        }
    }

    func ask(_ title: String, _ message: String, style: UserPrompt.Style) async throws {
        // A pattern covering the app's screen would hide the message
        if patternSource != .window, patternWindow.isShowing, let main = NSApp.mainWindow?.screen,
           patternWindow.screen == main {
            closePattern()
        }
        // SwiftUI drops a sheet presented while the previous one is still closing (e.g. "Use 100%
        // Red" right after answering "Run … measures?"), which left the app waiting for an
        // invisible message. Wait for the closing animation first…
        let sinceClosed = Date().timeIntervalSince(promptClosedAt)
        if sinceClosed < 0.6 { try await Task.sleep(for: .seconds(0.6 - sinceClosed)) }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let p = UserPrompt(title: title, message: message, style: style, continuation: c)
            pendingPrompt = p
            prompt = p
            // …and if it still did not appear, present it again.
            Task { @MainActor in
                for _ in 0..<5 {
                    try? await Task.sleep(for: .seconds(1))
                    guard self.pendingPrompt?.id == p.id, self.promptOnScreen != p.id else { return }
                    self.prompt = nil
                    try? await Task.sleep(for: .seconds(0.6))
                    guard self.pendingPrompt?.id == p.id, self.promptOnScreen != p.id else { return }
                    self.prompt = p
                }
            }
        }
    }

    /// Called by the prompt sheet when it is on screen.
    func promptDidAppear(_ id: UUID) { promptOnScreen = id }
}

/// Soft sounds: one when the app asks for a pattern, one when a measurement run finishes.
@MainActor
enum Chime {
    private static let requestSound = sound("Tink", volume: 0.35)
    private static let finishedSound = sound("Glass", volume: 0.3)

    private static func sound(_ name: String, volume: Float) -> NSSound? {
        let s = NSSound(named: NSSound.Name(name))
        s?.volume = volume
        return s
    }

    static func request() { requestSound?.stop(); requestSound?.play() }
    static func finished() { finishedSound?.stop(); finishedSound?.play() }
}
