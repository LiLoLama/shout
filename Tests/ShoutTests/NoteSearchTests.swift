import XCTest

final class NoteSearchTests: XCTestCase {

    private func notiz(_ titel: String, _ text: String, angeheftet: Bool = false,
                       alter sekunden: TimeInterval = 0) -> Note {
        Note(id: UUID(), fileName: titel + ".md", body: text,
             created: Date(timeIntervalSince1970: 0),
             modified: Date(timeIntervalSince1970: 1_000_000 - sekunden),
             pinned: angeheftet, extraFrontmatter: [], titleIsFixed: true)
    }

    func testAngehefteteZuerstDannNeueste() {
        let a = notiz("A", "", alter: 10)
        let b = notiz("B", "", alter: 0)
        let c = notiz("C", "", angeheftet: true, alter: 100)
        XCTAssertEqual(NoteSearch.sorted([a, b, c]).map(\.title), ["C", "B", "A"])
    }

    func testGleicheZeitNachTitel() {
        let b = notiz("B", ""), a = notiz("a", "")
        XCTAssertEqual(NoteSearch.sorted([b, a]).map(\.title), ["a", "B"])
    }

    func testLeereSucheZeigtAlles() {
        let ergebnis = NoteSearch.filter([notiz("A", "x"), notiz("B", "y")], query: "  ")
        XCTAssertEqual(ergebnis.count, 2)
        XCTAssertNil(ergebnis[0].snippet)
    }

    /// Eine zusammenhängende Wortfolge, ohne Groß-/Kleinschreibung und ohne
    /// Akzente — „cafe" findet „Café", aber „und cafe" findet „Café und" nicht.
    func testWortfolgeOhneGrossKleinUndAkzente() {
        let n = notiz("Einkauf", "Heute Café und Brötchen holen")
        XCTAssertEqual(NoteSearch.filter([n], query: "cafe UND").count, 1)
        XCTAssertEqual(NoteSearch.filter([n], query: "und cafe").count, 0)
        XCTAssertEqual(NoteSearch.filter([n], query: "brotchen").count, 1)
    }

    func testTrefferNurImTitel() {
        let ergebnis = NoteSearch.filter([notiz("Projekt Phoenix", "nichts")], query: "phoenix")
        XCTAssertEqual(ergebnis.count, 1)
        XCTAssertNil(ergebnis[0].snippet)
    }

    func testAusschnittMitKontext() throws {
        let text = String(repeating: "x", count: 100) + " Treffer " + String(repeating: "y", count: 100)
        let s = try XCTUnwrap(NoteSearch.filter([notiz("A", text)], query: "treffer")[0].snippet)
        XCTAssertEqual(s.match, "Treffer")
        XCTAssertTrue(s.before.hasPrefix("…"))
        XCTAssertEqual(s.before.count, 41)       // „…" + 40 Zeichen
        XCTAssertTrue(s.after.hasSuffix("…"))
    }

    func testAusschnittAmAnfang() throws {
        let s = try XCTUnwrap(NoteSearch.filter([notiz("A", "Treffer am Anfang")], query: "treffer")[0].snippet)
        XCTAssertEqual(s.before, "")
        XCTAssertEqual(s.after, " am Anfang")
    }

    func testZeilenumbruecheImAusschnitt() throws {
        let s = try XCTUnwrap(NoteSearch.filter([notiz("A", "eins\nTreffer\nzwei")], query: "treffer")[0].snippet)
        XCTAssertEqual(s.before, "eins ")
        XCTAssertEqual(s.after, " zwei")
    }

    func testVorschau() {
        XCTAssertEqual(NoteSearch.preview("# Titel\n\n- [ ] Milch\nBrot"), "Titel Milch Brot")
        XCTAssertEqual(NoteSearch.preview(String(repeating: "a", count: 300)).count, 120)
    }
}
