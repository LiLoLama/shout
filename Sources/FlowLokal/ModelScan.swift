import Foundation

/// Ein gefundenes Modell in einem durchsuchten Ordner.
struct ModelFund: Equatable {
    let kennung: String
    let pfad: URL
    let groesseBytes: Int64
}

/// Durchsucht einen Ordner nach Modellen.
///
/// Bewusst getrennt von `ModelStore`: Dateisystem-Durchlauf und
/// Auflösungsregeln haben nichts miteinander zu tun, und nur so bleiben beide
/// für sich prüfbar.
///
/// Es wird **nur auf Auftrag** durchsucht, nie von allein und nie auf einem
/// Pfad, den niemand genannt hat.
enum ModelScan {

    /// Sechs Ebenen decken alle bekannten Ablagen ab:
    /// `~/.lmstudio/models/<org>/<repo>/` (3), der HF-Cache mit
    /// `models--org--repo/snapshots/<hash>/` (3), flache Ordner (1).
    static let standardTiefe = 6
    static let standardEintraege = 50_000

    static func durchsuchen(_ wurzel: URL,
                            maxTiefe: Int = standardTiefe,
                            maxEintraege: Int = standardEintraege,
                            abbruch: () -> Bool = { false })
        -> (funde: [ModelFund], grenzeErreicht: Bool) {

        var funde: [ModelFund] = []
        var grenzeErreicht = false
        var besucht = 0
        let fm = FileManager.default

        // Breitensuche statt Rekursion: Die Tiefe ist damit ablesbar, und ein
        // sehr tiefer Baum kann den Stapel nicht sprengen.
        var warteschlange: [(url: URL, tiefe: Int)] = [(wurzel, 0)]

        while !warteschlange.isEmpty {
            if abbruch() { return (funde, true) }

            let (ordner, tiefe) = warteschlange.removeFirst()
            besucht += 1
            if besucht > maxEintraege { grenzeErreicht = true; break }

            // Ist dieser Ordner selbst ein Modell? Dann nicht weiter hinein —
            // in den Gewichten liegt nichts, was uns noch interessiert.
            if ModelStore.istVollstaendig(ordner) {
                funde.append(ModelFund(kennung: kennung(fuer: ordner, unter: wurzel),
                                       pfad: ordner,
                                       groesseBytes: groesse(von: ordner)))
                continue
            }

            if tiefe >= maxTiefe { grenzeErreicht = true; continue }

            guard let inhalt = try? fm.contentsOfDirectory(
                at: ordner,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }

            for eintrag in inhalt {
                let istOrdner = (try? eintrag.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false
                guard istOrdner else { continue }
                // Aus dem Namen neu anhängen statt die Kind-URL von
                // `contentsOfDirectory` zu übernehmen: Die löst Symlinks im
                // Elternpfad auf (z. B. `/var` -> `/private/var` bei
                // temporären Ordnern), sodass `pfad` sonst nicht mehr zu dem
                // Wurzelordner passt, den man tatsächlich übergeben hat.
                let kind = ordner.appendingPathComponent(eintrag.lastPathComponent, isDirectory: true)
                warteschlange.append((kind, tiefe + 1))
            }
        }

        return (funde, grenzeErreicht)
    }

    /// Leitet die Kennung `<org>/<repo>` aus dem Pfad ab.
    ///
    /// Zwei Formen kommen vor: Der HF-Cache schreibt `models--org--repo` in
    /// EINEN Ordnernamen (darunter `snapshots/<hash>/`), LM Studio benutzt
    /// zwei Ebenen `org/repo`. Greift keine der beiden, bleibt der Ordnername.
    static func kennung(fuer pfad: URL, unter wurzel: URL) -> String {
        let alleTeile: [String] = pfad.standardizedFileURL.pathComponents
        let praefixLaenge = wurzel.standardizedFileURL.pathComponents.count
        let teile: [String] = Array(alleTeile.dropFirst(praefixLaenge))

        if let hf = teile.first(where: { $0.hasPrefix("models--") }) {
            let zerlegt = hf.dropFirst("models--".count).components(separatedBy: "--")
            return zerlegt.joined(separator: "/")
        }
        // snapshots/<hash> am Ende abschneiden, dann die letzten zwei Ebenen.
        var rest = teile
        if let i = rest.firstIndex(of: "snapshots") { rest = Array(rest[..<i]) }
        if rest.count >= 2 { return rest.suffix(2).joined(separator: "/") }
        return rest.last ?? pfad.lastPathComponent
    }

    /// Summe der Gewichtsdateien (`*.safetensors`) direkt im Modellordner.
    /// `config.json` & Co. zählen nicht mit — gefragt ist die Größe des
    /// Modells, nicht die des Ordners. Unterordner bleiben außen vor —
    /// bei MLX liegen die Gewichte flach, und ein voller Durchlauf je Fund
    /// machte das Durchsuchen unnötig teuer.
    static func groesse(von ordner: URL) -> Int64 {
        guard let inhalt = try? FileManager.default.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return inhalt
            .filter { $0.lastPathComponent.hasSuffix(".safetensors") }
            .reduce(Int64(0)) { summe, datei in
                let bytes = (try? datei.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return summe + Int64(bytes)
            }
    }
}
