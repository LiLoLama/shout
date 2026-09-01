import XCTest

final class AudioWindowsTests: XCTestCase {

    /// Bewusst NICHT 16 kHz: Die Fensterung rechnet in Sekunden und ist damit
    /// taktunabhängig, aber 35 Minuten bei 16 kHz sind 33 Millionen Werte — der
    /// ganze Testlauf wurde davon von 1,5 auf 16 Sekunden langsamer. Mit 1 kHz
    /// bleiben die Verhältnisse (Minuten, Fensterlängen) unverändert prüfbar.
    private let takt = 1_000

    private func stille(_ sekunden: Double) -> [Float] {
        [Float](repeating: 0, count: Int(sekunden * Double(takt)))
    }

    /// „Sprache": abwechselnde Werte, damit die Energie deutlich über null liegt.
    private func sprache(_ sekunden: Double) -> [Float] {
        let anzahl = Int(sekunden * Double(takt))
        return (0..<anzahl).map { $0 % 2 == 0 ? Float(0.5) : Float(-0.5) }
    }

    // MARK: - Kurze Aufnahmen bleiben unangetastet

    func testKurzeAufnahmeErgibtEinFenster() {
        let fenster = AudioWindows.split(sprache(30), sampleRate: takt, maxSeconds: 600)
        XCTAssertEqual(fenster.count, 1)
        XCTAssertEqual(fenster.first?.range, 0..<(30 * takt))
        XCTAssertEqual(fenster.first?.offsetSeconds, 0)
    }

    /// Genau an der Grenze wird noch nicht geschnitten.
    func testGenauAufDerGrenzeEinFenster() {
        let fenster = AudioWindows.split(sprache(60), sampleRate: takt, maxSeconds: 60)
        XCTAssertEqual(fenster.count, 1)
    }

    func testLeereEingabeErgibtKeinFenster() {
        XCTAssertTrue(AudioWindows.split([], sampleRate: takt).isEmpty)
    }

    // MARK: - Lange Aufnahmen werden geteilt

    /// Der Fall aus dem Alltag der Datei-Transkription: 25 Minuten bei
    /// Zehn-Minuten-Fenstern.
    func testFuenfundzwanzigMinutenErgebenDreiFenster() {
        let fenster = AudioWindows.split(sprache(25 * 60), sampleRate: takt,
                                         maxSeconds: 600, searchSeconds: 15)
        XCTAssertEqual(fenster.count, 3)
    }

    /// Kein Sample darf fehlen und keines doppelt vorkommen — die Fenster müssen
    /// die Aufnahme lückenlos und ohne Überlappung abdecken. Das ist die
    /// wichtigste Eigenschaft: eine Lücke wäre stiller Inhaltsverlust, eine
    /// Überlappung ein doppelt transkribiertes Stück.
    func testFensterDeckenLueckenlosUndOhneUeberlappungAb() {
        let samples = sprache(25 * 60)
        let fenster = AudioWindows.split(samples, sampleRate: takt, maxSeconds: 600)

        XCTAssertEqual(fenster.first?.range.lowerBound, 0)
        XCTAssertEqual(fenster.last?.range.upperBound, samples.count)
        for (a, b) in zip(fenster, fenster.dropFirst()) {
            XCTAssertEqual(a.range.upperBound, b.range.lowerBound,
                           "Lücke oder Überlappung zwischen zwei Fenstern")
        }
    }

    /// Die Zeitversätze müssen zum Beginn des jeweiligen Fensters passen — sonst
    /// stimmen die Untertitel-Zeitmarken nicht.
    func testZeitversatzPasstZumFensterbeginn() {
        let fenster = AudioWindows.split(sprache(25 * 60), sampleRate: takt, maxSeconds: 600)
        for f in fenster {
            XCTAssertEqual(f.offsetSeconds, Double(f.range.lowerBound) / Double(takt),
                           accuracy: 0.0001)
        }
        XCTAssertEqual(fenster.first?.offsetSeconds, 0)
    }

    func testZeitversaetzeSteigen() {
        let fenster = AudioWindows.split(sprache(25 * 60), sampleRate: takt, maxSeconds: 600)
        for (a, b) in zip(fenster, fenster.dropFirst()) {
            XCTAssertLessThan(a.offsetSeconds, b.offsetSeconds)
        }
    }

    // MARK: - Geschnitten wird in der Pause

    /// Der Kern des Verfahrens: Liegt im Suchbereich eine Sprechpause, muss der
    /// Schnitt dort liegen und nicht stur bei der Höchstlänge. Aufbau: 9 Minuten
    /// Sprache, eine Sekunde Stille, dann weiter — bei zehn Minuten Fensterlänge
    /// und 90 s Suchbereich muss die Stille getroffen werden.
    func testSchnittLiegtInDerSprechpause() {
        var samples = sprache(9 * 60)
        let pauseBeginn = samples.count
        samples += stille(1)
        let pauseEnde = samples.count
        samples += sprache(9 * 60)

        let fenster = AudioWindows.split(samples, sampleRate: takt,
                                         maxSeconds: 600, searchSeconds: 90)

        XCTAssertEqual(fenster.count, 2)
        let schnitt = fenster[0].range.upperBound
        XCTAssertGreaterThanOrEqual(schnitt, pauseBeginn,
                                    "Der Schnitt liegt vor der Pause")
        XCTAssertLessThanOrEqual(schnitt, pauseEnde,
                                 "Der Schnitt liegt hinter der Pause")
    }

    /// Ohne Pause im Suchbereich wird trotzdem geschnitten — nur eben irgendwo.
    /// Wichtig ist, dass es überhaupt weitergeht und nichts verloren geht.
    func testOhneJedePauseWirdTrotzdemGeteilt() {
        let samples = sprache(25 * 60)
        let fenster = AudioWindows.split(samples, sampleRate: takt, maxSeconds: 600,
                                         searchSeconds: 15)
        XCTAssertGreaterThan(fenster.count, 1)
        XCTAssertEqual(fenster.last?.range.upperBound, samples.count)
    }

    /// Der Schnitt darf nie hinter die Höchstlänge rutschen, sonst wird das
    /// Fenster zu groß für den Endpunkt.
    func testKeinFensterUeberschreitetDieHoechstlaenge() {
        let fenster = AudioWindows.split(sprache(35 * 60), sampleRate: takt, maxSeconds: 600)
        for f in fenster {
            XCTAssertLessThanOrEqual(f.range.count, 600 * takt)
        }
    }

    /// Und nie so weit nach vorn, dass ein Fenster leer wird — sonst dreht die
    /// Schleife endlos.
    func testKeinLeeresFenster() {
        let fenster = AudioWindows.split(sprache(35 * 60), sampleRate: takt, maxSeconds: 600)
        for f in fenster {
            XCTAssertGreaterThan(f.range.count, 0)
        }
    }

    /// Jedes Fenster muss auch als WAV unter die Größengrenze passen — das ist
    /// der Zweck der Übung. Gerechnet wird mit dem echten Takt von 16 kHz, sonst
    /// prüft der Test nichts: Ein Fenster von 600 s ergibt dort 19,2 MB.
    func testJedesFensterPasstAlsWAVUnterDieGrenze() {
        let grenze = 25 * 1_024 * 1_024
        let sekundenJeFenster = 600.0
        let bytes = WAVEncoder.headerBytes + Int(sekundenJeFenster * 16_000) * 2
        XCTAssertLessThan(bytes, grenze)
        XCTAssertGreaterThan(bytes, 15 * 1_024 * 1_024,
                             "Deutlich kleiner wäre unnötig viele Anfragen")
    }
}
