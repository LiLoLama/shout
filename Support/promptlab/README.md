# promptlab — Prüfstand für die Prompts der Aufbereitung

Schickt echte Fehlfälle durch das eingestellte MLX-Modell und zeigt, was
herauskommt: alter Prompt gegen neuen, mehrere Durchgänge je Fall (das Modell
antwortet probabilistisch, ein einzelner Lauf beweist nichts).

```bash
xcodebuild -project FlowLokal.xcodeproj -scheme promptlab -configuration Debug \
  -derivedDataPath build -skipPackagePluginValidation -skipMacroValidation build
./build/Build/Products/Debug/promptlab
```

Gehört NICHT zur App: `build.sh` und `release.sh` bauen `-scheme FlowLokal` und
fassen dieses Ziel nicht an. Der Prüfstand benutzt dieselben Prompt-Zeichenketten
wie die App (`FormatterPrompt`) — sonst würde er etwas anderes messen als
ausgeliefert wird.

**Warum es das gibt:** Die Aufbereitung hat diktierte Bitten („Kannst du mir für
dieses Meeting einen Link erstellen?") als Auftrag an sich selbst gelesen und
geantwortet, statt zu formatieren — 5 Fälle in 192 Diktaten. Eine Wortstatistik
kann das nicht zuverlässig erkennen (eine umformulierte Absage behält 85 % der
Wörter), also musste der Prompt ran. Ob ein Prompt wirklich hilft, lässt sich nur
messen. Ergebnis am 27.08.2026, Fall „Bild-Frage": alter Prompt 4/4 falsch,
neuer 4/4 richtig.

Neue Fälle einfach in `faelle` in `main.swift` ergänzen.
