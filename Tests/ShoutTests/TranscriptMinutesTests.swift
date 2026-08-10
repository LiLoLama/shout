import XCTest

final class TranscriptMinutesTests: XCTestCase {

    // MARK: - Antwort des Modells zerlegen

    func testVollstaendigeAntwort() {
        let raw = """
        TITEL: Budget für das nächste Quartal
        PUNKTE:
        - Budget wird um 10 Prozent gekürzt
        - Entscheidung fällt nächste Woche
        TEXT:
        Wir haben über das Budget gesprochen. Es wird knapper als gedacht.
        """
        let section = TranscriptMinutes.parseSection(raw)
        XCTAssertEqual(section.title, "Budget für das nächste Quartal")
        XCTAssertEqual(section.points, ["Budget wird um 10 Prozent gekürzt",
                                        "Entscheidung fällt nächste Woche"])
        XCTAssertEqual(section.text, "Wir haben über das Budget gesprochen. Es wird knapper als gedacht.")
    }

    /// Kleine Modelle halten sich nicht immer ans Format. Dann ist die ganze
    /// Ausgabe der Text — besser als ein leeres Protokoll.
    func testAntwortOhneMarkerWirdKomplettZumText() {
        let raw = "Einfach nur ein Absatz ohne jede Struktur."
        let section = TranscriptMinutes.parseSection(raw)
        XCTAssertNil(section.title)
        XCTAssertTrue(section.points.isEmpty)
        XCTAssertEqual(section.text, raw)
    }

    func testFehlendeStuecke() {
        let raw = """
        TEXT:
        Nur Text, kein Titel und keine Punkte.
        """
        let section = TranscriptMinutes.parseSection(raw)
        XCTAssertNil(section.title)
        XCTAssertTrue(section.points.isEmpty)
        XCTAssertEqual(section.text, "Nur Text, kein Titel und keine Punkte.")
    }

    /// Aufzählungszeichen variieren je nach Modell und Laune.
    func testVerschiedeneAufzaehlungszeichen() {
        let raw = """
        PUNKTE:
        - Erster Punkt
        • Zweiter Punkt
        * Dritter Punkt
        1. Vierter Punkt
        TEXT:
        Der Text.
        """
        XCTAssertEqual(TranscriptMinutes.parseSection(raw).points,
                       ["Erster Punkt", "Zweiter Punkt", "Dritter Punkt", "Vierter Punkt"])
    }

    func testMarkerUnabhaengigVonGrossschreibung() {
        let raw = "Titel: Kurz\nText:\nInhalt."
        let section = TranscriptMinutes.parseSection(raw)
        XCTAssertEqual(section.title, "Kurz")
        XCTAssertEqual(section.text, "Inhalt.")
    }

    func testLeereAntwortGibtLeerenAbschnitt() {
        let section = TranscriptMinutes.parseSection("   \n  ")
        XCTAssertNil(section.title)
        XCTAssertTrue(section.points.isEmpty)
        XCTAssertEqual(section.text, "")
    }

    // MARK: - Dokument zusammensetzen

    private let headings = TranscriptMinutes.Headings(
        summary: "Zusammenfassung", points: "Kernpunkte", body: "Protokoll")

    func testDokumentMitAllenTeilen() {
        let sections = [
            TranscriptMinutes.Section(title: "Erstes Thema", points: [], text: "Erster Absatz."),
            TranscriptMinutes.Section(title: "Zweites Thema", points: [], text: "Zweiter Absatz."),
        ]
        let doc = TranscriptMinutes.assemble(summary: "Es ging ums Budget.",
                                             points: ["Budget wird gekürzt"],
                                             sections: sections, headings: headings)
        XCTAssertEqual(doc, """
        # Zusammenfassung

        Es ging ums Budget.

        # Kernpunkte

        - Budget wird gekürzt

        # Protokoll

        ## Erstes Thema

        Erster Absatz.

        ## Zweites Thema

        Zweiter Absatz.
        """)
    }

    /// Ohne Zusammenfassung darf keine leere Überschrift dastehen.
    func testLeereTeileFallenWeg() {
        let sections = [TranscriptMinutes.Section(title: nil, points: [], text: "Nur Text.")]
        let doc = TranscriptMinutes.assemble(summary: "", points: [], sections: sections,
                                             headings: headings)
        XCTAssertEqual(doc, "# Protokoll\n\nNur Text.")
    }

    func testAbschnitteOhneTextFallenWeg() {
        let sections = [
            TranscriptMinutes.Section(title: "Leer", points: [], text: "   "),
            TranscriptMinutes.Section(title: "Voll", points: [], text: "Inhalt."),
        ]
        let doc = TranscriptMinutes.assemble(summary: "", points: [], sections: sections,
                                             headings: headings)
        XCTAssertFalse(doc.contains("Leer"))
        XCTAssertTrue(doc.contains("## Voll"))
    }

    func testOhneJedenInhaltLeeresDokument() {
        XCTAssertEqual(TranscriptMinutes.assemble(summary: "", points: [], sections: [],
                                                  headings: headings), "")
    }

    // MARK: - Kernpunkte einsammeln

    /// Die zweite Stufe bekommt die Punkte aller Abschnitte — doppelte fliegen raus,
    /// sonst steht dasselbe dreimal im Protokoll.
    func testPunkteWerdenEingesammeltUndEntdoppelt() {
        let sections = [
            TranscriptMinutes.Section(title: nil, points: ["Budget gekürzt", "Termin offen"], text: "a"),
            TranscriptMinutes.Section(title: nil, points: ["budget gekürzt", "Neue Person"], text: "b"),
        ]
        XCTAssertEqual(TranscriptMinutes.collectPoints(from: sections),
                       ["Budget gekürzt", "Termin offen", "Neue Person"])
    }
}
