import Foundation
import SpeakerKit

enum SpeakerSeparatorError: Error {
    case unavailable(String)
}

/// Dünne Hülle um SpeakerKit (Pyannote, CoreML): sagt, wer wann spricht.
///
/// `actor` aus demselben Grund wie beim `Transcriber`: Laden und Rechnen laufen
/// serialisiert, und zwei Aufträge können sich nicht gegenseitig den Modellzustand
/// zerreißen.
///
/// Die Modelle (~50 MB) lädt SpeakerKit beim ersten Lauf selbst von Hugging Face
/// und legt sie danach lokal ab — dieselbe Mechanik wie bei WhisperKit. Bewusst
/// erst bei der ersten Nutzung: Wer nie Sprecher trennt, lädt auch nichts.
actor SpeakerSeparator {

    private var kit: SpeakerKit?

    var isLoaded: Bool { kit != nil }

    /// Ermittelt die Sprecherabschnitte für die ganze Datei.
    ///
    /// Die Samples müssen die GESAMTE Datei sein, nicht ein Block: Sprechernummern
    /// entstehen aus einem Clustering über alles, was der Lauf gesehen hat. Blockweise
    /// wäre „Sprecher 1" in Minute 3 nicht derselbe wie in Minute 40, und das
    /// öffentliche API gibt keine Stimm-Merkmale heraus, mit denen sich die Blöcke
    /// zusammenführen ließen.
    func ranges(for samples: [Float]) async throws -> [SpeakerRange] {
        // 16 kHz mono, wie vom MediaDecoder geliefert. Unter ein paar Sekunden
        // findet Pyannote ohnehin nichts Sinnvolles.
        guard samples.count > 16_000 * 2 else { return [] }

        if kit == nil {
            do {
                kit = try await SpeakerKit(PyannoteConfig())
                try await kit?.ensureModelsLoaded()
            } catch {
                kit = nil
                throw SpeakerSeparatorError.unavailable(error.localizedDescription)
            }
        }
        guard let kit else { throw SpeakerSeparatorError.unavailable("nicht geladen") }

        let result = try await kit.diarize(audioArray: samples, options: nil, progressCallback: nil)
        return result.segments.compactMap { segment in
            // `.multiple` und `.noMatch` bewusst verwerfen: Überlappende Stimmen
            // einem einzelnen Sprecher zuzuschlagen wäre geraten.
            guard let id = segment.speaker.speakerId else { return nil }
            return SpeakerRange(speaker: id,
                                start: Double(segment.startTime),
                                end: Double(segment.endTime))
        }
    }

    /// Gibt die Modelle frei. Nach einem Auftrag sinnvoll — sie belegen sonst
    /// Speicher neben Whisper und dem Sprachmodell.
    func unload() async {
        await kit?.unloadModels()
        kit = nil
    }
}
