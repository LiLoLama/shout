import XCTest

final class AbbruchFlaggeTests: XCTestCase {

    /// Frisch ist nichts gewünscht. Andernfalls bräche jede Suche ab, bevor
    /// sie den ersten Ordner gesehen hat.
    func testFrischeFlaggeIstNichtGesetzt() {
        XCTAssertFalse(AbbruchFlagge().istGesetzt)
    }

    /// Gesetzt bleibt gesetzt — auch von einem anderen Strang aus und auch
    /// mehrfach gesetzt. Genau so benutzt die Oberfläche sie: Der Knopf setzt
    /// auf dem Hauptstrang, die Suche liest nebenher.
    func testSetzenWirktUeberStrangGrenzeUndBleibt() async {
        let flagge = AbbruchFlagge()
        await Task.detached { flagge.setzen(); flagge.setzen() }.value
        XCTAssertTrue(flagge.istGesetzt)
    }
}
