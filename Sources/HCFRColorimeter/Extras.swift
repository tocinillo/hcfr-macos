// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Spectra, spectral samples (CCSS), luxmeter and simultaneous measures added in 2026 after HCFR for
// Windows (Views/SpectrumView, SpectralSampleDlg.cpp, ColorHCFR.cpp LuxMeterThreadFunc /
// SetLuxmeterValue, simultaneous measures), Copyright (c) Association Homecinema Francophone and
// HCFR contributors, GNU GPL.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import UniformTypeIdentifiers

/// Spectrum of a reading (spectral meters): evenly spaced bands from `start` to `end` nm.
struct Spectrum: Codable, Equatable {
    var start: Double
    var end: Double
    var values: [Double]

    var step: Double { values.count > 1 ? (end - start) / Double(values.count - 1) : 1 }
    func wavelength(_ i: Int) -> Double { start + Double(i) * step }
}

// MARK: - Luxmeter (HCFR: LX-1108 on a serial port, 9600 8N1)

final class Luxmeter: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var thread: Thread?
    private var running = false
    private var readings: [(Date, Double)] = []
    private(set) var port = ""

    /// Serial ports (USB serial adapters show up as /dev/cu.usbserial…).
    static func ports() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return items.filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && !$0.contains("debug-console") }
            .sorted().map { "/dev/" + $0 }
    }

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// Opens the port and reads the luxmeter's packets in the background.
    func start(_ path: String) -> String? {
        stop()
        guard !path.isEmpty else { return nil }
        let f = open(path, O_RDONLY | O_NOCTTY | O_NONBLOCK)
        guard f >= 0 else { return "Could not open \(path): \(String(cString: strerror(errno)))" }
        var t = termios()
        tcgetattr(f, &t)
        cfmakeraw(&t)
        cfsetispeed(&t, speed_t(B9600))
        cfsetospeed(&t, speed_t(B9600))
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CSIZE)
        t.c_cflag |= tcflag_t(CS8)
        tcsetattr(f, TCSANOW, &t)
        _ = fcntl(f, F_SETFL, 0) // blocking reads from now on
        lock.lock()
        fd = f
        running = true
        port = path
        readings = []
        lock.unlock()
        let th = Thread { [weak self] in self?.loop(f) }
        th.name = "Luxmeter"
        thread = th
        th.start()
        return nil
    }

    func stop() {
        lock.lock()
        let f = fd
        running = false
        fd = -1
        port = ""
        lock.unlock()
        if f >= 0 { close(f) }
        thread = nil
    }

    private func loop(_ f: Int32) {
        var packet: [UInt8] = []
        var byte: UInt8 = 0
        while isRunning {
            let n = read(f, &byte, 1)
            if n <= 0 { usleep(20_000); continue }
            if byte == 0x02 { packet = [byte]; continue }
            guard !packet.isEmpty else { continue }
            packet.append(byte)
            if byte == 0x0D {
                if let v = Self.parse(packet) {
                    lock.lock()
                    readings.append((Date(), v))
                    if readings.count > 600 { readings.removeFirst(readings.count - 600) }
                    lock.unlock()
                }
                packet = []
            } else if packet.count > 64 {
                packet = []
            }
        }
    }

    /// HCFR's SetLuxmeterValue: "\u{2}411" + unit ('5' lux, '6' ft-cd) + sign + scale + "0000" + digits + CR.
    static func parse(_ p: [UInt8]) -> Double? {
        let s = String(decoding: p, as: UTF8.self)
        let c = Array(s)
        guard c.count >= 12, s.hasPrefix("\u{2}411"), c[4] == "5" || c[4] == "6", c[5] == "0" || c[5] == "1",
              "012378".contains(c[6]), String(c[7..<11]) == "0000" else { return nil }
        let mul: Double = ["0": 1, "1": 0.1, "2": 0.01, "3": 0.001, "7": 10, "8": 100][c[6]] ?? 1
        let digits = String(c[11...].prefix { $0.isNumber })
        guard let n = Double(digits) else { return nil } // out of range (0x18 / 0x19)
        var v = n * mul * (c[5] == "1" ? -1 : 1)
        if c[4] == "6" { v /= 0.0929 } // ft-cd -> lux
        return v
    }

    /// Average of the values received since `start` (the colorimeter reading), else the latest one.
    func value(since start: Date) -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard running, !readings.isEmpty else { return nil }
        let recent = readings.filter { $0.0 >= start }.map(\.1)
        if !recent.isEmpty { return recent.reduce(0, +) / Double(recent.count) }
        return readings.last.map { Date().timeIntervalSince($0.0) < 5 ? $0.1 : nil } ?? nil
    }
}

// MARK: - Session: extras of each measure, second meter, spectral sample

extension ReferenceData {
    mutating func set(_ t: EditTarget, _ c: XYZ) {
        switch t {
        case .gray(let l): gray[l] = c
        case .patch(let p): colors[p] = c
        case .series(let v, let i): series[v, default: [:]][i] = c
        case .free(let i): series[.freeMeasures, default: [:]][i] = c
        case .contrast: break
        }
    }
}

extension Session {
    /// Keeps the spectrum, luxmeter value and second meter's reading of the measure just stored.
    func attach(_ t: EditTarget) {
        spectra[t.id] = lastSpectrum
        luxValues[t.id] = lastLux
        if simultaneous, let m2 = meter2, let c = lastSecondXYZ {
            if refData?.name != secondMeterName(m2) {
                refData = ReferenceData(name: secondMeterName(m2), grayCount: grayCount)
            }
            refData?.set(t, c)
        }
        lastSpectrum = nil
        lastLux = nil
        lastSecondXYZ = nil
    }

    func secondMeterName(_ m: ArgyllMeter) -> String { "Second meter: " + m.name }

    /// The column selected in the table, as a key of the extras.
    var selectedTarget: EditTarget {
        switch view {
        case .grayScale: return .gray(selectedLevel)
        case .primariesSecondaries: return .patch(selectedPatch)
        case .contrast: return .contrast(selectedIndex)
        case .freeMeasures: return .free(selectedIndex)
        default: return .series(view, selectedIndex)
        }
    }

    // Luxmeter

    func applyLuxPort() {
        if let err = luxmeter.start(appPrefs.luxPort) {
            luxStatus = nil
            errorMessage = err
        } else {
            luxStatus = appPrefs.luxPort.isEmpty ? nil : "Luxmeter on \(appPrefs.luxPort)"
        }
    }

    func lux(_ t: EditTarget) -> Double? { luxValues[t.id] }

    /// "Lux" or "Ft-cd" (Advanced → Imperial units), and the value in that unit.
    var luxLabel: String { appPrefs.imperialUnits ? "Ft-cd" : "Lux" }
    func luxText(_ t: EditTarget) -> String {
        guard let v = luxValues[t.id] else { return "" }
        return String(format: "%.2f", appPrefs.imperialUnits ? v * 0.0929 : v)
    }
    func hasLux(_ v: MeasureView) -> Bool {
        let prefix: String
        switch v {
        case .grayScale: prefix = "gray"
        case .primariesSecondaries: prefix = "patch"
        case .contrast: prefix = "contrast"
        case .freeMeasures: prefix = "free"
        default: prefix = "series:\(v.rawValue):"
        }
        return luxValues.keys.contains { $0.hasPrefix(prefix) }
    }

    // Second meter (simultaneous measures)

    func connectSecondMeter() {
        guard let port = selectedPort2, activity == .idle else { return }
        guard port.name != connectedPortName else {
            errorMessage = "Choose another meter: this one is the main meter."
            return
        }
        status = "Connecting the second meter \(port.displayName)…"
        Task {
            do {
                let m = try await ArgyllMeter.open(port: port)
                if let name = correction?.name, let c = m.corrections.first(where: { $0.name == name }) {
                    try? await m.setCorrection(c)
                }
                meter2 = m
                simultaneous = true
                status = "Second meter connected: \(m.name). Simultaneous measures: its readings go to the compared data (dE / ref)."
            } catch {
                errorMessage = "Second meter: " + error.localizedDescription
            }
        }
    }

    func disconnectSecondMeter() {
        meter2?.close()
        meter2 = nil
        simultaneous = false
    }

    // Spectral sample (CCSS)

    /// Folder for the spectral samples made here; the meter helper finds them (XDG_DATA_DIRS).
    nonisolated static var userCorrectionsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HCFR Colorimeter/ArgyllCMS")
    }

    /// Sensor → "Build colorimeter calibration spectral sample": the spectra measured with a spectro
    /// (white, red, green, blue and any other column) saved as an Argyll CCSS file, which colorimeters
    /// then list as a Display type.
    func createSpectralSample() {
        let order: [EditTarget] = [.patch(.white), .patch(.red), .patch(.green), .patch(.blue), .gray(100),
                                   .patch(.yellow), .patch(.cyan), .patch(.magenta)]
        var list = order.compactMap { spectra[$0.id] }
        if list.count < 3 { list = Array(spectra.values) }
        guard let first = list.first, list.count >= 3 else {
            errorMessage = "Measure white, red, green and blue with a spectrophotometer first (Measure → Primary colors). A colorimeter gives no spectrum."
            return
        }
        list = list.filter { $0.values.count == first.values.count && $0.start == first.start && $0.end == first.end }
        let alert = NSAlert()
        alert.messageText = "Build spectral sample (CCSS)"
        alert.informativeText = "Name of the display (it will appear in the colorimeter's Display list):"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = correction?.name.isEmpty == false ? "My display" : "My display"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? "My display" : field.stringValue
        let dir = Self.userCorrectionsDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-") + ".ccss")
            try Self.ccss(list, display: name, reference: meter?.name ?? "").write(to: file, atomically: true, encoding: .utf8)
            status = "Spectral sample saved: \(file.lastPathComponent). Reconnect the colorimeter to choose it in Display."
        } catch {
            errorMessage = "Could not save the spectral sample: \(error.localizedDescription)"
        }
    }

    static func ccss(_ spectra: [Spectrum], display: String, reference: String) -> String {
        let s = spectra[0]
        let f = DateFormatter()
        f.dateFormat = "EEE MMM dd HH:mm:ss yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        let names = (0..<s.values.count).map { "SPEC_\(Int(s.wavelength($0).rounded()))" }
        var lines = [
            "CCSS   ", "",
            "ORIGINATOR \"HCFR Colorimeter for macOS\"",
            "CREATED \"\(f.string(from: Date()))\"",
            "KEYWORD \"DISPLAY\"", "DISPLAY \"\(display)\"",
            "KEYWORD \"TECHNOLOGY\"", "TECHNOLOGY \"\(display)\"",
            "KEYWORD \"DISPLAY_TYPE_REFRESH\"", "DISPLAY_TYPE_REFRESH \"NO\"",
            "KEYWORD \"REFERENCE\"", "REFERENCE \"\(reference)\"",
            "KEYWORD \"SPECTRAL_BANDS\"", "SPECTRAL_BANDS \"\(s.values.count)\"",
            "KEYWORD \"SPECTRAL_START_NM\"", String(format: "SPECTRAL_START_NM \"%.6f\"", s.start),
            "KEYWORD \"SPECTRAL_END_NM\"", String(format: "SPECTRAL_END_NM \"%.6f\"", s.end),
            "KEYWORD \"SPECTRAL_NORM\"", "SPECTRAL_NORM \"1.000000\"",
            "DESCRIPTOR \"Made with HCFR Colorimeter for macOS\"", "",
        ]
        lines += names.map { "KEYWORD \"\($0)\"" }
        lines += ["NUMBER_OF_FIELDS \(s.values.count + 1)", "BEGIN_DATA_FORMAT", "SAMPLE_ID " + names.joined(separator: " "),
                  "END_DATA_FORMAT", "", "NUMBER_OF_SETS \(spectra.count)", "BEGIN_DATA"]
        for (i, sp) in spectra.enumerated() {
            lines.append("\(i + 1) " + sp.values.map { String(format: "%.6g", $0) }.joined(separator: " "))
        }
        lines += ["END_DATA", ""]
        return lines.joined(separator: "\n")
    }
}
