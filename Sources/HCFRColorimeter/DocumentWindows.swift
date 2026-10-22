// HCFR for macOS
// Copyright (C) 2026 Jorge Velázquez
// Several projects open at once (HCFR for Windows' multiple documents, Window menu and
// File → Duplicate) added in 2026.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI

/// The project of the window in front, so the menus act on it.
struct ActiveSessionKey: FocusedValueKey {
    typealias Value = Session
}

extension FocusedValues {
    var activeSession: Session? {
        get { self[ActiveSessionKey.self] }
        set { self[ActiveSessionKey.self] = newValue }
    }
}

/// What a project window opens with: a file, a copy of another window's project (deleted after
/// reading), or nothing (a new, empty project).
struct DocumentRequest: Codable, Hashable {
    var path: String?
    var isCopy = false
    /// Table shown first (tab menu) and the tables a copy keeps (File → Duplicate…).
    var view: String? = nil
    var keep: [String]? = nil
    var token = UUID()
}

/// Another project window, with its own measurements, generator and (if connected) meter.
struct DocumentWindow: View {
    let request: DocumentRequest?
    @StateObject private var session = Session()

    var body: some View {
        ContentView(session: session, autoConnect: false)
            .frame(minWidth: 1180, minHeight: 680)
            .background(WindowTabber())
            .onAppear {
                if let (d, owner) = ProjectReference.current, owner !== session { session.refData = d }
                guard let r = request, let p = r.path else { return }
                let url = URL(fileURLWithPath: p)
                session.openProject(url)
                if let k = r.keep { session.keepOnly(k) }
                if let v = r.view.flatMap(MeasureView.init(rawValue:)) { session.view = v }
                if r.isCopy {
                    session.clearMeasureUndo()
                    try? FileManager.default.removeItem(at: url)
                    session.projectURL = nil
                    session.isDirty = true
                    session.status = "Copy of the project — it is saved as a new file"
                }
            }
    }
}

/// Projects as tabs of one window (as HCFR for Windows' document tabs): File → New Tab opens a
/// project window as a tab of the window in front; Window → Merge All Windows joins them.
enum ProjectTabs {
    static let identifier = "HCFRProject"
    /// The window the next project window goes into as a tab (File → New Tab).
    @MainActor static weak var pendingParent: NSWindow?

    @MainActor static func prepare(_ w: NSWindow) {
        w.tabbingIdentifier = identifier
        if w.tabbingMode == .disallowed { w.tabbingMode = .automatic }
    }
}

/// Makes the window of a project tab-capable and, after File → New Tab, puts it in the parent's tabs.
struct WindowTabber: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in
            guard let w = v?.window else { return }
            ProjectTabs.prepare(w)
            if let parent = ProjectTabs.pendingParent, parent !== w {
                ProjectTabs.pendingParent = nil
                parent.addTabbedWindow(w, ordered: .above)
                w.makeKeyAndOrderFront(nil)
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// File menu items for several windows.
struct DocumentCommands: Commands {
    let main: Session
    @FocusedValue(\.activeSession) private var focused
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Window") { openWindow(id: "document", value: DocumentRequest()) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("New Tab") {
                if let w = NSApp.keyWindow { ProjectTabs.prepare(w); ProjectTabs.pendingParent = w }
                openWindow(id: "document", value: DocumentRequest())
            }
            .keyboardShortcut("t")
            Button("Open Project in New Tab…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.hcfrProject, .hcfrWindows, .json]
                let parent = NSApp.keyWindow
                guard panel.runModal() == .OK, let url = panel.url else { return }
                if let parent { ProjectTabs.prepare(parent); ProjectTabs.pendingParent = parent }
                openWindow(id: "document", value: DocumentRequest(path: url.path))
            }
            Button("Open Project in New Window…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.hcfrProject, .hcfrWindows, .json]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                openWindow(id: "document", value: DocumentRequest(path: url.path))
            }
            Button("Duplicate Project") {
                let s = focused ?? main
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("HCFR copy \(UUID().uuidString).hcfrex")
                s.saveProject(copyTo: url)
                openWindow(id: "document", value: DocumentRequest(path: url.path, isCopy: true))
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Duplicate Project…") {
                let s = focused ?? main
                guard let keep = DuplicateData.choose(s) else { return }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("HCFR copy \(UUID().uuidString).hcfrex")
                s.saveProject(copyTo: url)
                openWindow(id: "document", value: DocumentRequest(path: url.path, isCopy: true, keep: keep))
            }
            Divider()
        }
    }
}
