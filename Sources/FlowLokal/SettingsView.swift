import SwiftUI

/// „Aufnahme & Text" im Mischpult-Look — Graphit-Panels mit Klartext-Labels.
struct SettingsView: View {
    @ObservedObject var settings: RecordingSettings
    let onRecordHotkey: () -> Void

    @AppStorage("formattingEnabled") private var formattingEnabled = true
    @AppStorage("speechCommandsEnabled") private var speechCommands = false
    @AppStorage("transcriptionLanguage") private var language = "de"
    @AppStorage("soundCuesEnabled") private var soundCues = true
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
                            Keycap(text: settings.isCapturing ? "Taste drücken …" : settings.hotkeyDescription)
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
    }
}
