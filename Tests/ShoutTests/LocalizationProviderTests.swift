import XCTest

/// Prüft die Übersetzungstabelle für die Anbieter-Oberfläche.
///
/// Der eigentliche Wert liegt darin, dass diese Tests die Tabelle **aufbauen**:
/// Ein doppelter Schlüssel in einem Swift-Dictionary-Literal ist ein
/// Laufzeitabsturz. Ohne diesen Test fällt er erst beim Start der ausgelieferten
/// App auf — also beim Nutzer.
@MainActor
final class LocalizationProviderTests: XCTestCase {

    /// Alle deutschen Texte, die die Anbieter-Oberfläche benutzt. Kommt einer
    /// davon unübersetzt durch, fehlt der englische Eintrag.
    private let schluessel = [
        "Anbieter",
        "Läuft vollständig auf diesem Gerät. Nichts verlässt es.",
        "Läuft bei einem Anbieter deiner Wahl. Standard ist dein Gerät.",
        "Nur Anbieter, die transkribieren können, stehen hier.",
        "Adresse",
        "Die Basis-Adresse. „/chat/completions“ wird selbst angehängt.",
        "Schlüssel",
        "Ersetzen",
        "Speichern",
        "Bekommst du bei: %@",
        "Modell",
        "Modelle laden",
        "Verbindung",
        "Verbindung testen",
        "Verbindung steht · %@ s",
        "Der Schlüssel konnte nicht in der Keychain gespeichert werden.",
        "Es ist kein Schlüssel hinterlegt.",
        "Der Schlüssel wurde abgelehnt.",
        "Beim Anbieter ist kein Guthaben vorhanden.",
        "Zu viele Anfragen. Später erneut versuchen.",
        "Die Antwort des Anbieters war nicht verwertbar.",
        "Der Anbieter hat nicht rechtzeitig geantwortet.",
        "Keine Verbindung. Stimmt die Adresse — und läuft der Server?",
        "Unbekannter Fehler.",
        "Kosten",
        "Preise aktualisieren",
        "ca. %@ je Diktat",
        "ca. %@ je Minute Audio",
        "Preis dieses Modells unbekannt.",
        "Diesen Monat: %@",
        "(ohne die Modelle mit unbekanntem Preis)",
        "Näherung — abgerechnet wird beim Anbieter. Preise: Stand %@",
        "Anbieter · dieser Monat",
        "%@ Token",
        "%@ Minuten Audio",
        "Geschätzte Kosten",
        "Näherung — abgerechnet wird beim Anbieter.",
        "Ohne die Modelle mit unbekanntem Preis. Abgerechnet wird beim Anbieter.",
        "Die Erkennung ist fehlgeschlagen. Die Aufnahme liegt unter „Dateien“ und lässt sich dort erneut versuchen.",
        "Rechner zu schwach? Du kannst beide Schritte stattdessen bei einem Anbieter deiner Wahl laufen lassen — später unter „Modelle“.",
        "Gerät zu schwach? Du kannst beide Schritte stattdessen bei einem Anbieter deiner Wahl laufen lassen — später in den Einstellungen.",
        "Ein Schritt läuft bei einem Anbieter. Was dorthin geht, verlässt dein Gerät; abgerechnet wird beim Anbieter. Der andere Schritt und alles Übrige bleibt lokal.",
    ]

    override func setUp() {
        super.setUp()
        Loc.shared.apply("en")
    }

    override func tearDown() {
        Loc.shared.apply("system")
        super.tearDown()
    }

    /// Baut die Tabelle auf und liest alle neuen Schlüssel. Ein doppelter
    /// Schlüssel bringt schon diesen Test zum Absturz — genau das ist erwünscht,
    /// solange es hier passiert und nicht beim Nutzer.
    func testAlleAnbieterTexteSindUebersetzt() {
        for text in schluessel {
            let englisch = Loc.t(text)
            XCTAssertFalse(englisch.isEmpty, "Leere Übersetzung für „\(text)“")
            XCTAssertNotEqual(englisch, text, "Keine englische Fassung für „\(text)“")
        }
    }

    /// Die Einordnungen der Vorlagen laufen ebenfalls durch `Loc.t` — sie stehen
    /// im Katalog als deutscher Text und müssen dort ankommen. Diese Texte werden
    /// im Katalog aus Teilstücken zusammengesetzt; der Test prüft, dass die
    /// zusammengesetzte Fassung dem Schlüssel in der Tabelle entspricht.
    func testEinordnungenDerVorlagenSindUebersetzt() {
        for vorlage in ProviderCatalog.all {
            let englisch = Loc.t(vorlage.note)
            XCTAssertNotEqual(englisch, vorlage.note,
                              "Keine englische Fassung für die Einordnung von \(vorlage.id) — "
                            + "vermutlich stimmt der zusammengesetzte Text nicht mit dem "
                            + "Schlüssel in Localization.swift überein")
        }
    }

    /// Auf Deutsch kommt der Schlüssel selbst zurück — so ist das Verfahren
    /// gedacht, und ein fehlender Eintrag fällt harmlos auf Deutsch zurück.
    func testAufDeutschKommtDerSchluesselZurueck() {
        Loc.shared.apply("de")
        XCTAssertEqual(Loc.t("Verbindung testen"), "Verbindung testen")
    }
}
