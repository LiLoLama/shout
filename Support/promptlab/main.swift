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
