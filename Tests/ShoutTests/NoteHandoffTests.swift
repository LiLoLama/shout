import XCTest

final class NoteHandoffTests: XCTestCase {

    func testAuswahlGehtVor() {
        XCTAssertEqual(NoteHandoff.content(body: "eins zwei drei", selection: NSRange(location: 5, length: 4)), "zwei")
    }

    func testOhneAuswahlDieGanzeNotizOhneRandLeerraum() {
        XCTAssertEqual(NoteHandoff.content(body: "  Text\nmehr\n", selection: NSRange(location: 2, length: 0)),
                       "Text\nmehr")
    }

    func testNurLeerraumIstNichts() {
        XCTAssertNil(NoteHandoff.content(body: " \n ", selection: NSRange(location: 0, length: 0)))
    }

    func testAuswahlAusserhalbNimmtAlles() {
        XCTAssertEqual(NoteHandoff.content(body: "kurz", selection: NSRange(location: 10, length: 3)), "kurz")
    }

    func testAuswahlNurAusLeerraumNimmtAlles() {
        XCTAssertEqual(NoteHandoff.content(body: "a   b", selection: NSRange(location: 1, length: 3)), "a   b")
    }
}
