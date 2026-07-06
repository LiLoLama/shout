import Foundation

/// Deterministischer Sprachbefehl-Layer (Dragon-Stil): wandelt gesprochene
/// Marker wie „Komma", „Punkt" oder „neue Zeile" in echte Satzzeichen/Umbrüche.
///
/// Wird — wenn in den Einstellungen aktiviert — auf den Rohtext angewandt, BEVOR
/// der optionale KI-Formatter läuft. So funktioniert es auch bei ausgeschalteter
/// Formatierung und bei sehr kurzen Diktaten (unterhalb der LLM-Schwelle).
enum SpeechCommands {

    private struct Rule { let pattern: String; let replacement: String }

    // Reihenfolge: mehrteilige/spezifische Marker zuerst. Groß-/Kleinschreibung egal.
    // Grenzen über Lookarounds statt \b: schließt angrenzende Buchstaben, Ziffern
    // UND Bindestriche aus — sonst würde „Punkt-zu-Punkt" zu „.-zu-." zerfallen.
    private static let L = "(?<![\\p{L}\\p{N}-])"   // links: kein Wortzeichen/Bindestrich
    private static let R = "(?![\\p{L}\\p{N}-])"    // rechts: dito
    // „Punkt eins/zwei/…" ist ein Aufzählungs-Marker, auf den der Formatter baut —
    // dann NICHT durch „." ersetzen.
    private static let notEnumeration = "(?!\\s+(?:eins|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|\\d))"

    private static let rules: [Rule] = [
        .init(pattern: "\\s*\(L)neuer\\s+absatz\(R)\\s*", replacement: "\n\n"),
        .init(pattern: "\\s*\(L)neue\\s+zeile\(R)\\s*", replacement: "\n"),
        .init(pattern: "\\s*\(L)fragezeichen\(R)", replacement: "?"),
        .init(pattern: "\\s*\(L)ausrufezeichen\(R)", replacement: "!"),
        .init(pattern: "\\s*\(L)doppelpunkt\(R)", replacement: ":"),
        .init(pattern: "\\s*\(L)(?:semikolon|strichpunkt)\(R)", replacement: ";"),
        .init(pattern: "\\s*\(L)komma\(R)", replacement: ","),
        .init(pattern: "\\s*\(L)punkt\(R)\(notEnumeration)", replacement: "."),
    ]

    private static let compiled: [(NSRegularExpression, String)] = rules.compactMap {
        guard let re = try? NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]) else { return nil }
        return (re, $0.replacement)
    }

    static func apply(to text: String) -> String {
        var result = text
        for (regex, replacement) in compiled {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
