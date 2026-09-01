import Foundation

/// Klartext für die Anbieter-Oberfläche — gemeinsam für Mac und iPhone.
///
/// Die Fehlertypen in `RemoteProviderError` tragen absichtlich keine
/// Anzeigetexte: Die Oberfläche ist zweisprachig und übersetzt über `Loc`, und
/// ein Fehlerwert soll außerdem nichts enthalten, was im Log landen könnte.
/// Übersetzt wird deshalb hier, an genau einer Stelle für beide Plattformen.
@MainActor
enum ProviderText {

    static func describe(_ error: Error) -> String {
        guard let fehler = error as? RemoteProviderError else {
            return Loc.t("Unbekannter Fehler.")
        }
        switch fehler {
        case .missingKey:
            return Loc.t("Es ist kein Schlüssel hinterlegt.")
        case .invalidBaseURL:
            return Loc.t("Die Adresse ist unbrauchbar. Sie muss mit http:// oder https:// beginnen.")
        case .unauthorized:
            return Loc.t("Der Schlüssel wurde abgelehnt.")
        case .noCredit:
            return Loc.t("Beim Anbieter ist kein Guthaben vorhanden.")
        case .unknownModel(let modell):
            return Loc.f("Das Modell „%@“ kennt der Anbieter nicht.", modell)
        case .rateLimited(let after):
            guard let after else { return Loc.t("Zu viele Anfragen. Später erneut versuchen.") }
            return Loc.f("Zu viele Anfragen. Erneut möglich in etwa %d Sekunden.", Int(after))
        case .http(let status):
            return Loc.f("Der Anbieter antwortete mit Fehler %d.", status)
        case .malformedResponse:
            return Loc.t("Die Antwort des Anbieters war nicht verwertbar.")
        case .timedOut:
            return Loc.t("Der Anbieter hat nicht rechtzeitig geantwortet.")
        case .cannotConnect:
            return Loc.t("Keine Verbindung. Stimmt die Adresse — und läuft der Server?")
        }
    }
}

/// Grobe Vorauswahl der Transkriptions-Modelle aus einer Anbieter-Liste.
///
/// Die Modell-Liste eines Anbieters enthält alles durcheinander, und aus
/// hundert Chat-Modellen das eine Whisper herauszusuchen ist unnötige Arbeit.
/// **Bleibt nichts übrig, wird nicht gefiltert** — eine ungefilterte Liste ist
/// besser als eine leere, denn dann hat der Filter die Namensgebung dieses
/// Anbieters nur nicht erkannt.
enum AudioModelFilter {

    private static let hinweise = ["whisper", "transcribe", "voxtral", "scribe", "stt", "asr"]

    static func apply(_ ids: [String]) -> [String] {
        let gefiltert = ids.filter { id in
            let k = id.lowercased()
            return hinweise.contains { k.contains($0) }
        }
        return gefiltert.isEmpty ? ids : gefiltert
    }
}
