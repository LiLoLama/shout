import XCTest

final class AbkuerzungsgedaechtnisTests: XCTestCase {

    private var gedaechtnis: Abkuerzungsgedaechtnis!

    override func setUp() {
        super.setUp()
        // Eine eigene Ausgabe je Test, nicht die geteilte: Ein Gedächtnis, das
        // sich Tests merkt, wäre kein Gedächtnis mehr, sondern ein Zufall.
        gedaechtnis = Abkuerzungsgedaechtnis()
    }

    /// Ohne Vorgeschichte wird abgekürzt — genau dafür ist die Abkürzung da.
    func testOhneVorgeschichteDarfAbgekuerztWerden() {
        XCTAssertTrue(gedaechtnis.darfAbkuerzen("mlx-community/Qwen3-4B-4bit"))
    }

    /// Der Kern: Scheitert das Laden eines über die Abkürzung gelieferten
    /// Pfades, nimmt der nächste Versuch sie nicht erneut. Sonst bliebe die
    /// Aufbereitung dauerhaft und unbemerkt tot — jeder weitere Versuch
    /// bekäme denselben nicht ladbaren Ordner.
    func testGescheiterteAbkuerzungWirdNichtWiederholt() {
        gedaechtnis.abkuerzungGemerkt("mlx-community/Qwen3-4B-4bit")
        gedaechtnis.ladenGescheitert("mlx-community/Qwen3-4B-4bit")
        XCTAssertFalse(gedaechtnis.darfAbkuerzen("mlx-community/Qwen3-4B-4bit"))
    }

    /// Die Sperre gilt nur für die eine Kennung. Ein unbrauchbarer fremder
    /// Ordner sagt nichts über die anderen Modelle darin.
    func testSperreGiltNurFuerDieEigeneKennung() {
        gedaechtnis.abkuerzungGemerkt("mlx-community/Qwen3-4B-4bit")
        gedaechtnis.ladenGescheitert("mlx-community/Qwen3-4B-4bit")
        XCTAssertTrue(gedaechtnis.darfAbkuerzen("mlx-community/anderes-Modell"))
    }

    /// Ein Fehler OHNE vorherige Abkürzung darf nichts sperren: Der Pfad kam
    /// dann vom Hub, und ein abgerissenes Netz oder eine volle Platte bringt
    /// keinen fremden Ordner in Verruf.
    func testFehlerOhneAbkuerzungSperrtNichts() {
        gedaechtnis.ladenGescheitert("mlx-community/Qwen3-4B-4bit")
        XCTAssertTrue(gedaechtnis.darfAbkuerzen("mlx-community/Qwen3-4B-4bit"))
    }

    /// Nach einem gelungenen Ladevorgang ist der Hinweis verbraucht: Ein
    /// späterer Fehler aus ganz anderem Grund darf nicht nachträglich der
    /// Abkürzung angelastet werden.
    func testNachGelungenemLadenSperrtEinSpaetererFehlerNicht() {
        gedaechtnis.abkuerzungGemerkt("mlx-community/Qwen3-4B-4bit")
        gedaechtnis.ladenGelungen("mlx-community/Qwen3-4B-4bit")
        gedaechtnis.ladenGescheitert("mlx-community/Qwen3-4B-4bit")
        XCTAssertTrue(gedaechtnis.darfAbkuerzen("mlx-community/Qwen3-4B-4bit"))
    }

    /// Ein zweiter Fehlschlag ändert nichts mehr — gesperrt bleibt gesperrt.
    func testZweiterFehlschlagAendertNichts() {
        gedaechtnis.abkuerzungGemerkt("mlx-community/Qwen3-4B-4bit")
        gedaechtnis.ladenGescheitert("mlx-community/Qwen3-4B-4bit")
        gedaechtnis.ladenGescheitert("mlx-community/Qwen3-4B-4bit")
        XCTAssertFalse(gedaechtnis.darfAbkuerzen("mlx-community/Qwen3-4B-4bit"))
    }
}
