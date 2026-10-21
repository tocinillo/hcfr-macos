// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Test patterns added in 2026 after HCFR for Windows' Advanced → Targets\Images\Patterns menu and
// its pattern images (res/patterns, Generators/FullScreenWindow.cpp), GNU GPL.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import UniformTypeIdentifiers

/// A pattern image of HCFR (file in Resources/Patterns; PGenerator keeps the same files in images-HCFR).
struct TestImage: Identifiable, Hashable {
    let title: String
    let file: String
    /// HCFR's 16-235 version of the image, used on the Raspberry Pi with video levels.
    var videoFile: String?
    var id: String { file }
}

/// HCFR's Patterns menu, by group.
enum TestImages {
    static let groups: [(String, [TestImage])] = [
        ("Levels", [
            TestImage(title: "Shadow clipping", file: "clipl.png"),
            TestImage(title: "Highlight clipping", file: "cliph.png"),
            TestImage(title: "Near Black", file: "NBsdr.png", videoFile: "NBsdrv.png"),
        ]),
        ("Focus & Resolution", [
            TestImage(title: "Alignment & Convergence", file: "align.png"),
            TestImage(title: "Alignment & Uniformity", file: "Align2.png"),
            TestImage(title: "IMATEST", file: "sharp.png", videoFile: "sharpv.png"),
            TestImage(title: "ISO 12233:2000", file: "iso12233.png"),
            TestImage(title: "Belle Nuit", file: "bellenuit.png"),
            TestImage(title: "BBC HD Test Card", file: "BBCHD.png"),
            TestImage(title: "Phillips PM5644", file: "PM5644.png"),
            TestImage(title: "SMPTE RP-133", file: "VSMPTE133b.png"),
            TestImage(title: "Zone Plate [linear]", file: "zoneplate.png"),
        ]),
        ("Gradients & Ramps", [
            TestImage(title: "Neutral Gradient", file: "gradient.png"),
            TestImage(title: "Opposing Neutral Gradients", file: "gradient2.png"),
            TestImage(title: "RGBYCMW Luma Ramps [Shades]", file: "lramp.png"),
            TestImage(title: "RGBYCM Saturation Ramps [Tints]", file: "sramp.png", videoFile: "srampv.png"),
            TestImage(title: "Spectrum [light/full/dark]", file: "spectrum.png"),
            TestImage(title: "Chroma-gray Circles", file: "ERAMP.png", videoFile: "ERAMPv.png"),
            TestImage(title: "SMPTE 75% Bars", file: "smpte-75-bars1024.png"),
        ]),
        ("Cross Gradients", [
            TestImage(title: "Full Set [light]", file: "crossl.png", videoFile: "crosslv.png"),
            TestImage(title: "Full Set [dark]", file: "crossd.png", videoFile: "crossdv.png"),
            TestImage(title: "Red/Green Cross Gradient", file: "rgramp.png", videoFile: "rgrampv.png"),
            TestImage(title: "Red/Blue Cross Gradient", file: "rbramp.png", videoFile: "rbrampv.png"),
            TestImage(title: "Green/Blue Cross Gradient", file: "gbramp.png", videoFile: "gbrampv.png"),
            TestImage(title: "Red/Green [dark] Cross Gradient", file: "rgramp_d2.png"),
            TestImage(title: "Red/Blue [dark] Cross Gradient", file: "rbramp_d2.png"),
            TestImage(title: "Green/Blue [dark] Cross Gradient", file: "gbramp_d2.png"),
            TestImage(title: "Granger Rainbow [HSL]", file: "granger.png", videoFile: "grangerv.png"),
        ]),
        ("Evaluation Images", [
            TestImage(title: "Red", file: "timecode0.png", videoFile: "timecode0v.png"),
            TestImage(title: "Green", file: "timecode1.png", videoFile: "timecode1v.png"),
            TestImage(title: "Blue", file: "timecode2.png", videoFile: "timecode2v.png"),
            TestImage(title: "Yellow", file: "timecode3.png", videoFile: "timecode3v.png"),
            TestImage(title: "Cyan", file: "timecode4.png", videoFile: "timecode4v.png"),
            TestImage(title: "Magenta", file: "timecode5.png", videoFile: "timecode5v.png"),
            TestImage(title: "Skintones", file: "skintonep.png", videoFile: "skintonev.png"),
            TestImage(title: "High key", file: "dynamicp.png", videoFile: "dynamicv.png"),
            TestImage(title: "Full range", file: "dynamic1p.png", videoFile: "dynamic1v.png"),
            TestImage(title: "Low key", file: "bkp.png", videoFile: "bkv.png"),
            TestImage(title: "Calibration picture", file: "calpic.png", videoFile: "calpicv.png"),
            TestImage(title: "1956 test card", file: "1956.png"),
        ]),
        ("Black & White", [
            TestImage(title: "Gray World", file: "bw1.jpg", videoFile: "bw1v.jpg"),
            TestImage(title: "Shadows", file: "bw2.png", videoFile: "bw2v.png"),
        ]),
        ("Contrast", [
            TestImage(title: "ANSI contrast 1 (black center)", file: "ansi1.png"),
            TestImage(title: "ANSI contrast 2 (white center)", file: "ansi2.png"),
        ]),
    ]

    /// Folder of the pattern images: the app's Resources, or <repo>/Resources while developing.
    static var folder: URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent("Patterns")) }
        if let exe = Bundle.main.executableURL {
            candidates.append(exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/Patterns"))
        }
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }
}

extension Session {
    /// Shows a pattern image on the generator (HCFR's Patterns menu) until "Hide pattern" or ESC.
    func showTestImage(_ t: TestImage) {
        guard activity == .idle else { return }
        if patternSource == .raspberryPi {
            let file = videoLevels == .video ? (t.videoFile ?? t.file) : t.file
            Task {
                do {
                    try await piSend { "RGB=IMAGE;\($0.width),\($0.height),;100;255,255,255;0,0,0;-1,-1;/var/lib/PGenerator/images-HCFR/\(file)" }
                    testPatternShown = t.title
                    status = "Pattern on the Raspberry Pi: \(t.title) (PGenerator's images-HCFR/\(file))"
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            return
        }
        guard let screen = patternScreen else {
            errorMessage = "Test patterns need a pattern generator: choose a display of this Mac or the Raspberry Pi in Generator."
            return
        }
        guard let url = TestImages.folder?.appendingPathComponent(t.file),
              patternWindow.showImage(url, videoLevels: videoLevels == .video, on: screen) else {
            errorMessage = "The pattern image \(t.file) was not found. Rebuild the app with build-app.sh."
            return
        }
        testPatternShown = t.title
        status = "Pattern: \(t.title) — ESC or Patterns → Hide pattern to close"
    }

    /// HCFR's Patterns → Evaluation Images → User Defined (User1…User6): images of the user's own.
    func userPatternPath(_ n: Int) -> String? {
        let p = defaults.string(forKey: "userPattern\(n)")
        return p.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    }

    func chooseUserPattern(_ n: Int) {
        let panel = NSOpenPanel()
        panel.title = tr("Image for User") + " \(n)"
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaults.set(url.path, forKey: "userPattern\(n)")
        objectWillChange.send()
        showUserPattern(n)
    }

    func showUserPattern(_ n: Int) {
        guard activity == .idle else { return }
        guard let path = userPatternPath(n) else { chooseUserPattern(n); return }
        guard let screen = patternScreen else {
            errorMessage = "User images are shown on a display of this Mac: choose it in Generator."
            return
        }
        let url = URL(fileURLWithPath: path)
        guard patternWindow.showImage(url, videoLevels: videoLevels == .video, on: screen) else {
            errorMessage = "The image \(url.lastPathComponent) could not be opened."
            return
        }
        testPatternShown = "User\(n)"
        status = "Pattern: User\(n) (\(url.lastPathComponent)) — ESC or Patterns → Hide pattern to close"
    }

    /// HCFR's "Black +1% & +2% moving bars" / "White −1% & −2% moving bars".
    func showMovingBars(white: Bool) {
        guard activity == .idle else { return }
        guard let screen = patternScreen else {
            errorMessage = "The moving bars are shown on a display of this Mac (choose it in Generator). HCFR does not show them on a Raspberry Pi either."
            return
        }
        let lv = white ? [100.0, 99, 98] : [0.0, 1, 2]
        let codes = lv.map { l -> [Int] in let c = videoLevels.code(Reference.grayProp(l)); return [c, c, c] }
        patternWindow.showMovingBars(background: codes[0], bars: [codes[1], codes[2]], on: screen)
        testPatternShown = white ? "White −1% & −2% moving bars" : "Black +1% & +2% moving bars"
        status = "Pattern: \(testPatternShown!) — ESC or Patterns → Hide pattern to close"
    }

    /// HCFR's "Test colors" window: any color on the generator, to look at or adjust.
    func showTestColor(_ rgb: [Double]) {
        guard activity == .idle else { return }
        let codes = rgb.map { videoLevels.code(min(max($0, 0), 1)) }
        let black = videoLevels.code(0)
        if patternSource == .raspberryPi {
            let area = patternArea
            Task {
                do {
                    try await piSend { $0.rectangleMessage(rgb: codes, background: [black, black, black], areaPercent: area) }
                    testPatternShown = "Color \(codes)"
                } catch { errorMessage = error.localizedDescription }
            }
            return
        }
        guard let screen = patternScreen else {
            errorMessage = "Choose a display of this Mac or the Raspberry Pi in Generator to show a color."
            return
        }
        patternWindow.show(rgb: codes, background: [black, black, black], areaPercent: patternArea, on: screen)
        testPatternShown = "Color \(codes[0]),\(codes[1]),\(codes[2])"
        status = "Showing \(testPatternShown!) — ESC or Patterns → Hide pattern to close"
    }

    func hideTestPattern() {
        guard testPatternShown != nil else { return }
        testPatternShown = nil
        patternWindow.close()
        if patternSource == .raspberryPi { Task { try? await piSend { _ in PGeneratorClient.idleMessage } } }
        shownPattern = nil
        status = "Pattern closed"
    }
}
