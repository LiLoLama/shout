import Foundation

/// Versionsnummer wie „1.13.0" — verglichen Stelle für Stelle als Zahl;
/// fehlende Stellen gelten als 0 (1.13 == 1.13.0).
struct AppVersion: Comparable, Hashable, CustomStringConvertible {
    let parts: [Int]

    init?(_ string: String) {
        let teile = string.trimmingCharacters(in: .whitespaces)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard !teile.isEmpty, teile.count <= 4 else { return nil }
        var zahlen: [Int] = []
        for teil in teile {
            guard !teil.isEmpty, teil.allSatisfy({ $0.isASCII && $0.isNumber }), let zahl = Int(teil) else { return nil }
            zahlen.append(zahl)
        }
        parts = zahlen
    }

    private var normalized: [Int] {
        var p = parts
        while p.count > 1, p.last == 0 { p.removeLast() }
        return p
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { a.normalized == b.normalized }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        let x = a.parts + Array(repeating: 0, count: n - a.parts.count)
        let y = b.parts + Array(repeating: 0, count: n - b.parts.count)
        return x.lexicographicallyPrecedes(y)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(normalized) }

    var description: String { parts.map(String.init).joined(separator: ".") }
}

/// Eine Version aus `CHANGELOG.md`.
struct ChangelogEntry: Equatable, Identifiable {
    let version: AppVersion
    let date: String
    /// `zeigen: ja` — erscheint einmal im Fenster „Neu in shout.".
    let highlight: Bool
    /// Name einer Animation in `Explainers/<name>.html`.
    let video: String?
    let german: String
    let english: String

    var id: String { version.description }

    func text(german isGerman: Bool) -> String { isGerman ? german : english }
}

/// Liest `CHANGELOG.md`. Ein fehlerhafter Abschnitt wird übersprungen (und
/// geloggt) — der Rest bleibt lesbar, die App stürzt nie an der Datei ab.
enum ChangelogParser {

    static func parse(_ text: String) -> [ChangelogEntry] {
        let zeilen = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var abschnitte: [[String]] = []
        for zeile in zeilen {
            if zeile.hasPrefix("## ") {
                abschnitte.append([zeile])
            } else if !abschnitte.isEmpty {
                abschnitte[abschnitte.count - 1].append(zeile)
            }
        }
        var ergebnis: [ChangelogEntry] = []
        var gesehen = Set<AppVersion>()
        for abschnitt in abschnitte {
            guard let eintrag = entry(abschnitt) else {
                NSLog("shout: Abschnitt im Update-Log übersprungen: \(abschnitt.first ?? "")")
                continue
            }
            guard gesehen.insert(eintrag.version).inserted else { continue }
            ergebnis.append(eintrag)
        }
        return ergebnis.sorted { $0.version > $1.version }
    }

    /// Die mitgelieferte Datei. `nil`, wenn sie fehlt oder nicht lesbar ist.
    static func loadBundled(_ bundle: Bundle = .main) -> [ChangelogEntry]? {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    // MARK: - Intern

    private static func entry(_ zeilen: [String]) -> ChangelogEntry? {
        let kopf = zeilen[0].dropFirst(3).trimmingCharacters(in: .whitespaces)
        var teile = kopf.components(separatedBy: " — ")
        if teile.count != 2 { teile = kopf.components(separatedBy: " - ") }
        guard teile.count == 2, let version = AppVersion(teile[0]), isDate(teile[1]) else { return nil }

        var highlight: Bool?
        var video: String?
        var videoUngueltig = false
        var bloecke: [String: [String]] = [:]
        var aktuell: String?
        for zeile in zeilen.dropFirst() {
            if zeile.hasPrefix("### ") {
                let name = zeile.dropFirst(4).trimmingCharacters(in: .whitespaces)
                aktuell = name
                bloecke[name] = []
                continue
            }
            if let aktuell {
                bloecke[aktuell, default: []].append(zeile)
                continue
            }
            let t = zeile.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("zeigen:") {
                switch t.dropFirst(7).trimmingCharacters(in: .whitespaces).lowercased() {
                case "ja": highlight = true
                case "nein": highlight = false
                default: highlight = nil
                }
            } else if t.hasPrefix("video:") {
                let name = t.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if name.isEmpty {
                    video = nil
                } else if name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) {
                    video = name
                } else {
                    videoUngueltig = true
                }
            }
        }
        guard let highlight, !videoUngueltig,
              let deutsch = block(bloecke["Deutsch"]), let englisch = block(bloecke["English"]) else { return nil }
        return ChangelogEntry(version: version, date: teile[1].trimmingCharacters(in: .whitespaces),
                              highlight: highlight, video: video, german: deutsch, english: englisch)
    }

    private static func block(_ zeilen: [String]?) -> String? {
        guard let zeilen else { return nil }
        let text = zeilen.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// „JJJJ-MM-TT".
    private static func isDate(_ s: String) -> Bool {
        let t = Array(s.trimmingCharacters(in: .whitespaces))
        guard t.count == 10, t[4] == "-", t[7] == "-" else { return false }
        return t.enumerated().allSatisfy { i, c in i == 4 || i == 7 || (c.isASCII && c.isNumber) }
    }
}
