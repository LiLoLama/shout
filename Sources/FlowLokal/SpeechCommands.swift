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
    private static let rules: [Rule] = [
        .init(pattern: "\\s*\\bneuer\\s+absatz\\b\\s*", replacement: "\n\n"),
        .init(pattern: "\\s*\\bneue\\s+zeile\\b\\s*", replacement: "\n"),
        .init(pattern: "\\s*\\bfragezeichen\\b", replacement: "?"),
        .init(pattern: "\\s*\\bausrufezeichen\\b", replacement: "!"),
        .init(pattern: "\\s*\\bdoppelpunkt\\b", replacement: ":"),
        .init(pattern: "\\s*\\b(?:semikolon|strichpunkt)\\b", replacement: ";"),
        .init(pattern: "\\s*\\bkomma\\b", replacement: ","),
        .init(pattern: "\\s*\\bpunkt\\b", replacement: "."),
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
