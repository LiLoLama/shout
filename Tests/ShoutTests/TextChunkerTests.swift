import XCTest

final class TextChunkerTests: XCTestCase {

    /// Baut Text aus gleich langen Sätzen, damit die Länge vorhersagbar ist.
    private func saetze(_ count: Int) -> String {
        (1...count).map { "Das ist der Satz Nummer \($0) in diesem Text." }.joined(separator: " ")
    }

    func testLeererTextGibtLeeresErgebnis() {
        XCTAssertEqual(TextChunker.chunks(of: ""), [])
        XCTAssertEqual(TextChunker.chunks(of: "   \n  "), [])
    }

    func testKurzerTextBleibtEinAbschnitt() {
        let text = "Ein kurzer Satz."
        XCTAssertEqual(TextChunker.chunks(of: text), [text])
    }

    func testLangerTextWirdGeteilt() {
        let text = saetze(200)   // deutlich über 1500 Zeichen
        let parts = TextChunker.chunks(of: text)
        XCTAssertGreaterThan(parts.count, 1)
    }

    /// Der Inhalt darf beim Teilen nicht verloren gehen — Wortfolge bleibt gleich.
    func testTeilungVerliertKeinenInhalt() {
        let text = saetze(200)
        let parts = TextChunker.chunks(of: text)
        XCTAssertEqual(parts.joined(separator: " ").split(separator: " "),
                       text.split(separator: " "))
    }

    func testAbschnitteEndenAufSatzzeichen() {
        let parts = TextChunker.chunks(of: saetze(200))
        for part in parts.dropLast() {
            XCTAssertTrue(part.hasSuffix(".") || part.hasSuffix("!") || part.hasSuffix("?"),
                          "Abschnitt endet mitten im Satz: …\(part.suffix(40))")
        }
    }

    /// Ohne jedes Satzzeichen darf die Teilung nicht in eine Endlosschleife laufen,
    /// sondern schneidet hart am Zielmaß.
    func testTextOhneSatzzeichenWirdHartGeteilt() {
        let text = String(repeating: "wort ", count: 1000)
        let parts = TextChunker.chunks(of: text, targetLength: 200, minLength: 120)
        XCTAssertGreaterThan(parts.count, 1)
        for part in parts { XCTAssertLessThanOrEqual(part.count, 200) }
    }

    /// „z. B." ist kein Satzende. Ein Fehlschnitt dort ist zwar harmlos (er ändert
    /// keinen Wortlaut), setzt aber einen Absatz mitten in den Satz.
    func testAbkuerzungGiltNichtAlsSatzende() {
        let vorne = String(repeating: "Fülltext hier. ", count: 8)   // ~120 Zeichen
        let text = vorne + "Wir nehmen z. B. Das hier ist ein Test und es geht weiter."
        let parts = TextChunker.chunks(of: text, targetLength: 150, minLength: 100)
        XCTAssertFalse(parts.contains { $0.hasSuffix("z. B.") },
                       "Abschnitt endet auf einer Abkürzung: \(parts)")
    }

    func testEinzelneGrosseAbkuerzungWirdErkannt() {
        let vorne = String(repeating: "Fülltext hier. ", count: 8)
        let text = vorne + "Wir treffen Dr. Meier und dann fahren wir gemeinsam weiter."
        let parts = TextChunker.chunks(of: text, targetLength: 150, minLength: 100)
        XCTAssertFalse(parts.contains { $0.hasSuffix("Dr.") })
    }

    // MARK: - joinFormatted (Zusammenfügen formatierter Abschnitte)

    func testJoinLeerUndEinzeln() {
        XCTAssertEqual(TextChunker.joinFormatted([]), "")
        XCTAssertEqual(TextChunker.joinFormatted(["Ein Satz."]), "Ein Satz.")
    }

    func testJoinFliesstextMitLeerzeichen() {
        XCTAssertEqual(TextChunker.joinFormatted(["Erster Teil.", "Zweiter Teil."]),
                       "Erster Teil. Zweiter Teil.")
    }

    func testJoinLeereStueckeWerdenUebersprungen() {
        XCTAssertEqual(TextChunker.joinFormatted(["Erster Teil.", "", "  ", "Zweiter Teil."]),
                       "Erster Teil. Zweiter Teil.")
    }

    /// Endet ein Abschnitt mit einer Aufzählung, darf der nächste nicht mit
    /// Leerzeichen angeklebt werden — sonst klebt „3. das Feedback Für das…".
    func testJoinNachListeKommtZeilenumbruch() {
        let liste = "Wir brauchen:\n1. die Zahlen\n2. die Präsentation"
        XCTAssertEqual(TextChunker.joinFormatted([liste, "Danach geht es weiter."]),
                       liste + "\nDanach geht es weiter.")
    }

    func testJoinVorListeKommtZeilenumbruch() {
        let liste = "1. die Zahlen\n2. die Präsentation"
        XCTAssertEqual(TextChunker.joinFormatted(["Wir brauchen Folgendes.", liste]),
                       "Wir brauchen Folgendes.\n" + liste)
    }

    func testJoinErkenntSpiegelstrichListen() {
        XCTAssertEqual(TextChunker.joinFormatted(["Punkte:\n- eins\n- zwei", "Weiter im Text."]),
                       "Punkte:\n- eins\n- zwei\nWeiter im Text.")
    }
}
