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
}
