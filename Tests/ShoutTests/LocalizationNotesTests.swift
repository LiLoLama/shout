import XCTest

/// Alle neuen Texte der Seite „Notizen“. Ein doppelter Schlüssel bringt schon
/// diesen Test zum Absturz — genau das ist erwünscht, solange es hier passiert.
@MainActor
final class LocalizationNotesTests: XCTestCase {

    private let schluessel = [
        "Notizen",
        "Neue Notiz",
        "Ordner",
        "Jede Notiz ist eine Markdown-Datei in diesem Ordner. Liegt er in iCloud Drive oder einem Obsidian-Vault, findest du die Notizen auch dort.",
        "Im Finder zeigen",
        "Wählen …",
        "Der Ordner ist nicht erreichbar. Änderungen werden zwischengespeichert und landen dort, sobald er wieder da ist.",
        "Notizen durchsuchen",
        "Noch keine Notizen",
        "Keine Treffer",
        "Wähle links eine Notiz oder lege eine neue an.",
        "Diktiere oder tippe eine neue Notiz — sie landet als Datei in deinem Ordner.",
        "Anheften",
        "Lösen",
        "Umbenennen …",
        "Notiz umbenennen",
        "Titel",
        "„%@“ gelöscht",
        "Diese Notiz wurde auch anderswo geändert. Deine Fassung liegt als „%@“ daneben.",
        "Diese Notiz ist nicht mehr im Ordner.",
        "Wieder sichern",
        "Wird aus iCloud geladen …",
        "Unbenannt",
        "(Konflikt)",
        // Ausweg, wenn das Sichern dauerhaft scheitert
        "Konnte nicht gesichert werden. Wechseln, Löschen und Ordnerwechsel sind gesperrt, bis gesichert ist.",
        "Erneut sichern",
        "Text kopieren",
        "Verwerfen …",
        "Ungesicherten Text verwerfen?",
        "Der Text dieser Notiz ist nirgends gesichert. Kopiere ihn vorher, wenn du ihn behalten willst.",
        // schon vorhanden, hier mitgeprüft, weil die Seite sie benutzt
        "Löschen",
        "Rückgängig",
        "Umbenennen",
        "Abbrechen",
        "Wählen",
        "Verwerfen",
    ]

    override func setUp() {
        super.setUp()
        Loc.shared.apply("en")
    }

    override func tearDown() {
        Loc.shared.apply("system")
        super.tearDown()
    }

    func testAlleNotizTexteSindUebersetzt() {
        for text in schluessel {
            let englisch = Loc.t(text)
            XCTAssertFalse(englisch.isEmpty, "Leere Übersetzung für „\(text)“")
            XCTAssertNotEqual(englisch, text, "Keine englische Fassung für „\(text)“")
        }
    }
}
