import AVFoundation

/// Die Klang-Signale der App: fertige Klänge aus `Resources/Audio`.
///
/// Zwei Dinge sind hier wichtig und waren beim ersten Anlauf beide falsch:
///
/// **Nicht selbst umrechnen.** Die Dateien liegen in 48 kHz vor. Sie vorab auf
/// 44,1 kHz zu bringen, klingt hörbar schlechter — ein krummes Verhältnis, das ohne
/// hochwertigen Wandler Aliasing erzeugt. Stattdessen läuft der Player im Format der
/// Dateien; das Umrechnen auf die Hardware-Rate übernimmt der Mixer der Audio-Engine,
/// und der macht es richtig. Umgerechnet wird nur eine Datei, die aus der Reihe fällt
/// — dann mit maximaler Wandler-Qualität.
///
/// **Lautstärke angleichen.** Gemessen lagen Start und Stopp bei −1 dBFS Spitze
/// (praktisch voll ausgesteuert), der Fehlerton rund 10 dB darunter. Unverändert
/// abgespielt wären die ersten beiden unangenehm laut und der dritte kaum hörbar.
/// Deshalb wird beim Laden die lauteste 300-ms-Strecke gemessen und angeglichen —
/// zur Laufzeit statt als feste Zahl pro Datei, damit ausgetauschte Klänge von selbst
/// stimmig bleiben.
@MainActor
final class SoundCues {
    enum Cue { case start, stop, done, error }

    /// Zielwert der wahrgenommenen Lautstärke (RMS der lautesten 300 ms), linear.
    /// 0,05 entspricht etwa −26 dBFS: deutlich hörbar, aber nichts, was einen bei
    /// Kopfhörern zusammenzucken lässt. Die alten synthetischen Töne lagen mit
    /// 0,09 Spitze in derselben Gegend — daran ist die Zahl geeicht.
    private static let targetLoudness: Float = 0.05
    /// Obergrenze für den Spitzenwert (≈ −12 dBFS).
    private static let maxPeak: Float = 0.25

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var playToken = 0   // erkennt, ob seit dem Scheduling ein neuer Cue kam

    private var enabled: Bool { UserDefaults.standard.object(forKey: "soundCuesEnabled") as? Bool ?? true }

    init() {
        // Erst laden, dann das Format festlegen: Der Player bekommt das Format der
        // Dateien, nicht umgekehrt.
        var loaded: [(cue: Cue, buffer: AVAudioPCMBuffer)] = []
        for (cue, name) in [(Cue.start, "Rec_start"), (Cue.stop, "Rec_stop"), (Cue.error, "Error_sound")] {
            guard let buffer = Self.read(name) else { continue }
            loaded.append((cue, buffer))
        }
        guard let canonical = loaded.first?.buffer.format else {
            format = nil
            NSLog("SoundCues: keine Klangdatei ladbar — die App bleibt stumm")
            return
        }
        format = canonical

        for (cue, buffer) in loaded {
            guard let ready = Self.matched(buffer, to: canonical) else { continue }
            Self.normalize(ready)
            buffers[cue] = ready
        }
        // „Fertig eingefügt" nutzt denselben Klang wie das Aufnahme-Ende: Es ist die
        // eigentlich nützliche Rückmeldung („du kannst weiterarbeiten"), und ein
        // vierter, andersartiger Ton wäre nur Unruhe.
        buffers[.done] = buffers[.stop]

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: canonical)
        engine.prepare()
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

    /// Liest die Datei in ihrem eigenen Format ein — ohne jede Umrechnung.
    private static func read(_ name: String) -> AVAudioPCMBuffer? {
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
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 else {
            NSLog("SoundCues: \(name).mp3 konnte nicht gelesen werden")
            return nil
        }
        return buffer
    }

    /// Bringt einen Puffer auf das gemeinsame Format. Stimmt es schon überein — der
    /// Normalfall, weil alle Klänge aus derselben Quelle stammen —, wird der Puffer
    /// unverändert durchgereicht und es findet gar keine Umrechnung statt.
    private static func matched(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }

        guard let converter = AVAudioConverter(from: buffer.format, to: target) else { return nil }
        // Muss eine Datei doch umgerechnet werden, dann wenigstens ordentlich.
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 4_096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var delivered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if delivered {
                // .endOfStream und NICHT .noDataNow: Letzteres heißt „gerade nichts,
                // vielleicht später" — der Wandler hört dann auf, ohne seinen internen
                // Puffer auszuspülen, und das Ende des Klangs wird abgeschnitten.
                status.pointee = .endOfStream
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else {
            NSLog("SoundCues: Umrechnen fehlgeschlagen (\(error?.localizedDescription ?? "leeres Ergebnis"))")
            return nil
        }
        return output
    }

    /// Hebt oder senkt den Puffer auf die Ziel-Lautstärke.
    ///
    /// Gemessen wird die lauteste 300-Millisekunden-Strecke, nicht der Gesamt-RMS:
    /// Ein kurzer Klick und ein langer, leiser Ausklang haben denselben Spitzenwert,
    /// werden aber völlig verschieden laut wahrgenommen. Über die Gesamtlänge zu
    /// mitteln würde einen langen Klang mit viel Stille künstlich hochziehen —
    /// genau der Fall des 1,8 Sekunden langen Fehlertons.
    private static func normalize(_ buffer: AVAudioPCMBuffer) {
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

        let gain = min(targetLoudness / loudness, maxPeak / peak)
        guard abs(gain - 1) > 0.001 else { return }
        for c in 0..<channelCount {
            for i in 0..<frames { channels[c][i] *= gain }
        }
    }
}
