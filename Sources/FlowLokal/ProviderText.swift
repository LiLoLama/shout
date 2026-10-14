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
        if let anmeldung = error as? ChatGPTAuthError { return describe(anmeldung) }
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
        case .signInRequired:
            return Loc.t("Die Anmeldung bei ChatGPT ist abgelaufen. Bitte neu anmelden.")
        case .planLimitReached:
            return Loc.t("Das Limit deines ChatGPT-Abos ist erreicht. Bis es wieder frei ist, fügt shout. den Rohtext ein.")
        case .planNotEligible:
            return Loc.t("Für dieses ChatGPT-Konto ist die Nutzung in anderen Apps nicht freigegeben. Nötig ist Plus oder Pro.")
        }
    }

    static func describe(_ fehler: ChatGPTAuthError) -> String {
        switch fehler {
        case .cancelled:
            return Loc.t("Anmeldung abgebrochen.")
        case .denied:
            return Loc.t("Die Anmeldung wurde im Browser abgelehnt.")
        case .stateMismatch, .callbackFailed, .tokenRejected:
            return Loc.t("Die Anmeldung bei ChatGPT ist fehlgeschlagen. Bitte noch einmal versuchen.")
        case .clientMismatch:
            return Loc.t("Im Browser wurde ein anderes Konto gewählt. Bitte noch einmal anmelden.")
        case .invalidIDToken:
            return Loc.t("Die Antwort von ChatGPT ließ sich nicht prüfen. Bitte noch einmal versuchen.")
        case .missingUsageScope:
            return Loc.t("Angemeldet, aber ohne Erlaubnis, dein Abo zu nutzen. Bitte neu anmelden und die Nutzung erlauben.")
        case .listenerFailed:
            return Loc.t("shout. konnte den Rückruf für die Anmeldung nicht bereitstellen.")
        case .timedOut:
            return Loc.t("Die Anmeldung hat zu lange gedauert. Bitte noch einmal versuchen.")
        case .network:
            return Loc.t("Keine Verbindung zu ChatGPT.")
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
