import XCTest

/// Ein Diktat am Cursor darf nicht an das Wort davor kleben — und vor einem
/// Satzzeichen oder nach einer öffnenden Klammer steht kein Leerzeichen.
final class DictationInsertionTests: XCTestCase {

    func testAmAnfangOhneLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text("Hallo", after: nil), "Hallo")
    }

    func testNachWortMitLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text("Welt", after: "o"), " Welt")
    }

    func testNachLeerraumOhneLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text("Welt", after: " "), "Welt")
        XCTAssertEqual(DictationInsertion.text("Welt", after: "\n"), "Welt")
    }

    func testVorSatzzeichenOhneLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text(", und dann", after: "o"), ", und dann")
        XCTAssertEqual(DictationInsertion.text(".", after: "o"), ".")
    }

    func testNachOeffnenderKlammerOderAnfuehrungOhneLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text("Welt", after: "("), "Welt")
        XCTAssertEqual(DictationInsertion.text("Welt", after: "„"), "Welt")
    }

    func testLeererTextBleibtLeer() {
        XCTAssertEqual(DictationInsertion.text("", after: "o"), "")
    }

    func testNachSchliessenderAnfuehrungMitLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text("sagte", after: "“"), " sagte")
        XCTAssertEqual(DictationInsertion.text("sagte", after: "\""), " sagte")
        XCTAssertEqual(DictationInsertion.text("sagte", after: "'"), " sagte")
    }

    func testNachOeffnenderFranzoesischerAnfuehrungOhneLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text("Welt", after: "«"), "Welt")
        XCTAssertEqual(DictationInsertion.text("Welt", after: "‚"), "Welt")
    }

    func testDiktatMitfuehrendemLeerraumBekommtKeinZweitesLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text(" Welt", after: "o"), " Welt")
        XCTAssertEqual(DictationInsertion.text("\nWelt", after: "o"), "\nWelt")
    }
}
