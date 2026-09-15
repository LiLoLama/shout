import Foundation

/// Wo ein Modell steht — und ob es überhaupt noch da ist.
///
/// `nichtAuffindbar` ist der Zustand, der diese Erweiterung überhaupt
/// rechtfertigt: Ein verknüpftes Modell aus einem fremden Ordner kann
/// verschwinden, ohne dass shout. etwas dafür kann (Platte ab, Ordner
/// aufgeräumt). Das ist etwas anderes als "nie da gewesen", und die Oberfläche
/// muss es anders beantworten.
enum ModelZustand: Equatable {
    case nichtVorhanden
    case eigen(URL)
    case fremd(URL)
    case nichtAuffindbar
}

/// Beantwortet genau eine Frage: **Welcher Pfad gehört zu welcher Kennung?**
///
/// Lädt nichts herunter und löscht nichts — dadurch ist er vollständig gegen
/// einen Ordner mit Attrappen prüfbar, ohne WhisperKit oder MLX zu berühren.
///
/// Die Reihenfolge ist fest: erst der Basisordner, dann die Suchordner in ihrer
/// Reihenfolge, erster Treffer gewinnt. Keine Heuristik — bei Namensgleichheit
/// muss vorhersagbar sein, was geladen wird, und die Reihenfolge ist in der
/// Oberfläche sichtbar.
struct ModelStore {

    let basisordner: URL
    let suchordner: [URL]

    init(basisordner: URL, suchordner: [URL]) {
        self.basisordner = basisordner
        self.suchordner = suchordner
    }

    /// Alle Orte in Vorrangreihenfolge. Doppelte Einträge fallen heraus —
    /// wer den Basisordner zusätzlich als Suchordner einträgt, soll jedes
    /// Modell trotzdem nur einmal sehen.
    var orteInReihenfolge: [URL] {
        var gesehen = Set<String>()
        return ([basisordner] + suchordner).filter { ordner in
            gesehen.insert(ordner.standardizedFileURL.path).inserted
        }
    }

    /// Ordnername im Python-Format des Hugging-Face-Caches
    /// (`models--<org>--<repo>`) — so legt `HubCache` ab, und so sieht
    /// `~/.cache/huggingface/hub` aus.
    static func ordnername(fuer kennung: String) -> String {
        let teile = kennung.split(separator: "/").map(String.init)
        return (["models"] + teile).joined(separator: "--")
    }

    /// Ein Fund und der Ort (Basis- oder Suchordner), unter dem er steckt.
    ///
    /// Der Ort wird getrennt mitgeführt, weil er sich beim HF-Cache-Format
    /// NICHT mehr aus dem Elternordner des Fundes ablesen lässt: Der Fund
    /// liegt dann unter `models--org--repo/snapshots/<hash>/`, sein
    /// Elternordner ist also `snapshots` und nicht mehr der durchsuchte Ort.
    private struct Fund {
        let pfad: URL
        let ort: URL
    }

    private func fund(fuer kennung: String) -> Fund? {
        let name = Self.ordnername(fuer: kennung)
        for ort in orteInReihenfolge {
            let repoOrdner = ort.appendingPathComponent(name, isDirectory: true)
            // Flache Form zuerst: LM Studio und von Hand entpackte Modelle
            // legen Gewichte direkt in models--org--repo/ ab.
            if Self.istVollstaendig(repoOrdner) {
                return Fund(pfad: repoOrdner, ort: ort)
            }
            // HF-Cache-Form: Die Gewichte stecken eine Ebene tiefer unter
            // snapshots/<hash>/ (siehe HubCache.swift). Nur der Snapshot-
            // Ordner selbst ist vollständig, der Repo-Ordner nie.
            if let snapshot = Self.neuesterSnapshot(unter: repoOrdner) {
                return Fund(pfad: snapshot, ort: ort)
            }
        }
        return nil
    }

    func aufloesen(_ kennung: String) -> URL? {
        fund(fuer: kennung)?.pfad
    }

    func zustand(_ kennung: String, verknuepft: URL?) -> ModelZustand {
        // Ein echter Fund schlägt jede gespeicherte Verknüpfung: Wer das Modell
        // inzwischen selbst geladen hat, soll nicht auf einen toten Pfad starren.
        if let f = fund(fuer: kennung) {
            // Der Ort des Fundes MUSS genau der Basisordner sein — nicht der
            // Elternordner des Fundpfads, der beim HF-Cache-Format ja
            // "snapshots" heißt. Exakter Vergleich statt Präfix, weil ähnlich
            // benannte Nachbarordner (/basis und /basis-alt) sich sonst
            // überschneiden würden.
            let imBasis = f.ort.standardizedFileURL == basisordner.standardizedFileURL
            return imBasis ? .eigen(f.pfad) : .fremd(f.pfad)
        }
        return verknuepft == nil ? .nichtVorhanden : .nichtAuffindbar
    }

    /// Sucht unter `repoOrdner/snapshots/` nach vollständigen Snapshots und
    /// liefert den zuletzt geänderten.
    ///
    /// Gibt es mehrere Commit-Hashes, ist "irgendeiner" keine Option — die
    /// Auflösung muss vorhersagbar sein. Der zuletzt geänderte Snapshot ist
    /// der nachvollziehbarste Kandidat: Er entspricht dem zuletzt vom
    /// HF-Cache geschriebenen bzw. aktualisierten Stand.
    private static func neuesterSnapshot(unter repoOrdner: URL) -> URL? {
        let snapshotsOrdner = repoOrdner.appendingPathComponent("snapshots", isDirectory: true)
        guard let namen = try? FileManager.default.contentsOfDirectory(atPath: snapshotsOrdner.path)
        else { return nil }

        // Aus dem Namen neu anhängen statt Kind-URLs von contentsOfDirectory
        // zu übernehmen: Die lösen Symlinks im Elternpfad auf (z. B. /tmp ->
        // /private/tmp), sodass der Pfad sonst nicht mehr zu dem Ordner
        // passt, den man tatsächlich übergeben hat (wie in ModelScan.swift).
        return namen
            .map { snapshotsOrdner.appendingPathComponent($0, isDirectory: true) }
            .filter { istVollstaendig($0) }
            .max { a, b in aenderungsdatum(von: a) < aenderungsdatum(von: b) }
    }

    private static func aenderungsdatum(von ordner: URL) -> Date {
        (try? ordner.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    /// Ein Ordner zählt erst als Modell, wenn die Gewichte da sind. Ein
    /// abgebrochener Download hinterlässt sonst eine Hülle, die wie ein
    /// fertiges Modell aussieht und erst beim Laden auffliegt.
    static func istVollstaendig(_ ordner: URL) -> Bool {
        let fm = FileManager.default
        var istOrdner: ObjCBool = false
        guard fm.fileExists(atPath: ordner.path, isDirectory: &istOrdner),
              istOrdner.boolValue,
              let inhalt = try? fm.contentsOfDirectory(atPath: ordner.path)
        else { return false }
        return inhalt.contains("config.json")
            && inhalt.contains(where: { $0.hasSuffix(".safetensors") })
    }
}
