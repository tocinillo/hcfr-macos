// HCFR Colorimeter for macOS
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
        let c = try await piClient()
        status = "Setting PGenerator output: \(o.summary)…"
        for cmd in o.setCommands {
            let r = try await c.get(cmd)
            if !r.hasPrefix("OK") {
                throw PGeneratorError.communication("PGenerator did not accept \"\(cmd)\" (answer: \"\(r)\").")
            }
        }
        _ = try? await c.get("RESTARTPGENERATOR:")
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
                let c = try await piClient()
                let a = try await c.get(PiOutput.readCommand)
                guard let o = PiOutput.parse(a) else {
                    errorMessage = tr("This PGenerator did not report its output settings (it may be an old version).")
                    return
                }
                piCurrentOutput = o
                piOutput = o
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
            try? await c.osd("HCFR Colorimeter for macOS")
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
