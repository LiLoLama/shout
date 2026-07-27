using System.Globalization;

namespace Shout.Core;

/// <summary>
/// Oberflächensprache. Standard ist die Sprache des Systems: Deutsch auf einem
/// deutschsprachigen Windows, sonst Englisch. In den Einstellungen umschaltbar.
///
/// Als Schlüssel dient der deutsche Text selbst. Das hält die Aufrufe lesbar
/// (<c>Loc.T("Diktieren")</c>) und ein fehlender Eintrag fällt harmlos auf
/// Deutsch zurück, statt einen kryptischen Platzhalter anzuzeigen.
/// </summary>
public static class Loc
{
    /// <summary>Aktive Sprache: "de" oder "en".</summary>
    public static string Language { get; private set; } = "de";

    public static bool IsGerman => Language == "de";

    /// <summary>
    /// Legt die Sprache aus den Einstellungen fest. "system" folgt der
    /// Windows-Anzeigesprache; alles außer Deutsch bekommt Englisch, weil es
    /// nur diese zwei Übersetzungen gibt.
    /// </summary>
    public static void Initialize()
    {
        Language = Settings.Shared.UiLanguage switch
        {
            "de" => "de",
            "en" => "en",
            _ => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "de" ? "de" : "en",
        };
    }

    /// <summary>Übersetzt den Text (deutscher Text ist der Schlüssel).</summary>
    public static string T(string german)
        => IsGerman ? german : English.GetValueOrDefault(german, german);

    /// <summary>Übersetzt und setzt Platzhalter ein ({0}, {1} …).</summary>
    public static string F(string german, params object?[] args)
        => string.Format(CultureInfo.CurrentCulture, T(german), args);

    /// <summary>Anzeigenamen der Sprachauswahl selbst — immer in der jeweiligen Sprache.</summary>
    public static (string Key, string Label)[] LanguageOptions => new[]
    {
        ("system", T("Wie das System")),
        ("de", "Deutsch"),
        ("en", "English"),
    };

    private static readonly Dictionary<string, string> English = new(StringComparer.Ordinal)
    {
        // MARK: Tray-Menü und Zustände
        ["Diktieren"] = "Dictate",
        ["Aufnahme stoppen"] = "Stop recording",
        ["Einstellungen …"] = "Settings…",
        ["Beenden"] = "Quit",
        ["Modell wird geladen …"] = "Loading model…",
        ["Sprachmodell wird geladen …"] = "Loading speech model…",
        ["Sprachmodell wird geladen … {0} %"] = "Loading speech model… {0}%",
        ["Modell-Fehler — Internet prüfen, dann erneut „Diktieren“ wählen"] =
            "Model error — check your connection, then choose “Dictate” again",
        ["Modell-Fehler"] = "Model error",
        ["Bereit — {0}"] = "Ready — {0}",
        ["Bereit · {0} drücken"] = "Ready · press {0}",
        ["Ich höre zu …"] = "Listening…",
        ["Verarbeite …"] = "Processing…",
        ["shout. — lokale Diktier-App"] = "shout. — local dictation app",
        ["Der Hotkey ist bereits belegt — bitte in den Einstellungen ändern."] =
            "That hotkey is already taken — please pick another one in the settings.",
        ["Aufnahme konnte nicht gestartet werden: {0}"] = "Could not start recording: {0}",

        // MARK: Seitenleiste
        ["Aufnahme & Text"] = "Recording & text",
        ["Wörterbuch"] = "Dictionary",
        ["Verlauf"] = "History",
        ["Statistiken"] = "Statistics",
        ["Modelle"] = "Models",
        ["Sync & Geräte"] = "Sync & devices",
        ["Unterstützen"] = "Support",

        // MARK: Aufnahme & Text
        ["Aufnahme"] = "Recording",
        ["So startest du"] = "How to start",
        ["Drück die Tastenkombination, mit der du diktieren willst."] =
            "Press the key combination you want to dictate with.",
        ["Ändern"] = "Change",
        ["Taste drücken …"] = "Press a key…",
        ["Von selbst aufhören"] = "Stop by itself",
        ["Stoppt automatisch nach kurzer Sprechpause."] = "Stops automatically after a short pause.",
        ["Pause bis Stopp"] = "Pause before stopping",
        ["Pille immer anzeigen"] = "Always show the pill",
        ["Zeigt die Aufnahme-Pille dauerhaft am Bildschirmrand — per Klick starten, mit ✕/✓ abbrechen oder einfügen."] =
            "Keeps the recording pill at the edge of the screen — click to start, ✕ to cancel, ✓ to insert.",
        ["Position der Pille"] = "Pill position",
        ["Wähle eine Ecke — oder zieh die Pille einfach mit der Maus an eine beliebige Stelle."] =
            "Pick a corner — or simply drag the pill anywhere with the mouse.",
        ["Unten Mitte"] = "Bottom center",
        ["Unten links"] = "Bottom left",
        ["Unten rechts"] = "Bottom right",
        ["Oben Mitte"] = "Top center",
        ["Oben links"] = "Top left",
        ["Oben rechts"] = "Top right",
        ["Frei verschoben"] = "Moved freely",

        ["Text"] = "Text",
        ["Text automatisch aufräumen"] = "Clean up text automatically",
        ["Füllwörter raus, Satzzeichen und Aufzählungen setzen. Lädt ein zweites Modell."] =
            "Removes filler words, adds punctuation and lists. Loads a second model.",
        ["Sprachbefehle"] = "Spoken commands",
        ["‚Komma', ‚Punkt', ‚Fragezeichen', ‚neue Zeile', ‚neuer Absatz' werden zu echten Satzzeichen/Umbrüchen."] =
            "“comma”, “period”, “question mark”, “new line”, “new paragraph” become real punctuation and breaks.",
        ["In der Zwischenablage behalten"] = "Keep in the clipboard",
        ["Das Diktat bleibt zusätzlich in der Zwischenablage — sonst wird der vorherige Inhalt wiederhergestellt."] =
            "The dictation also stays in the clipboard — otherwise the previous content is restored.",

        ["Sprache & Ton"] = "Language & sound",
        ["Diktier-Sprache"] = "Dictation language",
        ["Sprache der Transkription. „Automatisch“ erkennt sie pro Aufnahme selbst."] =
            "Language of the transcription. “Automatic” detects it per recording.",
        ["Deutsch"] = "German",
        ["English"] = "English",
        ["Automatisch"] = "Automatic",
        ["Oberfläche"] = "Interface",
        ["Sprache der Bedienoberfläche. „Wie das System“ folgt der Windows-Anzeigesprache."] =
            "Language of the user interface. “Match the system” follows the Windows display language.",
        ["Wie das System"] = "Match the system",
        ["Klang-Signale"] = "Sound cues",
        ["Dezente Töne beim Start der Aufnahme und wenn der Text eingefügt ist."] =
            "Subtle tones when recording starts and when the text is inserted.",

        ["Mikrofon"] = "Microphone",
        ["Eingang"] = "Input",
        ["Systemstandard"] = "System default",

        // MARK: Wörterbuch
        ["Wörter, die shout. richtig schreiben soll"] = "Words shout. should spell correctly",
        ["Neuer Begriff (z. B. inthezone)"] = "New term (e.g. inthezone)",
        ["Hinzufügen"] = "Add",
        ["Aus Datei (CSV/TXT) …"] = "From file (CSV/TXT)…",
        ["Begriffe importieren"] = "Import terms",
        ["Noch keine Begriffe."] = "No terms yet.",
        ["{0} neue Begriffe."] = "{0} new terms.",
        ["Import fehlgeschlagen: {0}"] = "Import failed: {0}",
        ["Automatisch verbessert"] = "Corrected automatically",
        ["falsch"] = "wrong",
        ["richtig"] = "right",
        ["Noch keine Korrekturen — trag eine falsche und die richtige Schreibweise ein."] =
            "No corrections yet — enter a wrong and the correct spelling.",

        // MARK: Verlauf
        ["Alle löschen"] = "Delete all",
        ["Gesamten Verlauf löschen?"] = "Delete the entire history?",
        ["Noch keine Diktate"] = "No dictations yet",
        ["Was du diktierst, erscheint hier — zum Nachlesen und erneut Kopieren."] =
            "Whatever you dictate shows up here — to read again and copy.",
        ["Heute"] = "Today",
        ["Gestern"] = "Yesterday",

        // MARK: Statistiken
        ["Wörter gesamt"] = "Words total",
        ["Ø Wörter/Minute"] = "Ø words/minute",
        ["Diktate"] = "Dictations",
        ["Korrekturen gelernt"] = "Corrections learned",
        ["Streak"] = "Streak",
        ["Tage aktuell"] = "days current",
        ["längster"] = "longest",
        ["Meistgenutztes Wort"] = "Most used word",
        ["Aktivste Zeit"] = "Most active time",
        ["Vormittags"] = "Mornings",
        ["Mittags"] = "Midday",
        ["Nachmittags"] = "Afternoons",
        ["Abends"] = "Evenings",
        ["Nachts"] = "Nights",

        // MARK: Modelle
        ["{0} GB Arbeitsspeicher · {1} Kerne"] = "{0} GB memory · {1} cores",
        ["Empfohlen für diesen Rechner: {0} zum Transkribieren, {1} zum Aufbereiten."] =
            "Recommended for this machine: {0} for transcribing, {1} for cleanup.",
        ["Transkription (Sprache → Text)"] = "Transcription (speech → text)",
        ["Aufbereitung & Formatierung (KI-Textmodell)"] = "Cleanup & formatting (AI text model)",
        ["Empfohlen"] = "Recommended",
        ["Viel RAM nötig"] = "Needs lots of RAM",
        ["lädt …"] = "loading…",
        ["Während einer Aufnahme lässt sich das Modell nicht wechseln."] =
            "The model cannot be switched while recording.",
        ["Download fehlgeschlagen: {0}"] = "Download failed: {0}",
        ["Modelle werden beim ersten Auswählen einmalig von Hugging Face geladen und danach lokal gespeichert. Alles läuft anschließend komplett offline auf deinem Rechner."] =
            "Models are downloaded from Hugging Face once when first selected and then stored locally. Everything runs completely offline on your machine afterwards.",
        // Modell-Beschreibungen
        ["Sehr schnell, mäßige Genauigkeit — für schwache Rechner."] =
            "Very fast, moderate accuracy — for slower machines.",
        ["Guter Kompromiss aus Tempo und Genauigkeit."] = "A good balance of speed and accuracy.",
        ["Beste Genauigkeit, braucht einen flotten Rechner."] =
            "Best accuracy, needs a fast machine.",
        ["Schnell, für die Textbereinigung völlig ausreichend."] =
            "Fast, entirely sufficient for cleaning up text.",
        ["Gründlicher, spürbar langsamer — für starke Rechner."] =
            "More thorough, noticeably slower — for powerful machines.",

        // MARK: Sync & Geräte
        ["Daten übertragen"] = "Transfer data",
        ["shout. speichert alles lokal — keine Cloud. Für ein zweites Gerät exportierst du eine Datei, kopierst sie hinüber (USB-Stick, Netzwerk …) und importierst sie dort. Die Datei passt auch zur Mac- und iPhone-App."] =
            "shout. keeps everything local — no cloud. For a second device you export a file, copy it over (USB stick, network…) and import it there. The file also works with the Mac and iPhone app.",
        ["Exportieren …"] = "Export…",
        ["Importieren …"] = "Import…",
        ["Exportiert nach {0}."] = "Exported to {0}.",
        ["Export fehlgeschlagen: {0}"] = "Export failed: {0}",
        ["Import ERSETZT Wörterbuch, Verlauf und Statistiken auf diesem Gerät. Fortfahren?"] =
            "Importing REPLACES the dictionary, history and statistics on this device. Continue?",
        ["Ungültige Backup-Datei."] = "Invalid backup file.",
        ["Importiert: {0} Begriffe, {1} Diktate."] = "Imported: {0} terms, {1} dictations.",
        ["In der Datei enthalten"] = "Contained in the file",
        ["Begriffe & gelernte Korrekturen"] = "Terms & learned corrections",
        ["Deine bisherigen Diktate"] = "Your previous dictations",
        ["Wörter, Streak, aktive Tage"] = "Words, streak, active days",
        ["Einstellungen"] = "Settings",
        ["Auto-Stopp, Stille-Dauer, Formatierung"] = "Auto-stop, silence duration, formatting",
        ["Beim Import werden die aktuellen Daten auf diesem Gerät ersetzt. Die Datei enthält deinen Verlauf im Klartext — behandle sie vertraulich."] =
            "Importing replaces the current data on this device. The file contains your history in plain text — treat it as confidential.",

        // MARK: Unterstützen und Aktualisierung
        ["Aktualisierung"] = "Update",
        ["shout. {0} für Windows"] = "shout. {0} for Windows",
        ["Nach Aktualisierungen suchen"] = "Check for updates",
        ["Nach Aktualisierungen suchen …"] = "Check for updates…",
        ["Jetzt laden"] = "Download now",
        ["Neu starten und übernehmen"] = "Restart and apply",
        ["Releases auf GitHub öffnen"] = "Open releases on GitHub",
        ["Noch nicht nach Aktualisierungen gesucht."] = "Haven’t checked for updates yet.",
        ["Suche nach Aktualisierungen …"] = "Checking for updates…",
        ["shout. ist aktuell."] = "shout. is up to date.",
        ["shout. {0} ist aktuell."] = "shout. {0} is up to date.",
        ["Version {0} ist verfügbar."] = "Version {0} is available.",
        ["Wird geladen … {0} %"] = "Downloading… {0}%",
        ["Version {0} ist bereit — beim Neustart wird sie übernommen."] =
            "Version {0} is ready — it will be applied on restart.",
        ["Version {0} laden"] = "Download version {0}",
        ["Neu starten für Version {0}"] = "Restart for version {0}",
        ["Version {0} ist bereit. Über das Tray-Menü neu starten, um sie zu übernehmen."] =
            "Version {0} is ready. Restart from the tray menu to apply it.",
        ["Aktualisierung fehlgeschlagen: {0}"] = "Update failed: {0}",
        ["Automatische Aktualisierung steht nur in der installierten Version zur Verfügung (Setup.exe von der Releases-Seite). Diese Kopie läuft aus einem Programmordner."] =
            "Automatic updates are only available in the installed version (Setup.exe from the releases page). This copy runs from a program folder.",

        ["shout. ist Open Source"] = "shout. is open source",
        ["Kostenlos, quelloffen und komplett lokal."] = "Free, open source and entirely local.",
        ["shout. entsteht in meiner freien Zeit. Wenn dir die App hilft und du die Weiterentwicklung unterstützen möchtest, freue ich mich riesig — freiwillig, ohne Verpflichtung."] =
            "shout. is built in my spare time. If the app helps you and you’d like to support its development, I’d be delighted — entirely voluntary, no obligation.",
        ["Quellcode auf GitHub"] = "Source code on GitHub",
        ["Was shout. ausmacht"] = "What makes shout. shout.",
        ["Frei & quelloffen"] = "Free & open source",
        ["Der komplette Quellcode ist öffentlich — nutzen, anpassen, weitergeben."] =
            "The complete source code is public — use it, adapt it, pass it on.",
        ["Lokal & privat"] = "Local & private",
        ["Keine Cloud, keine Konten, keine Datenweitergabe. Alles bleibt auf deinem Rechner."] =
            "No cloud, no accounts, no data sharing. Everything stays on your machine.",
        ["Aktiv gepflegt"] = "Actively maintained",
        ["Ich bemühe mich, shout. aktuell zu halten, zu verbessern und zu erweitern."] =
            "I do my best to keep shout. current, improved and extended.",
        ["Fehler gefunden oder eine Idee? Auf GitHub freue ich mich über Issues und Pull Requests."] =
            "Found a bug or have an idea? Issues and pull requests are welcome on GitHub.",

        // MARK: Tastennamen (Hotkey-Anzeige)
        ["Strg"] = "Ctrl",
        ["Umschalt"] = "Shift",
        ["Leertaste"] = "Space",
        ["Eingabe"] = "Enter",

        // MARK: Dateiauswahl
        ["Text/CSV (*.csv;*.txt)|*.csv;*.txt|Alle Dateien (*.*)|*.*"] =
            "Text/CSV (*.csv;*.txt)|*.csv;*.txt|All files (*.*)|*.*",
        ["shout-Backup (*.json)|*.json"] = "shout backup (*.json)|*.json",
    };
}
