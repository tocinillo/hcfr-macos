// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// Interface languages added in 2026 (HCFR for Windows: Language… English, Français, Deutsch,
// Español, Italiano). English texts are the keys of Resources/<lang>.lproj/Localizable.strings.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import Foundation
import Combine

/// Translated text of an English interface string (or the string itself when there is none).
func tr(_ s: String) -> String {
    if let d = LocalizationTest.strings { return d[s] ?? s }
    return Bundle.main.localizedString(forKey: s, value: s, table: nil)
}

/// Development check (`--lang-test Resources/es.lproj/Localizable.strings`): a strings table used
/// instead of the app bundle's, as the development binary has no .lproj folders.
enum LocalizationTest {
    static var strings: [String: String]?
}

/// Translated format string, filled in (e.g. tr("Run %@ measures on %d values?", name, n)).
func tr(_ format: String, _ args: CVarArg...) -> String {
    String(format: tr(format), arguments: args)
}

/// Interface language (General preferences → Language), applied when the app starts again.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "", english = "en", spanish = "es"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return tr("System")
        case .english: return "English"
        case .spanish: return "Español"
        }
    }

    static var current: AppLanguage {
        guard let l = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first,
              UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] != nil
        else { return .system }
        return l.hasPrefix("es") ? .spanish : l.hasPrefix("en") ? .english : .system
    }

    func apply() {
        if self == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        else { UserDefaults.standard.set([rawValue], forKey: "AppleLanguages") }
    }
}

/// Translated status, prompt or error message. Messages are built at run time with names and
/// numbers in them, so each line is matched against the patterns below (names inside are translated too).
func trMessage(_ s: String) -> String {
    guard MessageRules.active, !s.isEmpty else { return s }
    return s.components(separatedBy: "\n").map(MessageRules.line).joined(separator: "\n")
}

enum MessageRules {
    static var active = Bundle.main.preferredLocalizations.first?.hasPrefix("es") ?? false

    static func line(_ l: String) -> String {
        let exact = tr(l)
        if exact != l || l.isEmpty { return exact }
        let ns = l as NSString
        for (re, template) in rules {
            guard let m = re.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) else { continue }
            var out = template
            for g in stride(from: m.numberOfRanges - 1, through: 1, by: -1) {
                let r = m.range(at: g)
                let part = r.location == NSNotFound ? "" : ns.substring(with: r)
                out = out.replacingOccurrences(of: "$\(g)", with: line(part))
            }
            return out
        }
        return l
    }

    static let rules: [(NSRegularExpression, String)] = table.compactMap { pair in
        (try? NSRegularExpression(pattern: "^" + pair.0 + "$")).map { ($0, pair.1) }
    }

    // Spanish (the only translation so far); English pattern → Spanish text with $1, $2…
    static let table: [(String, String)] = [
        ("Run (.+) measures on (\\d+) values \\((.+)\\)\\?", "¿Medir $1 en $2 valores ($3)?"),
        ("Run (.+) measures on (\\d+) values\\?", "¿Medir $1 en $2 valores?"),
        ("Run contrast measures \\((.+)\\)\\?", "¿Medir el contraste ($1)?"),
        ("Run Gray scale, Near Black/White, Primaries/Secondaries, saturations, Color Checker \\((.+)\\) and contrast patterns on (\\d+) values\\?",
         "¿Medir escala de grises, cerca del negro/blanco, primarios/secundarios, saturaciones, Color Checker ($1) y contraste en $2 valores?"),
        ("Use (.+) and press Continue\\.", "Ponga $1 y pulse Continuar."),
        ("Use (.+) IRE\\.", "Ponga $1 IRE."),
        ("(.+) to 100 IRE", "$1 a 100 IRE"),
        ("(.+) IRE", "$1 IRE"),
        ("100% (.+)", "$1 100%"),
        ("Measuring (.+) IRE…", "Midiendo $1 IRE…"),
        ("Measuring (.+): (.+) \\((\\d+) of (\\d+)\\)…", "Midiendo $1: $2 ($3 de $4)…"),
        ("Measuring (.+)…", "Midiendo $1…"),
        ("Continuous reading at (.+) IRE — click another column to measure it, Stop to finish",
         "Lectura continua a $1 IRE — pulse otra columna para medirla, Detener para terminar"),
        ("Continuous reading of (.+) — click another column to measure it, Stop to finish",
         "Lectura continua de $1 — pulse otra columna para medirla, Detener para terminar"),
        ("(.+) measurement finished", "Medida terminada: $1"),
        ("Free measure (\\d+) added", "Medida libre $1 añadida"),
        ("Ready — Display: (.+)", "Listo — Pantalla: $1"),
        ("Display: (.+)", "Pantalla: $1"),
        ("Connecting to the Raspberry Pi at (.+)…", "Conectando con la Raspberry Pi en $1…"),
        ("Connecting the second meter (.+)…", "Conectando la segunda sonda $1…"),
        ("Connecting to (.+)…", "Conectando con $1…"),
        ("Comparing with (.+): rows dE / ref and xy / ref", "Comparando con $1: filas dE / ref y xy / ref"),
        ("Exported: (.+) and the other HCFR sheets", "Exportado: $1 y las demás hojas de HCFR"),
        ("Exported: (.+)", "Exportado: $1"),
        ("Graph saved: (.+)", "Gráfico guardado: $1"),
        ("Project saved: (.+)", "Proyecto guardado: $1"),
        ("Report saved: (.+)", "Informe guardado: $1"),
        ("Gray scale: (\\d+) points \\(every (.+)%\\)", "Escala de grises: $1 puntos (cada $2%)"),
        ("Meter correction loaded: (.+)\\. It applies to the next readings\\.", "Corrección de la sonda cargada: $1. Se aplica a las próximas lecturas."),
        ("Meter correction saved: (.+)", "Corrección de la sonda guardada: $1"),
        ("Pattern on the Raspberry Pi: (.+) \\(PGenerator's images-HCFR/(.+)\\)", "Patrón en la Raspberry Pi: $1 (images-HCFR/$2 de PGenerator)"),
        ("Pattern: (.+) — ESC or Patterns → Hide pattern to close", "Patrón: $1 — ESC o Patrones → Ocultar patrón para cerrar"),
        ("Showing (.+) — ESC or Patterns → Hide pattern to close", "Mostrando $1 — ESC o Patrones → Ocultar patrón para cerrar"),
        ("Raspberry Pi connected at (.+) \\((.+)\\)", "Raspberry Pi conectada en $1 ($2)"),
        ("Second meter connected: (.+)\\. Simultaneous measures: its readings go to the compared data \\(dE / ref\\)\\.",
         "Segunda sonda conectada: $1. Medidas simultáneas: sus lecturas van a los datos comparados (dE / ref)."),
        ("Sensor matrix computed against (.+)\\. It applies to the next readings: measure again\\.",
         "Matriz del sensor calculada frente a $1. Se aplica a las próximas lecturas: vuelva a medir."),
        ("Sensor options not applied: (.+) \\(rebuild with build-app.sh to update the meter helper\\)",
         "Opciones del sensor no aplicadas: $1 (recompile con build-app.sh para actualizar el auxiliar de la sonda)"),
        ("Spectral sample saved: (.+)\\. Reconnect the colorimeter to choose it in Display\\.",
         "Muestra espectral guardada: $1. Vuelva a conectar el colorímetro para elegirla en Pantalla."),
        ("(\\d+) colorimeters found — choose one in Sensor and press Connect\\.", "Se encontraron $1 colorímetros — elija uno en Sensor y pulse Conectar."),
        ("(\\d+) colorimeters found\\.", "Se encontraron $1 colorímetros."),
        ("(\\d+) rows of (.+) copied", "$1 filas de $2 copiadas"),
        ("Could not open (.+)\\. It is not an HCFR Colorimeter project\\.", "No se pudo abrir $1. No es un proyecto de HCFR Colorimeter."),
        ("(.+) is not a meter correction file \\(\\.ccmx or \\.thc with a 3×3 matrix\\)\\.",
         "$1 no es un archivo de corrección de sonda (.ccmx o .thc con una matriz 3×3)."),
        ("Could not save the report: (.+)", "No se pudo guardar el informe: $1"),
        ("Could not save the spectral sample: (.+)", "No se pudo guardar la muestra espectral: $1"),
        ("Could not save the graph: (.+)", "No se pudo guardar el gráfico: $1"),
        ("Could not save the project: (.+)", "No se pudo guardar el proyecto: $1"),
        ("Could not save: (.+)", "No se pudo guardar: $1"),
        ("Could not export: (.+)", "No se pudo exportar: $1"),
        ("Second meter: (.+)", "Segunda sonda: $1"),
        ("Reading mode (.+) is not available on this meter, using (.+)\\.", "El modo de lectura $1 no está disponible en esta sonda; se usa $2."),
        ("No patterns found in (.+)\\. Each line must be R,G,B,name with video levels \\(16-235\\), as HCFR's usercolors.csv\\.",
         "No se encontraron patrones en $1. Cada línea debe ser R,G,B,nombre con niveles de vídeo (16-235), como el usercolors.csv de HCFR."),
        ("The pattern image (.+) was not found\\. Rebuild the app with build-app.sh\\.", "No se encontró la imagen de patrón $1. Recompile la aplicación con build-app.sh."),
        ("(.+); (.+)", "$1; $2"),
        ("(.+), (.+)", "$1, $2"),
    ]
}

/// Language picker state (General preferences).
final class LanguageChoice: ObservableObject {
    @Published var value: AppLanguage = .current { didSet { value.apply() } }
}
