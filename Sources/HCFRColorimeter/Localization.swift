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
    case system = "", english = "en", spanish = "es", german = "de", french = "fr", italian = "it"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return tr("System")
        case .english: return "English"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .italian: return "Italiano"
        }
    }

    static var current: AppLanguage {
        guard let l = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first,
              UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] != nil
        else { return .system }
        return AppLanguage.allCases.first { $0 != .system && l.hasPrefix($0.rawValue) } ?? .system
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
    /// Language of the interface ("es", "de", "fr", "it"); English needs no rules.
    static let language: String? = {
        let l = String((Bundle.main.preferredLocalizations.first ?? "en").prefix(2))
        return ["es", "de", "fr", "it"].contains(l) ? l : nil
    }()
    static var active = language != nil

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

    static let rules: [(NSRegularExpression, String)] = {
        let column = ["es": 0, "de": 1, "fr": 2, "it": 3][language ?? "es"] ?? 0
        return table.compactMap { row in
            guard let re = try? NSRegularExpression(pattern: "^" + row.0 + "$") else { return nil }
            let t = column == 0 ? row.1 : (extra[row.0]?[column - 1] ?? row.1)
            return (re, t)
        }
    }()

    // English pattern → Spanish text with $1, $2… (German, French and Italian in `extra`)
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
        ("Connecting to the Chromecast (.+)…", "Conectando con el Chromecast $1…"),
        ("Chromecast connected: (.+)", "Chromecast conectado: $1"),
        ("Could not connect to the Chromecast \"(.+)\"\\.", "No se pudo conectar con el Chromecast \"$1\"."),
        ("The Chromecast \"(.+)\" did not start the pattern receiver\\.", "El Chromecast \"$1\" no arrancó el receptor de patrones."),
        ("The Chromecast did not load the pattern \\((.+)\\)", "El Chromecast no cargó el patrón ($1)"),
        ("Connecting to the Raspberry Pi at (.+)…", "Conectando con la Raspberry Pi en $1…"),
        ("Connecting to madVR at (.+)…", "Conectando con madVR en $1…"),
        ("madVR connected at (.+)", "madVR conectado en $1"),
        ("madVR not connected", "madVR no conectado"),
        ("Setting PGenerator output: (.+)…", "Configurando la salida de PGenerator: $1…"),
        ("Restarting PGenerator with the new output…", "Reiniciando PGenerator con la nueva salida…"),
        ("PGenerator output: (.+)", "Salida de PGenerator: $1"),
        ("High resolution \\(3\\.3 nm\\) on — the meter may ask for a new calibration", "Alta resolución (3,3 nm) activada — la sonda puede pedir una nueva calibración"),
        ("Standard resolution \\(10 nm\\)", "Resolución estándar (10 nm)"),
        ("Could not connect to madVR at (.+)\\.", "No se pudo conectar con madVR en $1."),
        ("madVR at (.+) answered, but did not start its test pattern generator \\(madTPG\\)\\.", "madVR en $1 respondió, pero no arrancó su generador de patrones (madTPG)."),
        ("Error communicating with madVR", "Error de comunicación con madVR"),
        ("Connecting the second meter (.+)…", "Conectando la segunda sonda $1…"),
        ("Connecting to (.+)…", "Conectando con $1…"),
        ("Comparing with (.+): rows dE / ref and xy / ref", "Comparando con $1: filas dE / ref y xy / ref"),
        ("Reference project: (.+)", "Proyecto de referencia: $1"),
        ("Exported: (.+) \\((\\d+) HCFR sheets\\)", "Exportado: $1 ($2 hojas de HCFR)"),
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
        ("Free measure stored as (.+) too", "Medida libre guardada también como $1"),
        ("(.+), (.+)", "$1, $2"),
    ]

    /// German, French and Italian templates of the patterns above.
    static let extra: [String: [String]] = {
        var d: [String: [String]] = [:]
        for r in extraRows { d[r.0] = [r.1, r.2, r.3] }
        return d
    }()

    private static let extraRows: [(String, String, String, String)] = [
        ("Run (.+) measures on (\\d+) values \\((.+)\\)\\?", "$1-Messungen mit $2 Werten ($3) starten?", "Lancer les mesures $1 sur $2 valeurs ($3) ?", "Avviare le misure di $1 su $2 valori ($3)?"),
        ("Run (.+) measures on (\\d+) values\\?", "$1-Messungen mit $2 Werten starten?", "Lancer les mesures $1 sur $2 valeurs ?", "Avviare le misure di $1 su $2 valori?"),
        ("Run contrast measures \\((.+)\\)\\?", "Kontrastmessungen ($1) starten?", "Lancer les mesures de contraste ($1) ?", "Avviare le misure di contrasto ($1)?"),
        ("Run Gray scale, Near Black/White, Primaries/Secondaries, saturations, Color Checker \\((.+)\\) and contrast patterns on (\\d+) values\\?", "Graustufen, nahe Schwarz/Weiß, Primär-/Sekundärfarben, Sättigungen, Color Checker ($1) und Kontrast mit $2 Werten messen?", "Mesurer échelle de gris, proche noir/blanc, primaires/secondaires, saturations, Color Checker ($1) et contraste sur $2 valeurs ?", "Misurare scala di grigi, vicino al nero/bianco, primari/secondari, saturazioni, Color Checker ($1) e contrasto su $2 valori?"),
        ("Use (.+) and press Continue\\.", "Verwenden Sie $1 und drücken Sie Weiter.", "Utilisez $1 et appuyez sur Continuer.", "Usa $1 e premi Continua."),
        ("Use (.+) IRE\\.", "Verwenden Sie $1 IRE.", "Utilisez $1 IRE.", "Usa $1 IRE."),
        ("(.+) to 100 IRE", "$1 bis 100 IRE", "$1 à 100 IRE", "$1 a 100 IRE"),
        ("(.+) IRE", "$1 IRE", "$1 IRE", "$1 IRE"),
        ("100% (.+)", "$1 100%", "$1 100%", "$1 100%"),
        ("Measuring (.+) IRE…", "Messe $1 IRE…", "Mesure de $1 IRE…", "Misura di $1 IRE…"),
        ("Measuring (.+): (.+) \\((\\d+) of (\\d+)\\)…", "Messe $1: $2 ($3 von $4)…", "Mesure $1 : $2 ($3 sur $4)…", "Misura $1: $2 ($3 di $4)…"),
        ("Measuring (.+)…", "Messe $1…", "Mesure $1…", "Misura $1…"),
        ("Continuous reading at (.+) IRE — click another column to measure it, Stop to finish", "Fortlaufende Messung bei $1 IRE — andere Spalte anklicken, um sie zu messen, Stopp zum Beenden", "Lecture continue à $1 IRE — cliquez une autre colonne pour la mesurer, Arrêter pour finir", "Lettura continua a $1 IRE — fai clic su un'altra colonna per misurarla, Stop per finire"),
        ("Continuous reading of (.+) — click another column to measure it, Stop to finish", "Fortlaufende Messung von $1 — andere Spalte anklicken, um sie zu messen, Stopp zum Beenden", "Lecture continue de $1 — cliquez une autre colonne pour la mesurer, Arrêter pour finir", "Lettura continua di $1 — fai clic su un'altra colonna per misurarla, Stop per finire"),
        ("(.+) measurement finished", "Messung beendet: $1", "Mesure terminée : $1", "Misura terminata: $1"),
        ("Free measure (\\d+) added", "Freie Messung $1 hinzugefügt", "Mesure libre $1 ajoutée", "Misura libera $1 aggiunta"),
        ("Ready — Display: (.+)", "Bereit — Anzeige: $1", "Prêt — Écran : $1", "Pronto — Display: $1"),
        ("Display: (.+)", "Anzeige: $1", "Écran : $1", "Display: $1"),
        ("Connecting to the Raspberry Pi at (.+)…", "Verbinde mit dem Raspberry Pi unter $1…", "Connexion au Raspberry Pi à $1…", "Connessione al Raspberry Pi su $1…"),
        ("Connecting to madVR at (.+)…", "Verbinde mit madVR unter $1…", "Connexion à madVR à $1…", "Connessione a madVR su $1…"),
        ("madVR connected at (.+)", "madVR verbunden unter $1", "madVR connecté à $1", "madVR collegato su $1"),
        ("madVR not connected", "madVR nicht verbunden", "madVR non connecté", "madVR non collegato"),
        ("Setting PGenerator output: (.+)…", "Setze PGenerator-Ausgabe: $1…", "Réglage de la sortie PGenerator : $1…", "Impostazione dell'uscita PGenerator: $1…"),
        ("Restarting PGenerator with the new output…", "PGenerator wird mit der neuen Ausgabe neu gestartet…", "Redémarrage de PGenerator avec la nouvelle sortie…", "Riavvio di PGenerator con la nuova uscita…"),
        ("PGenerator output: (.+)", "PGenerator-Ausgabe: $1", "Sortie PGenerator : $1", "Uscita PGenerator: $1"),
        ("High resolution \\(3\\.3 nm\\) on — the meter may ask for a new calibration", "Hohe Auflösung (3,3 nm) an — das Gerät kann eine neue Kalibrierung verlangen", "Haute résolution (3,3 nm) activée — la sonde peut demander une nouvelle calibration", "Alta risoluzione (3,3 nm) attiva — la sonda può chiedere una nuova calibrazione"),
        ("Standard resolution \\(10 nm\\)", "Standardauflösung (10 nm)", "Résolution standard (10 nm)", "Risoluzione standard (10 nm)"),
        ("Could not connect to madVR at (.+)\\.", "Keine Verbindung zu madVR unter $1.", "Impossible de se connecter à madVR à $1.", "Impossibile collegarsi a madVR su $1."),
        ("madVR at (.+) answered, but did not start its test pattern generator \\(madTPG\\)\\.", "madVR unter $1 hat geantwortet, aber seinen Testmustergenerator (madTPG) nicht gestartet.", "madVR à $1 a répondu, mais n'a pas lancé son générateur de mires (madTPG).", "madVR su $1 ha risposto, ma non ha avviato il generatore di pattern (madTPG)."),
        ("Error communicating with madVR", "Kommunikationsfehler mit madVR", "Erreur de communication avec madVR", "Errore di comunicazione con madVR"),
        ("Connecting the second meter (.+)…", "Verbinde das zweite Messgerät $1…", "Connexion de la seconde sonde $1…", "Connessione della seconda sonda $1…"),
        ("Connecting to (.+)…", "Verbinde mit $1…", "Connexion à $1…", "Connessione a $1…"),
        ("Comparing with (.+): rows dE / ref and xy / ref", "Vergleich mit $1: Zeilen dE / Ref und xy / Ref", "Comparaison avec $1 : lignes dE / réf et xy / réf", "Confronto con $1: righe dE / rif e xy / rif"),
        ("Exported: (.+) \\((\\d+) HCFR sheets\\)", "Exportiert: $1 ($2 HCFR-Tabellen)", "Exporté : $1 ($2 feuilles HCFR)", "Esportato: $1 ($2 fogli HCFR)"),
        ("Exported: (.+)", "Exportiert: $1", "Exporté : $1", "Esportato: $1"),
        ("Graph saved: (.+)", "Grafik gesichert: $1", "Graphique enregistré : $1", "Grafico salvato: $1"),
        ("Project saved: (.+)", "Projekt gesichert: $1", "Projet enregistré : $1", "Progetto salvato: $1"),
        ("Report saved: (.+)", "Bericht gesichert: $1", "Rapport enregistré : $1", "Report salvato: $1"),
        ("Gray scale: (\\d+) points \\(every (.+)%\\)", "Graustufen: $1 Punkte (alle $2%)", "Échelle de gris : $1 points (tous les $2%)", "Scala di grigi: $1 punti (ogni $2%)"),
        ("Meter correction loaded: (.+)\\. It applies to the next readings\\.", "Messgerätekorrektur geladen: $1. Sie gilt für die nächsten Messungen.", "Correction de sonde chargée : $1. Elle s'applique aux prochaines lectures.", "Correzione della sonda caricata: $1. Si applica alle prossime letture."),
        ("Meter correction saved: (.+)", "Messgerätekorrektur gesichert: $1", "Correction de sonde enregistrée : $1", "Correzione della sonda salvata: $1"),
        ("Pattern on the Raspberry Pi: (.+) \\(PGenerator's images-HCFR/(.+)\\)", "Muster auf dem Raspberry Pi: $1 (images-HCFR/$2 von PGenerator)", "Mire sur le Raspberry Pi : $1 (images-HCFR/$2 de PGenerator)", "Pattern sul Raspberry Pi: $1 (images-HCFR/$2 di PGenerator)"),
        ("Pattern: (.+) — ESC or Patterns → Hide pattern to close", "Muster: $1 — ESC oder Muster → Muster ausblenden zum Schließen", "Mire : $1 — ÉCHAP ou Mires → Masquer la mire pour fermer", "Pattern: $1 — ESC o Pattern → Nascondi pattern per chiudere"),
        ("Showing (.+) — ESC or Patterns → Hide pattern to close", "Zeige $1 — ESC oder Muster → Muster ausblenden zum Schließen", "Affichage de $1 — ÉCHAP ou Mires → Masquer la mire pour fermer", "Visualizzazione di $1 — ESC o Pattern → Nascondi pattern per chiudere"),
        ("Raspberry Pi connected at (.+) \\((.+)\\)", "Raspberry Pi verbunden unter $1 ($2)", "Raspberry Pi connecté à $1 ($2)", "Raspberry Pi collegato su $1 ($2)"),
        ("Second meter connected: (.+)\\. Simultaneous measures: its readings go to the compared data \\(dE / ref\\)\\.", "Zweites Messgerät verbunden: $1. Simultane Messungen: seine Werte gehen in die Vergleichsdaten (dE / Ref).", "Seconde sonde connectée : $1. Mesures simultanées : ses lectures vont dans les données comparées (dE / réf).", "Seconda sonda collegata: $1. Misure simultanee: le sue letture vanno nei dati confrontati (dE / rif)."),
        ("Sensor matrix computed against (.+)\\. It applies to the next readings: measure again\\.", "Sensormatrix gegen $1 berechnet. Sie gilt für die nächsten Messungen: erneut messen.", "Matrice capteur calculée par rapport à $1. Elle s'applique aux prochaines lectures : mesurez à nouveau.", "Matrice del sensore calcolata rispetto a $1. Si applica alle prossime letture: misura di nuovo."),
        ("Sensor options not applied: (.+) \\(rebuild with build-app.sh to update the meter helper\\)", "Sensoroptionen nicht angewendet: $1 (mit build-app.sh neu erstellen, um den Messgeräte-Hilfsprozess zu aktualisieren)", "Options du capteur non appliquées : $1 (recompilez avec build-app.sh pour mettre à jour l'assistant de la sonde)", "Opzioni del sensore non applicate: $1 (ricompila con build-app.sh per aggiornare l'helper della sonda)"),
        ("Spectral sample saved: (.+)\\. Reconnect the colorimeter to choose it in Display\\.", "Spektralprobe gesichert: $1. Verbinden Sie das Colorimeter erneut, um sie unter Anzeige zu wählen.", "Échantillon spectral enregistré : $1. Reconnectez la sonde pour le choisir dans Écran.", "Campione spettrale salvato: $1. Ricollega la sonda per sceglierlo in Display."),
        ("(\\d+) colorimeters found — choose one in Sensor and press Connect\\.", "$1 Colorimeter gefunden — wählen Sie eines unter Sensor und drücken Sie Verbinden.", "$1 sondes trouvées — choisissez-en une dans Capteur et appuyez sur Connecter.", "$1 sonde trovate — scegline una in Sensore e premi Collega."),
        ("(\\d+) colorimeters found\\.", "$1 Colorimeter gefunden.", "$1 sondes trouvées.", "$1 sonde trovate."),
        ("(\\d+) rows of (.+) copied", "$1 Zeilen von $2 kopiert", "$1 lignes de $2 copiées", "$1 righe di $2 copiate"),
        ("Could not open (.+)\\. It is not an HCFR Colorimeter project\\.", "$1 konnte nicht geöffnet werden. Es ist kein HCFR-Colorimeter-Projekt.", "Impossible d'ouvrir $1. Ce n'est pas un projet HCFR Colorimeter.", "Impossibile aprire $1. Non è un progetto di HCFR Colorimeter."),
        ("(.+) is not a meter correction file \\(\\.ccmx or \\.thc with a 3×3 matrix\\)\\.", "$1 ist keine Korrekturdatei für Messgeräte (.ccmx oder .thc mit 3×3-Matrix).", "$1 n'est pas un fichier de correction de sonde (.ccmx ou .thc avec une matrice 3×3).", "$1 non è un file di correzione della sonda (.ccmx o .thc con una matrice 3×3)."),
        ("Could not save the report: (.+)", "Der Bericht konnte nicht gesichert werden: $1", "Impossible d'enregistrer le rapport : $1", "Impossibile salvare il report: $1"),
        ("Could not save the spectral sample: (.+)", "Die Spektralprobe konnte nicht gesichert werden: $1", "Impossible d'enregistrer l'échantillon spectral : $1", "Impossibile salvare il campione spettrale: $1"),
        ("Could not save the graph: (.+)", "Die Grafik konnte nicht gesichert werden: $1", "Impossible d'enregistrer le graphique : $1", "Impossibile salvare il grafico: $1"),
        ("Could not save the project: (.+)", "Das Projekt konnte nicht gesichert werden: $1", "Impossible d'enregistrer le projet : $1", "Impossibile salvare il progetto: $1"),
        ("Could not save: (.+)", "Konnte nicht sichern: $1", "Impossible d'enregistrer : $1", "Impossibile salvare: $1"),
        ("Could not export: (.+)", "Konnte nicht exportieren: $1", "Impossible d'exporter : $1", "Impossibile esportare: $1"),
        ("Second meter: (.+)", "Zweites Messgerät: $1", "Seconde sonde : $1", "Seconda sonda: $1"),
        ("Reading mode (.+) is not available on this meter, using (.+)\\.", "Messmodus $1 ist bei diesem Gerät nicht verfügbar, es wird $2 verwendet.", "Le mode de lecture $1 n'est pas disponible sur cette sonde, $2 est utilisé.", "La modalità di lettura $1 non è disponibile su questa sonda, si usa $2."),
        ("No patterns found in (.+)\\. Each line must be R,G,B,name with video levels \\(16-235\\), as HCFR's usercolors.csv\\.", "Keine Muster in $1 gefunden. Jede Zeile muss R,G,B,Name mit Videopegeln (16-235) sein, wie HCFRs usercolors.csv.", "Aucune mire trouvée dans $1. Chaque ligne doit être R,V,B,nom en niveaux vidéo (16-235), comme usercolors.csv de HCFR.", "Nessun pattern trovato in $1. Ogni riga deve essere R,G,B,nome con livelli video (16-235), come usercolors.csv di HCFR."),
        ("The pattern image (.+) was not found\\. Rebuild the app with build-app.sh\\.", "Das Musterbild $1 wurde nicht gefunden. Erstellen Sie die App mit build-app.sh neu.", "L'image de mire $1 est introuvable. Recompilez l'app avec build-app.sh.", "L'immagine del pattern $1 non è stata trovata. Ricompila l'app con build-app.sh."),
        ("(.+); (.+)", "$1; $2", "$1 ; $2", "$1; $2"),
        ("Free measure stored as (.+) too", "Freie Messung auch als $1 gespeichert", "Mesure libre enregistrée aussi comme $1", "Misura libera salvata anche come $1"),
        ("(.+), (.+)", "$1, $2", "$1, $2", "$1, $2"),
        ("Reference project: (.+)", "Referenzprojekt: $1", "Projet de référence : $1", "Progetto di riferimento: $1"),
        ("Connecting to the Chromecast (.+)…", "Verbinde mit dem Chromecast $1…", "Connexion au Chromecast $1…", "Connessione al Chromecast $1…"),
        ("Chromecast connected: (.+)", "Chromecast verbunden: $1", "Chromecast connecté : $1", "Chromecast collegato: $1"),
        ("Could not connect to the Chromecast \"(.+)\"\\.", "Keine Verbindung zum Chromecast \"$1\".", "Impossible de se connecter au Chromecast \"$1\".", "Impossibile collegarsi al Chromecast \"$1\"."),
        ("The Chromecast \"(.+)\" did not start the pattern receiver\\.", "Der Chromecast \"$1\" hat den Muster-Receiver nicht gestartet.", "Le Chromecast \"$1\" n'a pas lancé le récepteur de mires.", "Il Chromecast \"$1\" non ha avviato il ricevitore dei pattern."),
        ("The Chromecast did not load the pattern \\((.+)\\)", "Der Chromecast hat das Muster nicht geladen ($1)", "Le Chromecast n'a pas chargé la mire ($1)", "Il Chromecast non ha caricato il pattern ($1)"),
    ]
}

/// Language picker state (General preferences).
final class LanguageChoice: ObservableObject {
    @Published var value: AppLanguage = .current { didSet { value.apply() } }
}
