import XCTest
import CoreGraphics

final class PillPlacementTests: XCTestCase {

    /// Ultrawide, wie er bei angeschlossenem Monitor gemeldet wird.
    private let breit = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    /// Eingebautes Display, wenn der Monitor abgesteckt ist.
    private let schmal = CGRect(x: 0, y: 0, width: 1512, height: 945)

    // MARK: - Der eigentliche Fehler

    /// Genau der gemeldete Fall: Pille unten in der Mitte des Ultrawide, Monitor ab.
    /// Vorher wanderte sie an den rechten Rand, weil die Position absolut gespeichert
    /// war und x ≈ 1720 auf dem kleinen Schirm nicht mehr existierte.
    func testUntenMitteBleibtUntenMitte() {
        let aufBreit = CGPoint(x: breit.midX, y: breit.minY + 20)
        let anteil = PillPlacement.fraction(of: aufBreit, in: breit)
        let aufSchmal = PillPlacement.center(for: anteil, in: schmal)

        XCTAssertEqual(aufSchmal.x, schmal.midX, accuracy: 0.5, "Mitte muss Mitte bleiben")
        XCTAssertLessThan(aufSchmal.y, schmal.height * 0.1, "unten muss unten bleiben")
        XCTAssertLessThan(aufSchmal.x, schmal.maxX - 100, "darf nicht an den Rand rutschen")
    }

    func testLinkeKanteBleibtLinkeKante() {
        let links = CGPoint(x: breit.minX + 30, y: breit.midY)
        let anteil = PillPlacement.fraction(of: links, in: breit)
        let umgerechnet = PillPlacement.center(for: anteil, in: schmal)
        XCTAssertLessThan(umgerechnet.x, schmal.width * 0.05)
        XCTAssertEqual(umgerechnet.y, schmal.midY, accuracy: 1)
    }

    /// Ein Bildschirm, dessen Ursprung nicht bei null liegt (zweiter Monitor rechts).
    func testVersetzterBildschirm() {
        let versetzt = CGRect(x: 1512, y: 200, width: 2560, height: 1440)
        let punkt = CGPoint(x: versetzt.midX, y: versetzt.minY + 10)
        let anteil = PillPlacement.fraction(of: punkt, in: versetzt)
        XCTAssertEqual(anteil.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(PillPlacement.center(for: anteil, in: versetzt).x, punkt.x, accuracy: 0.5)
    }

    func testAnteilBleibtImRahmen() {
        let weitDraussen = PillPlacement.fraction(of: CGPoint(x: 9000, y: -400), in: schmal)
        let zurueck = PillPlacement.center(for: weitDraussen, in: schmal)
        XCTAssertGreaterThanOrEqual(zurueck.x, schmal.minX)
        XCTAssertLessThanOrEqual(zurueck.x, schmal.maxX)
        XCTAssertGreaterThanOrEqual(zurueck.y, schmal.minY)
    }

    // MARK: - Ausrichtung

    func testSeitenkanteWirdSenkrecht() {
        XCTAssertTrue(PillPlacement.prefersVertical(at: CGPoint(x: 0.01, y: 0.5)))
        XCTAssertTrue(PillPlacement.prefersVertical(at: CGPoint(x: 0.99, y: 0.5)))
    }

    func testObenUndUntenBleibenWaagerecht() {
        XCTAssertFalse(PillPlacement.prefersVertical(at: CGPoint(x: 0.5, y: 0.02)))
        XCTAssertFalse(PillPlacement.prefersVertical(at: CGPoint(x: 0.5, y: 0.98)))
    }

    /// In der Ecke ist beides gleich nah — dann bleibt es bei der gewohnten,
    /// waagerechten Pille.
    func testEckeBleibtWaagerecht() {
        XCTAssertFalse(PillPlacement.prefersVertical(at: CGPoint(x: 0.02, y: 0.02)))
        XCTAssertFalse(PillPlacement.prefersVertical(at: CGPoint(x: 0.98, y: 0.98)))
    }

    /// Mitte des Bildschirms: keine Kante ist nah, waagerecht ist die ruhigere Wahl.
    func testMitteBleibtWaagerecht() {
        XCTAssertFalse(PillPlacement.prefersVertical(at: CGPoint(x: 0.5, y: 0.5)))
    }
}
