import XCTest

final class AudioModelFilterTests: XCTestCase {

    /// Aus der Gesamtliste eines Anbieters bleiben die Transkriptions-Modelle
    /// übrig — aus hundert Chat-Modellen das eine Whisper zu suchen ist unnötige
    /// Arbeit.
    func testFiltertTranskriptionsModelleHeraus() {
        let alle = ["gpt-5", "gpt-5-mini", "whisper-1", "gpt-4o-mini-transcribe",
                    "text-embedding-3-small"]
        XCTAssertEqual(AudioModelFilter.apply(alle),
                       ["whisper-1", "gpt-4o-mini-transcribe"])
    }

    func testErkenntVoxtralUndScribe() {
        XCTAssertEqual(AudioModelFilter.apply(["mistral-large", "voxtral-mini-latest"]),
                       ["voxtral-mini-latest"])
        XCTAssertEqual(AudioModelFilter.apply(["chat", "scribe_v1"]), ["scribe_v1"])
    }

    func testGrossKleinschreibungIstEgal() {
        XCTAssertEqual(AudioModelFilter.apply(["Whisper-Large-V3"]), ["Whisper-Large-V3"])
    }

    /// **Der wichtige Fall.** Erkennt der Filter die Namensgebung eines Anbieters
    /// nicht, ist die ungefilterte Liste besser als eine leere — sonst stünde
    /// jemand vor einem leeren Auswahlmenü und hielte den Anbieter für kaputt.
    func testOhneTrefferBleibtDieListeUngefiltert() {
        let alle = ["modell-a", "modell-b"]
        XCTAssertEqual(AudioModelFilter.apply(alle), alle)
    }

    func testLeereListeBleibtLeer() {
        XCTAssertTrue(AudioModelFilter.apply([]).isEmpty)
    }

    /// Die Reihenfolge der Eingabe bleibt erhalten — sie kommt sortiert aus
    /// `ProviderModels.fetch` und soll sortiert bleiben.
    func testReihenfolgeBleibt() {
        XCTAssertEqual(AudioModelFilter.apply(["whisper-b", "chat", "whisper-a"]),
                       ["whisper-b", "whisper-a"])
    }
}
