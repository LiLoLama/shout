#if os(macOS)
import AVFoundation
import CoreAudio
import Foundation

/// Greift den **Systemton** ab — den Ton, den andere Programme ausgeben (Zoom,
/// Teams, Meet). Ab macOS 14.2 über einen Core-Audio-Process-Tap.
///
/// Drei Dinge daran sind nicht offensichtlich und haben je einen Nachmittag
/// gekostet:
///
/// 1. **Das abgegriffene Ausgabegerät MUSS als Haupt-Sub-Gerät ins Aggregat.**
///    Ohne Sub-Gerät hat das Aggregat keine Taktquelle: Es läuft, ruft brav den
///    IOProc auf und liefert ausschließlich Nullen.
/// 2. **Ohne `NSAudioCaptureUsageDescription` in der Info.plist** kann die App die
///    nötige Berechtigung gar nicht erst anfragen. Auch dann kommen Nullen statt
///    eines Fehlers — es gibt keinen Rückgabewert, an dem man das erkennt.
/// 3. **Die Eingänge des Ausgabegeräts landen mit im Puffer.** Ein Audio-Interface
///    bringt seine eigenen Eingänge mit (bei einem Apollo 32 Stück); wer alle
///    Puffer zusammenmischt, nimmt sie ungefragt auf. Der Tap ist immer der
///    LETZTE Puffer, weil die Tap-Liste hinter der Sub-Geräte-Liste steht.
@available(macOS 14.2, *)
final class SystemAudioTap {

    /// Mono-Samples in der Rate des Aggregats. Wird auf dem Audio-Thread gerufen.
    private var onSamples: (([Float]) -> Void)?

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    /// Abtastrate des Aggregats — sie richtet sich nach dem Ausgabegerät.
    private(set) var sampleRate: Double = 48_000
    /// Sollen die Eingänge der Sub-Geräte (Mikrofon) mit aufgenommen werden?
    private var includeSubDevices = false

    // MARK: - Steuerung

    /// - Parameter includeMicrophone: Nimmt zusätzlich das Mikrofon auf. Es kommt
    ///   als Sub-Gerät ins SELBE Aggregat — nur so teilen sich beide Quellen einen
    ///   Takt. Zwei getrennt laufende Geräte würden über eine Stunde auseinander
    ///   driften.
    func start(includeMicrophone: Bool, onSamples: @escaping ([Float]) -> Void) throws {
        self.onSamples = onSamples
        self.includeSubDevices = includeMicrophone

        let output = try Self.defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let outputUID = try Self.stringProperty(output, kAudioDevicePropertyDeviceUID)

        // Eigene Klang-Signale ausschließen — sonst steht der Start-Ton im Mitschnitt.
        let excluded: [AudioObjectID] = Self.ownProcessObject().map { [$0] } ?? []
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: excluded)
        description.name = "shout"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.unmuted   // Das Meeting soll hörbar bleiben.
        try Self.check(AudioHardwareCreateProcessTap(description, &tap), "Tap anlegen")
        let tapUID = try Self.stringProperty(tap, kAudioTapPropertyUID)

        var subDevices: [[String: Any]] = [[kAudioSubDeviceUIDKey: outputUID]]
        if includeMicrophone {
            let input = try Self.defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
            let inputUID = try Self.stringProperty(input, kAudioDevicePropertyDeviceUID)
            // Nur hinzufügen, wenn es nicht ohnehin dasselbe Gerät ist (ein
            // Interface bedient oft Ein- und Ausgang).
            if inputUID != outputUID {
                subDevices.append([kAudioSubDeviceUIDKey: inputUID,
                                   kAudioSubDeviceDriftCompensationKey: true])
            }
        }

        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "shout Mitschnitt",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            // Privat: Das Gerät taucht in keiner Geräteliste des Systems auf.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        try Self.check(AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregate),
                       "Aggregat anlegen")

        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try Self.check(AudioObjectGetPropertyData(aggregate, &address, 0, nil, &size, &asbd),
                       "Format lesen")
        sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48_000

        try Self.check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil) {
            [weak self] _, input, _, _, _ in
            self?.handle(input)
        }, "IOProc anlegen")
        try Self.check(AudioDeviceStart(aggregate, procID), "Aufnahme starten")
    }

    func stop() {
        if aggregate != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregate, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregate, procID) }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if tap != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tap) }
        procID = nil
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
        onSamples = nil
    }

    deinit { stop() }

    // MARK: - Audio-Thread

    private func handle(_ input: UnsafePointer<AudioBufferList>) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard list.count > 0, let callback = onSamples else { return }

        // Der Tap ist der letzte Puffer. Bei „nur Systemton" ist er der einzige, der
        // uns interessiert: Die davor sind die Eingänge des Ausgabegeräts, und die
        // ungefragt aufzunehmen wäre ein Fehler mit Ansage.
        let tapIndex = list.count - 1
        let first = includeSubDevices ? 0 : tapIndex

        var mixed: [Float] = []
        for index in first...tapIndex {
            let buffer = list[index]
            guard let data = buffer.mData else { continue }
            let channels = max(1, Int(buffer.mNumberChannels))
            let total = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let frames = total / channels
            guard frames > 0 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)

            if mixed.isEmpty { mixed = Array(repeating: 0, count: frames) }
            let usable = min(frames, mixed.count)
            for frame in 0..<usable {
                var sum: Float = 0
                for channel in 0..<channels { sum += samples[frame * channels + channel] }
                mixed[frame] += sum / Float(channels)
            }
        }
        guard !mixed.isEmpty else { return }

        // Bei zwei Quellen halbieren, damit die Summe nicht übersteuert.
        let sources = includeSubDevices ? Float(max(1, tapIndex - first + 1)) : 1
        if sources > 1 { for i in mixed.indices { mixed[i] /= sources } }
        callback(mixed)
    }

    // MARK: - Core-Audio-Kleinkram

    private static func check(_ status: OSStatus, _ what: String) throws {
        guard status != noErr else { return }
        throw MeetingRecorderError.systemAudioFailed("\(what) (\(status))")
    }

    private static func defaultDevice(selector: AudioObjectPropertySelector) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                             0, nil, &size, &device), "Standardgerät lesen")
        return device
    }

    private static func stringProperty(_ object: AudioObjectID,
                                       _ selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "UID lesen")
        return value as String
    }

    /// AudioObjectID des eigenen Prozesses, um ihn vom Tap auszunehmen.
    private static func ownProcessObject() -> AudioObjectID? {
        var pid = getpid()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr ? object : nil
    }
}
#endif
