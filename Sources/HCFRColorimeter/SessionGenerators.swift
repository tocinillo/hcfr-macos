// HCFR for macOS
// Copyright (C) 2026 Jorge Velázquez
// PGenerator output control and madVR Envy / madTPG generator added in 2026.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import Foundation

extension Session {
    // MARK: - PGenerator output (SDR / HDR10, color format, bit depth, range, HDR metadata)

    /// The output the Pi should have for the current reference: with automatic mode, HDR10 when
    /// the reference curve is ST.2084 (PQ), SDR otherwise (10 bits for HDR).
    var piWantedOutput: PiOutput {
        var o = piOutput
        if piAutoMode {
            o.hdr = prefs.mode == .st2084
            if o.hdr { o.bitDepth = 10 }
        }
        return o
    }

    /// Before the first pattern of a run: puts the Pi in the wanted mode if it is not already.
    func ensurePiMode() async throws {
        guard piAutoMode else { return }
        let want = piWantedOutput
        if let now = piCurrentOutput, now.matches(want) { return }
        if piCurrentOutput == nil { _ = try await piClient() }
        if let now = piCurrentOutput, now.matches(want) { return }
        try await applyPiOutput(want)
    }

    /// Sends the output settings to PGenerator and restarts it so they take effect.
    func applyPiOutput(_ o: PiOutput) async throws {
        piApplying = true
        defer { piApplying = false }
        _ = try await piClient()
        status = "Setting PGenerator output: \(o.summary)…"
        for cmd in o.setCommands {
            let r = try await piGet(cmd)
            if !r.hasPrefix("OK") {
                throw PGeneratorError.communication("PGenerator did not accept \"\(cmd)\" (answer: \"\(r)\").")
            }
        }
        _ = try? await piGet("RESTARTPGENERATOR:")
        status = "Restarting PGenerator with the new output…"
        dropPi()
        // PGenerator takes a few seconds to come back
        var lastError: Error?
        for _ in 0..<10 {
            try await Task.sleep(for: .seconds(2))
            do {
                _ = try await piClient()
                lastError = nil
                break
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        if piCurrentOutput == nil { piCurrentOutput = o }
        shownPattern = nil
        status = "PGenerator output: \((piCurrentOutput ?? o).summary)"
    }

    /// A command that expects an answer; if the connection was lost (PGenerator restarting, a
    /// network drop) it reconnects once, as the patterns do.
    func piGet(_ command: String) async throws -> String {
        do {
            return try await piClient().get(command)
        } catch PGeneratorError.communication {
            dropPi()
            return try await piClient().get(command)
        }
    }

    /// Generator → PGenerator output… → Apply.
    func applyPiOutputNow() {
        Task {
            do { try await applyPiOutput(piOutput) } catch { errorMessage = error.localizedDescription }
        }
    }

    /// Generator → PGenerator output… → Read from the Pi: the dialog starts from the Pi's settings.
    func readPiOutput() {
        Task {
            do {
                let a = try await piGet(PiOutput.readCommand)
                guard let o = PiOutput.parse(a) else {
                    errorMessage = tr("This PGenerator did not report its output settings (it may be an old version).")
                    return
                }
                piCurrentOutput = o
                piOutput = o
                coordinateLevels(withLimited: o.limited)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Reads the Pi's video modes (resolutions) for the output sheet. Best-effort and silent: some
    /// PGenerator versions don't answer GET_MODES_AVAILABLE, and that must not pop up an error or
    /// disturb a working connection — the resolution picker simply stays hidden.
    func readPiModes() {
        Task {
            guard let c = try? await piClient() else { return }
            if let (current, list) = try? await c.modes() {
                piModes = list
                piCurrentMode = current
            }
        }
    }

    /// Sets the Pi's video mode (resolution) and reconnects once it has restarted.
    func setPiMode(_ id: Int) {
        Task {
            piApplying = true
            defer { piApplying = false }
            do {
                let c = try await piClient()
                status = "Setting the PGenerator resolution…"
                try await c.setMode(id)
                dropPi()
                try await Task.sleep(for: .seconds(3))
                _ = try? await piClient()
                piCurrentMode = id
                readPiModes()
                status = "PGenerator resolution set"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Reboots the Raspberry Pi.
    func rebootPi() {
        Task {
            if let c = try? await piClient() { try? await c.reboot() }
            dropPi()
            status = "Rebooting the Raspberry Pi — it will be back in a minute"
        }
    }

    /// Coordinates the pattern Levels with the PGenerator range (feature request). Only one place in
    /// the chain may limit the range, or the signal is scaled twice: PGenerator set to Limited already
    /// compresses the output to 16–235, so the patterns must then be sent Full (PC, 0–255). The only
    /// invalid pair is Video patterns + Limited PGenerator (double scaling); the others are all valid
    /// (PC + Full for a full-range display, PC + Limited or Video + Full for a limited-range display).
    /// Changing one setting only moves the other when needed to avoid that double scaling.
    func coordinateLevels(withLimited pgenLimited: Bool) {   // the PGenerator range changed
        if pgenLimited && videoLevels == .video { videoLevels = .full }
    }

    func coordinateRange(withLevels levels: VideoLevels) {   // the Generator-menu Levels changed
        if levels == .video && piOutput.limited { piOutput.limited = false }
    }

    // MARK: - madVR Envy / madTPG

    /// Sends to madVR; if the connection was lost, reconnects once.
    func madVRSend(_ body: (MadVRClient) async throws -> Void) async throws {
        do {
            try await body(try await madVRClient())
        } catch is MadVRError {
            dropMadVR()
            try await body(try await madVRClient())
        }
    }

    /// The connected madVR, connecting first if needed (one attempt at a time).
    func madVRClient() async throws -> MadVRClient {
        if let madVR { return madVR }
        if let madVRConnecting { return try await madVRConnecting.value }
        let host = madVRAddress
        guard !host.isEmpty else {
            editingMadVRAddress = true
            madVRAddressDraft = ""
            throw MadVRError.communication(tr("Enter the IP address of the madVR Envy (or of the PC running madTPG) in Generator → madVR address."))
        }
        let t = Task { @MainActor () throws -> MadVRClient in
            self.status = "Connecting to madVR at \(host)…"
            let c = MadVRClient(host: host)
            try await c.connect()
            try? await c.osd("HCFR for macOS")
            await c.applyOptions(disable3DLUT: self.madVRDisable3DLUT, disableCalibration: self.madVRDisableCalibration,
                                 hdr: self.madVRHDR, osd: self.madVROSD)
            return c
        }
        madVRConnecting = t
        defer { madVRConnecting = nil }
        do {
            let c = try await t.value
            madVR = c
            madVRStatus = c.peerDescription.isEmpty ? c.host : "\(c.host) · \(c.peerDescription)"
            status = "madVR connected at \(c.host)"
            return c
        } catch {
            madVRStatus = nil
            status = "madVR not connected"
            throw error
        }
    }

    /// Patch position and screen blanking → the pattern window.
    func syncPatternWindow() {
        patternWindow.offset = CGPoint(x: patchOffsetX / 100, y: patchOffsetY / 100)
        patternWindow.blankOthers = blankOtherScreens
    }

    /// The madTPG options changed: send them to the connected madVR.
    func madVRApply() {
        guard let c = madVR else { return }
        let o = (madVRDisable3DLUT, madVRDisableCalibration, madVRHDR, madVROSD)
        Task { await c.applyOptions(disable3DLUT: o.0, disableCalibration: o.1, hdr: o.2, osd: o.3) }
    }

    func connectMadVR() {
        Task {
            do { _ = try await madVRClient() } catch { errorMessage = error.localizedDescription }
        }
    }

    func dropMadVR() {
        guard let c = madVR else { return }
        madVR = nil
        madVRStatus = nil
        c.close()
    }

    // MARK: - Chromecast

    /// Sends to the Chromecast; if the connection was lost, reconnects once.
    func chromecastSend(_ body: (ChromecastClient) async throws -> Void) async throws {
        do {
            try await body(try await chromecastClient())
        } catch is ChromecastError {
            dropChromecast()
            try await body(try await chromecastClient())
        }
    }

    /// The connected Chromecast, connecting first if needed (the chosen one, or the only one found).
    func chromecastClient() async throws -> ChromecastClient {
        if let chromecast { return chromecast }
        if let chromecastConnecting { return try await chromecastConnecting.value }
        let wanted = chromecastName
        let t = Task { @MainActor () throws -> ChromecastClient in
            var device: ChromecastDevice?
            if PGeneratorClient.isValidIPv4(wanted) {
                device = .address(wanted)
            } else {
                self.status = "Looking for the Chromecast on the network…"
                let found = await ChromecastClient.discover(timeout: 3)
                self.chromecastDevices = found
                device = found.first(where: { $0.name == wanted }) ?? (wanted.isEmpty && found.count == 1 ? found[0] : nil)
                if device == nil {
                    self.choosingChromecast = true
                    throw found.isEmpty ? ChromecastError.notFound
                        : ChromecastError.communication(tr("Choose the Chromecast in Generator → Chromecast…"))
                }
            }
            guard let device else { throw ChromecastError.notFound }
            self.status = "Connecting to the Chromecast \(device.name)…"
            let c = ChromecastClient(device: device)
            try await c.connect()
            return c
        }
        chromecastConnecting = t
        defer { chromecastConnecting = nil }
        do {
            let c = try await t.value
            chromecast = c
            chromecastStatus = c.device.name + (c.usesPatternReceiver ? "" : " · " + tr("default receiver"))
            status = "Chromecast connected: \(c.device.name)"
            return c
        } catch {
            chromecastStatus = nil
            status = "Chromecast not connected"
            throw error
        }
    }

    func connectChromecast() {
        Task {
            do { _ = try await chromecastClient() } catch { errorMessage = error.localizedDescription }
        }
    }

    func dropChromecast() {
        guard let c = chromecast else { return }
        chromecast = nil
        chromecastStatus = nil
        c.close()
    }

    /// Generator → Chromecast…: looks for the Chromecasts on the network.
    func searchChromecasts() {
        searchingChromecast = true
        Task {
            chromecastDevices = await ChromecastClient.discover(timeout: 3)
            searchingChromecast = false
        }
    }

    /// Uses this Chromecast (its name, or an IP address) as generator.
    func chooseChromecast(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        chromecastName = n
        defaults.set(n, forKey: "chromecastName")
        choosingChromecast = false
        dropChromecast()
        if patternSource == .chromecast { connectChromecast() } else { patternSource = .chromecast }
    }

    /// Generator → madVR address: the IPv4 address of the Envy or of the PC with madTPG.
    func setMadVRAddress(_ text: String) {
        let a = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PGeneratorClient.isValidIPv4(a) else {
            errorMessage = MadVRError.badAddress(a).localizedDescription
            return
        }
        guard a != madVRAddress || madVR == nil else { return }
        madVRAddress = a
        defaults.set(a, forKey: "madVRAddress")
        dropMadVR()
        if patternSource == .madVR { connectMadVR() } else { patternSource = .madVR }
    }
}
