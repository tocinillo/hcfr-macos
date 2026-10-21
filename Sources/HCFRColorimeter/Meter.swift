// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import Foundation

enum MeterError: LocalizedError {
    /// The meter asks the user to do something (cover sensor, show white...). `condition` is Argyll's inst_cal_cond.
    case needsCalibration(condition: UInt32, message: String)
    /// The meter is not in display measurement position (e.g. i1d3 diffuser covering the sensor).
    case incorrectPosition(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .needsCalibration(_, let msg): return msg
        case .incorrectPosition(let msg): return msg
        case .failed(let msg): return msg
        }
    }
}

/// Port found by the Argyll drivers.
struct MeterPort: Identifiable, Hashable {
    let index: Int
    let name: String
    /// Serial number (read from the meter), to tell identical models apart.
    var serial: String? = nil
    var id: String { name }
    /// System serial ports (Bluetooth, debug console) are almost never meters.
    var isLikelySerialNoise: Bool { name.hasPrefix("/dev/cu.") }

    /// "X-Rite i1 DisplayPro, ColorMunki Display" from "hid36: (X-Rite i1 DisplayPro, ColorMunki Display)".
    var model: String {
        guard let open = name.firstIndex(of: "("), let close = name.lastIndex(of: ")"), open < close else { return name }
        return String(name[name.index(after: open)..<close])
    }

    var displayName: String {
        guard let serial, !serial.isEmpty else { return name }
        return "\(model) — S/N \(serial)"
    }

    static func == (a: MeterPort, b: MeterPort) -> Bool { a.name == b.name }

    /// HCFR's "Simulated sensor": a model display in the meter helper, for training and demos.
    static let simulated = MeterPort(index: 1000, name: "Simulated sensor")
    var isSimulated: Bool { index == 1000 }
    func hash(into h: inout Hasher) { h.combine(name) }
}

/// Display type of the colorimeter (built-in calibration or HCFR CCSS spectral file), as in HCFR for Windows.
struct MeterCorrection: Identifiable, Hashable {
    let index: Int
    let name: String
    let isCCSS: Bool
    /// Refresh display type (CRT, plasma…): the integration time is a whole number of refresh periods.
    var refresh = false
    var id: Int { index }
}

/// What the open meter can do (HCFR's Argyll meter page enables its options from this).
struct MeterCaps: Equatable {
    var telephoto = false
    var ambient = false
    var hiRes = false
    var observer = false
    var integrationTime = false
}

/// `hcfr-meter` helper process (HCFR's ArgyllCMS drivers) with a line protocol.
final class MeterHelper: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var lines: [String] = []
    private var waiter: CheckedContinuation<String, Error>?
    private var dead = false
    private var killReason: String?
    private(set) var diagnostics: [String] = []

    static var executableURL: URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let exe = Bundle.main.executableURL {
            candidates.append(exe.deletingLastPathComponent().appendingPathComponent("hcfr-meter"))
            // Running with `swift run`: .build/<config>/HCFRColorimeter -> .build/meter/hcfr-meter
            candidates.append(exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("meter/hcfr-meter"))
        }
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    /// Folder containing `ArgyllCMS/*.ccss` (HCFR's Install/color files). Argyll searches XDG_DATA_DIRS.
    static var correctionsDataDir: String? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL { candidates.append(res) }
        if let exe = Bundle.main.executableURL {
            // Development: <repo>/.build/<config>/HCFRColorimeter -> <repo>/Resources
            candidates.append(exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources"))
        }
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("ArgyllCMS").path) }?.path
    }

    init() throws {
        guard let url = Self.executableURL else {
            throw MeterError.failed("The hcfr-meter helper was not found. Build it with build-meter.sh.")
        }
        process.executableURL = url
        var env = ProcessInfo.processInfo.environment
        // HCFR's CCSS files, and the spectral samples made with this app (Application Support)
        let userDir = Session.userCorrectionsDir.deletingLastPathComponent().path
        env["XDG_DATA_DIRS"] = [Self.correctionsDataDir, userDir, env["XDG_DATA_DIRS"]].compactMap { $0 }.joined(separator: ":")
        process.environment = env
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { self?.markDead() } else { self?.append(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let self, let s = String(data: h.availableData, encoding: .utf8), !s.isEmpty else { return }
            lock.lock()
            diagnostics.append(contentsOf: s.split(separator: "\n").map(String.init))
            if diagnostics.count > 200 { diagnostics.removeFirst(diagnostics.count - 200) }
            lock.unlock()
        }
        process.terminationHandler = { [weak self] _ in self?.markDead() }
        try process.run()
    }

    private func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let line = String(data: lineData, encoding: .utf8), line.hasPrefix("@") {
                lines.append(String(line.dropFirst()))
            }
        }
        let resume = deliverLocked()
        lock.unlock()
        resume?()
    }

    private func markDead() {
        lock.lock()
        dead = true
        let w = waiter
        waiter = nil
        let lastDiag = diagnostics.suffix(3).joined(separator: " ")
        let reason = killReason
        lock.unlock()
        w?.resume(throwing: MeterError.failed(reason ?? "The meter process stopped (is the colorimeter unplugged?). \(lastDiag)"))
    }

    /// Must be called with the lock held; returns the resumption to run outside the lock.
    private func deliverLocked() -> (() -> Void)? {
        guard let w = waiter, !lines.isEmpty else { return nil }
        waiter = nil
        let line = lines.removeFirst()
        return { w.resume(returning: line) }
    }

    func nextLine() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if !lines.isEmpty {
                let line = lines.removeFirst()
                lock.unlock()
                cont.resume(returning: line)
            } else if dead {
                lock.unlock()
                cont.resume(throwing: MeterError.failed("The meter process is not running."))
            } else {
                waiter = cont
                lock.unlock()
            }
        }
    }

    func send(_ command: String) {
        try? input.fileHandleForWriting.write(contentsOf: (command + "\n").data(using: .utf8)!)
    }

    func stop() {
        if process.isRunning {
            send("quit")
            process.terminate()
        }
    }

    /// Asks the helper to quit and waits (up to 3 s) so the driver closes the USB device cleanly;
    /// opening the same meter again while the old process still holds it fails on the i1 Display Pro
    /// ("Communication protocol breakdown").
    func stopAndWait() async {
        guard process.isRunning else { return }
        send("quit")
        for _ in 0..<30 where process.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if process.isRunning { process.terminate() }
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    var isRunning: Bool { process.isRunning && !dead }

    /// Stops a stuck helper; the pending command fails with `reason`.
    func kill(reason: String) {
        lock.lock()
        killReason = reason
        lock.unlock()
        if process.isRunning { process.terminate() }
    }

    deinit { stop() }
}

final class ArgyllMeter {
    private let helper: MeterHelper
    let name: String
    let serial: String
    /// The diffuser position is checked (like HCFR) only on meter models tested with this app.
    let checksDiffuser: Bool
    /// Spectrometer with a high resolution mode (3.3 nm instead of 10 nm): i1Pro, i1Pro2, i1Pro3, ColorMunki.
    let supportsHighRes: Bool
    /// Corrections the meter offers (built-in + HCFR CCSS files).
    let corrections: [MeterCorrection]
    let caps: MeterCaps
    /// Standard observers (Argyll number, description) for CCSS corrections and spectral meters.
    let observers: [(Int, String)]

    /// Serial-number prefixes of the meters this app was tested with (i1d3 driver family):
    /// "C1-" Calibrite ColorChecker Display, "CM-" X-Rite ColorMunki Display.
    /// On other models the diffuser-position check is turned off, because one user's meter
    /// reported the diffuser in place when it was not, which blocked every reading.
    static let testedSerialPrefixes = ["C1-", "CM-"]

    static func isTested(serial: String) -> Bool {
        testedSerialPrefixes.contains { serial.uppercased().hasPrefix($0) }
    }

    private init(helper: MeterHelper, name: String, serial: String, checksDiffuser: Bool, supportsHighRes: Bool,
                 corrections: [MeterCorrection], caps: MeterCaps, observers: [(Int, String)]) {
        self.caps = caps
        self.observers = observers
        self.supportsHighRes = supportsHighRes
        self.helper = helper
        self.name = name
        self.serial = serial
        self.checksDiffuser = checksDiffuser
        self.corrections = corrections
    }

    /// Lists the meters. When several are connected, each one not in `skipIdentify` (e.g. the one
    /// this app has open) is opened briefly to read its serial number.
    static func listPorts(identifyIfSeveral: Bool = true, knownSerials: [String: String] = [:],
                          skipIdentify: Set<String> = []) async throws -> [MeterPort] {
        let helper = try MeterHelper()
        defer { helper.stop() }
        _ = try await helper.nextLine() // READY
        helper.send("list")
        var ports: [MeterPort] = []
        while true {
            let line = try await helper.nextLine()
            if line.hasPrefix("PORT ") {
                let parts = line.dropFirst(5).split(separator: " ", maxSplits: 1)
                if parts.count == 2, let n = Int(parts[0]) { ports.append(MeterPort(index: n, name: String(parts[1]))) }
            } else if line.hasPrefix("ERR ") {
                throw MeterError.failed(String(line.dropFirst(4)))
            } else if line == "OK" {
                break
            }
        }
        ports.removeAll { $0.isLikelySerialNoise }
        for i in ports.indices {
            ports[i].serial = knownSerials[ports[i].name]
            guard identifyIfSeveral, ports.count > 1, ports[i].serial == nil,
                  !skipIdentify.contains(ports[i].name) else { continue }
            helper.send("ident \(ports[i].index)")
            let reply = try await helper.nextLine()
            if reply.hasPrefix("IDENT ") {
                let f = reply.split(separator: " ", maxSplits: 2)
                if f.count == 3 { ports[i].serial = String(f[2]) }
            }
        }
        return ports
    }

    /// Opens the meter like HCFR for Windows: no forced mode; the Display (correction) is applied afterwards.
    static func open(port: MeterPort) async throws -> ArgyllMeter {
        do {
            return try await openOnce(port: port)
        } catch MeterError.failed(let msg) where msg.hasPrefix("Communication failed") {
            // The device may still be held by a helper that is closing: try again once
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return try await openOnce(port: port)
        }
    }

    private static func openOnce(port: MeterPort) async throws -> ArgyllMeter {
        let helper = try MeterHelper()
        _ = try await helper.nextLine() // READY
        helper.send("open \(port.index) default")
        let line = try await helper.nextLine()
        guard line.hasPrefix("OPENED ") else {
            helper.stop()
            throw MeterError.failed(line.hasPrefix("ERR ") ? String(line.dropFirst(4)) : line)
        }
        let info = line.dropFirst(7).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let serial = info.count > 3 ? info[3] : ""

        // Before listing the Display types: with a wrong diffuser reading the driver lists none
        let checksDiffuser = isTested(serial: serial)
        if !checksDiffuser {
            helper.send("diffcheck 0")
            _ = try await helper.nextLine()
        }

        helper.send("types")
        var corrections: [MeterCorrection] = []
        while true {
            let l = try await helper.nextLine()
            if l.hasPrefix("TYPE ") {
                let f = l.dropFirst(5).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                if f.count >= 4, let i = Int(f[0]) {
                    corrections.append(MeterCorrection(index: i, name: f[1], isCCSS: f[3] == "ccss",
                                                       refresh: f.count > 4 && f[4] == "refresh=1"))
                }
            } else { break } // OK or ERR
        }

        // Sensor options (reading type, observer, integration time, hi-res)
        var caps = MeterCaps()
        helper.send("caps")
        let c = try await helper.nextLine()
        if c.hasPrefix("CAPS ") {
            let kv = Dictionary(c.dropFirst(5).split(separator: " ").compactMap { p -> (String, Bool)? in
                let f = p.split(separator: "=")
                return f.count == 2 ? (String(f[0]), f[1] == "1") : nil
            }, uniquingKeysWith: { a, _ in a })
            caps = MeterCaps(telephoto: kv["tele"] ?? false, ambient: kv["ambient"] ?? false, hiRes: kv["hires"] ?? false,
                             observer: kv["observer"] ?? false, integrationTime: kv["itime"] ?? false)
        }
        var observers: [(Int, String)] = []
        helper.send("observers")
        while true {
            let l = try await helper.nextLine()
            guard l.hasPrefix("OBS ") else { break }
            let f = l.dropFirst(4).split(separator: "\t", maxSplits: 1).map(String.init)
            if f.count == 2, let i = Int(f[0]) { observers.append((i, f[1])) }
        }
        return ArgyllMeter(helper: helper, name: info.first ?? port.name, serial: serial,
                           checksDiffuser: checksDiffuser, supportsHighRes: info.count > 4 && info[4] == "1",
                           corrections: corrections, caps: caps, observers: observers)
    }

    private func parseStatus(_ line: String) throws {
        if line.hasPrefix("CAL ") {
            let parts = line.dropFirst(4).split(separator: " ", maxSplits: 1)
            let cond = UInt32(parts.first.map(String.init) ?? "0", radix: 16) ?? 0
            throw MeterError.needsCalibration(condition: cond, message: parts.count > 1 ? String(parts[1]) : "Calibration required")
        }
        if line.hasPrefix("POS wrong") {
            throw MeterError.incorrectPosition(String(line.dropFirst(10)))
        }
        if line.hasPrefix("ERR ") { throw MeterError.failed(String(line.dropFirst(4))) }
    }

    /// Throws `incorrectPosition` if the meter can't measure a display right now (diffuser on).
    func checkPosition() async throws {
        helper.send("pos")
        try parseStatus(try await helper.nextLine())
    }

    /// 3.3 nm (true) or standard 10 nm (false) spectral resolution.
    func setHighRes(_ on: Bool) async throws {
        helper.send("highres \(on ? 1 : 0)")
        try parseStatus(try await helper.nextLine())
    }

    func setCorrection(_ c: MeterCorrection) async throws {
        helper.send("settype \(c.index)")
        try parseStatus(try await helper.nextLine())
    }

    /// A reading never takes this long (even dark patches with adaptive averaging); if it does, the
    /// driver is stuck, so the helper is stopped to unblock the app instead of waiting forever.
    static let readTimeout: TimeInterval = 180

    /// True while the helper process is alive.
    var isAlive: Bool { helper.isRunning }

    /// Spectrum of the last reading (spectral meters only).
    private(set) var lastSpectrum: Spectrum?

    var isSimulated: Bool { name == "Simulated sensor" }

    /// Simulated sensor: the signal (0…1 per channel) of the pattern on screen, which the next
    /// reading returns through the model display.
    func setStimulus(_ rgb: [Double]) async throws {
        helper.send(String(format: "stim %.6f %.6f %.6f", rgb[0], rgb[1], rgb[2]))
        _ = try await helper.nextLine()
    }

    func read() async throws -> XYZ {
        helper.send("read")
        let watchdog = DispatchWorkItem { [helper] in helper.kill(reason: "The colorimeter stopped responding (no reading in \(Int(Self.readTimeout / 60)) minutes).") }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.readTimeout, execute: watchdog)
        defer { watchdog.cancel() }
        lastSpectrum = nil
        var line = try await helper.nextLine()
        if line.hasPrefix("SPEC ") {
            let f = line.dropFirst(5).split(separator: " ").compactMap { Double($0) }
            if f.count > 3, f.count == 3 + Int(f[2]) {
                lastSpectrum = Spectrum(start: f[0], end: f[1], values: Array(f[3...]))
            }
            line = try await helper.nextLine()
        }
        try parseStatus(line)
        let v = line.split(separator: " ").dropFirst().compactMap { Double($0) }
        guard line.hasPrefix("XYZ "), v.count == 3 else { throw MeterError.failed("Unexpected reply: \(line)") }
        return XYZ(X: v[0], Y: v[1], Z: v[2])
    }

    /// Applies HCFR's sensor options; returns the reading type actually set (the meter may not have it).
    func applyOptions(readingType: Int, observer: Int, integrationMs: Int, refresh: Bool, hiRes: Bool,
                      averaging: Bool) async throws -> Int {
        helper.send("rtype \(readingType)")
        let r = try await helper.nextLine()
        try parseStatus(r)
        let actual = r.hasPrefix("RTYPE ") ? Int(r.dropFirst(6)) ?? readingType : readingType
        helper.send("obs \(observer)")
        try parseStatus(try await helper.nextLine())
        helper.send("itime \(integrationMs) \(refresh ? 1 : 0)")
        try parseStatus(try await helper.nextLine())
        helper.send("hires \(hiRes ? 1 : 0)")
        try parseStatus(try await helper.nextLine())
        // An older helper answers "Unknown command": averaging then stays as it was
        helper.send("adapt \(averaging ? 1 : 0)")
        _ = try await helper.nextLine()
        return actual
    }

    func calibrate() async throws {
        helper.send("cal")
        try parseStatus(try await helper.nextLine())
    }

    func close() { helper.stop() }

    /// Closes the meter and waits until the device is free to be opened again.
    func closeAndWait() async { await helper.stopAndWait() }

    /// Stops the helper even in the middle of a reading (the pending command fails with `reason`).
    func abort(reason: String) { helper.kill(reason: reason) }
}
