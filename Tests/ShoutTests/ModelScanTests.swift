import XCTest

final class ModelScanTests: XCTestCase {

    private var wurzel: URL!

    override func setUpWithError() throws {
        wurzel = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-modelscan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: wurzel, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wurzel)
    }

    /// Legt ein vollständiges MLX-Modell unter einem beliebigen Unterpfad an.
    @discardableResult
    private func legeMLXAn(unter pfad: String, gewichtBytes: Int = 16) throws -> URL {
        let ziel = wurzel.appendingPathComponent(pfad, isDirectory: true)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: ziel.appendingPathComponent("config.json"))
        try Data(repeating: 0, count: gewichtBytes)
            .write(to: ziel.appendingPathComponent("model.safetensors"))
        return ziel
    }

    /// Das HF-Cache-Muster: models--org--repo/snapshots/<hash>/
    func testFindetModellImHFCacheMuster() throws {
        let ziel = try legeMLXAn(
            unter: "models--mlx-community--Qwen3-4B-4bit/snapshots/abc123")
        let ergebnis = ModelScan.durchsuchen(wurzel)
        XCTAssertEqual(ergebnis.funde.count, 1)
        XCTAssertEqual(ergebnis.funde.first?.kennung, "mlx-community/Qwen3-4B-4bit")
        XCTAssertEqual(ergebnis.funde.first?.pfad, ziel)
        XCTAssertFalse(ergebnis.grenzeErreicht)
    }

    /// Das LM-Studio-Muster: <org>/<repo>/
    func testFindetModellImLMStudioMuster() throws {
        try legeMLXAn(unter: "mlx-community/Qwen3-4B-4bit")
        let ergebnis = ModelScan.durchsuchen(wurzel)
        XCTAssertEqual(ergebnis.funde.count, 1)
        XCTAssertEqual(ergebnis.funde.first?.kennung, "mlx-community/Qwen3-4B-4bit")
    }

    /// Ordner ohne Gewichte sind keine Funde — ein abgebrochener Download
    /// darf nicht in der Liste auftauchen.
    func testIgnoriertUnvollstaendigeOrdner() throws {
        let halb = wurzel.appendingPathComponent("mlx-community/Halbfertig", isDirectory: true)
        try FileManager.default.createDirectory(at: halb, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: halb.appendingPathComponent("config.json"))
        let ergebnis = ModelScan.durchsuchen(wurzel)
        XCTAssertTrue(ergebnis.funde.isEmpty)
    }

    func testMeldetGroesseDerGewichte() throws {
        try legeMLXAn(unter: "mlx-community/Qwen3-4B-4bit", gewichtBytes: 4096)
        let ergebnis = ModelScan.durchsuchen(wurzel)
        XCTAssertEqual(ergebnis.funde.first?.groesseBytes, 4096)
    }

    /// Jenseits der Tiefengrenze wird nicht mehr gesucht, und das Ergebnis
    /// sagt es. Wer auf / zeigt, soll eine Meldung bekommen statt zu warten.
    func testTiefengrenzeGreiftUndWirdGemeldet() throws {
        try legeMLXAn(unter: "a/b/c/d/e/f/g/h/mlx-community/Tief")
        let ergebnis = ModelScan.durchsuchen(wurzel, maxTiefe: 3)
        XCTAssertTrue(ergebnis.funde.isEmpty)
        XCTAssertTrue(ergebnis.grenzeErreicht)
    }

    /// Bereits Gefundenes geht beim Anschlagen der Grenze nicht verloren.
    func testGefundenesUeberlebtDieGrenze() throws {
        try legeMLXAn(unter: "mlx-community/Flach")
        try legeMLXAn(unter: "a/b/c/d/e/f/g/h/mlx-community/Tief")
        let ergebnis = ModelScan.durchsuchen(wurzel, maxTiefe: 3)
        XCTAssertEqual(ergebnis.funde.map(\.kennung), ["mlx-community/Flach"])
        XCTAssertTrue(ergebnis.grenzeErreicht)
    }

    /// Abbruch von außen: Der Durchlauf hört auf und meldet die Grenze.
    func testAbbruchStopptDenDurchlauf() throws {
        try legeMLXAn(unter: "mlx-community/Eins")
        let ergebnis = ModelScan.durchsuchen(wurzel, abbruch: { true })
        XCTAssertTrue(ergebnis.funde.isEmpty)
        XCTAssertTrue(ergebnis.grenzeErreicht)
    }

    func testLeererOrdnerLiefertNichts() {
        let ergebnis = ModelScan.durchsuchen(wurzel)
        XCTAssertTrue(ergebnis.funde.isEmpty)
        XCTAssertFalse(ergebnis.grenzeErreicht)
    }
}
