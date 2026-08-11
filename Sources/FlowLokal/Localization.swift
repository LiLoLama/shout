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
        language = Self.resolve(UserDefaults.standard.string(forKey: Self.storageKey))
    }

    /// Übernimmt die Auswahl aus den Einstellungen ("system", "de", "en").
    func apply(_ raw: String) {
        UserDefaults.standard.set(raw, forKey: Self.storageKey)
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
        "Halten": "Hold",
        "Umschalten": "Toggle",
        "So startest du": "How to start",
        "Drück die Taste, mit der du diktieren willst.": "Press the key you want to dictate with.",
        "Ändern": "Change",
        "Taste drücken …": "Press a key…",
        "Von selbst aufhören": "Stop by itself",
        "Stoppt automatisch nach kurzer Sprechpause (im Umschalt-Modus).":
            "Stops automatically after a short pause (in toggle mode).",
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
        "In Zwischenablage kopiert": "Copied to the clipboard",
        "Kopiert ✓": "Copied ✓",
        "Teilen": "Share",

        // MARK: - iOS: Verlauf und Wörterbuch

        "Deine Diktate erscheinen hier.": "Your dictations appear here.",
        "Begriffe": "Terms",
        "Eigennamen und Fachbegriffe, die shout. richtig schreiben soll.":
            "Proper nouns and technical terms shout. should spell correctly.",
        "Korrektur hinzufügen": "Add correction",
        "Diese Ersetzungen werden nach jeder Transkription angewendet.":
            "These replacements are applied after every transcription.",

        // MARK: - iOS: Einstellungen

        "Diktat": "Dictation",
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
        "Backup exportieren (teilen)": "Export backup (share)",
        "Backup importieren": "Import backup",
        "Daten (Mac ↔ iPhone)": "Data (Mac ↔ iPhone)",
        "Am Mac unter „Sync & Geräte“ exportieren, per AirDrop aufs iPhone senden und hier importieren — übernimmt Wörterbuch, Verlauf, Statistiken und Einstellungen. Achtung: Import ersetzt die aktuellen Daten.":
            "Export on the Mac under “Sync & devices”, send it to the iPhone via AirDrop and import it here — this takes over the dictionary, history, statistics and settings. Careful: importing replaces the current data.",
        "Wörter diktiert": "Words dictated",
        "Serie": "Streak",
        "%d Tage": "%d days",
        "Entwicklung unterstützen": "Support development",
        "shout. ist frei und quelloffen (GPL-3.0). Ich bemühe mich, die App aktuell zu halten und zu erweitern — Unterstützung ist freiwillig und hilft sehr. ❤️":
            "shout. is free and open source (GPL-3.0). I do my best to keep it current and extend it — support is voluntary and helps a lot. ❤️",

        // MARK: - iOS: Erststart

        "Diktieren direkt auf deinem iPhone — die Spracherkennung läuft komplett lokal. Keine Cloud, keine Konten, nichts verlässt dein Gerät.":
            "Dictate right on your iPhone — speech recognition runs entirely locally. No cloud, no accounts, nothing leaves your device.",
        "Mikrofon erlaubt": "Microphone allowed",
        "Für die Aufnahme deiner Diktate.": "To record your dictations.",
        "Sprachmodell geladen": "Speech model loaded",
        "Sprachmodell lädt …": "Speech model loading…",
        "%@ · %@ — einmalig, danach offline.": "%@ · %@ — once, then offline.",
        "Erlauben": "Allow",

        // MARK: - iOS: Engine-Meldungen

        "Sprachmodell konnte nicht geladen werden. Internet prüfen und erneut versuchen.":
            "The speech model could not be loaded. Check your connection and try again.",
        "Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen wird.":
            "You can only switch models while nothing is being recorded.",
        "Modell konnte nicht geladen werden (offline?). Vorheriges bleibt aktiv.":
            "The model could not be loaded (offline?). The previous one stays active.",

        // MARK: - iOS: Diktier-Tastatur

        "Für das Einfügen bitte Vollzugriff erlauben:\nEinstellungen → Allgemein → Tastatur → shout.":
            "Please allow full access for inserting:\nSettings → General → Keyboard → shout.",
        "Leerzeichen": "Space",
        "Einfügen: „%@“": "Insert: “%@”",

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

        // MARK: - Dateien auf dem iPhone

        "Datei auswählen …": "Choose a file…",
        "MP3, M4A, WAV, MP4, MOV und alles, was iOS abspielen kann": "MP3, M4A, WAV, MP4, MOV and anything iOS can play",
        "Zum Transkribieren wird das Sprachmodell gebraucht. Lade es in den Einstellungen — danach geht es hier weiter.": "Transcribing needs the speech model. Download it in the settings — then come back here.",
        "Das Modell zum Aufbereiten ist noch nicht geladen. Bis dahin kommt das Rohtranskript.": "The clean-up model is not loaded yet. Until then you get the raw transcript.",
        "Die Datei wird auf diesem Gerät gelesen — nichts wird hochgeladen. Lange Dateien dauern auf dem Telefon deutlich länger als am Rechner.": "The file is read on this device — nothing is uploaded. Long files take considerably longer on a phone than on a computer.",
        "Datei konnte nicht geöffnet werden": "The file could not be opened",
        "OK": "OK",
        "Protokoll wird erstellt …": "Creating minutes…",

        // MARK: - Meeting-Mitschnitt (iOS)

        "Meeting aufnehmen": "Record a meeting",
        "Handy auf den Tisch legen und aufnehmen. Die Aufnahme läuft weiter, wenn der Bildschirm aus ist, und wird danach automatisch transkribiert.": "Put the phone on the table and hit record. Recording continues with the screen off, and the transcript is created afterwards.",
        "Nimmt auf …": "Recording…",
        "Pausiert": "Paused",
        "Kurz vorweg": "One thing first",
        "Ein Gespräch mitzuschneiden ist ohne Einverständnis der anderen Beteiligten in Deutschland und Österreich strafbar. Frag kurz, bevor du aufnimmst.": "In Germany and Austria, recording a conversation without the consent of everyone involved is a criminal offence. Ask before you hit record.",
        "Verstanden": "Got it",
        "Zu wenig Speicher für die Sprechertrennung — der Text ist trotzdem vollständig.": "Not enough memory to separate speakers — the text is complete nonetheless.",

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
        "Zusammenfassung": "Summary",
        "Kernpunkte": "Key points",
        "Vergleichen": "Compare",
        "Vergleich ausblenden": "Hide comparison",
        "nur lesen": "read-only",
        "%d Wörter": "%d words",
        "%@ · %d Wörter": "%@ · %d words",
        "%@ in die Zwischenablage kopiert.": "%@ copied to the clipboard.",
        "Untertitel folgen immer dem ursprünglichen Transkript — Änderungen in diesem Fenster wirken sich nicht auf die Zeitmarken aus.": "Subtitles always follow the original transcript — edits in this window do not affect the timestamps.",
    ]
}
