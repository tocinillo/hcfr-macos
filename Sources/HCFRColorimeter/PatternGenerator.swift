// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import ImageIO

/// A pattern to show (or ask for): a gray level in IRE or a 100% color patch.
enum TestPattern: Equatable {
    case gray(Double)
    case color(PatchColor)
    /// Any RGB signal (0…1 of the video range), with the text asked for with the manual generator.
    case custom([Double], String)
    /// HCFR's ANSI contrast checkerboard (5×5): `inverted` false = black square in the center
    /// ("Contrast ANSI 1"), true = white square in the center ("Contrast ANSI 2").
    case ansi(inverted: Bool)

    /// Text used in the "Use … and press Continue" message of the manual (DVD) generator.
    var manualName: String {
        switch self {
        case .gray(let level): return "\(Reference.label(level)) IRE"
        case .color(.white): return "100% White (100 IRE)"
        case .color(let p): return "100% \(p.rawValue)"
        case .custom(_, let name): return name
        case .ansi(let inverted):
            return inverted ? "the ANSI contrast pattern 2 (chapter 'Contrast ANSI 2', white square in the center)"
                            : "the ANSI contrast pattern 1 (chapter 'Contrast ANSI 1', black square in the center)"
        }
    }

    /// Signal level (0…1) of each channel, before the video range is applied.
    var rgb: [Double] {
        switch self {
        case .gray(let level): return Array(repeating: Reference.grayProp(level), count: 3)
        case .color(let p): return p.rgb
        case .custom(let rgb, _): return rgb
        case .ansi: return [0, 0, 0]
        }
    }

    var ansiInverted: Bool? {
        if case .ansi(let inverted) = self { return inverted }
        return nil
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
        /// ANSI checkerboard instead of a patch: `rgb` squares on `background` (nil = patch).
        var ansiInverted: Bool? { didSet { needsDisplay = true } }
        /// Test image (HCFR's Patterns menu), already in the display's color space, fitted on black.
        var image: CGImage? { didSet { needsDisplay = true } }
        /// HCFR's moving bars: `rgb` = background, `bars` = the two bar levels, `phase` = position 0…1.
        var bars: [[Int]]? { didSet { needsDisplay = true } }
        var phase: CGFloat = 0 { didSet { needsDisplay = true } }

        override func draw(_ dirtyRect: NSRect) {
            let space = window?.screen?.colorSpace ?? .deviceRGB
            func color(_ c: [Int]) -> NSColor {
                NSColor(colorSpace: space, components: c.map { CGFloat($0) / 255 } + [1], count: 4)
            }
            color(background).setFill()
            bounds.fill()
            if let image, let ctx = NSGraphicsContext.current?.cgContext {
                let iw = CGFloat(image.width), ih = CGFloat(image.height)
                let k = min(bounds.width / iw, bounds.height / ih)
                let r = CGRect(x: bounds.midX - iw * k / 2, y: bounds.midY - ih * k / 2, width: iw * k, height: ih * k)
                ctx.interpolationQuality = .high
                ctx.draw(image, in: r)
                return
            }
            if let bars {
                // Black +1% / +2% (or white −1% / −2%) bars moving across the screen
                color(rgb).setFill()
                bounds.fill()
                let bw = bounds.width / 10
                for (i, level) in bars.enumerated() {
                    let x = (phase + CGFloat(i) * 0.5).truncatingRemainder(dividingBy: 1) * (bounds.width + bw) - bw
                    color(level).setFill()
                    NSRect(x: x, y: 0, width: bw, height: bounds.height).fill()
                }
                return
            }
            if let inverted = ansiInverted {
                // HCFR's FullScreenWindow: 5×5 blocks, the center one black (ANSI 1) or white (ANSI 2)
                let n = 5, bw = bounds.width / CGFloat(n), bh = bounds.height / CGFloat(n)
                color(rgb).setFill()
                for row in 0..<n {
                    for col in 0..<n where ((row + col) & 1 == 1) != inverted {
                        NSRect(x: CGFloat(col) * bw, y: CGFloat(row) * bh, width: bw, height: bh).fill()
                    }
                }
                return
            }
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

    func show(rgb: [Int], background: [Int] = [0, 0, 0], areaPercent: Double, ansiInverted: Bool? = nil, on screen: NSScreen) {
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
        stopAnimation()
        view?.image = nil
        view?.bars = nil
        view?.areaPercent = areaPercent
        view?.ansiInverted = ansiInverted
        view?.background = background
        view?.rgb = rgb
        view?.displayIfNeeded()
    }

    private var timer: Timer?

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    /// Test image, full screen (aspect kept). `videoLevels` maps 0–255 to 16–235 as HCFR's "v" images.
    func showImage(_ url: URL, videoLevels: Bool, on screen: NSScreen) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
        let space = screen.colorSpace?.cgColorSpace ?? CGColorSpaceCreateDeviceRGB()
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        // Same codes on screen as in the file: reinterpret in the display's space instead of converting
        ctx.draw(img.copy(colorSpace: space) ?? img, in: CGRect(x: 0, y: 0, width: w, height: h))
        if videoLevels, let data = ctx.data {
            let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
            var lut = [UInt8](repeating: 0, count: 256)
            for i in 0..<256 { lut[i] = UInt8((16 + Double(i) * 219 / 255).rounded()) }
            for i in 0..<(w * h * 4) where i % 4 != 3 { p[i] = lut[Int(p[i])] }
        }
        guard let shown = ctx.makeImage() else { return false }
        let black = videoLevels ? 16 : 0
        show(rgb: [black, black, black], background: [black, black, black], areaPercent: 100, on: screen)
        view?.image = shown
        return true
    }

    /// HCFR's animated near black / near white bars.
    func showMovingBars(background: [Int], bars: [[Int]], on screen: NSScreen) {
        show(rgb: background, background: background, areaPercent: 100, on: screen)
        view?.bars = bars
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let v = self?.view else { return }
                v.phase = (v.phase + 0.004).truncatingRemainder(dividingBy: 1)
            }
        }
    }

    func close() {
        stopAnimation()
        window?.orderOut(nil)
        window = nil
        view = nil
    }
}
