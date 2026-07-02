import SwiftUI

/// Einstellungen: Aufnahme-Modus, Hotkey, Auto-Stopp.
struct SettingsView: View {
    @ObservedObject var settings: RecordingSettings
    let onRecordHotkey: () -> Void

    @AppStorage("formattingEnabled") private var formattingEnabled = true
    @AppStorage("preferredMicUID") private var micUID = ""
    @State private var devices: [AudioDevices.Device] = []

    var body: some View {
        Form {
            Section("Aufnahme") {
                Picker("Modus", selection: $settings.mode) {
                    Text("Taste halten (Push-to-talk)").tag(RecordingSettings.Mode.hold)
                    Text("Umschalten (drücken = start/stopp)").tag(RecordingSettings.Mode.toggle)
                }
                .pickerStyle(.radioGroup)

                HStack {
                    Text("Aufnahme-Taste")
                    Spacer()
                    if settings.isCapturing {
                        Text("Taste drücken …").foregroundStyle(.secondary)
                    } else {
                        Text(settings.hotkeyDescription).fontWeight(.semibold)
                    }
                    Button(settings.isCapturing ? "…" : "Ändern", action: onRecordHotkey)
                        .disabled(settings.isCapturing)
                }
                Text("Tipp: Eine einzelne Modifier-Taste (z. B. rechte ⌥) drücken und loslassen, oder eine Kombi wie ⌥⌘Leertaste.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Automatisch stoppen") {
                Toggle("Bei Sprechpause automatisch stoppen", isOn: $settings.autoStop)
                if settings.mode == .hold {
                    Text("Nur im Umschalt-Modus wirksam (im Halten-Modus stoppt das Loslassen).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if settings.autoStop {
                    HStack {
                        Text("Pause bis Stopp")
                        Slider(value: $settings.silenceSeconds, in: 0.5...3.0, step: 0.1)
                        Text(String(format: "%.1f s", settings.silenceSeconds))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Text") {
                Toggle("Text automatisch aufräumen", isOn: $formattingEnabled)
                Text("Entfernt Füllwörter, setzt Satzzeichen und formatiert Aufzählungen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Mikrofon") {
                Picker("Eingang", selection: $micUID) {
                    Text("Systemstandard").tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
        .tint(Color.shoutLive)
        .onAppear { devices = AudioDevices.inputDevices() }
    }
}
