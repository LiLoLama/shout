# Eigenes Modellverzeichnis (macOS) — Umsetzungsplan

> **Für agentische Ausführung:** ERFORDERLICHER UNTER-SKILL: `superpowers:subagent-driven-development` (empfohlen) oder `superpowers:executing-plans`, Aufgabe für Aufgabe. Die Schritte nutzen Checkbox-Syntax (`- [ ]`).

Entwurf: `docs/superpowers/specs/2026-09-15-eigenes-modellverzeichnis-design.md`
Dies ist **Plan 1 von 2**. Der Windows-Teil (`ModelStore.cs`, `GgufHeader.cs`,
Familienerkennung) ist ein eigener Plan und teilt mit diesem keine Codezeile.

**Ziel:** Der Ablageort der lokalen Modelle wird wählbar, und Modelle aus
fremden Ordnern (vor allem LM Studio) werden mitbenutzt statt ein zweites Mal
heruntergeladen.

**Architektur:** Eine neue, abhängigkeitsfreie Einheit `ModelStore` beantwortet
genau eine Frage — welcher Pfad gehört zu welcher Modell-Kennung. Die Engines
hören auf, Ablageorte zu kennen. Am MLX-Ladeweg hängt sich shout. über das
öffentliche `Downloader`-Protokoll von `MLXLMCommon` ein; bei WhisperKit genügt
das vorhandene Feld `downloadBase`.

**Technik:** Swift 5.10, XCTest, XcodeGen. Pakete: `mlx-swift-lm`
(`MLXLMCommon`, `MLXHuggingFace`), `swift-huggingface` (`HubClient`, `HubCache`),
`argmax-oss-swift` (`WhisperKit`).

## Globale Vorgaben

- **Umlaute immer als echtes UTF-8** — `ä ö ü Ä Ö Ü ß`, nie `ae`/`oe`/`ue`/`ss`.
- **Code, Kommentare, Commits und Oberfläche auf Deutsch**, wie im ganzen Projekt.
- **Oberflächentexte gehen durch `Loc.t("deutscher Text")`** und brauchen einen
  Eintrag in `Localization.english` (`Sources/FlowLokal/Localization.swift:78`).
  Zwei Fallen: Ein **doppelter Schlüssel im Wörterbuch-Literal stürzt zur
  Laufzeit ab**, und ein **falsches Anführungs- oder Auslassungszeichen** lässt
  die Suche stillschweigend ins Deutsche zurückfallen. Typografische
  Anführungszeichen („…") im Schlüssel müssen im englischen Eintrag exakt
  gleich geschrieben sein.
- **Jede neue Datei aus `Sources/FlowLokal/`, die getestet wird, muss einzeln in
  die Quellenliste des Testziels** in `project.yml:330` eingetragen werden. Das
  Testziel listet Dateien einzeln auf, es zieht den Ordner nicht als Ganzes.
- **Nach jeder Änderung an `project.yml` erst `xcodegen generate`**, sonst kennt
  das Projekt die neue Datei nicht.
- **`ModelStore` darf nichts herunterladen und nichts löschen.** Er beantwortet
  Fragen. Alles andere gehört nicht hinein.
- **Die App wird nicht als Debug-Build gestartet.** Geprüft wird über die Tests;
  sichtbare Änderungen gehen über ein echtes Release.
- Testbefehl überall:
  ```bash
  cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
  ```

---

## Dateiaufteilung

| Datei | Verantwortung |
|---|---|
| `Sources/FlowLokal/ModelStore.swift` (neu) | Kennung → Pfad. Basisordner, Suchordner, Auflösung, Zustand. Abhängigkeitsfrei. |
| `Sources/FlowLokal/ModelScan.swift` (neu) | Einen Ordner durchsuchen und Funde melden. Getrennt von `ModelStore`, weil Dateisystem-Durchlauf und Auflösungsregeln nichts miteinander zu tun haben. |
| `Sources/FlowLokal/ModelPaths.swift` (neu) | Einstellungen: Basisordner und Suchordner lesen/schreiben, Vorgabe auflösen, Ordnerwechsel behandeln. Trennt Persistenz von Logik. |
| `Sources/FlowLokal/ShoutDownloader.swift` (neu) | Umsetzung von `MLXLMCommon.Downloader`: erst Store fragen, dann `HubClient`. |
| `Sources/FlowLokal/LocalTextEngine.swift` (ändern, Z. 59) | Makro → ausgeschriebenes `loadModelContainer`. |
| `Sources/FlowLokal/LocalSpeechEngine.swift` (ändern, Z. 53–71) | `downloadBase` an `WhisperKitConfig` durchreichen. |
| `Sources/FlowLokal/ModelsView.swift` (ändern) | Abschnitt für Basisordner und Suchordner, Zustände je Modell, Löschen-Regel. |
| `Tests/ShoutTests/ModelStoreTests.swift` (neu) | Auflösung, Vorrang, Zustände. |
| `Tests/ShoutTests/ModelScanTests.swift` (neu) | Durchsuchen, Muster, Grenzen, Abbruch. |
| `Tests/ShoutTests/ModelPathsTests.swift` (neu) | Vorgabe, Ordnerwechsel, Persistenz. |
| `project.yml` (ändern, Z. 330) | Neue Dateien ins Testziel. |

---

### Aufgabe 1: `ModelStore` — Auflösung mit Vorrang

**Dateien:**
- Neu: `Sources/FlowLokal/ModelStore.swift`
- Neu: `Tests/ShoutTests/ModelStoreTests.swift`
- Ändern: `project.yml:330` (Quellenliste Testziel)

**Schnittstellen:**
- Benutzt: nichts (abhängigkeitsfrei, nur `Foundation`)
- Liefert:
  - `struct ModelStore { init(basisordner: URL, suchordner: [URL]); func aufloesen(_ kennung: String) -> URL? }`
  - `ModelStore.ordnername(fuer kennung: String) -> String`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/ModelStoreTests.swift`:

```swift
import XCTest

final class ModelStoreTests: XCTestCase {

    private var wurzel: URL!
    private var basis: URL!
    private var fremd: URL!

    override func setUpWithError() throws {
        wurzel = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-modelstore-\(UUID().uuidString)", isDirectory: true)
        basis = wurzel.appendingPathComponent("basis", isDirectory: true)
        fremd = wurzel.appendingPathComponent("fremd", isDirectory: true)
        for ordner in [basis!, fremd!] {
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wurzel)
    }

    /// Legt ein MLX-Modell als Attrappe an: Ordner mit config.json und Gewichten.
    /// Der Inhalt ist gleichgültig — der Store prüft Struktur, nicht Inhalt.
    private func legeMLXAn(in ordner: URL, kennung: String) throws -> URL {
        let ziel = ordner.appendingPathComponent(
            ModelStore.ordnername(fuer: kennung), isDirectory: true)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: ziel.appendingPathComponent("config.json"))
        try Data().write(to: ziel.appendingPathComponent("model.safetensors"))
        return ziel
    }

    /// Nichts vorhanden heißt: kein Pfad. Nicht etwa der erwartete Pfad,
    /// den es noch nicht gibt — sonst hielte der Aufrufer ihn für gültig.
    func testOhneModellKeinPfad() {
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertNil(store.aufloesen("mlx-community/Qwen3-4B-4bit"))
    }

    func testFindetModellImBasisordner() throws {
        let erwartet = try legeMLXAn(in: basis, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [])
        XCTAssertEqual(store.aufloesen("mlx-community/Qwen3-4B-4bit"), erwartet)
    }

    func testFindetModellImSuchordner() throws {
        let erwartet = try legeMLXAn(in: fremd, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.aufloesen("mlx-community/Qwen3-4B-4bit"), erwartet)
    }

    /// Der Vorrang ist die Kernregel: Liegt dasselbe Modell doppelt, gewinnt
    /// der Basisordner. Sonst wäre nicht vorhersagbar, was geladen wird.
    func testBasisordnerSchlaegtSuchordner() throws {
        let imBasis = try legeMLXAn(in: basis, kennung: "mlx-community/Qwen3-4B-4bit")
        _ = try legeMLXAn(in: fremd, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.aufloesen("mlx-community/Qwen3-4B-4bit"), imBasis)
    }

    /// Ein Ordner ohne Gewichte ist kein Modell, auch wenn er richtig heißt.
    /// Ein abgebrochener Download darf nicht als fertiges Modell gelten.
    func testOrdnerOhneGewichteZaehltNicht() throws {
        let leer = basis.appendingPathComponent(
            ModelStore.ordnername(fuer: "mlx-community/Qwen3-4B-4bit"),
            isDirectory: true)
        try FileManager.default.createDirectory(at: leer, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: leer.appendingPathComponent("config.json"))
        let store = ModelStore(basisordner: basis, suchordner: [])
        XCTAssertNil(store.aufloesen("mlx-community/Qwen3-4B-4bit"))
    }

    /// Der HF-Cache benutzt das Python-Format models--org--repo.
    func testOrdnernameFolgtDemHFFormat() {
        XCTAssertEqual(
            ModelStore.ordnername(fuer: "mlx-community/Qwen3-4B-4bit"),
            "models--mlx-community--Qwen3-4B-4bit")
    }
}
```

- [ ] **Schritt 2: Test laufen lassen, Fehlschlag bestätigen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: Übersetzungsfehler, `cannot find 'ModelStore' in scope`.

- [ ] **Schritt 3: `ModelStore.swift` anlegen**

`Sources/FlowLokal/ModelStore.swift`:

```swift
import Foundation

/// Beantwortet genau eine Frage: **Welcher Pfad gehört zu welcher Kennung?**
///
/// Lädt nichts herunter und löscht nichts — dadurch ist er vollständig gegen
/// einen Ordner mit Attrappen prüfbar, ohne WhisperKit oder MLX zu berühren.
///
/// Die Reihenfolge ist fest: erst der Basisordner, dann die Suchordner in ihrer
/// Reihenfolge, erster Treffer gewinnt. Keine Heuristik — bei Namensgleichheit
/// muss vorhersagbar sein, was geladen wird, und die Reihenfolge ist in der
/// Oberfläche sichtbar.
struct ModelStore {

    let basisordner: URL
    let suchordner: [URL]

    init(basisordner: URL, suchordner: [URL]) {
        self.basisordner = basisordner
        self.suchordner = suchordner
    }

    /// Alle Orte in Vorrangreihenfolge. Doppelte Einträge fallen heraus —
    /// wer den Basisordner zusätzlich als Suchordner einträgt, soll jedes
    /// Modell trotzdem nur einmal sehen.
    var orteInReihenfolge: [URL] {
        var gesehen = Set<String>()
        return ([basisordner] + suchordner).filter { ordner in
            gesehen.insert(ordner.standardizedFileURL.path).inserted
        }
    }

    /// Ordnername im Python-Format des Hugging-Face-Caches
    /// (`models--<org>--<repo>`) — so legt `HubCache` ab, und so sieht
    /// `~/.cache/huggingface/hub` aus.
    static func ordnername(fuer kennung: String) -> String {
        let teile = kennung.split(separator: "/").map(String.init)
        return (["models"] + teile).joined(separator: "--")
    }

    func aufloesen(_ kennung: String) -> URL? {
        let name = Self.ordnername(fuer: kennung)
        for ort in orteInReihenfolge {
            let kandidat = ort.appendingPathComponent(name, isDirectory: true)
            if Self.istVollstaendig(kandidat) { return kandidat }
        }
        return nil
    }

    /// Ein Ordner zählt erst als Modell, wenn die Gewichte da sind. Ein
    /// abgebrochener Download hinterlässt sonst eine Hülle, die wie ein
    /// fertiges Modell aussieht und erst beim Laden auffliegt.
    static func istVollstaendig(_ ordner: URL) -> Bool {
        let fm = FileManager.default
        var istOrdner: ObjCBool = false
        guard fm.fileExists(atPath: ordner.path, isDirectory: &istOrdner),
              istOrdner.boolValue,
              let inhalt = try? fm.contentsOfDirectory(atPath: ordner.path)
        else { return false }
        return inhalt.contains("config.json")
            && inhalt.contains(where: { $0.hasSuffix(".safetensors") })
    }
}
```

- [ ] **Schritt 4: Datei ins Testziel eintragen**

In `project.yml`, in der Quellenliste von `ShoutTests` (nach `- path: Sources/FlowLokal/StoreIO.swift`, Zeile 366) ergänzen:

```yaml
      # Modellverzeichnis: abhängigkeitsfrei, ohne MLX-/WhisperKit-Bezug.
      - path: Sources/FlowLokal/ModelStore.swift
```

Dann:

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodegen generate
```

Erwartet: `Created project at .../FlowLokal.xcodeproj`

- [ ] **Schritt 5: Tests laufen lassen, Erfolg bestätigen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `** TEST SUCCEEDED **`, die sechs neuen Tests laufen durch.

- [ ] **Schritt 6: Committen**

```bash
git add Sources/FlowLokal/ModelStore.swift Tests/ShoutTests/ModelStoreTests.swift project.yml
git commit -m "ModelStore: Kennung zu Pfad auflösen, Basisordner hat Vorrang"
```

---

### Aufgabe 2: Zustände — und „nicht auffindbar"

**Dateien:**
- Ändern: `Sources/FlowLokal/ModelStore.swift`
- Ändern: `Tests/ShoutTests/ModelStoreTests.swift`

**Schnittstellen:**
- Benutzt: `ModelStore` aus Aufgabe 1
- Liefert: `enum ModelZustand: Equatable { case nichtVorhanden, eigen(URL), fremd(URL), nichtAuffindbar }`
  und `ModelStore.zustand(_ kennung: String, verknuepft: URL?) -> ModelZustand`

Der Parameter `verknuepft` ist der zuletzt bekannte Pfad aus den Einstellungen.
Ist er gesetzt, das Modell aber nirgends mehr auffindbar, lautet der Zustand
`nichtAuffindbar` — und **nicht** `nichtVorhanden`. Der Unterschied entscheidet
darüber, ob die Oberfläche einen Download anbietet oder erklärt, dass eine Platte
fehlt.

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

An `ModelStoreTests.swift` anhängen (vor der schließenden Klammer):

```swift
    func testZustandNichtVorhandenOhneVerknuepfung() {
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: nil),
                       .nichtVorhanden)
    }

    func testZustandEigenImBasisordner() throws {
        let pfad = try legeMLXAn(in: basis, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: nil),
                       .eigen(pfad))
    }

    func testZustandFremdImSuchordner() throws {
        let pfad = try legeMLXAn(in: fremd, kennung: "mlx-community/Qwen3-4B-4bit")
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: nil),
                       .fremd(pfad))
    }

    /// Der wichtigste Zustand: Es war einmal da, jetzt ist es weg. Das darf
    /// NICHT als "nicht vorhanden" durchgehen, sonst bietet die Oberfläche
    /// einen Download an, obwohl bloß eine Platte nicht steckt.
    func testZustandNichtAuffindbarWennVerknuepftUndWeg() {
        let weg = fremd.appendingPathComponent("models--mlx-community--Qwen3-4B-4bit",
                                               isDirectory: true)
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: weg),
                       .nichtAuffindbar)
    }

    /// Eine alte Verknüpfung darf einen echten Fund nicht überstimmen: Wer das
    /// Modell inzwischen in den Basisordner geladen hat, sieht "eigen".
    func testFundSchlaegtAlteVerknuepfung() throws {
        let pfad = try legeMLXAn(in: basis, kennung: "mlx-community/Qwen3-4B-4bit")
        let alt = fremd.appendingPathComponent("models--mlx-community--Qwen3-4B-4bit",
                                               isDirectory: true)
        let store = ModelStore(basisordner: basis, suchordner: [fremd])
        XCTAssertEqual(store.zustand("mlx-community/Qwen3-4B-4bit", verknuepft: alt),
                       .eigen(pfad))
    }
```

- [ ] **Schritt 2: Test laufen lassen, Fehlschlag bestätigen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `cannot find 'ModelZustand' in scope` bzw. `value of type 'ModelStore' has no member 'zustand'`.

- [ ] **Schritt 3: Zustände umsetzen**

In `Sources/FlowLokal/ModelStore.swift` vor `struct ModelStore` einfügen:

```swift
/// Wo ein Modell steht — und ob es überhaupt noch da ist.
///
/// `nichtAuffindbar` ist der Zustand, der diese Erweiterung überhaupt
/// rechtfertigt: Ein verknüpftes Modell aus einem fremden Ordner kann
/// verschwinden, ohne dass shout. etwas dafür kann (Platte ab, Ordner
/// aufgeräumt). Das ist etwas anderes als "nie da gewesen", und die Oberfläche
/// muss es anders beantworten.
enum ModelZustand: Equatable {
    case nichtVorhanden
    case eigen(URL)
    case fremd(URL)
    case nichtAuffindbar
}
```

Und innerhalb von `struct ModelStore`, nach `aufloesen`:

```swift
    func zustand(_ kennung: String, verknuepft: URL?) -> ModelZustand {
        // Ein echter Fund schlägt jede gespeicherte Verknüpfung: Wer das Modell
        // inzwischen selbst geladen hat, soll nicht auf einen toten Pfad starren.
        if let gefunden = aufloesen(kennung) {
            let imBasis = gefunden.standardizedFileURL.path
                .hasPrefix(basisordner.standardizedFileURL.path)
            return imBasis ? .eigen(gefunden) : .fremd(gefunden)
        }
        return verknuepft == nil ? .nichtVorhanden : .nichtAuffindbar
    }
```

- [ ] **Schritt 4: Tests laufen lassen, Erfolg bestätigen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `** TEST SUCCEEDED **`, jetzt elf Tests in `ModelStoreTests`.

- [ ] **Schritt 5: Committen**

```bash
git add Sources/FlowLokal/ModelStore.swift Tests/ShoutTests/ModelStoreTests.swift
git commit -m "ModelStore: vier Zustände, 'nicht auffindbar' getrennt von 'nicht vorhanden'"
```

---

### Aufgabe 3: Ordner durchsuchen

**Dateien:**
- Neu: `Sources/FlowLokal/ModelScan.swift`
- Neu: `Tests/ShoutTests/ModelScanTests.swift`
- Ändern: `project.yml` (Quellenliste Testziel)

**Schnittstellen:**
- Benutzt: `ModelStore.istVollstaendig` aus Aufgabe 1
- Liefert:
  - `struct ModelFund: Equatable { let kennung: String; let pfad: URL; let groesseBytes: Int64 }`
  - `enum ModelScan { static func durchsuchen(_ wurzel: URL, maxTiefe: Int = 6, maxEintraege: Int = 50_000, abbruch: () -> Bool = { false }) -> (funde: [ModelFund], grenzeErreicht: Bool) }`

Grenzen laut Entwurf: **sechs Ebenen, höchstens 50 000 besuchte Einträge.** Wird
eine Grenze erreicht, werden die bis dahin gefundenen Modelle **mitgeliefert**
und `grenzeErreicht` ist `true` — kein stiller Abbruch.

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/ModelScanTests.swift`:

```swift
import XCTest

final class ModelScanTests: XCTestCase {

    private var wurzel: URL!

    override func setUpWithError() throws {
        wurzel = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-modelscan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: wurzel, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wurzel)
    }

    /// Legt ein vollständiges MLX-Modell unter einem beliebigen Unterpfad an.
    @discardableResult
    private func legeMLXAn(unter pfad: String, gewichtBytes: Int = 16) throws -> URL {
        let ziel = wurzel.appendingPathComponent(pfad, isDirectory: true)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: ziel.appendingPathComponent("config.json"))
        try Data(repeating: 0, count: gewichtBytes)
            .write(to: ziel.appendingPathComponent("model.safetensors"))
        return ziel
    }

    /// Das HF-Cache-Muster: models--org--repo/snapshots/<hash>/
    func testFindetModellImHFCacheMuster() throws {
        let ziel = try legeMLXAn(
            unter: "models--mlx-community--Qwen3-4B-4bit/snapshots/abc123")
        let ergebnis = ModelScan.durchsuchen(wurzel)
        XCTAssertEqual(ergebnis.funde.count, 1)
        XCTAssertEqual(ergebnis.funde.first?.kennung, "mlx-community/Qwen3-4B-4bit")
        XCTAssertEqual(ergebnis.funde.first?.pfad, ziel)
        XCTAssertFalse(ergebnis.grenzeErreicht)
    }

    /// Das LM-Studio-Muster: <org>/<repo>/
    func testFindetModellImLMStudioMuster() throws {
        try legeMLXAn(unter: "mlx-community/Qwen3-4B-4bit")
        let ergebnis = ModelScan.durchsuchen(wurzel)
        XCTAssertEqual(ergebnis.funde.count, 1)
        XCTAssertEqual(ergebnis.funde.first?.kennung, "mlx-community/Qwen3-4B-4bit")
    }

    /// Ordner ohne Gewichte sind keine Funde — ein abgebrochener Download
    /// darf nicht in der Liste auftauchen.
    func testIgnoriertUnvollstaendigeOrdner() throws {
        let halb = wurzel.appendingPathComponent("mlx-community/Halbfertig", isDirectory: true)
        try FileManager.default.createDirectory(at: halb, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: halb.appendingPathComponent("config.json"))
        let ergebnis = ModelScan.durchsuchen(wurzel)
        XCTAssertTrue(ergebnis.funde.isEmpty)
    }

    func testMeldetGroesseDerGewichte() throws {
        try legeMLXAn(unter: "mlx-community/Qwen3-4B-4bit", gewichtBytes: 4096)
        let ergebnis = ModelScan.durchsuchen(wurzel)
        XCTAssertEqual(ergebnis.funde.first?.groesseBytes, 4096)
    }

    /// Jenseits der Tiefengrenze wird nicht mehr gesucht, und das Ergebnis
    /// sagt es. Wer auf / zeigt, soll eine Meldung bekommen statt zu warten.
    func testTiefengrenzeGreiftUndWirdGemeldet() throws {
        try legeMLXAn(unter: "a/b/c/d/e/f/g/h/mlx-community/Tief")
        let ergebnis = ModelScan.durchsuchen(wurzel, maxTiefe: 3)
        XCTAssertTrue(ergebnis.funde.isEmpty)
        XCTAssertTrue(ergebnis.grenzeErreicht)
    }

    /// Bereits Gefundenes geht beim Anschlagen der Grenze nicht verloren.
    func testGefundenesUeberlebtDieGrenze() throws {
        try legeMLXAn(unter: "mlx-community/Flach")
        try legeMLXAn(unter: "a/b/c/d/e/f/g/h/mlx-community/Tief")
        let ergebnis = ModelScan.durchsuchen(wurzel, maxTiefe: 3)
        XCTAssertEqual(ergebnis.funde.map(\.kennung), ["mlx-community/Flach"])
        XCTAssertTrue(ergebnis.grenzeErreicht)
    }

    /// Abbruch von außen: Der Durchlauf hört auf und meldet die Grenze.
    func testAbbruchStopptDenDurchlauf() throws {
        try legeMLXAn(unter: "mlx-community/Eins")
        let ergebnis = ModelScan.durchsuchen(wurzel, abbruch: { true })
        XCTAssertTrue(ergebnis.funde.isEmpty)
        XCTAssertTrue(ergebnis.grenzeErreicht)
    }

    func testLeererOrdnerLiefertNichts() {
        let ergebnis = ModelScan.durchsuchen(wurzel)
        XCTAssertTrue(ergebnis.funde.isEmpty)
        XCTAssertFalse(ergebnis.grenzeErreicht)
    }
}
```

- [ ] **Schritt 2: Test laufen lassen, Fehlschlag bestätigen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `cannot find 'ModelScan' in scope`.

- [ ] **Schritt 3: `ModelScan.swift` anlegen**

`Sources/FlowLokal/ModelScan.swift`:

```swift
import Foundation

/// Ein gefundenes Modell in einem durchsuchten Ordner.
struct ModelFund: Equatable {
    let kennung: String
    let pfad: URL
    let groesseBytes: Int64
}

/// Durchsucht einen Ordner nach Modellen.
///
/// Bewusst getrennt von `ModelStore`: Dateisystem-Durchlauf und
/// Auflösungsregeln haben nichts miteinander zu tun, und nur so bleiben beide
/// für sich prüfbar.
///
/// Es wird **nur auf Auftrag** durchsucht, nie von allein und nie auf einem
/// Pfad, den niemand genannt hat.
enum ModelScan {

    /// Sechs Ebenen decken alle bekannten Ablagen ab:
    /// `~/.lmstudio/models/<org>/<repo>/` (3), der HF-Cache mit
    /// `models--org--repo/snapshots/<hash>/` (3), flache Ordner (1).
    static let standardTiefe = 6
    static let standardEintraege = 50_000

    static func durchsuchen(_ wurzel: URL,
                            maxTiefe: Int = standardTiefe,
                            maxEintraege: Int = standardEintraege,
                            abbruch: () -> Bool = { false })
        -> (funde: [ModelFund], grenzeErreicht: Bool) {

        var funde: [ModelFund] = []
        var grenzeErreicht = false
        var besucht = 0
        let fm = FileManager.default

        // Breitensuche statt Rekursion: Die Tiefe ist damit ablesbar, und ein
        // sehr tiefer Baum kann den Stapel nicht sprengen.
        var warteschlange: [(url: URL, tiefe: Int)] = [(wurzel, 0)]

        while !warteschlange.isEmpty {
            if abbruch() { return (funde, true) }

            let (ordner, tiefe) = warteschlange.removeFirst()
            besucht += 1
            if besucht > maxEintraege { grenzeErreicht = true; break }

            // Ist dieser Ordner selbst ein Modell? Dann nicht weiter hinein —
            // in den Gewichten liegt nichts, was uns noch interessiert.
            if ModelStore.istVollstaendig(ordner) {
                funde.append(ModelFund(kennung: kennung(fuer: ordner, unter: wurzel),
                                       pfad: ordner,
                                       groesseBytes: groesse(von: ordner)))
                continue
            }

            if tiefe >= maxTiefe { grenzeErreicht = true; continue }

            guard let inhalt = try? fm.contentsOfDirectory(
                at: ordner,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }

            for eintrag in inhalt {
                let istOrdner = (try? eintrag.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false
                if istOrdner { warteschlange.append((eintrag, tiefe + 1)) }
            }
        }

        return (funde, grenzeErreicht)
    }

    /// Leitet die Kennung `<org>/<repo>` aus dem Pfad ab.
    ///
    /// Zwei Formen kommen vor: Der HF-Cache schreibt `models--org--repo` in
    /// EINEN Ordnernamen (darunter `snapshots/<hash>/`), LM Studio benutzt
    /// zwei Ebenen `org/repo`. Greift keine der beiden, bleibt der Ordnername.
    static func kennung(fuer pfad: URL, unter wurzel: URL) -> String {
        let teile = pfad.standardizedFileURL.pathComponents
            .dropFirst(wurzel.standardizedFileURL.pathComponents.count)
            .map(String.init)

        if let hf = teile.first(where: { $0.hasPrefix("models--") }) {
            let zerlegt = hf.dropFirst("models--".count).components(separatedBy: "--")
            return zerlegt.joined(separator: "/")
        }
        // snapshots/<hash> am Ende abschneiden, dann die letzten zwei Ebenen.
        var rest = teile
        if let i = rest.firstIndex(of: "snapshots") { rest = Array(rest[..<i]) }
        if rest.count >= 2 { return rest.suffix(2).joined(separator: "/") }
        return rest.last ?? pfad.lastPathComponent
    }

    /// Summe der Dateien direkt im Modellordner. Unterordner bleiben außen vor —
    /// bei MLX liegen die Gewichte flach, und ein voller Durchlauf je Fund
    /// machte das Durchsuchen unnötig teuer.
    static func groesse(von ordner: URL) -> Int64 {
        guard let inhalt = try? FileManager.default.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return inhalt.reduce(Int64(0)) { summe, datei in
            let bytes = (try? datei.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return summe + Int64(bytes)
        }
    }
}
```

- [ ] **Schritt 4: Datei ins Testziel eintragen**

In `project.yml` direkt nach dem Eintrag für `ModelStore.swift` ergänzen:

```yaml
      - path: Sources/FlowLokal/ModelScan.swift
```

Dann:

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodegen generate
```

- [ ] **Schritt 5: Tests laufen lassen, Erfolg bestätigen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `** TEST SUCCEEDED **`, acht Tests in `ModelScanTests`.

- [ ] **Schritt 6: Committen**

```bash
git add Sources/FlowLokal/ModelScan.swift Tests/ShoutTests/ModelScanTests.swift project.yml
git commit -m "ModelScan: Ordner auf Auftrag durchsuchen, mit Tiefen- und Anzahlgrenze"
```

---

### Aufgabe 4: Einstellungen — Vorgabe und Ordnerwechsel

**Dateien:**
- Neu: `Sources/FlowLokal/ModelPaths.swift`
- Neu: `Tests/ShoutTests/ModelPathsTests.swift`
- Ändern: `project.yml` (Quellenliste Testziel)

**Schnittstellen:**
- Benutzt: `ModelStore` aus Aufgabe 1
- Liefert:
  - `struct ModelPaths { var basisordner: URL; var suchordner: [URL]; var verknuepfungen: [String: URL] }`
  - `ModelPaths.laden(aus defaults: UserDefaults, vorgabe: () -> URL) -> ModelPaths`
  - `func sichern(in defaults: UserDefaults)`
  - `mutating func basisordnerWechseln(zu neu: URL)`
  - `var store: ModelStore`

**Die Kernregel dieser Aufgabe:** Ohne gespeicherte Einstellung ist der
Basisordner das, was `vorgabe()` liefert — zur Laufzeit der aufgelöste
HF-Cache-Ort. Ein **fest geschriebener Pfad wäre ein Fehler**: Der Ort achtet auf
`HF_HUB_CACHE` und `HF_HOME`, und wer die gesetzt hat, bekäme sonst sämtliche
Modelle erneut heruntergeladen.

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/ModelPathsTests.swift`:

```swift
import XCTest

final class ModelPathsTests: XCTestCase {

    private var wurzel: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        wurzel = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-modelpaths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: wurzel, withIntermediateDirectories: true)
        suiteName = "shout-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wurzel)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func ordner(_ name: String) -> URL {
        wurzel.appendingPathComponent(name, isDirectory: true)
    }

    /// Der Wächter gegen einen unbeabsichtigten Neu-Download: Ohne Einstellung
    /// zeigt der Basisordner auf denselben Ort wie vor der Umstellung. Deshalb
    /// wird die Vorgabe zur Laufzeit erfragt, nicht fest geschrieben.
    func testOhneEinstellungGiltDieVorgabe() {
        let erwartet = ordner("hf-cache")
        let pfade = ModelPaths.laden(aus: defaults, vorgabe: { erwartet })
        XCTAssertEqual(pfade.basisordner, erwartet)
        XCTAssertTrue(pfade.suchordner.isEmpty)
    }

    func testGesicherteEinstellungUeberlebtDasLaden() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        pfade.basisordner = ordner("platte")
        pfade.suchordner = [ordner("lmstudio")]
        pfade.sichern(in: defaults)

        let neu = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("vorgabe") })
        XCTAssertEqual(neu.basisordner, ordner("platte"))
        XCTAssertEqual(neu.suchordner, [ordner("lmstudio")])
    }

    /// Ein Ordnerwechsel bewegt nichts. Der alte Ordner rutscht nach vorn in
    /// die Suchordner — sonst gälten alle bisherigen Modelle als verschwunden.
    func testOrdnerwechselMachtAltenZumErstenSuchordner() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("alt") })
        pfade.basisordnerWechseln(zu: ordner("neu"))
        XCTAssertEqual(pfade.basisordner, ordner("neu"))
        XCTAssertEqual(pfade.suchordner.first, ordner("alt"))
    }

    /// Zweimal derselbe Wechsel darf den Ordner nicht doppelt eintragen.
    func testOrdnerwechselDoppeltErzeugtKeineDoppelung() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("alt") })
        pfade.basisordnerWechseln(zu: ordner("neu"))
        pfade.basisordnerWechseln(zu: ordner("alt"))
        pfade.basisordnerWechseln(zu: ordner("neu"))
        XCTAssertEqual(pfade.basisordner, ordner("neu"))
        XCTAssertEqual(Set(pfade.suchordner).count, pfade.suchordner.count)
    }

    /// Der neue Basisordner darf nicht gleichzeitig als Suchordner stehen
    /// bleiben — sonst erschiene jedes Modell doppelt.
    func testNeuerBasisordnerVerlaesstDieSuchordner() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("alt") })
        pfade.suchordner = [ordner("neu"), ordner("lmstudio")]
        pfade.basisordnerWechseln(zu: ordner("neu"))
        XCTAssertFalse(pfade.suchordner.contains(ordner("neu")))
        XCTAssertTrue(pfade.suchordner.contains(ordner("lmstudio")))
    }

    func testStoreUebernimmtReihenfolge() {
        var pfade = ModelPaths.laden(aus: defaults, vorgabe: { self.ordner("basis") })
        pfade.suchordner = [ordner("a"), ordner("b")]
        XCTAssertEqual(pfade.store.orteInReihenfolge,
                       [ordner("basis"), ordner("a"), ordner("b")])
    }
}
```

- [ ] **Schritt 2: Test laufen lassen, Fehlschlag bestätigen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `cannot find 'ModelPaths' in scope`.

- [ ] **Schritt 3: `ModelPaths.swift` anlegen**

`Sources/FlowLokal/ModelPaths.swift`:

```swift
import Foundation

/// Wo die Modelle liegen — als Einstellung, getrennt von der Logik.
///
/// `ModelStore` beantwortet Fragen, `ModelPaths` merkt sich die Antworten.
/// Die Trennung hält den Store frei von `UserDefaults` und damit prüfbar.
struct ModelPaths {

    /// Wohin shout. selbst herunterlädt.
    var basisordner: URL
    /// Fremde Ordner, in denen mitbenutzt wird. Reihenfolge = Vorrang.
    var suchordner: [URL]
    /// Zuletzt bekannter Pfad je Modell-Kennung. Nur dafür da, „nicht
    /// auffindbar" von „nie da gewesen" zu unterscheiden.
    var verknuepfungen: [String: URL]

    private enum Schluessel {
        static let basis = "modelBaseDirectory"
        static let such = "modelSearchDirectories"
        static let verknuepft = "modelLinks"
    }

    /// Lädt die Einstellung. `vorgabe` wird **zur Laufzeit** erfragt und nur
    /// benutzt, wenn nichts gespeichert ist.
    ///
    /// Sie darf nicht durch einen festen Pfad ersetzt werden: Der Standardort
    /// des Hugging-Face-Caches achtet auf `HF_HUB_CACHE` und `HF_HOME`. Wer
    /// eine davon gesetzt hat, bekäme sonst beim ersten Start nach dem Update
    /// sämtliche Modelle erneut heruntergeladen.
    static func laden(aus defaults: UserDefaults, vorgabe: () -> URL) -> ModelPaths {
        let basis = defaults.string(forKey: Schluessel.basis).map(URL.init(fileURLWithPath:))
            ?? vorgabe()
        let such = (defaults.stringArray(forKey: Schluessel.such) ?? [])
            .map(URL.init(fileURLWithPath:))
        let verknuepft = (defaults.dictionary(forKey: Schluessel.verknuepft) as? [String: String] ?? [:])
            .mapValues(URL.init(fileURLWithPath:))
        return ModelPaths(basisordner: basis, suchordner: such, verknuepfungen: verknuepft)
    }

    func sichern(in defaults: UserDefaults) {
        defaults.set(basisordner.path, forKey: Schluessel.basis)
        defaults.set(suchordner.map(\.path), forKey: Schluessel.such)
        defaults.set(verknuepfungen.mapValues(\.path), forKey: Schluessel.verknuepft)
    }

    /// Wechselt den Basisordner, **ohne etwas zu verschieben**.
    ///
    /// Der bisherige Ordner rutscht an die erste Stelle der Suchordner: Sonst
    /// gälten alle bisher geladenen Modelle mit einem Schlag als verschwunden,
    /// und shout. böte an, Gigabytes erneut zu laden, die schon da sind.
    /// Ein Umzug über Laufwerksgrenzen dauert Minuten und kann abbrechen —
    /// dafür ist der Gewinn zu klein.
    mutating func basisordnerWechseln(zu neu: URL) {
        let alt = basisordner
        guard alt.standardizedFileURL != neu.standardizedFileURL else { return }
        basisordner = neu
        // Der neue Basisordner darf nicht zusätzlich als Suchordner stehen,
        // sonst erschiene jedes Modell doppelt.
        suchordner.removeAll { $0.standardizedFileURL == neu.standardizedFileURL }
        if !suchordner.contains(where: { $0.standardizedFileURL == alt.standardizedFileURL }) {
            suchordner.insert(alt, at: 0)
        }
    }

    var store: ModelStore {
        ModelStore(basisordner: basisordner, suchordner: suchordner)
    }
}
```

- [ ] **Schritt 4: Datei ins Testziel eintragen**

In `project.yml` nach `ModelScan.swift` ergänzen:

```yaml
      - path: Sources/FlowLokal/ModelPaths.swift
```

Dann:

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodegen generate
```

- [ ] **Schritt 5: Tests laufen lassen, Erfolg bestätigen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `** TEST SUCCEEDED **`, sechs Tests in `ModelPathsTests`.

- [ ] **Schritt 6: Committen**

```bash
git add Sources/FlowLokal/ModelPaths.swift Tests/ShoutTests/ModelPathsTests.swift project.yml
git commit -m "ModelPaths: Basisordner und Suchordner sichern, Wechsel verschiebt nichts"
```

---

### Aufgabe 5: `ShoutDownloader` — der Anschluss an MLX

**Dateien:**
- Neu: `Sources/FlowLokal/ShoutDownloader.swift`
- Ändern: `Sources/FlowLokal/LocalTextEngine.swift:59`
- Ändern: `project.yml` (Quellenliste des **App**-Ziels, nicht des Testziels)

**Schnittstellen:**
- Benutzt: `ModelStore` (Aufgabe 1), `ModelPaths` (Aufgabe 4)
- Liefert: `struct ShoutDownloader: MLXLMCommon.Downloader`

Diese Aufgabe wird **nicht** durch einen Unit-Test abgesichert: Sie berührt MLX,
und das Testziel ist bewusst frei von MLX und WhisperKit, damit die Suite ohne
Modelle in unter einer Sekunde läuft. Geprüft wird über den Übersetzer und den
Start der App.

- [ ] **Schritt 1: `ShoutDownloader.swift` anlegen**

`Sources/FlowLokal/ShoutDownloader.swift`:

```swift
import Foundation
import MLXLMCommon
import HuggingFace

/// Setzt `MLXLMCommon.Downloader` um und schiebt den `ModelStore` davor.
///
/// Das Protokoll hat genau eine Methode und gibt ein lokales Verzeichnis
/// zurück — dadurch hängen „vorhandenes Modell mitbenutzen" und „woanders hin
/// herunterladen" an DERSELBEN Stelle statt an zweien.
///
/// Warum nicht das Makro `#huggingFaceLoadModelContainer(configuration:)`:
/// Es nimmt den Standard-Hub und lässt sich nicht umlenken. Der ausgeschriebene
/// Weg über `loadModelContainer(from:using:configuration:)` ist eine Zeile
/// länger und die einzige Möglichkeit, hier einzugreifen.
struct ShoutDownloader: Downloader {

    let store: ModelStore
    /// Wohin eigene Downloads gehen.
    let basisordner: URL

    func download(id: String,
                  revision: String?,
                  matching patterns: [String],
                  useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {

        // Erst der Store: Liegt das Modell irgendwo — im eigenen Ordner oder in
        // einem durchsuchten —, wird es benutzt, nicht erneut geladen.
        if !useLatest, let vorhanden = store.aufloesen(id) {
            return vorhanden
        }

        // Sonst der echte Hub, mit unserem Ablageort. Der Aufruf ist genau der,
        // den das Makro #hubDownloader erzeugt (siehe HuggingFaceIntegrationMacros.swift,
        // Zeile 46 ff.) — nur mit gesetztem Cache-Verzeichnis statt HubCache.default.
        guard let repoID = Repo.ID(rawValue: id) else {
            throw ShoutDownloaderError.ungueltigeKennung(id)
        }
        let client = HubClient(cache: HubCache(cacheDirectory: basisordner))
        return try await client.downloadSnapshot(
            of: repoID,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in progressHandler(progress) })
    }
}

enum ShoutDownloaderError: Error {
    case ungueltigeKennung(String)
}
```

Die Signaturen sind an der Makro-Expansion abgelesen
(`.build/checkouts/mlx-swift-lm/Libraries/MLXHuggingFaceMacros/HuggingFaceIntegrationMacros.swift:46-56`)
und am bequemen Initialisierer
(`.build/checkouts/swift-huggingface/Sources/HuggingFace/Hub/HubClient.swift:109`),
nicht geraten. `HubClient(cache:)` setzt Host und Token-Anbieter selbst — genau
wie `HubClient()` im Makro, nur mit unserem Verzeichnis.

- [ ] **Schritt 2: Ladestelle in `LocalTextEngine` umstellen**

In `Sources/FlowLokal/LocalTextEngine.swift` den Block ab Zeile 57 ersetzen.

Vorher:

```swift
            let cfg = ModelConfiguration(id: id)
            container = try await #huggingFaceLoadModelContainer(configuration: cfg) { progress in
                onProgress?(progress.fractionCompleted)
            }
```

Nachher:

```swift
            let cfg = ModelConfiguration(id: id)
            // Ausgeschrieben statt über das Makro: Nur so lässt sich der
            // Downloader austauschen — das Makro nimmt fest den Standard-Hub.
            let pfade = ModelPaths.laden(aus: .standard,
                                         vorgabe: { HubCache.default.cacheDirectory })
            container = try await loadModelContainer(
                from: ShoutDownloader(store: pfade.store, basisordner: pfade.basisordner),
                using: #huggingFaceTokenizerLoader(),
                configuration: cfg) { progress in
                onProgress?(progress.fractionCompleted)
            }
```

- [ ] **Schritt 3: Datei ins App-Ziel eintragen**

`Sources/FlowLokal/` wird vom App-Ziel als Ordner gezogen, neue Dateien landen
automatisch darin. Trotzdem neu erzeugen, damit Xcode sie kennt:

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodegen generate
```

- [ ] **Schritt 4: Übersetzen und Tests laufen lassen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild build -project FlowLokal.xcodeproj -scheme shout -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `** BUILD SUCCEEDED **`. Bei Fehlern zu `HubClient.snapshot` die
Signatur im Paket nachsehen (siehe Hinweis in Schritt 1) und anpassen.

Danach die Testsuite, um zu belegen, dass nichts umgefallen ist:

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `** TEST SUCCEEDED **`.

- [ ] **Schritt 5: Committen**

```bash
git add Sources/FlowLokal/ShoutDownloader.swift Sources/FlowLokal/LocalTextEngine.swift
git commit -m "MLX lädt über den ShoutDownloader: erst der Store, dann der Hub"
```

---

### Aufgabe 6: WhisperKit auf den Basisordner legen

**Dateien:**
- Ändern: `Sources/FlowLokal/LocalSpeechEngine.swift:53–71`

**Schnittstellen:**
- Benutzt: `ModelPaths` (Aufgabe 4)
- Liefert: nichts Neues

Für ASR ist nur der **Ablageort** vorgesehen, nicht das Mitbenutzen fremder
Ordner — das CoreML-Format von `argmaxinc/whisperkit-coreml` liegt praktisch bei
niemandem von einem anderen Werkzeug herum. `modelFolder` bleibt dem iOS-Zweig
vorbehalten.

- [ ] **Schritt 1: `downloadBase` durchreichen**

In `Sources/FlowLokal/LocalSpeechEngine.swift` in `prepare(reset:onProgress:)`
direkt nach `let name = modelName` einfügen:

```swift
        // Der Ablageort ist wählbar; die Vorgabe wird zur Laufzeit aufgelöst,
        // damit HF_HUB_CACHE/HF_HOME weiter gelten und niemand nach dem Update
        // erneut lädt.
        let basis = ModelPaths.laden(aus: .standard,
                                     vorgabe: { HubCache.default.cacheDirectory }).basisordner
```

Dann die vier `WhisperKitConfig(...)`-Aufrufe um `downloadBase: basis` ergänzen.
Aus

```swift
            pipe = try await WhisperKit(WhisperKitConfig(model: name, download: false))
```

wird

```swift
            pipe = try await WhisperKit(WhisperKitConfig(model: name,
                                                        downloadBase: basis,
                                                        download: false))
```

und entsprechend für die Aufrufe in Zeile 68 und 71:

```swift
            pipe = try await WhisperKit(WhisperKitConfig(model: name, downloadBase: basis))
```

Der iOS-Zweig mit `WhisperKit.download(variant:)` und `modelFolder:` bleibt
**unverändert** — iOS ist nicht Teil dieser Erweiterung.

- [ ] **Schritt 2: `HubCache` importieren**

Am Kopf von `Sources/FlowLokal/LocalSpeechEngine.swift` ergänzen:

```swift
import HuggingFace
```

- [ ] **Schritt 3: Übersetzen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild build -project FlowLokal.xcodeproj -scheme shout -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `** BUILD SUCCEEDED **`.

- [ ] **Schritt 4: Tests laufen lassen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `** TEST SUCCEEDED **`.

- [ ] **Schritt 5: Committen**

```bash
git add Sources/FlowLokal/LocalSpeechEngine.swift
git commit -m "Whisper-Modelle landen im gewählten Basisordner"
```

---

### Aufgabe 7: Oberfläche auf der Modelle-Seite

**Dateien:**
- Ändern: `Sources/FlowLokal/ModelsView.swift`
- Ändern: `Sources/FlowLokal/Localization.swift`

**Schnittstellen:**
- Benutzt: `ModelPaths` (Aufgabe 4), `ModelScan` (Aufgabe 3), `ModelZustand` (Aufgabe 2)
- Liefert: nichts, was andere Aufgaben brauchen

**Wichtig — kein Löschen.** `ModelsView` hat heute keinerlei Löschfunktion; die
Seite wählt aus und lädt. Diese Aufgabe fügt **keine** hinzu. Die einzige
entfernende Handlung ist „Ordner aus der Liste nehmen", und die ändert nur eine
Einstellung. Keine Zeile dieser Aufgabe ruft `FileManager.removeItem`.

- [ ] **Schritt 1: Zustand für die Ordner anlegen**

In `Sources/FlowLokal/ModelsView.swift` zu den vorhandenen `@State`-Feldern
(nach `@State private var didFetch = false`, Zeile 30) ergänzen:

```swift
    // Modellverzeichnis: Basisordner und durchsuchte Ordner.
    @State private var pfade = ModelPaths.laden(aus: .standard,
                                                vorgabe: { HubCache.default.cacheDirectory })
    @State private var funde: [URL: [ModelFund]] = [:]
    @State private var durchsuchtGerade: URL?
    @State private var grenzeErreicht: Set<URL> = []
    @State private var abbrechen = false
```

Und am Kopf der Datei:

```swift
import HuggingFace
```

- [ ] **Schritt 2: Den Abschnitt bauen**

In `ModelsView.swift` unterhalb der Modellliste im `body` einfügen:

```swift
                ordnerAbschnitt
```

Und als neue Methode in `ModelsView` ergänzen:

```swift
    // MARK: - Modellverzeichnis

    /// Basisordner und durchsuchte Ordner. Bewusst unterhalb der Modellliste:
    /// Es ist eine Einstellung, kein Hauptweg — wer nichts ändert, merkt nichts.
    private var ordnerAbschnitt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Loc.t("Wo die Modelle liegen"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.85))

            // Basisordner
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("Basisordner")).font(.system(size: 11.5))
                        .foregroundStyle(Color(white: 0.6))
                    Text(pfade.basisordner.path).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.8)).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 8)
                Button(Loc.t("Ändern")) { basisordnerWaehlen() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.shoutLive)
            }

            Divider().overlay(Color(white: 0.25))

            // Durchsuchte Ordner
            HStack {
                Text(Loc.t("Durchsuchte Ordner")).font(.system(size: 11.5))
                    .foregroundStyle(Color(white: 0.6))
                Spacer()
                Button(Loc.t("Ordner hinzufügen")) { suchordnerHinzufuegen() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.shoutLive)
            }

            if pfade.suchordner.isEmpty {
                Text(Loc.t("Noch keiner. Wer schon Modelle hat, spart sich den Download."))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
            }

            ForEach(pfade.suchordner, id: \.self) { ordner in
                suchordnerZeile(ordner)
            }
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.13)))
    }

    private func suchordnerZeile(_ ordner: URL) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ordner.path).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.8)).lineLimit(1).truncationMode(.head)
                if durchsuchtGerade == ordner {
                    Text(Loc.t("Wird durchsucht …")).font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.5))
                } else if grenzeErreicht.contains(ordner) {
                    Text(Loc.t("Der Ordner ist sehr groß — es wurde nicht vollständig durchsucht."))
                        .font(.system(size: 10)).foregroundStyle(Color(white: 0.55))
                } else {
                    Text(Loc.f("%d Modelle gefunden", funde[ordner]?.count ?? 0))
                        .font(.system(size: 10)).foregroundStyle(Color(white: 0.5))
                }
            }
            Spacer(minLength: 8)
            if durchsuchtGerade == ordner {
                Button(Loc.t("Abbrechen")) { abbrechen = true }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color(white: 0.6))
            } else {
                Button(Loc.t("Erneut durchsuchen")) { durchsuchen(ordner) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color(white: 0.6))
                // Entfernt NUR den Eintrag aus der Liste. Die Dateien im Ordner
                // gehören jemand anderem und werden nicht angefasst.
                Button(Loc.t("Entfernen")) { suchordnerEntfernen(ordner) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color(white: 0.6))
            }
        }
    }

    private func basisordnerWaehlen() {
        guard let neu = ordnerAuswaehlen() else { return }
        pfade.basisordnerWechseln(zu: neu)
        pfade.sichern(in: .standard)
    }

    private func suchordnerHinzufuegen() {
        guard let neu = ordnerAuswaehlen() else { return }
        guard !pfade.suchordner.contains(where: { $0.standardizedFileURL == neu.standardizedFileURL }),
              neu.standardizedFileURL != pfade.basisordner.standardizedFileURL else { return }
        pfade.suchordner.append(neu)
        pfade.sichern(in: .standard)
        durchsuchen(neu)
    }

    /// Nimmt den Ordner aus der Liste. Löscht nichts.
    private func suchordnerEntfernen(_ ordner: URL) {
        pfade.suchordner.removeAll { $0.standardizedFileURL == ordner.standardizedFileURL }
        funde[ordner] = nil
        grenzeErreicht.remove(ordner)
        pfade.sichern(in: .standard)
    }

    private func ordnerAuswaehlen() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = Loc.t("Wählen")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Durchsuchen läuft abseits des Hauptstrangs — ein großer Ordner darf die
    /// Oberfläche nicht einfrieren.
    private func durchsuchen(_ ordner: URL) {
        durchsuchtGerade = ordner
        abbrechen = false
        grenzeErreicht.remove(ordner)
        Task.detached(priority: .utility) {
            let ergebnis = ModelScan.durchsuchen(ordner, abbruch: { await abbrechenGesetzt() })
            await MainActor.run {
                funde[ordner] = ergebnis.funde
                if ergebnis.grenzeErreicht { grenzeErreicht.insert(ordner) }
                durchsuchtGerade = nil
            }
        }
    }

    @MainActor private func abbrechenGesetzt() -> Bool { abbrechen }
```

> **Hinweis:** `ModelScan.durchsuchen` nimmt einen synchronen `abbruch`-Block.
> Der Aufruf oben braucht deshalb eine kleine Anpassung — entweder `abbrechen`
> als `Sendable`-Box (z. B. `let flagge = AbbruchFlagge()`) außerhalb des Tasks,
> oder `ModelScan.durchsuchen` bekommt eine `async`-Überladung. Die einfachere
> Variante: eine kleine `final class AbbruchFlagge: @unchecked Sendable` mit
> einem `NSLock`-geschützten `Bool`, die von beiden Seiten benutzt wird.

- [ ] **Schritt 3: Zustände je Modellzeile anzeigen**

`modelRow` (Zeile 268) bekommt einen weiteren Parameter und zwei Abzeichen.
Signatur ergänzen um `zustand: ModelZustand`, und im inneren `HStack(spacing: 7)`
nach den vorhandenen Abzeichen einfügen:

```swift
                        switch zustand {
                        case .fremd:
                            tag(Loc.t("Fremder Ordner"), color: Color(white: 0.55))
                        case .nichtAuffindbar:
                            // Deutlich ausgezeichnet, nicht nur ausgegraut: Hier
                            // fehlt eine Platte, das ist etwas anderes als
                            // "noch nicht geladen".
                            tag(Loc.t("Nicht auffindbar"), color: .orange)
                        case .eigen, .nichtVorhanden:
                            EmptyView()
                        }
```

Und unterhalb der Beschreibung (`Text(Loc.t(o.note))`) der Pfad, wenn das Modell
fremd ist:

```swift
                    if case .fremd(let pfad) = zustand {
                        Text(pfad.path).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(white: 0.42))
                            .lineLimit(1).truncationMode(.head)
                    }
```

Zusätzlich beim Hinweis `tooBig` ergänzen, dass der Empfehler bei selbst
gewählten Modellen nicht mehr greift — der vorhandene `tag(Loc.t("Viel RAM nötig"))`
deckt das ab und bleibt unverändert.

- [ ] **Schritt 4: Englische Entsprechungen eintragen**

Erst prüfen, dass keiner der Schlüssel schon existiert — **ein doppelter
Schlüssel im Wörterbuch-Literal stürzt zur Laufzeit ab**:

```bash
for s in "Wo die Modelle liegen" "Basisordner" "Ändern" "Durchsuchte Ordner" "Ordner hinzufügen" "Entfernen" "Erneut durchsuchen" "Abbrechen" "Wählen" "Fremder Ordner" "Nicht auffindbar"; do printf '%-34s %s\n' "$s" "$(grep -c "^        \"$s\":" Sources/FlowLokal/Localization.swift)"; done
```

Erwartet: überall `0`. Wo `1` steht, den vorhandenen Eintrag benutzen und den
neuen weglassen.

Dann in `Sources/FlowLokal/Localization.swift` im Wörterbuch `english` ergänzen
(nur die Schlüssel, die oben `0` ergaben):

```swift
        // MARK: - Modellverzeichnis

        "Wo die Modelle liegen": "Where the models live",
        "Basisordner": "Base folder",
        "Durchsuchte Ordner": "Searched folders",
        "Ordner hinzufügen": "Add folder",
        "Erneut durchsuchen": "Search again",
        "Wird durchsucht …": "Searching …",
        "%d Modelle gefunden": "%d models found",
        "Noch keiner. Wer schon Modelle hat, spart sich den Download.":
            "None yet. If you already have models, this saves the download.",
        "Der Ordner ist sehr groß — es wurde nicht vollständig durchsucht.":
            "This folder is very large — it was not searched completely.",
        "Fremder Ordner": "External folder",
        "Nicht auffindbar": "Not found",
        "Schon Modelle auf dem Rechner?": "Already have models on this Mac?",
```

Gedankenstriche (`—`), Auslassungspunkte (`…`) und typografische
Anführungszeichen müssen in Schlüssel und Aufruf **zeichengenau gleich** sein,
sonst greift die Übersetzung still nicht und es bleibt Deutsch stehen.

- [ ] **Schritt 5: Übersetzen und Tests laufen lassen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild build -project FlowLokal.xcodeproj -scheme shout -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: `** BUILD SUCCEEDED **`.

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -15
```

Erwartet: `** TEST SUCCEEDED **`.

- [ ] **Schritt 6: Belegen, dass nichts löscht**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && grep -n "removeItem\|trashItem\|unlink" Sources/FlowLokal/ModelStore.swift Sources/FlowLokal/ModelScan.swift Sources/FlowLokal/ModelPaths.swift Sources/FlowLokal/ShoutDownloader.swift
```

Erwartet: **keine Ausgabe.** Findet sich etwas, ist eine Löschfunktion
hineingewandert, die hier nichts zu suchen hat.

- [ ] **Schritt 7: Committen**

```bash
git add Sources/FlowLokal/ModelsView.swift Sources/FlowLokal/Localization.swift
git commit -m "Modelle-Seite: Basisordner, durchsuchte Ordner und Herkunft je Modell"
```

---

### Aufgabe 8: Hinweis im Onboarding

**Dateien:**
- Ändern: `Sources/FlowLokal/OnboardingView.swift`

**Schnittstellen:**
- Benutzt: den Abschnitt aus Aufgabe 7
- Liefert: nichts

Kein eigener Schritt im Onboarding — nur eine Zeile. Der Schmerz entsteht beim
ersten Start, aber die Mehrheit hat nichts zu finden und darf nicht aufgehalten
werden.

- [ ] **Schritt 1: Zeile einbauen**

Auf dem Schritt, der den Modell-Download ankündigt, unterhalb des vorhandenen
Textes:

```swift
Button(Loc.t("Schon Modelle auf dem Rechner?")) {
    // Führt auf die Modelle-Seite; dort steht der Abschnitt für die Ordner.
    zeigeModelleSeite()
}
.buttonStyle(.link)
```

Die vorhandene Navigation der Onboarding-Ansicht benutzen — keine neue bauen.

- [ ] **Schritt 2: Übersetzen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild build -project FlowLokal.xcodeproj -scheme shout -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -20
```

Erwartet: `** BUILD SUCCEEDED **`. Der Schlüssel `"Schon Modelle auf dem Rechner?"`
wurde in Aufgabe 7 Schritt 3 bereits eingetragen.

- [ ] **Schritt 3: Committen**

```bash
git add Sources/FlowLokal/OnboardingView.swift
git commit -m "Onboarding weist auf vorhandene Modelle hin"
```

---

## Abschließende Prüfung von Hand

Diese Punkte lassen sich nicht über Tests belegen und gehören **vor** ein
Release geprüft — in einem echten Build aus `/Applications`, nicht als
Debug-Start:

- [ ] Erststart nach dem Update mit gesetztem `HF_HOME`: Es wird **nichts** neu
      geladen. (Der zugehörige Test deckt die Logik ab, nicht die Umgebung.)
- [ ] Basisordner auf eine externe Platte legen, ein Modell laden, Platte
      abziehen: Zustand wird `nicht auffindbar`, es startet **kein** Download,
      und ein Diktat schlägt mit klarer Meldung fehl statt zu hängen.
- [ ] `~/.lmstudio/models` als Suchordner hinzufügen: Modelle erscheinen mit
      Pfad und Abzeichen „Fremder Ordner".
- [ ] Einen durchsuchten Ordner über „Entfernen" aus der Liste nehmen und danach
      im Finder prüfen, dass **alle Dateien darin noch da sind**.
- [ ] Oberfläche einmal auf Englisch durchsehen: keine deutschen Reste (das wäre
      ein nicht gefundener Schlüssel).
