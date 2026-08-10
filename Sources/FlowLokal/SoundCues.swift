import AVFoundation

/// Die Klang-Signale der App: fertige Klänge aus `Resources/Audio`.
///
/// Vorher waren das synthetisierte Holz-Taps. Die echten Dateien klingen besser,
/// bringen aber ein Problem mit: Sie sind unterschiedlich laut ausgesteuert.
/// Gemessen lagen Start und Stopp bei −1 dBFS Spitze (praktisch voll ausgesteuert),
/// der Fehlerton rund 10 dB darunter. Unverändert abgespielt wären die ersten
/// beiden unangenehm laut und der dritte kaum hörbar.
///
/// Deshalb wird beim Laden **gemessen und angeglichen**: Jeder Klang wird auf
/// dieselbe wahrgenommene Lautstärke gebracht (lauteste 300 ms), gedeckelt durch
/// eine Spitzenwert-Grenze. Das passiert zur Laufzeit und nicht als feste Zahl pro
/// Datei — so bleibt die Lautstärke stimmig, wenn die Klänge ausgetauscht werden.
@MainActor
final class SoundCues {
    enum Cue { case start, stop, done, error }

    /// Zielwert der wahrgenommenen Lautstärke (RMS der lautesten 300 ms), linear.
    /// 0,05 entspricht etwa −26 dBFS: deutlich hörbar, aber nichts, was einen bei
    /// Kopfhörern zusammenzucken lässt. Die alten synthetischen Töne lagen mit
    /// 0,09 Spitze in derselben Gegend — daran ist die Zahl geeicht.
    private static let targetLoudness: Float = 0.05
    /// Obergrenze für den Spitzenwert (≈ −12 dBFS). Greift bei Klängen mit hoher
    /// Dynamik, bei denen die Lautheits-Angleichung die Spitzen zu weit hochzöge.
    private static let maxPeak: Float = 0.25

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var playToken = 0   // erkennt, ob seit dem Scheduling ein neuer Cue kam

    private var enabled: Bool { UserDefaults.standard.object(forKey: "soundCuesEnabled") as? Bool ?? true }

    init() {
        // Ein gemeinsames Format für den Player: Die Dateien liegen in 48 kHz vor,
        // könnten aber ausgetauscht werden — deshalb wird beim Laden auf dieses
        // Format umgerechnet, statt sich auf die Abtastrate der Dateien zu verlassen.
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
        guard let format else { return }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()

        buffers[.start] = load("Rec_start", to: format)
        let stop = load("Rec_stop", to: format)
        buffers[.stop] = stop
        // „Fertig eingefügt" nutzt denselben Klang wie das Aufnahme-Ende: Es ist die
        // eigentlich nützliche Rückmeldung („du kannst weiterarbeiten"), und ein
        // vierter, andersartiger Ton wäre nur Unruhe.
        buffers[.done] = stop
        buffers[.error] = load("Error_sound", to: format)
    }

    func play(_ cue: Cue) {
        guard enabled, let buffer = buffers[cue] else { return }
        do {
            // engine.isRunning statt eines Einmal-Flags: nach einem Audio-Config-Wechsel
            // (Kopfhörer an/ab) stoppt die Engine — dann hier sauber neu starten.
            if !engine.isRunning { try engine.start() }
            playToken &+= 1
            let token = playToken
            // Nach dem Abspielen Engine pausieren (rendert sonst dauerhaft Stille).
            // Kommt zwischenzeitlich ein neuer Cue (Token geändert), NICHT pausieren.
            player.scheduleBuffer(buffer, at: nil, options: .interrupts,
                                  completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playToken == token else { return }
                    self.player.pause()
                    self.engine.pause()
                }
            }
            if !player.isPlaying { player.play() }
        } catch {
            NSLog("SoundCues: Wiedergabe fehlgeschlagen: \(error)")
        }
    }

    // MARK: - Laden

    private func load(_ name: String, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
            NSLog("SoundCues: \(name).mp3 liegt nicht im Bundle")
            return nil
        }
        guard let file = try? AVAudioFile(forReading: url) else {
            NSLog("SoundCues: \(name).mp3 ist nicht lesbar")
            return nil
        }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              (try? file.read(into: source)) != nil,
              let buffer = resample(source, to: target) else {
            NSLog("SoundCues: \(name).mp3 konnte nicht aufbereitet werden")
            return nil
        }
        normalize(buffer)
        return buffer
    }

    /// Rechnet auf das Player-Format um. Stimmen die Formate schon überein, wird der
    /// Puffer unverändert durchgereicht.
    private func resample(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: target) else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var delivered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }

    /// Hebt oder senkt den Puffer auf die Ziel-Lautstärke.
    ///
    /// Gemessen wird die lauteste 300-Millisekunden-Strecke, nicht der Gesamt-RMS:
    /// Ein kurzer Klick und ein langer, leiser Ausklang haben denselben Spitzenwert,
    /// werden aber völlig verschieden laut wahrgenommen. Über die Gesamtlänge zu
    /// mitteln würde einen langen Klang mit viel Stille künstlich hochziehen —
    /// genau der Fall des 1,8 Sekunden langen Fehlertons.
    private func normalize(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return }

        var mono = [Float](repeating: 0, count: frames)
        var peak: Float = 0
        for i in 0..<frames {
            var sum: Float = 0
            for c in 0..<channelCount { sum += channels[c][i] }
            let value = sum / Float(channelCount)
            mono[i] = value
            peak = max(peak, abs(value))
        }
        guard peak > 0 else { return }

        let window = min(frames, Int(buffer.format.sampleRate * 0.3))
        var energy: Float = 0
        for i in 0..<window { energy += mono[i] * mono[i] }
        var best = energy
        for i in window..<frames {
            energy += mono[i] * mono[i] - mono[i - window] * mono[i - window]
            best = max(best, energy)
        }
        let loudness = (best / Float(window)).squareRoot()
        guard loudness > 0 else { return }

        let gain = min(Self.targetLoudness / loudness, Self.maxPeak / peak)
        guard abs(gain - 1) > 0.001 else { return }
        for c in 0..<channelCount {
            for i in 0..<frames { channels[c][i] *= gain }
        }
    }
}
