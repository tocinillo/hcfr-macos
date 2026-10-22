// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Windows HCFR project files (.chc) added in 2026.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// HCFR for Windows' measures file ("ColorHCFR File (*.chc)").
    static let hcfrWindows = UTType(importedAs: "org.hcfr.windows.chc", conformingTo: .data)
}

enum ChcError: LocalizedError {
    case notHCFR, newerVersion(Int), truncated

    var errorDescription: String? {
        switch self {
        case .notHCFR: return "It is not an HCFR measures file (.chc)."
        case .newerVersion(let v): return "The file was saved by a newer HCFR (format \(v)) that this version cannot read."
        case .truncated: return "The file is incomplete or damaged."
        }
    }
}

/// HCFR for Windows' .chc file (an MFC archive, little endian), read and written as the Windows
/// program does (CDataSetDoc::Serialize, CMeasure::Serialize, CColor::Serialize, Matrix::Serialize).
///
/// Document: "COLORHCF" (two longs) · file format version · CMeasure · sensor object · generator
/// object · window positions (format 3). CMeasure 17: HDR / gamma / reference preferences, override
/// black, gray scale, near black, near white, six saturation scales, Color Checker (valid patches
/// with their index, then a marker color), the same for the master set, free measures, primaries,
/// secondaries, on/off and ANSI contrast, primary white, info text and IRE mode. A color is
/// version · XYZ matrix · two ignored 3×3 matrices · [spectrum] · [lux]; spectra and lux values
/// go both ways.
///
/// Written files carry a simulated sensor and the manual generator (the Windows program replaces
/// them by the ones you choose) and file format 2, without window positions.
enum ChcFile {
    static let noData = -99999.99
    private static let marker = (0.123, 0.456, 0.789)
    /// HCFR's ColorStandard and WhiteTarget numbers.
    static let standards: [ColorStandard] = [.palSecam, .sdtv, .hdtv, .hdtv75, .colorChecker, .sRGB, .uhdtvP3,
                                             .uhdtv2020, .uhdtvP3in2020, .uhdtv709in2020, .custom]
    static let whites: [Int: WhitePoint] = [0: .d65, 1: .d55, 2: .d50, 3: .d75, 4: .d93, 5: .a, 6: .b, 7: .c,
                                            8: .e, 9: .dci, 10: .custom]
    static let saturationViews: [MeasureView] = [.redSat, .greenSat, .blueSat, .yellowSat, .cyanSat, .magentaSat]
    static let maxUserCC = 10000

    // MARK: - Reading

    static func read(_ data: Data) throws -> ProjectFile {
        var r = Reader(data: [UInt8](data))
        guard try r.i32() == 0x4F4C_4F43, try r.i32() == 0x4643_4852 else { throw ChcError.notHCFR }
        let docVersion = Int(try r.i32())
        guard docVersion <= 3 else { throw ChcError.newerVersion(docVersion) }
        return try readMeasure(&r)
    }

    private static func readMeasure(_ r: inout Reader) throws -> ProjectFile {
        let v = Int(try r.i32())
        guard v <= 17 else { throw ChcError.newerVersion(v) }
        var p = ReferencePrefs()
        if v > 16 {
            p.blackSlope = try r.f64(); p.whiteSlope = try r.f64(); p.whiteSlopeStart = try r.f64()
        }
        if v > 15 { p.hlgSystemGamma = try r.f64() }
        if v > 14 {
            p.masterMinL = try r.f64(); p.masterMaxL = try r.f64()
            p.targetMinL = try r.f64(); p.targetMaxL = try r.f64()
            p.contentMaxL = try r.f64(); p.frameAvgMaxL = try r.f64()
            p.bt2390 = try r.bool(); p.overrideTargets = try r.bool()
            p.diffuseWhite = try r.f64()
        }
        if v > 13 { _ = try r.i32() }   // near white clipping column
        var standard = ColorStandard.hdtv, white = WhitePoint.d65, gamma = 2.2, ccMode: Int?
        if v > 11 {
            var n = [Int](repeating: 0, count: 8), d = [Double](repeating: 0, count: 11)
            for i in 0..<7 { n[i] = Int(try r.i32()) }
            for i in 0..<5 { d[i] = try r.f64() }
            n[7] = Int(try r.i32())
            for i in 5..<11 { d[i] = try r.f64() }
            white = whites[n[0]] ?? .d65
            ccMode = n[1]
            standard = standards.indices.contains(n[2]) ? standards[n[2]] : .hdtv
            p.deltaEFormula = n[3]; p.grayDeltaE = n[4]; p.deltaEWeight = n[5]; p.gammaMode = n[6]
            gamma = d[0]; p.gammaRel = d[1]; p.split = d[2]
            p.customWhiteX = d[3]; p.customWhiteY = d[4]
            p.useMeasuredGamma = n[7] != 0
            p.customBlueX = d[5]; p.customRedX = d[6]; p.customGreenX = d[7]
            p.customBlueY = d[8]; p.customRedY = d[9]; p.customGreenY = d[10]
        }
        var overrideBlack = false
        if v > 10 {
            overrideBlack = try r.bool()
            if let b = try r.color(nil) { p.manualBlack = b[1] }
        }
        // Gray scale
        let gsize = Int(try r.i32())
        let levels = Reference.levels(count: max(gsize, 2))
        var gray: [Int: [Double]] = [:]
        for i in 0..<gsize {
            if let c = try r.color(i < levels.count ? "gray:" + Session.levelKey(levels[i]) : nil) { gray[i] = c }
        }
        var series: [String: [String: [Double]]] = [:]
        var sizes: [String: Int] = [:]
        func readArray(_ view: MeasureView) throws -> Int {
            let n = Int(try r.i32())
            for i in 0..<n {
                if let c = try r.color("series:\(view.rawValue):\(i)") { series[view.rawValue, default: [:]]["\(i)"] = c }
            }
            return n
        }
        if v > 2 {
            sizes["Near black"] = try readArray(.nearBlack)
            sizes["Near white"] = try readArray(.nearWhite)
        }
        if v > 1 {
            for s in saturationViews { sizes["Saturations"] = try readArray(s) }
            if v >= 8 {
                try readCC(&r, version: v, view: .colorChecker, into: &series)
                if v >= 10 {
                    var ignored: [String: [String: [Double]]] = [:]
                    try readCC(&r, version: v, view: .colorChecker, keep: false, into: &ignored)   // master set
                }
            }
        }
        let freeCount = Int(try r.i32())
        var free: [[Double]] = []
        for _ in 0..<freeCount { if let c = try r.color("free:\(free.count)") { free.append(c) } }
        var colors: [String: [Double]] = [:]
        for patch in [PatchColor.red, .green, .blue, .yellow, .cyan, .magenta] {
            if let c = try r.color("patch:" + patch.rawValue) { colors[patch.rawValue] = c }
        }
        var contrast: [String: [Double]] = [:]
        for (i, item) in [ContrastPatch.black, .white, .ansi1, .ansi2].enumerated() {
            if let c = try r.color("contrast:\(i)") { contrast[item.rawValue] = c }
        }
        if v > 8, let c = try r.color("patch:White") { colors[PatchColor.white.rawValue] = c }
        // info text and IRE mode follow; not needed

        // Gray levels as this app keys them
        var measurements: [String: [Double]] = [:]
        for (i, c) in gray where i < levels.count { measurements[Session.levelKey(levels[i])] = c }
        var file = ProjectFile(standard: standard.rawValue, white: white.rawValue, gamma: gamma,
                               overrideBlack: overrideBlack, measurements: measurements)
        file.grayCount = max(gsize, 2)
        file.references = p
        file.colors = colors
        file.series = series
        file.scaleSizes = sizes
        file.colorChecker = ccMode
        file.freeMeasures = free.isEmpty ? nil : free
        file.contrast = contrast.isEmpty ? nil : contrast
        file.spectra = r.spectra.isEmpty ? nil : r.spectra
        file.lux = r.lux.isEmpty ? nil : r.lux
        return file
    }

    private static func readCC(_ r: inout Reader, version v: Int, view: MeasureView, keep: Bool = true,
                               into series: inout [String: [String: [Double]]]) throws {
        let size = Int(try r.i32())
        if v <= 12 {
            for i in 0..<size {
                if let c = try r.color(keep ? "series:\(view.rawValue):\(i)" : nil) { series[view.rawValue, default: [:]]["\(i)"] = c }
            }
            return
        }
        for _ in 0..<size {
            let c = try r.rawColor()
            if c[0] == marker.0 && c[1] == marker.1 && c[2] == marker.2 { break }
            let j = Int(try r.i32())
            if c[0] > -1, c[1] > -1, c[2] > -1 {
                series[view.rawValue, default: [:]]["\(j)"] = c
                if keep { r.keepExtras("series:\(view.rawValue):\(j)") }
            }
        }
    }

    // MARK: - Writing

    static func write(_ f: ProjectFile) -> Data {
        var w = Writer()
        w.i32(0x4F4C_4F43); w.i32(0x4643_4852)
        w.i32(2)   // file format 2: no window positions
        writeMeasure(&w, f)
        writeSimulatedSensor(&w)
        writeManualGenerator(&w)
        return Data(w.bytes)
    }

    private static func writeMeasure(_ w: inout Writer, _ f: ProjectFile) {
        let p = f.references ?? ReferencePrefs()
        w.i32(17)
        w.f64(p.blackSlope); w.f64(p.whiteSlope); w.f64(p.whiteSlopeStart)
        w.f64(p.hlgSystemGamma)
        w.f64(p.masterMinL); w.f64(p.masterMaxL); w.f64(p.targetMinL); w.f64(p.targetMaxL)
        w.f64(p.contentMaxL); w.f64(p.frameAvgMaxL)
        w.bool(p.bt2390); w.bool(p.overrideTargets)
        w.f64(p.diffuseWhite)
        w.i32(101)   // near white clipping column
        let whiteNo = whites.first { $0.value.rawValue == f.white }?.key ?? 0
        let standardNo = standards.firstIndex { $0.rawValue == f.standard } ?? 2
        w.i32(Int32(whiteNo)); w.i32(Int32(f.colorChecker ?? 0)); w.i32(Int32(standardNo))
        w.i32(Int32(p.deltaEFormula)); w.i32(Int32(p.grayDeltaE)); w.i32(Int32(p.deltaEWeight)); w.i32(Int32(p.gammaMode))
        w.f64(f.gamma); w.f64(p.gammaRel); w.f64(p.split); w.f64(p.customWhiteX); w.f64(p.customWhiteY)
        w.bool(p.useMeasuredGamma)
        w.f64(p.customBlueX); w.f64(p.customRedX); w.f64(p.customGreenX)
        w.f64(p.customBlueY); w.f64(p.customRedY); w.f64(p.customGreenY)
        w.bool(f.overrideBlack)
        w.color([0, p.manualBlack, 0])   // user black

        // Gray scale: one color per level, no data where not measured
        let n = max(f.grayCount ?? Reference.defaultGrayCount, 2)
        let levels = Reference.levels(count: n)
        var gray = [[Double]?](repeating: nil, count: n)
        for (k, v) in f.measurements where v.count == 3 {
            guard let level = Double(k), let i = levels.firstIndex(where: { abs($0 - level) < 1e-6 }) else { continue }
            gray[i] = v
        }
        let spectra = f.spectra ?? [:], lux = f.lux ?? [:]
        func put(_ xyz: [Double]?, _ key: String) { w.color(xyz, spectrum: spectra[key], lux: lux[key]) }
        w.i32(Int32(n))
        for (i, c) in gray.enumerated() { put(c, "gray:" + Session.levelKey(levels[i])) }

        let sizes = f.scaleSizes ?? [:]
        func array(_ view: MeasureView, _ size: Int) {
            let m = f.series?[view.rawValue] ?? [:]
            w.i32(Int32(size))
            for i in 0..<size { put(m["\(i)"], "series:\(view.rawValue):\(i)") }
        }
        array(.nearBlack, sizes["Near black"] ?? 5)
        array(.nearWhite, sizes["Near white"] ?? 5)
        for s in saturationViews { array(s, sizes["Saturations"] ?? 5) }

        // Color Checker: the measured patches with their index, then the marker color
        let cc = f.series?[MeasureView.colorChecker.rawValue] ?? [:]
        w.i32(Int32(maxUserCC))
        var patches: [(Int, [Double])] = []
        for (k, v) in cc { if let i = Int(k), v.count == 3 { patches.append((i, v)) } }
        for (i, v) in patches.sorted(by: { $0.0 < $1.0 }) {
            put(v, "series:\(MeasureView.colorChecker.rawValue):\(i)"); w.i32(Int32(i))
        }
        w.color([marker.0, marker.1, marker.2])
        w.i32(Int32(5 * maxUserCC))
        w.color([marker.0, marker.1, marker.2])

        let free = f.freeMeasures ?? []
        w.i32(Int32(free.count))
        for (i, c) in free.enumerated() { put(c, "free:\(i)") }
        let colors = f.colors ?? [:]
        for patch in [PatchColor.red, .green, .blue, .yellow, .cyan, .magenta] { put(colors[patch.rawValue], "patch:" + patch.rawValue) }
        // On/off black and white: HCFR for Windows takes the white of the gray scale (gamma, Y
        // targets, ΔE) from the on/off white, and sets both when it measures a gray scale (its 0 %
        // and 100 %, or the override black). Without them Windows shows no targets and wrong ΔE.
        var contrast = f.contrast ?? [:]
        if contrast[ContrastPatch.white.rawValue] == nil, let w = gray.last ?? nil { contrast[ContrastPatch.white.rawValue] = w }
        if contrast[ContrastPatch.black.rawValue] == nil {
            if f.overrideBlack { contrast[ContrastPatch.black.rawValue] = [0, p.manualBlack, 0] }
            else if let b = gray.first ?? nil { contrast[ContrastPatch.black.rawValue] = b }
        }
        for (i, item) in [ContrastPatch.black, .white, .ansi1, .ansi2].enumerated() { put(contrast[item.rawValue], "contrast:\(i)") }
        put(colors[PatchColor.white.rawValue], "patch:White")
        w.string("Calibration by: \r\nDisplay: \(f.display ?? "")\r\nNote: Saved by HCFR Colorimeter for macOS \(AboutPanel.version)\r\n")
        w.bool(false)   // IRE scale mode
    }

    /// CSimulatedSensor (CSensor → COneDeviceSensor → CSimulatedSensor), no errors simulated.
    private static func writeSimulatedSensor(_ w: inout Writer) {
        w.newClass("CSimulatedSensor")
        w.matrix(cols: 3, rows: 3, [1, 0, 0, 0, 1, 0, 0, 0, 1])   // sensor to XYZ matrix
        w.i32(1); w.i32(0)                                          // CSensor 1, calibration time (32-bit time_t)
        w.i32(3)                                                    // COneDeviceSensor 3, no calibration info
        w.f32(100); w.bool(false); w.bool(false); w.bool(false); w.i32(15)
        w.matrix(cols: 3, rows: 3, [0.64, 0.33, 0.03, 0.30, 0.60, 0.10, 0.15, 0.06, 0.79])
        w.matrix(cols: 1, rows: 3, [0.3127, 0.3290, 0.3583])
        w.string(""); w.string("")
        w.i32(2)                                                    // CSimulatedSensor 2
        w.f64(0); w.i32(0); w.i32(0); w.i32(0)
        w.bool(false); w.bool(false); w.f64(0); w.bool(false); w.f64(0)
    }

    /// CManualDVDGenerator (CGenerator's data only).
    private static func writeManualGenerator(_ w: inout Writer) {
        w.newClass("CManualDVDGenerator")
        w.i32(6)
        w.bool(false); w.bool(true); w.bool(false); w.bool(false); w.bool(false); w.bool(false)
    }

    // MARK: - MFC archive primitives

    struct Reader {
        let data: [UInt8]
        var pos = 0
        /// Spectra and lux values of the colors read, by this app's column keys ("gray:50"…).
        var spectra: [String: Spectrum] = [:]
        var lux: [String: Double] = [:]
        private var lastSpectrum: Spectrum?
        private var lastLux: Double?

        init(data: [UInt8]) { self.data = data }

        mutating func keepExtras(_ key: String) {
            if let s = lastSpectrum { spectra[key] = s }
            if let l = lastLux { lux[key] = l }
        }

        mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
            guard n >= 0, pos + n <= data.count else { throw ChcError.truncated }
            defer { pos += n }
            return data[pos ..< pos + n]
        }
        mutating func u32() throws -> UInt32 {
            try take(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }
        mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
        mutating func bool() throws -> Bool { try i32() != 0 }
        mutating func f64() throws -> Double {
            Double(bitPattern: try take(8).reversed().reduce(0) { $0 << 8 | UInt64($1) })
        }
        /// Matrix::Serialize: "CMatrixC" header, version, columns, rows, values by column.
        mutating func matrix() throws -> (cols: Int, rows: Int, values: [Double]) {
            guard try i32() == 0x434d_6174, try i32() == 0x7269_7843 else { throw ChcError.notHCFR }
            _ = try i32()
            let cols = Int(try i32()), rows = Int(try i32())
            guard cols >= 0, rows >= 0, cols * rows < 1_000_000 else { throw ChcError.truncated }
            var v = [Double](repeating: 0, count: cols * rows)
            for c in 0..<cols { for r in 0..<rows { v[r * cols + c] = try f64() } }
            return (cols, rows, v)
        }
        /// CColor: XYZ (also when it is "no data").
        mutating func rawColor() throws -> [Double] {
            let version = Int(try i32())
            guard version <= 6 else { throw ChcError.newerVersion(version) }
            let xyz = try matrix().values
            _ = try matrix(); _ = try matrix()
            lastSpectrum = nil
            lastLux = nil
            if [2, 4, 5, 6].contains(version) {
                _ = try i32()
                let lo = Double(try i32()), hi = Double(try i32())
                if version == 2 || version == 4 { _ = try i32() } else { _ = try f64() }
                _ = try i32()                    // CSpectrum version
                let values = try matrix().values
                if values.count > 1 { lastSpectrum = Spectrum(start: lo, end: hi, values: values) }
            }
            if [3, 4, 6].contains(version) { lastLux = try f64() }
            return Array(xyz.prefix(3)) + [Double](repeating: 0, count: max(0, 3 - xyz.count))
        }
        /// CColor, nil when not measured; its spectrum and lux value are kept under `key`.
        mutating func color(_ key: String?) throws -> [Double]? {
            let c = try rawColor()
            guard c[0] > -1 && c[1] > -1 && c[2] > -1 else { return nil }
            if let key { keepExtras(key) }
            return c
        }
    }

    struct Writer {
        var bytes: [UInt8] = []
        mutating func u32(_ v: UInt32) { for k in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(k))) & 0xFF)) } }
        mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
        mutating func i64(_ v: Int64) { let u = UInt64(bitPattern: v); for k in 0..<8 { bytes.append(UInt8((u >> (8 * UInt64(k))) & 0xFF)) } }
        mutating func u16(_ v: UInt16) { bytes.append(UInt8(v & 0xFF)); bytes.append(UInt8(v >> 8)) }
        mutating func bool(_ v: Bool) { i32(v ? 1 : 0) }
        mutating func f32(_ v: Float) { u32(v.bitPattern) }
        mutating func f64(_ v: Double) { let u = v.bitPattern; for k in 0..<8 { bytes.append(UInt8((u >> (8 * UInt64(k))) & 0xFF)) } }
        mutating func matrix(cols: Int, rows: Int, _ v: [Double]) {
            i32(0x434d_6174); i32(0x7269_7843); i32(1); i32(Int32(cols)); i32(Int32(rows))
            for c in 0..<cols { for r in 0..<rows { f64(v[r * cols + c]) } }
        }
        /// CColor: XYZ (nil = no data), the two unused matrices, the spectrum (version 5) and the
        /// lux value (version 3), or both (version 6).
        mutating func color(_ xyz: [Double]?, spectrum: Spectrum? = nil, lux: Double? = nil) {
            let v = xyz.flatMap { $0.count == 3 ? $0 : nil }
            let spec = v == nil ? nil : spectrum.flatMap { $0.values.count > 1 ? $0 : nil }
            let lx = v == nil ? nil : lux
            i32(lx != nil ? (spec != nil ? 6 : 3) : (spec != nil ? 5 : 1))
            matrix(cols: 1, rows: 3, v ?? [ChcFile.noData, ChcFile.noData, ChcFile.noData])
            matrix(cols: 3, rows: 3, [Double](repeating: 0, count: 9))
            matrix(cols: 3, rows: 3, [Double](repeating: 0, count: 9))
            if let s = spec {
                i32(Int32(s.values.count)); i32(Int32(s.start.rounded())); i32(Int32(s.end.rounded())); f64(s.step)
                i32(1)                                                     // CSpectrum version
                matrix(cols: 1, rows: s.values.count, s.values)
            }
            if let lx { f64(lx) }
        }
        /// MFC CString (multibyte build): length (byte, or 0xFF + word) and the bytes.
        mutating func string(_ s: String) {
            let b = Array(s.data(using: .windowsCP1252, allowLossyConversion: true) ?? Data())
            if b.count < 255 { bytes.append(UInt8(b.count)) } else { bytes.append(0xFF); u16(UInt16(min(b.count, 0xFFFD))) }
            bytes += b.prefix(0xFFFD)
        }
        /// CArchive::WriteObject of a class not written before: new class tag, schema, name.
        mutating func newClass(_ name: String) {
            u16(0xFFFF); u16(1); u16(UInt16(name.utf8.count)); bytes += Array(name.utf8)
        }
    }
}
