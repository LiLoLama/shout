import AVFoundation

/// Dezente, synthetisierte Klang-Signale (à la Wispr Flow): kurz, weich, warm —
/// keine Asset-Dateien, alles zur Laufzeit gerendert. Reine Sinustöne mit sanfter
/// Hüllkurve und leiser Oktav-Beimischung wirken wertig statt „System-Beep".
@MainActor
final class SoundCues {
    enum Cue { case start, stop, done }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44_100.0
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var started = false

    private var enabled: Bool { UserDefaults.standard.object(forKey: "soundCuesEnabled") as? Bool ?? true }

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Kurze, sanft ansteigende bzw. abfallende Zwei-/Einton-Motive.
        buffers[.start] = render([(587.33, 0.00, 0.10), (880.00, 0.05, 0.14)], format: format) // D5 → A5, „hört zu"
        buffers[.stop]  = render([(783.99, 0.00, 0.09), (523.25, 0.05, 0.13)], format: format) // G5 → C5, „aufgenommen"
        buffers[.done]  = render([(659.25, 0.00, 0.08), (987.77, 0.05, 0.15)], format: format) // E5 → B5, „fertig"
    }

    func play(_ cue: Cue) {
        guard enabled, let buffer = buffers[cue] else { return }
        do {
            if !started { try engine.start(); started = true }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            if !player.isPlaying { player.play() }
        } catch {
            NSLog("SoundCues: Wiedergabe fehlgeschlagen: \(error)")
        }
    }

    // MARK: - Synthese

    private func render(_ notes: [(freq: Double, start: Double, dur: Double)],
                        format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let total = (notes.map { $0.start + $0.dur }.max() ?? 0.2) + 0.03
        let frames = AVAudioFrameCount(total * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames

        let count = Int(frames)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for note in notes {
                let local = t - note.start
                guard local >= 0, local <= note.dur else { continue }
                let env = envelope(local, dur: note.dur)
                let fundamental = sin(2 * .pi * note.freq * local)
                let octave = 0.16 * sin(2 * .pi * note.freq * 2 * local)   // Wärme
                sample += env * (fundamental + octave)
            }
            let value = Float(sample * 0.15)   // leiser Master-Pegel
            channels[0][i] = value
            if format.channelCount > 1 { channels[1][i] = value }
        }
        return buffer
    }

    /// Sanfte Hüllkurve: kurzer Attack, weicher Release — kein Knacken.
    private func envelope(_ t: Double, dur: Double) -> Double {
        let attack = 0.010
        let release = min(0.07, dur * 0.6)
        if t < attack { return t / attack }
        if t > dur - release { return max(0, (dur - t) / release) }
        return 1
    }
}
