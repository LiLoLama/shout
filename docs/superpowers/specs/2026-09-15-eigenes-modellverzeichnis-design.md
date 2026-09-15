# Eigenes Modellverzeichnis: Ablageort wählen und vorhandene Modelle mitbenutzen (macOS + Windows)

Stand: 2026-09-15 · Status: **Entwurf**, noch nicht umgesetzt.
Umsetzungsplan: `docs/superpowers/plans/2026-09-15-eigenes-modellverzeichnis.md`

## Ziel

shout. lädt seine Modelle selbst herunter und legt sie an einen festen Ort. Das
ist für den ersten Start richtig — man soll nichts einrichten müssen. Danach
erzeugt es zwei Ärgernisse:

1. **Dieselben Modelle mehrfach auf der Platte.** Wer LM Studio oder Ollama
   benutzt, hat Qwen längst liegen; shout. lädt es ein zweites Mal. Bei einem
   2-GB-GGUF und einem 1,6-GB-Whisper ist das kein Detail mehr.
   (Ausnahme, siehe unten: Am Mac teilt shout. sich den HF-Cache mit
   `huggingface-cli` bereits heute — dort besteht das Problem nur gegenüber
   LM Studio.)
2. **Kein Mitspracherecht beim Ort.** Auf einem Notebook mit 256 GB gehören
   mehrere Gigabyte Modelle auf die externe Platte, nicht auf das Systemlaufwerk.

Diese Erweiterung gibt beides: einen **wählbaren Basisordner**, in den shout.
herunterlädt, und **durchsuchbare Ordner**, aus denen es vorhandene Modelle
mitbenutzt, ohne sie zu kopieren.

Die Haltung des Programms bleibt unberührt: Es wird nichts von allein
durchsucht, nichts verschoben, und fremde Dateien werden nie gelöscht.

## Umfang

**Enthalten**

- Ein wählbarer **Basisordner** für alle vier lokalen Engines: Whisper und MLX am
  Mac, ggml und GGUF unter Windows. Vorgabe ist der heutige Ort — ohne Eingriff
  ändert sich für niemanden etwas.
- Eine Liste **durchsuchter Ordner**. Auf Auftrag durchsucht, Fundstücke werden
  in dieselbe Modellliste eingereiht wie eigene Downloads.
- Durchsucht wird dort, wo die Formate wirklich passen:
  - **Windows:** `*.gguf` und `ggml-*.bin`
  - **Mac (MLX):** Ordner mit `config.json` und `*.safetensors`, zusätzlich das
    HF-Cache-Muster `models--<org>--<repo>/snapshots/<hash>/`
- **Erkennung des Chat-Templates** aus dem GGUF-Kopf unter Windows, mit Zuordnung
  zu einer bekannten Modellfamilie (siehe „Das Chat-Template").
- Vier unterscheidbare Zustände je Modell, darunter ausdrücklich „nicht
  auffindbar".
- Eine Zeile im Onboarding, die auf die Modelle-Seite führt.

**Nicht enthalten**

- **iOS.** Kein geteiltes Dateisystem, Modelle leben im App-Container.
- **Fremde WhisperKit-Ordner am Mac.** Technisch möglich
  (`WhisperKitConfig.modelFolder`), aber das CoreML-Format von
  `argmaxinc/whisperkit-coreml` liegt praktisch bei niemandem von einem anderen
  Werkzeug herum. Der Basisordner für ASR ist enthalten, das Mitbenutzen nicht.
- **Dateien verschieben.** Ein Ordnerwechsel bewegt nichts (siehe „Ordnerwechsel").
- **Durchsuchen ohne Auftrag.** Kein Absuchen üblicher Orte beim Start.
- **Ollamas Blob-Ablage.** Dort liegen die Gewichte als sha256-benannte Blobs
  hinter Manifesten; das zu lesen ist ein eigener Leser und ein eigenes Projekt.
  Wer die Modelle mitbenutzen will, hat sie meist ohnehin auch als GGUF.
- **Jinja2 ausführen.** Siehe „Das Chat-Template".

## Aufbau

### `ModelStore` — eine Einheit je Plattform

Eine neue Einheit mit genau einer Aufgabe: **aus einer Modell-Kennung einen
konkreten Pfad machen.** Sie besitzt den Basisordner, die Liste der Suchordner,
das Durchsuchen und das Auflösen.

```
ModelStore
  basisordner        (Einstellung, Vorgabe = heutiger Ort)
  suchordner: [Pfad] (Einstellung, geordnet)
  durchsuchen(Pfad, abbruch) -> [Fund]
  aufloesen(Kennung) -> Pfad?
  zustand(Kennung)   -> nichtVorhanden | eigen | fremd(Pfad) | nichtAuffindbar
```

Sie **lädt nichts herunter und löscht nichts**. Sie beantwortet Fragen. Dadurch
ist sie vollständig gegen einen Ordner mit leeren Attrappen-Dateien prüfbar —
die Testsuite bleibt ohne WhisperKit und MLX unter einer Sekunde.

Das ist dieselbe Bewegung wie beim Anbieter-Umbau, eine Ebene tiefer: Die Engines
hören auf, über Ablageorte Bescheid zu wissen.

### Anschluss am Mac

`MLXLMCommon` hat ein öffentliches Protokoll `Downloader` mit einer einzigen
Methode, die ein lokales Verzeichnis zurückgibt
(`Libraries/MLXLMCommon/Downloader.swift`). shout. setzt es selbst um:

```
ShoutDownloader.download(id:…) -> URL
    store.aufloesen(id)  →  Treffer: dieses Verzeichnis zurückgeben
                         →  kein Treffer: an HubClient weiterreichen
```

Dadurch hängen „vorhandenes Modell mitbenutzen" und „woanders hin herunterladen"
an **derselben** Stelle statt an zweien.

Das bequeme Makro `#huggingFaceLoadModelContainer(configuration:)` in
`Sources/FlowLokal/LocalTextEngine.swift:59` nimmt den Standard-Hub und lässt
sich nicht umlenken. Es wechselt auf die ausgeschriebene Form:

```swift
try await loadModelContainer(from: ShoutDownloader(store),
                             using: #huggingFaceTokenizerLoader(),
                             configuration: cfg) { progress in … }
```

Kein Verhaltensunterschied, aber eine echte Änderung an der Ladestelle.

Der Ablageort für eigene Downloads kommt über
`HubClient(cache: HubCache(cacheDirectory:))`.

**Die Vorgabe muss der aufgelöste heutige Ort sein, kein fest geschriebener
Pfad.** Der Standard-Cache wird über `CacheLocationProvider.environment`
ermittelt (`Sources/HuggingFace/Shared/CacheLocationProvider.swift:160`) und
achtet dabei in dieser Reihenfolge auf `HF_HUB_CACHE`, `HF_HOME` und erst dann
auf `~/.cache/huggingface/hub`. Wer `HF_HOME` gesetzt hat, bekäme mit einem fest
geschriebenen Pfad **sämtliche Modelle erneut heruntergeladen**. Die Vorgabe des
Basisordners ist deshalb das, was der Provider zum Zeitpunkt der Umstellung
liefert — übernommen, nicht nachgebaut.

### Was am Mac heute schon gilt (und den Nutzen verschiebt)

Beim Nachsehen zeigte sich: shout. legt seine MLX-Modelle **bereits** unter
`~/.cache/huggingface/hub` ab, im Python-Format `<kind>--<namespace>--<repo>`
(`Sources/HuggingFace/Hub/HubCache.swift:107`) — also genau dort, wo auch
`huggingface-cli` und `python -m huggingface_hub` ablegen.

Für diese Kombination ist das Doppel-Problem am Mac also **heute schon gelöst**,
nur weiß es niemand. Der verbleibende Gewinn am Mac ist damit ehrlicher
benannt:

1. **Verlegen** des Basisordners auf eine externe Platte — der Hauptgrund.
2. **LM Studio**, das unter `~/.lmstudio/models/<org>/<repo>/` eine **andere**
   Struktur benutzt als der HF-Cache und deshalb einen Suchordner braucht.
3. **Sichtbarkeit** — die Modelle-Seite zeigt künftig, wo etwas liegt.

Unter Windows bleibt der Nutzen unverändert groß, weil dort ein eigener,
flacher Ordner benutzt wird und `ggml`/GGUF mit fremden Werkzeugen geteilt
werden können.

Für ASR genügen die vorhandenen Felder von `WhisperKitConfig`: `downloadBase`
für den Ablageort (`modelFolder` bleibt dem iOS-Zweig vorbehalten).

### Anschluss unter Windows

`ModelCatalog.PathFor` und `ModelCatalog.IsDownloaded`
(`windows/src/Shout/Core/ModelCatalog.cs:88`) sind heute schon der einzige
Engpass. Sie fragen künftig den `ModelStore`, statt selbst `Path.Combine` auf
`StoreIO.ModelDirectory` zu rechnen.

## Verhalten

### Auflösung

Feste Reihenfolge, erster Treffer gewinnt:

1. Basisordner
2. Suchordner in ihrer Reihenfolge

Keine Heuristik, keine „beste" Wahl. Bei Namensgleichheit entscheidet die
Position, und die ist in der Oberfläche sichtbar und verschiebbar. Ist der
Basisordner zugleich als Suchordner eingetragen, erscheint jedes Modell trotzdem
nur einmal.

### Durchsuchen

Nur auf Auftrag, nie von allein, nie auf einem Pfad, den niemand genannt hat.
Mit Fortschritt und Abbruch.

**Grenzen: sechs Ebenen tief, höchstens 50 000 besuchte Einträge.** Wer
versehentlich auf `C:\` oder `/` zeigt, bekommt nach dem Anschlagen der Grenze
eine Meldung, dass der Ordner zu groß ist, samt der bis dahin gefundenen
Modelle — kein stiller Abbruch und kein minutenlanges Warten. Sechs Ebenen
decken alle Ablagen ab, die wir kennen: `~/.lmstudio/models/<org>/<repo>/` (3),
der HF-Cache mit `models--org--repo/snapshots/<hash>/` (3) und ein flacher
Windows-Ordner (1).

Ein **Fund** trägt: Kennung, Pfad, Größe und — unter Windows bei GGUF — die
erkannte Modellfamilie.

Die Kennung ist unter Windows der Dateiname, am Mac `<org>/<repo>` aus der
Ordnerstruktur, hilfsweise der Ordnername.

### Zustände

Vier, und sie müssen in der Oberfläche unterscheidbar sein:

| Zustand | Bedeutung |
|---|---|
| nicht vorhanden | herunterladbar, wie heute |
| eigen | liegt im Basisordner, von shout. geladen |
| fremd | liegt in einem Suchordner, mit sichtbarem Pfad |
| **nicht auffindbar** | war verlinkt, Datei ist weg |

### Löschen — die wichtigste Regel

Bei einem **eigenen** Modell heißt der Knopf „Löschen" und löscht die Datei, wie
heute. Bei einem **fremden** heißt er „Aus der Liste entfernen" und fasst die
Datei nicht an. shout. darf niemandem sein LM Studio ausräumen.

### Ordnerwechsel

Wer den Basisordner umstellt, löst **keinen Umzug** aus. Der bisherige Ordner
rutscht automatisch an die erste Stelle der Suchordner. Nichts wird kopiert,
nichts verschwindet, neue Downloads landen am neuen Ort. Ein Umzug über
Laufwerksgrenzen dauert Minuten, kann abbrechen und bräuchte Fortschritt,
Abbruch und einen Aufräumweg — für einen Gewinn, der nur „ordentlicher aussieht".

### Wenn ein Modell im Betrieb fehlt

Externe Platte nicht gesteckt, Modell im fremden Ordner gelöscht: Es wird
**nicht** still nachgeladen. Der Weg dafür existiert bereits —
`LocalSpeechEngine(allowDownload: false)` wirft, der Aufrufer nimmt den anderen
Zweig (`Sources/FlowLokal/LocalSpeechEngine.swift:29`). Daran hängen wir uns,
mit einer Meldung, die den erwarteten Pfad nennt.

Mitten im Diktat einen Multi-GB-Download anzustoßen, weil ein Ordner fehlt, wäre
die schlechteste denkbare Reaktion.

## Das Chat-Template

Unter Windows steht das Chat-Template heute **fest verdrahtet** auf ChatML
(`windows/src/Shout/Core/Engines/LocalTextEngine.cs:93`). Der Katalog enthält
deshalb bewusst nur Qwen-2.5-Instruct. Ein gefundenes GGUF aus der Llama-,
Gemma- oder Mistral-Familie würde keinen Fehler werfen, sondern **still
schlechteren Text** liefern — die schlimmste Fehlerart.

Das Template steckt als `tokenizer.chat_template` im GGUF-Kopf. Es zu lesen ist
leicht. Es **auszuführen** hieße, einen Jinja2-Interpreter in C# zu haben — ein
eigenes Projekt, in keinem Verhältnis zum Zweck.

**Deshalb: erkennen statt ausführen.**

1. `GgufHeader` liest nur den Dateikopf (Magic, Version, Metadaten-Paare) und
   zieht `tokenizer.chat_template` heraus. Die Gewichte werden nicht angefasst.
2. Das Template wird gegen eine Handvoll Fingerabdrücke gehalten: ChatML,
   Llama 3, Gemma, Mistral, Phi.
3. Trifft einer, greift ein von Hand geschriebener Zusammenbau für diese Familie.
4. Trifft keiner, wird das Modell **angeboten, aber sichtbar als ungeprüft
   gekennzeichnet**; ChatML bleibt der Rückfall wie heute.

Das ist wenig Code, deckt die realen Fälle ab und verwandelt „still schlechterer
Text" in „sichtbar unsicher". Die Katalog-Modelle verhalten sich unverändert.

Nebenbei entschärft das ein Risiko, das heute schon besteht: Über die
HF-Suche landen bereits beliebige GGUF in `Settings.Shared.DiscoveredLlmModels`,
ohne dass jemand das Template prüft.

## Oberfläche

**Ort ist die Modelle-Seite** (`Sources/FlowLokal/ModelsView.swift`,
`windows/src/Shout/UI/ModelsPage.cs`). Ein neuer Abschnitt, unterhalb der
Modellliste:

- **Basisordner** — Pfad, Knopf „Ändern", darunter der belegte Platz.
- **Durchsuchte Ordner** — Liste mit Pfad und Trefferzahl, Knöpfe „Ordner
  hinzufügen", „Erneut durchsuchen", „Entfernen". Reihenfolge verschiebbar,
  weil sie den Vorrang bestimmt.

In der Modellliste bekommt jedes fremde Modell seinen Pfad als Unterzeile und
ein Abzeichen, das es von eigenen unterscheidet. „Nicht auffindbar" ist
deutlich ausgezeichnet, nicht nur ausgegraut.

**Im Onboarding** eine unaufdringliche Zeile, kein eigener Schritt: „Schon
Modelle auf dem Rechner? → Ordner wählen", die auf die Modelle-Seite führt. Der
Schmerz entsteht beim ersten Start, aber niemand wird durch einen Extraschritt
aufgehalten.

Eine Einschränkung, die sichtbar sein muss: Der Modell-Empfehler nach
Arbeitsspeicher (`ModelCatalog.RecommendedAsr`, `RecommendedLlm`) greift bei
einem selbst gewählten Modell nicht. Wer ein 14B-Modell einbindet, bekommt einen
Hinweis auf die zu erwartende Wartezeit statt schweigender Enttäuschung.

## Sicherheit und Berechtigungen

Die Mac-App läuft **ohne App-Sandbox** (`Release/shout.entitlements` — nötig für
Accessibility und globale Hotkeys). Fremde Pfade funktionieren damit ohne
Security-Scoped Bookmarks. Der iOS-Weg mit
`startAccessingSecurityScopedResource` wird hier nicht gebraucht, weil iOS nicht
enthalten ist.

## Prüfungen

Alles gegen Attrappen, kein echtes Modell nötig:

- Auflösungsreihenfolge; Vorrang des Basisordners
- Basisordner zugleich als Suchordner → keine Doppelung
- Ordnerwechsel macht den alten Ordner zum ersten Suchordner
- Fund verschwindet → Zustand „nicht auffindbar", **kein** Download
- Durchsuchen: findet Passendes, ignoriert Fremdes, hält die Tiefengrenze,
  lässt sich abbrechen
- `GgufHeader`: Template gelesen, Template fehlt, Datei abgeschnitten, Magic
  falsch
- Familienerkennung je Fingerabdruck, und der Rückfall bei Unbekanntem
- **Ein fremdes Modell entfernen löscht die Datei nicht** — die eine Prüfung,
  die wirklich zählt
- Mac: `ShoutDownloader` fragt erst den Store und reicht nur bei Fehlschlag weiter
- **Ohne Einstellung zeigt der Basisordner auf denselben Ort wie vor der
  Umstellung** — geprüft auch mit gesetztem `HF_HOME` bzw. `HF_HUB_CACHE`. Diese
  Prüfung ist der Wächter gegen einen unbeabsichtigten Neu-Download bei allen
  bestehenden Installationen.
- Tiefen- und Anzahlgrenze greifen und liefern das bis dahin Gefundene mit

## Offene Punkte für die Umsetzung

- Die Fingerabdrücke der Modellfamilien entstehen aus echten GGUF-Dateien, nicht
  aus dem Gedächtnis — sie gehören beim Bauen einzeln belegt.
- Ob LM Studio am Mac tatsächlich `~/.lmstudio/models/<org>/<repo>/` benutzt, ist
  aus der Dokumentation übernommen und beim Bauen an einer echten Installation
  zu bestätigen. Trifft es nicht zu, ändert das nur die Beispielpfade, nicht den
  Aufbau.
