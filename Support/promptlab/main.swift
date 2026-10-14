import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Prüfstand für die Prompts der Aufbereitung: schickt echte Fehlfälle durch das
/// gewählte MLX-Modell und zeigt, was herauskommt — alter Prompt gegen neuen.
/// Nicht Teil der App; `xcodebuild -scheme promptlab` baut es bei Bedarf.

let faelle: [(name: String, text: String)] = [
    ("Link erstellen",
     "Kannst du mir für dieses Meeting einen Link erstellen?"),
    ("Logos ergänzen",
     "wunderbar das passt jetzt super kannst du bitte das logo von elotech gmbh und das logo von prefa noch aus dem internet raussuchen und ergänzen ganz unten"),
    ("Absage-Auslöser",
     "Gib mir jetzt ein paar Phrasen, die ich dir sagen kann, damit das besser klingt."),
    ("Bild-Frage",
     "Kannst du mir basierend auf dem Bild herausfinden, wer diese Personen genau sind?"),
    ("Normalfall (Gegenprobe)",
     "also äh wir müssten halt noch quasi die zahlen vom letzten quartal durchgehen und dann sozusagen die präsentation fertig machen bevor das meeting am donnerstag ist"),
]

/// Der Prompt-Stand VOR dieser Änderung: Regeln als System-Prompt, Transkript
/// blank als Nutzer-Nachricht.
let alterSystemPrompt = """
Du bist ein Formatierer für diktierten Text (meist Deutsch oder Englisch). Deine Aufgabe ist NICHT, \
Fragen zu beantworten oder Inhalte hinzuzufügen, sondern den Rohtext aus einer \
Spracherkennung zu bereinigen und sauber zu formatieren.

Regeln:
- Antworte in exakt derselben Sprache wie die Eingabe.
- Entferne Füllwörter (äh, ähm, also, halt, quasi, sozusagen), Wiederholungen und Versprecher.
- Setze korrekte Interpunktion und Groß-/Kleinschreibung.
- Behalte Wortwahl, Bedeutung und Sprache exakt bei. Erfinde nichts dazu und kürze inhaltlich nicht.

Gib AUSSCHLIESSLICH den bereinigten Text aus — keine Erklärung, keine Anführungszeichen, kein Codeblock.
"""

let modelID = UserDefaults.standard.string(forKey: "formatModel") ?? "mlx-community/gemma-4-e4b-it-4bit"
FileHandle.standardError.write("Lade \(modelID) …\n".data(using: .utf8)!)

let container = try await #huggingFaceLoadModelContainer(
    configuration: ModelConfiguration(id: modelID)
) { _ in }

func lauf(system: String, user: String) async throws -> String {
    let session = ChatSession(container, instructions: system,
                              generateParameters: GenerateParameters(temperature: 0.2))
    return try await session.respond(to: user).trimmingCharacters(in: .whitespacesAndNewlines)
}

func urteil(_ input: String, _ output: String) -> String {
    switch FormattingGuard.check(input: input, output: output) {
    case .ok: return "ok"
    case .unrelated(let s): return "VERWORFEN (nur \(s) % aus dem Diktat)"
    case .truncated(let i, let o): return "VERWORFEN (\(i)→\(o) Wörter)"
    }
}

if CommandLine.arguments.contains("luna") {
    try await lunaVergleich()
    exit(0)
}

let durchgaenge = 4

for (name, text) in faelle {
    print("\n════ \(name)")
    print("DIKTAT: \(text)")
    for (label, system, user) in [("ALT", alterSystemPrompt, text),
                                  ("NEU", FormatterPrompt.system(for: nil, termHint: nil),
                                   FormatterPrompt.user(for: text))] {
        print("  \(label):")
        for i in 1...durchgaenge {
            let out = try await lauf(system: system, user: user)
            let kurz = out.count > 88 ? String(out.prefix(88)) + "…" : out
            print("    \(i). \(kurz)   [\(urteil(text, out))]")
        }
    }
}

// MARK: - Gemma gegen Luna über das ChatGPT-Abo

/// `promptlab luna`: dieselben Diktate durch das lokale Gemma und durch Luna
/// über das ChatGPT-Abo, beide mit dem Prompt der App. Für Luna läuft dieselbe
/// Engine wie in der App (`ChatGPTPlanTextEngine`) — also ohne `temperature`
/// und mit `reasoning.effort: none`.
///
/// Das Zugangstoken kommt aus der Anmeldung der App. Erneuert wird hier
/// **nie**: Das Refresh-Token wechselt dabei, und eine zweite Erneuerung neben
/// der App könnte die Anmeldung kaputt machen. Ist das Token abgelaufen, in
/// shout. „Verbindung testen“ drücken — das erneuert es — und neu starten.
///
/// Die echten Diktate kommen aus `history.json` und landen nur im Bericht auf
/// der Platte, nie im Repo.
func lunaVergleich() async throws {
    let lauefe = 3
    guard let sitzung = ChatGPTCredentialStore.loadSession(),
          !sitzung.needsRefresh(now: Date())
    else {
        FileHandle.standardError.write(Data("Kein gültiges Abo-Token. In shout. unter Modelle „Verbindung testen“ drücken und neu starten.\n".utf8))
        exit(2)
    }
    let token = sitzung.accessToken
    let luna = ChatGPTPlanTextEngine(model: "gpt-6-luna", token: { erneuern in
        if erneuern { throw RemoteProviderError.signInRequired }
        return token
    })

    var alle = faelle
    alle.append(contentsOf: echteDiktate(anzahl: 12))

    struct Messung { var verworfen = 0; var fehler = 0; var zeiten: [Double] = [] }
    var gemma = Messung(), lunaM = Messung()

    for (name, text) in alle {
        print("\n════ \(name) (\(text.count) Zeichen)")
        print("DIKTAT: \(text)")
        let system = FormatterPrompt.system(for: nil, termHint: nil)
        let user = FormatterPrompt.user(for: text)

        for (label, istLuna) in [("GEMMA", false), ("LUNA", true)] {
            print("  \(label):")
            for i in 1...lauefe {
                let start = Date()
                do {
                    let out = istLuna
                        ? try await luna.respond(system: system, user: user, temperature: 0.2)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        : try await lauf(system: system, user: user)
                    let dauer = Date().timeIntervalSince(start)
                    let u = urteil(text, out)
                    if istLuna { lunaM.zeiten.append(dauer) } else { gemma.zeiten.append(dauer) }
                    if u != "ok" { if istLuna { lunaM.verworfen += 1 } else { gemma.verworfen += 1 } }
                    print("    \(i). [\(u) · \(String(format: "%.1f", dauer)) s] \(out)")
                } catch {
                    if istLuna { lunaM.fehler += 1 } else { gemma.fehler += 1 }
                    let beschreibung = (error as? RemoteProviderError)?.logDescription ?? "\(error)"
                    print("    \(i). FEHLER: \(beschreibung)")
                    if error as? RemoteProviderError == .planLimitReached { break }
                }
            }
        }
    }

    func median(_ z: [Double]) -> String {
        guard !z.isEmpty else { return "–" }
        let s = z.sorted()
        return String(format: "%.1f s", s[s.count / 2])
    }
    let gesamt = alle.count * lauefe
    print("\n════ ZUSAMMENFASSUNG (\(alle.count) Fälle × \(lauefe) Läufe = \(gesamt) je Modell)")
    print("GEMMA: verworfen \(gemma.verworfen), Fehler \(gemma.fehler), Median \(median(gemma.zeiten)), max \(String(format: "%.1f s", gemma.zeiten.max() ?? 0))")
    print("LUNA:  verworfen \(lunaM.verworfen), Fehler \(lunaM.fehler), Median \(median(lunaM.zeiten)), max \(String(format: "%.1f s", lunaM.zeiten.max() ?? 0))")
}

/// Echte Diktate aus dem Verlauf, gleichmäßig über die Längen verteilt — vom
/// kurzen Satz bis zum langen Absatz. Nur Einträge, bei denen die Aufbereitung
/// damals etwas geändert hat (`raw` steht dann neben `text`).
func echteDiktate(anzahl: Int) -> [(name: String, text: String)] {
    struct Eintrag: Decodable { let raw: String?; let text: String }
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/shout/history.json")
    guard let data = try? Data(contentsOf: url),
          let eintraege = try? JSONDecoder().decode([Eintrag].self, from: data)
    else { return [] }
    let roh = eintraege.compactMap { e -> String? in
        guard let r = e.raw, r != e.text, r.count >= 40 else { return nil }
        return r
    }.sorted { $0.count < $1.count }
    guard roh.count >= anzahl else { return roh.enumerated().map { ("Verlauf \($0.offset + 1)", $0.element) } }
    return (0..<anzahl).map { i in
        let index = (roh.count - 1) * i / (anzahl - 1)
        return ("Verlauf \(i + 1)", roh[index])
    }
}
