// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// General / Advanced / sensor options added in 2026 after HCFR for Windows (GeneralPropPage.cpp,
// AdvancedPropPage.cpp, Sensors/ArgyllSensor.cpp, Sensors/Sensor.cpp), GNU GPL.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import Foundation

/// Colors added to a primaries / secondaries run (HCFR "BWColorsToAdd").
enum ColorsToAdd: Int, CaseIterable, Identifiable, Codable {
    case none = 0, white = 1, whiteAndBlack = 2
    var id: Int { rawValue }
    var title: String { ["None", "White", "White and black"][rawValue] }
}

/// HCFR's Argyll meter reading types.
enum ReadingType: Int, CaseIterable, Identifiable, Codable {
    case display = 0, telephoto = 1, ambient = 2
    var id: Int { rawValue }
    var title: String { ["Display", "Telephoto", "Ambient"][rawValue] }
}

/// HCFR's integration time choices for i1 Display Pro / ColorMunki Display (seconds; 0 = Argyll default).
enum IntegrationTime: Int, CaseIterable, Identifiable, Codable {
    case argyllDefault = 0, best, s03, s04, s06, s08, s10
    var id: Int { rawValue }
    var seconds: Double { [0, 0.5, 0.3, 0.4, 0.6, 0.8, 1.0][rawValue] }
    var title: String {
        switch self {
        case .argyllDefault: return "Argyll Default [0.2 sec]"
        case .best: return "Best [0.5 sec]"
        default: return String(format: "%.1f sec", seconds)
        }
    }
}

/// Luminance graph modes (HCFR's Luminance graph menu: relative, Absolute Y, log(Y), L*).
enum LuminanceMode: String, CaseIterable, Identifiable, Codable {
    case relative = "Luminance %", absolute = "Absolute Y", log = "log(Y)", lStar = "L*"
    var id: String { rawValue }
}

/// Scale and display options of the graphs (HCFR's right-click graph menus).
struct GraphOptions: Codable, Equatable {
    var luminance = LuminanceMode.relative
    /// RGB levels scale: 0 = 0-200%, 1 = 60-140%, 2 = 50-150%, 3 = 80-120%.
    var rgbScale = 1
    /// Delta E axis maximum (5, 10 or 20).
    var deltaEMax = 10.0
    /// Color temperature scale: 0 = auto, 1 = 2000-10000 K, 2 = 4000-8000 K.
    var tempScale = 0
    /// CIE diagram: saturations, Color Checker and free measures shown whatever the table.
    var cieAllSeries = false

    var rgbDomain: ClosedRange<Double> { [0.0...200, 60...140, 50...150, 80...120][min(max(rgbScale, 0), 3)] }
}

/// Options of HCFR's General and Advanced pages and of the sensor page. Saved with the settings.
struct AppPrefs: Codable, Equatable {
    // General
    /// "Bip at the beginning of measure (latency definition help)".
    var latencyBeep = false
    /// "Frame insertion" (ABL inhibitor): every `ablFrequency` patterns, a gray frame of
    /// `ablLevel` % is shown for `ablDuration` ms before the pattern.
    var ablEnabled = false
    var ablFrequency = 10
    var ablDuration = 500
    var ablLevel = 50
    var colorsToAdd = ColorsToAdd.white
    /// "Gray levels rounding assumption": round down (AVSHD, DVE) or 10-bit targets (HDR10 Blu-ray).
    var roundDown = false
    var use10bit = false

    // Advanced
    /// "Measure launch: Confirmation message".
    var confirmMeasures = true
    /// "Delta E: Highlight" (green / yellow / red cells).
    var highlight = true

    // Sensor
    var readingType = ReadingType.display
    /// Argyll observer number (0 = default, CIE 1931 2°).
    var observer = 0
    var integrationTime = IntegrationTime.best
    var hiRes = false
    /// HCFR's sensor matrix: applied to every reading (identity = no correction), row major.
    var sensorMatrix: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    /// Advanced → "Do not use white in matrix calculus (R1.x)".
    var matrixOnlyPrimaries = false

    var hasSensorMatrix: Bool { sensorMatrix != [1, 0, 0, 0, 1, 0, 0, 0, 1] && sensorMatrix.count == 9 }

    func correct(_ c: XYZ) -> XYZ {
        guard hasSensorMatrix else { return c }
        let m = sensorMatrix
        return XYZ(X: m[0] * c.X + m[1] * c.Y + m[2] * c.Z,
                   Y: m[3] * c.X + m[4] * c.Y + m[5] * c.Z,
                   Z: m[6] * c.X + m[7] * c.Y + m[8] * c.Z)
    }
}

extension Decodable where Self: Encodable {
    /// Decodes saved settings over the defaults, so settings saved by an older version (with fewer
    /// fields) keep their values and the new fields get their defaults.
    static func decodeMerging(_ data: Data?, over defaults: Self) -> Self {
        guard let data,
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults)) as? [String: Any] else { return defaults }
        let merged = base.merging(saved) { _, new in new }
        guard let json = try? JSONSerialization.data(withJSONObject: merged),
              let value = try? JSONDecoder().decode(Self.self, from: json) else { return defaults }
        return value
    }
}
