import XCTest

@MainActor
final class DeferredTerminationTests: XCTestCase {

    func testAntwortetGenauEinmal() {
        var antworten: [Bool] = []
        let warten = DeferredTermination { antworten.append($0) }
        XCTAssertTrue(warten.isPending)

        XCTAssertTrue(warten.resolve { true })
        XCTAssertFalse(warten.resolve { false }, "zweiter Weg, etwa der Sicherheits-Zeitgeber")

        XCTAssertEqual(antworten, [true])
        XCTAssertFalse(warten.isPending)
    }

    func testAbbrechenWirdWeitergegeben() {
        var antworten: [Bool] = []
        let warten = DeferredTermination { antworten.append($0) }
        warten.resolve { false }
        XCTAssertEqual(antworten, [false])
    }

    /// Ein modaler Hinweis in den Prüfungen lässt den Main-Actor weiterlaufen. Wird
    /// das Diktat währenddessen fertig, darf es weder ein zweites Mal fragen noch
    /// ein zweites Mal antworten.
    func testVerschachtelterAufrufWaehrendDerPruefungTutNichts() {
        var antworten: [Bool] = []
        var gefragt = 0
        let warten = DeferredTermination { antworten.append($0) }

        warten.resolve {
            gefragt += 1
            XCTAssertFalse(warten.isPending)
            let innen = warten.resolve {
                gefragt += 1
                return false
            }
            XCTAssertFalse(innen)
            return true
        }

        XCTAssertEqual(gefragt, 1)
        XCTAssertEqual(antworten, [true])
    }

    func testNachDerAntwortWirdNichtMehrGefragt() {
        let warten = DeferredTermination { _ in }
        warten.resolve { true }
        var gefragt = false
        warten.resolve {
            gefragt = true
            return true
        }
        XCTAssertFalse(gefragt)
    }
}
