import AppKit
import ApplicationServices

/// Beobachtet nach dem Einfügen das fokussierte Textfeld (über die
/// Accessibility-API) und erkennt, wenn der Nutzer darin ein Wort korrigiert.
///
/// Ablauf:
///  1. `begin(inserted:)` merkt sich das fokussierte AXUIElement + seinen aktuellen
///     Inhalt (Baseline, direkt nach dem Einfügen).
///  2. Ein AXObserver lauscht auf Wertänderungen. Nach kurzer Ruhe (Debounce)
///     wird Baseline mit dem neuen Inhalt Wort für Wort verglichen.
///  3. Genau ein ausgetauschtes Wort → `onLearn(falsch, richtig)`.
///
/// Funktioniert nur, wo die App ihren Textinhalt über Accessibility preisgibt
/// (native Felder, Mail, Notes … ja; manche Web-/Electron-Felder, Terminal nein).
@MainActor
final class CorrectionWatcher {

    var onLearn: ((_ wrong: String, _ right: String) -> Void)?

    private var observer: AXObserver?
    private var element: AXUIElement?
    private var baseline = ""
    private var debounceTimer: Timer?
    private var lifetimeTimer: Timer?

    /// Startet die Beobachtung des aktuell fokussierten Feldes.
    func begin(inserted: String) {
        stop()
        guard AXIsProcessTrusted() else {
            NSLog("SHOUT-LEARN: Accessibility nicht erlaubt")
            return
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            NSLog("SHOUT-LEARN: kein fokussiertes UI-Element")
            return
        }
        let el = focused as! AXUIElement

        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        let appID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unbekannt"

        guard let value = Self.stringValue(of: el) else {
            NSLog("SHOUT-LEARN: %@ gibt keinen Text ueber Accessibility preis -> Lernen hier nicht moeglich", appID)
            return
        }
        element = el
        baseline = value

        guard pid != 0 else { return }
        NSLog("SHOUT-LEARN: beobachte %@ (Textlaenge %d)", appID, value.count)

        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<CorrectionWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.scheduleEvaluation()
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        observer = obs

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, el, kAXValueChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)

        // Nach 90 s ist eine Korrektur unwahrscheinlich → Beobachtung beenden.
        lifetimeTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    func stop() {
        debounceTimer?.invalidate(); debounceTimer = nil
        lifetimeTimer?.invalidate(); lifetimeTimer = nil
        if let observer, let element {
            AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        element = nil
        baseline = ""
    }

    // MARK: - Auswertung

    /// Wird bei jeder Wertänderung aufgerufen; debounced, damit Tippen Zeichen für
    /// Zeichen nicht als viele Mini-Änderungen zählt.
    private func scheduleEvaluation() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    private func evaluate() {
        guard let element, let current = Self.stringValue(of: element), current != baseline else { return }
        if let (wrong, right) = Self.detectSingleWordCorrection(from: baseline, to: current) {
            NSLog("SHOUT-LEARN: Einzelwort-Korrektur erkannt (Längen \(wrong.count)→\(right.count))")
            onLearn?(wrong, right)
        } else {
            NSLog("SHOUT-LEARN: Änderung erkannt, aber keine eindeutige Einzelwort-Korrektur → nichts gelernt")
        }
        // Baseline nachziehen, damit eine weitere Korrektur erkannt werden kann.
        baseline = current
    }

    // MARK: - Helfer

    private static func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Erkennt genau eine Wort-Ersetzung (gleiche Wortanzahl, ein Token verschieden).
    /// Konservativ, um Fehltreffer zu vermeiden — das Popup mit Rückgängig fängt Reste.
    static func detectSingleWordCorrection(from old: String, to new: String) -> (String, String)? {
        let oldWords = old.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        let newWords = new.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        guard oldWords.count == newWords.count else { return nil }

        var changed: [(String, String)] = []
        for (a, b) in zip(oldWords, newWords) where a != b { changed.append((a, b)) }
        guard changed.count == 1 else { return nil }

        let wrong = changed[0].0.trimmingCharacters(in: .punctuationCharacters)
        let right = changed[0].1.trimmingCharacters(in: .punctuationCharacters)
        guard wrong.count >= 2, right.count >= 2,
              wrong.lowercased() != right.lowercased() else { return nil }
        return (wrong, right)
    }
}
