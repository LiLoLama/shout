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
    private let transcriber = Transcriber(makeEngine: EngineFactory.speech,
                                              makeFallback: EngineFactory.speechFallback)
    private let injector = TextInjector()
    private let formatter = Formatter(makeEngine: EngineFactory.text)
    private let dictionary = PersonalDictionary()
    private let history = DictationHistory()
    private let stats = StatsStore()
    private let correctionWatcher = CorrectionWatcher()
    private let toast = LearnedToast()
    private let recIndicator = RecordingIndicator()
    private let sounds = SoundCues()

    // MARK: - Notizen und Scratchpad
    //
    // Alles entsteht erst beim ersten Zugriff. Der Ordner in „Dokumente“ entsteht
    // sogar erst mit der ersten gesicherten Notiz.

    let noteVersions = NoteVersions()

    /// Eigene Transforms (`transforms.json`) und der Zauberstab.
    private let transformStore = TransformStore()
    private lazy var transformRunner = NoteTransformRunner(
        saveVersion: { [weak self] session in self?.saveVersionBeforeTransform(session) },
        transform: { [formatter] text, anweisung in try await formatter.transform(text, instruction: anweisung) })
    private var noteTools: NoteToolbox {
        NoteToolbox(runner: transformRunner, transforms: transformStore, onVoiceInstruction: { [weak self] session in self?.beginVoiceInstruction(for: session) })
    }

    /// Vor jedem Transform ein Stand — unabhängig von der Zehn-Minuten-Frist.
    private func saveVersionBeforeTransform(_ session: NoteEditorSession) {
        guard !session.note.isNew else { return }
        noteVersions.save(session.note.body, for: session.note.fileName)
    }

    private var notesStoreStorage: NoteStore?
    private var noteStore: NoteStore {
        if let store = notesStoreStorage { return store }
        let store = NoteStore(folder: NotesFolder.current(), beforeOverwrite: noteVersions.overwriteHook)
        notesStoreStorage = store
        noteVersions.attach(to: store)
        // Stände ohne Datei nach 30 Tagen weg — nur mit erreichbarem Ordner, sonst
        // sähe jede Notiz verwaist aus.
        if store.folderState == .ok {
            noteVersions.cleanUp(keeping: Set(store.notes.map(\.fileName)))
        }
        // Mit dem Ordner entsteht auch das Scratchpad-Modell (ohne Panel): Es hört auf
        // Umbenennungen. Würde „Eingang“ sonst zuerst auf der Seite umbenannt, legte
        // ⌃⌥I danach eine zweite Eingangs-Notiz an. Nicht schon beim Start — das läse
        // den Ordner in „Dokumente“ und könnte nach der Freigabe dafür fragen.
        _ = scratchpad
        return store
    }

    /// Eine Sitzung pro Notiz — Seite und Panel teilen sie.
    private var noteRegistryStorage: NoteSessionRegistry?
    private var noteRegistry: NoteSessionRegistry {
        if let registry = noteRegistryStorage { return registry }
        let registry = NoteSessionRegistry(store: noteStore)
        noteRegistryStorage = registry
        return registry
    }

    private var notesPageStorage: NotesPageModel?
    private var notesPage: NotesPageModel {
        if let page = notesPageStorage { return page }
        let page = NotesPageModel(store: noteStore, registry: noteRegistry)
        page.versions = noteVersions
        page.onFolderChanged = { [weak self] in self?.scratchpadStorage?.resetTabs() }
        notesPageStorage = page
        return page
    }

    private var scratchpadStorage: ScratchpadModel?
    private var scratchpad: ScratchpadModel {
        if let model = scratchpadStorage { return model }
        let store = noteStore
        // Ein frisch angelegter Ordner hat das Modell eben schon selbst erzeugt.
        if let model = scratchpadStorage { return model }
        let model = ScratchpadModel(store: store, registry: noteRegistry)
        scratchpadStorage = model
        return model
    }

    private var scratchpadPanelStorage: ScratchpadPanelController?
    private var scratchpadPanel: ScratchpadPanelController {
        if let controller = scratchpadPanelStorage { return controller }
        let controller = ScratchpadPanelController(model: scratchpad, settings: scratchpadSettings, mic: scratchpadMic,
                                                   handoff: handoffTarget,
                                                   tools: noteTools,
                                                   onMic: { [weak self] in self?.toggleScratchpadMic() },
                                                   onHandoff: { [weak self] in self?.handoffFromScratchpad() })
        scratchpadPanelStorage = controller
        return controller
    }

    let scratchpadSettings = ScratchpadSettings()
    private let scratchpadMic = ScratchpadMicState()
    private let scratchpadKey = GlobalHotkey()
    private let inboxKey = GlobalHotkey()
    private var scratchpadPress = HotkeyPressClassifier()
    private var scratchpadHoldTimer: Timer?
    private var scratchpadMenuItem: NSMenuItem?
    /// Wohin das laufende Diktat geht — festgelegt beim Start der Aufnahme.
    private var dictationTarget: DictationTarget = .frontApp(bundleID: nil)

    /// Ein Beenden, das auf das laufende Diktat wartet (`.terminateLater`).
    /// Siehe `applicationShouldTerminate`.
    private var pendingTermination: DeferredTermination?
    private var pendingTerminationTimer: Timer?
    /// Wie lange das Beenden höchstens auf die Zustellung wartet.
    private static let terminationWaitLimit: TimeInterval = 20
    /// Was das laufende Diktat schon erkannt hat — für den Fall, dass das Beenden
    /// nicht länger auf die Aufbereitung warten kann.
    private var processingText: (text: String, raw: String)?

    /// Reine Modifier-Diktiertaste (Vorgabe: rechte ⌥): seit wann sie gedrückt ist
    /// (`nil` = nicht gedrückt), ob genau dieser Druck eine Aufnahme gestartet hat
    /// und ob eine Scratchpad- oder Eingangs-Taste den Druck für sich beansprucht hat.
    /// Siehe `claimDictationModifierPress()`.
    private var dictationModifierDownAt: TimeInterval?
    private var recordingStartedByModifierPress = false
    private var dictationModifierClaimed = false

    /// Mitschnitt einer Besprechung über das Mikrofon. Gehört dem Delegate und
    /// nicht der Ansicht, damit eine laufende Aufnahme das Schließen des
    /// Dashboard-Fensters übersteht.
    private let meetingRecorder = MeetingRecorder()

    /// Merkt von selbst, dass ein Meeting läuft, und die Karte, die dann fragt.
    private let meetingDetector = MeetingDetector()
    private let meetingPrompt = MeetingPrompt()
    /// Das Meeting, das den laufenden Mitschnitt ausgelöst hat.
    private var autoMeeting: MeetingDetector.Meeting?
    /// Erkanntes Meeting, das wegen gesperrtem Bildschirm noch nicht gefragt wurde.
    private var deferredMeeting: MeetingDetector.Meeting?
    /// Speist Zeit und Pegel in die Karte — nur während eines solchen Mitschnitts.
    private var meetingTicker: Timer?

    /// Datei-Transkription: eigene Warteschlange, teilt sich Modelle und Wörterbuch
    /// mit dem Diktat. Serialisiert wird über den Transcriber-actor.
    private lazy var fileQueue = FileTranscriptionQueue(
        transcriber: transcriber, formatter: formatter, dictionary: dictionary)

    /// Wurde in dieser Sitzung schon auf die fehlende Bedienungshilfen-Freigabe
    /// hingewiesen?
    private var warnedAboutAccessibility = false

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

    /// Der Schalter auf der Einstellungsseite (`@AppStorage`) und der Backup-Import
    /// schreiben „formattingEnabled“ direkt in die UserDefaults und umgehen den
    /// Setter — ohne Beobachter bliebe der Zauberstab auf altem Stand.
    private var formattingObserver: AnyCancellable?

    /// Zuletzt aktive Fremd-App (nicht shout.) — Ziel fürs Einfügen aus dem Verlauf.
    private var lastExternalApp: NSRunningApplication?
    /// Ziel von „Ablegen“ im Scratchpad — spiegelt `lastExternalApp` für den Knopf.
    private let handoffTarget = HandoffTarget()

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
        formattingObserver = UserDefaults.standard.publisher(for: \.formattingEnabled)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateFormatterMenu() }
            }
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
        setupScratchpad()
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
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(externalAppTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        // Die App, die beim Start vorne war, ist schon ein Ziel fürs Ablegen.
        if let vorne = NSWorkspace.shared.frontmostApplication,
           vorne.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApp = vorne
            handoffTarget.update(vorne)
        }

        setupMeetingDetection()

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
                onFinish: { [weak self] tab in self?.finishOnboarding(tab) },
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

    /// Schließt das Onboarding und öffnet das Dashboard auf `tab`.
    ///
    /// Das Ziel kommt von außen, statt hier fest zu stehen: Der Hinweis
    /// „Schon Modelle auf dem Rechner?" will auf der Modelle-Seite landen, und
    /// `openDashboard(_:)` setzt den Tab ohnehin selbst — ein festes
    /// `.aufnahme` überschriebe den Wunsch also sofort wieder. Der normale
    /// Abschluss („Los geht's") übergibt weiterhin `.aufnahme`.
    private func finishOnboarding(_ tab: DashboardModel.Tab) {
        UserDefaults.standard.set(true, forKey: "didCompleteOnboarding")
        UserDefaults.standard.set(true, forKey: "didShowDashboard")
        onboardingWindow?.close()
        onboardingWindow = nil
        openDashboard(tab)
    }

    /// Automatisch gelernt — nur, wenn der Nutzer das will. Der Wächter wird
    /// erst gar nicht gestartet (siehe `stopAndProcess`); diese Abfrage fängt den
    /// Fall ab, dass der Schalter umgelegt wird, während einer noch läuft.
    private func handleLearnedCorrection(wrong: String, right: String) {
        guard UserDefaults.standard.object(forKey: "autoLearnCorrections") as? Bool ?? true else { return }
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
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApp = app
            handoffTarget.update(app)
        }
    }

    /// Eine beendete App ist kein Ziel mehr — sonst bliebe der Ablegen-Knopf auf ihr stehen.
    @objc private func externalAppTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier == lastExternalApp?.processIdentifier else { return }
        lastExternalApp = nil
        handoffTarget.update(nil)
    }

    // MARK: - Meeting-Erkennung

    private func setupMeetingDetection() {
        // Während eines Diktats oder eines schon laufenden Mitschnitts wird nicht
        // gefragt. Der Detektor fragt selbst nach, statt dass jemand ihn umschaltet.
        meetingDetector.isBusy = { [weak self] in
            guard let self else { return true }
            return self.state == .recording || self.state == .working
                || self.meetingRecorder.isRecording || self.meetingPrompt.isVisible
        }
        meetingDetector.onDetected = { [weak self] meeting in self?.meetingDetected(meeting) }
        meetingDetector.onEnded = { [weak self] in self?.meetingEnded() }

        NotificationCenter.default.addObserver(
            forName: .shoutMeetingDetectChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.meetingDetector.apply() }
        }

        // Bei gesperrtem Bildschirm wird die Frage zurückgehalten und beim
        // Entsperren nachgeholt — sofern das Meeting dann noch läuft. Ohne das
        // verstrichen die zwanzig Sekunden der Karte vor einem schwarzen Schirm.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showDeferredMeeting() }
        }
        meetingDetector.apply()
    }

    private func meetingDetected(_ meeting: MeetingDetector.Meeting) {
        guard MeetingDetector.mode != .off else { return }

        // Gesperrt: aufheben statt wegwerfen. Ein Mitschnitt darf trotzdem
        // anlaufen, wenn die Einstellung ausdrücklich „aufnehmen" sagt.
        if MeetingDetector.screenLocked(), MeetingDetector.mode == .ask {
            deferredMeeting = meeting
            return
        }
        offer(meeting)
    }

    /// Nach dem Entsperren: das zurückgehaltene Meeting anbieten, falls es noch läuft.
    private func showDeferredMeeting() {
        guard let meeting = deferredMeeting else { return }
        deferredMeeting = nil
        guard meetingDetector.current == meeting, !meetingRecorder.isRecording else { return }
        offer(meeting)
    }

    private func offer(_ meeting: MeetingDetector.Meeting) {
        let icon = MeetingDetector.hostApp(for: meeting)?.icon
        switch MeetingDetector.mode {
        case .off:
            return
        case .auto:
            startMeetingRecording(meeting, icon: icon)
        case .ask:
            meetingPrompt.ask(
                appName: meeting.name, icon: icon,
                onAccept: { [weak self] in self?.startMeetingRecording(meeting, icon: icon) },
                onDecline: { [weak self] in self?.meetingDetector.decline(meeting) },
                onMute: { [weak self] in self?.meetingDetector.mute(meeting) }
            )
        }
    }

    /// Das erkannte Meeting ist vorbei. Läuft dazu ein Mitschnitt, wird er
    /// gesichert — niemand soll nach dem Meeting merken, dass noch aufgenommen wird.
    private func meetingEnded() {
        if autoMeeting != nil, meetingRecorder.isRecording {
            finishMeetingRecording()
        } else if meetingPrompt.state == .ask {
            meetingPrompt.dismiss()
        }
    }

    /// Startet den Mitschnitt für ein erkanntes Meeting: Mikrofon **und** der Ton
    /// genau dieses Programms — nicht der ganze Systemton, sonst läge die Musik
    /// von nebenan mit in der Datei.
    private func startMeetingRecording(_ meeting: MeetingDetector.Meeting, icon: NSImage?) {
        do {
            try meetingRecorder.start(source: .both, limitedTo: meeting.processObject)
        } catch {
            meetingPrompt.showDone(appName: meeting.name, icon: icon,
                                   message: error.localizedDescription,
                                   onOpen: { [weak self] in self?.openDashboard(.meeting) })
            meetingDetector.decline(meeting)
            return
        }
        autoMeeting = meeting
        // Wer hier einmal aufgenommen hat, kennt den Hinweis — er steht auf der Karte.
        UserDefaults.standard.set(true, forKey: "meetingLegalHintShown")
        sounds.play(.start)
        meetingPrompt.showRecording(appName: meeting.name, icon: icon) { [weak self] in
            self?.finishMeetingRecording()
        }
        let ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.meetingRecorder.isRecording else { return }
                self.meetingPrompt.update(
                    duration: self.meetingRecorder.duration,
                    level: self.meetingRecorder.level,
                    note: self.meetingRecorder.noSignal
                        ? Loc.t("Es kommt kein Ton an. Beim Systemton fehlt dann meist die Erlaubnis: Systemeinstellungen → Datenschutz & Sicherheit → Tonaufnahme.")
                        : nil)
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        meetingTicker = ticker
    }

    /// Stoppt, benennt nach dem Programm („Zoom 2026-09-18 19-23") und reicht die
    /// Datei an dieselbe Warteschlange wie jeder andere Mitschnitt. Kein
    /// Namensdialog: Wer die Karte benutzt, hat das Dashboard nicht offen.
    private func finishMeetingRecording() {
        meetingTicker?.invalidate()
        meetingTicker = nil
        let meeting = autoMeeting
        autoMeeting = nil
        meetingDetector.forgetCurrent()

        guard let url = meetingRecorder.stop() else { meetingPrompt.dismiss(); return }
        let named = MeetingRecorder.rename(
            url, to: "\(meeting?.name ?? Loc.t("Meeting")) \(MeetingRecorder.timestamp())")
        fileQueue.add([named])
        sounds.play(.stop)
        meetingPrompt.showDone(
            appName: meeting?.name ?? Loc.t("Meeting"),
            icon: meeting.flatMap { MeetingDetector.hostApp(for: $0)?.icon },
            message: Loc.t("Wird unter „Meeting“ transkribiert."),
            onOpen: { [weak self] in self?.openDashboard(.meeting) })
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

    /// Läuft gerade ein Ablegen (es wartet, bis ⏎ losgelassen ist)? Dann ignorieren
    /// wir Tastenwiederholungen von ⌘⏎.
    private var handoffRunning = false

    /// Ablegen aus dem Scratchpad: Auswahl oder Notiz formatiert in die App davor.
    /// Die Notiz bleibt. Ohne Bedienungshilfen nur kopieren — mit dem Hinweis wie beim Diktat.
    private func handoffFromScratchpad() {
        guard !handoffRunning else { return }
        // Eine offene Komposition steht erst nach dem Festschreiben im Text der Sitzung.
        scratchpadPanelStorage?.commitComposition()
        guard let session = scratchpadStorage?.active else { return }
        session.flush()
        guard let text = NoteHandoff.content(body: session.note.body, selection: session.lastSelection) else {
            NSSound.beep()
            return
        }
        // Ohne lebendes Ziel nicht still scheitern: der Text liegt dann wenigstens bereit.
        guard let app = lastExternalApp, !app.isTerminated else {
            copyHandoff(text)
            return
        }
        guard AXIsProcessTrusted() else {
            copyHandoff(text)
            warnAboutMissingAccessibility()
            return
        }
        handoffRunning = true
        Task { @MainActor in
            defer { self.handoffRunning = false }
            // Erst loslassen lassen: Wiederholungen von ⌘⏎ gingen sonst nach dem
            // Ausblenden als „Senden“ an die Ziel-App (Slack, Teams, Notion …).
            guard await self.waitForReturnReleased() else {
                self.copyHandoff(text)
                return
            }
            self.scratchpadPanel.hide()
            app.activate()
            try? await Task.sleep(nanoseconds: 250_000_000)
            // ⌘V nur, wenn das Ziel wirklich vorne ist — sonst landet es in irgendeiner App.
            guard !app.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                self.copyHandoff(text)
                return
            }
            self.injector.paste(markdown: text, keepInClipboard: self.keepInClipboard)
        }
    }

    /// Wartet (höchstens 1,5 s), bis ⏎ und ⌘ losgelassen sind. `false`, wenn sie
    /// danach noch gedrückt sind.
    private func waitForReturnReleased() async -> Bool {
        func gehalten() -> Bool {
            CGEventSource.keyState(.combinedSessionState, key: 0x24)   // kVK_Return
                || NSEvent.modifierFlags.contains(.command)
        }
        let ende = Date().addingTimeInterval(1.5)
        while gehalten() {
            if Date() >= ende { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    /// Legt den Text formatiert in die Zwischenablage (vertraulich markiert) und sagt es.
    private func copyHandoff(_ text: String) {
        injector.copyConcealed(markdown: text)
        toast.showInfo(Loc.t("Kopiert. ⌘V setzt den Text ein."))
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

        let padItem = NSMenuItem(title: Loc.t("Scratchpad"), action: #selector(toggleScratchpadFromMenu), keyEquivalent: "")
        padItem.target = self
        menu.addItem(padItem)
        scratchpadMenuItem = padItem
        updateScratchpadMenuItem()

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
            self.transformRunner.isAvailable = ready && self.formattingEnabled
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
                onEngineChanged: { [weak self] purpose in await self?.reloadEngine(for: purpose) },
                onPersistentPillChanged: { [weak self] on in self?.recIndicator.setPersistent(on) },
                onPillPositionChanged: { [weak self] in self?.recIndicator.reposition() },
                files: fileQueue,
                meetingRecorder: meetingRecorder,
                notes: notesPage,
                scratchpadSettings: scratchpadSettings,
                onScratchpadCapture: { [weak self] rolle in self?.beginScratchpadCapture(rolle) },
                noteTools: noteTools,
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
        // Ebenso eine Scratchpad-Taste — sonst blieben beide Tasten abgemeldet.
        if scratchpadSettings.capturing != nil { endScratchpadCapture() }

        let closing = notification.object as? NSWindow
        if closing === correctionWindow { correctionWindow = nil }   // Retention lösen
        if closing === onboardingWindow { onboardingWindow = nil }
        if closing === dashboardWindow { notesPageStorage?.flush() }
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

    /// Läuft noch ein Diktat, wartet das Beenden auf seine Zustellung — sonst wäre ein
    /// Diktat in den Eingang oder eine Notiz still weg. Danach kommen die Prüfungen
    /// in `terminationChecks()`.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Ein zweites Beenden, während das erste noch wartet, ändert nichts.
        guard pendingTermination == nil else { return .terminateCancel }
        switch state {
        case .recording:
            // Was schon gesprochen ist, wird noch erkannt und zugestellt.
            stopAndProcess()
            return waitForDictationThenTerminate()
        case .working:
            return waitForDictationThenTerminate()
        case .loadingModel, .idle, .failed:
            return terminationChecks()
        }
    }

    /// Antwortet AppKit erst, wenn das Diktat zugestellt ist (`dictationProcessingFinished`)
    /// oder `terminationWaitLimit` verstrichen ist (`terminationWaitTimedOut`).
    /// Die Notiz-Prüfungen laufen erst danach, damit sie das Diktat mit sichern.
    private func waitForDictationThenTerminate() -> NSApplication.TerminateReply {
        pendingTermination = DeferredTermination { NSApp.reply(toApplicationShouldTerminate: $0) }
        // `.common`: Solange AppKit auf die Antwort wartet, läuft die Run-Loop im
        // Modal-Modus — ein Zeitgeber nur im Standard-Modus käme nie an.
        let timer = Timer(timeInterval: Self.terminationWaitLimit, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.terminationWaitTimedOut() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingTerminationTimer = timer
        return .terminateLater
    }

    /// Das Diktat ist zugestellt oder gescheitert. Die halbe Sekunde lässt das ⌘V in
    /// die App davor noch abgehen (`TextInjector` sendet es nach 0,06 s und stellt
    /// die Zwischenablage nach 0,41 s wieder her).
    private func dictationProcessingFinished() {
        guard pendingTermination != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.answerPendingTermination() }
        }
    }

    private func answerPendingTermination() {
        pendingTerminationTimer?.invalidate()
        pendingTerminationTimer = nil
        pendingTermination?.resolve { terminationChecks() == .terminateNow }
        pendingTermination = nil
    }

    /// Die Zustellung dauert zu lange (etwa ein hängender Anbieter). Ist der Text
    /// schon erkannt, geht er in die Zwischenablage und den Verlauf. Sonst fragt
    /// die App, statt ihn still zu verlieren.
    private func terminationWaitTimedOut() {
        pendingTerminationTimer = nil
        pendingTermination?.resolve {
            if state == .working, processingText == nil {
                let alert = NSAlert()
                alert.messageText = Loc.t("Ein Diktat wird noch verarbeitet.")
                alert.informativeText = Loc.t("Wenn du jetzt beendest, geht es verloren.")
                alert.addButton(withTitle: Loc.t("Trotzdem beenden"))
                alert.addButton(withTitle: Loc.t("Abbrechen"))
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return false }
            }
            // Auch während des Hinweises kann die Erkennung fertig geworden sein.
            if state == .working, let stand = processingText {
                injector.copyConcealed(stand.text)
                history.add(stand.text, raw: stand.raw)
            }
            return terminationChecks() == .terminateNow
        }
        pendingTermination = nil
    }

    /// Die Prüfungen vor dem Beenden: Notizen, Mitschnitt, Datei-Aufträge.
    /// Gibt nur `.terminateNow` oder `.terminateCancel` zurück.
    private func terminationChecks() -> NSApplication.TerminateReply {
        // Notizen zuerst: Ungesicherter Text aller offenen Notizen (Seite und Panel,
        // höchstens eine Sekunde alt) wird jetzt gesichert. Scheitert das (Platte voll,
        // fremde Änderung nicht lesbar), geht er als Rettungskopie in den App-Support
        // (die Seite zeigt sie danach an). Scheitert auch das, fragt die App nach, statt
        // den Text still zu verlieren. Wird das Beenden abgebrochen und erneut versucht,
        // entsteht für denselben Text keine zweite Kopie.
        // Die Tabs des Panels über das Modell sichern: Es merkt sich dabei auch neue
        // Tabs, die es erst mit dem ersten Sichern als Datei gibt.
        scratchpadStorage?.flushAll()
        if let registry = noteRegistryStorage {
            registry.flushAll()
            let rettung = notesPageStorage?.rescueDirectory ?? NotesPageModel.defaultRescueDirectory
            let ergebnis = registry.writeRescueCopies(in: rettung)
            // Neue Kopien sofort im Hinweis der Seite — falls das Beenden abgebrochen wird.
            if !ergebnis.written.isEmpty { notesPageStorage?.refreshRescuedFiles() }
            if !ergebnis.failed.isEmpty {
                let alert = NSAlert()
                alert.messageText = Loc.t("Eine Notiz konnte nicht gesichert werden.")
                alert.informativeText = Loc.t("Weder im Notizordner noch als Rettungskopie war Platz. Der Text geht beim Beenden verloren.")
                alert.addButton(withTitle: Loc.t("Text kopieren und beenden"))
                alert.addButton(withTitle: Loc.t("Abbrechen"))
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ergebnis.failed.map(\.note.body).joined(separator: "\n\n---\n\n"),
                                               forType: .string)
            }
        }
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
        // Zweite Absicherung: Die Rettung läuft schon in applicationShouldTerminate,
        // hier würde sie nur eine zweite Kopie schreiben.
        noteRegistryStorage?.flushAll()    // Seite und Panel, höchstens eine Sekunde alt
        scratchpadKey.unregister()
        inboxKey.unregister()
        fileQueue.cancelAll()
        meetingTicker?.invalidate()
        meetingTicker = nil
        meetingDetector.stop()      // Core-Audio-Listener sauber abhängen
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

    /// Einmal pro Start: erklärt, warum nichts eingefügt wurde, und führt in die
    /// Systemeinstellungen. Bei jedem Diktat zu fragen wäre eine Plage — der Text
    /// liegt ja in der Zwischenablage.
    private func warnAboutMissingAccessibility() {
        guard !warnedAboutAccessibility else { return }
        warnedAboutAccessibility = true
        let alert = NSAlert()
        alert.messageText = Loc.t("Einfügen braucht die Bedienungshilfen.")
        alert.informativeText = Loc.t("Der Text liegt in der Zwischenablage — ⌘V setzt ihn ein. Damit shout. das selbst kann, muss es unter „Bedienungshilfen“ freigegeben sein.")
        alert.addButton(withTitle: Loc.t("Einstellungen öffnen"))
        alert.addButton(withTitle: Loc.t("Später"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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

    /// Lädt die Engine eines Schrittes neu, nachdem sich die Anbieter-Einstellung
    /// geändert hat — Umschalten zwischen „auf diesem Gerät" und „Anbieter", ein
    /// anderer Anbieter, ein neuer Schlüssel, ein anderes Modell.
    ///
    /// Dieselben Schutzbedingungen wie beim Modellwechsel: nicht während einer
    /// Aufnahme und nicht während einer laufenden Datei-Transkription, sonst
    /// zieht es das Modell unter der laufenden Arbeit weg.
    ///
    /// Ein Fehlschlag wird hier NICHT zurückgerollt. Der Grund ist der
    /// Unterschied zum Modellwechsel: Dort bedeutet ein Fehler „Download
    /// misslungen", und das alte Modell liegt noch da. Hier ist die Einstellung
    /// die Absicht des Nutzers, und ob sie funktioniert, sagt ihm der
    /// Verbindungstest im Anbieter-Block. Stillschweigend zurückzuschalten wäre
    /// verwirrender als eine Einstellung, die noch nicht trägt — beim Diktat
    /// kommt ohnehin der Rohtext, nichts geht verloren.
    private func reloadEngine(for purpose: EnginePurpose) async {
        guard state == .idle || state == .failed else {
            dashboardModel.modelNote = Loc.t("Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen oder verarbeitet wird.")
            return
        }
        guard !fileQueue.isRunning else {
            dashboardModel.modelNote = Loc.t("Transkription läuft — Modellwechsel ist erst danach möglich.")
            return
        }
        dashboardModel.modelNote = nil

        switch purpose {
        case .text:
            guard dashboardModel.formatLoadingID == nil else { return }
            await formatter.reload(onProgress: formatProgressHandler())
            dashboardModel.formatterReady = await formatter.isReady
            updateFormatterMenu()
        case .audio:
            guard dashboardModel.asrLoadingID == nil else { return }
            state = .loadingModel
            try? await transcriber.reload(onProgress: asrProgressHandler())
            let ready = await transcriber.isReady
            dashboardModel.transcriberReady = ready
            dashboardModel.asrLoadFailed = !ready
            state = ready ? .idle : .failed
        }
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
            // Global: Ereignisse für andere Apps. Lokal: für shout. selbst.
            if let m = NSEvent.addGlobalMonitorForEvents(matching: matching, handler: { [weak self] event in
                self?.route(event, local: false)
            }) { eventMonitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: matching, handler: { [weak self] event in
                self?.route(event, local: true)
                return event
            }) { eventMonitors.append(m) }
        }
    }

    private func route(_ event: NSEvent, local: Bool) {
        // Selbst erzeugte ⌘V-Events (TextInjector) ignorieren — sonst kann das
        // Einfügen eines Diktats den eigenen Hotkey erneut auslösen.
        if let cg = event.cgEvent,
           cg.getIntegerValueField(.eventSourceUserData) == TextInjector.syntheticEventTag {
            return
        }
        switch event.type {
        case .flagsChanged: handleFlagsChanged(event, local: local)
        case .keyDown: handleKeyDown(event, local: local)
        case .keyUp: handleKeyUp(event)
        default: break
        }
    }

    private func handleKeyDown(_ event: NSEvent, local: Bool) {
        // Auto-Repeat der gehaltenen Taste ignorieren (sonst togglet der Toggle-Modus
        // im Sekundentakt und feste Shortcuts feuern mehrfach).
        guard !event.isARepeat else { return }

        // Eine Scratchpad-Taste wird nur aus shout. selbst aufgenommen. Ein Druck in
        // einer anderen App (⌥L für „@“ in Mail) würde sonst angemeldet und danach
        // systemweit verschluckt. Fremde Ereignisse laufen normal weiter.
        if local, NSApp.isActive, let rolle = scratchpadSettings.capturing {
            captureScratchpadKey(event, rolle: rolle)
            return
        }

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
        let echte = mods.intersection([.command, .option, .control, .shift])
        for rolle in ScratchpadSettings.Role.allCases {
            if let kombi = scratchpadSettings.combo(for: rolle), kombi.keyCode == keyCode, kombi.flags == echte {
                return true
            }
        }
        return false
    }

    /// Funktionstasten F1–F12 (dürfen als eigenständiger Hotkey ohne Modifier dienen).
    private static let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
    private static func isFunctionKey(_ keyCode: UInt16) -> Bool { functionKeyCodes.contains(keyCode) }

    private func handleKeyUp(_ event: NSEvent) {
        guard !isCapturingHotkey else { return }
        if settings.matchesKeyUp(event) { handleTrigger(down: false) }
    }

    private func handleFlagsChanged(_ event: NSEvent, local: Bool) {
        if isCapturingHotkey {
            handleCaptureFlagsChanged(event)
            return
        }
        guard let pressed = settings.modifierPressed(in: event) else { return }
        if pressed {
            // Während eine Scratchpad-Taste aufgenommen wird, gehört die ⌥ zur neuen
            // Kombination und startet kein Diktat — in shout. selbst, nicht anderswo.
            guard !local || scratchpadSettings.capturing == nil else { return }
            dictationModifierDownAt = ProcessInfo.processInfo.systemUptime
            dictationModifierClaimed = false
            let vorher = state
            handleTrigger(down: true)
            recordingStartedByModifierPress = vorher != .recording && state == .recording
        } else {
            let beansprucht = dictationModifierClaimed
            dictationModifierDownAt = nil
            dictationModifierClaimed = false
            recordingStartedByModifierPress = false
            // Gehörte der Druck zu einer Scratchpad- oder Eingangs-Taste, beendet das
            // Loslassen nichts — sonst stoppte es deren Diktat vorzeitig.
            if !beansprucht { handleTrigger(down: false) }
        }
    }

    /// Ist die Diktiertaste eine reine Modifier-Taste, die auch in einer
    /// Scratchpad-Kombination vorkommt (rechte ⌥ in ⌃⌥N), meldet `flagsChanged`
    /// sie schon vor dem N — im Halten- und Umschalten-Modus läuft dann bereits
    /// eine Aufnahme in die App davor, und das Halten der Scratchpad-Taste fände
    /// `state != .idle` vor. Kommt die Carbon-Taste im selben Druck an, gehört der
    /// Druck ihr: Eine eben erst (vor weniger als `claimWindow`) von genau diesem
    /// Druck gestartete Aufnahme wird ohne Ton verworfen — egal mit welchem Ziel:
    /// Hat das Panel den Fokus, zielt sie auf die Notiz und liefe sonst nach dem
    /// Ausblenden unbemerkt weiter (das Loslassen der ⌥ ist ja beansprucht), bzw.
    /// ⌃⌥I schriebe in die Notiz statt in den Eingang. Gesprochen wurde in
    /// diesem Bruchteil noch nichts. Außerdem wird ein wartender Doppeltipp
    /// zurückgesetzt, und das Loslassen der ⌥ beendet danach nichts. Eine länger laufende Aufnahme
    /// bleibt unberührt: Dann diktiert der Nutzer schon, und nichts wird verworfen.
    private func claimDictationModifierPress() {
        guard settings.isModifierOnly, let seit = dictationModifierDownAt, !dictationModifierClaimed else { return }
        let jetzt = ProcessInfo.processInfo.systemUptime
        guard jetzt - seit < Self.claimWindow else { return }
        dictationModifierClaimed = true
        if recordingStartedByModifierPress, state == .recording {
            discardRecordingSilently()
        }
        recordingStartedByModifierPress = false
        if armedTimer != nil {
            disarmPill()
            if state == .idle { recIndicator.finish() }
        }
        if settings.mode == .doubleTap { doubleTap = DoubleTapDetector() }
    }

    /// Wie lange nach dem Druck der Modifier-Diktiertaste eine Scratchpad-Taste
    /// ihn noch für sich beanspruchen darf.
    private static let claimWindow: TimeInterval = 1.0

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

    // MARK: - Scratchpad-Tasten

    private func setupScratchpad() {
        scratchpadKey.onPress = { [weak self] in self?.scratchpadKeyDown() }
        scratchpadKey.onRelease = { [weak self] in self?.scratchpadKeyUp() }
        inboxKey.onPress = { [weak self] in self?.inboxKeyDown() }
        inboxKey.onRelease = { [weak self] in self?.inboxKeyUp() }
        scratchpadSettings.onChange = { [weak self] in self?.applyScratchpadHotkeys() }
        applyScratchpadHotkeys()
        // Wer während der Tastenaufnahme in eine andere App wechselt, hat sie
        // vergessen: beenden, damit beide Tasten wieder angemeldet sind.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification, object: nil
        )
    }

    @objc private func appDidResignActive(_ notification: Notification) {
        scratchpadSettings.cancelCapture()     // meldet über onChange neu an
    }

    /// Meldet beide Tasten neu an. Während eine aufgenommen wird, bleiben sie
    /// abgemeldet — sonst finge Carbon die alte Kombination ab.
    private func applyScratchpadHotkeys() {
        scratchpadKey.unregister()
        inboxKey.unregister()
        var probleme: [ScratchpadSettings.Role: String] = [:]
        if scratchpadSettings.isEnabled, scratchpadSettings.capturing == nil {
            for (rolle, taste) in [(ScratchpadSettings.Role.scratchpad, scratchpadKey), (.inbox, inboxKey)] {
                guard let kombi = scratchpadSettings.combo(for: rolle) else { continue }
                do {
                    try taste.register(kombi)
                } catch GlobalHotkey.RegistrationError.taken {
                    probleme[rolle] = Loc.t("Von einer anderen App belegt")
                } catch {
                    probleme[rolle] = Loc.t("Konnte nicht angemeldet werden")
                }
            }
        }
        if !scratchpadSettings.isEnabled { scratchpadPanelStorage?.hide() }
        scratchpadSettings.registrationProblems = probleme
        updateScratchpadMenuItem()
    }

    private func scratchpadKeyDown() {
        claimDictationModifierPress()
        scratchpadPress.press(at: ProcessInfo.processInfo.systemUptime)
        scratchpadHoldTimer?.invalidate()
        scratchpadHoldTimer = Timer.scheduledTimer(withTimeInterval: HotkeyPressClassifier.holdThreshold,
                                                   repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.scratchpadPress.tick(at: ProcessInfo.processInfo.systemUptime) == .holdBegan {
                    self.beginScratchpadDictation()
                }
            }
        }
    }

    private func scratchpadKeyUp() {
        scratchpadHoldTimer?.invalidate()
        scratchpadHoldTimer = nil
        switch scratchpadPress.release(at: ProcessInfo.processInfo.systemUptime) {
        case .tap:
            scratchpadPanel.toggle()
        case .holdEnded:
            if state == .recording, case .scratchpad = dictationTarget { stopAndProcess() }
        case .holdBegan, nil:
            break
        }
    }

    /// Halten der Scratchpad-Taste: Panel auf, Diktat in den vorderen Tab — oder
    /// in einen neuen, wenn der vordere schon Text hat.
    private func beginScratchpadDictation() {
        guard state == .idle else { return }
        scratchpadPanel.show(focus: false)
        guard let tab = scratchpad.tabForDictation(newIfActiveHasText: true) else { return }
        // Gehalten: Das Loslassen stoppt, nicht eine Pause (wie im Halten-Modus).
        startRecording(target: .scratchpad(noteID: tab.id), held: true)
    }

    /// Mikrofon-Knopf im Panel: in den vorderen Tab diktieren bzw. das Diktat beenden.
    private func toggleScratchpadMic() {
        if state == .recording, case .scratchpad = dictationTarget {
            stopAndProcess()
            return
        }
        guard state == .idle, let tab = scratchpad.tabForDictation(newIfActiveHasText: false) else { return }
        startRecording(target: .scratchpad(noteID: tab.id))
    }

    /// „Per Sprache …“ im Zauberstab: nimmt die Anweisung mit der Pille auf.
    /// Läuft schon eine Aufnahme oder Verarbeitung (auch eine Anweisung), wird nichts
    /// umgewidmet: Der Druck auf eine andere Taste ändert das Ziel einer laufenden
    /// Aufnahme nie, hier ebenso wenig.
    private func beginVoiceInstruction(for session: NoteEditorSession) {
        guard state == .idle, !session.isTransforming else {
            NSSound.beep()
            return
        }
        startRecording(target: .instruction(noteID: session.id))
    }

    /// Eingangs-Taste: folgt dem Modus der Diktiertaste. Doppeltipp gibt es für
    /// Carbon-Tasten nicht; dort gilt wie bei „Umschalten“: Tippen startet, erneutes Tippen stoppt.
    private func inboxKeyDown() {
        claimDictationModifierPress()
        switch settings.mode {
        case .hold:
            if state == .idle { startRecording(target: .inbox) }
        case .toggle, .doubleTap:
            if state == .idle {
                startRecording(target: .inbox)
            } else if state == .recording, dictationTarget == .inbox {
                stopAndProcess()
            }
        }
    }

    private func inboxKeyUp() {
        guard settings.mode == .hold, state == .recording, dictationTarget == .inbox else { return }
        stopAndProcess()
    }

    // MARK: - Scratchpad-Tasten aufnehmen (aus den Einstellungen)

    func beginScratchpadCapture(_ rolle: ScratchpadSettings.Role) {
        scratchpadSettings.capturing = rolle
        scratchpadSettings.captureHint = nil
        applyScratchpadHotkeys()
    }

    private func endScratchpadCapture() {
        scratchpadSettings.capturing = nil
        scratchpadSettings.captureHint = nil
        applyScratchpadHotkeys()
    }

    private func captureScratchpadKey(_ event: NSEvent, rolle: ScratchpadSettings.Role) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53, mods.isEmpty {    // Esc bricht ab
            endScratchpadCapture()
            return
        }
        let kombi = HotkeyCombo(keyCode: event.keyCode, flags: mods)
        let diktat = (keyCode: settings.keyCode, modifiers: settings.modifiers, isModifierOnly: settings.isModifierOnly)
        if let grund = scratchpadSettings.rejection(for: kombi, role: rolle, dictationKey: diktat) {
            scratchpadSettings.captureHint = grund
            return
        }
        scratchpadSettings.capturing = nil
        scratchpadSettings.captureHint = nil
        scratchpadSettings.setCombo(kombi, for: rolle)     // meldet über onChange neu an
    }

    // MARK: - Menüeintrag

    @objc private func toggleScratchpadFromMenu() { scratchpadPanel.toggle() }

    private func updateScratchpadMenuItem() {
        guard let eintrag = scratchpadMenuItem else { return }
        eintrag.isHidden = !scratchpadSettings.isEnabled
        let name = scratchpadSettings.combo(for: .scratchpad).map { RecordingSettings.keyName(forKeyCode: $0.keyCode) } ?? ""
        if let kombi = scratchpadSettings.combo(for: .scratchpad), name.count == 1 {
            eintrag.keyEquivalent = name.lowercased()
            eintrag.keyEquivalentModifierMask = kombi.flags
        } else {
            eintrag.keyEquivalent = ""
        }
    }

    // MARK: - Aufnahme-Steuerung

    /// `held`: Die auslösende Taste wird gehalten (Scratchpad-Taste halten) — dann
    /// stoppt ihr Loslassen, nie der Auto-Stopp, unabhängig vom Modus der Diktiertaste.
    private func startRecording(target explizit: DictationTarget? = nil, held: Bool = false) {
        // Das Beenden wartet gerade auf ein Diktat — ein neues ginge dabei verloren.
        guard pendingTermination == nil else { return }
        disarmPill()
        // Ziel-App merken, solange sie noch im Vordergrund ist. Das Panel ist
        // nicht aktivierend — hat es den Fokus, ist die App davor trotzdem vorne.
        let vorne = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        dictationTarget = explizit ?? DictationTarget.forDictationKey(
            panelIsKey: scratchpadPanelStorage?.isKey == true,
            activeNote: scratchpadStorage?.active?.id,
            frontBundleID: vorne)
        // Aktuelles Mikrofon aus den Einstellungen (Menü oder Dashboard) übernehmen.
        let micUID = UserDefaults.standard.string(forKey: micUIDKey)
        recorder.preferredDeviceUID = (micUID?.isEmpty == false) ? micUID : nil
        // Auto-Stopp nur sinnvoll, wenn die Taste nicht gehalten wird — im
        // Halten-Modus stoppt ja das Loslassen.
        recorder.autoStopEnabled = (settings.mode != .hold && !held && settings.autoStop)
        recorder.silenceSeconds = settings.silenceSeconds
        do {
            try recorder.start()
            state = .recording
            recIndicator.show()
            if case .scratchpad = dictationTarget { scratchpadMic.isRecording = true }
            sounds.play(.start)
        } catch {
            sounds.play(.error)
            NSLog("Aufnahme-Start fehlgeschlagen: \(error)")
        }
    }

    /// Wie `cancelRecording()`, aber ohne Ton: für eine Aufnahme, die nur
    /// Sekundenbruchteile lief und nie gemeint war (siehe `claimDictationModifierPress()`).
    private func discardRecordingSilently() {
        _ = recorder.stop()
        scratchpadMic.isRecording = false
        state = .idle
        recIndicator.finish()
    }

    /// Bricht eine laufende Aufnahme ab: Samples verwerfen, nichts transkribieren.
    private func cancelRecording() {
        _ = recorder.stop()      // Aufnahme beenden, Samples verwerfen
        scratchpadMic.isRecording = false
        state = .idle
        recIndicator.finish()    // zurück zur Idle-Pille bzw. ausblenden
        sounds.play(.error)      // dezenter „verworfen"-Ton
    }

    private func stopAndProcess() {
        scratchpadMic.isRecording = false
        let samples = recorder.stop()
        // Pille bleibt sichtbar und wechselt in die „Verarbeiten"-Animation,
        // bis der fertige Text eingefügt ist.
        recIndicator.showProcessing()
        sounds.play(.stop)
        state = .working
        let ziel = dictationTarget
        // Notizen bekommen den neutralen Ton der Aufbereitung.
        let bundleID = ziel.formatterBundleID
        // Eine Anweisung wird weder aufbereitet noch nach Sprachbefehlen durchsucht.
        let useFormatting = formattingEnabled && !ziel.isInstruction
        let useCommands = UserDefaults.standard.bool(forKey: "speechCommandsEnabled") && !ziel.isInstruction

        Task {
            defer {
                processingText = nil
                state = .idle
                recIndicator.finish()
                // Wartet ein Beenden auf dieses Diktat, darf es jetzt weiter.
                dictationProcessingFinished()
            }
            guard !samples.isEmpty else { return }
            do {
                let raw = try await transcriber.transcribe(samples)
                var output = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else { return }

                // Gesprochene Befehle („Komma", „neue Zeile" …) vor der Formatierung anwenden.
                if useCommands { output = SpeechCommands.apply(to: output) }
                // Eine Anweisung ist kein Diktat: Beim Beenden gehört sie nicht in den Verlauf.
                if !ziel.isInstruction { processingText = (output, raw) }

                if useFormatting {
                    output = await formatter.format(output, bundleID: bundleID, termHint: dictionary.termHint)
                }
                // Gelernte/manuelle Korrekturen als letztes anwenden — sie gewinnen immer.
                output = dictionary.applyCorrections(to: output)

                let final = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty else { return }
                deliver(final, raw: raw, to: ziel, seconds: Double(samples.count) / 16_000.0)
            } catch {
                sounds.play(.error)
                NSLog("Verarbeitung fehlgeschlagen: \(error)")
                rescueRecording(samples, after: error)
            }
        }
    }

    /// Bringt ein fertiges Diktat an sein Ziel. Verlauf und Statistik zählen jedes.
    ///
    /// Kein Text geht still verloren: Nimmt die Notiz oder der Eingang ihn nicht an,
    /// liegt er in der Zwischenablage, ein Hinweis sagt das, und der Verlauf hat ihn auch.
    private func deliver(_ final: String, raw: String, to ziel: DictationTarget, seconds: Double) {
        switch ziel {
        case .frontApp:
            // Ohne Bedienungshilfen-Freigabe kommt das synthetische ⌘V
            // nirgends an — bis hierher war das Diktat danach spurlos weg.
            // Stattdessen: in die Zwischenablage legen und einmal pro Start
            // sagen, woran es liegt.
            guard AXIsProcessTrusted() else {
                injector.copyConcealed(final)
                lastInsertedText = final
                history.add(final, raw: raw)
                sounds.play(.error)
                warnAboutMissingAccessibility()
                return
            }
            injector.paste(final, keepInClipboard: keepInClipboard)
            sounds.play(.done)
            lastInsertedText = final
            // Rohtext mitgeben: Im Verlauf lässt sich so nachsehen, was die
            // Spracherkennung WIRKLICH geliefert hat — unverzichtbar, um
            // fehlenden Inhalt der richtigen Stufe zuzuordnen (Whisper vs.
            // Aufbereitung).
            history.add(final, raw: raw)
            let words = final.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
            stats.record(words: words, seconds: seconds)

            // Kurz warten, bis das Einfügen im Zielfeld angekommen ist, dann das
            // Feld beobachten, um manuelle Korrekturen automatisch zu lernen.
            // Abgeschaltet heißt abgeschaltet: Dann entsteht auch kein
            // AXObserver auf dem fremden Textfeld.
            if UserDefaults.standard.object(forKey: "autoLearnCorrections") as? Bool ?? true {
                let inserted = final
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    self.correctionWatcher.begin(inserted: inserted)
                }
            }
        case .scratchpad(let id):
            if scratchpad.insertDictation(final, into: id) {
                sounds.play(.done)
            } else {
                injector.copyConcealed(final)
                sounds.play(.error)
                toast.showInfo(Loc.t("Die Notiz nimmt gerade nichts an. Der Text liegt in der Zwischenablage."))
            }
            recordDelivered(final, raw: raw, seconds: seconds)
        case .inbox:
            if scratchpad.appendToInbox(final) {
                sounds.play(.done)
                toast.showInfo(Loc.t("Im Eingang notiert"), actionTitle: Loc.t("Öffnen")) { [weak self] in
                    guard let self else { return }
                    self.scratchpadPanel.show(focus: true)
                    self.scratchpad.openInbox()
                }
            } else {
                injector.copyConcealed(final)
                sounds.play(.error)
                toast.showInfo(Loc.t("Der Eingang ist gerade nicht erreichbar. Der Text liegt in der Zwischenablage."))
            }
            recordDelivered(final, raw: raw, seconds: seconds)
        case .instruction(let id):
            // Eine Anweisung, kein Diktat: nicht in den Verlauf, nicht in die Statistik.
            guard !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard let session = noteRegistryStorage?.session(id: id) else {
                injector.copyConcealed(final)
                sounds.play(.error)
                toast.showInfo(Loc.t("Die Notiz ist nicht mehr offen. Die Anweisung liegt in der Zwischenablage."))
                return
            }
            // Startet sie nicht (Grund steht im Balken), bleibt sie unter „Zuletzt“.
            sounds.play(transformRunner.runInstruction(final, on: session) != nil ? .done : .error)
        }
    }

    private func recordDelivered(_ final: String, raw: String, seconds: Double) {
        lastInsertedText = final
        history.add(final, raw: raw)
        let woerter = final.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
        stats.record(words: woerter, seconds: seconds)
    }

    /// Rettet eine Aufnahme, deren Erkennung gescheitert ist, in die
    /// Datei-Warteschlange.
    ///
    /// Der Fall, für den das gebaut ist: Die Transkription läuft bei einem
    /// Anbieter, der Aufruf scheitert (Netz weg, Guthaben leer), und es liegt
    /// kein lokales Modell auf der Platte, das einspringen könnte. Ohne diese
    /// Rettung wäre die Aufnahme weg — anders als bei der Aufbereitung, wo immer
    /// noch der Rohtext bleibt, gibt es hier nichts, was man einfügen könnte.
    ///
    /// Auf der Platte landet WAV: Es braucht keinen Encoder, und die
    /// Warteschlange dekodiert es ohnehin wieder zu denselben Samples. Eine
    /// Minute sind knapp 2 MB — für eine Handvoll gescheiterter Diktate
    /// verschmerzbar, und der Nutzer sieht sie in der Liste und kann sie löschen.
    ///
    /// Nur bei externer Erkennung: Läuft lokal etwas schief, ist es kein
    /// vorübergehender Zustand, den ein zweiter Versuch heilt.
    private func rescueRecording(_ samples: [Float], after error: Error) {
        guard case .remote = EngineSelection.decide(for: .audio) else { return }
        guard !samples.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let name = "Diktat \(formatter.string(from: Date())).wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        do {
            try WAVEncoder.data(from: samples).write(to: url)
        } catch {
            NSLog("Aufnahme konnte nicht gesichert werden: \(error)")
            return
        }
        // `start: false` — nicht sofort loslaufen: Die Ursache (kein Guthaben,
        // Netz weg) besteht meist noch. Der Auftrag liegt bereit und der Nutzer
        // startet ihn, wenn es wieder geht.
        fileQueue.add([url], start: false)
        dashboardModel.modelNote = Loc.t("Die Erkennung ist fehlgeschlagen. Die Aufnahme liegt unter „Dateien“ und lässt sich dort erneut versuchen.")
    }
}

extension UserDefaults {
    /// KVO-Zugang zum Schlüssel „formattingEnabled“ (Name muss dem Schlüssel entsprechen).
    @objc dynamic var formattingEnabled: Bool { bool(forKey: "formattingEnabled") }
}
