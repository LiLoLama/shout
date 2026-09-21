# Meeting-Erkennung: von selbst merken, dass ein Meeting läuft, und einen Mitschnitt anbieten

Stand: 2026-09-18 · Plattform: macOS (Windows später, Skizze am Ende)

## Ziel

Wenn ein Online-Meeting beginnt, soll shout. das von allein bemerken und ein
Fenster anbieten: „Zoom-Meeting läuft — mitschneiden?". Ein Klick startet den
vorhandenen Mitschnitt, ein zweiter Klick oder zwanzig Sekunden Nichtstun lassen
das Fenster wieder verschwinden. Ob überhaupt gefragt wird, steht in den
Einstellungen.

Der Mitschnitt selbst ist fertig (`MeetingRecorder`, `SystemAudioTap`,
`FileTranscriptionQueue`). Neu ist ausschließlich das **Erkennen** und das
**Fragen**.

## Das Signal — gemessen, nicht angenommen

Die naheliegende Idee, auf die Mikrofonnutzung zu horchen, ist falsch. Zwei
Messungen auf macOS 27.0 zeigen warum:

1. **Das Mikrofon läuft ohnehin ständig.** Auf einem Rechner mit aktivem „Hey
   Siri" steht `com.apple.CoreSpeech` dauerhaft mit offenem Eingabestrom da. Ein
   Mikro-Auslöser feuerte im Leerlauf.
2. **Man kann stumm im Meeting sitzen** und trotzdem mitschneiden wollen, weil
   andere reden. Das Mikrofon sagt darüber nichts.

Das tragende Signal ist der **Ausgabestrom einer Konferenz-App**:
`kAudioProcessPropertyIsRunningOutput` auf dem Prozessobjekt aus
`kAudioHardwarePropertyProcessObjectList`.

Belege:

- Das Flag hängt am **offenen Strom, nicht am hörbaren Ton**. Eine Testengine,
  die fünf Sekunden lang ausschließlich Nullen ausgibt, meldet durchgehend
  `out 1`; nach `engine.stop()` sofort `out 0`. Eine Gesprächspause im Meeting
  setzt die Erkennung also nicht zurück.
- Ein echtes Zoom-Meeting (77 s, mit Stummschaltung und Pausen) meldet
  durchgehend und ohne ein einziges Flackern `us.zoom.xos [MIKRO|TON]`. Zwei
  Sekunden nach dem Verlassen ist der Prozess aus der Liste verschwunden.
- Zoom **ohne** Meeting, nur im Hintergrund geöffnet: `run 0 in 0 out 0`.
- Die Prozessliste samt Bundle-IDs ist **ohne jede Berechtigung** lesbar,
  nachgewiesen mit einem unsignierten Kommandozeilenprogramm ohne TCC-Eintrag.

### Beobachten statt pollen — mit einer Einschränkung

Property-Listener auf `kAudioProcessPropertyIsRunningInput`/`…Output`
registrieren sich mit Status `noErr` und **feuern nie** (Regression seit
macOS 26, bestätigt auf 27.0). Darauf darf nichts gebaut werden.

Was zuverlässig feuert:

| Property | Objekt | Verhalten |
|---|---|---|
| `kAudioDevicePropertyDeviceIsRunningSomewhere` | Standard-Ausgabegerät | feuert bei 0↔1 |
| `kAudioHardwarePropertyProcessObjectList` | System | feuert, aber **doppelt** und **zu früh** (Objekt existiert vor dem IO-Start) |
| `kAudioHardwarePropertyDefaultOutputDevice` | System | feuert beim Gerätewechsel |

Daraus folgt der Aufbau: Die Listener sind der **Wecker**, danach wird für eine
begrenzte Zeit einmal pro Sekunde nachgelesen. Im Ruhezustand läuft kein Timer.

## Aufbau

### `MeetingDetector.swift` — neu

`@MainActor final class MeetingDetector: ObservableObject`, nur macOS.

Zustandsautomat:

```
schlafend ──Listener feuert──▶ prüfend (1 Hz)
prüfend   ──12 s durchgehend Kandidat──▶ Meeting läuft  → onDetected
prüfend   ──8 Runden ohne Kandidat──▶ schlafend
Meeting   ──5 Runden ohne Kandidat──▶ schlafend         → onEnded
```

Ein Kandidat ist ein Prozessobjekt, das **alle** Bedingungen erfüllt:

- Bundle-ID beginnt mit einem Präfix aus der Konferenz-Tabelle
  (Präfix, weil der Ton im Helfer laufen kann: `us.zoom.caphost` neben
  `us.zoom.xos`, `com.google.Chrome.helper` neben `com.google.Chrome`),
- das Präfix ist nicht vom Nutzer abgeschaltet,
- `IsRunningOutput == 1`,
- es ist nicht der eigene Prozess (`kAudioHardwarePropertyTranslatePIDToProcessObject`).

Die Haltezeit von 12 s sinkt auf 4 s, **wenn zusätzlich eine Kamera läuft**
(`kCMIODevicePropertyDeviceIsRunningSomewhere`, ebenfalls berechtigungsfrei
lesbar). Die Kamera ist ausdrücklich **kein** eigener Auslöser: Im Messlauf lief
sie elf Sekunden lang für Zooms Vorschaufenster, bevor überhaupt ein Meeting
existierte.

Das Mikrofon ist **kein** Auslöser und **keine** Bedingung.

Der Detektor schweigt vollständig, solange ein Diktat läuft, ein Mitschnitt
läuft, der Bildschirm gesperrt ist oder für diese App schon gefragt wurde
(Abkühlung bis zum Ende des Meetings).

### `MeetingPrompt.swift` — neu

Ein `NSPanel` nach demselben Muster wie die Pille (`RecordingIndicator`):
`[.borderless, .nonactivatingPanel]`, `level = .statusBar`, `backgroundColor =
.clear`, `collectionBehavior = [.canJoinAllSpaces, .stationary,
.fullScreenAuxiliary]` — damit es auch über einem Zoom-Vollbild steht und den
Tastaturfokus nicht wegnimmt.

Inhalt: App-Symbol, „Zoom-Meeting läuft", eine Zeile Erklärung, die Knöpfe
**Mitschneiden** und **Nicht jetzt**, klein „Nie bei Zoom", dazu dauerhaft der
rechtliche Hinweis. Nach dem Start verwandelt sich dieselbe Karte in eine
Laufanzeige mit Zeit, Pegel und **Stoppen** — das Dashboard muss dafür nicht
offen sein.

Auftritt wie bei der Pille: Zielzustand in einer Transaktion ohne Animation
setzen, im nächsten Durchlauf aufklappen (Feder), und bei „Bewegung reduzieren"
ohne Feder. Selbstauflösung nach 20 s = „Nicht jetzt".

Position: oben mittig; steht die Pille oben, weicht die Karte nach unten aus.

### Änderungen an Vorhandenem

| Datei | Änderung |
|---|---|
| `SystemAudioTap.swift` | `start(includeMicrophone:onlyProcesses:)` — mit Prozessliste `CATapDescription(monoMixdownOfProcesses:)`, sonst wie bisher global |
| `MeetingRecorder.swift` | `start(source:limitedTo:)` reicht das Prozessobjekt durch |
| `MeetingView.swift` | Abschnitt „Meeting erkennen" |
| `AppDelegate.swift` | Detektor besitzen, mit Prompt und `meetingRecorder` verdrahten |
| `Localization.swift` | neue Texte |

Der begrenzte Tap ist kein Beiwerk: Ein global mitschneidender Tap nimmt Spotify
im Hintergrund mit auf. Bei einem Mitschnitt, den man selbst startet, ist das
verschmerzbar — bei einem automatisch angebotenen nicht. Weil die Erkennung die
pid ohnehin kennt, kann genau dieser Prozess getappt werden.

## Verhalten

### Einstellungen

`@AppStorage("meetingDetect")` mit drei Werten:

| Wert | Wirkung |
|---|---|
| `off` | Kein Detektor, kein Timer, keine Listener |
| `ask` | **Voreinstellung** — Karte fragt |
| `auto` | Mitschnitt startet ohne Rückfrage, die Karte zeigt nur die Laufanzeige |

`ask` ist die Voreinstellung, weil eine Frage keine Aufnahme ist. `auto` ist
bewusst nur auf ausdrücklichen Wunsch zu haben: Ein Gespräch ohne Einverständnis
der anderen mitzuschneiden ist in Deutschland und Österreich strafbar (§ 201
StGB), und eine App sollte das nicht von selbst tun. Der Hinweis steht deshalb
auch auf der Karte, nicht nur in den Einstellungen.

Abgeschaltete Programme stehen als Präfixliste in
`UserDefaults["meetingDetectMuted"]`; „Nie bei Zoom" schreibt dorthin, die
Einstellungen zeigen sie und können sie leeren.

### Erkannte Programme

Zoom, Microsoft Teams, Webex, Skype, FaceTime, Discord, Slack (Huddles), Jitsi,
GoTo Meeting, Around, RingCentral, BlueJeans.

**Browser bewusst nicht.** Safari spielt seinen Ton über
`com.apple.WebKit.GPU` — einen Prozess, den sich jede WebKit-App teilt, also
nicht zuzuordnen. Chrome wäre über das Präfix zuzuordnen, aber ein Meet-Call und
ein YouTube-Tab sehen von außen identisch aus, und gerade der stumme Teilnehmer
nimmt das letzte Unterscheidungsmerkmal weg. Lieber gar nicht erkennen als bei
jedem Video fragen. Ein späterer Weg wäre der Fenstertitel über die
Bedienungshilfen (das Recht hat die App fürs Einfügen ohnehin) — erst dann, wenn
sich das an echten Titeln nachmessen lässt.

### Nach dem Mitschnitt

Stoppen benennt automatisch (`Zoom 2026-09-18 19-23`) und reicht die Datei an
`FileTranscriptionQueue.add` — derselbe einzige Verarbeitungsweg wie bisher.
Kein Namensdialog: Wer die Karte benutzt, hat das Dashboard nicht offen.
Umbenennen geht unter „Meeting" weiterhin.

Endet das Meeting, während aufgenommen wird, stoppt der Mitschnitt von selbst.

## Sicherheit und Berechtigungen

Die Erkennung braucht **keine** zusätzliche Berechtigung und keinen neuen
Info.plist-Schlüssel — nachgewiesen. Der Mitschnitt braucht wie bisher
`NSAudioCaptureUsageDescription` (steht schon drin) und die Erlaubnis zur
Tonaufnahme; fehlt sie, greift die vorhandene `noSignal`-Erkennung.

Es verlässt nichts das Gerät. Gelesen werden ausschließlich Statusflags und
Bundle-IDs.

## Prüfungen

1. Zoom-Meeting betreten → Karte erscheint nach ~12 s (mit Kamera nach ~4 s).
2. Stumm schalten, Gesprächspause → Karte bzw. laufender Mitschnitt bleibt.
3. „Nicht jetzt" → keine erneute Frage für dasselbe Meeting.
4. „Nie bei Zoom" → auch beim nächsten Meeting still; Einstellungen zeigen es.
5. Meeting verlassen → Erkennung endet binnen ~5 s; laufender Mitschnitt stoppt
   und landet in der Warteschlange.
6. Zoom nur geöffnet, kein Meeting → nichts.
7. Musik in Spotify → nichts (keine Konferenz-App).
8. Kopfhörer während des Meetings anstecken → Erkennung läuft weiter
   (Listener wird auf das neue Standardgerät umgehängt).
9. Diktat während eines Meetings → keine Karte, Diktat unbeeinflusst.
10. Mit `meetingDetect = off` läuft kein Timer und kein Listener.

## Windows (später)

`IAudioSessionManager2` liefert pro Prozess `AudioSessionState` und die pid —
dasselbe Muster, dieselbe Konferenz-Tabelle. Eigene Runde.
