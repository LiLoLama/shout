import XCTest

/// Tests für Zeitgrenzen und Wiederholungsversuche.
///
/// Der Kern: Beim Diktat darf nichts hängen, aber ein **lokales** Modell darf
/// sich Zeit nehmen. Diese beiden Anforderungen widersprechen sich scheinbar —
/// gelöst wird es dadurch, dass die Grenze der Engine gehört und lokal `nil` ist.
final class FormatterDeadlineTests: XCTestCase {

    private let langesDiktat =
        "also ich wollte nur kurz sagen dass der Termin am Dienstag leider nicht "
      + "klappt weil ich da schon beim Zahnarzt bin"

    // MARK: - Grenze beim Diktat

    /// Hängt die Engine über ihre Grenze hinaus, kommt der Rohtext. Grenze und
    /// Verzögerung sind klein gehalten, damit der Test nicht wartet.
    func testHaengendeEngineLiefertRohtext() async {
        let engine = StubTextEngine(fallback: "Aufbereitet.",
                                    callTimeout: 0.05,
                                    delay: .milliseconds(600))
        let formatter = Formatter(makeEngine: { engine })
        await formatter.load()

        let start = Date()
        let ergebnis = await formatter.format(langesDiktat, bundleID: nil)
        let dauer = Date().timeIntervalSince(start)

        XCTAssertEqual(ergebnis, langesDiktat)
        XCTAssertLessThan(dauer, 0.5, "Die Grenze muss vor der Engine greifen")
    }

    /// Ohne Grenze (`nil` — das lokale Modell) wird gewartet, nicht abgeschnitten.
    /// Wäre das anders, würde ein großes Gemma auf einem langsamen Mac plötzlich
    /// keine Aufbereitung mehr liefern.
    func testOhneGrenzeWirdGewartet() async {
        let engine = StubTextEngine(fallback: "Der Termin am Dienstag klappt leider nicht, "
                                           + "weil ich beim Zahnarzt bin.",
                                    callTimeout: nil,
                                    delay: .milliseconds(120))
        let formatter = Formatter(makeEngine: { engine })
        await formatter.load()

        let ergebnis = await formatter.format(langesDiktat, bundleID: nil)

        XCTAssertTrue(ergebnis.contains("Zahnarzt"))
        XCTAssertNotEqual(ergebnis, langesDiktat, "Ohne Grenze muss das Ergebnis ankommen")
    }

    /// Bleibt die Engine unter der Grenze, passiert nichts Besonderes.
    func testUnterDerGrenzeKommtDasErgebnis() async {
        let engine = StubTextEngine(fallback: "Der Termin am Dienstag klappt leider nicht, "
                                           + "weil ich beim Zahnarzt bin.",
                                    callTimeout: 5,
                                    delay: .milliseconds(20))
        let formatter = Formatter(makeEngine: { engine })
        await formatter.load()

        let ergebnis = await formatter.format(langesDiktat, bundleID: nil)

        XCTAssertTrue(ergebnis.contains("Zahnarzt"))
    }

    // MARK: - Kein Wiederholungsversuch beim Diktat

    /// Beim Diktat wird genau einmal gefragt. Ein zweiter Anlauf würde die
    /// Wartezeit verdoppeln, während jemand mit dem Finger auf der Taste steht.
    func testDiktatFragtGenauEinmal() async {
        let engine = StubTextEngine(answers: [nil, "Käme zu spät."])
        let formatter = Formatter(makeEngine: { engine })
        await formatter.load()

        let ergebnis = await formatter.format(langesDiktat, bundleID: nil)

        XCTAssertEqual(ergebnis, langesDiktat)
        let aufrufe = await engine.recordedPrompts.count
        XCTAssertEqual(aufrufe, 1, "Kein Wiederholungsversuch beim Diktat")
    }

    // MARK: - Ein Wiederholungsversuch bei Protokollen

    /// Im Hintergrund ist ein zweiter Anlauf billiger als ein fehlender
    /// Protokollabschnitt.
    func testProtokollVersuchtEinZweitesMal() async {
        let antwort = """
        TITEL: Terminabsage
        PUNKTE:
        - Dienstag klappt nicht
        TEXT:
        Der Termin am Dienstag klappt nicht.
        """
        // Erst eine Zeitüberschreitung, dann die Antwort. Zwei weitere für die
        // Zusammenfassungsstufe.
        let engine = StubTextEngine(answers: [nil, antwort], fallback: "Eine Zusammenfassung.",
                                    callTimeout: 0.05, delay: nil)
        // Zeitüberschreitung ist eine Ursache, die von selbst weggeht — nur dann
        // wird überhaupt wiederholt.
        await engine.setzeFehler(.timedOut)
        let formatter = Formatter(makeEngine: { engine })
        await formatter.load()

        let ergebnis = await formatter.minutes(from: langesDiktat)

        XCTAssertNotNil(ergebnis, "Der zweite Versuch muss das Protokoll retten")
        let aufrufe = await engine.recordedPrompts.count
        XCTAssertGreaterThanOrEqual(aufrufe, 2)
    }

    /// Aber nur bei Ursachen, die von selbst weggehen. Ein abgelehnter Schlüssel
    /// wird beim zweiten Mal genauso abgelehnt — das wäre nur Wartezeit.
    func testAbgelehnterSchluesselWirdNichtWiederholt() async {
        let engine = StubTextEngine(answers: [nil], fallback: nil, callTimeout: 5)
        await engine.setzeFehler(.unauthorized)
        let formatter = Formatter(makeEngine: { engine })
        await formatter.load()

        _ = await formatter.minutes(from: langesDiktat)

        let aufrufe = await engine.recordedPrompts.count
        XCTAssertEqual(aufrufe, 1, "Ein abgelehnter Schlüssel wird nicht wiederholt")
    }

    // MARK: - Der Deadline-Helfer für sich

    func testDeadlineLaesstSchnellesDurch() async throws {
        let wert = try await withDeadline(1) { 42 }
        XCTAssertEqual(wert, 42)
    }

    func testDeadlineBrichtLangsamesAb() async {
        do {
            _ = try await withDeadline(0.05) {
                try await Task.sleep(nanoseconds: 600_000_000)
                return 42
            }
            XCTFail("Die Grenze hätte greifen müssen")
        } catch {
            XCTAssertEqual(error as? RemoteProviderError, .timedOut)
        }
    }

    /// `nil` heißt: keine Grenze, auch nicht bei langer Laufzeit.
    func testKeineGrenzeBrichtNichtAb() async throws {
        let wert = try await withDeadline(nil) {
            try await Task.sleep(nanoseconds: 60_000_000)
            return 42
        }
        XCTAssertEqual(wert, 42)
    }
}
