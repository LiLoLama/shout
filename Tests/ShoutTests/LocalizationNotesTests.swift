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
        "Eine Notiz konnte nicht gesichert werden.",
        "Weder im Notizordner noch als Rettungskopie war Platz. Der Text geht beim Beenden verloren.",
        "Text kopieren und beenden",
        // Beenden, während ein Diktat noch verarbeitet wird
        "Ein Diktat wird noch verarbeitet.",
        "Wenn du jetzt beendest, geht es verloren.",
        // Hinweis auf gerettete Notizen
        "Beim letzten Beenden wurden ungesicherte Notizen gerettet.",
        "In den Notizordner holen",
        // Scratchpad-Tasten
        "Mit ⌃ oder ⌥ kombinieren",
        "Schon belegt",
        "Von einer anderen App belegt",
        // Scratchpad: Hinweise beim Zustellen eines Diktats („Scratchpad“ selbst
        // heißt auch englisch so und kann deshalb nicht in diese Liste)
        "Die Notiz nimmt gerade nichts an. Der Text liegt in der Zwischenablage.",
        "Im Eingang notiert",
        "Der Eingang ist gerade nicht erreichbar. Der Text liegt in der Zwischenablage.",
        // Scratchpad-Panel
        "Eingang.md",
        "Neuer Tab",
        "Tab schließen",
        "Liste ein/aus",
        "Noch keine Notiz offen. ⌘N legt eine neue an.",
        "Diktat beenden",
        "In diese Notiz diktieren",
        "Konnte nicht angemeldet werden",
        // Scratchpad-Einstellungen und Hinweiskarte
        "Scratchpad aktiv",
        "Schwebender Notizblock mit eigenen Tasten.",
        "Scratchpad-Taste",
        "Antippen blendet ein und aus, Halten diktiert hinein.",
        "Eingangs-Taste",
        "Diktiert in die Eingangs-Notiz, ohne ein Fenster zu öffnen.",
        "Beim Öffnen",
        "Letzte Notizen",
        "Angeheftete",
        "Drücke die Tastenkombination … (Esc bricht ab)",
        "Keine",
        "Neu: das Scratchpad",
        "%@ antippen blendet einen schwebenden Notizblock ein, halten diktiert hinein. %@ diktiert in die Eingangs-Notiz, ohne ein Fenster zu öffnen.",
        // Scratchpad: Ablegen
        "In %@ ablegen",
        "Ablegen",
        "Keine App zum Ablegen",
        "Ablegen (⌘⏎)",
        "Kopiert. ⌘V setzt den Text ein.",
        "Einstellungen",
        "Ändern",
        "Entfernen",
        "Verstanden",
        "Öffnen",
        // schon vorhanden, hier mitgeprüft, weil die Seite sie benutzt
        "Löschen",
        "Rückgängig",
        "Umbenennen",
        "Abbrechen",
        "Wählen",
        "Verwerfen",
        // Scratchpad: eingebaute Transforms
        "Aufräumen",
        "Als Mail",
        "Zusammenfassen",
        "To-do-Liste",
        "Ins Englische",
        "Räume auf …",
        "Schreibe als Mail …",
        "Fasse zusammen …",
        "Erstelle To-dos …",
        "Übersetze …",
        "Aufgeräumt",
        "Als Mail umgeschrieben",
        "Zusammengefasst",
        "To-do-Liste erstellt",
        "Übersetzt",
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
