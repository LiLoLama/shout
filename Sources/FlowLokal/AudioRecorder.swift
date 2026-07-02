import AVFoundation
import AudioToolbox

/// Nimmt Mikrofon-Audio auf und liefert es als 16-kHz-Mono-Float-Array —
/// genau das Format, das Whisper erwartet.
///
/// Die Hardware liefert i.d.R. 44,1/48 kHz (evtl. Stereo). Wir hängen einen
/// Tap auf den Input-Node und resamplen jeden Puffer per AVAudioConverter
/// live auf 16 kHz Mono. Der Tap-Callback läuft auf einem Audio-Thread,
/// deshalb ist der Sample-Puffer per NSLock geschützt.
final class AudioRecorder {

    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat!

    private let lock = NSLock()
    private var samples: [Float] = []

    private let targetSampleRate = 16_000.0

    /// Gewünschtes Eingabegerät (stabile Core-Audio-UID). nil = Systemstandard.
    var preferredDeviceUID: String?

    // MARK: - Auto-Stopp (Stille-Erkennung)

    var autoStopEnabled = false
    var silenceSeconds = 1.5
    /// Wird einmal aufgerufen, wenn nach erkannter Sprache lang genug Stille war.
    var onSilence: (() -> Void)?
    /// Laufender Eingangspegel 0…1 (für den Aufnahme-Hinweis). Läuft über den Main-Thread.
    var onLevel: ((Float) -> Void)?

    private let speechRMSThreshold: Float = 0.015
    private var heardSpeech = false
    private var silenceAccumulated = 0.0
    private var silenceFired = false

    func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        heardSpeech = false
        silenceAccumulated = 0
        silenceFired = false

        // Frische Engine je Aufnahme, damit ein Gerätewechsel sauber greift.
        engine = AVAudioEngine()
        let input = engine.inputNode

        // Gewünschtes Eingabegerät setzen — MUSS vor dem Auslesen des Formats passieren.
        if let uid = preferredDeviceUID,
           let deviceID = AudioDevices.deviceID(forUID: uid),
           let audioUnit = input.audioUnit {
            var device = deviceID
            AudioUnitSetProperty(
                audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let inputFormat = input.inputFormat(forBus: 0)

        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    /// Beendet die Aufnahme und gibt die gesammelten 16-kHz-Samples zurück.
    @discardableResult
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let result = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        return result
    }

    // MARK: - Intern

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }

        let ratio = targetSampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: outBuffer, error: &conversionError) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return buffer
        }

        guard conversionError == nil,
              let channelData = outBuffer.floatChannelData else { return }

        let frameCount = Int(outBuffer.frameLength)
        let channel = channelData[0]
        let chunk = Array(UnsafeBufferPointer(start: channel, count: frameCount))

        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()

        analyze(chunk)
    }

    /// Berechnet einmal den RMS-Pegel und nutzt ihn für Live-Pegel + Stille-Erkennung.
    private func analyze(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }

        var sumSquares: Float = 0
        for sample in chunk { sumSquares += sample * sample }
        let rms = (sumSquares / Float(chunk.count)).squareRoot()

        // Live-Pegel 0…1 (Sprache ~0,05–0,25 → skaliert & begrenzt).
        let level = min(1, rms * 6)
        let levelCallback = onLevel
        DispatchQueue.main.async { levelCallback?(level) }

        guard autoStopEnabled, !silenceFired else { return }
        let duration = Double(chunk.count) / 16_000.0
        if rms > speechRMSThreshold {
            heardSpeech = true
            silenceAccumulated = 0
        } else if heardSpeech {
            silenceAccumulated += duration
            if silenceAccumulated >= silenceSeconds {
                silenceFired = true
                let callback = onSilence
                DispatchQueue.main.async { callback?() }
            }
        }
    }
}
