# Externe Anbieter für Aufbereitung und Transkription (macOS + iOS)

Stand: 2026-09-01 · Status: **umgesetzt** (macOS + iOS); Windows offen.
Umsetzungsplan: `docs/superpowers/plans/2026-09-01-externe-anbieter.md`

## Ziel

shout. verarbeitet alles auf dem Gerät. Das ist die Haltung des Programms und
bleibt die Voreinstellung. Zwei Gruppen fallen dabei aber durchs Raster:

1. **Zu schwache Hardware.** Die Aufbereitung braucht MLX (Apple Silicon) und
   je nach Modell 8–48 GB RAM. Wer darunter liegt, bekommt entweder das
   kleinste 4-bit-Modell oder gar keine Aufbereitung.
2. **Qualitätsanspruch.** Ein 4-bit-2B-Modell räumt Diktate ordentlich auf, aber
   ein großes Modell räumt sie besser auf. Manche wollen einfach das bessere
   Ergebnis und nehmen dafür in Kauf, dass Text das Gerät verlässt.

Diese Erweiterung macht **beide Verarbeitungsschritte umschaltbar**: Aufbereitung
und Transkription können je einzeln auf einen selbst gewählten Anbieter gelegt
werden. Lokal bleibt Voreinstellung; es findet nie ein automatischer Wechsel nach
außen statt.

Nebenwirkung, die ausdrücklich Teil des Ziels ist: Mit Ollama und LM Studio im
Katalog kann ein schwacher Laptop den kräftigen Rechner im eigenen Netz benutzen.
Dann verlässt trotzdem nichts das eigene Netzwerk — die Haltung des Programms
bleibt gewahrt, die Rechenleistung nicht.

## Umfang

**Enthalten**

- Ein OpenAI-kompatibler Client für Text (`/v1/chat/completions`) und Audio
  (`/v1/audio/transcriptions`).
- Vorlagen-Katalog als reine Daten (Name, Basis-URL, Schlüssel-Link, empfohlene
  Modelle, Audio-Fähigkeit, Einordnung) plus „Eigener Endpunkt".
- Zwei unabhängige Schalter: `formatEngine` und `asrEngine`, je `lokal`/`extern`.
  Sie liegen mit der übrigen Endpunkt-Konfiguration (Vorlagen-ID, Basis-URL,
  Modell-ID, je getrennt für Text und Audio) in `UserDefaults`, neben den
  bestehenden Schlüsseln `asrModel` und `formatModel`. Nur der Schlüssel selbst
  liegt in der Keychain.
- Schlüsselverwahrung in der Keychain, gerätegebunden.
- Modell-Liste und Preistabelle **nur auf Knopfdruck** aus dem Netz.
- Kostenzählung aus den echten `usage`-Werten der Antworten, in USD.
- „Verbindung testen" mit Klartext-Diagnose.
- macOS **und** iOS (gemeinsamer Code), Oberfläche je Plattform.
- Angepasste Versprechen in `README.md` und `Support/Info-iOS.plist`.

**Bewusst nicht enthalten**

- **Windows.** Der C#-Port zieht als eigener Schritt nach, mit demselben Katalog
  als Daten. Der entstehende Funktionsversatz gehört nach `OFFEN.md`.
- **Anmeldung mit dem eigenen Abo (ChatGPT, SuperGrok, Claude).** Geht nicht
  legitim — Begründung unten unter „Abo-Anmeldung".
- **Agent-CLI als Engine** (`codex exec`, `claude -p`). Technisch machbar und
  legitim, aber zurückgestellt — Begründung unten.
- **Automatische Modell-Empfehlung aus dem Netz.** Empfehlungen sind
  handverlesen und werden mit Releases gepflegt; eine Empfehlung, die an fremden
  Daten hängt, ist nicht testbar.
- **Umrechnung in Euro.** Anbieter rechnen in USD ab; ein erfundener Kurs wäre
  entweder veraltet oder ein zweiter Netzzugriff.
- **Dauerhaftes „Cloud"-Abzeichen in Pille oder Dashboard.** Ausdrücklich
  entschieden: der Zustand steht in der Modell-Ansicht, sonst fühlt sich die App
  identisch an. Das Dashboard zeigt weiterhin den Namen des aktiven Modells —
  dort steht dann eben „GPT-5 mini · OpenRouter".

## Architektur

Zwei Fassaden bleiben unverändert, darunter je zwei austauschbare Engines:

```
AppDelegate / MobileEngine / FileTranscriptionQueue   ← kein Aufrufer ändert sich
        │
        ├─ Formatter   (Router: Prompts, Chunking, Guard, Protokolle, Sprachprofil)
        │     ├─ LocalTextEngine    ← heutiger MLX-Code, 1:1 herausgezogen
        │     └─ RemoteTextEngine   ← POST /v1/chat/completions
        │
        └─ Transcriber (Router: Sprachwahl, Plausibilitätsprüfung, Segmentaufbau)
              ├─ LocalSpeechEngine  ← heutiger WhisperKit-Code
              └─ RemoteSpeechEngine ← POST /v1/audio/transcriptions (multipart)
```

### Warum Router statt Weiche

Verworfene Alternativen:

- **Weiche in `Formatter`/`Transcriber`** (`if remote { … }`): weniger Dateien,
  aber `Formatter.swift` würde weiter wachsen und dann Modell-Laden, HTTP,
  Chunking, Protokolle und Sprachprofil in einer Klasse vereinen. Tests
  bräuchten echte Netzaufrufe.
- **Wahl in den Aufrufern**: dieselbe Weiche läge dreifach in `AppDelegate`,
  `MobileEngine` und `FileTranscriptionQueue`.

Der Router gewinnt, weil alles Anbieterunabhängige oben bleibt: `FormattingGuard`
und `TextChunker` greifen damit automatisch auch bei Cloud-Modellen. Ein
Cloud-Modell, das auf das Diktat *antwortet* statt es zu formatieren, wird
genauso verworfen wie Gemma heute.

### Das Textprotokoll

`Formatter` hat den Schnitt schon: die private Methode
`respond(system:user:temperature:)` ist genau die eine Operation, die ein
Textmodell leisten muss. Das Protokoll umfasst deshalb nur:

- `isReady`, `isLoading`, `displayName`
- `chunkLength` — die Engine sagt, wie große Stücke sie verträgt
- `prepare(reset:onProgress:)`, `warmUp()`
- `respond(system:user:temperature:) async throws -> String`

Beide Engines sind Actors, wie `Formatter` heute; die Zugriffe im Protokoll sind
entsprechend `async`.

`chunkLength` ist die eine bewusste Abweichung im Verhalten: Lokal schneidet
`TextChunker` klein, weil das 4-bit-Modell bei langen Eingaben still Inhalt
verschluckt (siehe Kommentar in `Formatter.format`). Ein Cloud-Modell mit großem
Kontextfenster darf größere Stücke bekommen — weniger Aufrufe, weniger Latenz,
weniger Kosten. Konkret: lokal die heutigen Werte aus `TextChunker`, extern 6000
Zeichen für Diktate und 12000 für Protokoll-Abschnitte. Beides sind Konstanten im
Code, keine Einstellung — die Oberfläche soll das nicht fragen müssen.

### Das Sprachprotokoll

Die Engine liefert `[TranscriptSegment]`, der Router fügt zusammen.
`transcribe(_:)` und `transcribeSegments(_:)` bleiben nach außen unverändert.

Die Cloud-Endpunkte können Segmente: mit `response_format=verbose_json` kommen
Zeitstempel zurück. Anbieter, die nur Fließtext liefern, bekommen ein
Ersatzsegment über die Gesamtlänge. Dann funktionieren Diktat und `.txt`, aber
**`.srt`-Untertitel und Sprechertrennung werden unbrauchbar** — das muss an der
Vorlage stehen, nicht stillschweigend passieren.

### Neue Dateien

| Datei | Aufgabe |
|---|---|
| `TextEngine.swift` | Protokoll + gemeinsame Typen |
| `LocalTextEngine.swift` | MLX-Code aus `Formatter` herausgezogen |
| `RemoteTextEngine.swift` | Chat-Completions-Client |
| `SpeechEngine.swift` | Protokoll |
| `LocalSpeechEngine.swift` | WhisperKit-Code aus `Transcriber` herausgezogen |
| `RemoteSpeechEngine.swift` | Transcriptions-Client (multipart) |
| `RemoteProvider.swift` | Vorlagen-Katalog, URL-Bau, Fehlertypen, Zeitgrenzen |
| `ProviderKeychain.swift` | Keychain-Zugriff |
| `WAVEncoder.swift` | `[Float]` → 16-bit-PCM-WAV im Speicher |
| `ProviderCosts.swift` | Preistabelle, Zählung, Vorab-Schätzung |
| `ProviderCatalogFetch.swift` | `/v1/models` und Preisliste auf Knopfdruck |
| `ProviderPanel.swift` | Oberflächen-Baustein macOS (`ConsolePanel`/`FieldRow`), zweimal verwendet |
| `MobileProviderSection.swift` | Dasselbe im iOS-`Form`/`Section`-Idiom, zweimal verwendet |

`Formatter.swift` und `Transcriber.swift` werden dabei **kleiner**: das
Modell-Laden zieht komplett aus. Alle neuen Dateien müssen einzeln in die
iOS-Quellenliste in `project.yml` (der `ShoutMobile`-Abschnitt listet die
FlowLokal-Dateien explizit).

## Anbieter-Katalog

Eine Vorlage ist reine Daten: `id`, `name`, `baseURL`, `keyURL`, `chatModels`,
`audioModels`, `needsKey`, `note`. Ein neuer Anbieter ist ein Listeneintrag.

| Vorlage | Text | Audio | Einordnung |
|---|---|---|---|
| OpenAI | ✓ | ✓ | Der Referenz-Endpunkt |
| OpenRouter | ✓ | – | Ein Schlüssel, hunderte Modelle |
| EURouter | ✓ | – | `https://api.eurouter.ai/v1` · Verarbeitung nur in der EU, 100+ Modelle |
| Groq | ✓ | ✓ | Sehr schnell — relevant fürs Live-Diktat |
| Mistral | ✓ | ✓ | EU-Anbieter |
| DeepSeek | ✓ | – | Günstig |
| Anthropic | ✓ | – | Über die OpenAI-Kompatibilitätsschicht |
| Google Gemini | ✓ | – | Dito |
| xAI · Grok | ✓ | – | `https://api.x.ai/v1` · Schlüssel aus console.x.ai — **SuperGrok-Abo gilt hier nicht** |
| Ollama | ✓ | – | Kein Schlüssel, eigener Rechner/eigenes Netz |
| LM Studio | ✓ | – | Dito |
| Eigener Endpunkt | ✓ | ✓ | Alles selbst eintragen (whisper.cpp-Server, vLLM, …) |

Geprüft sind die Basis-URLs von EURouter (`https://api.eurouter.ai/v1`,
`/models` vorhanden, Audio nicht dokumentiert) und xAI (`https://api.x.ai/v1`).
**Alle übrigen Basis-URLs und die Modell-IDs sind vor dem Ausliefern einmal
gegen die Dokumentation des jeweiligen Anbieters zu prüfen** — eine falsche URL
in einer mitgelieferten Vorlage ist schlimmer als keine Vorlage. Das ist eine
Aufgabe im Umsetzungsplan, keine Annahme in diesem Entwurf.

Pauschal-Abos mit echtem Endpunkt (z. B. GLM Coding Plan von z.ai,
Anthropic-kompatibel, fester Monatspreis mit Kontingent statt Token-Abrechnung)
sind vom Katalog automatisch mitabgedeckt — sie sind aus Sicht der App eine
normale Basis-URL plus Schlüssel. Damit ist der Wunsch „Abo nutzen statt pro
Anfrage zahlen" ohne Sonderweg erfüllt.

## Schlüsselverwahrung

Keychain, `kSecClassGenericPassword`, Service `com.inthezone.flowlokal.provider`,
Konto = Vorlagen-ID (ein Schlüssel pro Anbieter, egal ob für Text, Audio oder
beides). Zugriffsklasse `…WhenUnlockedThisDeviceOnly` — kein Abgleich über die
iCloud-Keychain, passend zur Haltung des Programms. Die Tastatur-Erweiterung
braucht keinen Zugriff, sie formatiert nichts.

Drei Regeln:

1. **`BackupBundle` bekommt niemals den Schlüssel.** Die Konfiguration (Vorlage,
   Basis-URL, Modell) darf in `SettingsSnapshot` — sie ist harmlos und beim
   Gerätewechsel praktisch. Beim Import fällt der Schalter aber auf **lokal**
   zurück, solange kein Schlüssel in der Keychain liegt. Ein Backup darf nicht
   dazu führen, dass ein Gerät stillschweigend anfängt, Text zu verschicken.
2. **Nie anzeigen, nie protokollieren.** In der Oberfläche steht `sk-…4f2a`.
   Fehlermeldungen werden gekürzt; der `Authorization`-Header taucht in keinem
   `NSLog` auf.
3. **„Verbindung testen".** Ein Minimalaufruf mit fünf Token, Ergebnis
   „Verbindung steht · 0,4 s" oder der konkrete Fehler (Schlüssel abgelehnt,
   Adresse nicht erreichbar, Modell unbekannt, kein Guthaben). Ohne diesen Knopf
   findet niemand eine vertippte Basis-URL.

## Kosten

**Gezählt, nicht geschätzt.** Jede OpenAI-kompatible Antwort enthält `usage` mit
den echten Token-Zahlen — die Zählung braucht kein Netz und ist exakt.
`StatsStore` bekommt zwei Zähler pro Monat: Token (Text) und Sekunden (Audio,
wird meist pro Minute abgerechnet), aufgeschlüsselt nach Anbieter und Modell. In
der Statistik-Ansicht erscheint „Diesen Monat · 128.000 Token · ca. $0,42".

**Abweichung bei der Umsetzung (01.09.2026): eigene Datei statt `StatsStore`.**
Der Entwurf wollte die Zähler als optionale Felder in `StatsStore.Data`. Beim
Bauen sprachen drei Dinge dagegen: Ausgaben sind gerätebezogen — über die
Sicherungsdatei auf ein zweites Gerät getragen und dort addiert ergäben sie eine
Zahl, die nichts beschreibt; `BackupBundle` bleibt so ganz unverändert bei
Version 1, ohne neues Feld und ohne Migrationspfad; und die Engines sind Actors
und können in einen eigenen Speicher ohne Kopplung an `StatsStore` melden. Der
Verbrauch liegt daher in `anbieter-verbrauch.json`, die Preistabelle in
`anbieter-preise.json`, beide neben `stats.json`. Die neuen Felder in
`SettingsSnapshot` bleiben wie geplant optional.

**Anzeige in USD.** Alle Anbieter rechnen in USD ab.

**Die Preistabelle** liegt als JSON im Programm und wird nur auf Knopfdruck
aktualisiert; Quelle ist die freie Modell-API von OpenRouter (die Endpunkte der
Anbieter selbst liefern Modell-IDs, aber fast nie Preise). Beschriftung:
„Näherung — abgerechnet wird beim Anbieter", dazu der Stand des letzten Abrufs.
Im Modell-Wähler steht daraus eine Vorab-Zahl („ca. $0,0004 je Diktat"),
gerechnet auf ein typisches Diktat. Bei Ollama, LM Studio und eigenem Endpunkt
verschwinden alle Kostenanzeigen.

## Fehlerverhalten

**Text — das bestehende Prinzip gilt unverändert: niemals blockieren.**
Zeitüberschreitung, HTTP-Fehler, kein Guthaben, Netz weg → der Rohtext wird
eingefügt, genau wie heute bei nicht geladenem Modell.

| | Zeitgrenze | Wiederholung |
|---|---|---|
| Diktat | 15 s hart | keine (der Mensch wartet) |
| Datei / Protokoll | 120 s je Abschnitt | eine, `Retry-After` bei 429 beachtet |

Offline wird am kurzen Verbindungs-Timeout erkannt, statt 15 Sekunden zu warten.

**Audio — hier gibt es keinen Rohtext als Rückfall.** Zwei Stufen:

1. Liegt ein lokales Whisper-Modell auf der Platte, übernimmt es. Der Weg
   **extern → lokal** ist immer unbedenklich; der umgekehrte passiert nie von
   selbst.
2. Liegt keines, wandert die Aufnahme in die bestehende
   `FileTranscriptionQueue` statt in den Müll — dort steht sie mit „erneut
   versuchen" wie ein normaler Datei-Auftrag.

### Lange Aufnahmen (Upload-Grenze)

Die Transcriptions-Endpunkte begrenzen die Dateigröße (bei OpenAI 25 MB). WAV mit
16 kHz, Mono, 16 bit sind rund 1,9 MB je Minute — die Grenze liegt damit bei etwa
**13 Minuten je Aufruf**. Für Diktate ist das folgenlos, für die
Datei-Transkription nicht: dort sind Aufnahmen von einer Stunde der Normalfall.

`RemoteSpeechEngine` schneidet deshalb selbst: Fenster von 10 Minuten, Schnitt an
der leisesten Stelle innerhalb der letzten 15 Sekunden des Fensters. Die
Zeitstempel der zurückgegebenen Segmente werden um den Fenster-Versatz
verschoben, damit `.srt` weiter stimmt. Fenster laufen der Reihe nach, nicht
parallel — sonst reißt ein Ratenlimit den ganzen Auftrag ab, und der
Fortschrittsbalken der Warteschlange braucht ohnehin eine Reihenfolge.

**Abweichung bei der Umsetzung (01.09.2026): keine Überlappung.** Der Entwurf
sah 2 Sekunden Überlappung vor, aus der die doppelten Segmente wieder entfernt
werden. Beim Bauen fiel auf, dass diese Entfernung eine Heuristik wäre, die im
Zweifel echten Inhalt verwirft — genau der Fehler, den dieses Programm nicht
machen darf. Wird an der leisesten Stelle getrennt, braucht es die Überlappung
ohnehin nicht. Der Preis: Wird über zehn Minuten durchgehend gesprochen, findet
sich im Suchbereich keine Pause und ein einzelnes Wort am Übergang kann
verstümmelt werden. Das ist selten und sichtbar, während stiller Inhaltsverlust
weder das eine noch das andere ist. Ein Test hält fest, dass die Fenster
lückenlos **und** ohne Überlappung abdecken.

Ein Fenster, das dauerhaft scheitert, lässt den Auftrag scheitern (statt eine
Lücke im Transkript zu hinterlassen) — die Regel darunter greift dann.

**Fehler müssen sichtbar sein**, sonst hält man einen stillen Rohtext für
Absicht. Kein Dauerabzeichen, aber: der letzte Fehler steht im Klartext neben dem
Anbieter („Letzter Fehler · 401 Schlüssel abgelehnt · 14:32"), und beim
**ersten** Fehlschlag einer Sitzung erscheint der bestehende Toast einmalig.

## Oberfläche

**Ort ist die Modell-Ansicht, nicht die Einstellungen.** `ModelsView` beantwortet
schon heute die Frage „welches Modell macht welchen Schritt"; die Anbieterwahl
ist dieselbe Frage. Auf iOS liegt dieselbe Struktur in
`MobileSettingsView.modelSection` mit denselben zwei Abschnitten.

Jedes der beiden bestehenden Panels („Transkription (Sprache → Text)" und
„Aufbereitung & Formatierung") bekommt oben einen Umschalter **„Auf diesem
Gerät" / „Anbieter"**:

- **Auf diesem Gerät** → alles bleibt exakt wie heute: Modell-Liste,
  RAM-Empfehlung, Download-Fortschritt, Hugging-Face-Liste.
- **Anbieter** → `ProviderPanel(purpose:)` mit Vorlagen-Auswahl, Schlüsselfeld
  (`sk-…4f2a`, „Ersetzen"/„Entfernen"), Modellfeld mit „Modelle laden"-Knopf und
  freier Eingabe für ganz neue Modell-IDs, „Verbindung testen", Kostenzeile und
  gegebenenfalls dem letzten Fehler.

Ein Baustein, zweimal verwendet. Bei Vorlagen ohne Schlüsselbedarf (Ollama, LM
Studio) verschwindet das Schlüsselfeld, stattdessen ein Adressfeld mit
vorbelegtem Port. Kann eine Vorlage kein Audio, sagt das Audio-Panel das hin,
statt einen Fehlschlag zu produzieren. Empfehlungen nutzen den bestehenden
`tag()`-Stil („Empfohlen") — kein neues Gestaltungsvokabular.

**Onboarding:** in `OnboardingView` **und** `MobileOnboardingView` je eine Zeile
im Modell-Download-Schritt — „Rechner zu schwach? Du
kannst stattdessen einen eigenen Anbieter verbinden →". Kein zusätzlicher
Schritt, kein Dialog. Begründung: Wer zu schwache Hardware hat, trifft zuerst das
Onboarding, das ihm einen Mehr-Gigabyte-Download vorschlägt, den seine Maschine
nicht tragen kann.

Alle neuen Texte über `Loc.t("deutscher Text")` mit dem deutschen Text als
Schlüssel; auf typografische Apostrophe achten, keine Schlüssel doppeln.

## Angepasste Versprechen

Beide Änderungen landen **zusammen mit der Funktion**, nicht vorher — sonst
beschreiben sie etwas, das es noch nicht gibt.

**`Support/Info-iOS.plist`**, `NSMicrophoneUsageDescription`. Diesen Text liest
die App-Store-Prüfung, und iOS zeigt ihn im Berechtigungsdialog.

- alt: „shout. nimmt dein Mikrofon auf, um Sprache lokal in Text umzuwandeln.
  Nichts verlässt dein Gerät."
- neu: „shout. nimmt dein Mikrofon auf, um Sprache in Text umzuwandeln.
  Standardmäßig geschieht das lokal auf deinem Gerät; nur wenn du selbst einen
  externen Anbieter einrichtest, wird die Aufnahme dorthin übertragen."

**`README.md`.** Der Einstieg behauptet heute „No cloud, no account, no data ever
leaves the machine". Das Versprechen bleibt als **Voreinstellung** stehen und
wird präzisiert („by default"), dazu ein eigener kurzer Abschnitt „Optional:
bring your own provider". Dieser Abschnitt nennt ausdrücklich den Ollama-/LM-
Studio-Fall (kräftiger Rechner im eigenen Netz), weil das die Haltung des
Programms gerade nicht aufgibt, sondern erweitert.

## Abo-Anmeldung

Ausdrücklich geprüft, weil es naheliegt und bei Codex, Claude Code und Gemini CLI
sichtbar funktioniert.

**„Sign in with ChatGPT" existiert** seit dem 2. August 2026 als offene Beta —
aber als *Identitätssystem*: die App erhält Name, E-Mail-Adresse und Profilbild,
mit sechs Startpartnern. Ein Nutzungsrecht überträgt es nicht; Anfragen unter dem
Plan des Nutzers laufen zu lassen ist ein offener Feature-Wunsch
(`openai/codex#10974`), kein ausgeliefertes Produkt.

Bei Codex, Claude Code und Gemini CLI geht es, weil das **Erstanbieter-Clients**
sind: die Anmeldung stellt Token aus, die an deren Client-ID gebunden sind.
Fremd-Apps, die dasselbe können, benutzen die Client-ID des Erstanbieter-Clients
— das verstößt gegen die Nutzungsbedingungen, kostet regelmäßig Konten und
bricht bei jeder Rotation von Client-ID oder Anmelde-Endpunkt. Für ein
quelloffenes, unter Klarnamen notarisiertes Programm ist das die falsche Wette.
**Wird nicht gebaut.**

Zwei legitime Wege zum selben Ziel:

- **Pauschal-Abos mit echtem Endpunkt** (z.ai GLM Coding Plan, Kimi, MiniMax):
  fester Monatspreis, Kontingent statt Token-Rechnung, normale Basis-URL. Vom
  Katalog abgedeckt, kein zusätzlicher Code. **Ist enthalten.**
- **Lokal installierte Agent-CLI als dritte Engine** (`codex exec`, `claude -p`):
  eigener Erstanbieter-Client, eigene Anmeldung, eigener Rechner — kein
  Schlüssel, keine Token-Abrechnung, keine Grauzone für shout. Signierung
  erlaubt es ohne Änderung (die App läuft bewusst ohne App-Sandbox wegen
  Accessibility und globaler Hotkeys; Hardened Runtime beschränkt Bibliotheken,
  nicht Kindprozesse). **Zurückgestellt**, weil so eine CLI eine komplette
  Agenten-Laufzeit startet: 2–10 s Vorlauf, fürs Live-Diktat unbrauchbar,
  für Datei-Transkripte und Protokolle dagegen tauglich. Abo-Kontingente sind
  außerdem nicht für 200 Diktate am Tag gebaut, und unter iOS geht es gar nicht.
  Kommt als eigene Ausbaustufe, wenn der HTTP-Weg im Alltag steht.

## Reihenfolge der Umsetzung

Vier Stufen, jede einzeln lauffähig und ausliefertauglich:

1. **Engine-Extraktion ohne Verhaltensänderung.** `LocalTextEngine` und
   `LocalSpeechEngine` herausziehen, Router einsetzen, Tests grün. Danach
   verhält sich die App exakt wie vorher — das ist die Prüfung, dass der Schnitt
   sitzt.
2. **Text extern.** `RemoteTextEngine`, Katalog, Keychain, Oberflächen-Baustein,
   „Verbindung testen". Ab hier ist die Funktion für Aufbereitung, Protokolle und
   Sprachprofil nutzbar.
3. **Audio extern.** `RemoteSpeechEngine`, `WAVEncoder`, Fensterung langer
   Aufnahmen, Rückfall auf lokal beziehungsweise in die Warteschlange.
4. **Kosten, Preisliste, Onboarding-Zeile, angepasste Versprechen in README und
   Info-iOS.plist.**

Die Windows-Portierung folgt als eigener Durchgang nach Stufe 4.

## Risiken

- **Funktionsversatz zwischen den Plattformen**, solange Windows fehlt. Gehört
  nach `OFFEN.md`.
- **Anbieter ohne Zeitstempel** machen `.srt` und Sprechertrennung unbrauchbar.
  Steht an der Vorlage.
- **Die Preistabelle ist eine Näherung aus fremder Quelle.** Beschriftung sagt es.
- **Vorlagen veralten.** Basis-URLs und Modell-IDs sind gepflegte Daten; der
  „Modelle laden"-Knopf und das freie Modellfeld sind die Notausgänge, wenn eine
  Vorlage hinterherhängt.
- **Der Ruf des Programms.** Das lokale Versprechen ist das Verkaufsargument.
  Deshalb: lokal bleibt Voreinstellung, kein automatischer Wechsel nach außen,
  und die README verkauft die Erweiterung über den Ollama-Fall statt über die
  Cloud.

## Tests

Weil `RemoteTextEngine` und `RemoteSpeechEngine` hinter demselben winzigen
Protokoll sitzen, kann `Tests/ShoutTests` eine Attrappen-Engine einsetzen und
prüfen, was heute schwer prüfbar ist:

- `FormattingGuard` greift bei einer plaudernden Cloud-Antwort.
- Bei Zeitüberschreitung kommt wirklich der Rohtext.
- Eine gescheiterte Fern-Transkription landet in der Warteschlange.
- Nach einem Backup-Import ohne Schlüssel steht der Schalter auf „lokal".
- `WAVEncoder`: Kopfdaten, 16 kHz, Mono, Länge.
- URL-Bau: Basis-URL mit und ohne `/v1`, mit und ohne Schrägstrich am Ende —
  der häufigste Tippfehler.

## Portierung Windows (späterer Schritt)

Der C#-Port hat dieselben zwei Schnittstellen (`Formatter`, `Transcriber` in
`windows/src/Shout/Core/`) und dieselben Aufrufstellen (`TrayContext`,
`FileTranscriptionQueue`). Der Vorlagen-Katalog ist Daten und wird gespiegelt;
statt der Keychain kommt DPAPI (`ProtectedData`) zum Einsatz. Der WAV-Weg ist
dort einfacher, weil die Aufnahme schon als WAV 16 kHz Mono vorliegt.
