import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import SwiftUI

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
    private var dictionaryWindow: NSWindow?
    private let correctionWatcher = CorrectionWatcher()
    private let toast = LearnedToast()
    private var lastInsertedText = ""
    private var correctionWindow: NSWindow?

    private var micMenu: NSMenu!
    private let micUIDKey = "preferredMicUID"

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var formatterMenuItem: NSMenuItem!
    private var formattingToggleItem: NSMenuItem!
    private var loginToggleItem: NSMenuItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// keyCode der rechten Wahltaste (⌥) auf macOS.
    private let rightOptionKeyCode: UInt16 = 61

    /// Ziel-App zum Zeitpunkt des Aufnahmestarts (fürs app-abhängige Register).
    private var targetBundleID: String?

    private let formattingEnabledKey = "formattingEnabled"
    private var formattingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(formattingEnabled, forKey: formattingEnabledKey)
            updateFormatterMenu()
        }
    }

    // MARK: - Init

    override init() {
        if UserDefaults.standard.object(forKey: formattingEnabledKey) == nil {
            formattingEnabled = true
        } else {
            formattingEnabled = UserDefaults.standard.bool(forKey: formattingEnabledKey)
        }
        super.init()
    }

    // MARK: - App-Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        let dictItem = NSMenuItem(title: "Wörterbuch …", action: #selector(openDictionary), keyEquivalent: "")
        dictItem.target = self
        menu.addItem(dictItem)

        micMenu = NSMenu()
        let micItem = NSMenuItem(title: "Mikrofon", action: nil, keyEquivalent: "")
        micItem.submenu = micMenu
        menu.addItem(micItem)

        menu.addItem(
            NSMenuItem(title: "Rechte ⌥-Taste halten zum Diktieren", action: nil, keyEquivalent: "")
        )

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
        if menu === statusItem.menu { rebuildMicMenu() }
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
            statusMenuItem?.title = "Bereit — ⌥ halten zum Diktieren"
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

    // MARK: - Wörterbuch-Fenster

    @objc private func openDictionary() {
        if dictionaryWindow == nil {
            let hosting = NSHostingController(rootView: DictionaryView(dictionary: dictionary))
            let window = NSWindow(contentViewController: hosting)
            window.title = "shout. — Wörterbuch"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 480, height: 540))
            window.isReleasedWhenClosed = false
            window.delegate = self
            dictionaryWindow = window
        }
        // Accessory-Apps zeigen sonst kein Fenster im Vordergrund → kurz auf .regular.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        dictionaryWindow?.center()
        dictionaryWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Zurück zur reinen Menu-Bar-App (kein Dock-Icon).
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
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        // Globaler Hotkey ⌥⌘C → letztes Diktat korrigieren.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // keyCode 8 = "c"
        if mods == [.command, .option], event.keyCode == 8 {
            openCorrectionWindow()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard event.keyCode == rightOptionKeyCode else { return }
        let isKeyDown = event.modifierFlags.contains(.option)

        if isKeyDown, state == .idle {
            startRecording()
        } else if !isKeyDown, state == .recording {
            stopAndProcess()
        }
    }

    // MARK: - Aufnahme-Steuerung

    private func startRecording() {
        // Ziel-App merken, solange sie noch im Vordergrund ist.
        targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        do {
            try recorder.start()
            state = .recording
        } catch {
            NSLog("Aufnahme-Start fehlgeschlagen: \(error)")
        }
    }

    private func stopAndProcess() {
        let samples = recorder.stop()
        state = .working
        let bundleID = targetBundleID
        let useFormatting = formattingEnabled

        Task {
            defer { state = .idle }
            guard !samples.isEmpty else { return }
            do {
                let raw = try await transcriber.transcribe(samples)
                var output = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else { return }

                if useFormatting {
                    output = await formatter.format(output, bundleID: bundleID, termHint: dictionary.termHint)
                }
                // Gelernte/manuelle Korrekturen als letztes anwenden — sie gewinnen immer.
                output = dictionary.applyCorrections(to: output)

                let final = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty else { return }
                injector.insert(final)
                lastInsertedText = final

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
