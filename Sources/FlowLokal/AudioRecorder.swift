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

    private let lock = NSLock()
    private var samples: [Float] = []
    /// Zählt jede Aufnahme hoch; verspätete Tap-Callbacks einer alten Engine
    /// tragen eine ältere Generation und werden ignoriert. Unter `lock` zugegriffen.
    private var generation = 0

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

    // Adaptiver VAD: statt fester Schwelle läuft ein Rausch-Boden mit, der sich
    // an die Umgebung anpasst. Sprache = RMS deutlich über dem Boden.
    private var noiseFloor: Float = 0.01
    private let speechFactor: Float = 3.5      // wie weit über dem Rauschen = Sprache
    private let absoluteFloor: Float = 0.010   // unter diesem RMS ist es immer „still"

    private var heardSpeech = false
    private var silenceAccumulated = 0.0
    private var silenceFired = false

    func start() throws {
        let gen: Int
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        generation &+= 1
        gen = generation
        // VAD-Zustand unter demselben Lock zurücksetzen wie der Audio-Thread ihn
        // liest/schreibt — sonst racet ein noch laufender Alt-Callback mit dem Reset.
        heardSpeech = false
        silenceAccumulated = 0
        silenceFired = false
        noiseFloor = 0.01   // Rausch-Boden je Aufnahme neu einpendeln lassen
        lock.unlock()

        #if os(iOS)
        // iOS: Audio-Session für Aufnahme aktivieren (ersetzt die macOS-Geräteauswahl).
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
        try session.setActive(true)
        #endif

        // Frische Engine je Aufnahme, damit ein Gerätewechsel sauber greift.
        engine = AVAudioEngine()
        let input = engine.inputNode

        #if os(macOS)
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
        #endif

        let inputFormat = input.inputFormat(forBus: 0)

        // Converter + Zielformat als lokale, unveränderliche Konstanten je Aufnahme —
        // so liest der Audio-Thread nie eine Instanz-Property, die start() gerade ersetzt.
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "shout.AudioRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Audio-Converter konnte nicht erstellt werden."])
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, converter: converter, targetFormat: targetFormat, generation: gen)
        }

        engine.prepare()
        try engine.start()
    }

    /// Beendet die Aufnahme und gibt die gesammelten 16-kHz-Samples zurück.
    @discardableResult
    func stop() -> [Float] {
        // Den letzten in-flight Tap-Puffer (~85 ms bei 4096 Frames) noch ankommen
        // lassen, damit das Ende des letzten Wortes nicht abgeschnitten wird.
        Thread.sleep(forTimeInterval: 0.09)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
        // Session freigeben, damit z. B. Musik-Wiedergabe anderer Apps weiterläuft.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        lock.lock()
        let result = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        let trimmed = trimSilence(result)
        if trimmed.count != result.count {
            NSLog("shout: Aufnahme %.1fs → getrimmt %.1fs",
                  Double(result.count) / 16_000, Double(trimmed.count) / 16_000)
        }
        return trimmed
    }

    /// Schneidet führende/abschließende Stille weg, bevor die Samples an Whisper
    /// gehen (weniger Halluzinationen in Stille, geringere Latenz).
    ///
    /// Die Schwelle ist RELATIV zum lautesten Fenster der Aufnahme und eng nach
    /// oben gedeckelt — bewusst NICHT vom adaptiven Rausch-Boden abgeleitet
    /// (der kann bei langem Sprechen über den Sprechpegel klettern; leise
    /// Satzanfänge oder ganze leise Passagen würden dann weggeschnitten).
    private func trimSilence(_ input: [Float]) -> [Float] {
        guard input.count > 3_200 else { return input }   // < 0,2 s: unverändert lassen
        let window = 480                                   // 30 ms bei 16 kHz

        // Fenster-RMS einmal berechnen; Peak bestimmt die Schwelle.
        var windowRMS: [Float] = []
        windowRMS.reserveCapacity(input.count / window + 1)
        var i = 0
        while i < input.count {
            let end = min(i + window, input.count)
            var sum: Float = 0
            for j in i..<end { sum += input[j] * input[j] }
            windowRMS.append((sum / Float(end - i)).squareRoot())
            i += window
        }
        let peak = windowRMS.max() ?? 0
        guard peak >= 0.008 else { return [] }             // nie substanzielle Energie → still

        // 10 % des Peaks, geklemmt auf [0.004, 0.012] — leise Sprecher bleiben drin,
        // echtes Grundrauschen (~0.002–0.006) bleibt draußen.
        let threshold = min(max(0.004, peak * 0.10), 0.012)

        var firstSpeech = -1, lastSpeech = -1
        for (w, rms) in windowRMS.enumerated() where rms > threshold {
            if firstSpeech < 0 { firstSpeech = w * window }
            lastSpeech = min(w * window + window, input.count)
        }

        guard firstSpeech >= 0 else { return [] }
        let pad = 4_800                                    // 300 ms Sicherheitsrand
        let start = max(0, firstSpeech - pad)
        let stop = min(input.count, lastSpeech + pad)
        return Array(input[start..<stop])
    }

    // MARK: - Intern

    private func append(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter,
                        targetFormat: AVAudioFormat, generation gen: Int) {
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
        guard gen == generation else { lock.unlock(); return }   // Callback einer alten Engine
        samples.append(contentsOf: chunk)
        lock.unlock()

        analyze(chunk, generation: gen)
    }

    /// Berechnet einmal den RMS-Pegel und nutzt ihn für Live-Pegel + Stille-Erkennung.
    private func analyze(_ chunk: [Float], generation gen: Int) {
        guard !chunk.isEmpty else { return }

        var sumSquares: Float = 0
        for sample in chunk { sumSquares += sample * sample }
        let rms = (sumSquares / Float(chunk.count)).squareRoot()

        // Live-Pegel 0…1: sqrt-Kurve für kräftigeren Ausschlag, mit kleinem
        // Rauschabzug, damit Stille wirklich klein bleibt. Kein geteilter Zustand.
        let level = min(1, max(0, rms.squareRoot() - 0.04) * 5.5)
        let levelCallback = onLevel
        DispatchQueue.main.async { levelCallback?(level) }

        let duration = Double(chunk.count) / 16_000.0
        var fireSilence = false

        // Gesamter VAD-Zustand (noiseFloor + Stille-Tracking) unter EINEM Lock, mit
        // Generation-Check am Anfang: ein verspäteter Callback einer alten Engine
        // fasst den frisch zurückgesetzten Zustand der neuen Aufnahme nicht mehr an.
        lock.lock()
        guard gen == generation else { lock.unlock(); return }
        // Rausch-Boden als Minimum-Tracker: folgt leisen Fenstern schnell nach
        // unten, „vergisst" nach oben nur sehr langsam und ist hart gedeckelt.
        // WICHTIG: Er darf NICHT aus Sprach-Chunks lernen — die frühere Variante
        // (steigt bei jedem Chunk Richtung rms) kletterte bei Dauersprechen in
        // wenigen Sekunden über den Sprechpegel, wodurch Sprache als „Stille"
        // galt (Auto-Stopp mitten im Satz, Anfang/Ende weggetrimmt).
        if rms < noiseFloor {
            noiseFloor = noiseFloor * 0.5 + rms * 0.5
        } else {
            noiseFloor = min(noiseFloor * 1.002, 0.015)
        }
        let threshold = max(absoluteFloor, noiseFloor * speechFactor)
        if autoStopEnabled, !silenceFired {
            if rms > threshold {
                heardSpeech = true
                silenceAccumulated = 0
            } else if heardSpeech {
                silenceAccumulated += duration
                if silenceAccumulated >= silenceSeconds {
                    silenceFired = true
                    fireSilence = true
                }
            }
        }
        lock.unlock()

        if fireSilence {
            let callback = onSilence
            DispatchQueue.main.async { callback?() }
        }
    }
}
