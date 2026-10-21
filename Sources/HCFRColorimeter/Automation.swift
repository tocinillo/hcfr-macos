// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Automation added in 2026: other programs (PCG's JVC autocalibration) ask HCFR for readings
// with hcfr:// links and get the results as files.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit

/// hcfr://status?out=/path/name
///     → name.result.json: {"ok", "meter", "display", "generator", "points", "busy"}
/// hcfr://measure-grayscale?points=33&out=/path/name
///     → measures the gray scale (no confirmation) and writes name.GrayScaleSheet.csv (HCFR's
///       export layout) and name.result.json ({"ok": true/false, "message": …}) when finished.
/// hcfr://measure-level?level=50&out=/path/name
///     → reads one gray level (0…100 % white) through the generator and writes name.result.json
///       with X Y Z, x y, R G B (HCFR's RGB rows), the Y target, ΔE and gamma of that level, as the
///       gray scale table would show them (the reading also goes into the table if the level is in it).
/// hcfr://stop?out=/path/name → stops the measures in progress.
extension Session {
    func handleAutomation(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let out = q("out"), !out.isEmpty else { return }

        func finish(_ ok: Bool, _ message: String, extra: [String: Any] = [:]) {
            var d: [String: Any] = ["ok": ok, "message": message]
            d.merge(extra) { $1 }
            if let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted]) {
                try? data.write(to: URL(fileURLWithPath: out + ".result.json"), options: .atomic)
            }
        }

        switch url.host {
        case "status":
            finish(meter != nil, meter == nil ? "No colorimeter connected in HCFR" : "Ready", extra: [
                "meter": meter?.name ?? "",
                "display": correction?.name ?? "",
                "generator": automationGeneratorName,
                "points": grayCount,
                "busy": activity != .idle,
                "overrideBlack": overrideBlack,
                "reference": gammaDescription,
                "whiteY": whiteY ?? 0,
            ])

        case "measure-grayscale":
            guard meter != nil else { finish(false, "No colorimeter connected in HCFR"); return }
            if activity == .continuous { stop() }
            guard activity == .idle, prompt == nil else { finish(false, "HCFR is busy"); return }
            if let p = q("points").flatMap(Int.init), p != grayCount { setGrayCount(p, confirmed: true) }
            view = .grayScale
            wizardSkipConfirm = true
            status = "Automatic measure requested by \(q("from") ?? "another program")"
            measure(.grayScale)
            guard activity == .measuring else { finish(false, "The measure could not start"); return }
            Task { @MainActor in
                while self.activity != .idle { try? await Task.sleep(for: .milliseconds(300)) }
                let missing = self.levels.filter { self.measurements[$0] == nil }
                guard missing.isEmpty else {
                    finish(false, self.errorMessage ?? trMessage(self.status))
                    return
                }
                if let sheet = self.hcfrSheets().first(where: { $0.0 == "GrayScaleSheet" }) {
                    do {
                        try sheet.1.write(toFile: out + ".GrayScaleSheet.csv", atomically: true, encoding: .utf8)
                        finish(true, "Measured \(self.levels.count) levels", extra: ["points": self.grayCount])
                    } catch {
                        finish(false, error.localizedDescription)
                    }
                }
            }

        case "measure-level":
            guard let level = q("level").flatMap(Double.init), level >= 0, level <= 100 else {
                finish(false, "Bad level"); return
            }
            guard meter != nil else { finish(false, "No colorimeter connected in HCFR"); return }
            if activity == .continuous { stop() }
            guard activity == .idle, prompt == nil else { finish(false, "HCFR is busy"); return }
            view = .grayScale
            run(.measuring) {
                do {
                    try await self.present(.gray(level))
                    self.status = "Measuring \(Reference.label(level)) IRE…"
                    let xyz = try await self.readWithCalibration(pattern: .gray(level))
                    if self.allLevels.contains(level) {
                        self.measurements[level] = xyz
                        self.selectedLevel = level
                        self.lastMeasure = Date()
                        self.isDirty = true
                    }
                    let white = level == 100 ? xyz.Y : self.whiteY
                    let r = StepResult(level: level, xyz: xyz, whiteY: white, baseY: white ?? baseWhiteY,
                                       blackY: self.targetBlackY, ref: self.ref)
                    let rgb = ColorMath.rgb(xyz, ref: self.ref)
                    finish(true, "Measured \(Reference.label(level)) IRE", extra: [
                        "level": level, "X": xyz.X, "Y": xyz.Y, "Z": xyz.Z, "x": xyz.x, "y": xyz.y,
                        "R": rgb[0], "G": rgb[1], "B": rgb[2],
                        "targetY": r.targetY ?? 0, "deltaE": r.deltaE ?? 0, "gamma": r.gamma ?? 0,
                        "whiteY": white ?? 0,
                    ])
                    self.status = "Measured \(Reference.label(level)) IRE (requested by \(q("from") ?? "another program"))"
                } catch {
                    finish(false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                    throw error
                }
            }

        case "stop":
            // The other program cancelled: stop the measures it asked for
            if activity != .idle { stop() }
            finish(true, "Stopped")

        default:
            finish(false, "Unknown request: \(url.host ?? "")")
        }
    }

    private var automationGeneratorName: String {
        switch patternSource {
        case .manual: return "manual"
        case .raspberryPi: return "Raspberry Pi"
        case .display: return "display"
        case .window: return "window"
        case .madVR: return "madVR"
        case .chromecast: return "Chromecast"
        }
    }
}
