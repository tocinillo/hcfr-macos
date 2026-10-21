// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import Combine
import SwiftUI

/// Shows the session's prompts ("Use 30 IRE…", calibration, position…) in a movable panel that
/// floats above every window, including the measurement window, like HCFR for Windows' message
/// boxes. (A sheet stayed attached to the main window, behind the measurement window.)
@MainActor
final class PromptPanelController {
    private var panel: NSPanel?
    private var shownID: UUID?
    private var subscription: AnyCancellable?
    private weak var session: Session?

    init(session: Session) {
        self.session = session
        subscription = session.$prompt
            .receive(on: RunLoop.main)
            .sink { [weak self] prompt in self?.update(prompt) }
    }

    private func update(_ prompt: UserPrompt?) {
        guard let prompt, let session else {
            close()
            return
        }
        guard prompt.id != shownID else { return }
        close()
        let host = NSHostingController(rootView: PromptSheet(prompt: prompt, session: session))
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
                        styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        p.contentViewController = host
        p.title = prompt.title
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        // Above the measurement window (.floating) but below full-screen patterns (.screenSaver)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.setContentSize(host.view.fittingSize)
        // Centered on the main window
        if let main = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0 !== p }) {
            let f = main.frame, s = p.frame.size
            p.setFrameOrigin(NSPoint(x: f.midX - s.width / 2, y: f.midY - s.height / 2))
        } else {
            p.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
        shownID = prompt.id
        session.promptDidAppear(prompt.id)
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        shownID = nil
    }
}
