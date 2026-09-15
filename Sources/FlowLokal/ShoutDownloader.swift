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
    /// Wohin eigene Downloads gehen.
    let basisordner: URL

    func download(id: String,
                  revision: String?,
                  matching patterns: [String],
                  useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {

        // Erst der Store: Liegt das Modell irgendwo — im eigenen Ordner oder in
        // einem durchsuchten —, wird es benutzt, nicht erneut geladen.
        if !useLatest, let vorhanden = store.aufloesen(id) {
            return vorhanden
        }

        // Sonst der echte Hub, mit unserem Ablageort. Der Aufruf ist genau der,
        // den das Makro #hubDownloader erzeugt (siehe HuggingFaceIntegrationMacros.swift,
        // Zeile 46 ff.) — nur mit gesetztem Cache-Verzeichnis statt HubCache.default.
        guard let repoID = Repo.ID(rawValue: id) else {
            throw ShoutDownloaderError.ungueltigeKennung(id)
        }
        let client = HubClient(cache: HubCache(cacheDirectory: basisordner))
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
