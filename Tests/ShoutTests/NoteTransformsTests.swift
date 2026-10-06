import XCTest

@MainActor
final class NoteTransformsTests: XCTestCase {

    private var ordner: URL!
    private var datei: URL { ordner.appendingPathComponent("transforms.json") }

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        ordner = FileManager.default.temporaryDirectory.appendingPathComponent("shout-transforms-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: ordner)
        Loc.shared.apply("system")
        super.tearDown()
    }

    func testFuenfEingebauteMitAnweisung() {
        XCTAssertEqual(BuiltinTransform.allCases.count, 5)
        for t in BuiltinTransform.allCases {
            XCTAssertFalse(t.instruction.isEmpty)
            XCTAssertFalse(t.name.isEmpty)
            XCTAssertFalse(t.done.isEmpty)
        }
        XCTAssertTrue(BuiltinTransform.todos.instruction.contains("- [ ]"))
    }

    func testAnlegenSichertUndLaedtWieder() {
        let store = TransformStore(url: datei)
        let neu = store.add(name: " Kürzer ", prompt: " Halbiere die Länge. ")
        XCTAssertEqual(neu?.name, "Kürzer")
        XCTAssertEqual(neu?.prompt, "Halbiere die Länge.")
        let wieder = TransformStore(url: datei)
        XCTAssertEqual(wieder.custom, store.custom)
    }

    func testLeererNameOderPromptWirdAbgelehnt() {
        let store = TransformStore(url: datei)
        XCTAssertNil(store.add(name: "  ", prompt: "x"))
        XCTAssertNil(store.add(name: "x", prompt: "\n"))
        XCTAssertTrue(store.custom.isEmpty)
    }

    func testBearbeitenUndLoeschen() throws {
        let store = TransformStore(url: datei)
        let neu = try XCTUnwrap(store.add(name: "A", prompt: "a"))
        XCTAssertTrue(store.update(neu.id, name: "B", prompt: "b"))
        XCTAssertEqual(store.custom.first?.name, "B")
        XCTAssertFalse(store.update(UUID(), name: "C", prompt: "c"))
        store.remove(neu.id)
        XCTAssertTrue(TransformStore(url: datei).custom.isEmpty)
    }

    func testKaputteDateiErgibtLeereListe() throws {
        try Data("kein json".utf8).write(to: datei)
        XCTAssertTrue(TransformStore(url: datei).custom.isEmpty)
    }

    func testAllesErsetzen() {
        let store = TransformStore(url: datei)
        let liste = [NoteTransform(id: UUID(), name: "X", prompt: "x")]
        store.replaceAll(liste)
        XCTAssertEqual(TransformStore(url: datei).custom, liste)
    }
}
