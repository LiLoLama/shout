import Foundation

/// Ein Textmodell, das genau **eine** Operation beherrscht: auf eine Anweisung
/// antworten. Ob das lokal im Prozess passiert (MLX, Apple Silicon) oder über
/// HTTP bei einem selbst gewählten Anbieter, weiß nur die Implementierung.
///
/// Der Schnitt sitzt hier, weil `Formatter` ihn schon hatte: Dessen private
/// Methode `respond(system:user:temperature:)` war bereits die einzige Stelle,
/// an der überhaupt ein Modell gefragt wurde. Alles andere — Prompts, Chunking,
/// Kürzungs-Schutz, Protokoll-Erzeugung, Sprachprofil — ist anbieterunabhängig
/// und bleibt im Router. Folge: `FormattingGuard` und `TextChunker` greifen
/// automatisch auch bei Cloud-Modellen.
///
/// `: Actor` ist Absicht. Beide Implementierungen tragen veränderlichen Zustand
/// (geladenes Modell bzw. laufende Anfragen), und der Router ist selbst ein
/// Actor. Über die Actor-Beschränkung sind alle Zugriffe automatisch isoliert,
/// ohne dass irgendwo eine Sperre von Hand gehalten werden muss.
protocol TextEngine: Actor {

    /// Bereit für `respond`. Ist das `false`, fügt der Router den Rohtext ein —
    /// niemals blockieren, das gilt für lokal und extern gleichermaßen.
    var isReady: Bool { get }

    /// Läuft gerade ein Ladevorgang (lokal: Download/Initialisierung).
    var isLoading: Bool { get }

    /// Für die Oberfläche, z. B. „Gemma 4 · E4B" oder „GPT-5 mini · OpenRouter".
    var displayName: String { get }

    /// Zielgröße der Abschnitte, die diese Engine verträgt (Zeichen).
    ///
    /// Der Grund für die Unterscheidung steht in `Formatter.format`: Das kleine
    /// quantisierte Modell lässt bei langen Eingaben still Inhalt weg, deshalb
    /// wird lokal klein geschnitten. Ein Modell mit großem Kontextfenster darf
    /// größere Stücke bekommen — weniger Aufrufe heißt bei einem Anbieter
    /// weniger Latenz und weniger Kosten.
    var chunkTargetLength: Int { get }

    /// Untergrenze für den Schnitt an Satzgrenzen (siehe `TextChunker`).
    var chunkMinLength: Int { get }

    /// Lädt bzw. verbindet. `reset` erzwingt einen Neuaufbau, auch wenn schon
    /// etwas geladen ist (Modellwechsel zur Laufzeit).
    ///
    /// Wirft nicht: Ein fehlgeschlagener Ladevorgang lässt `isReady` auf `false`
    /// stehen, und der Router fügt dann eben den Rohtext ein. Das ist das
    /// bestehende Verhalten und soll so bleiben.
    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async

    /// „Aufwärmen": ein Ein-Token-Durchlauf, damit die erste echte Aufbereitung
    /// nicht spürbar länger dauert (lokal: Metal-Pipeline kompilieren).
    func warmUp() async

    /// Ein Aufruf ans Modell. Wirft bei jedem Fehler; der Router entscheidet,
    /// was das für den Text bedeutet.
    func respond(system: String, user: String, temperature: Float) async throws -> String
}
