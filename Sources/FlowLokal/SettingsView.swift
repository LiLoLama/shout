import SwiftUI

/// „Aufnahme & Text" im Mischpult-Look — Graphit-Panels mit Klartext-Labels.
struct SettingsView: View {
    @ObservedObject var settings: RecordingSettings
    let onRecordHotkey: () -> Void
    var onPersistentPillChanged: (Bool) -> Void = { _ in }
    var onPillPositionChanged: () -> Void = {}

    @AppStorage("formattingEnabled") private var formattingEnabled = true
    @AppStorage("speechCommandsEnabled") private var speechCommands = false
    @AppStorage("transcriptionLanguage") private var language = "de"
    @AppStorage("soundCuesEnabled") private var soundCues = true
    @AppStorage("persistentPill") private var persistentPill = false
    @AppStorage("pillAnchor") private var pillAnchor = "bottomCenter"
    @AppStorage("pillCustom") private var pillCustom = false
    @AppStorage("preferredMicUID") private var micUID = ""
    @State private var devices: [AudioDevices.Device] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ConsolePanel(title: "Aufnahme") {
                    FieldRow(title: "Aufnahme-Art",
                             help: settings.mode == .hold
                                ? "Taste gedrückt halten, beim Loslassen wird eingefügt."
                                : "Einmal drücken zum Starten, nochmal zum Stoppen.") {
                        ConsoleSegmented(selection: $settings.mode,
                                         options: [(.hold, "Halten"), (.toggle, "Umschalten")])
                    }
                    ConsoleDivider()
                    FieldRow(title: "So startest du",
                             help: "Drück die Taste, mit der du diktieren willst.") {
                        HStack(spacing: 10) {
                            Keycap(text: settings.isCapturing ? (settings.captureHint ?? "Taste drücken …") : settings.hotkeyDescription)
                            Button("Ändern", action: onRecordHotkey)
                                .buttonStyle(ConsoleButtonStyle())
                                .disabled(settings.isCapturing)
                        }
                    }
                    ConsoleDivider()
                    FieldRow(title: "Von selbst aufhören",
                             help: "Stoppt automatisch nach kurzer Sprechpause (im Umschalt-Modus).") {
                        Toggle("", isOn: $settings.autoStop).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                    if settings.autoStop {
                        ConsoleDivider()
                        FieldRow(title: "Pause bis Stopp") {
                            HStack(spacing: 12) {
                                Slider(value: $settings.silenceSeconds, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 130).tint(Color.shoutLive)
                                Keycap(text: String(format: "%.1f s", settings.silenceSeconds))
                            }
                        }
                    }
                    ConsoleDivider()
                    FieldRow(title: "Pille immer anzeigen",
                             help: "Zeigt die Aufnahme-Pille dauerhaft am Bildschirmrand — per Klick starten, mit ✕/✓ abbrechen oder einfügen.") {
                        Toggle("", isOn: $persistentPill).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                    ConsoleDivider()
                    FieldRow(title: "Position der Pille",
                             help: pillCustom
                                ? "Frei platziert. Du kannst die Pille jederzeit mit der Maus verschieben oder hier wieder eine feste Ecke wählen."
                                : "Wähle eine Ecke — oder zieh die Pille einfach mit der Maus an eine beliebige Stelle.") {
                        Picker("", selection: Binding(
                            get: { pillCustom ? "custom" : pillAnchor },
                            set: { newValue in
                                guard newValue != "custom" else { return }
                                pillAnchor = newValue
                                pillCustom = false
                                onPillPositionChanged()
                            }
                        )) {
                            Text("Unten Mitte").tag("bottomCenter")
                            Text("Unten links").tag("bottomLeft")
                            Text("Unten rechts").tag("bottomRight")
                            Text("Oben Mitte").tag("topCenter")
                            Text("Oben links").tag("topLeft")
                            Text("Oben rechts").tag("topRight")
                            if pillCustom { Text("Frei verschoben").tag("custom") }
                        }
                        .labelsHidden().pickerStyle(.menu).tint(Color.shoutLive).frame(maxWidth: 160)
                    }
                }

                ConsolePanel(title: "Text") {
                    FieldRow(title: "Text automatisch aufräumen",
                             help: "Füllwörter raus, Satzzeichen und Aufzählungen setzen.") {
                        Toggle("", isOn: $formattingEnabled).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                    ConsoleDivider()
                    FieldRow(title: "Sprachbefehle",
                             help: "‚Komma', ‚Punkt', ‚Fragezeichen', ‚neue Zeile', ‚neuer Absatz' werden zu echten Satzzeichen/Umbrüchen.") {
                        Toggle("", isOn: $speechCommands).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                }

                ConsolePanel(title: "Sprache & Ton") {
                    FieldRow(title: "Diktier-Sprache",
                             help: "Sprache der Transkription. „Automatisch“ erkennt sie pro Aufnahme selbst.") {
                        Picker("", selection: $language) {
                            Text("Deutsch").tag("de")
                            Text("English").tag("en")
                            Text("Automatisch").tag("auto")
                        }
                        .labelsHidden().pickerStyle(.menu).tint(Color.shoutLive).frame(maxWidth: 160)
                    }
                    ConsoleDivider()
                    FieldRow(title: "Klang-Signale",
                             help: "Dezente Töne beim Start der Aufnahme und wenn der Text eingefügt ist.") {
                        Toggle("", isOn: $soundCues).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                }

                ConsolePanel(title: "Mikrofon") {
                    FieldRow(title: "Eingang") {
                        Picker("", selection: $micUID) {
                            Text("Systemstandard").tag("")
                            ForEach(devices) { device in Text(device.name).tag(device.uid) }
                        }
                        .labelsHidden().pickerStyle(.menu).tint(Color.shoutLive).frame(maxWidth: 220)
                    }
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
        .onAppear { devices = AudioDevices.inputDevices() }
        .onChange(of: persistentPill) { _, newValue in onPersistentPillChanged(newValue) }
    }
}
