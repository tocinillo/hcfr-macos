// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit

/// A pattern to show (or ask for): a gray level in IRE or a 100% color patch.
enum TestPattern: Equatable {
    case gray(Double)
    case color(PatchColor)

    /// Text used in the "Use … and press Continue" message of the manual (DVD) generator.
    var manualName: String {
        switch self {
        case .gray(let level): return "\(Reference.label(level)) IRE"
        case .color(.white): return "100% White (100 IRE)"
        case .color(let p): return "100% \(p.rawValue)"
        }
    }

    /// Signal level (0…1) of each channel, before the video range is applied.
    var rgb: [Double] {
        switch self {
        case .gray(let level): return Array(repeating: Double(level) / 100, count: 3)
        case .color(let p): return p.rgb
        }
    }
}

/// Where patterns come from: the user's DVD / external generator, a display of this Mac, or a
/// Raspberry Pi running PGenerator on the network (as HCFR for Windows' "rPI" display mode).
enum PatternSource: Hashable {
    case manual
    case display(CGDirectDisplayID)
    case raspberryPi
}

/// Output levels of the built-in generator (as HCFR's GDI generator option).
enum VideoLevels: String, CaseIterable, Identifiable {
    case full = "PC levels (0–255)"
    case video = "Video levels (16–235)"
    var id: String { rawValue }

    /// 8-bit code for a signal level 0…1, rounded like HCFR's GDI generator.
    func code(_ v: Double) -> Int {
        switch self {
        case .full: return Int((v * 255).rounded())
        case .video: return Int((16 + v * 219).rounded())
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// Full-screen pattern window on the chosen display. Colors are drawn in the display's own color
/// space so macOS color management does not change the RGB values sent to the screen.
@MainActor
final class PatternWindowController {
    private final class PatternWindow: NSWindow {
        var onEscape: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
        }
    }

    private final class PatternView: NSView {
        var rgb: [Int] = [0, 0, 0] { didSet { needsDisplay = true } }
        /// Black around a window patch (16 with video levels).
        var background: [Int] = [0, 0, 0] { didSet { needsDisplay = true } }
        /// Share of the screen area covered by the patch (100 = full field), on black.
        var areaPercent: Double = 100 { didSet { needsDisplay = true } }

        override func draw(_ dirtyRect: NSRect) {
            let space = window?.screen?.colorSpace ?? .deviceRGB
            func color(_ c: [Int]) -> NSColor {
                NSColor(colorSpace: space, components: c.map { CGFloat($0) / 255 } + [1], count: 4)
            }
            color(background).setFill()
            bounds.fill()
            let k = sqrt(min(max(areaPercent, 1), 100) / 100)
            let w = bounds.width * k, h = bounds.height * k
            color(rgb).setFill()
            NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h).fill()
        }
    }

    /// Development check: draws a pattern off screen at 1x in device RGB (as the real window draws
    /// in the display's own color space, without conversion) and returns center and corner pixels.
    static func renderTest(rgb: [Int], areaPercent: Double) -> (center: [Int], corner: [Int]) {
        let size = NSSize(width: 200, height: 100)
        let v = PatternView(frame: NSRect(origin: .zero, size: size))
        v.rgb = rgb
        v.areaPercent = areaPercent
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        v.draw(v.bounds)
        NSGraphicsContext.restoreGraphicsState()
        func px(_ x: Int, _ y: Int) -> [Int] {
            var p = [Int](repeating: 0, count: 4)
            rep.getPixel(&p, atX: x, y: y)
            return Array(p.prefix(3))
        }
        return (px(100, 50), px(2, 2))
    }

    private var window: PatternWindow?
    private var view: PatternView?
    var onEscape: (() -> Void)?

    var isShowing: Bool { window != nil }
    var screen: NSScreen? { window?.screen }

    func show(rgb: [Int], background: [Int] = [0, 0, 0], areaPercent: Double, on screen: NSScreen) {
        if window == nil || window?.screen != screen {
            close()
            let w = PatternWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered,
                                  defer: false, screen: screen)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isReleasedWhenClosed = false
            w.colorSpace = screen.colorSpace
            w.backgroundColor = NSColor(colorSpace: screen.colorSpace ?? .deviceRGB,
                                        components: background.map { CGFloat($0) / 255 } + [1], count: 4)
            w.onEscape = { [weak self] in self?.onEscape?() }
            let v = PatternView(frame: NSRect(origin: .zero, size: screen.frame.size))
            w.contentView = v
            w.setFrame(screen.frame, display: true)
            // On the app's own screen the pattern covers the app: make it key so ESC stops
            if screen == NSApp.mainWindow?.screen { w.makeKeyAndOrderFront(nil) } else { w.orderFrontRegardless() }
            window = w
            view = v
        }
        view?.areaPercent = areaPercent
        view?.background = background
        view?.rgb = rgb
        view?.displayIfNeeded()
    }

    func close() {
        window?.orderOut(nil)
        window = nil
        view = nil
    }
}
