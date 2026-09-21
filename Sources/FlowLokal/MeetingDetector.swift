#if os(macOS)
import AppKit
import CoreAudio
import CoreMediaIO
import Foundation

extension Notification.Name {
    /// Die Einstellung „Meetings erkennen" wurde geändert — der Detektor muss
    /// sich neu ausrichten (Listener anhängen oder abbauen).
    static let shoutMeetingDetectChanged = Notification.Name("shout.meetingDetectChanged")
}

/// Merkt von selbst, dass ein Online-Meeting läuft, damit shout. einen Mitschnitt
/// anbieten kann.
///
/// **Das Signal ist der Ausgabestrom, nicht das Mikrofon.** Das ist der Kern
/// dieser Datei, und es ist gegen die Intuition, also hier der Grund:
///
///  1. Das Mikrofon läuft auf einem Mac mit „Hey Siri" **dauerhaft** —
///     `com.apple.CoreSpeech` hält den Eingabestrom offen, rund um die Uhr. Ein
///     Mikro-Auslöser feuerte im Leerlauf.
///  2. Man sitzt oft **stumm** in einem Meeting und will es trotzdem
///     mitschneiden, weil andere reden. Das Mikrofon weiß davon nichts.
///
/// `kAudioProcessPropertyIsRunningOutput` hängt am **offenen Strom, nicht am
/// hörbaren Ton** (nachgemessen: eine Engine, die nur Stille ausgibt, meldet
/// durchgehend 1). Eine Gesprächspause setzt die Erkennung also nicht zurück.
/// Ein echtes Zoom-Meeting stand damit 77 Sekunden ohne ein einziges Flackern da,
/// über Stummschaltung und Pausen hinweg; zwei Sekunden nach dem Verlassen war
/// der Prozess aus der Liste verschwunden.
///
/// **Beobachtet wird über Umwege.** Listener auf `IsRunningOutput` selbst
/// registrieren sich mit `noErr` und feuern nie (Regression seit macOS 26,
/// bestätigt auf 27.0). Zuverlässig feuern nur
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` am Standard-Ausgabegerät und
/// die Prozessliste — Letztere doppelt und zu früh, weil das Prozessobjekt vor
/// dem IO-Start entsteht. Beide dienen deshalb nur als **Wecker**; danach wird
/// eine begrenzte Zeit lang einmal pro Sekunde nachgelesen. Im Ruhezustand läuft
/// kein Timer.
///
/// Gelesen werden ausschließlich Statusflags und Bundle-IDs. Das braucht **keine
/// Berechtigung** (nachgewiesen mit einem unsignierten Programm ohne
/// TCC-Eintrag) und es verlässt nichts das Gerät.
@MainActor
final class MeetingDetector: ObservableObject {

    /// Ein laufendes Meeting: welches Programm, welcher Prozess.
    struct Meeting: Equatable {
        /// Das Präfix aus der Tabelle, nicht die volle Bundle-ID des Helfers.
        let prefix: String
        let name: String
        let pid: pid_t
        /// Für den Tap: So lässt sich genau dieser Prozess abgreifen, statt
        /// global alles mitzunehmen.
        let processObject: AudioObjectID
    }

    enum Mode: String { case off, ask, auto }

    /// Programme, deren Ausgabestrom ein Meeting bedeutet.
    ///
    /// Verglichen wird das **Präfix**, weil der Ton im Helfer laufen kann:
    /// `us.zoom.caphost` steht neben `us.zoom.xos`.
    ///
    /// Browser stehen bewusst NICHT hier. Safari spielt über
    /// `com.apple.WebKit.GPU` — ein Prozess, den sich jede WebKit-App teilt, also
    /// nicht zuzuordnen. Und ein Meet-Call in Chrome sieht von außen aus wie ein
    /// YouTube-Tab. Lieber nicht erkennen als bei jedem Video fragen.
    static let known: [(prefix: String, name: String)] = [
        ("us.zoom", "Zoom"),
        ("com.microsoft.teams", "Microsoft Teams"),
        ("com.microsoft.SkypeForBusiness", "Skype for Business"),
        ("Cisco-Systems.Spark", "Webex"),
        ("com.cisco.webexmeetingsapp", "Webex"),
        ("com.webex.meetingmanager", "Webex"),
        ("com.skype.skype", "Skype"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.hnc.Discord", "Discord"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("org.jitsi", "Jitsi Meet"),
        ("com.logmein.GoToMeeting", "GoTo Meeting"),
        ("com.bluejeansnet", "BlueJeans"),
        ("com.ringcentral", "RingCentral"),
        ("com.teamaround.around", "Around"),
    ]

    // MARK: - Zustand

    @Published private(set) var current: Meeting?

    /// Ein Meeting wurde erkannt. Der Empfänger entscheidet, ob er fragt oder
    /// sofort aufnimmt.
    var onDetected: ((Meeting) -> Void)?
    /// Das erkannte Meeting ist vorbei.
    var onEnded: (() -> Void)?
    /// Solange das wahr ist, hält sich der Detektor still — ein laufendes Diktat
    /// oder ein schon laufender Mitschnitt braucht keine Frage.
    var isBusy: () -> Bool = { false }

    private var timer: Timer?
    private var running = false
    private var observedDevice = AudioObjectID(kAudioObjectUnknown)
    private var blocks: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    /// Wie viele Runden der Kandidat schon durchgehend da ist.
    private var heldTicks = 0
    /// Wie viele Runden gar nichts zu sehen war — danach wieder schlafen.
    private var idleTicks = 0
    /// Wie viele Runden das laufende Meeting fehlt — danach ist es vorbei.
    private var missingTicks = 0
    private var candidate: Meeting?
    /// Für dieses Meeting bereits abgelehnt. Wird beim Ende geleert.
    private var declined: Set<String> = []

    /// Halten, bevor gefragt wird. Zwölf Sekunden, damit ein Klingelton oder ein
    /// kurzer Hinweiston nichts auslöst.
    private static let holdTicks = 12
    /// Mit laufender Kamera reicht weniger — dann ist es ziemlich sicher ein
    /// Meeting. Die Kamera allein löst NIE aus: Sie lief im Messlauf elf Sekunden
    /// für Zooms Vorschaufenster, bevor überhaupt ein Meeting existierte.
    private static let holdTicksWithCamera = 4
    private static let sleepAfterIdleTicks = 8
    private static let endAfterMissingTicks = 5

    // MARK: - Einstellungen

    static var mode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: "meetingDetect") ?? "") ?? .ask
    }

    /// Präfixe, für die nie gefragt werden soll („Nie bei Zoom").
    static var mutedPrefixes: [String] {
        get { UserDefaults.standard.stringArray(forKey: "meetingDetectMuted") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "meetingDetectMuted") }
    }

    // MARK: - Steuerung

    /// Richtet sich nach der Einstellung: bei `off` wird alles abgebaut, sonst
    /// hängen die Wecker.
    func apply() {
        Self.mode == .off ? stop() : start()
    }

    func start() {
        guard !running else { return }
        running = true
        installWakeups()
        // Ein Meeting kann schon laufen, wenn die App startet.
        wake()
    }

    func stop() {
        guard running else { return }
        running = false
        removeWakeups()
        timer?.invalidate()
        timer = nil
        candidate = nil
        heldTicks = 0
        if current != nil { current = nil; onEnded?() }
    }

    /// „Nicht jetzt" — für dieses Meeting nicht mehr fragen.
    ///
    /// `current` bleibt bewusst stehen: Das Meeting läuft ja weiter, und nur
    /// solange es verfolgt wird, merkt der Detektor sein Ende — und erst dieses
    /// Ende leert die Abkühlung. Ohne das galte die Absage für alle folgenden
    /// Meetings bis zum Neustart der App.
    func decline(_ meeting: Meeting) {
        declined.insert(meeting.prefix)
        candidate = nil
        heldTicks = 0
    }

    /// „Nie bei diesem Programm".
    func mute(_ meeting: Meeting) {
        var list = Self.mutedPrefixes
        if !list.contains(meeting.prefix) { list.append(meeting.prefix) }
        Self.mutedPrefixes = list
        decline(meeting)
    }

    deinit {
        // `removeWakeups` ist MainActor-gebunden; die Blöcke halten nur `self`
        // schwach, und ein abgebauter Detektor bekommt keine Weckrufe mehr, weil
        // `running` dann falsch ist.
    }

    // MARK: - Wecker

    private func installWakeups() {
        // 1. Die Prozessliste — feuert doppelt und zu früh, taugt nur zum Wecken.
        listen(to: AudioObjectID(kAudioObjectSystemObject),
               selector: kAudioHardwarePropertyProcessObjectList)
        // 2. Wechselt das Ausgabegerät (Kopfhörer!), muss der Gerät-Listener mit.
        listen(to: AudioObjectID(kAudioObjectSystemObject),
               selector: kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.observeDefaultOutput()
        }
        observeDefaultOutput()
    }

    /// Hängt den „läuft irgendwer darauf"-Listener ans aktuelle Ausgabegerät.
    private func observeDefaultOutput() {
        let device = Self.defaultOutputDevice()
        guard device != observedDevice else { return }
        if observedDevice != AudioObjectID(kAudioObjectUnknown) {
            removeListener(on: observedDevice, selector: kAudioDevicePropertyDeviceIsRunningSomewhere)
        }
        observedDevice = device
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        listen(to: device, selector: kAudioDevicePropertyDeviceIsRunningSomewhere)
    }

    private func listen(to object: AudioObjectID,
                        selector: AudioObjectPropertySelector,
                        extra: (() -> Void)? = nil) {
        var address = Self.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.running else { return }
                extra?()
                self.wake()
            }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return }
        blocks.append((object, address, block))
    }

    private func removeListener(on object: AudioObjectID, selector: AudioObjectPropertySelector) {
        blocks.removeAll { entry in
            guard entry.0 == object, entry.1.mSelector == selector else { return false }
            var address = entry.1
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, entry.2)
            return true
        }
    }

    private func removeWakeups() {
        for (object, addressValue, block) in blocks {
            var address = addressValue
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        blocks.removeAll()
        observedDevice = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Nachschauen

    /// Weckt die Prüfrunde. Läuft sie schon, verlängert das nur ihre Geduld.
    private func wake() {
        idleTicks = 0
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Damit die Runde auch läuft, während ein Menü offen ist.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func sleep() {
        timer?.invalidate()
        timer = nil
        candidate = nil
        heldTicks = 0
        idleTicks = 0
    }

    private func tick() {
        guard running, Self.mode != .off else { sleep(); return }

        // Während eines Diktats oder eines laufenden Mitschnitts wird nicht
        // gefragt — aber ein schon erkanntes Meeting darf zu Ende gehen.
        if isBusy(), current == nil {
            candidate = nil
            heldTicks = 0
            return
        }

        let found = scan()

        if let meeting = current {
            if let found, found.pid == meeting.pid {
                missingTicks = 0
            } else {
                missingTicks += 1
                if missingTicks >= Self.endAfterMissingTicks { end() }
            }
            return
        }

        guard let found, !declined.contains(found.prefix) else {
            candidate = nil
            heldTicks = 0
            idleTicks += 1
            if idleTicks >= Self.sleepAfterIdleTicks { sleep() }
            return
        }

        idleTicks = 0
        if candidate?.pid != found.pid {
            candidate = found
            heldTicks = 0
        }
        heldTicks += 1

        let needed = Self.cameraRunning() ? Self.holdTicksWithCamera : Self.holdTicks
        guard heldTicks >= needed else { return }

        current = found
        missingTicks = 0
        onDetected?(found)
    }

    private func end() {
        current = nil
        candidate = nil
        heldTicks = 0
        missingTicks = 0
        declined.removeAll()
        onEnded?()
    }

    /// Das laufende Meeting von außen für beendet erklären (z. B. weil der
    /// Mitschnitt von Hand gestoppt wurde).
    func forgetCurrent() {
        guard current != nil else { return }
        current = nil
        missingTicks = 0
        declined.removeAll()
    }

    /// Sucht den ersten Prozess, der ein Meeting sein kann.
    private func scan() -> Meeting? {
        let muted = Self.mutedPrefixes
        let own = Self.ownProcessObject()
        for object in Self.processObjects() where object != own {
            guard Self.flag(object, kAudioProcessPropertyIsRunningOutput) else { continue }
            guard let bundle = Self.bundleID(object), !bundle.isEmpty else { continue }
            guard let match = Self.known.first(where: { bundle.hasPrefix($0.prefix) }),
                  !muted.contains(match.prefix) else { continue }
            return Meeting(prefix: match.prefix, name: match.name,
                           pid: Self.pid(object), processObject: object)
        }
        return nil
    }

    /// Das sichtbare Programm zum Meeting — für Symbol und Namen im Fenster.
    /// Der Ton kann aus einem Helfer kommen, der gar kein Fenster hat.
    static func hostApp(for meeting: Meeting) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        return apps.first {
            $0.activationPolicy == .regular && ($0.bundleIdentifier?.hasPrefix(meeting.prefix) ?? false)
        } ?? apps.first { $0.processIdentifier == meeting.pid }
    }

    // MARK: - Core-Audio-Kleinkram

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr && value == 1
    }

    private static func pid(_ object: AudioObjectID) -> pid_t {
        var addr = address(kAudioProcessPropertyPID)
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return -1 }
        return value
    }

    private static func bundleID(_ object: AudioObjectID) -> String? {
        var addr = address(kAudioProcessPropertyBundleID)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
        }
        return status == noErr ? value as String? : nil
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &device) == noErr else {
            return AudioObjectID(kAudioObjectUnknown)
        }
        return device
    }

    /// Das eigene Prozessobjekt — der eigene Ton ist nie ein Meeting.
    private static func ownProcessObject() -> AudioObjectID {
        var pid = getpid()
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr ? object : AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Kamera und Bildschirm

    /// Läuft irgendeine Kamera? Verstärkt nur — die Kamera allein löst nichts aus.
    /// Ebenfalls berechtigungsfrei lesbar.
    private static func cameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == noErr else { return false }
        for device in ids {
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(UInt32(kCMIODevicePropertyDeviceIsRunningSomewhere)),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var value: UInt32 = 0
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &running, 0, nil, 4, &got, &value) == noErr, value == 1 {
                return true
            }
        }
        return false
    }

    /// Ist der Bildschirm gesperrt? Die **Erkennung** läuft trotzdem weiter — nur
    /// die Frage wird zurückgehalten, bis wieder jemand hinsieht. Sonst wäre ein
    /// Meeting, das während der Abwesenheit beginnt, verpasst, und die zwanzig
    /// Sekunden der Karte verstrichen vor einem Sperrbildschirm.
    static func screenLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Int) == 1
    }
}
#endif
