import AppKit
import AVFoundation
import ApplicationServices
import Combine
import ServiceManagement
import Sparkle
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
        case failed    // Modell-Laden fehlgeschlagen (z. B. Erststart offline)
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
    private let correctionWatcher = CorrectionWatcher()
    private let toast = LearnedToast()
    private let recIndicator = RecordingIndicator()
    private let sounds = SoundCues()

    /// Mitschnitt einer Besprechung über das Mikrofon. Gehört dem Delegate und
    /// nicht der Ansicht, damit eine laufende Aufnahme das Schließen des
    /// Dashboard-Fensters übersteht.
    private let meetingRecorder = MeetingRecorder()

    /// Datei-Transkription: eigene Warteschlange, teilt sich Modelle und Wörterbuch
    /// mit dem Diktat. Serialisiert wird über den Transcriber-actor.
    private lazy var fileQueue = FileTranscriptionQueue(
        transcriber: transcriber, formatter: formatter, dictionary: dictionary)

    /// Sparkle-Auto-Update: prüft beim Start (SUEnableAutomaticChecks) und per
    /// Menüpunkt gegen den Appcast; installiert EdDSA-signierte Updates per Klick.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var lastInsertedText = ""
    private var correctionWindow: NSWindow?

    private let settings = RecordingSettings()

    private let dashboardModel = DashboardModel()
    private var dashboardWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    /// Ergebnisfenster der Datei-Transkription, eines je Auftrag. Ohne dieses
    /// Verzeichnis öffnete jeder Doppelklick ein weiteres Fenster derselben Datei.
    private var transcriptWindows: [UUID: NSWindow] = [:]

    /// Zeitlogik der Aufnahme-Art „Doppeltipp".
    private var doubleTap = DoubleTapDetector()
    /// Läuft ab, wenn der zweite Tipp ausbleibt — blendet die wartende Pille weg.
    private var armedTimer: Timer?

    // Hotkey-Aufnahme (Recorder in den Einstellungen)
    private var isCapturingHotkey = false
    private var captureKeyDownSeen = false
    private var captureModifierKeyCode: UInt16?

    private var micMenu: NSMenu!
    private let micUIDKey = "preferredMicUID"

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var retryModelItem: NSMenuItem!
    private var formatterMenuItem: NSMenuItem!
    private var formattingToggleItem: NSMenuItem!
    private var loginToggleItem: NSMenuItem!
    private var eventMonitors: [Any] = []

    /// Sprachwechsel in den Einstellungen → Menüs neu aufbauen (die SwiftUI-Views
    /// erledigen das über Loc.shared selbst).
    private var languageObserver: AnyCancellable?

    /// Ziel-App zum Zeitpunkt des Aufnahmestarts (fürs app-abhängige Register).
    private var targetBundleID: String?

    /// Zuletzt aktive Fremd-App (nicht shout.) — Ziel fürs Einfügen aus dem Verlauf.
    private var lastExternalApp: NSRunningApplication?

    /// „In der Zwischenablage behalten" (wie Windows). Standard AUS — die Mac-App
    /// hat den vorherigen Inhalt bisher immer wiederhergestellt.
    private var keepInClipboard: Bool { UserDefaults.standard.bool(forKey: "keepInClipboard") }

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
        let aboutItem = appMenu.addItem(withTitle: Loc.t("Über shout. …"), action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: Loc.t("shout. beenden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: Loc.t("Bearbeiten"))
        editMenu.addItem(withTitle: Loc.t("Widerrufen"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: Loc.t("Wiederholen"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: Loc.t("Ausschneiden"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: Loc.t("Kopieren"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: Loc.t("Einsetzen"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: Loc.t("Alles auswählen"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        // Oberflächensprache umgestellt → Menütexte nachziehen.
        languageObserver = Loc.shared.$language
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyLanguageChange() }
            }
        seedDictationLanguage()
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

        // Auto-Stopp: Stille erkannt → Aufnahme beenden (nicht im Halten-Modus).
        recorder.onSilence = { [weak self] in
            guard let self, self.state == .recording else { return }
            self.stopAndProcess()
        }
        // Live-Pegel → schwebender Aufnahme-Hinweis reagiert auf Audio.
        recorder.onLevel = { [weak self] level in
            self?.recIndicator.updateLevel(level)
        }

        // Klickbare Pille: Start (nur idle), Abbrechen/Absenden (nur während Aufnahme).
        recIndicator.setActions(
            start:  { [weak self] in guard let self, self.state == .idle else { return }; self.startRecording() },
            cancel: { [weak self] in guard let self, self.state == .recording else { return }; self.cancelRecording() },
            submit: { [weak self] in guard let self, self.state == .recording else { return }; self.stopAndProcess() }
        )
        // Dauer-Modus („Pille immer anzeigen") aus den Einstellungen übernehmen.
        recIndicator.setPersistent(UserDefaults.standard.bool(forKey: "persistentPill"))

        // Zuletzt aktive Fremd-App verfolgen (Ziel fürs Einfügen aus dem Verlauf).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(externalAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )

        // Erststart: Onboarding-Assistent; danach das Hauptfenster.
        if !UserDefaults.standard.bool(forKey: "didCompleteOnboarding") {
            openOnboarding()
        } else if !UserDefaults.standard.bool(forKey: "didShowDashboard") {
            UserDefaults.standard.set(true, forKey: "didShowDashboard")
            openDashboard(.aufnahme)
        }
    }

    private func openOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(
                dashboard: dashboardModel, settings: settings,
                onFinish: { [weak self] in self?.finishOnboarding() },
                onRetryModel: { [weak self] in self?.retryLoadModel() }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "shout."
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.delegate = self
            window.center()
            onboardingWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "didCompleteOnboarding")
        UserDefaults.standard.set(true, forKey: "didShowDashboard")
        onboardingWindow?.close()
        onboardingWindow = nil
        openDashboard(.aufnahme)
    }

    private func handleLearnedCorrection(wrong: String, right: String) {
        addLearned(wrong: wrong, right: right, showUndo: true)
    }

    private func addLearned(wrong: String, right: String, showUndo: Bool) {
        let termExisted = dictionary.contents.terms.contains {
            $0.caseInsensitiveCompare(right) == .orderedSame
        }
        // Eine ggf. verdrängte Korrektur zum selben Falsch-Wort merken, um sie beim
        // Rückgängig-Machen wiederherstellen zu können.
        let displaced = dictionary.contents.corrections.first {
            $0.wrong.caseInsensitiveCompare(wrong) == .orderedSame && $0.right != right
        }
        dictionary.addCorrection(wrong: wrong, right: right)
        guard showUndo else { return }
        toast.show(wrong: wrong, right: right) { [weak self] in
            guard let self else { return }
            self.dictionary.removeCorrection(PersonalDictionary.Correction(wrong: wrong, right: right))
            if !termExisted { self.dictionary.removeTerm(right) }
            if let displaced {
                self.dictionary.addCorrection(wrong: displaced.wrong, right: displaced.right)
            }
        }
    }

    // MARK: - Manuelles Korrigieren (universell, in jeder App)

    @objc private func openCorrectionWindow() {
        guard !lastInsertedText.isEmpty else { return }
        // Ein bereits offenes Korrektur-Fenster zuerst schließen, sonst bleibt bei
        // mehrfachem ⌥⌘C das vorige Fenster unverwaltet zurück (Leck).
        correctionWindow?.close()
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
        window.title = Loc.t("shout. — Korrigieren")
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
        injector.paste(text, keepInClipboard: keepInClipboard)
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
        if let app = lastExternalApp, !app.isTerminated {
            app.activate()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self.injector.paste(trimmed, keepInClipboard: self.keepInClipboard)
            }
        } else {
            // Kein (lebendes) Ziel bekannt → wenigstens in die Zwischenablage, aber
            // als vertraulich markiert (kein Leak in Clipboard-Historien).
            injector.copyConcealed(trimmed)
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
        buildStatusMenu()
    }

    /// Baut das Menü der Menüleiste komplett neu — auch nach einem Sprachwechsel.
    private func buildStatusMenu() {
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: Loc.t("Modell wird geladen …"), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        retryModelItem = NSMenuItem(title: Loc.t("Modell erneut laden"), action: #selector(retryLoadModel), keyEquivalent: "")
        retryModelItem.target = self
        retryModelItem.isHidden = true
        menu.addItem(retryModelItem)

        formatterMenuItem = NSMenuItem(title: Loc.t("Formatter: suche …"), action: nil, keyEquivalent: "")
        formatterMenuItem.isEnabled = false
        menu.addItem(formatterMenuItem)

        menu.addItem(.separator())

        formattingToggleItem = NSMenuItem(
            title: Loc.t("Formatierung"), action: #selector(toggleFormatting), keyEquivalent: "f"
        )
        formattingToggleItem.target = self
        menu.addItem(formattingToggleItem)

        loginToggleItem = NSMenuItem(
            title: Loc.t("Beim Login starten"), action: #selector(toggleLoginItem), keyEquivalent: ""
        )
        loginToggleItem.target = self
        menu.addItem(loginToggleItem)

        let correctItem = NSMenuItem(title: Loc.t("Letztes Diktat korrigieren …"), action: #selector(openCorrectionWindow), keyEquivalent: "c")
        correctItem.keyEquivalentModifierMask = [.command, .option]
        correctItem.target = self
        menu.addItem(correctItem)

        let pasteLastItem = NSMenuItem(title: Loc.t("Zuletzt Gesprochenes einfügen"), action: #selector(pasteLastDictation), keyEquivalent: "v")
        pasteLastItem.keyEquivalentModifierMask = [.command, .control]
        pasteLastItem.target = self
        menu.addItem(pasteLastItem)

        let openItem = NSMenuItem(title: Loc.t("shout. öffnen …"), action: #selector(openMainWindow), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        let dictItem = NSMenuItem(title: Loc.t("Wörterbuch …"), action: #selector(openDictionaryTab), keyEquivalent: "")
        dictItem.target = self
        menu.addItem(dictItem)

        micMenu = NSMenu()
        let micItem = NSMenuItem(title: Loc.t("Mikrofon"), action: nil, keyEquivalent: "")
        micItem.submenu = micMenu
        menu.addItem(micItem)

        menu.addItem(.separator())
        let updateItem = NSMenuItem(title: Loc.t("Nach Aktualisierungen suchen …"),
                                    action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                    keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(title: Loc.t("Über shout. …"), action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: Loc.t("Beenden"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()
        updateFormatterMenu()
        updateLoginMenu()
        rebuildMicMenu()
    }

    /// Erststart: die Diktier-Sprache aus der Systemsprache belegen statt fest
    /// „de" (wie die Windows-App). „auto" kann der Nutzer jederzeit wählen.
    private func seedDictationLanguage() {
        let key = "transcriptionLanguage"
        guard UserDefaults.standard.string(forKey: key) == nil else { return }
        let system = Locale.preferredLanguages.first ?? Locale.current.identifier
        UserDefaults.standard.set(system.hasPrefix("de") ? "de" : "en", forKey: key)
    }

    /// Menüs nach einem Wechsel der Oberflächensprache neu beschriften.
    private func applyLanguageChange() {
        setupMainMenu()
        buildStatusMenu()
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

        let systemItem = NSMenuItem(title: Loc.t("Systemstandard"), action: #selector(selectMic(_:)), keyEquivalent: "")
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
            statusMenuItem?.title = Loc.t("Modell wird geladen …")
        case .idle:
            button.title = "🎙️"
            statusMenuItem?.title = Loc.f("Bereit — %@", settings.triggerDescription)
        case .recording:
            button.title = "🔴"
            statusMenuItem?.title = Loc.t("Aufnahme läuft …")
        case .working:
            button.title = "✍️"
            statusMenuItem?.title = Loc.t("Verarbeite …")
        case .failed:
            button.title = "⚠️"
            statusMenuItem?.title = Loc.t("Modell nicht geladen — „Modell erneut laden“")
        }
        retryModelItem?.isHidden = (state != .failed)
    }

    private func updateFormatterMenu() {
        formattingToggleItem?.state = formattingEnabled ? .on : .off
        // Formatter ist ein actor → Zustand asynchron lesen und dann das Menü setzen.
        Task {
            let ready = await formatter.isReady
            let loading = await formatter.isLoading
            let name = await formatter.activeModelName
            if ready {
                formatterMenuItem?.title = Loc.f("Formatter: %@", name)
            } else if loading {
                formatterMenuItem?.title = Loc.t("Formatter: Modell wird geladen …")
            } else {
                formatterMenuItem?.title = Loc.t("Formatter: nicht geladen (Rohtext)")
            }
        }
    }

    @objc private func toggleFormatting() {
        formattingEnabled.toggle()
        // Falls gerade erst eingeschaltet: laden (load() ist idempotent).
        if formattingEnabled { loadFormatter() }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }


    // MARK: - Hauptfenster (Dashboard)

    @objc private func openMainWindow() { openDashboard(.aufnahme) }
    @objc private func openDictionaryTab() { openDashboard(.woerterbuch) }

    /// „Über shout." — dasselbe Popover, das auch der Klick auf die Wortmarke öffnet.
    @objc private func openAbout() {
        openDashboard(dashboardModel.tab)
        dashboardModel.showAbout = true
    }

    /// Reicht den Sparkle-Updater als Closures an die Views weiter (kein Sparkle-Import dort).
    private var updateBridge: UpdateBridge {
        let updater = updaterController.updater
        return UpdateBridge(
            check: { updater.checkForUpdates() },
            lastCheck: { updater.lastUpdateCheckDate },
            automatic: { updater.automaticallyChecksForUpdates },
            setAutomatic: { updater.automaticallyChecksForUpdates = $0 }
        )
    }

    private func openDashboard(_ tab: DashboardModel.Tab) {
        dashboardModel.tab = tab
        if dashboardWindow == nil {
            let view = DashboardView(
                model: dashboardModel, settings: settings, dictionary: dictionary,
                history: history, stats: stats,
                onRecordHotkey: { [weak self] in self?.beginHotkeyCapture() },
                generateProfile: { [weak self] sample in await self?.formatter.describeVoice(from: sample) ?? nil },
                onExport: { [weak self] in self?.exportData() ?? "" },
                onImport: { [weak self] in self?.importData() ?? "" },
                onInsertHistory: { [weak self] text in self?.insertFromHistory(text) },
                onSelectASR: { [weak self] id in await self?.switchASRModel(to: id) },
                onSelectFormat: { [weak self] id in await self?.switchFormatModel(to: id) },
                onPersistentPillChanged: { [weak self] on in self?.recIndicator.setPersistent(on) },
                onPillPositionChanged: { [weak self] in self?.recIndicator.reposition() },
                files: fileQueue,
                meetingRecorder: meetingRecorder,
                onOpenResult: { [weak self] job in self?.openTranscriptWindow(for: job) },
                onCloseResult: { [weak self] id in self?.closeTranscriptWindow(id) },
                updates: updateBridge
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

    // MARK: - Ergebnisfenster der Datei-Transkription

    /// Öffnet das Ergebnisfenster eines Auftrags — oder holt das bestehende nach vorn.
    private func openTranscriptWindow(for job: FileTranscriptionJob) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let existing = transcriptWindows[job.id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: TranscriptWindowView(job: job, queue: fileQueue,
                                           formatterReady: dashboardModel.formatterReady))
        let window = NSWindow(contentViewController: hosting)
        window.title = Loc.f("shout. — %@", job.name)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 620))
        window.minSize = NSSize(width: 620, height: 420)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        window.center()
        // Mehrere Fenster versetzt öffnen, sonst liegen sie exakt übereinander.
        if !transcriptWindows.isEmpty {
            let offset = CGFloat(transcriptWindows.count * 24)
            window.setFrameOrigin(NSPoint(x: window.frame.origin.x + offset,
                                          y: window.frame.origin.y - offset))
        }
        transcriptWindows[job.id] = window
        window.makeKeyAndOrderFront(nil)
    }

    /// Schließt das Fenster eines Auftrags (etwa weil er aus der Liste fliegt).
    private func closeTranscriptWindow(_ id: UUID) {
        transcriptWindows[id]?.close()
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
            voiceProfile: UserDefaults.standard.string(forKey: "voiceProfile")
        )
        let bundle = BackupBundle(dictionary: dictionary.contents, history: history.entries,
                                  stats: stats.data, settings: snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(bundle) else { return Loc.t("Export fehlgeschlagen.") }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "shout-backup.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return Loc.t("Export abgebrochen.") }
        do {
            try data.write(to: url, options: .atomic)
            return Loc.f("Exportiert nach %@.", url.lastPathComponent)
        } catch {
            return Loc.f("Export fehlgeschlagen: %@", error.localizedDescription)
        }
    }

    private func importData() -> String {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return Loc.t("Import abgebrochen.") }
        guard let data = try? Data(contentsOf: url) else { return Loc.t("Datei nicht lesbar.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(BackupBundle.self, from: data) else {
            return Loc.t("Ungültige Backup-Datei.")
        }
        guard bundle.version <= BackupBundle.currentVersion else {
            return Loc.t("Dieses Backup stammt aus einer neueren Version von shout. Bitte zuerst die App aktualisieren.")
        }

        dictionary.replaceContents(bundle.dictionary)
        history.replaceEntries(bundle.history)
        stats.replaceData(bundle.stats)

        let s = bundle.settings
        if let m = s.mode, let mode = RecordingSettings.Mode(rawValue: m) { settings.mode = mode }
        if let a = s.autoStop { settings.autoStop = a }
        if let sec = s.silenceSeconds { settings.silenceSeconds = sec }
        // Failable-Konvertierung: eine defekte/hand-editierte Datei darf nicht crashen.
        if let kc = s.keyCode, let v = UInt16(exactly: kc) { settings.keyCode = v }
        if let md = s.modifiers, let v = UInt(exactly: md) { settings.modifiers = v }
        if let mo = s.isModifierOnly { settings.isModifierOnly = mo }
        // Ein hand-editiertes Backup könnte einen reservierten Hotkey enthalten
        // (würde nie auslösen bzw. mit dem synthetischen Einfügen kollidieren)
        // → auf den Standard (rechte ⌥) zurücksetzen.
        if !settings.isModifierOnly,
           isReservedCombo(keyCode: settings.keyCode, mods: NSEvent.ModifierFlags(rawValue: settings.modifiers)) {
            settings.setModifierOnly(keyCode: 61)
        }
        if let f = s.formattingEnabled { UserDefaults.standard.set(f, forKey: "formattingEnabled") }
        if let mic = s.preferredMicUID { UserDefaults.standard.set(mic, forKey: "preferredMicUID") }
        if let vp = s.voiceProfile { UserDefaults.standard.set(vp, forKey: "voiceProfile") }
        updateStatusItem()

        return Loc.f("Importiert: %d Begriffe, %d Diktate.",
                     bundle.dictionary.terms.count, bundle.history.count)
    }

    /// Klick aufs Dock-/Launchpad-Icon öffnet das Hauptfenster wieder.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboard(dashboardModel.tab)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Falls die Hotkey-Aufnahme noch lief, abbrechen.
        if isCapturingHotkey { endHotkeyCapture() }

        let closing = notification.object as? NSWindow
        if closing === correctionWindow { correctionWindow = nil }   // Retention lösen
        if closing === onboardingWindow { onboardingWindow = nil }
        if let id = transcriptWindows.first(where: { $0.value === closing })?.key {
            transcriptWindows.removeValue(forKey: id)
        }

        // Zurück zur reinen Menu-Bar-App (kein Dock-Icon) nur, wenn wirklich kein
        // eigenes Fenster mehr sichtbar ist (das schließende zählt nicht mehr).
        let dashVisible = dashboardWindow?.isVisible == true && dashboardWindow !== closing
        let corrVisible = correctionWindow?.isVisible == true && correctionWindow !== closing
        let onbVisible = onboardingWindow?.isVisible == true && onboardingWindow !== closing
        let transcriptVisible = transcriptWindows.values.contains { $0.isVisible && $0 !== closing }
        if !dashVisible && !corrVisible && !onbVisible && !transcriptVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Läuft noch ein Datei-Auftrag, wird nachgefragt — sonst ist die Arbeit von
    /// vielleicht einer halben Stunde stillschweigend weg.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Ein laufender Mitschnitt zuerst: Die Datei liegt zwar auf der Platte, aber
        // ohne das Stoppen bekäme sie weder Namen noch Auftrag — eine Stunde Meeting
        // wäre praktisch verloren.
        if meetingRecorder.isRecording {
            let alert = NSAlert()
            alert.messageText = Loc.t("Es läuft noch ein Mitschnitt.")
            alert.informativeText = Loc.t("Beim Beenden wird er gestoppt und gesichert. Du findest ihn danach unter „Meeting“.")
            alert.addButton(withTitle: Loc.t("Stoppen und beenden"))
            alert.addButton(withTitle: Loc.t("Abbrechen"))
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            if let url = meetingRecorder.stop() { fileQueue.add([url], start: false) }
        }
        guard fileQueue.hasUnfinishedJobs else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = Loc.t("Es läuft noch eine Datei-Transkription.")
        alert.informativeText = Loc.t("Wirklich beenden? Der laufende Auftrag geht verloren.")
        alert.addButton(withTitle: Loc.t("Trotzdem beenden"))
        alert.addButton(withTitle: Loc.t("Abbrechen"))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        fileQueue.cancelAll()
        correctionWatcher.stop()    // AXObserver + Timer sauber abbauen
        for m in eventMonitors { NSEvent.removeMonitor(m) }
        eventMonitors.removeAll()
    }

    // MARK: - Rechte / Permissions

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Modelle laden

    /// Erzeugt einen Fortschritts-Callback, der den (Main-Actor-)DashboardModel füttert.
    private func asrProgressHandler() -> @Sendable (Double) -> Void {
        let model = dashboardModel
        return { frac in Task { @MainActor in model.asrProgress = frac } }
    }
    private func formatProgressHandler() -> @Sendable (Double) -> Void {
        let model = dashboardModel
        return { frac in Task { @MainActor in model.formatProgress = frac } }
    }

    @objc private func retryLoadModel() {
        // Nur aus dem Fehlerzustand — während .loadingModel läuft bereits ein Load,
        // ein zweiter Aufruf würde eine parallele WhisperKit-Initialisierung starten.
        guard state == .failed else { return }
        loadModel()
    }

    private func loadModel() {
        state = .loadingModel
        dashboardModel.asrLoadFailed = false
        dashboardModel.asrLoadingID = UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR
        dashboardModel.asrProgress = 0
        Task {
            do {
                try await transcriber.load(onProgress: asrProgressHandler())
                dashboardModel.activeASR = UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR
                dashboardModel.transcriberReady = true
                state = .idle
            } catch {
                // Nicht mehr im Endlos-Spinner hängen bleiben: klarer Fehlerzustand
                // mit „erneut laden" im Menü und im Onboarding.
                NSLog("Modell-Ladefehler: \(error)")
                dashboardModel.asrLoadFailed = true
                state = .failed
                // NACH state=.failed: das didSet ruft updateStatusItem() und würde
                // einen zuvor gesetzten Titel sofort überschreiben.
                statusMenuItem?.title = Loc.f("Modell-Ladefehler: %@", error.localizedDescription)
            }
            dashboardModel.asrLoadingID = nil
            dashboardModel.asrProgress = nil
        }
    }

    private func loadFormatter() {
        // Läuft bereits ein Load/Wechsel (Startup, Toggle, Modellwechsel)? Dann nicht
        // erneut anstoßen — sonst doppelter UI-Zustand (der Formatter selbst
        // serialisiert zwar, aber wir sparen die redundante Runde).
        guard dashboardModel.formatLoadingID == nil else { return }
        // Ladezustand sofort sichtbar machen (load() ist asynchron und kann dauern).
        formatterMenuItem?.title = Loc.t("Formatter: Modell wird geladen …")
        dashboardModel.formatLoadingID = UserDefaults.standard.string(forKey: "formatModel") ?? ModelCatalog.defaultFormatting
        dashboardModel.formatProgress = 0
        Task {
            await formatter.load(onProgress: formatProgressHandler())
            dashboardModel.formatLoadingID = nil
            dashboardModel.formatProgress = nil
            dashboardModel.formatterReady = await formatter.isReady
            updateFormatterMenu()
        }
    }

    /// Modell-Empfehler: wechselt das Transkriptions-Modell zur Laufzeit.
    /// Nur im Ruhezustand erlaubt (nicht während Aufnahme/Verarbeitung/Laden),
    /// damit der State und die laufende Pipeline nicht zerrissen werden.
    private func switchASRModel(to id: String) async {
        // Auch aus dem Fehlerzustand heraus erlaubt — so kann der Nutzer sich mit
        // einem kleineren Modell aus einem fehlgeschlagenen Erst-Download befreien.
        guard state == .idle || state == .failed else {
            dashboardModel.modelNote = Loc.t("Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen oder verarbeitet wird.")
            return
        }
        // Ein Wechsel mitten in einer Datei-Transkription würde das Modell unter dem
        // laufenden Auftrag wegziehen.
        guard !fileQueue.isRunning else {
            dashboardModel.modelNote = Loc.t("Transkription läuft — Modellwechsel ist erst danach möglich.")
            return
        }
        dashboardModel.modelNote = nil
        let previous = UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR
        UserDefaults.standard.set(id, forKey: "asrModel")
        dashboardModel.asrLoadingID = id
        dashboardModel.asrProgress = 0
        state = .loadingModel
        do {
            try await transcriber.reload(onProgress: asrProgressHandler())
            dashboardModel.activeASR = id
        } catch {
            // Laden fehlgeschlagen (z. B. offline) → vorheriges Modell wiederherstellen,
            // damit die App funktionsfähig bleibt und nicht still Diktate verschluckt.
            NSLog("ASR-Modellwechsel fehlgeschlagen: \(error)")
            UserDefaults.standard.set(previous, forKey: "asrModel")
            try? await transcriber.reload(onProgress: asrProgressHandler())
            dashboardModel.activeASR = previous
            dashboardModel.modelNote = Loc.t("Modell konnte nicht geladen werden (offline?). Vorheriges Modell bleibt aktiv.")
        }
        dashboardModel.asrLoadingID = nil
        dashboardModel.asrProgress = nil
        // State an der tatsächlichen Modell-Verfügbarkeit ausrichten (nicht blind .idle):
        // sonst behauptet die App „bereit", obwohl gar kein Modell geladen ist.
        let ready = await transcriber.isReady
        dashboardModel.transcriberReady = ready
        dashboardModel.asrLoadFailed = !ready
        state = ready ? .idle : .failed
    }

    /// Modell-Empfehler: wechselt das Formatierungs-Modell zur Laufzeit.
    /// Der Formatter-actor serialisiert Loads, daher genügt der Schutz gegen
    /// parallele Wechsel; die App-Aufnahme bleibt davon unberührt.
    private func switchFormatModel(to id: String) async {
        guard dashboardModel.formatLoadingID == nil else { return }
        // Wie beim ASR-Wechsel: nicht während Aufnahme/Verarbeitung — sonst hält die
        // laufende Formatierung das alte LLM, während das neue lädt → zwei Multi-GB-
        // Modelle gleichzeitig im Unified Memory (Memory-Pressure auf kleinen Macs).
        guard state == .idle || state == .failed else {
            dashboardModel.modelNote = Loc.t("Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen oder verarbeitet wird.")
            return
        }
        // Ein Wechsel mitten in einer Datei-Transkription würde das Modell unter dem
        // laufenden Auftrag wegziehen.
        guard !fileQueue.isRunning else {
            dashboardModel.modelNote = Loc.t("Transkription läuft — Modellwechsel ist erst danach möglich.")
            return
        }
        dashboardModel.modelNote = nil
        let previous = UserDefaults.standard.string(forKey: "formatModel") ?? ModelCatalog.defaultFormatting
        UserDefaults.standard.set(id, forKey: "formatModel")
        dashboardModel.formatLoadingID = id
        dashboardModel.formatProgress = 0
        updateFormatterMenu()
        await formatter.reload(onProgress: formatProgressHandler())
        // Formatter.load() wirft nicht (Fehler = Rohtext-Fallback). Erfolg deshalb
        // an isReady ablesen und bei Fehlschlag zurückrollen — sonst markiert die UI
        // ein Modell als aktiv, das gar nicht geladen ist.
        if await formatter.isReady {
            dashboardModel.activeFormat = id
        } else {
            NSLog("Format-Modellwechsel fehlgeschlagen — zurück auf \(previous)")
            UserDefaults.standard.set(previous, forKey: "formatModel")
            await formatter.reload(onProgress: formatProgressHandler())
            dashboardModel.activeFormat = previous
            dashboardModel.modelNote = Loc.t("Aufbereitungs-Modell konnte nicht geladen werden (offline?). Vorheriges bleibt aktiv.")
        }
        dashboardModel.formatLoadingID = nil
        dashboardModel.formatProgress = nil
        dashboardModel.formatterReady = await formatter.isReady
        updateFormatterMenu()
    }

    // MARK: - Hotkey

    private func installHotkeyMonitors() {
        for matching in [NSEvent.EventTypeMask.flagsChanged, .keyDown, .keyUp] {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: matching, handler: { [weak self] event in
                self?.route(event)
            }) { eventMonitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: matching, handler: { [weak self] event in
                self?.route(event)
                return event
            }) { eventMonitors.append(m) }
        }
    }

    private func route(_ event: NSEvent) {
        // Selbst erzeugte ⌘V-Events (TextInjector) ignorieren — sonst kann das
        // Einfügen eines Diktats den eigenen Hotkey erneut auslösen.
        if let cg = event.cgEvent,
           cg.getIntegerValueField(.eventSourceUserData) == TextInjector.syntheticEventTag {
            return
        }
        switch event.type {
        case .flagsChanged: handleFlagsChanged(event)
        case .keyDown: handleKeyDown(event)
        case .keyUp: handleKeyUp(event)
        default: break
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Auto-Repeat der gehaltenen Taste ignorieren (sonst togglet der Toggle-Modus
        // im Sekundentakt und feste Shortcuts feuern mehrfach).
        guard !event.isARepeat else { return }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if isCapturingHotkey {
            let realMods = mods.intersection([.command, .option, .control, .shift])
            // Escape bricht die Aufnahme ab, statt sich selbst als Hotkey zu setzen.
            if event.keyCode == 53, realMods.isEmpty { endHotkeyCapture(); return }
            // Reservierte Kombinationen nicht als Diktier-Hotkey zulassen —
            // sie würden nie auslösen (feste Shortcuts fangen sie vorher ab).
            guard !isReservedCombo(keyCode: event.keyCode, mods: mods) else { return }
            // Normale Tasten brauchen mindestens einen Modifier — sonst würde die
            // Taste danach in JEDER App das Diktat auslösen (jedes getippte „a“).
            // Funktionstasten (F1–F12) sind als eigenständiger Hotkey ok.
            guard !realMods.isEmpty || Self.isFunctionKey(event.keyCode) else {
                settings.captureHint = Loc.t("Mit ⌘/⌥/⌃/⇧ kombinieren (oder F-Taste)")
                return
            }
            captureKeyDownSeen = true
            settings.setRegular(keyCode: event.keyCode, modifiers: event.modifierFlags)
            endHotkeyCapture()
            return
        }
        // Fester Hotkey ⌥⌘C → letztes Diktat korrigieren (keyCode 8 = "c").
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

    /// Kombinationen, die für feste Funktionen bzw. das synthetische Einfügen
    /// belegt sind und daher nicht als Diktier-Hotkey aufgenommen werden dürfen.
    private func isReservedCombo(keyCode: UInt16, mods: NSEvent.ModifierFlags) -> Bool {
        if mods == [.command, .option], keyCode == 8 { return true }    // ⌥⌘C
        if mods == [.command, .control], keyCode == 9 { return true }   // ⌃⌘V
        if mods == [.command], keyCode == 9 { return true }             // ⌘V (synthetisches Paste)
        return false
    }

    /// Funktionstasten F1–F12 (dürfen als eigenständiger Hotkey ohne Modifier dienen).
    private static let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
    private static func isFunctionKey(_ keyCode: UInt16) -> Bool { functionKeyCodes.contains(keyCode) }

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
        case .doubleTap:
            guard down else { return }   // Loslassen bedeutet hier nichts
            // systemUptime läuft in derselben Zeitbasis wie NSEvent.timestamp
            // und ist monoton — Systemzeit-Sprünge können nichts anrichten.
            let now = ProcessInfo.processInfo.systemUptime
            switch doubleTap.handleDown(at: now, isRecording: state == .recording) {
            case .armed: if state == .idle { armPill() }
            case .start: if state == .idle { startRecording() }
            case .stop: stopAndProcess()
            case .ignored: break
            }
        }
    }

    // MARK: - Wartezustand des Doppeltipps

    /// Erster Tipp: Pille erscheint als pulsierender Punkt und wartet auf den zweiten.
    private func armPill() {
        recIndicator.showArmed()
        armedTimer?.invalidate()
        armedTimer = Timer.scheduledTimer(withTimeInterval: doubleTap.window, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.armExpired() }
        }
    }

    /// Der zweite Tipp kam nicht: Pille wieder ausblenden (bzw. zurück zur
    /// Dauer-Pille). Der Detektor braucht kein Aufräumen — sein Zeitfenster ist
    /// abgelaufen, der nächste Tipp zählt von sich aus als neuer erster.
    private func armExpired() {
        armedTimer = nil
        guard state == .idle else { return }
        recIndicator.finish()
    }

    /// Beendet den Wartezustand, ohne die Pille anzufassen — sie wird vom
    /// Aufrufer sowieso auf den nächsten Zustand gesetzt.
    private func disarmPill() {
        armedTimer?.invalidate()
        armedTimer = nil
    }

    // MARK: - Hotkey aufnehmen (aus den Einstellungen)

    func beginHotkeyCapture() {
        isCapturingHotkey = true
        captureKeyDownSeen = false
        captureModifierKeyCode = nil
        settings.isCapturing = true
        settings.captureHint = nil
    }

    private func endHotkeyCapture() {
        isCapturingHotkey = false
        settings.isCapturing = false
        settings.captureHint = nil
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
        disarmPill()
        // Ziel-App merken, solange sie noch im Vordergrund ist.
        targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Aktuelles Mikrofon aus den Einstellungen (Menü oder Dashboard) übernehmen.
        let micUID = UserDefaults.standard.string(forKey: micUIDKey)
        recorder.preferredDeviceUID = (micUID?.isEmpty == false) ? micUID : nil
        // Auto-Stopp nur sinnvoll, wenn die Taste nicht gehalten wird — im
        // Halten-Modus stoppt ja das Loslassen.
        recorder.autoStopEnabled = (settings.mode != .hold && settings.autoStop)
        recorder.silenceSeconds = settings.silenceSeconds
        do {
            try recorder.start()
            state = .recording
            recIndicator.show()
            sounds.play(.start)
        } catch {
            sounds.play(.error)
            NSLog("Aufnahme-Start fehlgeschlagen: \(error)")
        }
    }

    /// Bricht eine laufende Aufnahme ab: Samples verwerfen, nichts transkribieren.
    private func cancelRecording() {
        _ = recorder.stop()      // Aufnahme beenden, Samples verwerfen
        state = .idle
        recIndicator.finish()    // zurück zur Idle-Pille bzw. ausblenden
        sounds.play(.error)      // dezenter „verworfen"-Ton
    }

    private func stopAndProcess() {
        let samples = recorder.stop()
        // Pille bleibt sichtbar und wechselt in die „Verarbeiten"-Animation,
        // bis der fertige Text eingefügt ist.
        recIndicator.showProcessing()
        sounds.play(.stop)
        state = .working
        let bundleID = targetBundleID
        let useFormatting = formattingEnabled
        let useCommands = UserDefaults.standard.bool(forKey: "speechCommandsEnabled")

        Task {
            defer { state = .idle; recIndicator.finish() }
            guard !samples.isEmpty else { return }
            do {
                let raw = try await transcriber.transcribe(samples, biasTerms: dictionary.contents.terms)
                var output = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else { return }

                // Gesprochene Befehle („Komma", „neue Zeile" …) vor der Formatierung anwenden.
                if useCommands { output = SpeechCommands.apply(to: output) }

                if useFormatting {
                    output = await formatter.format(output, bundleID: bundleID, termHint: dictionary.termHint)
                }
                // Gelernte/manuelle Korrekturen als letztes anwenden — sie gewinnen immer.
                output = dictionary.applyCorrections(to: output)

                let final = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty else { return }
                injector.paste(final, keepInClipboard: keepInClipboard)
                sounds.play(.done)
                lastInsertedText = final
                // Rohtext mitgeben: Im Verlauf lässt sich so nachsehen, was die
                // Spracherkennung WIRKLICH geliefert hat — unverzichtbar, um
                // fehlenden Inhalt der richtigen Stufe zuzuordnen (Whisper vs.
                // Aufbereitung).
                history.add(final, raw: raw)
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
                sounds.play(.error)
                NSLog("Verarbeitung fehlgeschlagen: \(error)")
            }
        }
    }
}
