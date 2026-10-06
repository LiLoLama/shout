import Foundation

/// Oberflächensprache. Standard ist die Sprache des Systems: Deutsch auf einem
/// deutschsprachigen Mac, sonst Englisch. In den Einstellungen umschaltbar und
/// unabhängig von der Diktier-Sprache (die steckt in „transcriptionLanguage").
///
/// Als Schlüssel dient der deutsche Text selbst. Das hält die Aufrufe lesbar
/// (`Loc.t("Diktieren")`) und ein fehlender Eintrag fällt harmlos auf Deutsch
/// zurück, statt einen kryptischen Platzhalter anzuzeigen. Gleiches Verfahren
/// wie in der Windows-App (windows/src/Shout/Core/Localization.cs) — die
/// englischen Texte sind absichtlich wortgleich gehalten.
@MainActor
final class Loc: ObservableObject {

    static let shared = Loc()

    /// Schlüssel in UserDefaults: "system", "de" oder "en".
    /// `nonisolated`, damit @AppStorage(Loc.storageKey) auch außerhalb des
    /// MainActors (in der memberwise-Init einer View) darauf zugreifen darf.
    nonisolated static let storageKey = "uiLanguage"

    /// Aktive Sprache: "de" oder "en" (nie "system" — das ist schon aufgelöst).
    /// Views, die sich darauf beziehen, bauen bei einer Änderung neu auf.
    @Published private(set) var language: String

    private init() {
        #if os(iOS)
        let sharedDefaults = UserDefaults(suiteName: "group.com.inthezone.shout")
        let appValue = UserDefaults.standard.string(forKey: Self.storageKey)
        let shared = sharedDefaults?.string(forKey: Self.storageKey)
        language = Self.resolve(shared ?? appValue)
        if shared == nil { sharedDefaults?.set(appValue ?? "system", forKey: Self.storageKey) }
        #else
        language = Self.resolve(UserDefaults.standard.string(forKey: Self.storageKey))
        #endif
    }

    /// Übernimmt die Auswahl aus den Einstellungen ("system", "de", "en").
    func apply(_ raw: String) {
        UserDefaults.standard.set(raw, forKey: Self.storageKey)
        #if os(iOS)
        // Haupt-App und Tastatur-Erweiterung besitzen getrennte Standard-Container.
        // Die App Group hält ihre Oberflächensprache dennoch synchron.
        UserDefaults(suiteName: "group.com.inthezone.shout")?.set(raw, forKey: Self.storageKey)
        #endif
        language = Self.resolve(raw)
    }

    /// "system" folgt der macOS-Anzeigesprache; alles außer Deutsch bekommt
    /// Englisch, weil es nur diese zwei Übersetzungen gibt.
    private static func resolve(_ raw: String?) -> String {
        switch raw {
        case "de": return "de"
        case "en": return "en"
        default:
            let system = Locale.preferredLanguages.first ?? Locale.current.identifier
            return system.hasPrefix("de") ? "de" : "en"
        }
    }

    static var isGerman: Bool { shared.language == "de" }

    /// Übersetzt den Text (deutscher Text ist der Schlüssel).
    static func t(_ german: String) -> String {
        isGerman ? german : (english[german] ?? german)
    }

    /// Übersetzt und setzt Platzhalter ein (%@, %d …).
    static func f(_ german: String, _ args: CVarArg...) -> String {
        String(format: t(german), arguments: args)
    }

    /// Anzeigenamen der Sprachauswahl selbst — immer in der jeweiligen Sprache.
    static var languageOptions: [(key: String, label: String)] {
        [("system", t("Wie das System")), ("de", "Deutsch"), ("en", "English")]
    }

    private static let english: [String: String] = [
        // MARK: - Menüleiste und Zustände

        "shout. beenden": "Quit shout.",
        "Bearbeiten": "Edit",
        "Widerrufen": "Undo",
        "Wiederholen": "Redo",
        "Ausschneiden": "Cut",
        "Kopieren": "Copy",
        "Einsetzen": "Paste",
        "Alles auswählen": "Select All",

        "Modell wird geladen …": "Loading model…",
        "Modell erneut laden": "Reload model",
        "Modell nicht geladen — „Modell erneut laden“": "Model not loaded — choose “Reload model”",
        "Modell-Ladefehler: %@": "Model loading error: %@",
        "Formatter: suche …": "Formatter: searching…",
        "Formatter: %@": "Formatter: %@",
        "Formatter: Modell wird geladen …": "Formatter: loading model…",
        "Formatter: nicht geladen (Rohtext)": "Formatter: not loaded (raw text)",
        "Formatierung": "Formatting",
        "Beim Login starten": "Start at login",
        "Letztes Diktat korrigieren …": "Correct last dictation…",
        "Zuletzt Gesprochenes einfügen": "Insert last dictation",
        "shout. öffnen …": "Open shout.…",
        "Wörterbuch …": "Dictionary…",
        "Nach Aktualisierungen suchen …": "Check for updates…",
        "Über shout. …": "About shout.…",
        "Beenden": "Quit",

        "Bereit — %@": "Ready — %@",
        "Bereit · %@": "Ready · %@",
        "%@ halten": "hold %@",
        "%@ drücken": "press %@",
        "%@ doppelt tippen": "double-tap %@",
        "Aufnahme läuft …": "Recording…",
        "Verarbeite …": "Processing…",
        "shout. — Korrigieren": "shout. — Correct",
        "Mit ⌘/⌥/⌃/⇧ kombinieren (oder F-Taste)": "Combine with ⌘/⌥/⌃/⇧ (or an F key)",

        // MARK: - Seitenleiste

        "Aufnahme & Text": "Recording & text",
        "Wörterbuch": "Dictionary",
        "Verlauf": "History",
        "Statistiken": "Statistics",
        "Modelle": "Models",
        "Sync & Geräte": "Sync & devices",
        "Unterstützen": "Support",
        "Bald": "Soon",

        // MARK: - Aufnahme & Text

        "Aufnahme": "Recording",
        "Aufnahme-Art": "How to record",
        "Taste gedrückt halten, beim Loslassen wird eingefügt.":
            "Hold the key down; the text is inserted when you let go.",
        "Einmal drücken zum Starten, nochmal zum Stoppen.":
            "Press once to start, press again to stop.",
        "Zweimal kurz tippen zum Starten, einmal tippen zum Stoppen.":
            "Tap twice quickly to start, tap once to stop.",
        "Halten": "Hold",
        "Umschalten": "Toggle",
        "Doppeltipp": "Double-tap",
        "So startest du": "How to start",
        "Drück die Taste, mit der du diktieren willst.": "Press the key you want to dictate with.",
        "Ändern": "Change",
        "Taste drücken …": "Press a key…",
        "Von selbst aufhören": "Stop by itself",
        "Stoppt automatisch nach kurzer Sprechpause (im Umschalt- und Doppeltipp-Modus).":
            "Stops automatically after a short pause (in toggle and double-tap mode).",
        "Pause bis Stopp": "Pause before stopping",
        "Pille immer anzeigen": "Always show the pill",
        "Zeigt die Aufnahme-Pille dauerhaft am Bildschirmrand — per Klick starten, mit ✕/✓ abbrechen oder einfügen.":
            "Keeps the recording pill at the edge of the screen — click to start, ✕ to cancel, ✓ to insert.",
        "Position der Pille": "Pill position",
        "Wähle eine Ecke — oder zieh die Pille einfach mit der Maus an eine beliebige Stelle.":
            "Pick a corner — or simply drag the pill anywhere with the mouse.",
        "Frei platziert. Du kannst die Pille jederzeit mit der Maus verschieben oder hier wieder eine feste Ecke wählen.":
            "Placed freely. You can drag the pill with the mouse at any time or pick a fixed corner again here.",
        "Unten Mitte": "Bottom center",
        "Unten links": "Bottom left",
        "Unten rechts": "Bottom right",
        "Oben Mitte": "Top center",
        "Oben links": "Top left",
        "Oben rechts": "Top right",
        "Frei verschoben": "Moved freely",
        "Pille fixieren": "Lock the pill",
        "Verhindert das Verschieben mit der Maus. Praktisch, wenn sie einmal richtig sitzt — ein Klick daneben rückt sie dann nicht mehr weg.": "Prevents moving it with the mouse. Handy once it sits where you want it — a stray click no longer nudges it away.",
        "Ausrichtung der Pille": "Orientation of the pill",
        "„Automatisch“ stellt sie an einer Seitenkante senkrecht und oben oder unten waagerecht — dort, wo sie am wenigsten Platz wegnimmt.": "“Automatic” makes it vertical at a side edge and horizontal at the top or bottom — whichever takes up the least room.",
        "Waagerecht": "Horizontal",
        "Senkrecht": "Vertical",

        "Text": "Text",
        "Text automatisch aufräumen": "Clean up text automatically",
        "Füllwörter raus, Satzzeichen und Aufzählungen setzen.":
            "Removes filler words, adds punctuation and lists.",
        "Sprachbefehle": "Spoken commands",
        "‚Komma', ‚Punkt', ‚Fragezeichen', ‚neue Zeile', ‚neuer Absatz' werden zu echten Satzzeichen/Umbrüchen.":
            "“comma”, “period”, “question mark”, “new line”, “new paragraph” become real punctuation and breaks.",
        "In der Zwischenablage behalten": "Keep in the clipboard",
        "Das Diktat bleibt zusätzlich in der Zwischenablage — sonst wird der vorherige Inhalt wiederhergestellt.":
            "The dictation also stays in the clipboard — otherwise the previous content is restored.",

        "Sprache & Ton": "Language & sound",
        "Diktier-Sprache": "Dictation language",
        "Sprache der Transkription. „Automatisch“ erkennt sie pro Aufnahme selbst.":
            "Language of the transcription. “Automatic” detects it per recording.",
        "Deutsch": "German",
        "English": "English",
        "Automatisch": "Automatic",
        "Oberfläche": "Interface",
        "Sprache der Bedienoberfläche. „Wie das System“ folgt der Sprache von macOS.":
            "Language of the user interface. “Match the system” follows the macOS display language.",
        "Wie das System": "Match the system",
        "Klang-Signale": "Sound cues",
        "Dezente Töne beim Start der Aufnahme und wenn der Text eingefügt ist.":
            "Subtle tones when recording starts and when the text is inserted.",

        "Mikrofon": "Microphone",
        "Eingang": "Input",
        "Systemstandard": "System default",

        // MARK: - Aufnahme-Pille

        "Aufnahme starten": "Start recording",
        "Abbrechen": "Cancel",
        "Einfügen": "Insert",

        // MARK: - Wörterbuch

        "Wörter, die shout. richtig schreiben soll": "Words shout. should spell correctly",
        "Neuer Begriff (z. B. inthezone)": "New term (e.g. inthezone)",
        "Hinzufügen": "Add",
        "Aus Datei (CSV/TXT) …": "From file (CSV/TXT)…",
        "Aus Kontakten …": "From contacts…",
        "Noch keine Begriffe.": "No terms yet.",
        "%d neue Begriffe.": "%d new terms.",
        "%d Namen aus Kontakten.": "%d names from contacts.",
        "Kein Zugriff auf Kontakte.": "No access to contacts.",
        "Automatisch verbessert": "Corrected automatically",
        "Ausbesserungen von selbst lernen": "Learn from my corrections",
        "Verbesserst du nach dem Diktat ein Wort im Text, merkt sich shout. das Paar. Abgeschaltet bleibt das Wörterbuch unberührt — und kein fremdes Textfeld wird beobachtet.":
            "If you fix a word in the text after dictating, shout. remembers the pair. Switched off, the dictionary stays untouched — and no text field of another app is watched.",
        "Höchstens %d Zeichen — das sieht nach einem versehentlich mitgelernten Link aus.":
            "At most %d characters — this looks like a link that was learned by accident.",
        "falsch": "wrong",
        "richtig": "right",
        "Noch keine Korrekturen — shout. lernt sie auch automatisch, wenn du ein Wort ausbesserst.":
            "No corrections yet — shout. also learns them automatically when you fix a word.",

        // MARK: - Verlauf

        "Alle löschen": "Delete all",
        "Noch keine Diktate": "No dictations yet",
        "Was du diktierst, erscheint hier — zum Nachlesen und erneut Kopieren.":
            "Whatever you dictate shows up here — to read again and copy.",
        "Heute": "Today",
        "Gestern": "Yesterday",
        "Am Cursor einfügen (in der zuletzt aktiven App)":
            "Insert at the cursor (in the last active app)",
        "In die Zwischenablage kopieren": "Copy to the clipboard",
        "Löschen": "Delete",
        "Original anzeigen": "Show original",
        "Original ausblenden": "Hide original",
        "Rohtext der Spracherkennung — vor Befehlen, Aufbereitung und Korrekturen.":
            "Raw speech-recognition text — before commands, cleanup and corrections.",
        "Original in die Zwischenablage kopieren": "Copy the original to the clipboard",

        // MARK: - Statistiken

        "Wörter gesamt": "Words total",
        "Ø Wörter/Minute": "Ø words/minute",
        "Diktate": "Dictations",
        "Korrekturen gelernt": "Corrections learned",
        "Streak": "Streak",
        "Tage aktuell": "days current",
        "längster": "longest",
        "Meistgenutztes Wort": "Most used word",
        "Aktivste Zeit": "Most active time",
        "Vormittags": "Mornings",
        "Mittags": "Midday",
        "Nachmittags": "Afternoons",
        "Abends": "Evenings",
        "Nachts": "Nights",
        "Dein Sprachprofil": "Your speech profile",
        "Wird nach %d weiteren Diktaten freigeschaltet.": "Unlocks after %d more dictations.",
        "shout. kann aus deinen Diktaten ein kurzes Profil deines Sprachstils erstellen — vollständig lokal.":
            "shout. can build a short profile of your speaking style from your dictations — entirely local.",
        "Erstelle …": "Creating…",
        "Profil erstellen": "Create profile",
        "Aktualisieren": "Refresh",

        // MARK: - Modelle

        "%d GB Arbeitsspeicher · %d Kerne": "%d GB memory · %d cores",
        "Empfohlen für deinen Mac: **%@** zum Transkribieren, **%@** zum Aufbereiten.":
            "Recommended for your Mac: **%@** for transcribing, **%@** for cleanup.",
        "Transkription (Sprache → Text)": "Transcription (speech → text)",
        "Aufbereitung & Formatierung (KI-Textmodell)": "Cleanup & formatting (AI text model)",
        "Empfohlen": "Recommended",
        "Viel RAM nötig": "Needs lots of RAM",
        "Modelle werden beim ersten Auswählen einmalig von Hugging Face geladen und danach lokal gespeichert. Alles läuft anschließend komplett offline auf deinem Mac.":
            "Models are downloaded from Hugging Face once when first selected and then stored locally. Everything runs completely offline on your Mac afterwards.",
        "Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen oder verarbeitet wird.":
            "You can only switch models while nothing is being recorded or processed.",
        "Modell konnte nicht geladen werden (offline?). Vorheriges Modell bleibt aktiv.":
            "The model could not be loaded (offline?). The previous model stays active.",
        "Aufbereitungs-Modell konnte nicht geladen werden (offline?). Vorheriges bleibt aktiv.":
            "The cleanup model could not be loaded (offline?). The previous one stays active.",

        // MARK: - Anbieter (eigene API statt lokalem Modell)
        //
        // „Verarbeitung", „Auf diesem Gerät" und „Entfernen" stehen schon weiter
        // unten (Datei-Transkription) mit derselben Übersetzung. Doppelte
        // Schlüssel lassen die App beim Start abstürzen, deshalb hier NICHT
        // wiederholen.

        "Anbieter": "Provider",
        "Läuft vollständig auf diesem Gerät. Nichts verlässt es.":
            "Runs entirely on this device. Nothing leaves it.",
        "Läuft bei einem Anbieter deiner Wahl. Standard ist dein Gerät.":
            "Runs at a provider of your choice. Your device is the default.",
        "Nur Anbieter, die transkribieren können, stehen hier.":
            "Only providers that can transcribe are listed here.",
        "Adresse": "Address",
        "Die Basis-Adresse. „/chat/completions“ wird selbst angehängt.":
            "The base address. “/chat/completions” is appended automatically.",
        "Schlüssel": "Key",
        "Ersetzen": "Replace",
        "Speichern": "Save",
        "Bekommst du bei: %@": "Get one at: %@",
        "Modell": "Model",
        "Kennung frei eintragbar.": "Identifier can be typed freely.",
        "Vorschläge": "Suggestions",
        "Modelle laden": "Load models",
        "Verbindung": "Connection",
        "Verbindung testen": "Test connection",
        "Verbindung steht · %@ s": "Connected · %@ s",
        "Verbindung steht, aber „%@“ steht nicht in der Modell-Liste des Anbieters.":
            "Connected, but “%@” is not in the provider’s model list.",
        "Verbindung steht · %@ s. Der Anbieter liefert keine Modell-Liste — ob das Modell stimmt, zeigt erst der erste Versuch.":
            "Connected · %@ s. This provider offers no model list — whether the model is right shows on the first attempt.",
        "Der Schlüssel konnte nicht in der Keychain gespeichert werden.":
            "The key could not be stored in the keychain.",
        "Es ist kein Schlüssel hinterlegt.": "No key has been stored.",
        "Die Adresse ist unbrauchbar. Sie muss mit http:// oder https:// beginnen.":
            "The address is unusable. It must start with http:// or https://.",
        "Der Schlüssel wurde abgelehnt.": "The key was rejected.",
        "Beim Anbieter ist kein Guthaben vorhanden.": "There is no credit at the provider.",
        "Das Modell „%@“ kennt der Anbieter nicht.": "The provider does not know the model “%@”.",
        "Zu viele Anfragen. Später erneut versuchen.": "Too many requests. Try again later.",
        "Zu viele Anfragen. Erneut möglich in etwa %d Sekunden.":
            "Too many requests. Possible again in about %d seconds.",
        "Der Anbieter antwortete mit Fehler %d.": "The provider responded with error %d.",
        "Die Antwort des Anbieters war nicht verwertbar.":
            "The provider’s response was not usable.",
        "Der Anbieter hat nicht rechtzeitig geantwortet.":
            "The provider did not respond in time.",
        "Keine Verbindung. Stimmt die Adresse — und läuft der Server?":
            "No connection. Is the address right — and is the server running?",
        "Unbekannter Fehler.": "Unknown error.",
        "Kosten": "Cost",
        "Preise aktualisieren": "Update prices",
        "ca. %@ je Diktat": "approx. %@ per dictation",
        "ca. %@ je Minute Audio": "approx. %@ per minute of audio",
        "Preis dieses Modells unbekannt.": "The price of this model is unknown.",
        "Diesen Monat: %@": "This month: %@",
        "(ohne die Modelle mit unbekanntem Preis)": "(excluding models with an unknown price)",
        "Näherung — abgerechnet wird beim Anbieter. Preise: Stand %@":
            "Approximation — the provider does the billing. Prices as of %@",
        "Anbieter · dieser Monat": "Provider · this month",
        "%@ Token": "%@ tokens",
        "%@ Minuten Audio": "%@ minutes of audio",
        "Geschätzte Kosten": "Estimated cost",
        "Rechner zu schwach? Du kannst beide Schritte stattdessen bei einem Anbieter deiner Wahl laufen lassen — später unter „Modelle“.":
            "Machine too weak? You can run both steps at a provider of your choice instead — later under “Models”.",
        "Schon Modelle auf dem Rechner?": "Already have models on this Mac?",
        "Gerät zu schwach? Du kannst beide Schritte stattdessen bei einem Anbieter deiner Wahl laufen lassen — später in den Einstellungen.":
            "Device too weak? You can run both steps at a provider of your choice instead — later in Settings.",
        "Näherung — abgerechnet wird beim Anbieter.":
            "Approximation — the provider does the billing.",
        "Ohne die Modelle mit unbekanntem Preis. Abgerechnet wird beim Anbieter.":
            "Excluding models with an unknown price. The provider does the billing.",
        "Die Erkennung ist fehlgeschlagen. Die Aufnahme liegt unter „Dateien“ und lässt sich dort erneut versuchen.":
            "Recognition failed. The recording is under “Files” and can be retried there.",
        "Ein Schritt läuft bei einem Anbieter. Was dorthin geht, verlässt dein Gerät; abgerechnet wird beim Anbieter. Der andere Schritt und alles Übrige bleibt lokal.":
            "One step runs at a provider. Whatever goes there leaves your device; the provider does the billing. The other step and everything else stays local.",

        // Einordnungen der Vorlagen
        "Der Referenz-Endpunkt. Kann Text und Transkription.":
            "The reference endpoint. Handles text and transcription.",
        "Ein Schlüssel für hunderte Modelle, auch für die Transkription. Dort liefert er womöglich keine Zeitmarken; Untertitel können dann unbrauchbar werden.":
            "One key for hundreds of models, transcription included. It may not return timestamps there, which can make subtitles unusable.",
        "Nur Transkription, dafür sehr günstig (rund $0,10 je Stunde) und mit Zeitmarken. Für EU-Verarbeitung „api“ in der Adresse durch „eu-api“ ersetzen.":
            "Transcription only, but very cheap (about $0.10 per hour) and with timestamps. For EU processing, replace “api” in the address with “eu-api”.",
        "Verarbeitung ausschließlich in der EU, ein Schlüssel für über 100 Modelle. Keine Transkription.":
            "Processing exclusively in the EU, one key for over 100 models. No transcription.",
        "Sehr schnell — die interessanteste Wahl fürs Live-Diktat.":
            "Very fast — the most interesting choice for live dictation.",
        "Europäischer Anbieter, kann Text und Transkription.":
            "European provider, handles text and transcription.",
        "Günstig. Keine Transkription.": "Inexpensive. No transcription.",
        "Über die OpenAI-Kompatibilitätsschicht. Keine Transkription.":
            "Via the OpenAI compatibility layer. No transcription.",
        "Über die OpenAI-Kompatibilitätsschicht, die Anthropic selbst als Testweg und nicht als Dauerlösung bezeichnet. Keine Transkription.":
            "Via the OpenAI compatibility layer, which Anthropic itself calls a way to test rather than a long-term solution. No transcription.",
        "Schlüssel aus der xAI-Konsole. Ein SuperGrok-Abo gilt hier NICHT — Abos enthalten keinen API-Zugang.":
            "Key from the xAI console. A SuperGrok subscription does NOT count here — subscriptions include no API access.",
        "Läuft auf deinem eigenen Rechner — auch auf einem anderen im eigenen Netz. Dann verlässt nichts dein Netzwerk.":
            "Runs on your own machine — including another one on your own network. Then nothing leaves your network.",
        "Wie Ollama: dein eigener Rechner, dein eigenes Netz.":
            "Like Ollama: your own machine, your own network.",
        "Alles selbst eintragen — für whisper.cpp-Server, vLLM, Pauschal-Abos mit eigenem Endpunkt und alles andere OpenAI-kompatible.":
            "Enter everything yourself — for whisper.cpp servers, vLLM, flat-rate plans with their own endpoint, and anything else OpenAI-compatible.",

        // Live-Liste von Hugging Face
        "AKTUELLE MODELLE · HUGGING FACE": "CURRENT MODELS · HUGGING FACE",
        "Lädt …": "Loading…",
        "Keine Verbindung zu Hugging Face. %@": "No connection to Hugging Face. %@",
        "Suche aktuelle Modelle …": "Looking for current models…",
        "Keine Modelle gefunden.": "No models found.",
        "Aktuell beliebt": "Popular right now",
        "Größe unbekannt": "Size unknown",
        "Live aus der Hugging-Face-Bibliothek „mlx-community“ (Instruct-Modelle, 4-bit). Größe geschätzt — für die Aufbereitung; die Transkription bleibt bei den geprüften Whisper-Modellen oben.":
            "Live from the Hugging Face library “mlx-community” (instruct models, 4-bit). Size estimated — for cleanup; transcription stays with the vetted Whisper models above.",

        // Modell-Beschreibungen (macOS-Katalog)
        "~600 MB · schnell": "~600 MB · fast",
        "~1,5 GB · schnell & sehr genau": "~1.5 GB · fast & very accurate",
        "~3 GB · maximale Genauigkeit, langsamer": "~3 GB · maximum accuracy, slower",
        "~2 GB · sehr schnell": "~2 GB · very fast",
        "~5 GB · guter Standard": "~5 GB · a good default",
        "~5,5 GB · mehr Qualität": "~5.5 GB · more quality",
        "~8 GB · sehr gute Aufbereitung": "~8 GB · very good cleanup",
        "~18 GB · High-End, beste Qualität": "~18 GB · high end, best quality",

        // MARK: - Sync & Geräte

        "Daten übertragen": "Transfer data",
        "shout. speichert alles lokal — keine Cloud. Für ein zweites Gerät exportierst du eine Datei, kopierst sie hinüber (AirDrop, USB-Stick …) und importierst sie dort. Die Datei passt auch zur Windows- und iPhone-App.":
            "shout. keeps everything local — no cloud. For a second device you export a file, copy it over (AirDrop, USB stick…) and import it there. The file also works with the Windows and iPhone app.",
        "Exportieren …": "Export…",
        "Importieren …": "Import…",
        "Export fehlgeschlagen.": "Export failed.",
        "Export abgebrochen.": "Export cancelled.",
        "Exportiert nach %@.": "Exported to %@.",
        "Export fehlgeschlagen: %@": "Export failed: %@",
        "Import abgebrochen.": "Import cancelled.",
        "Datei nicht lesbar.": "File could not be read.",
        "Ungültige Backup-Datei.": "Invalid backup file.",
        "Dieses Backup stammt aus einer neueren Version von shout. Bitte zuerst die App aktualisieren.":
            "This backup comes from a newer version of shout. Please update the app first.",
        "Importiert: %d Begriffe, %d Diktate.": "Imported: %d terms, %d dictations.",
        "In der Datei enthalten": "Contained in the file",
        "Begriffe & gelernte Korrekturen": "Terms & learned corrections",
        "Deine bisherigen Diktate": "Your previous dictations",
        "Wörter, Streak, aktive Tage": "Words, streak, active days",
        "Einstellungen": "Settings",
        "Aufnahme-Art, Hotkey, Mikrofon, Formatierung": "Recording mode, hotkey, microphone, formatting",
        "Beim Import werden die aktuellen Daten auf diesem Gerät ersetzt. Die Datei enthält deinen Verlauf im Klartext — behandle sie vertraulich.":
            "Importing replaces the current data on this device. The file contains your history in plain text — treat it as confidential.",

        // MARK: - Unterstützen

        "shout. ist Open Source": "shout. is open source",
        "Kostenlos, quelloffen und komplett lokal.": "Free, open source and entirely local.",
        "Ich entwickle shout. in meiner freien Zeit und bemühe mich, die App aktuell zu halten, zu verbessern und zu erweitern. Wenn dir shout. hilft und du die Weiterentwicklung unterstützen möchtest, freue ich mich riesig — freiwillig, ohne Verpflichtung.":
            "I build shout. in my spare time and do my best to keep it current, improved and extended. If shout. helps you and you’d like to support its development, I’d be delighted — entirely voluntary, no obligation.",
        "Quellcode auf GitHub": "Source code on GitHub",
        "Was shout. ausmacht": "What makes shout. shout.",
        "Frei & quelloffen": "Free & open source",
        "Der komplette Quellcode ist öffentlich — nutzen, anpassen, weitergeben.":
            "The complete source code is public — use it, adapt it, pass it on.",
        "Lokal & privat": "Local & private",
        "Keine Cloud, keine Konten, keine Datenweitergabe. Alles bleibt auf deinem Mac.":
            "No cloud, no accounts, no data sharing. Everything stays on your Mac.",
        "Aktiv gepflegt": "Actively maintained",
        "Ich bemühe mich, shout. aktuell zu halten, zu verbessern und zu erweitern.":
            "I do my best to keep shout. current, improved and extended.",
        "Fehler gefunden oder eine Idee? Auf GitHub freue ich mich über Issues und Pull Requests.":
            "Found a bug or have an idea? Issues and pull requests are welcome on GitHub.",

        // MARK: - Über shout. (Klick auf die Wortmarke)

        "Über shout.": "About shout.",
        "Lokale Diktier-App für macOS": "Local dictation app for macOS",
        "Version %@ (Build %@)": "Version %@ (build %@)",
        "Version kopieren": "Copy version",
        "Kopiert": "Copied",
        "Aktualisierung": "Update",
        "Nach Aktualisierungen suchen": "Check for updates",
        "Automatisch nach Aktualisierungen suchen": "Check for updates automatically",
        "Zuletzt geprüft: %@": "Last checked: %@",
        "Noch nicht nach Aktualisierungen gesucht.": "Haven’t checked for updates yet.",
        "Alles lokal — Sprache, Text und Verlauf verlassen deinen Mac nicht.":
            "All local — speech, text and history never leave your Mac.",
        "Lizenz (GPL-3.0)": "License (GPL-3.0)",
        "Fehler melden": "Report a bug",
        "Unterstützen …": "Support…",

        // MARK: - Erststart-Assistent

        "Willkommen bei shout.": "Welcome to shout.",
        "Diktieren in jede App — komplett lokal auf deinem Mac. Keine Cloud, keine Konten. In vier kurzen Schritten ist alles startklar.":
            "Dictate into any app — entirely local on your Mac. No cloud, no accounts. Four short steps and you’re ready.",
        "Perfekt — shout. darf dein Mikrofon nutzen.": "Perfect — shout. may use your microphone.",
        "shout. braucht Zugriff auf dein Mikrofon, um deine Sprache lokal in Text umzuwandeln.":
            "shout. needs access to your microphone to turn your speech into text locally.",
        "In Systemeinstellungen öffnen": "Open System Settings",
        "Mikrofon erlauben": "Allow microphone",
        "Bedienungshilfen": "Accessibility",
        "Alles bereit — shout. kann Text an der Cursor-Position einfügen.":
            "All set — shout. can insert text at the cursor.",
        "Damit shout. den fertigen Text an der Cursor-Position einfügen kann, aktiviere es unter „Bedienungshilfen“. Danach erkennt shout. die Freigabe automatisch.":
            "So shout. can insert the finished text at the cursor, enable it under “Accessibility”. shout. then picks up the permission automatically.",
        "Bedienungshilfen öffnen": "Open Accessibility",
        "Sprachmodell": "Speech model",
        "Das Sprachmodell ist geladen und liegt lokal auf deinem Mac.":
            "The speech model is loaded and lives locally on your Mac.",
        "Das Sprachmodell konnte nicht geladen werden — meist fehlt beim ersten Start die Internet-Verbindung. Prüfe die Verbindung und versuch es erneut.":
            "The speech model could not be loaded — usually the internet connection is missing on first launch. Check your connection and try again.",
        "Beim ersten Start lädt shout. das Sprachmodell einmalig herunter (danach läuft alles offline). Das kann je nach Verbindung ein paar Minuten dauern.":
            "On first launch shout. downloads the speech model once (everything runs offline afterwards). Depending on your connection this can take a few minutes.",
        "Erneut versuchen": "Try again",
        "Probier es aus": "Give it a try",
        "Klick ins Feld, halte %@ und sprich einen Satz. Dein Text erscheint direkt hier.":
            "Click into the field, hold %@ and say a sentence. Your text appears right here.",
        "Tipp: Aufnahme-Art und Taste kannst du später unter „Aufnahme & Text“ ändern.":
            "Tip: you can change the recording mode and key later under “Recording & text”.",
        "Zurück": "Back",
        "Weiter": "Continue",
        "Los geht’s": "Let’s go",

        // MARK: - Korrigieren und Lern-Hinweis

        "Letztes Diktat korrigieren": "Correct last dictation",
        "Bessere falsch erkannte Wörter aus. shout. lernt die Korrekturen fürs nächste Mal — in jeder App.":
            "Fix words that were recognised wrong. shout. learns the corrections for next time — in every app.",
        "Übernehmen": "Apply",
        "Ins Wörterbuch gelernt": "Learned into the dictionary",
        "Rückgängig": "Undo",

        // MARK: - iOS: Diktier-Screen

        "Diktieren": "Dictate",
        "Verwerfen": "Discard",
        "Sprachmodell wird geladen …": "Loading speech model…",
        "Sprachmodell wird geladen … %d %%": "Loading speech model… %d%%",
        "Einmalig — danach läuft alles offline.": "Just once — everything runs offline afterwards.",
        "Tippe zum Diktieren": "Tap to dictate",
        "Bereit": "Ready",
        "Ich höre zu …": "Listening…",
        "Problem": "Problem",
        // „Aufnahme starten" steht schon im Abschnitt „Aufnahme-Pille".
        "Aufnahme stoppen": "Stop recording",
        "Fertig — zurück zu deiner App wischen": "Done — swipe back to your app",
        "Dann in der shout-Tastatur auf Einfügen tippen.": "Then tap Insert in the shout keyboard.",
        "Schritt 1 fertig — zurück zu deiner App": "Step 1 complete — return to your app",
        "Schritt 2: In der shout-Tastatur auf Einfügen tippen.":
            "Step 2: Tap Insert in the shout. keyboard.",
        "In Zwischenablage kopiert": "Copied to the clipboard",
        "Kopiert ✓": "Copied ✓",
        "Teilen": "Share",

        // MARK: - iOS: Verlauf und Wörterbuch

        "Deine Diktate erscheinen hier.": "Your dictations appear here.",
        "Erstes Diktat aufnehmen": "Record your first dictation",
        "Alle Diktate löschen?": "Delete all dictations?",
        "%d Diktate löschen": "Delete %d dictations",
        "Du kannst das Löschen direkt danach rückgängig machen.":
            "You can undo the deletion immediately afterwards.",
        "Alle Diktate gelöscht": "All dictations deleted",
        "Diktat gelöscht": "Dictation deleted",
        "Begriffe": "Terms",
        "Noch keine Begriffe": "No terms yet",
        "Eigennamen und Fachbegriffe, die shout. richtig schreiben soll.":
            "Proper nouns and technical terms shout. should spell correctly.",
        "Korrektur hinzufügen": "Add correction",
        "Noch keine Korrekturen": "No corrections yet",
        "Diese Ersetzungen werden nach jeder Transkription angewendet.":
            "These replacements are applied after every transcription.",

        // MARK: - iOS: Einstellungen

        "Diktat": "Dictation",
        "Diktieren & Sprache": "Dictation & language",
        "Sprache, Aufbereitung, Befehle und Auto-Stopp":
            "Language, cleanup, commands and auto-stop",
        "Sprachmodelle": "Speech models",
        "shout.-Tastatur": "shout. keyboard",
        "Einrichten und Vollzugriff verstehen": "Set up and understand Full Access",
        "Backup & Übertragung": "Backup & transfer",
        "Daten zwischen Mac und iPhone übertragen": "Transfer data between Mac and iPhone",
        "Sprache": "Language",
        "Aufbereitungs-Modell lädt … %d %%": "Cleanup model loading… %d%%",
        "Sprachbefehle („Komma“, „neue Zeile“ …)": "Spoken commands (“comma”, “new line”…)",
        "Auto-Stopp bei Sprechpause": "Auto-stop on a speech pause",
        "Sprache der Bedienoberfläche. „Wie das System“ folgt der Sprache deines iPhones.":
            "Language of the user interface. “Match the system” follows your iPhone’s language.",
        "Gerät": "Device",
        "★ = Empfehlung für dein Gerät. Tippe „Laden“, um ein Modell herunterzuladen und zu aktivieren — einmalig, danach läuft alles offline.":
            "★ = recommended for your device. Tap “Download” to fetch and activate a model — once, then everything runs offline.",
        "Aufbereitung (KI-Textmodell)": "Cleanup (AI text model)",
        "★ Empfohlen": "★ Recommended",
        "Aktiv": "Active",
        "Laden": "Download",
        "Wird geladen … %d %%": "Downloading… %d%%",
        "Schnell": "Fast",
        "Ausgewogen": "Balanced",
        "Sehr genau": "Very accurate",
        "Maximale Genauigkeit": "Maximum accuracy",
        "Beste Aufbereitung": "Best cleanup",
        "Backup exportieren (teilen)": "Export backup (share)",
        "Backup importieren": "Import backup",
        "Letzte Sicherheitskopie teilen": "Share latest safety backup",
        "Backup importieren?": "Import backup?",
        "Daten ersetzen und importieren": "Replace data and import",
        "Das Backup ersetzt %d Wörterbuch-Einträge, %d Diktate, Statistiken und geteilte Einstellungen. Vorher wird automatisch eine lokale Sicherheitskopie erstellt.":
            "The backup replaces %d dictionary entries, %d dictations, statistics and shared settings. A local safety backup is created first.",
        "Eine Sicherheitskopie der vorherigen Daten wurde lokal gespeichert.":
            "A safety backup of the previous data was saved locally.",
        "Import ersetzt Wörterbuch, Verlauf, Statistiken und geteilte Einstellungen. Direkt davor legt shout. automatisch eine lokale Sicherheitskopie an.":
            "Import replaces the dictionary, history, statistics and shared settings. shout. automatically creates a local safety backup immediately beforehand.",
        "Daten (Mac ↔ iPhone)": "Data (Mac ↔ iPhone)",
        "Am Mac unter „Sync & Geräte“ exportieren, per AirDrop aufs iPhone senden und hier importieren — übernimmt Wörterbuch, Verlauf, Statistiken und Einstellungen. Achtung: Import ersetzt die aktuellen Daten.":
            "Export on the Mac under “Sync & devices”, send it to the iPhone via AirDrop and import it here — this takes over the dictionary, history, statistics and settings. Careful: importing replaces the current data.",
        "Wörter diktiert": "Words dictated",
        "Serie": "Streak",
        "%d Tage": "%d days",
        "Entwicklung unterstützen": "Support development",
        "shout. ist frei und quelloffen (GPL-3.0). Ich bemühe mich, die App aktuell zu halten und zu erweitern — Unterstützung ist freiwillig und hilft sehr. ❤️":
            "shout. is free and open source (GPL-3.0). I do my best to keep it current and extend it — support is voluntary and helps a lot. ❤️",
        "Einrichten": "Set up",
        "1. Einstellungen → Allgemein → Tastatur → Tastaturen öffnen":
            "1. Open Settings → General → Keyboard → Keyboards",
        "2. shout. auswählen und „Vollen Zugriff erlauben“ aktivieren":
            "2. Select shout. and enable Allow Full Access",
        "3. In einem Textfeld über die Globe-Taste zu shout. wechseln":
            "3. In a text field, use the Globe key to switch to shout.",
        "Vollzugriff wird nur benötigt, damit App und Tastatur das fertige Diktat über den gemeinsamen lokalen Speicher austauschen können. shout. überträgt keine Tastatureingaben und keine Diktate ins Internet.":
            "Full Access is only needed so the app and keyboard can exchange the finished dictation through shared local storage. shout. does not send keystrokes or dictations to the internet.",
        "Ablauf": "Flow",
        "Aufnehmen → zurückkehren → einfügen": "Record → return → insert",
        "Die Aufnahme findet in shout. statt, weil iOS Tastatur-Erweiterungen keinen Mikrofonzugriff erlaubt.":
            "Recording happens in shout. because iOS does not allow keyboard extensions to access the microphone.",

        // MARK: - iOS: Erststart

        "Diktieren direkt auf deinem Gerät — die Spracherkennung läuft komplett lokal. Keine Cloud, keine Konten, nichts verlässt dein Gerät.":
            "Dictate right on your device — speech recognition runs entirely locally. No cloud, no accounts, nothing leaves your device.",
        "Mikrofon erlaubt": "Microphone allowed",
        "Mikrofon noch nicht erlaubt": "Microphone not allowed yet",
        "Für die Aufnahme deiner Diktate.": "To record your dictations.",
        "Für die Aufnahme deiner Diktate. Du kannst das auch später entscheiden.":
            "To record your dictations. You can decide this later.",
        "Du kannst shout. ansehen und den Zugriff später beim ersten Diktat erlauben.":
            "You can explore shout. and allow access later when you record your first dictation.",
        "Sprachmodell geladen": "Speech model loaded",
        "Sprachmodell lädt …": "Speech model loading…",
        "%@ · %@ — einmalig, danach offline.": "%@ · %@ — once, then offline.",
        "Erlauben": "Allow",
        "Einstellungen öffnen": "Open Settings",
        "Einfügen braucht die Bedienungshilfen.": "Inserting needs Accessibility access.",
        "Der Text liegt in der Zwischenablage — ⌘V setzt ihn ein. Damit shout. das selbst kann, muss es unter „Bedienungshilfen“ freigegeben sein.":
            "The text is on the clipboard — ⌘V inserts it. For shout. to do that itself, it needs to be allowed under “Accessibility”.",
        "App ansehen": "Explore the app",
        "Mikrofonzugriff wird erst benötigt, wenn du wirklich aufnimmst.":
            "Microphone access is only needed when you actually record.",

        // MARK: - iOS: Engine-Meldungen

        "Sprachmodell konnte nicht geladen werden. Internet prüfen und erneut versuchen.":
            "The speech model could not be loaded. Check your connection and try again.",
        "Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen wird.":
            "You can only switch models while nothing is being recorded.",
        "Modell konnte nicht geladen werden (offline?). Vorheriges bleibt aktiv.":
            "The model could not be loaded (offline?). The previous one stays active.",
        "Kein Mikrofon-Zugriff. Öffne die Einstellungen und erlaube das Mikrofon für shout.":
            "No microphone access. Open Settings and allow the microphone for shout.",
        "Aufnahme konnte nicht gestartet werden: %@": "Recording could not start: %@",
        "Keine Aufnahme erkannt. Versuch es erneut.": "No recording detected. Try again.",
        "Kein gesprochener Inhalt erkannt. Versuch es erneut.":
            "No spoken content detected. Try again.",
        "Die Verarbeitung ist fehlgeschlagen. Versuch es erneut.":
            "Processing failed. Try again.",

        // MARK: - iOS: Diktier-Tastatur

        "1 Aufnehmen · 2 Hier einfügen": "1 Record · 2 Insert here",
        "In shout. aufnehmen": "Record in shout.",
        "Öffnet shout. für die Aufnahme. Kehre danach zu diesem Textfeld zurück.":
            "Opens shout. to record. Return to this text field afterwards.",
        "Diktat einfügen": "Insert dictation",
        "Fügt das zuletzt in shout. aufgenommene Diktat in dieses Textfeld ein.":
            "Inserts the dictation most recently recorded in shout. into this text field.",
        "Vollzugriff einrichten": "Set up Full Access",
        "Nächste Tastatur": "Next keyboard",
        "Zeilenumbruch": "Return",
        "Zum Einfügen fehlt noch Vollzugriff": "Full Access is still needed to insert",
        "Öffne die Anleitung. shout. verarbeitet weiterhin alles lokal auf deinem Gerät.":
            "Open the guide. shout. still processes everything locally on your device.",
        "Bereit zum Einfügen": "Ready to insert",
        "shout. wird geöffnet …": "Opening shout.…",
        "Nimm dort auf und kehre danach zu diesem Textfeld zurück.":
            "Record there, then return to this text field.",
        "Aufnahme läuft in shout.": "Recording in shout.",
        "Stoppe dort die Aufnahme und kehre anschließend hierher zurück.":
            "Stop the recording there, then return here.",
        "Diktat wird verarbeitet …": "Processing dictation…",
        "Kehre gleich zu diesem Textfeld zurück.": "Return to this text field in a moment.",
        "Kein neues Diktat": "No new dictation",
        "Öffne shout. und versuch die Aufnahme erneut.": "Open shout. and try recording again.",
        "Aufnahme verworfen": "Recording discarded",
        "Du kannst jederzeit ein neues Diktat aufnehmen.": "You can record a new dictation at any time.",
        "Das letzte Diktat ist abgelaufen": "The last dictation has expired",
        "Nimm ein neues Diktat auf, damit nichts Veraltetes eingefügt wird.":
            "Record a new dictation so nothing outdated is inserted.",
        "Diktat eingefügt": "Dictation inserted",
        "Du kannst direkt weiterarbeiten oder erneut aufnehmen.":
            "You can keep working or record again.",
        "Zuerst in shout. aufnehmen": "First, record in shout.",
        "Danach zurückkehren und hier auf Einfügen tippen.":
            "Then return and tap Insert here.",
        "Leerzeichen": "Space",

        // MARK: - Modell-Beschreibungen (iOS-Katalog)

        "~150 MB · am schnellsten, einfache Sätze": "~150 MB · fastest, simple sentences",
        "~500 MB · schnell & solide": "~500 MB · fast & solid",
        "~600 MB · sehr genau, etwas langsamer": "~600 MB · very accurate, a bit slower",
        "~1,5 GB · maximale Genauigkeit": "~1.5 GB · maximum accuracy",
        "~0,7 GB · am schnellsten": "~0.7 GB · fastest",
        "~1 GB · besser im Deutschen": "~1 GB · better at German",
        "~2 GB · beste Qualität, etwas langsamer": "~2 GB · best quality, a bit slower",

        // MARK: - Tastennamen (Hotkey-Anzeige)

        "linke ⌘": "left ⌘",
        "rechte ⌘": "right ⌘",
        "linke ⇧": "left ⇧",
        "rechte ⇧": "right ⇧",
        "linke ⌥": "left ⌥",
        "rechte ⌥": "right ⌥",
        "linke ⌃": "left ⌃",
        "rechte ⌃": "right ⌃",
        "Leertaste": "Space",
        "Taste %d": "Key %d",

        // MARK: - Dateien
        // „Kopieren“ und „Abbrechen“ stehen schon weiter oben — hier nicht wiederholen,
        // ein doppelter Schlüssel im Dictionary-Literal lässt die App beim Start abstürzen.

        "Dateien": "Files",
        "Audio- oder Videodateien hierher ziehen": "Drag audio or video files here",
        "MP3, M4A, WAV, MP4, MOV und alles, was macOS abspielen kann": "MP3, M4A, WAV, MP4, MOV and anything macOS can play",
        "Auswählen …": "Choose…",
        "Verarbeitung": "Processing",
        "Das Modell zum Aufbereiten ist noch nicht geladen. Sobald es bereit ist, lässt sich der Schalter umlegen — bis dahin kommt das Rohtranskript.": "The clean-up model is not loaded yet. Once it is ready the switch works — until then you get the raw transcript.",
        "Sprachbefehle anwenden": "Apply spoken commands",
        "Standardmäßig aus: In einer Aufzeichnung ist „Punkt“ meist ein normales Wort und kein Satzzeichen.": "Off by default: in a recording, “period” is usually just a word, not punctuation.",
        "Aufträge": "Jobs",
        "Kein gesprochener Inhalt erkannt.": "No speech detected.",
        "Als Text sichern …": "Save as text…",
        "Untertitel sichern …": "Save subtitles…",
        "Gesichert: %@": "Saved: %@",
        "Sichern fehlgeschlagen: %@": "Saving failed: %@",
        "Aus der Liste entfernen": "Remove from list",
        "Alle abbrechen": "Cancel all",
        "Wartet": "Waiting",
        "Wird transkribiert …": "Transcribing…",
        "Fertig · %d Wörter": "Done · %d words",
        "Abgebrochen": "Cancelled",
        "Zum Transkribieren wird das Sprachmodell gebraucht. Lade es unter „Modelle“ herunter — danach geht es hier weiter.": "Transcribing needs the speech model. Download it under “Models” — then come back here.",
        "Die Datei wird auf diesem Gerät gelesen — nichts wird hochgeladen. Ergebnisse werden nicht automatisch gespeichert und tauchen weder im Verlauf noch in den Statistiken auf.": "The file is read on this device — nothing is uploaded. Results are not saved automatically and appear neither in the history nor in the statistics.",
        "Diese Datei enthält keine Tonspur.": "This file has no audio track.",
        "Diese Datei kann nicht gelesen werden (%@).": "This file cannot be read (%@).",
        "Transkription läuft — Modellwechsel ist erst danach möglich.": "Transcription running — you can switch models afterwards.",
        "Es läuft noch eine Datei-Transkription.": "A file transcription is still running.",
        "Wirklich beenden? Der laufende Auftrag geht verloren.": "Quit anyway? The running job will be lost.",
        "Trotzdem beenden": "Quit anyway",

        // MARK: - Meetings auf dem iPhone

        "Meetings": "Meetings",
        "Datei auswählen …": "Choose a file…",
        "MP3, M4A, WAV, MP4, MOV und alles, was iOS abspielen kann": "MP3, M4A, WAV, MP4, MOV and anything iOS can play",
        "Zum Transkribieren wird das Sprachmodell gebraucht. Lade es in den Einstellungen — danach geht es hier weiter.": "Transcribing needs the speech model. Download it in the settings — then come back here.",
        "Das Modell zum Aufbereiten ist noch nicht geladen. Bis dahin kommt das Rohtranskript.": "The clean-up model is not loaded yet. Until then you get the raw transcript.",
        "Alles läuft auf diesem Gerät — nichts wird hochgeladen. Aufnahmen und fertige Transkripte bleiben liegen, bis du sie hier entfernst.": "Everything runs on this device — nothing is uploaded. Recordings and finished transcripts stay until you remove them here.",
        "Datei konnte nicht geöffnet werden": "The file could not be opened",
        "Aufnahme entfernen?": "Remove recording?",
        "Die Aufnahme und ihr Transkript werden vom Gerät entfernt. Das lässt sich nicht rückgängig machen.":
            "The recording and its transcript are removed from the device. This cannot be undone.",
        "Der Auftrag und sein Transkript werden aus shout. entfernt. Die ursprüngliche Datei bleibt erhalten.":
            "The job and its transcript are removed from shout. The original file remains.",
        "Auftrag abbrechen": "Cancel job",
        "Textfassung": "Text version",
        "Transkript kopieren": "Copy transcript",
        "Transkript teilen": "Share transcript",
        "OK": "OK",
        "Protokoll wird erstellt …": "Creating minutes…",

        // MARK: - Was soll damit passieren? (iOS)

        "Noch nicht verarbeitet": "Not processed yet",
        "Verarbeiten": "Process",
        "Auf diesem Gerät": "On this device",
        "Nur transkribieren": "Transcribe only",
        "Reiner Text mit Zeitmarken. Geht am schnellsten.": "Plain text with timestamps. The quickest option.",
        "Transkribieren und Protokoll": "Transcribe and write minutes",
        "Aufnahme teilen …": "Share the recording…",
        "Zum Beispiel per AirDrop an den Rechner — dort geht die Verarbeitung deutlich schneller. Die Aufnahme bleibt hier trotzdem liegen.": "By AirDrop to your computer, for instance — processing is considerably faster there. The recording stays here either way.",
        "Später entscheiden": "Decide later",

        // MARK: - Meeting-Mitschnitt

        "Meeting aufnehmen": "Record a meeting",
        "Aufnehmen": "Record",
        "Pause": "Pause",
        "Fortsetzen": "Resume",
        "Stoppen": "Stop",
        "Systemton": "System audio",
        "Meeting": "Meeting",
        "Mitschnitte": "Recordings",
        "Diktieren geht weiter — Mitschnitt und Diktat stören sich nicht.": "Dictation still works — recording and dictation do not interfere.",
        "Der Mitschnitt bleibt auf diesem Rechner und wird hier transkribiert. Ein Gespräch ohne Einverständnis der anderen mitzuschneiden ist in Deutschland und Österreich strafbar.": "The recording stays on this computer and is transcribed here. Recording a conversation without the consent of the others is a criminal offence in Germany and Austria.",
        "Es läuft noch ein Mitschnitt.": "A recording is still running.",
        "Beim Beenden wird er gestoppt und gesichert. Du findest ihn danach unter „Meeting“.": "Quitting stops and saves it. You will find it under “Meeting” afterwards.",
        "Stoppen und beenden": "Stop and quit",
        "Beides": "Both",
        "Nimmt über das Mikrofon auf — für Besprechungen im Raum.": "Records through the microphone — for meetings in the room.",
        "Nimmt den Ton anderer Programme auf — für Online-Meetings. Deine eigene Stimme ist dann NICHT dabei.": "Records the audio of other apps — for online meetings. Your own voice is NOT included.",
        "Mikrofon und Ton anderer Programme zusammen — für Online-Meetings, bei denen du mitsprichst.": "Microphone and the audio of other apps together — for online meetings where you speak too.",
        "Es kommt kein Ton an. Beim Systemton fehlt dann meist die Erlaubnis: Systemeinstellungen → Datenschutz & Sicherheit → Tonaufnahme.": "No audio is arriving. For system audio this usually means the permission is missing: System Settings → Privacy & Security → Audio Recording.",
        "Handy auf den Tisch legen und antippen": "Put the phone on the table and tap",
        "Die Aufnahme läuft weiter, wenn der Bildschirm aus ist. Was danach damit passiert, entscheidest du selbst.": "Recording continues with the screen off. What happens with it afterwards is up to you.",
        "Nimmt auf …": "Recording…",
        "Pausiert": "Paused",
        "Kurz vorweg": "One thing first",
        "Ein Gespräch mitzuschneiden ist ohne Einverständnis der anderen Beteiligten in Deutschland und Österreich strafbar. Frag kurz, bevor du aufnimmst.": "In Germany and Austria, recording a conversation without the consent of everyone involved is a criminal offence. Ask before you hit record.",
        "Verstanden": "Got it",
        "Aufnahme verwerfen?": "Discard recording?",
        "Aufnahme verwerfen": "Discard recording",
        "Weiter aufnehmen": "Keep recording",
        "Die bisherige Aufnahme wird gelöscht. Das lässt sich nicht rückgängig machen.":
            "The recording so far will be deleted. This cannot be undone.",
        "Mikrofonpegel": "Microphone level",
        "%d Prozent": "%d percent",
        "Wie soll die Aufnahme heißen?": "What should the recording be called?",
        "Du kannst sie auch später in der Liste umbenennen.": "You can also rename it later in the list.",
        "Name": "Name",
        "Sichern": "Save",
        "Später": "Later",
        "Zusammenfassung und Kernpunkte aus diesem Text — die Datei wird dafür nicht noch einmal transkribiert.": "A summary and key points from this text — the file is not transcribed again for this.",
        "Umbenennen": "Rename",
        "Entfernen": "Remove",
        "Aufnahme löschen": "Delete the recording",
        "Aufnahme löschen?": "Delete the recording?",
        "Die Audiodatei wird vom Gerät entfernt. Das lässt sich nicht rückgängig machen.": "The audio file is removed from the device. This cannot be undone.",
        "Zu wenig Speicher für die Sprechertrennung — der Text ist trotzdem vollständig.": "Not enough memory to separate speakers — the text is complete nonetheless.",

        // MARK: - Meeting-Erkennung

        "Meeting erkennen": "Detect meetings",
        "Wenn ein Meeting läuft": "When a meeting is running",
        "Erkannt werden Zoom, Teams, Webex, Skype, FaceTime, Discord, Slack und Jitsi — daran, dass ihr Ton läuft. Dein Mikrofon spielt dabei keine Rolle, du kannst also stumm dabeisitzen.":
            "Zoom, Teams, Webex, Skype, FaceTime, Discord, Slack and Jitsi are detected by their audio output. Your microphone plays no part in this, so you can sit in muted.",
        "Nichts tun": "Do nothing",
        "Fragen": "Ask",
        "Nie fragen bei": "Never ask for",
        "Wieder fragen": "Ask again",
        "%@-Meeting läuft": "%@ meeting in progress",
        "Mitschneiden und daraus ein Protokoll machen?": "Record it and turn it into minutes?",
        "Mitschneiden": "Record it",
        "Nicht jetzt": "Not now",
        "Nie bei %@": "Never for %@",
        "Bitte vorher die anderen Beteiligten fragen.": "Please ask the others first.",
        "%@ wird mitgeschnitten": "Recording %@",
        "Mitschnitt gesichert": "Recording saved",
        "Wird unter „Meeting“ transkribiert.": "Being transcribed under “Meeting”.",

        // MARK: - Ergebnisfenster

        "Öffnen": "Open",
        "shout. — %@": "shout. — %@",
        "Rohtext": "Raw text",
        "Protokoll erstellen": "Create minutes",
        "Sprecher erkennen": "Detect speakers",
        "Trennt die Stimmen und stellt „Sprecher 1“, „Sprecher 2“ voran. Lädt beim ersten Mal ein zusätzliches Modell und braucht die ganze Datei im Speicher — bei einer Stunde rund 230 MB.": "Separates the voices and puts “Speaker 1”, “Speaker 2” in front. Downloads an additional model the first time and needs the whole file in memory — about 230 MB for an hour.",
        "Sprecher %d": "Speaker %d",
        "Sprecher werden getrennt …": "Separating speakers…",
        "Die Sprecher konnten nicht getrennt werden — der Text ist trotzdem vollständig.": "The speakers could not be separated — the text is complete nonetheless.",
        "Zusätzlich zum Rohtext ein Protokoll: Zusammenfassung, Kernpunkte und der gegliederte Text. Dauert bei langen Dateien deutlich länger.": "In addition to the raw text, a set of minutes: summary, key points and the structured text. Takes considerably longer for long files.",
        "Protokoll": "Minutes",
        "Dafür wird das Modell zum Aufbereiten gebraucht. Lade es unter „Modelle“ herunter.": "This needs the clean-up model. Download it under “Models”.",
        "Zusammenfassung": "Summary",
        "Kernpunkte": "Key points",
        "Vergleichen": "Compare",
        "Vergleich ausblenden": "Hide comparison",
        "nur lesen": "read-only",
        "%d Wörter": "%d words",
        "%@ · %d Wörter": "%@ · %d words",
        "%@ in die Zwischenablage kopiert.": "%@ copied to the clipboard.",
        "Untertitel folgen immer dem ursprünglichen Transkript — Änderungen in diesem Fenster wirken sich nicht auf die Zeitmarken aus.": "Subtitles always follow the original transcript — edits in this window do not affect the timestamps.",

        // MARK: - Modellverzeichnis

        "%d Modelle gefunden": "%d models found",
        "%d Modelle gefunden. Der Ordner ist sehr groß — es wurde nicht vollständig durchsucht.":
            "%d models found. This folder is very large — it was not searched completely.",
        "Abgebrochen bei %d Modellen.": "Cancelled at %d models.",
        "Auf diesem Rechner gefunden": "Found on this Mac",
        "Aus den durchsuchten Ordnern. Diese Modelle liegen schon auf diesem Rechner und werden nicht heruntergeladen.":
            "From the searched folders. These models are already on this Mac and will not be downloaded.",
        "Basisordner": "Base folder",
        "Durchsuchen": "Search",
        "Durchsuchte Ordner": "Searched folders",
        "Erneut durchsuchen": "Search again",
        "Fremder Ordner": "External folder",
        "Hierhin lädt shout. selbst. Vorhandene Modelle bleiben, wo sie sind.":
            "This is where shout. downloads to. Existing models stay where they are.",
        "Modelle aus diesen Ordnern werden mitbenutzt statt neu geladen.":
            "Models in these folders are used as they are instead of downloaded again.",
        "Nicht auffindbar": "Not found",
        "Noch keiner. Wer schon Modelle hat, spart sich den Download.":
            "None yet. If you already have models, this saves the download.",
        "Noch nicht durchsucht.": "Not searched yet.",
        "Ordner hinzufügen": "Add folder",
        "Standardort": "Default location",
        "Wird durchsucht …": "Searching…",
        "Wo die Modelle liegen": "Where the models live",
        "Wählen": "Choose",

        // MARK: - Notizen (Scratchpad)

        "Notizen": "Notes",
        "Neue Notiz": "New Note",
        "Ordner": "Folder",
        "Jede Notiz ist eine Markdown-Datei in diesem Ordner. Liegt er in iCloud Drive oder einem Obsidian-Vault, findest du die Notizen auch dort.":
            "Every note is a Markdown file in this folder. If it lives in iCloud Drive or an Obsidian vault, your notes show up there too.",
        "Im Finder zeigen": "Show in Finder",
        "Wählen …": "Choose…",
        "Der Ordner ist nicht erreichbar. Änderungen werden zwischengespeichert und landen dort, sobald er wieder da ist.":
            "The folder can’t be reached. Changes are kept aside and move there as soon as it’s back.",
        "Notizen durchsuchen": "Search notes",
        "Noch keine Notizen": "No notes yet",
        "Keine Treffer": "No matches",
        "Wähle links eine Notiz oder lege eine neue an.": "Pick a note on the left or create a new one.",
        "Diktiere oder tippe eine neue Notiz — sie landet als Datei in deinem Ordner.":
            "Dictate or type a new note — it’s saved as a file in your folder.",
        "Anheften": "Pin",
        "Lösen": "Unpin",
        "Umbenennen …": "Rename…",
        "Notiz umbenennen": "Rename Note",
        "Titel": "Title",
        "„%@“ gelöscht": "“%@” deleted",
        "Diese Notiz wurde auch anderswo geändert. Deine Fassung liegt als „%@“ daneben.":
            "This note was also changed elsewhere. Your version is saved next to it as “%@”.",
        "Diese Notiz ist nicht mehr im Ordner.": "This note is no longer in the folder.",
        "Wieder sichern": "Save again",
        "Wird aus iCloud geladen …": "Downloading from iCloud…",
        "Unbenannt": "Untitled",
        "(Konflikt)": "(Conflict)",
        "Konnte nicht gesichert werden. Wechseln, Löschen und Ordnerwechsel sind gesperrt, bis gesichert ist.":
            "Couldn’t save. Switching, deleting and changing the folder are blocked until it’s saved.",
        "Erneut sichern": "Try again",
        "Text kopieren": "Copy text",
        "Verwerfen …": "Discard…",
        "Ungesicherten Text verwerfen?": "Discard unsaved text?",
        "Der Text dieser Notiz ist nirgends gesichert. Kopiere ihn vorher, wenn du ihn behalten willst.":
            "This note’s text isn’t saved anywhere. Copy it first if you want to keep it.",
        "Eine Notiz konnte nicht gesichert werden.": "A note couldn’t be saved.",
        "Weder im Notizordner noch als Rettungskopie war Platz. Der Text geht beim Beenden verloren.":
            "There was no room in the notes folder or for a rescue copy. The text will be lost when you quit.",
        "Text kopieren und beenden": "Copy text and quit",
        // Beenden, während ein Diktat noch verarbeitet wird
        "Ein Diktat wird noch verarbeitet.": "A dictation is still being processed.",
        "Wenn du jetzt beendest, geht es verloren.": "If you quit now, it will be lost.",
        "Beim letzten Beenden wurden ungesicherte Notizen gerettet.": "Unsaved notes were rescued when shout. last quit.",
        "In den Notizordner holen": "Move to notes folder",
        // Scratchpad-Tasten
        "Mit ⌃ oder ⌥ kombinieren": "Combine with ⌃ or ⌥",
        "Schon belegt": "Already in use",
        "Von einer anderen App belegt": "Taken by another app",
        // Scratchpad: Menüeintrag und Hinweise beim Zustellen eines Diktats
        "Scratchpad": "Scratchpad",
        "Die Notiz nimmt gerade nichts an. Der Text liegt in der Zwischenablage.":
            "The note can’t take text right now. It’s on the clipboard.",
        "Im Eingang notiert": "Added to Inbox",
        "Der Eingang ist gerade nicht erreichbar. Der Text liegt in der Zwischenablage.":
            "The inbox can’t be reached right now. The text is on the clipboard.",
        "Die Notiz ist nicht mehr offen. Die Anweisung liegt in der Zwischenablage.":
            "The note is no longer open. The instruction is on the clipboard.",
        // Scratchpad-Panel
        "Eingang.md": "Inbox.md",
        "Neuer Tab": "New Tab",
        "Tab schließen": "Close Tab",
        "Liste ein/aus": "Show/Hide List",
        "Noch keine Notiz offen. ⌘N legt eine neue an.": "No note open. ⌘N creates one.",
        "Diktat beenden": "Stop dictation",
        "In diese Notiz diktieren": "Dictate into this note",
        "Konnte nicht angemeldet werden": "Couldn’t be registered",
        // Scratchpad-Einstellungen und Hinweiskarte auf der Seite „Notizen“
        "Scratchpad aktiv": "Scratchpad on",
        "Schwebender Notizblock mit eigenen Tasten.": "A floating notepad with its own keys.",
        "Scratchpad-Taste": "Scratchpad key",
        "Antippen blendet ein und aus, Halten diktiert hinein.": "Tap to show or hide, hold to dictate into it.",
        "Eingangs-Taste": "Inbox key",
        "Diktiert in die Eingangs-Notiz, ohne ein Fenster zu öffnen.": "Dictates into the inbox note without opening a window.",
        "Beim Öffnen": "When opening",
        "Letzte Notizen": "Last notes",
        "Angeheftete": "Pinned",
        "Drücke die Tastenkombination … (Esc bricht ab)": "Press the key combination… (Esc cancels)",
        "Keine": "None",
        "Neu: das Scratchpad": "New: the Scratchpad",
        "%@ antippen blendet einen schwebenden Notizblock ein, halten diktiert hinein. %@ diktiert in die Eingangs-Notiz, ohne ein Fenster zu öffnen.":
            "Tap %@ to show a floating notepad, hold it to dictate into it. %@ dictates into the inbox note without opening a window.",
        // Scratchpad: Ablegen
        "In %@ ablegen": "Send to %@",
        "Ablegen": "Send",
        "Keine App zum Ablegen": "No app to send to",
        "Ablegen (⌘⏎)": "Send (⌘⏎)",
        "Kopiert. ⌘V setzt den Text ein.": "Copied. ⌘V pastes the text.",

        // Scratchpad: eingebaute Transforms
        "Aufräumen": "Clean up",
        "Als Mail": "As email",
        "Zusammenfassen": "Summarize",
        "To-do-Liste": "To-do list",
        "Ins Englische": "To English",
        "Räume auf …": "Cleaning up…",
        "Schreibe als Mail …": "Writing as email…",
        "Fasse zusammen …": "Summarizing…",
        "Erstelle To-dos …": "Making to-dos…",
        "Übersetze …": "Translating…",
        "Aufgeräumt": "Cleaned up",
        "Als Mail umgeschrieben": "Rewritten as email",
        "Zusammengefasst": "Summarized",
        "To-do-Liste erstellt": "To-do list created",
        "Übersetzt": "Translated",

        // Scratchpad: Transforms
        "Kein Text zum Bearbeiten.": "No text to work on.",
        "Zu lang für das gewählte Modell": "Too long for the selected model",
        "Unter Modelle ein Textmodell wählen": "Choose a text model under Models",
        "Das Modell hat nichts zurückgegeben. Der Text bleibt, wie er war.":
            "The model returned nothing. The text is unchanged.",
        "Das Modell hat zu lange gebraucht. Der Text bleibt, wie er war.":
            "The model took too long. The text is unchanged.",
        "Das Modell hat nicht geantwortet. Der Text bleibt, wie er war.":
            "The model didn’t respond. The text is unchanged.",
        "Der Text hat sich inzwischen geändert. Das Ergebnis liegt in der Zwischenablage.":
            "The text changed in the meantime. The result is on the clipboard.",
        "Das Ergebnis ließ sich nicht einsetzen. Es liegt in der Zwischenablage.":
            "The result couldn’t be inserted. It’s on the clipboard.",
        "Das Ergebnis ließ sich nicht sichern. Es liegt in der Zwischenablage.":
            "The result couldn’t be saved. It’s on the clipboard.",
        "„%@“ wird angewendet …": "Applying “%@”…",
        "„%@“ angewendet": "Applied “%@”",
        "Anweisung angewendet": "Instruction applied",
        "Per Sprache …": "By voice…",
        "Zuletzt: %@": "Last: %@",
        "Text umarbeiten": "Rework text",

        // Scratchpad: Versionen
        "Versionen …": "Versions…",
        "Versionen von „%@“": "Versions of “%@”",
        "Noch keine Versionen": "No versions yet",
        "Konnte nicht wiederhergestellt werden.": "Couldn’t be restored.",
        "Wiederherstellen": "Restore",
        "Schließen": "Close",

        // Scratchpad: Bilder
        "Das Bild ist größer als 10 MB.": "The image is larger than 10 MB.",
        "Das Bild lässt sich nicht lesen.": "The image can’t be read.",
        "Das Bild konnte nicht gesichert werden.": "The image couldn’t be saved.",

        // Scratchpad: eigene Transforms
        "Eigene Transforms": "Custom transforms",
        "Noch keine eigenen Transforms.": "No custom transforms yet.",
        "Erscheinen im Zauberstab und wirken auf die Auswahl oder die ganze Notiz.":
            "They appear in the magic wand and work on the selection or the whole note.",
        "Neuer Transform": "New transform",
        "Transform bearbeiten": "Edit transform",
        "Anweisung": "Instruction",
        "Konnte nicht gesichert werden.": "Couldn’t be saved.",
        "Scratchpad-Taste nicht übernommen (belegt oder ungültig).": "Scratchpad key not imported (taken or invalid).",
        "Notizordner nicht übernommen: Ordner nicht gefunden.": "Notes folder not imported: folder not found.",
        "Notizordner nicht übernommen: Es gibt ungesicherten Text.": "Notes folder not imported: there is unsaved text.",
        "Was soll mit dem Text passieren? Zum Beispiel: „Kürze auf drei Sätze.“":
            "What should happen to the text? For example: “Shorten to three sentences.”",
    ]
}
