// HCFR for macOS
// Copyright (C) 2026 Jorge Velázquez
// Help menu added in 2026 after HCFR for Windows' Help menu (MainFrm.cpp: OnHelpInstall,
// OnHelpSupport, OnUpdateSoft), GNU GPL.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import SwiftUI

enum HelpLinks {
    /// "Colorimeter Installation": HCFR for Windows opens ArgyllCMS' installation page; this is its macOS one.
    static let install = URL(string: "https://www.argyllcms.com/doc/Installing_OSX.html")!
    /// "Support": the HCFR thread at AVS Forum, as HCFR for Windows.
    static let support = URL(string: "https://www.avsforum.com/threads/hcfr-open-source-projector-display-calibration-software.1393853/")!
    static let releasesAPI = URL(string: "https://api.github.com/repos/tocinillo/hcfr-macos/releases/latest")!
    static let tagsAPI = URL(string: "https://api.github.com/repos/tocinillo/hcfr-macos/tags")!
    static let releases = URL(string: AboutPanel.sourceURL + "/releases")!

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// Help → Updates → "Check for new software" (and General → "Check for updates" at start-up).
enum UpdateCheck {
    struct Release {
        var version: String
        /// The DMG of the release (nil when it has none: only the page can be opened).
        var dmg: URL?
        var notes: String
    }

    /// Latest published release, from GitHub's API.
    static func latestRelease() async -> Release? {
        var req = URLRequest(url: HelpLinks.releasesAPI, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let r = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = r["tag_name"] as? String else { return nil }
        let assets = r["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        return Release(version: clean(tag), dmg: (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:)),
                       notes: (r["body"] as? String) ?? "")
    }

    static func clean(_ tag: String) -> String {
        String(tag.drop { !$0.isNumber })
    }

    /// "1.10" > "1.9"
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// `quiet`: at start-up, only says something when there is a newer version.
    @MainActor
    static func run(quiet: Bool) {
        Task {
            let rel = await latestRelease()
            let alert = NSAlert()
            if let rel, isNewer(rel.version, than: AboutPanel.version) {
                alert.messageText = tr("A new version is available")
                var info = tr("HCFR for macOS %@ is available (you have %@).", rel.version, AboutPanel.version)
                let notes = rel.notes.components(separatedBy: "\n---").first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !notes.isEmpty { info += "\n\n" + String(notes.prefix(900)) }
                alert.informativeText = info
                let canInstall = rel.dmg != nil && AutoUpdate.canReplaceApp
                if canInstall { alert.addButton(withTitle: tr("Install and Relaunch")) }
                alert.addButton(withTitle: tr("Download"))
                alert.addButton(withTitle: tr("Later"))
                let r = alert.runModal()
                if canInstall && r == .alertFirstButtonReturn, let dmg = rel.dmg {
                    AutoUpdate.install(dmg, version: rel.version)
                } else if r == (canInstall ? .alertSecondButtonReturn : .alertFirstButtonReturn) {
                    HelpLinks.open(HelpLinks.releases)
                }
            } else if !quiet {
                if rel == nil {
                    alert.messageText = tr("Could not check for updates")
                    alert.informativeText = tr("No answer from GitHub. Check the internet connection, or look at the project page.")
                    alert.addButton(withTitle: tr("OK"))
                    alert.addButton(withTitle: tr("Open project page"))
                    if alert.runModal() == .alertSecondButtonReturn { HelpLinks.open(HelpLinks.releases) }
                } else {
                    alert.messageText = tr("HCFR for macOS is up to date")
                    alert.informativeText = tr("You have the latest version (%@).", AboutPanel.version)
                    alert.runModal()
                }
            }
        }
    }
}

/// Installs a new version without going through the DMG by hand: downloads the release's DMG,
/// copies the app out of it, quits, replaces this app with it and opens it again.
enum AutoUpdate {
    static var appURL: URL { Bundle.main.bundleURL }

    /// The app can be replaced: it runs from a real .app (not from the DMG or a translocated copy)
    /// in a folder this user can write to.
    static var canReplaceApp: Bool {
        let path = appURL.path
        guard path.hasSuffix(".app"), !path.contains("/AppTranslocation/"), !path.hasPrefix("/Volumes/") else { return false }
        return FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: path)
    }

    @MainActor
    static func install(_ dmg: URL, version: String) {
        let panel = UpdateProgress.show(tr("Downloading HCFR for macOS %@…", version))
        Task.detached {
            do {
                let staged = try await prepare(dmg)
                await MainActor.run {
                    panel.close()
                    relaunch(with: staged)
                }
            } catch {
                await MainActor.run {
                    panel.close()
                    let a = NSAlert()
                    a.messageText = tr("The update could not be installed")
                    a.informativeText = error.localizedDescription
                    a.addButton(withTitle: tr("Download"))
                    a.addButton(withTitle: tr("Cancel"))
                    if a.runModal() == .alertFirstButtonReturn { HelpLinks.open(HelpLinks.releases) }
                }
            }
        }
    }

    /// Downloads the DMG, mounts it and copies its app to a temporary folder; returns that copy.
    private static func prepare(_ dmg: URL) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("HCFR-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let (file, resp) = try await URLSession.shared.download(from: dmg)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("The download failed.") }
        let image = work.appendingPathComponent("update.dmg")
        try FileManager.default.moveItem(at: file, to: image)
        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        guard let app = try FileManager.default.contentsOfDirectory(atPath: mount.path).first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError("The DMG has no app.")
        }
        let staged = work.appendingPathComponent(app)
        try run("/usr/bin/ditto", [mount.appendingPathComponent(app).path, staged.path])
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    /// Quits; a small script waits for the app to end, swaps the app and opens the new one.
    @MainActor
    private static func relaunch(with staged: URL) {
        let script = """
        #!/bin/sh
        APP="$1"; NEW="$2"; PID="$3"
        n=0
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; n=$((n+1)); [ $n -gt 2000 ] && exit 0; done
        rm -rf "$APP.old"
        if mv "$APP" "$APP.old" && /usr/bin/ditto "$NEW" "$APP"; then
          rm -rf "$APP.old"
        else
          rm -rf "$APP"; mv "$APP.old" "$APP"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null
        rm -rf "$(dirname "$NEW")"
        /usr/bin/open "$APP"
        """
        let scriptURL = staged.deletingLastPathComponent().appendingPathComponent("install.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [scriptURL.path, appURL.path, staged.path, String(ProcessInfo.processInfo.processIdentifier)]
            try p.run()
        } catch {
            HelpLinks.open(HelpLinks.releases)
            return
        }
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else { throw UpdateError(text.isEmpty ? "\(tool) failed" : text) }
        return text
    }

    struct UpdateError: LocalizedError {
        let message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { tr(message) }
    }
}

/// Small window with a spinner while the update downloads.
enum UpdateProgress {
    @MainActor
    static func show(_ text: String) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "HCFR for macOS"
        let spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 33, width: 24, height: 24))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 56, y: 35, width: 290, height: 20)
        panel.contentView?.addSubview(spinner)
        panel.contentView?.addSubview(label)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        return panel
    }
}

/// The Help menu: same entries as HCFR for Windows.
struct HelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Colorimeter Installation") { HelpLinks.open(HelpLinks.install) }
            Menu("Updates") {
                Button("Check for new software") { UpdateCheck.run(quiet: false) }
            }
            Button("Support") { HelpLinks.open(HelpLinks.support) }
        }
    }
}
