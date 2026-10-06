import XCTest

final class FormatterTransformTests: XCTestCase {

    private func formatter(_ engine: StubTextEngine) async -> Formatter {
        let f = Formatter(makeEngine: { engine })
        await f.load()
        return f
    }

    func testAnweisungImSystemTextZwischenDenMarkierungen() async throws {
        let engine = StubTextEngine(answers: ["- Punkt"])
        let f = await formatter(engine)
        let ergebnis = try await f.transform("Ein langer Text.", instruction: "Fasse zusammen.")
        XCTAssertEqual(ergebnis, "- Punkt")
        let system = await engine.recordedSystems.first ?? ""
        let user = await engine.recordedPrompts.first ?? ""
        XCTAssertTrue(system.contains("Fasse zusammen."))
        XCTAssertTrue(system.contains("Gib nur das Ergebnis zurück"))
        XCTAssertTrue(user.contains("\(TransformPrompt.begin)\nEin langer Text.\n\(TransformPrompt.end)"))
    }

    func testZuLangWirftOhneAufruf() async {
        let engine = StubTextEngine(answers: ["x"])
        let f = await formatter(engine)
        do {
            _ = try await f.transform(String(repeating: "a", count: TransformPrompt.maxLength + 1), instruction: "x")
            XCTFail("hätte werfen müssen")
        } catch {
            XCTAssertEqual(error as? TransformError, .tooLong)
        }
        let aufrufe = await engine.recordedPrompts.count
        XCTAssertEqual(aufrufe, 0)
    }

    func testGenauAnDerGrenzeGeht() async throws {
        let f = await formatter(StubTextEngine(answers: ["ok"]))
        let ergebnis = try await f.transform(String(repeating: "a", count: TransformPrompt.maxLength), instruction: "x")
        XCTAssertEqual(ergebnis, "ok")
    }

    func testLeeresErgebnisWirdVerworfen() async {
        let f = await formatter(StubTextEngine(answers: ["  \n "]))
        do {
            _ = try await f.transform("Text", instruction: "x")
            XCTFail("hätte werfen müssen")
        } catch {
            XCTAssertEqual(error as? TransformError, .emptyResult)
        }
    }

    func testVorredeFaelltWeg() async throws {
        let f = await formatter(StubTextEngine(answers: ["Hier ist die Zusammenfassung:\n\n- a\n- b"]))
        let ergebnis = try await f.transform("Text", instruction: "x")
        XCTAssertEqual(ergebnis, "- a\n- b")
    }

    func testKeinWaechterFremdeAntwortIstGewollt() async throws {
        let f = await formatter(StubTextEngine(answers: ["Dear Anna,\n\nthanks."]))
        let ergebnis = try await f.transform("Liebe Anna, danke.", instruction: "Ins Englische.")
        XCTAssertEqual(ergebnis, "Dear Anna,\n\nthanks.")
    }

    func testOhneModellNoModel() async {
        let f = await formatter(StubTextEngine(answers: ["x"], isReady: false))
        do {
            _ = try await f.transform("Text", instruction: "x")
            XCTFail("hätte werfen müssen")
        } catch {
            XCTAssertEqual(error as? TransformError, .noModel)
        }
    }

    func testVoruebergehenderFehlerZweiterVersuch() async throws {
        let engine = StubTextEngine(answers: [nil, "gut"])
        await engine.setzeFehler(.cannotConnect(code: -1004))
        let f = await formatter(engine)
        let ergebnis = try await f.transform("Text", instruction: "x")
        XCTAssertEqual(ergebnis, "gut")
        let aufrufe = await engine.recordedPrompts.count
        XCTAssertEqual(aufrufe, 2)
    }

    func testAbgelehnterSchluesselKeinZweiterVersuch() async {
        let engine = StubTextEngine(answers: [nil, "gut"])
        await engine.setzeFehler(.unauthorized)
        let f = await formatter(engine)
        do {
            _ = try await f.transform("Text", instruction: "x")
            XCTFail("hätte werfen müssen")
        } catch {
            guard case .failed = error as? TransformError else { return XCTFail("falscher Fehler: \(error)") }
        }
        let aufrufe = await engine.recordedPrompts.count
        XCTAssertEqual(aufrufe, 1)
    }

    func testZweimalZeitlimitTimedOut() async {
        let engine = StubTextEngine(answers: [nil, nil])
        await engine.setzeFehler(.timedOut)
        let f = await formatter(engine)
        do {
            _ = try await f.transform("Text", instruction: "x")
            XCTFail("hätte werfen müssen")
        } catch {
            XCTAssertEqual(error as? TransformError, .timedOut)
        }
    }

    func testCodeblockUmDieGanzeAntwortFaelltWeg() {
        XCTAssertEqual(TransformPrompt.clean("```markdown\n# Titel\n```"), "# Titel")
    }

    func testNormaleErsteZeileMitDoppelpunktBleibt() {
        XCTAssertEqual(TransformPrompt.clean("Einkauf:\n- Milch"), "Einkauf:\n- Milch")
    }
}
