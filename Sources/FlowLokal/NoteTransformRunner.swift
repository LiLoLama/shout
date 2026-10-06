import AppKit

/// Führt Transforms auf einer Notiz aus: sichert vorher einen Stand, sperrt den
/// Text, ersetzt Auswahl bzw. Text in einem Rückgängig-Schritt und meldet das
/// Ergebnis über `session.toolNotice`. Esc oder „Abbrechen“ lassen den Text, wie er war.
@MainActor
final class NoteTransformRunner: ObservableObject {

    /// Gibt es ein Textmodell? Sonst ist der Zauberstab aus.
    @Published var isAvailable = false
    /// Die zuletzt gesprochene Anweisung — im Menü als „Zuletzt: …“.
    @Published private(set) var lastInstruction: String? {
        didSet { defaults.set(lastInstruction, forKey: Self.lastKey) }
    }

    private static let lastKey = "scratchpad.lastInstruction"
    private let defaults: UserDefaults
    private let saveVersion: (NoteEditorSession) -> Void
    private let copy: (String) -> Void
    private let transform: (String, String) async throws -> String

    /// `transform(text, anweisung)` — im Betrieb `Formatter.transform`.
    init(defaults: UserDefaults = .standard,
         saveVersion: @escaping (NoteEditorSession) -> Void = { _ in },
         copy: @escaping (String) -> Void = NoteTransformRunner.copyToClipboard,
         transform: @escaping (String, String) async throws -> String) {
        self.defaults = defaults
        self.saveVersion = saveVersion
        self.copy = copy
        self.transform = transform
        lastInstruction = defaults.string(forKey: Self.lastKey)
    }

    nonisolated static func copyToClipboard(_ text: String) {
        let ablage = NSPasteboard.general
        ablage.clearContents()
        ablage.setString(text, forType: .string)
    }

    /// Startet einen Transform. `nil`, wenn keiner startet (schon einer läuft,
    /// Platzhalter, nichts zu bearbeiten, zu lang) — dann steht der Grund im Balken.
    @discardableResult
    func run(instruction: String, working: String, done: String,
             on session: NoteEditorSession) -> Task<Void, Never>? {
        guard !session.isTransforming, session.status != .placeholder else { return nil }
        // Erst sichern: Ein Konflikt oder Neuladen beim Sichern ersetzt den Text.
        // Bereich und Text kommen deshalb aus dem Stand danach.
        session.flush()
        let ns = session.note.body as NSString
        let auswahl = session.lastSelection
        let bereich = auswahl.length > 0 && auswahl.location >= 0 && NSMaxRange(auswahl) <= ns.length
            ? auswahl : NSRange(location: 0, length: ns.length)
        let text = ns.substring(with: bereich)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            session.showToolNotice(.failed(Loc.t("Kein Text zum Bearbeiten.")))
            return nil
        }
        guard text.count <= TransformPrompt.maxLength else {
            session.showToolNotice(.failed(Self.message(for: TransformError.tooLong)))
            return nil
        }
        // Die Version ist, was vor dem Transform in der Datei stand.
        saveVersion(session)
        let vorher = session.note.body
        let task = Task { [transform, copy] in
            do {
                let ergebnis = try await transform(text, instruction)
                guard !Task.isCancelled else { return }
                session.endTransform(nil)
                guard session.note.body == vorher else {
                    // Von außen neu geladen (Konflikt): nicht hineinschreiben, aber
                    // das Ergebnis auch nicht wegwerfen.
                    copy(ergebnis)
                    session.showToolNotice(.failed(Loc.t("Der Text hat sich inzwischen geändert. Das Ergebnis liegt in der Zwischenablage.")))
                    return
                }
                guard session.replace(bereich, with: ergebnis) else {
                    copy(ergebnis)
                    session.showToolNotice(.failed(Loc.t("Das Ergebnis ließ sich nicht einsetzen. Es liegt in der Zwischenablage.")))
                    return
                }
                // Wurde der Tab inzwischen geschlossen, läuft kein Zeitgeber mehr:
                // sofort sichern, sonst ginge das Ergebnis verloren.
                session.flush()
                if session.hasUnsavedText {
                    copy(ergebnis)
                    session.showToolNotice(.failed(Loc.t("Das Ergebnis ließ sich nicht sichern. Es liegt in der Zwischenablage.")))
                    return
                }
                session.showToolNotice(.done(done, undo: NoteEditorSession.ToolUndo(before: vorher, after: session.note.body)))
            } catch {
                guard !Task.isCancelled else { return }
                session.endTransform(.failed(Self.message(for: error)))
            }
        }
        session.beginTransform(working) { task.cancel() }
        return task
    }

    /// Eine frei formulierte Anweisung (per Sprache oder „Zuletzt: …“). Wird gemerkt.
    @discardableResult
    func runInstruction(_ raw: String, on session: NoteEditorSession) -> Task<Void, Never>? {
        let anweisung = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !anweisung.isEmpty else { return nil }
        lastInstruction = anweisung
        return run(instruction: anweisung,
                   working: Loc.f("„%@“ wird angewendet …", Self.short(anweisung)),
                   done: Loc.t("Anweisung angewendet"),
                   on: session)
    }

    static func message(for error: Error) -> String {
        switch error as? TransformError {
        case .noModel: return Loc.t("Unter Modelle ein Textmodell wählen")
        case .tooLong: return Loc.t("Zu lang für das gewählte Modell")
        case .emptyResult: return Loc.t("Das Modell hat nichts zurückgegeben. Der Text bleibt, wie er war.")
        case .timedOut: return Loc.t("Das Modell hat zu lange gebraucht. Der Text bleibt, wie er war.")
        case .failed, .none: return Loc.t("Das Modell hat nicht geantwortet. Der Text bleibt, wie er war.")
        }
    }

    /// Für Menü und Balken: höchstens 40 Zeichen.
    nonisolated static func short(_ s: String) -> String {
        s.count <= 40 ? s : String(s.prefix(39)) + "…"
    }
}
