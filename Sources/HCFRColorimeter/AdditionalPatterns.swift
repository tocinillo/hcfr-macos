// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Additional Patterns window added in 2026 after HCFR for Windows' Advanced → Patterns… dialog
// (PatternDisplay.cpp) and its drawing (Generators/FullScreenWindow.cpp OnPaint), GNU GPL.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import SwiftUI

/// A pattern of HCFR's "Select Pattern" dialog.
enum ExtraPattern: Equatable {
    /// Full field color (0…100 % per channel).
    case solid([Double])
    /// "Black +": a gray field changed one video step at a time with + / −.
    case blackPlus
    /// Dots of a color every N pixels (+ / − change N).
    case dots([Double])
    /// Horizontal or vertical lines (+ / − change the color).
    case lines(vertical: Bool)
    /// Shadings: 0 = B&W, 1 red, 2 green, 3 blue, 4 all colors, 8 black level test, 9 white level test.
    case shading(Int)
    /// Eight color bars (black, red, green, yellow, blue, magenta, cyan, white).
    case colorBars
    /// Red, green and blue crosses (convergence grid).
    case convergence
    /// Circles and grid (geometry).
    case geometry
    /// A set of pictures, changed with + / −.
    case pictures(PictureSet)
}

/// HCFR's picture sets of the dialog (CHCFR21_PATTERNS.dll resources), in Resources/Patterns/extra.
enum PictureSet: String, CaseIterable, Identifiable {
    case grid16 = "Grid Analysis"
    case testBench = "Test Picture bench"
    case iris = "Iris & Definition"
    case ansi1 = "Contrast ANSI 1"
    case ansi2 = "Contrast ANSI 2"
    case boxes = "Contrast boxes"
    var id: String { rawValue }

    /// File names and whether HCFR stretches them to the screen.
    var files: [(String, Bool)] {
        switch self {
        case .grid16: return (1...11).map { (String(format: "extra/16x16-%02d.png", $0), false) }
        case .testBench: return (1...20).map { (String(format: "extra/testbench-%02d.png", $0), $0 <= 16) }
        case .iris: return [("extra/720-1.png", false), ("extra/720-2.png", true), ("extra/720-3.png", true), ("extra/720-4.png", true)]
        case .ansi1, .ansi2:
            let n = self == .ansi1 ? 1 : 2
            return ["00-2", "00-5", "01", "02", "05", "10", "20", "30", "40", "50"].map { ("extra/ansi\(n)-\($0).png", true) }
        case .boxes: return ["01", "02", "05", "10", "20", "30", "40", "50"].map { ("extra/box-\($0).png", true) }
        }
    }
}

/// State of the Additional Patterns window and of the pattern shown.
@MainActor
final class ExtraPatternState: ObservableObject {
    @Published var pattern: ExtraPattern?
    /// Number of pads / dots across the screen (HCFR's m_nPads, 2…70).
    @Published var pads = 25
    /// HCFR's "Dot2": 2-pixel dots and lines, and one-way shadings.
    @Published var thick = false
    /// "Black +" level (0…100 %) and line color index.
    @Published var level = 0.0
    @Published var lineColor = 0
    @Published var pictureIndex = 0
    var keyMonitor: Any?
}

extension Session {
    /// Advanced → Patterns…: shows (or redraws) a pattern of the Additional Patterns window.
    func showExtraPattern(_ p: ExtraPattern) {
        guard activity == .idle else { return }
        guard let screen = patternScreen else {
            errorMessage = "The additional patterns are shown on a display of this Mac: choose it in Generator."
            return
        }
        let st = extraPatterns
        if st.pattern != p {
            st.pattern = p
            st.pictureIndex = 0
            if case .blackPlus = p { st.level = 0 }
            st.lineColor = 0
        }
        let code = { (v: Double) in self.videoLevels.code(min(max(v, 0), 100) / 100) }
        let black = code(0)
        let scale = screen.backingScaleFactor
        switch p {
        case .solid(let c):
            patternWindow.show(rgb: c.map(code), background: [black, black, black], areaPercent: 100, on: screen)
        case .blackPlus:
            let v = code(st.level)
            patternWindow.show(rgb: [v, v, v], background: [black, black, black], areaPercent: 100, on: screen)
        case .pictures(let set):
            let files = set.files
            let (file, stretch) = files[min(st.pictureIndex, files.count - 1)]
            guard let url = TestImages.folder?.appendingPathComponent(file),
                  patternWindow.showImage(url, videoLevels: videoLevels == .video, native: !stretch, on: screen) else {
                errorMessage = "The pattern image \(file) was not found. Rebuild the app with build-app.sh."
                return
            }
        default:
            let pads = st.pads, thick = st.thick, lineColor = st.lineColor
            let white = code(100)
            patternWindow.showDrawn(background: [black, black, black], on: screen) { rect, color in
                ExtraPatternDrawing.draw(p, in: rect, pixel: 1 / scale, pads: pads, thick: thick, lineColor: lineColor,
                                         black: black, white: white, code: code, color: color)
            }
        }
        testPatternShown = tr("Additional pattern")
        status = tr("Pattern: ") + tr(Self.extraName(p)) + " — " + tr("+ / − change it, * resets it, ESC closes")
        installExtraKeys()
    }

    static func extraName(_ p: ExtraPattern) -> String {
        switch p {
        case .solid: return "Color"
        case .blackPlus: return "Black +"
        case .dots: return "Dot pattern"
        case .lines(let v): return v ? "Vertical lines" : "Horizontal lines"
        case .shading(let k): return [0: "B&W", 1: "Red Shading", 2: "Green Shading", 3: "Blue Shading", 4: "All colors Shading",
                                      8: "Black level test", 9: "White level test"][k] ?? "Shading"
        case .colorBars: return "Color bars"
        case .convergence: return "Convergence Grid"
        case .geometry: return "Geometry"
        case .pictures(let s): return s.rawValue
        }
    }

    /// + / PageUp, − / PageDown, * / Home and Space while an additional pattern is shown (HCFR's keys).
    private func installExtraKeys() {
        guard extraPatterns.keyMonitor == nil else { return }
        extraPatterns.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let p = self.extraPatterns.pattern, self.testPatternShown != nil else { return e }
            let st = self.extraPatterns
            let ch = e.charactersIgnoringModifiers ?? ""
            var up = false, down = false, home = false
            switch e.keyCode {
            case 116: up = true            // page up
            case 121: down = true          // page down
            case 115: home = true          // home
            case 53: self.hideTestPattern(); return nil
            default:
                if ch == "+" || ch == "=" { up = true } else if ch == "-" { down = true }
                else if ch == "*" { home = true }
                else if ch == " " { st.thick.toggle(); self.showExtraPattern(p); return nil }
                else { return e }
            }
            switch p {
            case .blackPlus:
                let step = 100.0 / 219
                if up { st.level = min(100, st.level + step) }
                if down { st.level = max(0, st.level - step) }
                if home { st.level = 50 }
            case .lines:
                if up { st.lineColor = (st.lineColor + 1) % 4 }
                if down { st.lineColor = (st.lineColor + 3) % 4 }
                if home { st.lineColor = 0 }
            case .pictures(let set):
                if up { st.pictureIndex = min(set.files.count - 1, st.pictureIndex + 1) }
                if down { st.pictureIndex = max(0, st.pictureIndex - 1) }
                if home { st.pictureIndex = 0 }
            case .dots, .shading, .convergence, .geometry:
                if up { st.pads = min(70, st.pads + 1) }
                if down { st.pads = max(2, st.pads - 1) }
                if home { st.pads = 25 }
            default: return e
            }
            self.showExtraPattern(p)
            return nil
        }
    }

    func removeExtraKeys() {
        if let m = extraPatterns.keyMonitor { NSEvent.removeMonitor(m) }
        extraPatterns.keyMonitor = nil
        extraPatterns.pattern = nil
    }
}

/// The drawing of HCFR's FullScreenWindow for these patterns (in points; `pixel` = one screen pixel).
enum ExtraPatternDrawing {
    static func draw(_ p: ExtraPattern, in r: NSRect, pixel px: CGFloat, pads: Int, thick: Bool, lineColor: Int,
                     black: Int, white: Int, code: (Double) -> Int, color: ([Int]) -> NSColor) {
        // AppKit has y up: HCFR's coordinates (y down) are flipped when filling
        func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: [Int]) {
            color(c).setFill()
            NSRect(x: r.minX + x, y: r.maxY - y - h, width: w, height: h).fill()
        }
        let W = r.width, H = r.height
        let n = CGFloat(max(pads, 2))
        let pSize = (thick ? 2 : 1) * px
        func rgb(_ c: [Double]) -> [Int] { c.map { code($0) } }
        switch p {
        case .dots(let c):
            let stepX = W / n, stepY = H / n
            var x: CGFloat = 0
            while x < W { var y: CGFloat = 0; while y < H { fill(x, y, pSize, pSize, rgb(c)); y += stepY }; x += stepX }
        case .lines(let vertical):
            let c = [[100.0, 100, 100], [100, 0, 0], [0, 100, 0], [0, 0, 100]][lineColor % 4]
            if vertical {
                var x: CGFloat = 0
                while x < W { fill(x, 0, pSize, H, rgb(c)); x += pSize * 2 }
            } else {
                var y: CGFloat = 0
                while y < H { fill(0, y, W, pSize, rgb(c)); y += pSize * 2 }
            }
        case .shading(let k):
            var maxLevel = 255.0, start = 0.0
            if k == 8 { maxLevel = 30; start = 0 } else if k == 9 { maxLevel = 30; start = 255 - 30 }
            let count = max(pads, 2)
            let stepX = W / CGFloat(count)
            let limitY = thick ? H : H / 2
            let third = limitY / 3
            func level(_ i: Int) -> Double { start + Double(i) * maxLevel / Double(count - 1) }
            func codeOf(_ v: Double) -> Int {
                // HCFR's 0–255 shading values, mapped to the output levels
                code(v / 255 * 100)
            }
            func column(_ i: Int, _ v: Double, top: CGFloat, height: CGFloat) {
                let c = codeOf(v)
                switch k {
                case 1: fill(CGFloat(i) * stepX, top, stepX, height, [c, black, black])
                case 2: fill(CGFloat(i) * stepX, top, stepX, height, [black, c, black])
                case 3: fill(CGFloat(i) * stepX, top, stepX, height, [black, black, c])
                case 4:
                    let h3 = height / 3
                    fill(CGFloat(i) * stepX, top, stepX, h3, [c, black, black])
                    fill(CGFloat(i) * stepX, top + h3, stepX, h3, [black, c, black])
                    fill(CGFloat(i) * stepX, top + 2 * h3, stepX, height - 2 * h3, [black, black, c])
                default: fill(CGFloat(i) * stepX, top, stepX, height, [c, c, c])
                }
            }
            _ = third
            for i in 0..<count {
                column(i, level(i), top: 0, height: limitY)
                if !thick { column(i, level(count - 1 - i), top: limitY, height: H - limitY) }
            }
        case .colorBars:
            let bars: [[Double]] = [[0, 0, 0], [100, 0, 0], [0, 100, 0], [100, 100, 0], [0, 0, 100], [100, 0, 100], [0, 100, 100], [100, 100, 100]]
            let w = W / 8
            for (i, c) in bars.enumerated() { fill(CGFloat(i) * w, 0, w, H, rgb(c)) }
        case .convergence:
            let stepX = W / n, stepY = H / n
            let sets: [[[Double]]] = [[[100, 0, 0], [0, 100, 0], [0, 0, 100]], [[0, 100, 0], [0, 0, 100], [100, 0, 0]], [[0, 0, 100], [100, 0, 0], [0, 100, 0]]]
            var orbY: CGFloat = 0
            for l in 0..<3 {
                var i: CGFloat = 0
                while i < W {
                    for (k, c) in sets[l].enumerated() {
                        var j: CGFloat = 0
                        let cx = CGFloat(k * 2) * stepX + i
                        while j < H {
                            fill(cx - stepX, orbY + j, stepX * 2 + px, px, rgb(c))
                            fill(cx, orbY + j - stepY, px, stepY * 2 + px, rgb(c))
                            j += stepY * 6
                        }
                    }
                    i += stepX * 6
                }
                orbY += 2 * stepY
            }
        case .geometry:
            let stepY = H / n
            let ratio = W / H
            let w = [white, white, white]
            let half = min((sqrt(W * W + H * H) / 2 - H / 2 - px) / 2.37 - px, H / 4 - px)
            color(w).setStroke()
            func ellipse(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
                let path = NSBezierPath(ovalIn: NSRect(x: r.minX + x0, y: r.maxY - y1, width: x1 - x0, height: y1 - y0))
                path.lineWidth = px
                path.stroke()
            }
            ellipse(half, 0, W - half, H)
            ellipse(0, 0, half * 2, half * 2)
            ellipse(0, H - half * 2, half * 2, H)
            ellipse(W - half * 2, 0, W, half * 2)
            ellipse(W - half * 2, H - half * 2, W, H)
            ellipse((W - H) / 2, 0, (W + H) / 2, H)
            let stepX = stepY * ratio
            let offset = W.truncatingRemainder(dividingBy: stepY) / 2
            var x = offset
            while x < W - px { fill(x, 0, px, H, w); x += stepX }
            var y: CGFloat = 0
            while y < H - px { fill(0, y, W, px, w); y += stepY }
        default:
            break
        }
    }
}

/// The Additional Patterns window (a floating panel, so the main window stays usable).
@MainActor
enum AdditionalPatternsPanel {
    private static var panel: NSPanel?
    private static weak var owner: Session?

    static func show(_ session: Session) {
        if let panel, owner === session { panel.makeKeyAndOrderFront(nil); return }
        panel?.close()
        owner = session
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                        styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        p.title = tr("Additional Patterns")
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: AdditionalPatternsView(session: session, st: session.extraPatterns) { p.close() })
        p.setContentSize(p.contentView?.fittingSize ?? p.frame.size)
        p.center()
        p.makeKeyAndOrderFront(nil)
        panel = p
    }
}

/// Advanced → Patterns…: HCFR's "Select Pattern" dialog.
struct AdditionalPatternsView: View {
    @ObservedObject var session: Session
    @ObservedObject var st: ExtraPatternState
    var close: () -> Void

    private func button(_ title: String, _ p: ExtraPattern) -> some View {
        Button(tr(title)) { session.showExtraPattern(p) }.frame(maxWidth: .infinity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Additional Patterns").font(.title3.bold())
            GroupBox("Colors") {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        button("Black", .solid([0, 0, 0])); button("Gray", .solid([50, 50, 50])); button("White", .solid([100, 100, 100]))
                    }
                    GridRow {
                        button("Red", .solid([100, 0, 0])); button("Green", .solid([0, 100, 0])); button("Blue", .solid([0, 0, 100]))
                    }
                    GridRow {
                        button("Cyan", .solid([0, 100, 100])); button("Magenta", .solid([100, 0, 100])); button("Yellow", .solid([100, 100, 0]))
                    }
                    GridRow {
                        button("Black +", .blackPlus); button("Color", .colorBars); Color.clear.frame(height: 1)
                    }
                }
            }
            GroupBox("Tools") {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow { button("Black level test", .shading(8)); button("White level test", .shading(9)); button("B&W", .shading(0)) }
                    GridRow { button("Red Shading", .shading(1)); button("Green Shading", .shading(2)); button("Blue Shading", .shading(3)) }
                    GridRow { button("All colors Shading", .shading(4)); Color.clear.frame(height: 1); Color.clear.frame(height: 1) }
                }
            }
            GroupBox("Geometry") {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow { button("Horizontal lines", .lines(vertical: false)); button("Vertical lines", .lines(vertical: true)); button("Convergence Grid", .convergence) }
                    GridRow { button("White Dot Pattern", .dots([100, 100, 100])); button("Red Dot Pattern", .dots([100, 0, 0])); button("Green Dot Pattern", .dots([0, 100, 0])) }
                    GridRow { button("Blue Dot Pattern", .dots([0, 0, 100])); button("Geometry", .geometry); Color.clear.frame(height: 1) }
                }
                Toggle("Thick dots and lines (2 pixels)", isOn: $st.thick).padding(.top, 4)
            }
            GroupBox("Pictures, Iris & Definition") {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow { button("Grid Analysis", .pictures(.grid16)); button("Test Picture", .pictures(.testBench)); button("Iris & Definition", .pictures(.iris)) }
                    GridRow { button("Ansi 1", .pictures(.ansi1)); button("Ansi 2", .pictures(.ansi2)); button("Boxes", .pictures(.boxes)) }
                    GridRow {
                        Button("EIA 1956") { if let t = TestImages.find("1956.png") { session.showTestImage(t) } }.frame(maxWidth: .infinity)
                        Button("SMPTE 75%") { if let t = TestImages.find("smpte-75-bars1024.png") { session.showTestImage(t) } }.frame(maxWidth: .infinity)
                        Button(tr("Calibration picture")) { if let t = TestImages.find("calpic.png") { session.showTestImage(t) } }.frame(maxWidth: .infinity)
                    }
                }
            }
            Text("+ / − (or Page Up / Down) change the level, the number of dots or the picture; * (or Home) goes back to the default; Space switches thin / thick; ESC closes the pattern.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Hide pattern") { session.hideTestPattern() }.disabled(session.testPatternShown == nil)
                Spacer()
                Button("Close") { close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onChange(of: st.thick) { if let p = st.pattern, session.testPatternShown != nil { session.showExtraPattern(p) } }
    }
}
