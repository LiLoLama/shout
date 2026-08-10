import Foundation

/// Baut aus den Antworten des Sprachmodells ein Protokoll: Zusammenfassung,
/// Kernpunkte, darunter der gegliederte Volltext.
///
/// Warum ein eigener Typ und nicht einfach der Diktat-Formatter: Der bereinigt
/// diktierten Text und ist ausdrücklich darauf getrimmt, NICHTS zu kürzen und
/// nichts umzustellen. Auf ein Whisper-Transkript losgelassen — das ohnehin schon
/// interpunktiert und weitgehend füllwortfrei ist — kommt dabei fast unverändert
/// die Eingabe heraus. Ein Protokoll ist die andere Aufgabe: verdichten, gliedern,
/// das Wichtigste nach oben holen.
///
/// Das Zerlegen der Modellantwort ist bewusst nachsichtig: Kleine quantisierte
/// Modelle halten sich nicht zuverlässig an ein Ausgabeformat. Was nicht erkannt
/// wird, landet als Text im Protokoll — lieber unstrukturiert als verloren.
enum TranscriptMinutes {

    struct Section: Equatable {
        var title: String?
        var points: [String]
        var text: String
    }

    /// Überschriften des Dokuments. Als Parameter statt über `Loc`, damit das
    /// Zusammensetzen eine reine Funktion bleibt und ohne Oberfläche testbar ist.
    struct Headings {
        let summary: String
        let points: String
        let body: String
    }

    // MARK: - Antwort des Modells zerlegen

    private static let titleMarkers = ["titel:", "überschrift:", "title:"]
    private static let pointsMarkers = ["punkte:", "kernpunkte:", "points:"]
    private static let textMarkers = ["text:", "inhalt:", "body:"]

    /// Zerlegt eine Modellantwort der Form `TITEL: … / PUNKTE: … / TEXT: …`.
    /// Fehlt jeder Marker, gilt die ganze Antwort als Text.
    static func parseSection(_ raw: String) -> Section {
        let lines = raw.components(separatedBy: .newlines)
        var title: String?
        var points: [String] = []
        var textLines: [String] = []

        enum Part { case none, points, text }
        var part = Part.none
        var sawMarker = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowered = trimmed.lowercased()

            if let marker = titleMarkers.first(where: { lowered.hasPrefix($0) }) {
                title = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if title?.isEmpty == true { title = nil }
                part = .none
                sawMarker = true
                continue
            }
            if let marker = pointsMarkers.first(where: { lowered.hasPrefix($0) }) {
                let rest = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { points.append(rest) }
                part = .points
                sawMarker = true
                continue
            }
            if let marker = textMarkers.first(where: { lowered.hasPrefix($0) }) {
                let rest = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { textLines.append(rest) }
                part = .text
                sawMarker = true
                continue
            }

            switch part {
            case .points:
                let point = stripBullet(trimmed)
                if !point.isEmpty { points.append(point) }
            case .text, .none:
                textLines.append(line)
            }
        }

        let text = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Ohne jeden Marker ist die ganze Antwort der Text — kein Grund, sie wegzuwerfen.
        return Section(title: sawMarker ? title : nil, points: points, text: text)
    }

    /// Entfernt Aufzählungszeichen: „- ", „• ", „* " und „1. ".
    private static func stripBullet(_ line: String) -> String {
        var rest = Substring(line)
        if let first = rest.first, "-•*–—".contains(first) {
            rest = rest.dropFirst()
        } else {
            // Nummerierung „12. " abtrennen, aber nur wenn wirklich ein Punkt folgt.
            let digits = rest.prefix { $0.isNumber }
            if !digits.isEmpty, rest.dropFirst(digits.count).first == "." {
                rest = rest.dropFirst(digits.count + 1)
            }
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// Sammelt die Kernpunkte aller Abschnitte ein und entdoppelt sie (ohne Rücksicht
    /// auf Groß-/Kleinschreibung — Modelle formulieren denselben Punkt gern zweimal
    /// leicht anders angeschrieben).
    static func collectPoints(from sections: [Section]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for point in sections.flatMap(\.points) {
            let key = point.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(point)
        }
        return result
    }

    // MARK: - Dokument zusammensetzen

    static func assemble(summary: String, points: [String],
                         sections: [Section], headings: Headings) -> String {
        var blocks: [String] = []

        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSummary.isEmpty {
            blocks.append("# \(headings.summary)\n\n\(cleanSummary)")
        }
        if !points.isEmpty {
            blocks.append("# \(headings.points)\n\n" + points.map { "- \($0)" }.joined(separator: "\n"))
        }

        let body = sections.compactMap { section -> String? in
            let text = section.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            guard let title = section.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return text }
            return "## \(title)\n\n\(text)"
        }
        if !body.isEmpty {
            blocks.append("# \(headings.body)\n\n" + body.joined(separator: "\n\n"))
        }

        return blocks.joined(separator: "\n\n")
    }
}
