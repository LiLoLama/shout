import SwiftUI

/// „Aufnahme & Text" im Mischpult-Look — Graphit-Panels mit Klartext-Labels.
struct SettingsView: View {
    @ObservedObject var settings: RecordingSettings
    let onRecordHotkey: () -> Void
    var onPersistentPillChanged: (Bool) -> Void = { _ in }
    var onPillPositionChanged: () -> Void = {}

    @AppStorage("formattingEnabled") private var formattingEnabled = true
    @AppStorage("speechCommandsEnabled") private var speechCommands = false
    @AppStorage("keepInClipboard") private var keepInClipboard = false
    @AppStorage("transcriptionLanguage") private var language = "de"
    @AppStorage(Loc.storageKey) private var uiLanguage = "system"
    @AppStorage("soundCuesEnabled") private var soundCues = true
    @AppStorage("persistentPill") private var persistentPill = false
    @AppStorage("pillAnchor") private var pillAnchor = "bottomCenter"
    @AppStorage("pillCustom") private var pillCustom = false
    /// Fixiert: Die Pille lässt sich nicht mehr aus Versehen verschieben.
    @AppStorage("pillLocked") private var pillLocked = false
    @AppStorage("pillOrientation") private var pillOrientation = "auto"
    @AppStorage("preferredMicUID") private var micUID = ""
    @State private var devices: [AudioDevices.Device] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ConsolePanel(title: Loc.t("Aufnahme")) {
                    FieldRow(title: Loc.t("Aufnahme-Art"),
                             help: settings.mode == .hold
                                ? Loc.t("Taste gedrückt halten, beim Loslassen wird eingefügt.")
                                : Loc.t("Einmal drücken zum Starten, nochmal zum Stoppen.")) {
                        ConsoleSegmented(selection: $settings.mode,
                                         options: [(.hold, Loc.t("Halten")), (.toggle, Loc.t("Umschalten"))])
                    }
                    ConsoleDivider()
                    FieldRow(title: Loc.t("So startest du"),
                             help: Loc.t("Drück die Taste, mit der du diktieren willst.")) {
                        HStack(spacing: 10) {
                            Keycap(text: settings.isCapturing ? (settings.captureHint ?? Loc.t("Taste drücken …")) : settings.hotkeyDescription)
                            Button(Loc.t("Ändern"), action: onRecordHotkey)
                                .buttonStyle(ConsoleButtonStyle())
                                .disabled(settings.isCapturing)
                        }
                    }
                    ConsoleDivider()
                    FieldRow(title: Loc.t("Von selbst aufhören"),
                             help: Loc.t("Stoppt automatisch nach kurzer Sprechpause (im Umschalt-Modus).")) {
                        Toggle("", isOn: $settings.autoStop).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                    if settings.autoStop {
                        ConsoleDivider()
                        FieldRow(title: Loc.t("Pause bis Stopp")) {
                            HStack(spacing: 12) {
                                Slider(value: $settings.silenceSeconds, in: 0.5...3.0, step: 0.1)
                                    .frame(width: 130).tint(Color.shoutLive)
                                Keycap(text: String(format: "%.1f s", settings.silenceSeconds))
                            }
                        }
                    }
                    ConsoleDivider()
                    FieldRow(title: Loc.t("Pille immer anzeigen"),
                             help: Loc.t("Zeigt die Aufnahme-Pille dauerhaft am Bildschirmrand — per Klick starten, mit ✕/✓ abbrechen oder einfügen.")) {
                        Toggle("", isOn: $persistentPill).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                    ConsoleDivider()
                    FieldRow(title: Loc.t("Position der Pille"),
                             help: pillCustom
                                ? Loc.t("Frei platziert. Du kannst die Pille jederzeit mit der Maus verschieben oder hier wieder eine feste Ecke wählen.")
                                : Loc.t("Wähle eine Ecke — oder zieh die Pille einfach mit der Maus an eine beliebige Stelle.")) {
                        Picker("", selection: Binding(
                            get: { pillCustom ? "custom" : pillAnchor },
                            set: { newValue in
                                guard newValue != "custom" else { return }
                                pillAnchor = newValue
                                pillCustom = false
                                onPillPositionChanged()
                            }
                        )) {
                            Text(Loc.t("Unten Mitte")).tag("bottomCenter")
                            Text(Loc.t("Unten links")).tag("bottomLeft")
                            Text(Loc.t("Unten rechts")).tag("bottomRight")
                            Text(Loc.t("Oben Mitte")).tag("topCenter")
                            Text(Loc.t("Oben links")).tag("topLeft")
                            Text(Loc.t("Oben rechts")).tag("topRight")
                            if pillCustom { Text(Loc.t("Frei verschoben")).tag("custom") }
                        }
                        .labelsHidden().pickerStyle(.menu).tint(Color.shoutLive).frame(maxWidth: 160)
                    }
                    ConsoleDivider()
                    FieldRow(title: Loc.t("Pille fixieren"),
                             help: Loc.t("Verhindert das Verschieben mit der Maus. Praktisch, wenn sie einmal richtig sitzt — ein Klick daneben rückt sie dann nicht mehr weg.")) {
                        Toggle("", isOn: $pillLocked).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                    ConsoleDivider()
                    FieldRow(title: Loc.t("Ausrichtung der Pille"),
                             help: Loc.t("„Automatisch“ stellt sie an einer Seitenkante senkrecht und oben oder unten waagerecht — dort, wo sie am wenigsten Platz wegnimmt.")) {
                        Picker("", selection: Binding(
                            get: { pillOrientation },
                            set: { pillOrientation = $0; onPillPositionChanged() }
                        )) {
                            Text(Loc.t("Automatisch")).tag("auto")
                            Text(Loc.t("Waagerecht")).tag("horizontal")
                            Text(Loc.t("Senkrecht")).tag("vertical")
                        }
                        .labelsHidden().pickerStyle(.menu).tint(Color.shoutLive).frame(maxWidth: 160)
                    }
                }

                ConsolePanel(title: Loc.t("Text")) {
                    FieldRow(title: Loc.t("Text automatisch aufräumen"),
                             help: Loc.t("Füllwörter raus, Satzzeichen und Aufzählungen setzen.")) {
                        Toggle("", isOn: $formattingEnabled).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                    ConsoleDivider()
                    FieldRow(title: Loc.t("Sprachbefehle"),
                             help: Loc.t("‚Komma', ‚Punkt', ‚Fragezeichen', ‚neue Zeile', ‚neuer Absatz' werden zu echten Satzzeichen/Umbrüchen.")) {
                        Toggle("", isOn: $speechCommands).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                    ConsoleDivider()
                    FieldRow(title: Loc.t("In der Zwischenablage behalten"),
                             help: Loc.t("Das Diktat bleibt zusätzlich in der Zwischenablage — sonst wird der vorherige Inhalt wiederhergestellt.")) {
                        Toggle("", isOn: $keepInClipboard).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                }

                ConsolePanel(title: Loc.t("Sprache & Ton")) {
                    FieldRow(title: Loc.t("Diktier-Sprache"),
                             help: Loc.t("Sprache der Transkription. „Automatisch“ erkennt sie pro Aufnahme selbst.")) {
                        Picker("", selection: $language) {
                            Text(Loc.t("Deutsch")).tag("de")
                            Text(Loc.t("English")).tag("en")
                            Text(Loc.t("Automatisch")).tag("auto")
                        }
                        .labelsHidden().pickerStyle(.menu).tint(Color.shoutLive).frame(maxWidth: 160)
                    }
                    ConsoleDivider()
                    // Oberflächensprache — unabhängig von der Diktier-Sprache.
                    FieldRow(title: Loc.t("Oberfläche"),
                             help: Loc.t("Sprache der Bedienoberfläche. „Wie das System“ folgt der Sprache von macOS.")) {
                        Picker("", selection: Binding(
                            get: { uiLanguage },
                            set: { Loc.shared.apply($0) }   // schreibt UserDefaults und baut die UI neu auf
                        )) {
                            ForEach(Loc.languageOptions, id: \.key) { option in
                                Text(option.label).tag(option.key)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).tint(Color.shoutLive).frame(maxWidth: 160)
                    }
                    ConsoleDivider()
                    FieldRow(title: Loc.t("Klang-Signale"),
                             help: Loc.t("Dezente Töne beim Start der Aufnahme und wenn der Text eingefügt ist.")) {
                        Toggle("", isOn: $soundCues).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
                    }
                }

                ConsolePanel(title: Loc.t("Mikrofon")) {
                    FieldRow(title: Loc.t("Eingang")) {
                        Picker("", selection: $micUID) {
                            Text(Loc.t("Systemstandard")).tag("")
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
