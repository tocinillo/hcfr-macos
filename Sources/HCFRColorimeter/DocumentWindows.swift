// HCFR Colorimeter for macOS
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
    var token = UUID()
}

/// Another project window, with its own measurements, generator and (if connected) meter.
struct DocumentWindow: View {
    let request: DocumentRequest?
    @StateObject private var session = Session()

    var body: some View {
        ContentView(session: session, autoConnect: false)
            .frame(minWidth: 1180, minHeight: 680)
            .onAppear {
                guard let r = request, let p = r.path else { return }
                let url = URL(fileURLWithPath: p)
                session.openProject(url)
                if r.isCopy {
                    try? FileManager.default.removeItem(at: url)
                    session.projectURL = nil
                    session.isDirty = true
                    session.status = "Copy of the project — it is saved as a new file"
                }
            }
    }
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
            Button("Open Project in New Window…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.hcfrProject, .json]
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
            Divider()
        }
    }
}
