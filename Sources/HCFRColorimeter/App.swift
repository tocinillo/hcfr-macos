// HCFR for macOS
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
    /// The project of the window in front (the menus act on it); the main window's otherwise.
    @FocusedValue(\.activeSession) private var focusedSession
    private var s: Session { focusedSession ?? session }
    @Environment(\.openWindow) private var openWindow

    init() { Snapshot.runIfRequested() }

    /// Opens a project. Several projects can be open at once (as HCFR for Windows): if the window in
    /// front already holds a project, this opens the new one in its own window instead of replacing it.
    private func openProjectKeepingOthers(_ url: URL) {
        if s.hasMeasurements || s.projectURL != nil {
            openWindow(id: "document", value: DocumentRequest(path: url.path))
        } else {
            s.openProject(url)
        }
    }

    private func openProjectDialogKeepingOthers() {
        guard s.activity == .idle else { return }
        let panel = NSOpenPanel()
        panel.title = tr("Open project")
        panel.allowedContentTypes = [.hcfrProject, .hcfrWindows, .json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { openProjectKeepingOthers(url) }
    }

    var body: some Scene {
        Window("HCFR for macOS", id: "main") {
            ContentView(session: session)
                .frame(minWidth: 1180, minHeight: 680)
                .onAppear { AppDelegate.session = session }
                .background(WindowCloseGuard(session: session))
                .background(OpenWindowCapture())
        }
        .defaultSize(width: 1400, height: 860)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About HCFR for macOS") { AboutPanel.show() }
                Button("Check for Updates…") { UpdateCheck.run(quiet: false) }
            }
            CommandGroup(before: .newItem) {
                Button("Calibration Wizard…") { s.openWizard() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                Divider()
            }
            CommandGroup(replacing: .newItem) {
                Button("New Project") { s.confirmNewProject = true }
                    .keyboardShortcut("n")
                Button("Open Project…") { openProjectDialogKeepingOthers() }
                    .keyboardShortcut("o")
                Menu("Open Recent") {
                    ForEach(s.recentProjects, id: \.self) { url in
                        Button(url.lastPathComponent) { openProjectKeepingOthers(url) }
                    }
                    if !s.recentProjects.isEmpty { Divider() }
                    Button("Clear Menu") { Session.clearRecent() }
                        .disabled(s.recentProjects.isEmpty)
                }
            }
            // Not "replacing: .saveItem": with the project windows (WindowGroup for:) macOS treats
            // the app as document based and leaves that group out of the File menu.
            CommandGroup(after: .newItem) {
                Divider()
                Button("Save Project") { s.saveProject() }
                    .keyboardShortcut("s")
                Button("Save Project As…") { s.saveProject(as: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Compare with Project…") { s.chooseReferenceProject() }
                Button("Stop Comparing") { s.refData = nil }
                    .disabled(s.refData == nil)
                Button(s.isReferenceProject ? "Update Reference Project" : "Set as Reference Project") { s.setAsReferenceProject() }
                    .disabled(!s.hasMeasurements)
                Button("Clear Reference Project") { s.clearReferenceProject() }
                    .disabled(ProjectReference.current == nil)
                Divider()
                Button("Export Measurements (CSV)…") { s.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!s.hasMeasurements)
                Button("Export HCFR sheets (CSV)…") { s.exportHCFRSheets() }
                    .disabled(!s.hasMeasurements)
                Button("Export to Excel (.xlsx)…") { s.exportExcel() }
                    .disabled(!s.hasMeasurements)
                Button("Add to Excel Workbook…") { s.appendExcel() }
                    .disabled(!s.hasMeasurements)
                Button("Create PDF Report…") { s.exportPDFReport() }
                    .disabled(!s.hasMeasurements)
                Divider()
            }
            MeasureCommands(main: session)
            CommandMenu("Patterns") {
                Button("Black +1% & +2% moving bars") { s.showMovingBars(white: false) }
                Button("White −1% & −2% moving bars") { s.showMovingBars(white: true) }
                ForEach(TestImages.groups, id: \.0) { group in
                    Menu(tr(group.0)) {
                        ForEach(group.1) { t in Button(tr(t.title)) { s.showTestImage(t) } }
                    }
                }
                Menu("User Defined") {
                    ForEach(1...6, id: \.self) { n in
                        Button("User\(n)" + (s.userPatternPath(n).map { ": " + URL(fileURLWithPath: $0).lastPathComponent } ?? " — " + tr("choose an image…"))) {
                            s.showUserPattern(n)
                        }
                    }
                    Divider()
                    Menu("Change image") {
                        ForEach(1...6, id: \.self) { n in Button("User\(n)…") { s.chooseUserPattern(n) } }
                    }
                }
                Divider()
                Button("Additional Patterns…") { AdditionalPatternsPanel.show(s) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Show color…") { s.editingTestColor = true }
                Button("Hide pattern") { s.hideTestPattern() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(s.testPatternShown == nil)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy Table") { s.copyTable() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(!s.hasMeasurements)
            }
            HelpCommands()
            DocumentCommands(main: session)
        }

        WindowGroup("HCFR for macOS", id: "document", for: DocumentRequest.self) { $request in
            DocumentWindow(request: request)
        }
        .defaultSize(width: 1400, height: 860)

        Settings {
            PreferencesView(session: session)
        }
    }
}

enum AboutPanel {
    /// The app's version (Info.plist, from the VERSION file); the fallback is for `swift run`.
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.26"
    /// Public repository with this program's complete source code (GPL v2 requirement).
    static let sourceURL = "https://github.com/tocinillo/hcfr-macos"

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
        add("Built from the source code of HCFR for Windows (version 3.5.4.4), "
            + "a free and open-source display calibration program created by the HCFR community "
            + "(homecinema-fr.com). The color calculations follow HCFR's own formulas, and the "
            + "colorimeter drivers and CCSS corrections are the ones included in HCFR.\n\n")
        add("Source code: ")
        add(sourceURL.replacingOccurrences(of: "https://", with: ""), link: sourceURL)
        add("\nmacOS version by Jorge Velázquez: ")
        add("github.com/diablonet/HCFR-Colorimeter-macOS", link: "https://github.com/diablonet/HCFR-Colorimeter-macOS")
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
            .applicationName: "HCFR for macOS",
            .applicationVersion: version,
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            .credits: credits,
        ])
    }
}

/// Asks "Save the current measurements?" when the window is closed (red button or ⌘W), before it
/// closes. Cancel keeps the window open. Without this the window closed first and, on Cancel, the
/// windowless app asked again in a loop.
/// Captures SwiftUI's openWindow so Finder-opened projects can open in their own window.
private struct OpenWindowCapture: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.onAppear {
            AppDelegate.openDocument = { req in openWindow(id: "document", value: req) }
        }
    }
}

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
            ProjectTabs.prepare(window)
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

    /// Opens a project window from Finder / another scene (set by the main window).
    @MainActor static var openDocument: ((DocumentRequest) -> Void)?

    /// Double-clicking .hcfrex / .chc files in Finder (several projects open as separate windows).
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            let files = urls.filter { $0.scheme != "hcfr" }
            // hcfr:// links from other programs (PCG's autocalibration): Automation.swift
            if let link = urls.first(where: { $0.scheme == "hcfr" }) {
                var tries = 0
                while AppDelegate.session == nil && tries < 30 { try? await Task.sleep(for: .milliseconds(200)); tries += 1 }
                AppDelegate.session?.handleAutomation(link)
            }
            guard !files.isEmpty else { return }
            var tries = 0
            while AppDelegate.session == nil && tries < 30 { try? await Task.sleep(for: .milliseconds(200)); tries += 1 }
            guard let session = AppDelegate.session else { return }
            for url in files {
                // Keep any project already open: fill the front window if it is empty, else a new one
                if session.hasMeasurements || session.projectURL != nil, let open = AppDelegate.openDocument {
                    open(DocumentRequest(path: url.path))
                } else if session.confirmDiscardChanges() {
                    session.openProject(url)
                }
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

/// Measure, Undo / Redo, View → Luminance and Page Setup / Print (kept apart from the app's
/// commands so the compiler can type-check them).
struct MeasureCommands: Commands {
    let main: Session
    @FocusedValue(\.activeSession) private var focused
    private var s: Session { focused ?? main }

    var body: some Commands {
        CommandMenu("Measure") {
            Button("Measure Selected Column") { s.measureSelected() }
                .keyboardShortcut("r")
                .disabled(s.meter == nil || s.activity == .measuring)
            Button(s.activity == .continuous ? "Stop Continuous Reading" : "Read Selected Column Continuously") {
                s.activity == .continuous ? s.stop() : s.start()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(s.meter == nil || s.activity == .measuring)
            Divider()
            // HCFR for Windows' function keys
            Group {
                Button("Gray scale") { s.measure(.grayScale) }.keyboardShortcut(FKey.f2, modifiers: [])
                Button("Primary colors") { s.measure(.primaries) }.keyboardShortcut(FKey.f3, modifiers: [])
                Button("Primary and secondary colors") { s.measure(.primariesSecondaries) }.keyboardShortcut(FKey.f4, modifiers: [])
                Button("Gray scale and colors") { s.measure(.grayScaleAndColors) }.keyboardShortcut(FKey.f5, modifiers: [])
                Button("Full Tilt Boogie") { s.measure(.fullTiltBoogie) }.keyboardShortcut(FKey.f5, modifiers: [.shift])
            }
            .disabled(s.meter == nil || s.activity != .idle)
            Divider()
            Button("Single measurement") { s.measureSelected() }
                .keyboardShortcut(FKey.f7, modifiers: [])
                .disabled(s.meter == nil || s.activity == .measuring)
            Button("Continuous measurement") { s.activity == .continuous ? s.stop() : s.start() }
                .keyboardShortcut(FKey.f8, modifiers: [])
                .disabled(s.meter == nil || s.activity == .measuring)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(tr("Undo")) { Session.undoCommand(s, redo: false) }
                .keyboardShortcut("z")
            Button(tr("Redo")) { Session.undoCommand(s, redo: true) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(after: .toolbar) {
            Button("Luminance (luxmeter)") { LuminanceWindow.toggle(s) }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(s.appPrefs.luxPort.isEmpty)
            Divider()
        }
        CommandGroup(replacing: .printItem) {
            Button("Page Setup…") { Session.pageSetup() }
            Button("Print…") { Report.printReport(s) }
                .keyboardShortcut("p")
                .disabled(!s.hasMeasurements)
        }
    }
}

/// Function keys as menu shortcuts (HCFR for Windows' F2–F8).
enum FKey {
    static func key(_ code: Int) -> KeyEquivalent { KeyEquivalent(Character(UnicodeScalar(UInt32(code))!)) }
    static let f2 = key(NSF2FunctionKey), f3 = key(NSF3FunctionKey), f4 = key(NSF4FunctionKey)
    static let f5 = key(NSF5FunctionKey), f7 = key(NSF7FunctionKey), f8 = key(NSF8FunctionKey)
}
