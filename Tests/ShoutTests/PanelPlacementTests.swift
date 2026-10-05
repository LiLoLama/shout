import XCTest

/// Der Panel-Rahmen als Anteil der sichtbaren Fläche: Er übersteht das Umstecken
/// auf einen anderen Bildschirm und bleibt immer ganz sichtbar.
final class PanelPlacementTests: XCTestCase {

    private let gross = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let minimum = CGSize(width: 360, height: 260)

    func testRundlaufAufDemselbenBildschirm() {
        let rahmen = CGRect(x: 400, y: 300, width: 500, height: 400)
        let gesichert = PanelPlacement.save(rahmen, in: gross, screen: "1")
        XCTAssertEqual(PanelPlacement.restore(gesichert, in: gross, minSize: minimum), rahmen)
        XCTAssertEqual(gesichert.screen, "1")
    }

    func testKleinererBildschirmBleibtSichtbarUndMindestgross() {
        let gesichert = PanelPlacement.save(CGRect(x: 400, y: 300, width: 500, height: 400), in: gross, screen: nil)
        let klein = CGRect(x: 0, y: 0, width: 500, height: 400)
        XCTAssertEqual(PanelPlacement.restore(gesichert, in: klein, minSize: minimum),
                       CGRect(x: 140, y: 140, width: 360, height: 260))
    }

    func testVersetzterBildschirm() {
        let rechts = CGRect(x: 1000, y: 100, width: 1000, height: 800)
        let rahmen = CGRect(x: 1500, y: 500, width: 400, height: 300)
        let gesichert = PanelPlacement.save(rahmen, in: rechts, screen: nil)
        XCTAssertEqual(PanelPlacement.restore(gesichert, in: rechts, minSize: minimum), rahmen)
    }

    func testErsterStartObenRechts() {
        XCTAssertEqual(PanelPlacement.initial(in: gross, size: CGSize(width: 520, height: 420)),
                       CGRect(x: 464, y: 364, width: 520, height: 420))
    }
}
