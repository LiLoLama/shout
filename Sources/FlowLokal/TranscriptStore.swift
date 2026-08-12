import Foundation

/// Das gesicherte Ergebnis eines Mitschnitts.
///
/// Die Segmente kommen mit, obwohl die iPhone-Oberfläche sie heute nicht anzeigt:
/// Sie sind die Grundlage für Untertitel, und sie später aus dem fertigen Text
/// zurückzurechnen wäre unmöglich.
struct StoredTranscript: Codable, Equatable {
    var rawText: String
    var formattedText: String
    var segments: [TranscriptSegment]
    var duration: Double
    var speakerNote: String?
}

/// Legt das Transkript **neben die Audiodatei** — `Meeting 2026-08-12 09-15.m4a`
/// bekommt `Meeting 2026-08-12 09-15.json`.
///
/// Kein zentraler Index: Der müsste gepflegt werden und kann von der Wirklichkeit
/// abweichen. So gehört das Ergebnis zur Aufnahme wie ihr Dateiname — wer die
/// Aufnahme entfernt, entfernt beides, und es kann nichts verwaisen.
///
/// Gesichert wird ausschließlich für **eigene Mitschnitte**. Ausgewählte Dateien
/// liegen beim Nutzer, dort hätte die App nichts abzulegen — und am Mac steht auf
/// der Seite ausdrücklich, dass Ergebnisse nicht automatisch gespeichert werden.
/// Weil es dort keine Mitschnitte gibt, bleibt diese Zusage von allein wahr.
enum TranscriptStore {

    static func sidecar(for audio: URL) -> URL {
        audio.deletingPathExtension().appendingPathExtension("json")
    }

    static func save(_ transcript: StoredTranscript, for audio: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(transcript)
            try data.write(to: sidecar(for: audio), options: .atomic)
        } catch {
            // Ein verlorenes Transkript ist ärgerlich, aber kein Grund, den
            // fertigen Auftrag scheitern zu lassen — der Text steht ja da.
            NSLog("shout: Transkript konnte nicht gesichert werden: \(error)")
        }
    }

    static func load(for audio: URL) -> StoredTranscript? {
        guard let data = try? Data(contentsOf: sidecar(for: audio)) else { return nil }
        return try? JSONDecoder().decode(StoredTranscript.self, from: data)
    }

    static func remove(for audio: URL) {
        try? FileManager.default.removeItem(at: sidecar(for: audio))
    }
}
