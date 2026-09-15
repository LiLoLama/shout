import Foundation
import MLXLMCommon
import HuggingFace

/// Setzt `MLXLMCommon.Downloader` um und schiebt den `ModelStore` davor.
///
/// Das Protokoll hat genau eine Methode und gibt ein lokales Verzeichnis
/// zurück — dadurch hängen „vorhandenes Modell mitbenutzen“ und „woanders hin
/// herunterladen“ an DERSELBEN Stelle statt an zweien.
///
/// Warum nicht das Makro `#huggingFaceLoadModelContainer(configuration:)`:
/// Es nimmt den Standard-Hub und lässt sich nicht umlenken. Der ausgeschriebene
/// Weg über `loadModelContainer(from:using:configuration:)` ist eine Zeile
/// länger und die einzige Möglichkeit, hier einzugreifen.
struct ShoutDownloader: Downloader {

    let store: ModelStore
    /// Wohin eigene Downloads gehen — `nil`, solange nichts eingestellt ist.
    let gewaehlterBasisordner: URL?

    func download(id: String,
                  revision: String?,
                  matching patterns: [String],
                  useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {

        // Wohin shout. selbst ablegt: mit Wahl der gewählte Ordner, ohne Wahl
        // der Standard-Cache des Hubs. Genau dieser Ordner geht unten auch an
        // den `HubClient` — die beiden dürfen nicht auseinanderlaufen.
        let eigenerDownloadOrdner = gewaehlterBasisordner ?? HubCache.default.cacheDirectory

        // Erst der Store — aber nur für FREMDE Ordner (LM Studio, von Hand
        // abgelegte Modelle). Dort weiß niemand mehr als wir, und ein
        // Mitbenutzen erspart denselben Download ein zweites Mal.
        //
        // Im EIGENEN Cache entscheidet weiterhin der `HubClient`: Er kennt die
        // Snapshot-Metadaten und damit jede erwartete Datei (Shards, *.json,
        // *.jinja) und vervollständigt einen abgebrochenen Download. Die
        // Prüfung des Stores ist dagegen schwach (config.json plus irgendeine
        // *.safetensors) — sie hier vorzuschalten machte jeden halben Snapshot
        // dauerhaft und lautlos zum "fertigen" Modell.
        if !useLatest,
           let vorhanden = store.abkuerzbarerFund(id, eigenerDownloadOrdner: eigenerDownloadOrdner) {
            // Nur HIER wird verknüpft, und zwar genau dann, wenn ein FREMDER
            // Ordner tatsächlich mitbenutzt wird: Dieser Pfad kann verschwinden
            // (Platte ab, LM Studio aufgeräumt), ohne dass shout. etwas dafür
            // kann. Erst die Verknüpfung macht daraus später `nichtAuffindbar`
            // statt `nichtVorhanden` — sonst böte die Oberfläche einen
            // Multi-GB-Download an, obwohl bloß eine Platte fehlt.
            //
            // Unterhalb dieser Stelle lädt shout. in den EIGENEN Ordner. Dort
            // wird nichts gemerkt: Ein eigener Download ist kein fremdes
            // Modell, und die Suche findet ihn von allein wieder.
            //
            // `ModelPaths.verknuepfungMerken` schreibt ausschließlich die
            // Verknüpfungen — der Basisordner bleibt unberührt, auch wenn hier
            // mehrere Downloads gleichzeitig durchlaufen.
            ModelPaths.verknuepfungMerken(id, pfad: vorhanden, in: .standard)
            return vorhanden
        }

        // Sonst der echte Hub. Der Aufruf ist genau der, den das Makro
        // #hubDownloader erzeugt (siehe HuggingFaceIntegrationMacros.swift,
        // Zeile 46 ff.) — nur mit gesetztem Cache-Verzeichnis, WENN einer
        // gewählt wurde.
        //
        // Ohne Wahl bleibt es beim unveränderten Standardweg (`HubClient()`
        // nimmt `HubCache.default`). Einen eigenen Pfad zu erfinden wäre
        // teuer: WhisperKit und MLX haben unterschiedliche Standardorte, und
        // jede Verschiebung bedeutet für Bestandsnutzer einen Neu-Download im
        // Gigabyte-Bereich.
        guard let repoID = Repo.ID(rawValue: id) else {
            throw ShoutDownloaderError.ungueltigeKennung(id)
        }
        let client = gewaehlterBasisordner.map { HubClient(cache: HubCache(cacheDirectory: $0)) }
            ?? HubClient()
        return try await client.downloadSnapshot(
            of: repoID,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in progressHandler(progress) })
    }
}

enum ShoutDownloaderError: Error {
    case ungueltigeKennung(String)
}
