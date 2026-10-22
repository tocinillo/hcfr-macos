// HCFR for macOS
// Copyright (C) 2026 Jorge Velázquez
// CSV export added in 2026 (HCFR for Windows: File → Export, Export.cpp).
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import AppKit
import UniformTypeIdentifiers

extension Session {
    /// Every measurement of the project as CSV (one row per patch), for spreadsheets.
    func csvText() -> String {
        func f(_ v: Double?, _ d: Int) -> String {
            guard let v, v.isFinite else { return "" }
            return String(format: "%.\(d)f", v)
        }
        func q(_ s: String) -> String { s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        let r = ref
        var lines = [
            "# HCFR for macOS \(AboutPanel.version) for macOS",
            "# Project,\(q(projectName))",
            "# Color space,\(q(r.standard.rawValue)),White point,\(r.white.rawValue),EOTF,\(q(gammaDescription))",
            "# Delta E,\(q(r.deltaEFormula.title)),Gray,\(q(r.grayDeltaE.title))",
        ]
        if let m = meter { lines.append("# Meter,\(q(m.name)),Serial,\(q(m.serial)),Display,\(q(correction?.name ?? ""))") }
        lines.append("View,Patch,X,Y,Z,x,y,Delta E,delta xy,delta L %,Y target,Gamma,CCT")
        func add(_ view: String, _ name: String, _ c: XYZ?, dE: Double?, dxy: Double?, dL: Double?, target: Double?,
                 gamma: Double? = nil, cct: Double? = nil) {
            guard let c else { return }
            lines.append([q(view), q(name), f(c.X, 4), f(c.Y, 4), f(c.Z, 4), f(c.x, 4), f(c.y, 4), f(dE, 2), f(dxy, 4),
                          f(dL.map { $0 * 100 }, 2), f(target, 4), f(gamma, 3), f(cct, 0)].joined(separator: ","))
        }
        for s in results where !(s.level == 0 && overrideBlack) {
            add(MeasureView.grayScale.rawValue, Reference.label(s.level), s.xyz, dE: s.deltaE, dxy: s.deltaxy, dL: nil,
                target: s.targetY, gamma: s.gamma, cct: s.cct)
        }
        for p in patchResults {
            add(MeasureView.primariesSecondaries.rawValue, p.patch.rawValue, colorMeasurements[p.patch], dE: p.deltaE,
                dxy: p.deltaxy, dL: p.deltaL, target: p.reference.Y * colorWhiteY, cct: p.cct)
        }
        for v in MeasureView.allCases where v.isSeries {
            for s in seriesResults(v) {
                add(v.rawValue, s.name, s.xyz, dE: s.deltaE, dxy: s.deltaxy, dL: s.deltaL, target: s.targetY, cct: s.cct)
            }
        }
        for s in contrastResults where contrastMeasurements[ContrastPatch.allCases[s.index]] != nil {
            add(MeasureView.contrast.rawValue, s.name, s.xyz, dE: nil, dxy: nil, dL: nil, target: nil)
        }
        if let c = onOffContrast { lines.append("# On/off contrast,\(c.isInfinite ? "Infinite" : f(c, 0))") }
        if let c = ansiContrast { lines.append("# ANSI contrast,\(c.isInfinite ? "Infinite" : f(c, 0))") }
        return lines.joined(separator: "\n") + "\n"
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "Export measurements"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = projectName + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csvText().write(to: url, atomically: true, encoding: .utf8)
            status = "Exported: \(url.lastPathComponent)"
        } catch {
            errorMessage = "Could not export: \(error.localizedDescription)"
        }
    }
}

extension Session {
    /// File → "Create PDF Report…" (HCFR's Export → Create PDF Report): the printed report as a PDF file.
    func exportPDFReport() {
        guard let pdf = Report.makePDF(self) else { errorMessage = "Could not create the report."; return }
        let panel = NSSavePanel()
        panel.title = "Create PDF Report"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = projectName + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pdf.write(to: url)
            status = "Report saved: \(url.lastPathComponent)"
        } catch {
            errorMessage = "Could not save the report: \(error.localizedDescription)"
        }
    }

    /// Edit → "Copy Table": the table shown, tab separated (pastes into Numbers / Excel), as HCFR's Copy.
    func copyTable() {
        let lines = csvText().split(separator: "\n").map(String.init)
        guard let header = lines.first(where: { !$0.hasPrefix("#") }) else { return }
        let name = view.rawValue
        let rows = lines.filter { $0.hasPrefix(name + ",") || $0.hasPrefix("\"" + name + "\",") }
        let tsv = ([header] + rows).map { $0.replacingOccurrences(of: ",", with: "\t") }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tsv, forType: .string)
        status = "\(rows.count) rows of \(name) copied"
    }
}
