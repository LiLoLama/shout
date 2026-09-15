import XCTest

final class ModelStoreTests: XCTestCase {

    private var wurzel: URL!
    private var basis: URL!
    private var fremd: URL!

    override func setUpWithError() throws {
        wurzel = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-modelstore-\(UUID().uuidString)", isDirectory: true)
        basis = wurzel.appendingPathComponent("basis", isDirectory: true)
        fremd = wurzel.appendingPathComponent("fremd", isDirectory: true)
        for ordner in [basis!, fremd!] {
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wurzel)
    }

    /// Legt ein MLX-Modell als Attrappe an: Ordner mit config.json und Gewichten.
    /// Der Inhalt ist gleichgültig — der Store prüft Struktur, nicht Inhalt.
    private func legeMLXAn(in ordner: URL, kennung: String) throws -> URL {
        let ziel = ordner.appendingPathComponent(
            ModelStore.ordnername(fuer: kennung), isDirectory: true)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: ziel.appendingPathComponent("config.json"))
        try Data().write(to: ziel.appendingPathComponent("model.safetensors"))
        return ziel
    }

    /// Legt ein Modell im Format des Hugging-Face-Caches an:
    /// `models--org--repo/snapshots/<hash>/` mit config.json und Gewichten.
    /// `geaendert` setzt das Änderungsdatum des Snapshot-Ordners explizit —
    /// so lässt sich "zuletzt geändert" deterministisch prüfen, ohne auf
    /// echte Zeitabstände zwischen zwei Anlagen angewiesen zu sein.
    private func legeHFCacheModellAn(in ordner: URL, kennung: String, hash: String,
                                     geaendert: Date? = nil) throws -> URL {
        let snapshot = ordner
            .appendingPathComponent(ModelStore.ordnername(fuer: kennung), isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(hash, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("config.json"))
        try Data().write(to: snapshot.appendingPathComponent("model.safetensors"))
        if let geaendert {
            try FileManager.default.setAttributes([.modificationDate: geaendert],
                                                  ofItemAtPath: snapshot.path)
        }
        return snapshot
    }

    /// Nichts vorhanden heißt: kein Pfad. Nicht etwa der erwartete Pfad,
    /// den es noch nicht gibt — sonst hielte der Aufrufer ihn für gültig.
    func testOhneModellKeinPfad() {
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertNil(store.aufloesen("mlx-community/Qwen3-4B-4bit"))
    }

    func testFindetModellImBasisordner() throws {
        let erwartet = try legeMLXAn(in: basis, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [])
        XCTAssertEqual(store.aufloesen("mlx-community/Qwen3-4B-4bit"), erwartet)
    }

    func testFindetModellImSuchordner() throws {
        let erwartet = try legeMLXAn(in: fremd, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.aufloesen("mlx-community/Qwen3-4B-4bit"), erwartet)
    }

    /// Der Vorrang ist die Kernregel: Liegt dasselbe Modell doppelt, gewinnt
    /// der Basisordner. Sonst wäre nicht vorhersagbar, was geladen wird.
    func testBasisordnerSchlaegtSuchordner() throws {
        let imBasis = try legeMLXAn(in: basis, kennung: "mlx-community/Qwen3-4B-4bit")
        _ = try legeMLXAn(in: fremd, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.aufloesen("mlx-community/Qwen3-4B-4bit"), imBasis)
    }

    /// Ein Ordner ohne Gewichte ist kein Modell, auch wenn er richtig heißt.
    /// Ein abgebrochener Download darf nicht als fertiges Modell gelten.
    func testOrdnerOhneGewichteZaehltNicht() throws {
        let leer = basis.appendingPathComponent(
            ModelStore.ordnername(fuer: "mlx-community/Qwen3-4B-4bit"),
            isDirectory: true)
        try FileManager.default.createDirectory(at: leer, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: leer.appendingPathComponent("config.json"))
        let store = ModelStore(basisordner: basis, suchordner: [])
        XCTAssertNil(store.aufloesen("mlx-community/Qwen3-4B-4bit"))
    }

    /// Der HF-Cache benutzt das Python-Format models--org--repo.
    func testOrdnernameFolgtDemHFFormat() {
        XCTAssertEqual(
            ModelStore.ordnername(fuer: "mlx-community/Qwen3-4B-4bit"),
            "models--mlx-community--Qwen3-4B-4bit")
    }

    func testZustandNichtVorhandenOhneVerknuepfung() {
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: nil),
                       .nichtVorhanden)
    }

    func testZustandEigenImBasisordner() throws {
        let pfad = try legeMLXAn(in: basis, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: nil),
                       .eigen(pfad))
    }

    func testZustandFremdImSuchordner() throws {
        let pfad = try legeMLXAn(in: fremd, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: nil),
                       .fremd(pfad))
    }

    /// Der wichtigste Zustand: Es war einmal da, jetzt ist es weg. Das darf
    /// NICHT als "nicht vorhanden" durchgehen, sonst bietet die Oberfläche
    /// einen Download an, obwohl bloß eine Platte nicht steckt.
    func testZustandNichtAuffindbarWennVerknuepftUndWeg() {
        let weg = fremd.appendingPathComponent("models--mlx-community--Qwen3-4B-4bit",
                                               isDirectory: true)
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: weg),
                       .nichtAuffindbar)
    }

    /// Eine alte Verknüpfung darf einen echten Fund nicht überstimmen: Wer das
    /// Modell inzwischen in den Basisordner geladen hat, sieht "eigen".
    func testFundSchlaegtAlteVerknuepfung() throws {
        let pfad = try legeMLXAn(in: basis, kennung: "mlx-community/Qwen3-4B-4bit")
        let alt = fremd.appendingPathComponent("models--mlx-community--Qwen3-4B-4bit",
                                               isDirectory: true)
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: alt),
                       .eigen(pfad))
    }

    /// Ähnlich benannte Nachbarordner dürfen sich nicht überschneiden:
    /// Wenn der Basisordner "/Users/x/basis" ist und ein Suchordner
    /// "/Users/x/basis-alt", dann darf ein Fund in "basis-alt" nicht
    /// fälschlich als .eigen (im Basisordner) gemeldet werden, sondern
    /// muss korrekt als .fremd erkannt werden.
    func testÄhnlichBenannteSuchordnerVerwechselnSichNicht() throws {
        let basisAlt = wurzel.appendingPathComponent("basis-alt", isDirectory: true)
        try FileManager.default.createDirectory(at: basisAlt, withIntermediateDirectories: true)

        let pfad = try legeMLXAn(in: basisAlt, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [basisAlt])

        // Das Modell liegt in "basis-alt", nicht in "basis" — muss als .fremd gelten.
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: nil),
                       .fremd(pfad))
    }

    // MARK: - HF-Cache-Format (models--org--repo/snapshots/<hash>/)

    /// Der HF-Cache legt die Gewichte nicht direkt in models--org--repo/ ab,
    /// sondern eine Ebene tiefer unter snapshots/<hash>/. aufloesen muss
    /// genau diesen Snapshot-Ordner liefern, nicht den Repo-Ordner darüber —
    /// nur dort liegen config.json und die Gewichte tatsächlich.
    func testFindetModellImHFCacheFormat() throws {
        let snapshot = try legeHFCacheModellAn(
            in: basis, kennung: "mlx-community/Qwen3-4B-4bit", hash: "abc123")
        let store = ModelStore(basisordner: basis, suchordner: [])
        XCTAssertEqual(store.aufloesen("mlx-community/Qwen3-4B-4bit"), snapshot)
    }

    /// Ein selbst geladenes Modell im HF-Cache-Format muss trotz des
    /// zusätzlichen snapshots/<hash>-Zwischenordners als .eigen gelten —
    /// sonst hielte die Oberfläche jeden eigenen Download für fremd.
    func testZustandEigenBeiHFCacheFormatImBasisordner() throws {
        let snapshot = try legeHFCacheModellAn(
            in: basis, kennung: "mlx-community/Qwen3-4B-4bit", hash: "abc123")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: nil),
                       .eigen(snapshot))
    }

    /// Dieselbe Unterscheidung muss auch für einen Suchordner funktionieren:
    /// Ein HF-Cache-Fund außerhalb des Basisordners bleibt .fremd.
    func testZustandFremdBeiHFCacheFormatImSuchordner() throws {
        let snapshot = try legeHFCacheModellAn(
            in: fremd, kennung: "mlx-community/Qwen3-4B-4bit", hash: "abc123")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: nil),
                       .fremd(snapshot))
    }

    /// Mehrere Snapshots (mehrere Commit-Hashes) müssen vorhersagbar
    /// aufgelöst werden: Es gewinnt der zuletzt geänderte, nicht "irgendeiner"
    /// — sonst wäre nicht nachvollziehbar, welche Gewichte geladen werden.
    func testMehrereSnapshotsLiefernDenZuletztGeaenderten() throws {
        let alt = try legeHFCacheModellAn(
            in: basis, kennung: "mlx-community/Qwen3-4B-4bit", hash: "alt",
            geaendert: Date(timeIntervalSince1970: 1_000))
        let neu = try legeHFCacheModellAn(
            in: basis, kennung: "mlx-community/Qwen3-4B-4bit", hash: "neu",
            geaendert: Date(timeIntervalSince1970: 2_000))
        let store = ModelStore(basisordner: basis, suchordner: [])
        XCTAssertEqual(store.aufloesen("mlx-community/Qwen3-4B-4bit"), neu)
        XCTAssertNotEqual(store.aufloesen("mlx-community/Qwen3-4B-4bit"), alt)
    }

    /// Ein Snapshot-Ordner ohne Gewichte (z. B. ein abgebrochener Download)
    /// zählt nicht als Modell, auch wenn config.json schon da ist.
    func testSnapshotOhneGewichteZaehltNicht() throws {
        let snapshot = basis
            .appendingPathComponent(ModelStore.ordnername(fuer: "mlx-community/Qwen3-4B-4bit"),
                                    isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("abc123", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("config.json"))
        let store = ModelStore(basisordner: basis, suchordner: [])
        XCTAssertNil(store.aufloesen("mlx-community/Qwen3-4B-4bit"))
    }

    // MARK: - Abkürzung des Downloads

    /// In einem FREMDEN Ordner ist die Abkürzung richtig: Dort gibt es keine
    /// Metadaten und niemanden, der vervollständigen könnte — das Modell
    /// mitzubenutzen erspart denselben Download ein zweites Mal.
    func testFremderFundKuerztAb() throws {
        let ziel = try legeMLXAn(in: fremd, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.abkuerzbarerFund("mlx-community/Qwen3-4B-4bit",
                                              eigenerDownloadOrdner: basis),
                       ziel)
    }

    /// Der Kern der Korrektur: Im EIGENEN Cache wird nicht abgekürzt. Sonst
    /// ersetzte die schwache Prüfung des Stores (config.json plus irgendeine
    /// *.safetensors) die starke des HubClients, der anhand der Metadaten
    /// jede erwartete Datei kennt — ein abgebrochener Download bliebe für
    /// immer halb, weil jeder weitere Versuch dieselbe Abkürzung nähme.
    func testFundImEigenenCacheKuerztNichtAb() throws {
        _ = try legeMLXAn(in: basis, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertNil(store.abkuerzbarerFund("mlx-community/Qwen3-4B-4bit",
                                            eigenerDownloadOrdner: basis))
        // Der Fund als solcher bleibt bestehen — nur abgekürzt wird er nicht.
        XCTAssertNotNil(store.aufloesen("mlx-community/Qwen3-4B-4bit"))
    }

    /// Auch im HF-Cache-Format (snapshots/<hash>/) muss der eigene Ordner
    /// erkannt werden: Der Fundpfad liegt dann zwei Ebenen tiefer, entscheidend
    /// ist der durchsuchte Ort, nicht der Elternordner des Fundes.
    func testFundImEigenenCacheKuerztAuchImHFFormatNichtAb() throws {
        _ = try legeHFCacheModellAn(
            in: basis, kennung: "mlx-community/Qwen3-4B-4bit", hash: "abc123")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertNil(store.abkuerzbarerFund("mlx-community/Qwen3-4B-4bit",
                                            eigenerDownloadOrdner: basis))
    }

    /// Mit gewähltem Basisordner ist der eigene Download-Ordner ein anderer
    /// als ohne. Maßgeblich ist immer der Ordner, der im selben Aufruf an den
    /// HubClient geht — liegt der Fund woanders, darf abgekürzt werden.
    func testEigenerOrdnerIstDerUebergebene() throws {
        let ziel = try legeMLXAn(in: basis, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        // Herunterladen würde shout. nach `fremd` — `basis` ist damit fremd.
        XCTAssertEqual(store.abkuerzbarerFund("mlx-community/Qwen3-4B-4bit",
                                              eigenerDownloadOrdner: fremd),
                       ziel)
    }

    /// Ohne Fund gibt es nichts abzukürzen — der Hub ist zuständig.
    func testOhneFundKeineAbkuerzung() {
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertNil(store.abkuerzbarerFund("mlx-community/Qwen3-4B-4bit",
                                            eigenerDownloadOrdner: basis))
    }

    // MARK: - Symlinks in den Ortsvergleichen

    /// Die Sperre gegen das Abkürzen im eigenen Cache darf nicht an der
    /// Schreibweise scheitern: `/tmp` ist ein Symlink auf `/private/tmp`,
    /// beide Wege bezeichnen denselben Ordner. Mit bloßem
    /// `standardizedFileURL` gälten sie als verschieden — und shout. kürzte
    /// ausgerechnet im eigenen halben Download ab.
    func testEigenerOrdnerWirdUeberDenSymlinkErkannt() throws {
        let (ueberSymlink, echt) = try symlinkPaar()
        defer { try? FileManager.default.removeItem(at: ueberSymlink) }

        _ = try legeMLXAn(in: ueberSymlink, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: ueberSymlink, suchordner: [])
        XCTAssertNil(store.abkuerzbarerFund("mlx-community/Qwen3-4B-4bit",
                                            eigenerDownloadOrdner: echt))
    }

    /// Dieselbe Gleichheit muss auch der Zustand sehen: Ein Modell im
    /// Basisordner bleibt `.eigen`, auch wenn der Basisordner über die andere
    /// Schreibweise hereinkommt — sonst trüge die Oberfläche „Fremder Ordner"
    /// an den eigenen Download.
    func testZustandEigenTrotzUnterschiedlicherSchreibweise() throws {
        let (ueberSymlink, echt) = try symlinkPaar()
        defer { try? FileManager.default.removeItem(at: ueberSymlink) }

        _ = try legeMLXAn(in: ueberSymlink, kennung: "mlx-community/Qwen3-4B-4bit")
        // Angelegt über `/tmp`, dem Store bekannt als `/private/tmp` — derselbe
        // Ordner. Der gelieferte Pfad hängt an der Schreibweise des Ortes.
        let store = ModelStore(basisordner: echt, suchordner: [ueberSymlink])
        let erwartet = echt.appendingPathComponent(
            ModelStore.ordnername(fuer: "mlx-community/Qwen3-4B-4bit"), isDirectory: true)
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: nil),
                       .eigen(erwartet))
    }

    /// Derselbe Ordner in zwei Schreibweisen ist EIN Ort, kein zweiter.
    func testOrteInReihenfolgeFasstSchreibweisenZusammen() throws {
        let (ueberSymlink, echt) = try symlinkPaar()
        defer { try? FileManager.default.removeItem(at: ueberSymlink) }

        let store = ModelStore(basisordner: echt, suchordner: [ueberSymlink])
        XCTAssertEqual(store.orteInReihenfolge, [echt])
    }

    /// Legt einen echten Ordner an und liefert ihn in beiden Schreibweisen.
    ///
    /// Bewusst unter `/tmp` statt unter `FileManager.temporaryDirectory`: Der
    /// temporäre Ordner kommt schon als `/var/…` (also aufgelöst) daher, ein
    /// Unterschied wäre dort gar nicht zu erzeugen. Und der Ordner muss
    /// wirklich existieren — `resolvingSymlinksInPath()` löst nur auf, was da
    /// ist.
    private func symlinkPaar() throws -> (ueberSymlink: URL, echt: URL) {
        let name = "shout-symlink-\(UUID().uuidString)"
        let ueberSymlink = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: ueberSymlink, withIntermediateDirectories: true)
        let echt = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        return (ueberSymlink, echt)
    }
}
