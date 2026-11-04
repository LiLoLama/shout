import AVFoundation
import AudioToolbox
import os

/// Nimmt Mikrofon-Audio auf und liefert es als 16-kHz-Mono-Float-Array —
/// genau das Format, das Whisper erwartet.
///
/// Am Mac liefert `MicCapture` (AVCaptureSession) die Samples schon in 16 kHz
/// Mono, Begründung dort. Am iPhone hängen wir einen Tap auf den Input-Node der
/// AVAudioEngine und resamplen jeden Puffer per AVAudioConverter live auf 16 kHz
/// Mono. Beide Wege liefern auf einem eigenen Thread, deshalb ist der
/// Sample-Puffer per NSLock geschützt.
final class AudioRecorder {

    /// Abfragbar per `log show --predicate 'subsystem == "com.inthezone.flowlokal"'`.
    /// Bewusst Logger statt NSLog: NSLog-Texte erscheinen im Systemlog nur als
    /// `<private>`, damit war die Gerätewechsel-Diagnose blind.
    private static let log = Logger(subsystem: "com.inthezone.flowlokal", category: "aufnahme")

    #if os(macOS)
    private let mic = MicCapture()
    #else
    private var engine = AVAudioEngine()
    #endif

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
    /// Einmal je Aufnahme, sobald vom Mikrofon echtes Signal ankommt — ab da wird
    /// wirklich aufgenommen. Läuft über den Main-Thread.
    ///
    /// Echtes Signal, nicht der erste Puffer: Bluetooth-Kopfhörer melden das
    /// Mikrofon nach wenigen Millisekunden als offen, liefern aber noch rund eine
    /// Sekunde lang Nullen, bis ihre Sprachverbindung steht. Wer schon beim ersten
    /// Puffer losspricht, verliert den Satzanfang. Ein echtes Mikrofon rauscht
    /// dagegen immer ein wenig und ist sofort „bereit".
    var onReady: (() -> Void)?
    /// Kommt nach so vielen Sekunden noch immer nur digitale Stille (stummgeschaltetes
    /// oder virtuelles Gerät), wird `onReady` trotzdem gemeldet — sonst wartete man
    /// vergeblich auf den Start-Ton.
    private static let readyFallback: TimeInterval = 2.0

    // Adaptiver VAD: statt fester Schwelle läuft ein Rausch-Boden mit, der sich
    // an die Umgebung anpasst. Sprache = RMS deutlich über dem Boden.
    private var noiseFloor: Float = 0.01
    private let speechFactor: Float = 3.5      // wie weit über dem Rauschen = Sprache
    private let absoluteFloor: Float = 0.010   // unter diesem RMS ist es immer „still"

    private var heardSpeech = false
    private var silenceAccumulated = 0.0
    private var silenceFired = false

    // MARK: - Gerätewechsel während der Aufnahme

    /// Läuft gerade eine Aufnahme? Nur auf dem Main-Thread gelesen und geschrieben.
    private var isRunning = false
    /// Steht `onReady` für diese Aufnahme noch aus? Unter `lock`, der Audio-Thread liest es.
    private var readyPending = false
    /// Wann `start()` lief — für die Log-Zeile, wie lange das Mikrofon bis zum
    /// ersten echten Signal brauchte. Unter `lock`.
    private var startedAt = Date()
    #if os(iOS)
    /// Beobachtet die laufende Engine auf `AVAudioEngineConfigurationChange`.
    private var configObserver: NSObjectProtocol?
    /// Neustarts, die der laufenden Aufnahme noch zustehen. Begrenzt, damit ein
    /// Gerät, das sich dauernd umkonfiguriert, keine Endlosschleife auslöst.
    private var restartsLeft = 0
    private static let maxRestarts = 5
    #endif

    func start() throws {
        let gen: Int
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        generation &+= 1
        gen = generation
        readyPending = true
        startedAt = Date()
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
                                options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
        try session.setActive(true)
        restartsLeft = Self.maxRestarts
        #endif

        try openMicrophone(generation: gen)
        isRunning = true

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readyFallback) { [weak self] in
            guard let self, self.isRunning else { return }
            self.lock.lock()
            let fire = self.readyPending && self.generation == gen
            if fire { self.readyPending = false }
            self.lock.unlock()
            guard fire else { return }
            Self.log.error("Mikrofon liefert nach \(Self.readyFallback, format: .fixed(precision: 1), privacy: .public) s noch kein Signal, Start-Ton kommt trotzdem")
            self.onReady?()
        }
    }

    private func openMicrophone(generation gen: Int) throws {
        #if os(macOS)
        try mic.start(deviceUID: preferredDeviceUID) { [weak self] chunk in
            self?.ingest(chunk, generation: gen)
        }
        #else
        try launchEngine(generation: gen)
        #endif
    }

    private func closeMicrophone() {
        #if os(macOS)
        mic.stop()
        #else
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #endif
    }

    #if os(iOS)
    /// Baut eine frische Engine auf, hängt den Tap ein und startet sie. Dient dem
    /// Start und dem Neustart nach einem Gerätewechsel.
    ///
    /// Frische Engine statt Wiederverwendung: Nach einem Wechsel meldet eine alte
    /// Engine gelegentlich noch das frühere Format, und `installTap` mit einem
    /// Format, das nicht zur Hardware passt, endet in einer Exception.
    private func launchEngine(generation gen: Int) throws {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil

        engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        // Mitten im Umschalten meldet das Gerät kurz 0 Hz oder 0 Kanäle.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "shout.AudioRecorder", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Das Eingabegerät liefert gerade kein gültiges Format."])
        }

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

        // Schaltet das Gerät um (Bluetooth-Kopfhörer ins Headset-Profil, anderes
        // Gerät gesteckt), hält die Engine an und meldet sich hier. Ohne Neustart
        // bliebe die Aufnahme danach stumm, obwohl die Pille läuft.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Self.log.info("Audio-Gerät hat umgeschaltet")
            self?.relaunch()
        }

        engine.prepare()
        try engine.start()
    }

    /// Startet die Aufnahme mit dem neuen Geräteformat neu. Die bisher gesammelten
    /// Samples bleiben, es geht nahtlos weiter. Läuft auf dem Main-Thread.
    /// Nur am iPhone nötig — am Mac übernimmt `MicCapture` Gerätewechsel selbst.
    private func relaunch() {
        guard isRunning else { return }
        guard restartsLeft > 0 else {
            Self.log.error("Audio-Gerät schaltet ständig um, Aufnahme wird nicht mehr neu gestartet")
            return
        }
        restartsLeft -= 1

        lock.lock()
        let gen = generation
        lock.unlock()

        closeMicrophone()
        do {
            try openMicrophone(generation: gen)
            Self.log.info("Aufnahme läuft nach Neustart weiter")
        } catch {
            // Gerät noch mitten im Umschalten: kurz warten und erneut versuchen.
            Self.log.error("Neustart nach Gerätewechsel fehlgeschlagen, neuer Versuch: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.relaunch()
            }
        }
    }
    #endif

    /// Beendet die Aufnahme und gibt die gesammelten 16-kHz-Samples zurück.
    @discardableResult
    func stop() -> [Float] {
        isRunning = false
        lock.lock()
        readyPending = false
        lock.unlock()
        // Den letzten in-flight Puffer (~85 ms bei 4096 Frames) noch ankommen
        // lassen, damit das Ende des letzten Wortes nicht abgeschnitten wird.
        Thread.sleep(forTimeInterval: 0.09)
        closeMicrophone()
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
            Self.log.info("Aufnahme \(Double(result.count) / 16_000, format: .fixed(precision: 1), privacy: .public) s → getrimmt \(Double(trimmed.count) / 16_000, format: .fixed(precision: 1), privacy: .public) s")
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

    #if os(iOS)
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
        ingest(Array(UnsafeBufferPointer(start: channel, count: frameCount)), generation: gen)
    }
    #endif

    /// Nimmt einen Block 16-kHz-Mono-Samples auf. Läuft auf dem Audio-Thread.
    private func ingest(_ chunk: [Float], generation gen: Int) {
        lock.lock()
        guard gen == generation else { lock.unlock(); return }   // Callback einer alten Aufnahme
        samples.append(contentsOf: chunk)
        // Echtes Signal statt digitaler Stille (siehe `onReady`). Die Schwelle liegt
        // weit unter dem Grundrauschen jedes echten Mikrofons (um −66 dBFS).
        let fireReady = readyPending && chunk.contains { abs($0) > 0.0001 }
        if fireReady { readyPending = false }
        let since = startedAt
        lock.unlock()

        if fireReady {
            let readyCallback = onReady
            DispatchQueue.main.async { [weak self] in
                guard self?.isRunning == true else { return }
                Self.log.info("Mikrofon liefert Signal nach \(Date().timeIntervalSince(since) * 1000, format: .fixed(precision: 0), privacy: .public) ms")
                readyCallback?()
            }
        }

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
