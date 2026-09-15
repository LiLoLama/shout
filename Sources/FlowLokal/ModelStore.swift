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

    func aufloesen(_ kennung: String) -> URL? {
        let name = Self.ordnername(fuer: kennung)
        for ort in orteInReihenfolge {
            let kandidat = ort.appendingPathComponent(name, isDirectory: true)
            if Self.istVollstaendig(kandidat) { return kandidat }
        }
        return nil
    }

    func zustand(_ kennung: String, verknuepft: URL?) -> ModelZustand {
        // Ein echter Fund schlägt jede gespeicherte Verknüpfung: Wer das Modell
        // inzwischen selbst geladen hat, soll nicht auf einen toten Pfad starren.
        if let gefunden = aufloesen(kennung) {
            // Der Elternordner des Fundes MUSS genau der Basisordner sein.
            // Exakter Vergleich statt Präfix, weil ähnlich benannte Nachbarordner
            // (/basis und /basis-alt) sich sonst überschneiden würden.
            let imBasis = gefunden.deletingLastPathComponent().standardizedFileURL
                == basisordner.standardizedFileURL
            return imBasis ? .eigen(gefunden) : .fremd(gefunden)
        }
        return verknuepft == nil ? .nichtVorhanden : .nichtAuffindbar
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
