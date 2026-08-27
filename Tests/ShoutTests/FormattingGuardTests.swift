import XCTest

final class FormattingGuardTests: XCTestCase {

    // MARK: - Modell hat geantwortet statt formatiert
    //
    // Der gemeldete Fehler: Ein Diktat, das wie eine Bitte klingt, wird von der
    // Aufbereitung als Auftrag gelesen. Die Ausgabe ist dann eine Antwort und
    // besteht fast nur aus Wörtern, die nie diktiert wurden. Gemessen an 192
    // Diktaten mit gespeichertem Original: die vier echten Fehlfälle lagen bei
    // 17–22 % gemeinsamen Wörtern, gewöhnliches Bereinigen bei 91 % (Median).

    func testAntwortStattFormatierungWirdErkannt() {
        let diktat = "Könntest du bitte im Internet nach dem Logo suchen und es dann "
                   + "in die Präsentation einfügen, danke"
        let antwort = "Bitte gib mir den Text, den ich formatieren soll. "
                    + "Ich kann keine Logos aus dem Internet suchen."
        XCTAssertEqual(FormattingGuard.check(input: diktat, output: antwort),
                       .unrelated(inputSharePercent: 27))
    }

    /// Der Fall, an dem jede Längenregel scheitern MUSS: die Antwort ist länger
    /// als das Diktat (im Verlauf: 9 Wörter hinein, 11 heraus, 22 % behalten).
    func testLaengereAntwortWirdTrotzdemErkannt() {
        let diktat = "Schau mal kurz nach dem Preis"
        let antwort = "Bitte gib mir den Text, den ich für dich formatieren soll."
        guard case .unrelated = FormattingGuard.check(input: diktat, output: antwort) else {
            return XCTFail("eine längere, inhaltlich fremde Ausgabe muss auffallen")
        }
    }

    func testKnappeAbsageWirdErkannt() {
        let diktat = "Bitte lade das Bild herunter und schick es an das Team weiter"
        XCTAssertNotEqual(FormattingGuard.check(input: diktat, output: "Ich kann dir dabei nicht helfen."),
                          .ok)
    }

    // MARK: - Gewöhnliches Bereinigen bleibt unangetastet

    func testFuellwoerterEntfernenIstInOrdnung() {
        let diktat = "also äh ich glaube halt wir sollten quasi das Angebot noch mal "
                   + "durchrechnen bevor wir es rausschicken"
        let sauber = "Ich glaube, wir sollten das Angebot noch mal durchrechnen, "
                   + "bevor wir es rausschicken."
        XCTAssertEqual(FormattingGuard.check(input: diktat, output: sauber), .ok)
    }

    /// Umgangssprachliches Diktat, halbe Wortzahl heraus — und trotzdem in
    /// Ordnung, weil jedes Wort der Ausgabe diktiert wurde.
    func testStarkGekuerztAberInhaltlichPassendBleibtOk() {
        let diktat = "ja also das sieht irgendwie nicht so richtig aus finde ich "
                   + "das wirkt schon sehr komisch auf mich"
        let sauber = "Das sieht nicht richtig aus, das wirkt sehr komisch."
        XCTAssertEqual(FormattingGuard.check(input: diktat, output: sauber), .ok)
    }

    func testUmbauInEineListeBleibtOk() {
        let diktat = "wir brauchen erstens die Zahlen zweitens die Präsentation "
                   + "und drittens das Feedback vom Kunden"
        let sauber = "Wir brauchen:\n1. die Zahlen\n2. die Präsentation\n3. das Feedback vom Kunden"
        XCTAssertEqual(FormattingGuard.check(input: diktat, output: sauber), .ok)
    }

    // MARK: - Verschlucktes Ende (die bisherige Regel, unverändert ab 30 Wörtern)

    func testStarkeKuerzungBeiPassendemInhaltGiltAlsVerschluckt() {
        let diktat = (1...40).map { "Punkt\($0)" }.joined(separator: " ")
        let haelfte = (1...15).map { "Punkt\($0)" }.joined(separator: " ")
        XCTAssertEqual(FormattingGuard.check(input: diktat, output: haelfte),
                       .truncated(inWords: 40, outWords: 15))
    }

    /// Kurze Diktate nicht auf Kürzung prüfen: dort ist das Entfernen von
    /// Füllwörtern schnell die halbe Wortzahl, ohne dass Inhalt fehlt. Genau
    /// dieser Fall hat meinen ersten Maßstab widerlegt — er schlug hier an.
    func testKurzeDiktateWerdenNichtAufKuerzungGeprueft() {
        XCTAssertEqual(FormattingGuard.check(input: "also äh das ist gut ja wirklich gut",
                                             output: "Das ist gut."), .ok)
    }

    // MARK: - Ränder

    func testSehrKurzeEingabeWirdNichtBewertet() {
        // Unter fünf Wörtern ist die Wort-Überlappung Rauschen.
        XCTAssertEqual(FormattingGuard.check(input: "kurzer Test hier", output: "Etwas ganz anderes."), .ok)
    }

    func testLeereAusgabeFaelltAuf() {
        XCTAssertNotEqual(FormattingGuard.check(input: "ein etwas längerer Satz mit genug Wörtern drin",
                                                output: ""), .ok)
    }

    func testGroszschreibungUndSatzzeichenZaehlenNichtGegenDieAusgabe() {
        let diktat = "das angebot muss heute noch raus sonst wird das nichts mehr"
        let sauber = "Das Angebot muss heute noch raus, sonst wird das nichts mehr!"
        XCTAssertEqual(FormattingGuard.check(input: diktat, output: sauber), .ok)
    }
}
