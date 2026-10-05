import XCTest

@MainActor
final class NotesFolderTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!
    private let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

    override func setUp() {
        super.setUp()
        suite = "shout-notesfolder-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testVorgabe() {
        XCTAssertEqual(NotesFolder.defaultURL(german: true, home: home).path, "/Users/test/Documents/shout Notizen")
        XCTAssertEqual(NotesFolder.defaultURL(german: false, home: home).path, "/Users/test/Documents/shout Notes")
    }

    /// Die Vorgabe wird beim ersten Aufruf festgeschrieben. Sonst hieße der
    /// Ordner nach einem Sprachwechsel anders, und die Notizen wären scheinbar weg.
    func testErsterAufrufSchreibtVorgabeFest() {
        let deutsch = NotesFolder.current(defaults: defaults, german: true, home: home)
        let spaeter = NotesFolder.current(defaults: defaults, german: false, home: home)
        XCTAssertEqual(spaeter.path, deutsch.path)
        XCTAssertEqual(defaults.string(forKey: NotesFolder.defaultsKey), "/Users/test/Documents/shout Notizen")
    }

    func testGewaehlterOrdner() {
        NotesFolder.set(URL(fileURLWithPath: "/Volumes/Daten/Notizen", isDirectory: true), defaults: defaults)
        XCTAssertEqual(NotesFolder.current(defaults: defaults, home: home).path, "/Volumes/Daten/Notizen")
    }

    func testIstVorgabe() {
        XCTAssertTrue(NotesFolder.isDefault(NotesFolder.defaultURL(german: false, home: home), home: home))
        XCTAssertTrue(NotesFolder.isDefault(NotesFolder.defaultURL(german: true, home: home), home: home))
        XCTAssertFalse(NotesFolder.isDefault(URL(fileURLWithPath: "/Volumes/Daten/Notizen"), home: home))
    }
}
