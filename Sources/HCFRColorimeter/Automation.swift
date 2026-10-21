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
        }
    }
}
