import AVFoundation

/// Nimmt Mikrofon-Audio auf und liefert es als 16-kHz-Mono-Float-Array —
/// genau das Format, das Whisper erwartet.
///
/// Die Hardware liefert i.d.R. 44,1/48 kHz (evtl. Stereo). Wir hängen einen
/// Tap auf den Input-Node und resamplen jeden Puffer per AVAudioConverter
/// live auf 16 kHz Mono. Der Tap-Callback läuft auf einem Audio-Thread,
/// deshalb ist der Sample-Puffer per NSLock geschützt.
final class AudioRecorder {

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat!

    private let lock = NSLock()
    private var samples: [Float] = []

    private let targetSampleRate = 16_000.0

    func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        let input = engine.inputNode
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
    }
}
