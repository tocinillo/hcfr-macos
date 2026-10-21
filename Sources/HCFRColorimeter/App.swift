// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI

@main
struct ColorimeterApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var session = Session()

    init() { Snapshot.runIfRequested() }

    var body: some Scene {
        Window("HCFR Colorimeter", id: "main") {
            ContentView(session: session)
                .frame(minWidth: 1180, minHeight: 680)
                .onAppear { AppDelegate.session = session }
                .background(WindowCloseGuard(session: session))
        }
        .defaultSize(width: 1400, height: 860)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About HCFR Colorimeter") { AboutPanel.show() }
            }
            CommandGroup(before: .newItem) {
                Button("Calibration Wizard…") { session.openWizard() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                Divider()
            }
            CommandGroup(replacing: .newItem) {
                Button("New Project") { session.confirmNewProject = true }
                    .keyboardShortcut("n")
                Button("Open Project…") { session.openProjectDialog() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Project") { session.saveProject() }
                    .keyboardShortcut("s")
                Button("Save Project As…") { session.saveProject(as: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Compare with Project…") { session.chooseReferenceProject() }
                Button("Stop Comparing") { session.refData = nil }
                    .disabled(session.refData == nil)
                Divider()
                Button("Export Measurements (CSV)…") { session.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!session.hasMeasurements)
                Button("Export HCFR sheets (CSV)…") { session.exportHCFRSheets() }
                    .disabled(!session.hasMeasurements)
                Button("Create PDF Report…") { session.exportPDFReport() }
                    .disabled(!session.hasMeasurements)
            }
            CommandMenu("Patterns") {
                Button("Black +1% & +2% moving bars") { session.showMovingBars(white: false) }
                Button("White −1% & −2% moving bars") { session.showMovingBars(white: true) }
                ForEach(TestImages.groups, id: \.0) { group in
                    Menu(tr(group.0)) {
                        ForEach(group.1) { t in Button(tr(t.title)) { session.showTestImage(t) } }
                    }
                }
                Divider()
                Button("Show color…") { session.editingTestColor = true }
                Button("Hide pattern") { session.hideTestPattern() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(session.testPatternShown == nil)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy Table") { session.copyTable() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(!session.hasMeasurements)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") { Report.printReport(session) }
                    .keyboardShortcut("p")
                    .disabled(!session.hasMeasurements)
            }
            HelpCommands()
        }

        Settings {
            PreferencesView(session: session)
        }
    }
}

enum AboutPanel {
    static let version = "1.3.1"
    /// Public repository with this program's complete source code (GPL v2 requirement).
    static let sourceURL = "https://github.com/diablonet/HCFR-Colorimeter-macOS"

    static func show() {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let bold = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        center.paragraphSpacing = 6

        let credits = NSMutableAttributedString()
        func add(_ text: String, font: NSFont = body, link: String? = nil) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: center,
                                                        .foregroundColor: NSColor.labelColor]
            if let link, let url = URL(string: link) { attrs[.link] = url }
            credits.append(NSAttributedString(string: text, attributes: attrs))
        }
        add("Unofficial macOS port of HCFR, not affiliated with the HCFR project.\n\n", font: bold)
        add("Built from the source code of HCFR Colorimeter for Windows (version 3.5.4.4), "
            + "a free and open-source display calibration program created by the HCFR community "
            + "(homecinema-fr.com). The color calculations follow HCFR's own formulas, and the "
            + "colorimeter drivers and CCSS corrections are the ones included in HCFR.\n\n")
        add("Source code: ")
        add(sourceURL.replacingOccurrences(of: "https://", with: ""), link: sourceURL)
        add("\nHCFR project: ")
        add("github.com/arthur-liberman/hcfr-code", link: "https://github.com/arthur-liberman/hcfr-code")
        add("\nOriginal project: ")
        add("sourceforge.net/projects/hcfr", link: "https://sourceforge.net/projects/hcfr/")
        add("\nColorimeter drivers: ArgyllCMS, Copyright Graeme W. Gill (")
        add("argyllcms.com", link: "https://www.argyllcms.com")
        add(")\nHCFR: Copyright Association Homecinema Francophone and HCFR contributors\n\n")
        add("This program is free software: you can redistribute it and/or modify it under the terms "
            + "of the GNU General Public License version 2. It comes with ABSOLUTELY NO WARRANTY. ")
        add("License", link: "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html")
        add(" (also in the app: Contents/Resources/LICENSE.txt).")

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "HCFR Colorimeter",
            .applicationVersion: version,
            .version: "5",
            .credits: credits,
        ])
    }
}

/// Asks "Save the current measurements?" when the window is closed (red button or ⌘W), before it
/// closes. Cancel keeps the window open. Without this the window closed first and, on Cancel, the
/// windowless app asked again in a loop.
private struct WindowCloseGuard: NSViewRepresentable {
    let session: Session

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            context.coordinator.install(on: window, session: session)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Window delegate that answers windowShouldClose and forwards everything else to SwiftUI's.
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var original: NSWindowDelegate?
        private weak var session: Session?

        @MainActor func install(on window: NSWindow, session: Session) {
            guard !(window.delegate is Coordinator) else { return }
            self.session = session
            original = window.delegate
            window.delegate = self
        }

        @MainActor func windowShouldClose(_ sender: NSWindow) -> Bool {
            if let session, !session.confirmDiscardChanges() { return false }
            AppDelegate.alreadyConfirmedQuit = true
            return original?.windowShouldClose?(sender) ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var session: Session?
    /// The user already answered the save question when closing the window.
    @MainActor static var alreadyConfirmedQuit = false

    /// Double-clicking a .hcfrex file in Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            guard let url = urls.first else { return }
            // hcfr:// links from other programs (PCG's autocalibration): Automation.swift
            if url.scheme == "hcfr" {
                var tries = 0
                while AppDelegate.session == nil && tries < 30 { try? await Task.sleep(for: .milliseconds(200)); tries += 1 }
                AppDelegate.session?.handleAutomation(url)
                return
            }
            if let session = AppDelegate.session {
                if session.confirmDiscardChanges() { session.openProject(url) }
            } else {
                // Window not ready yet: open it as soon as it is
                try? await Task.sleep(for: .seconds(1))
                if let session = AppDelegate.session { session.openProject(url) }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Writing to a meter helper that already stopped must not kill the app
        signal(SIGPIPE, SIG_IGN)
        // Needed when run as a bare binary (swift run) instead of the .app
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Ask to save unsaved measurements before quitting.
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session = AppDelegate.session, !AppDelegate.alreadyConfirmedQuit else { return .terminateNow }
        if session.confirmDiscardChanges() {
            AppDelegate.alreadyConfirmedQuit = true
            return .terminateNow
        }
        return .terminateCancel
    }
}
