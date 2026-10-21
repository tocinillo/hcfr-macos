// HCFR Colorimeter for macOS
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
    static let releasesAPI = URL(string: "https://api.github.com/repos/diablonet/HCFR-Colorimeter-macOS/releases/latest")!
    static let tagsAPI = URL(string: "https://api.github.com/repos/diablonet/HCFR-Colorimeter-macOS/tags")!
    static let releases = URL(string: AboutPanel.sourceURL + "/releases")!

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// Help → Updates → "Check for new software" (and General → "Check for updates" at start-up).
enum UpdateCheck {
    /// Latest published version ("1.2"), from the releases or, without any, the tags of the repository.
    static func latest() async -> String? {
        func get(_ url: URL) async -> Any? {
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        if let r = await get(HelpLinks.releasesAPI) as? [String: Any], let tag = r["tag_name"] as? String { return clean(tag) }
        if let t = await get(HelpLinks.tagsAPI) as? [[String: Any]] {
            return t.compactMap { $0["name"] as? String }.map(clean).max { isNewer($1, than: $0) }
        }
        return nil
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
            let v = await latest()
            let alert = NSAlert()
            if let v, isNewer(v, than: AboutPanel.version) {
                alert.messageText = tr("A new version is available")
                alert.informativeText = tr("HCFR Colorimeter %@ is available (you have %@).", v, AboutPanel.version)
                alert.addButton(withTitle: tr("Download"))
                alert.addButton(withTitle: tr("Later"))
                if alert.runModal() == .alertFirstButtonReturn { HelpLinks.open(HelpLinks.releases) }
            } else if !quiet {
                if v == nil {
                    alert.messageText = tr("Could not check for updates")
                    alert.informativeText = tr("No answer from GitHub. Check the internet connection, or look at the project page.")
                    alert.addButton(withTitle: tr("OK"))
                    alert.addButton(withTitle: tr("Open project page"))
                    if alert.runModal() == .alertSecondButtonReturn { HelpLinks.open(HelpLinks.releases) }
                } else {
                    alert.messageText = tr("HCFR Colorimeter is up to date")
                    alert.informativeText = tr("You have the latest version (%@).", AboutPanel.version)
                    alert.runModal()
                }
            }
        }
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
