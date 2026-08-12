import XCTest

/// Namensgebung für Mitschnitte: was aus einer Eingabe wird und wo sie landet.
@MainActor
final class MeetingNameTests: XCTestCase {

    // MARK: - Eingabe säubern

    func testNormalerNameBleibt() {
        XCTAssertEqual(MeetingRecorder.safeName("Kickoff Redesign"), "Kickoff Redesign")
    }

    /// Schrägstriche und Doppelpunkte zerlegen Pfade — sie müssen weg, bevor aus
    /// „Team: Q3/Q4" ein Ordner wird.
    func testPfadzeichenWerdenErsetzt() {
        XCTAssertEqual(MeetingRecorder.safeName("Team: Q3/Q4"), "Team- Q3-Q4")
    }

    /// Ein führender Punkt macht eine versteckte Datei — die fände niemand wieder.
    func testFuehrenderPunktFliegtRaus() {
        XCTAssertEqual(MeetingRecorder.safeName("...Geheim"), "Geheim")
    }

    func testLeereEingabeGibtNichts() {
        XCTAssertNil(MeetingRecorder.safeName("   "))
        XCTAssertNil(MeetingRecorder.safeName(""))
        XCTAssertNil(MeetingRecorder.safeName("."))
    }

    func testUmlauteBleibenErhalten() {
        XCTAssertEqual(MeetingRecorder.safeName("Jahresgespräch Müller"), "Jahresgespräch Müller")
    }

    /// Gekappt wird auf 80 Zeichen, und danach darf kein Leerzeichen am Ende stehen.
    func testSehrLangerNameWirdGekappt() throws {
        let name = try XCTUnwrap(MeetingRecorder.safeName(String(repeating: "a", count: 200)))
        XCTAssertEqual(name.count, 80)
        let mitLuecke = try XCTUnwrap(MeetingRecorder.safeName(String(repeating: "ab ", count: 40)))
        XCTAssertFalse(mitLuecke.hasSuffix(" "))
    }

    // MARK: - Freier Platz im Ordner

    func testFreierNameBleibtUnveraendert() throws {
        let ordner = try temporaererOrdner()
        let ziel = MeetingRecorder.freeTarget(in: ordner, name: "Kickoff", extension: "m4a")
        XCTAssertEqual(ziel.lastPathComponent, "Kickoff.m4a")
    }

    /// Zwei Meetings mit demselben Namen dürfen sich nicht überschreiben.
    func testBelegterNameBekommtEineZahl() throws {
        let ordner = try temporaererOrdner()
        try Data().write(to: ordner.appendingPathComponent("Kickoff.m4a"))
        XCTAssertEqual(
            MeetingRecorder.freeTarget(in: ordner, name: "Kickoff", extension: "m4a").lastPathComponent,
            "Kickoff 2.m4a")

        try Data().write(to: ordner.appendingPathComponent("Kickoff 2.m4a"))
        XCTAssertEqual(
            MeetingRecorder.freeTarget(in: ordner, name: "Kickoff", extension: "m4a").lastPathComponent,
            "Kickoff 3.m4a")
    }

    private func temporaererOrdner() throws -> URL {
        let ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-namen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: ordner) }
        return ordner
    }
}
