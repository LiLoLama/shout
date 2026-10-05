import Foundation

/// Die Eingangs-Notiz: Diktate der Eingangs-Taste werden unten angehängt, unter
/// einer Überschrift pro Tag. Rein — der Aufrufer hängt das Ergebnis ans Ende.
enum NoteInbox {

    /// „## Montag, 5. Oktober 2026“ bzw. „## Monday, October 5, 2026“.
    static func dayHeading(for date: Date, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMMyyyy")
        return "## " + formatter.string(from: date)
    }

    /// Was ans Ende von `body` gehört: bei Bedarf eine Leerzeile und die neue
    /// Tagesüberschrift, dann „- **14:32** Diktat“. Weitere Zeilen eines
    /// Diktats stehen eingerückt unter dem Spiegelstrich.
    static func appendix(to body: String, text: String, date: Date, locale: Locale,
                         timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let gesprochen = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gesprochen.isEmpty else { return "" }
        let ueberschrift = dayHeading(for: date, locale: locale, timeZone: timeZone)
        let uhr = DateFormatter()
        uhr.locale = Locale(identifier: "en_US_POSIX")
        uhr.timeZone = timeZone
        uhr.dateFormat = "HH:mm"

        let zeilen = gesprochen
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        var eintrag = "- **\(uhr.string(from: date))** " + (zeilen.first ?? "")
        for zeile in zeilen.dropFirst() { eintrag += "\n  " + zeile }

        let anfang = body.isEmpty
        var ergebnis = ""
        if !anfang && body.last?.isNewline != true { ergebnis += "\n" }
        if lastHeading(in: body) != ueberschrift {
            if !anfang { ergebnis += "\n" }
            ergebnis += ueberschrift + "\n"
        }
        return ergebnis + eintrag + "\n"
    }

    /// Die letzte „## “-Überschrift im Text.
    static func lastHeading(in body: String) -> String? {
        body.split(whereSeparator: \.isNewline)
            .last { $0.hasPrefix("## ") }
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}
