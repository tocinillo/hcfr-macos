// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI
import PDFKit

/// Printable report: project info, gray scale table and primaries/secondaries table.
/// Rendered to a vector PDF and printed with the standard macOS print dialog (which can also save as PDF).
@MainActor
enum Report {
    static func printReport(_ session: Session) {
        guard let pdf = makePDF(session), let doc = PDFDocument(data: pdf) else {
            session.errorMessage = "Could not create the report."
            return
        }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.orientation = .landscape
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 24; info.bottomMargin = 24; info.leftMargin = 24; info.rightMargin = 24
        info.jobDisposition = .spool
        guard let op = doc.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false) else {
            session.errorMessage = "Could not start printing."
            return
        }
        op.jobTitle = "HCFR Colorimeter — \(session.projectName)"
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }

    static func makePDF(_ session: Session) -> Data? {
        let view = ReportView(session: session)
            .environment(\.colorScheme, .light)
            .frame(width: 1000)
        let renderer = ImageRenderer(content: view)
        let data = NSMutableData()
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        return ok ? data as Data : nil
    }
}

private func rfmt(_ v: Double?, _ digits: Int) -> String {
    guard let v, v.isFinite else { return "" }
    return String(format: "%.\(digits)f", v)
}

/// Same Delta E colors as the main table (HCFR CIE2000 thresholds).
private func reportDeltaEColor(_ dE: Double?) -> Color {
    guard let dE else { return .clear }
    if dE < 2.0 { return Color(red: 175 / 255, green: 1, blue: 175 / 255) }
    if dE < 3.0 { return Color(red: 1, green: 1, blue: 175 / 255) }
    return Color(red: 1, green: 175 / 255, blue: 175 / 255)
}

private struct ReportView: View {
    @ObservedObject var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            graySection
            if !session.colorMeasurements.isEmpty { colorSection }
            Text("HCFR Colorimeter \(AboutPanel.version) for macOS — Mac version by Jorge Velázquez, Mazatlán, México. Unofficial port of HCFR (github.com/arthur-liberman/hcfr-code). GNU GPL v2. Source: \(AboutPanel.sourceURL.replacingOccurrences(of: "https://", with: ""))")
                .font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    // MARK: Header

    private var header: some View {
        let r = session.ref
        var info: [(String, String)] = [
            ("Project", session.projectName),
            ("Printed", Date().formatted(date: .abbreviated, time: .shortened)),
            ("Color space", r.standard.rawValue),
            ("White point", "\(r.white.rawValue) (\(r.white.kelvin) K)"),
            ("EOTF", r.standard.usesSRGBCurve ? "sRGB" : "Power law, gamma \(String(format: "%.2f", r.gamma))"),
            ("Override black", session.overrideBlack ? "On (0 cd/m²)" : "Off"),
            ("Delta E", "CIE2000, Absolute Y w/o gamma"),
        ]
        if let m = session.meter {
            info.append(("Colorimeter", m.serial.isEmpty ? m.name : "\(m.name) — S/N \(m.serial)"))
        }
        if let c = session.correction { info.append(("Display", c.name)) }
        if let d = session.lastMeasure { info.append(("Last measure", d.formatted(date: .abbreviated, time: .standard))) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("HCFR Colorimeter — Calibration report").font(.system(size: 18, weight: .bold))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                ForEach(Array(stride(from: 0, to: info.count, by: 2)), id: \.self) { i in
                    GridRow {
                        Text(info[i].0 + ":").bold()
                        Text(info[i].1)
                        if i + 1 < info.count {
                            Text(info[i + 1].0 + ":").bold()
                            Text(info[i + 1].1)
                        }
                    }
                }
            }
            .font(.system(size: 10))
        }
    }

    // MARK: Gray scale

    private var graySection: some View {
        let results = session.results
        let baseShown = session.measurements[100] == nil
        func isOver(_ r: StepResult) -> Bool { r.level == 0 && session.overrideBlack }
        func isBase(_ r: StepResult) -> Bool { r.level == 100 && baseShown }
        let rows: [(String, (StepResult) -> String)] = [
            ("x", { isOver($0) ? "nan" : isBase($0) ? rfmt(session.white.x, 4) : rfmt($0.xyz?.x, 4) }),
            ("y", { isOver($0) ? "nan" : isBase($0) ? rfmt(session.white.y, 4) : rfmt($0.xyz?.y, 4) }),
            ("Y", { isOver($0) ? "0" : isBase($0) ? rfmt(baseWhiteY, 3) : rfmt($0.xyz?.Y, 3) }),
            ("Delta E", { isOver($0) ? "" : isBase($0) ? "0.0" : rfmt($0.deltaE, 1) }),
            ("delta xy", { isOver($0) ? "" : isBase($0) ? rfmt(0, 4) : rfmt($0.deltaxy, 4) }),
            ("Y target", { rfmt($0.targetY, 3) }),
            ("R %", { rfmt($0.balance?[0], 1) }),
            ("G %", { rfmt($0.balance?[1], 1) }),
            ("B %", { rfmt($0.balance?[2], 1) }),
            ("Gamma", { rfmt($0.gamma, 2) }),
            ("CCT K", { rfmt($0.cct, 0) }),
        ]
        let summary = "Average gamma: \(rfmt(session.averageGamma, 2).isEmpty ? "—" : rfmt(session.averageGamma, 2))   "
            + "Contrast: \(contrastText)   Average dE: \(rfmt(session.averageDeltaE, 2).isEmpty ? "—" : rfmt(session.averageDeltaE, 2))   "
            + "Max dE: \(rfmt(session.maxDeltaE, 2).isEmpty ? "—" : rfmt(session.maxDeltaE, 2))"
        return VStack(alignment: .leading, spacing: 4) {
            Text("Gray scale").font(.system(size: 13, weight: .bold))
            Text(summary).font(.system(size: 9, design: .monospaced))
            // Gray scales of more than 11 points are printed in blocks of 11 columns
            ForEach(Array(stride(from: 0, to: results.count, by: 11)), id: \.self) { start in
                let part = Array(results[start..<min(start + 11, results.count)])
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        headerCell("% White", width: 70)
                        ForEach(part) { r in headerCell(Reference.label(r.level)) }
                        // Keep the columns of a short last block as wide as the others
                        ForEach(part.count..<11, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, minHeight: 16) }
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            labelCell(row.0)
                            ForEach(part) { r in
                                let de: Double? = row.0 == "Delta E" && !isOver(r) ? (isBase(r) ? 0 : r.deltaE) : nil
                                valueCell(row.1(r), fill: de.map(reportDeltaEColor))
                            }
                            ForEach(part.count..<11, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, minHeight: 15) }
                        }
                    }
                }
                .overlay(Rectangle().stroke(Color.gray))
            }
        }
    }

    private var contrastText: String {
        guard let c = session.contrast else { return "—" }
        return c.isInfinite ? "Infinity:1" : String(format: "%.0f:1", c)
    }

    // MARK: Colors

    private var colorSection: some View {
        let results = session.patchResults
        let rows: [(String, (PatchResult) -> String)] = [
            ("x", { rfmt($0.xyz?.x, 4) }),
            ("y", { rfmt($0.xyz?.y, 4) }),
            ("Y", { rfmt($0.xyz?.Y, 3) }),
            ("Delta E", { rfmt($0.deltaE, 1) }),
            ("delta xy", { rfmt($0.deltaxy, 4) }),
            ("delta L", { $0.deltaLText }),
            ("Ref x", { rfmt($0.reference.x, 4) }),
            ("Ref y", { rfmt($0.reference.y, 4) }),
        ]
        let d = session.colorDeltaEs
        let summary = "Average dE: \(d.isEmpty ? "—" : rfmt(d.reduce(0, +) / Double(d.count), 2))   Max dE: \(d.max().map { rfmt($0, 2) } ?? "—")   "
            + "Reference: \(session.standard.shortName) primaries, 100% saturation"
        return VStack(alignment: .leading, spacing: 4) {
            Text("Primaries and secondaries").font(.system(size: 13, weight: .bold))
            Text(summary).font(.system(size: 9, design: .monospaced))
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    headerCell("Color", width: 70)
                    ForEach(results) { r in headerCell(r.patch.rawValue, tint: tint(r.patch)) }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        labelCell(row.0)
                        ForEach(results) { r in
                            let de: Double? = row.0 == "Delta E" ? r.deltaE : nil
                            valueCell(row.1(r), fill: de.map(reportDeltaEColor))
                        }
                    }
                }
            }
            .overlay(Rectangle().stroke(Color.gray))
        }
    }

    private func tint(_ p: PatchColor) -> Color {
        switch p {
        case .red: return Color(red: 240 / 255, green: 200 / 255, blue: 200 / 255)
        case .green: return Color(red: 200 / 255, green: 240 / 255, blue: 200 / 255)
        case .blue: return Color(red: 200 / 255, green: 200 / 255, blue: 240 / 255)
        case .yellow: return Color(red: 240 / 255, green: 240 / 255, blue: 200 / 255)
        case .cyan: return Color(red: 200 / 255, green: 240 / 255, blue: 240 / 255)
        case .magenta: return Color(red: 240 / 255, green: 200 / 255, blue: 240 / 255)
        case .white: return Color(white: 0.85)
        }
    }

    // MARK: Cells

    private func headerCell(_ text: String, width: CGFloat? = nil, tint: Color = Color(white: 0.85)) -> some View {
        Text(text).font(.system(size: 9, weight: .bold))
            .frame(maxWidth: width ?? .infinity, minHeight: 16)
            .frame(width: width)
            .background(tint)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.6), lineWidth: 0.5))
    }

    private func labelCell(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .bold))
            .frame(width: 70, height: 15)
            .background(Color(white: 0.93))
            .overlay(Rectangle().stroke(Color.gray.opacity(0.6), lineWidth: 0.5))
    }

    private func valueCell(_ text: String, fill: Color?) -> some View {
        Text(text).font(.system(size: 9, design: .monospaced))
            .frame(maxWidth: .infinity, minHeight: 15, alignment: .trailing)
            .padding(.trailing, 4)
            .background(fill ?? .clear)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.6), lineWidth: 0.5))
    }
}
