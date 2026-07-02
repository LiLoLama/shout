import CoreAudio
import Foundation

/// Core-Audio-Helfer: listet Eingabegeräte auf und löst eine stabile Geräte-UID
/// zur (flüchtigen) AudioDeviceID auf.
enum AudioDevices {

    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let uid: String
    }

    /// Alle Geräte mit mindestens einem Eingangskanal.
    static func inputDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasInput(id),
                  let name = stringProperty(id, kAudioObjectPropertyName),
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID)
            else { return nil }
            return Device(id: id, name: name, uid: uid)
        }
    }

    /// Aktuelle AudioDeviceID zu einer gespeicherten UID (Geräte-IDs ändern sich,
    /// UIDs sind stabil).
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        inputDevices().first { $0.uid == uid }?.id
    }

    // MARK: - Intern

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return false
        }
        // Reine Ausgabegeräte liefern eine leere Bufferliste → Puffer-Anzahl 0.
        // allocate(maximumBuffers:) trapt bei 0, deshalb mindestens 1.
        let bufferCount = max(1, Int(dataSize) / MemoryLayout<AudioBuffer>.size)
        let bufferList = AudioBufferList.allocate(maximumBuffers: bufferCount)
        defer { free(bufferList.unsafeMutablePointer) }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, bufferList.unsafeMutablePointer) == noErr else {
            return false
        }
        var channels: UInt32 = 0
        for buffer in bufferList { channels += buffer.mNumberChannels }
        return channels > 0
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}
