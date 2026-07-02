import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Verdrahtet die Diktier-Pipeline:
///   Hotkey (Right ⌥ halten) → Aufnahme → WhisperKit → [Formatting-LLM] → Text an Cursor.
///
/// v0 = ASR + Rohtext. v1 = optionaler lokaler Formatting-Layer (LM Studio/Ollama).
/// Noch offen: VAD/Auto-Stop, Personal Dictionary, gelernte Stil-Edits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {

    // MARK: - Zustand

    enum State {
        case loadingModel
        case idle
        case recording
        case working   // transkribieren + formatieren
    }

    private var state: State = .loadingModel {
        didSet { updateStatusItem() }
    }

    // MARK: - Komponenten

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let injector = TextInjector()
    private let formatter = Formatter()
    private let dictionary = PersonalDictionary()
    private let history = DictationHistory()
    private let stats = StatsStore()
    private let license = LicenseStore()
    private let correctionWatcher = CorrectionWatcher()
    private let toast = LearnedToast()
    private let recIndicator = RecordingIndicator()
    private var lastInsertedText = ""
    private var correctionWindow: NSWindow?

    private let settings = RecordingSettings()

    private let dashboardModel = DashboardModel()
    private var dashboardWindow: NSWindow?

    // Hotkey-Aufnahme (Recorder in den Einstellungen)
    private var isCapturingHotkey = false
    private var captureKeyDownSeen = false
    private var captureModifierKeyCode: UInt16?

    private var micMenu: NSMenu!
    private let micUIDKey = "preferredMicUID"

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var formatterMenuItem: NSMenuItem!
    private var formattingToggleItem: NSMenuItem!
    private var loginToggleItem: NSMenuItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Ziel-App zum Zeitpunkt des Aufnahmestarts (fürs app-abhängige Register).
    private var targetBundleID: String?

    /// Zuletzt aktive Fremd-App (nicht shout.) — Ziel fürs Einfügen aus dem Verlauf.
    private var lastExternalApp: NSRunningApplication?

    private let formattingEnabledKey = "formattingEnabled"
    /// Einzige Quelle der Wahrheit: UserDefaults (Menü UND Dashboard steuern sie).
    private var formattingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: formattingEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: formattingEnabledKey); updateFormatterMenu() }
    }

    // MARK: - App-Lifecycle

    /// Standard-Menüleiste mit Bearbeiten-Befehlen — sonst funktioniert ⌘C/⌘V/⌘X
    /// in Textfeldern nicht (Menüleisten-Apps haben sonst kein „Bearbeiten"-Menü).
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "shout. beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Bearbeiten")
        editMenu.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        // Gespeichertes Mikrofon wiederherstellen (leer/nil = Systemstandard).
        let savedUID = UserDefaults.standard.string(forKey: micUIDKey)
        recorder.preferredDeviceUID = (savedUID?.isEmpty == false) ? savedUID : nil

        setupStatusItem()
        requestPermissions()
        installHotkeyMonitors()
        loadModel()
        loadFormatter()

        // Automatisches Lernen: erkannte Korrektur → Wörterbuch + Popup mit Rückgängig.
        correctionWatcher.onLearn = { [weak self] wrong, right in
            self?.handleLearnedCorrection(wrong: wrong, right: right)
        }

        // Auto-Stopp: Stille erkannt → Aufnahme beenden (nur im Umschalt-Modus aktiv).
        recorder.onSilence = { [weak self] in
            guard let self, self.state == .recording else { return }
            self.stopAndProcess()
        }
        // Live-Pegel → schwebender Aufnahme-Hinweis reagiert auf Audio.
        recorder.onLevel = { [weak self] level in
            self?.recIndicator.updateLevel(level)
        }

        // Zuletzt aktive Fremd-App verfolgen (Ziel fürs Einfügen aus dem Verlauf).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(externalAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )

        // Beim allerersten Start das Hauptfenster zeigen (sichtbare App statt nur Menüleiste).
        if !UserDefaults.standard.bool(forKey: "didShowDashboard") {
            UserDefaults.standard.set(true, forKey: "didShowDashboard")
            openDashboard(.aufnahme)
        }
    }

    private func handleLearnedCorrection(wrong: String, right: String) {
        addLearned(wrong: wrong, right: right, showUndo: true)
    }

    private func addLearned(wrong: String, right: String, showUndo: Bool) {
        let termExisted = dictionary.contents.terms.contains {
            $0.caseInsensitiveCompare(right) == .orderedSame
        }
        dictionary.addCorrection(wrong: wrong, right: right)
        guard showUndo else { return }
        toast.show(wrong: wrong, right: right) { [weak self] in
            guard let self else { return }
            self.dictionary.removeCorrection(PersonalDictionary.Correction(wrong: wrong, right: right))
            if !termExisted { self.dictionary.removeTerm(right) }
        }
    }

    // MARK: - Manuelles Korrigieren (universell, in jeder App)

    @objc private func openCorrectionWindow() {
        guard !lastInsertedText.isEmpty else { return }
        let original = lastInsertedText

        let view = CorrectionView(
            original: original,
            onApply: { [weak self] edited in
                self?.learnFromManualEdit(original: original, edited: edited)
                self?.correctionWindow?.close()
            },
            onCancel: { [weak self] in self?.correctionWindow?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "shout. — Korrigieren"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        correctionWindow = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func pasteLastDictation() {
        let text = lastInsertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        injector.paste(text)
    }

    @objc private func externalAppActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier != Bundle.main.bundleIdentifier { lastExternalApp = app }
    }

    /// Fügt Text aus dem Verlauf am Cursor ein: zuletzt aktive App nach vorn holen,
    /// dann einfügen (mit Clipboard-Wiederherstellung wie beim Diktat).
    private func insertFromHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastInsertedText = trimmed
        if let app = lastExternalApp {
            app.activate()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self.injector.paste(trimmed)
            }
        } else {
            // Kein Ziel bekannt → wenigstens in die Zwischenablage.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(trimmed, forType: .string)
        }
    }

    private func learnFromManualEdit(original: String, edited: String) {
        let subs = CorrectionWatcher.wordSubstitutions(from: original, to: edited)
        guard !subs.isEmpty else { return }
        for (wrong, right) in subs {
            addLearned(wrong: wrong, right: right, showUndo: subs.count == 1)
        }
    }

    // MARK: - Menu-Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Modell wird geladen …", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        formatterMenuItem = NSMenuItem(title: "Formatter: suche …", action: nil, keyEquivalent: "")
        formatterMenuItem.isEnabled = false
        menu.addItem(formatterMenuItem)

        menu.addItem(.separator())

        formattingToggleItem = NSMenuItem(
            title: "Formatierung", action: #selector(toggleFormatting), keyEquivalent: "f"
        )
        formattingToggleItem.target = self
        menu.addItem(formattingToggleItem)

        loginToggleItem = NSMenuItem(
            title: "Beim Login starten", action: #selector(toggleLoginItem), keyEquivalent: ""
        )
        loginToggleItem.target = self
        menu.addItem(loginToggleItem)

        let correctItem = NSMenuItem(title: "Letztes Diktat korrigieren …", action: #selector(openCorrectionWindow), keyEquivalent: "c")
        correctItem.keyEquivalentModifierMask = [.command, .option]
        correctItem.target = self
        menu.addItem(correctItem)

        let pasteLastItem = NSMenuItem(title: "Zuletzt Gesprochenes einfügen", action: #selector(pasteLastDictation), keyEquivalent: "v")
        pasteLastItem.keyEquivalentModifierMask = [.command, .control]
        pasteLastItem.target = self
        menu.addItem(pasteLastItem)

        let openItem = NSMenuItem(title: "shout. öffnen …", action: #selector(openMainWindow), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        let dictItem = NSMenuItem(title: "Wörterbuch …", action: #selector(openDictionaryTab), keyEquivalent: "")
        dictItem.target = self
        menu.addItem(dictItem)

        micMenu = NSMenu()
        let micItem = NSMenuItem(title: "Mikrofon", action: nil, keyEquivalent: "")
        micItem.submenu = micMenu
        menu.addItem(micItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()
        updateFormatterMenu()
        updateLoginMenu()
        rebuildMicMenu()
    }

    // MARK: - Mikrofon-Auswahl

    /// Wird beim Öffnen des Menüs aufgerufen → Geräteliste ist immer aktuell.
    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusItem.menu {
            rebuildMicMenu()
            updateStatusItem()
        }
    }

    private func rebuildMicMenu() {
        guard let micMenu else { return }
        micMenu.removeAllItems()
        let selectedUID = UserDefaults.standard.string(forKey: micUIDKey)

        let systemItem = NSMenuItem(title: "Systemstandard", action: #selector(selectMic(_:)), keyEquivalent: "")
        systemItem.target = self
        systemItem.representedObject = ""   // "" = Systemstandard
        systemItem.state = (selectedUID == nil || selectedUID == "") ? .on : .off
        micMenu.addItem(systemItem)
        micMenu.addItem(.separator())

        for device in AudioDevices.inputDevices() {
            let item = NSMenuItem(title: device.name, action: #selector(selectMic(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = (device.uid == selectedUID) ? .on : .off
            micMenu.addItem(item)
        }
    }

    @objc private func selectMic(_ sender: NSMenuItem) {
        let uid = (sender.representedObject as? String) ?? ""
        UserDefaults.standard.set(uid, forKey: micUIDKey)
        recorder.preferredDeviceUID = uid.isEmpty ? nil : uid
        rebuildMicMenu()
    }

    // MARK: - Autostart bei Login

    private func updateLoginMenu() {
        loginToggleItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Login-Item umschalten fehlgeschlagen: \(error)")
        }
        updateLoginMenu()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        switch state {
        case .loadingModel:
            button.title = "⏳"
            statusMenuItem?.title = "Modell wird geladen …"
        case .idle:
            button.title = "🎙️"
            let verb = settings.mode == .hold ? "halten" : "drücken"
            statusMenuItem?.title = "Bereit — \(settings.hotkeyDescription) \(verb)"
        case .recording:
            button.title = "🔴"
            statusMenuItem?.title = "Aufnahme läuft …"
        case .working:
            button.title = "✍️"
            statusMenuItem?.title = "Verarbeite …"
        }
    }

    private func updateFormatterMenu() {
        formattingToggleItem?.state = formattingEnabled ? .on : .off
        if formatter.isReady {
            formatterMenuItem?.title = "Formatter: \(formatter.activeModelName)"
        } else if formatter.isLoading {
            formatterMenuItem?.title = "Formatter: Modell wird geladen …"
        } else {
            formatterMenuItem?.title = "Formatter: nicht geladen (Rohtext)"
        }
    }

    @objc private func toggleFormatting() {
        formattingEnabled.toggle()
        // Falls gerade erst eingeschaltet und Modell noch nicht geladen: laden.
        if formattingEnabled, !formatter.isReady {
            loadFormatter()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }


    // MARK: - Hauptfenster (Dashboard)

    @objc private func openMainWindow() { openDashboard(.aufnahme) }
    @objc private func openDictionaryTab() { openDashboard(.woerterbuch) }

    private func openDashboard(_ tab: DashboardModel.Tab) {
        dashboardModel.tab = tab
        if dashboardWindow == nil {
            let view = DashboardView(
                model: dashboardModel, settings: settings, dictionary: dictionary,
                history: history, stats: stats, license: license,
                onRecordHotkey: { [weak self] in self?.beginHotkeyCapture() },
                generateProfile: { [weak self] sample in await self?.formatter.describeVoice(from: sample) ?? nil },
                onExport: { [weak self] in self?.exportData() ?? "" },
                onImport: { [weak self] in self?.importData() ?? "" },
                onInsertHistory: { [weak self] text in self?.insertFromHistory(text) }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "shout."
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 780, height: 580))
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.delegate = self
            window.center()
            dashboardWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Export / Import (lokales „Sync")

    private func exportData() -> String {
        let snapshot = SettingsSnapshot(
            mode: settings.mode.rawValue,
            autoStop: settings.autoStop,
            silenceSeconds: settings.silenceSeconds,
            keyCode: Int(settings.keyCode),
            modifiers: Int(settings.modifiers),
            isModifierOnly: settings.isModifierOnly,
            formattingEnabled: UserDefaults.standard.object(forKey: "formattingEnabled") as? Bool,
            preferredMicUID: UserDefaults.standard.string(forKey: "preferredMicUID"),
            voiceProfile: UserDefaults.standard.string(forKey: "voiceProfile"),
            licenseKey: UserDefaults.standard.string(forKey: "licenseKey")
        )
        let bundle = BackupBundle(dictionary: dictionary.contents, history: history.entries,
                                  stats: stats.data, settings: snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bundle) else { return "Export fehlgeschlagen." }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "shout-backup.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return "Export abgebrochen." }
        do { try data.write(to: url); return "Exportiert nach \(url.lastPathComponent)." }
        catch { return "Export fehlgeschlagen: \(error.localizedDescription)" }
    }

    private func importData() -> String {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return "Import abgebrochen." }
        guard let data = try? Data(contentsOf: url) else { return "Datei nicht lesbar." }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(BackupBundle.self, from: data) else {
            return "Ungültige Backup-Datei."
        }

        dictionary.replaceContents(bundle.dictionary)
        history.replaceEntries(bundle.history)
        stats.replaceData(bundle.stats)

        let s = bundle.settings
        if let m = s.mode, let mode = RecordingSettings.Mode(rawValue: m) { settings.mode = mode }
        if let a = s.autoStop { settings.autoStop = a }
        if let sec = s.silenceSeconds { settings.silenceSeconds = sec }
        if let kc = s.keyCode { settings.keyCode = UInt16(kc) }
        if let md = s.modifiers { settings.modifiers = UInt(md) }
        if let mo = s.isModifierOnly { settings.isModifierOnly = mo }
        if let f = s.formattingEnabled { UserDefaults.standard.set(f, forKey: "formattingEnabled") }
        if let mic = s.preferredMicUID { UserDefaults.standard.set(mic, forKey: "preferredMicUID") }
        if let vp = s.voiceProfile { UserDefaults.standard.set(vp, forKey: "voiceProfile") }
        if let lk = s.licenseKey, !lk.isEmpty { license.activate(lk) }
        updateStatusItem()

        return "Importiert: \(bundle.dictionary.terms.count) Begriffe, \(bundle.history.count) Diktate."
    }

    /// Klick aufs Dock-/Launchpad-Icon öffnet das Hauptfenster wieder.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboard(dashboardModel.tab)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Falls die Hotkey-Aufnahme noch lief, abbrechen.
        if isCapturingHotkey { endHotkeyCapture() }
        // Zurück zur reinen Menu-Bar-App (kein Dock-Icon), sobald kein Fenster mehr offen ist.
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Rechte / Permissions

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Modelle laden

    private func loadModel() {
        state = .loadingModel
        Task {
            do {
                try await transcriber.load()
                state = .idle
            } catch {
                statusMenuItem?.title = "Modell-Ladefehler: \(error.localizedDescription)"
                NSLog("Modell-Ladefehler: \(error)")
            }
        }
    }

    private func loadFormatter() {
        // Ladezustand sofort sichtbar machen (load() ist asynchron und kann dauern).
        formatterMenuItem?.title = "Formatter: Modell wird geladen …"
        Task {
            await formatter.load()
            updateFormatterMenu()
        }
    }

    // MARK: - Hotkey

    private func installHotkeyMonitors() {
        for matching in [NSEvent.EventTypeMask.flagsChanged, .keyDown, .keyUp] {
            NSEvent.addGlobalMonitorForEvents(matching: matching) { [weak self] event in
                self?.route(event)
            }
            NSEvent.addLocalMonitorForEvents(matching: matching) { [weak self] event in
                self?.route(event)
                return event
            }
        }
    }

    private func route(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged: handleFlagsChanged(event)
        case .keyDown: handleKeyDown(event)
        case .keyUp: handleKeyUp(event)
        default: break
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if isCapturingHotkey {
            captureKeyDownSeen = true
            settings.setRegular(keyCode: event.keyCode, modifiers: event.modifierFlags)
            endHotkeyCapture()
            return
        }
        // Fester Hotkey ⌥⌘C → letztes Diktat korrigieren (keyCode 8 = "c").
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == [.command, .option], event.keyCode == 8 {   // ⌥⌘C
            openCorrectionWindow()
            return
        }
        if mods == [.command, .control], event.keyCode == 9 {   // ⌃⌘V = zuletzt Gesprochenes einfügen
            pasteLastDictation()
            return
        }
        if settings.matchesKeyDown(event) { handleTrigger(down: true) }
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard !isCapturingHotkey else { return }
        if settings.matchesKeyUp(event) { handleTrigger(down: false) }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        if isCapturingHotkey {
            handleCaptureFlagsChanged(event)
            return
        }
        if let pressed = settings.modifierPressed(in: event) {
            handleTrigger(down: pressed)
        }
    }

    /// Setzt Start/Stopp je nach Modus.
    private func handleTrigger(down: Bool) {
        switch settings.mode {
        case .hold:
            if down, state == .idle { startRecording() }
            else if !down, state == .recording { stopAndProcess() }
        case .toggle:
            guard down else { return }   // nur der Tastendruck zählt
            if state == .idle { startRecording() }
            else if state == .recording { stopAndProcess() }
        }
    }

    // MARK: - Hotkey aufnehmen (aus den Einstellungen)

    func beginHotkeyCapture() {
        isCapturingHotkey = true
        captureKeyDownSeen = false
        captureModifierKeyCode = nil
        settings.isCapturing = true
    }

    private func endHotkeyCapture() {
        isCapturingHotkey = false
        settings.isCapturing = false
    }

    /// Reine Modifier-Taste (z. B. rechte ⌥): beim Loslassen erfassen, sofern
    /// keine normale Taste gedrückt wurde.
    private func handleCaptureFlagsChanged(_ event: NSEvent) {
        let flag = RecordingSettings.flag(forModifierKeyCode: event.keyCode)
        guard !flag.isEmpty else { return }
        if event.modifierFlags.contains(flag) {
            captureModifierKeyCode = event.keyCode          // gedrückt
        } else if !captureKeyDownSeen, captureModifierKeyCode == event.keyCode {
            settings.setModifierOnly(keyCode: event.keyCode)  // losgelassen → erfassen
            endHotkeyCapture()
        }
    }

    // MARK: - Aufnahme-Steuerung

    private func startRecording() {
        // Ziel-App merken, solange sie noch im Vordergrund ist.
        targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Aktuelles Mikrofon aus den Einstellungen (Menü oder Dashboard) übernehmen.
        let micUID = UserDefaults.standard.string(forKey: micUIDKey)
        recorder.preferredDeviceUID = (micUID?.isEmpty == false) ? micUID : nil
        // Auto-Stopp nur im Umschalt-Modus sinnvoll (im Halten-Modus stoppt das Loslassen).
        recorder.autoStopEnabled = (settings.mode == .toggle && settings.autoStop)
        recorder.silenceSeconds = settings.silenceSeconds
        do {
            try recorder.start()
            state = .recording
            recIndicator.show()
        } catch {
            NSLog("Aufnahme-Start fehlgeschlagen: \(error)")
        }
    }

    private func stopAndProcess() {
        let samples = recorder.stop()
        recIndicator.hide()
        state = .working
        let bundleID = targetBundleID
        let useFormatting = formattingEnabled

        Task {
            defer { state = .idle }
            guard !samples.isEmpty else { return }
            do {
                let raw = try await transcriber.transcribe(samples, biasTerms: dictionary.contents.terms)
                var output = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else { return }

                if useFormatting {
                    output = await formatter.format(output, bundleID: bundleID, termHint: dictionary.termHint)
                }
                // Gelernte/manuelle Korrekturen als letztes anwenden — sie gewinnen immer.
                output = dictionary.applyCorrections(to: output)

                let final = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty else { return }
                injector.paste(final)
                lastInsertedText = final
                history.add(final)
                let words = final.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
                stats.record(words: words, seconds: Double(samples.count) / 16_000.0)

                // Kurz warten, bis das Einfügen im Zielfeld angekommen ist, dann das
                // Feld beobachten, um manuelle Korrekturen automatisch zu lernen.
                let inserted = final
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    self.correctionWatcher.begin(inserted: inserted)
                }
            } catch {
                NSLog("Verarbeitung fehlgeschlagen: \(error)")
            }
        }
    }
}
