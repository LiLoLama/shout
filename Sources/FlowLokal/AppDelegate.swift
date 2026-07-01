import AppKit
import AVFoundation
import ApplicationServices

/// Verdrahtet die v0-Kernschleife:
///   Hotkey (Right ⌥ halten) → Aufnahme → WhisperKit → Text an Cursor einfügen.
///
/// Bewusst simpel gehalten: kein VAD, kein Formatting-LLM, kein Kontext.
/// Das sind die nächsten Ausbaustufen (siehe README).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Zustand

    enum State {
        case loadingModel
        case idle
        case recording
        case transcribing
    }

    private var state: State = .loadingModel {
        didSet { updateStatusItem() }
    }

    // MARK: - Komponenten

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let injector = TextInjector()

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// keyCode der rechten Wahltaste (⌥) auf macOS.
    private let rightOptionKeyCode: UInt16 = 61

    // MARK: - App-Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        requestPermissions()
        installHotkeyMonitors()
        loadModel()
    }

    // MARK: - Menu-Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Modell wird geladen …", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Rechte ⌥-Taste halten zum Diktieren", action: nil, keyEquivalent: "")
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q")
        )
        statusItem.menu = menu
        updateStatusItem()
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
        case .transcribing:
            button.title = "✍️"
            statusMenuItem?.title = "Transkribiere …"
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Rechte / Permissions

    private func requestPermissions() {
        // Mikrofon: löst den TCC-Dialog aus (NSMicrophoneUsageDescription muss in Info.plist stehen).
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // Accessibility: nötig für globales Tasten-Monitoring UND für das Einfügen via ⌘V.
        // Der Prompt schickt den Nutzer in die Systemeinstellungen.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Modell laden

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

    // MARK: - Hotkey

    private func installHotkeyMonitors() {
        // Global: greift, wenn eine andere App im Vordergrund ist (braucht Accessibility).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        // Local: greift, wenn unsere App selbst aktiv wäre.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard event.keyCode == rightOptionKeyCode else { return }
        let isKeyDown = event.modifierFlags.contains(.option)

        if isKeyDown, state == .idle {
            startRecording()
        } else if !isKeyDown, state == .recording {
            stopAndTranscribe()
        }
    }

    // MARK: - Aufnahme-Steuerung

    private func startRecording() {
        do {
            try recorder.start()
            state = .recording
        } catch {
            NSLog("Aufnahme-Start fehlgeschlagen: \(error)")
        }
    }

    private func stopAndTranscribe() {
        let samples = recorder.stop()
        state = .transcribing

        Task {
            defer { state = .idle }
            guard !samples.isEmpty else { return }
            do {
                let text = try await transcriber.transcribe(samples)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                injector.insert(trimmed)
            } catch {
                NSLog("Transkription fehlgeschlagen: \(error)")
            }
        }
    }
}
