import AppKit
import Carbon.HIToolbox

/// Eine globale Taste über Carbon (`RegisterEventHotKey`). Anders als ein
/// `NSEvent`-Monitor fängt sie die Taste ab — in der App darunter landet kein
/// Zeichen — und braucht keine Bedienungshilfen-Berechtigung. Drücken und
/// Loslassen kommen beide, damit ist Halten erkennbar.
///
/// Eine Instanz bleibt registriert (und am Leben), bis `unregister()` gerufen
/// wird: Das statische Verzeichnis hält sie stark.
@MainActor
final class GlobalHotkey {

    enum RegistrationError: Error, Equatable {
        /// Eine andere App hat die Kombination schon.
        case taken
        case failed(OSStatus)
    }

    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private let kennung: UInt32
    private var ref: EventHotKeyRef?

    private static var naechsteKennung: UInt32 = 1
    private static var registriert: [UInt32: GlobalHotkey] = [:]
    private static var handlerInstalliert = false
    /// „shou“
    private static let signatur = OSType(0x7368_6F75)

    init() {
        kennung = Self.naechsteKennung
        Self.naechsteKennung += 1
    }

    func register(_ kombi: HotkeyCombo) throws {
        unregister()
        let handlerStatus = Self.installiereHandler()
        // Ohne Handler käme nie ein Ereignis an — dann nicht so tun, als wäre die Taste registriert.
        guard handlerStatus == noErr else { throw RegistrationError.failed(handlerStatus) }
        var neu: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kombi.keyCode), kombi.carbonModifiers,
                                         EventHotKeyID(signature: Self.signatur, id: kennung),
                                         GetApplicationEventTarget(), 0, &neu)
        if status == OSStatus(eventHotKeyExistsErr) { throw RegistrationError.taken }
        guard status == noErr, let neu else { throw RegistrationError.failed(status) }
        ref = neu
        Self.registriert[kennung] = self
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.registriert[kennung] = nil
    }

    private static func installiereHandler() -> OSStatus {
        guard !handlerInstalliert else { return noErr }
        var typen = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, ereignis, _ in
            guard let ereignis else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let parameterStatus = GetEventParameter(ereignis, EventParamName(kEventParamDirectObject),
                                                    EventParamType(typeEventHotKeyID),
                                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard parameterStatus == noErr else { return OSStatus(eventNotHandledErr) }
            let gedrueckt = GetEventKind(ereignis) == UInt32(kEventHotKeyPressed)
            // Carbon liefert auf dem Hauptstrang.
            let behandelt = MainActor.assumeIsolated { () -> Bool in
                guard let taste = GlobalHotkey.registriert[id.id] else { return false }
                if gedrueckt { taste.onPress() } else { taste.onRelease() }
                return true
            }
            return behandelt ? noErr : OSStatus(eventNotHandledErr)
        }, typen.count, &typen, nil, nil)
        handlerInstalliert = status == noErr
        return status
    }
}
