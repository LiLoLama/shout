import AVFoundation

/// Dezente, synthetisierte Klang-Signale (à la Wispr Flow): eher perkussiv als
/// tonal — weiche, dumpfe „Tocks" mit schnellem Abfall. Alles zur Laufzeit
/// gerendert (keine Asset-Dateien, offline). Für den wertigen, gedämpften
/// Charakter: tiefer Körper + Sub-Oktave, ein kurzer Noise-Transient für die
/// Anschlag-Textur und ein Tiefpass, der die Höhen wegnimmt.
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

        // Holz-Knock: freq = Körper-Tonhöhe (tief = warm), decay = SEHR kurz (trocken,
        // perkussiv statt nachschwingend), cutoff = Dämpfung.
        buffers[.start] = renderKnock(freq: 260, decay: 0.032, cutoff: 1500, format: format) // warmes Klopfen
        buffers[.stop]  = renderKnock(freq: 200, decay: 0.040, cutoff: 1300, format: format) // tiefer, schließend
        buffers[.done]  = renderKnock(freq: 320, decay: 0.026, cutoff: 1700, format: format) // kurz & leicht
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

    // MARK: - Holz-Knock-Synthese

    // Nur der tiefe Körper + eine sehr schwache Ober-Mode. Kurz gehalten, damit
    // keine Tonhöhe nachschwingt (das wäre der „Bongo"-Effekt).
    private let modes: [(ratio: Double, gain: Double)] = [(1.0, 1.0), (1.87, 0.10)]

    private func renderKnock(freq: Double, decay: Double, cutoff: Double,
                             format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let total = decay * 3 + 0.02
        let frames = AVAudioFrameCount(total * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames

        let dt = 1.0 / sampleRate
        // Haupt-Tiefpass (warm, hält Höhen fern).
        let alpha = dt / (1.0 / (2 * .pi * cutoff) + dt)
        // Separater, dunklerer Tiefpass NUR für den Anschlag-Noise → warmes „Tock"
        // statt hellem „Tss" (das war das Metallische/Blecherne).
        let noiseAlpha = dt / (1.0 / (2 * .pi * 850) + dt)
        var lp = 0.0, nlp = 0.0

        let count = Int(frames)
        for i in 0..<count {
            let t = Double(i) / sampleRate

            // Sehr kurze, warme Körper-Resonanz — nur „Anfassen", kein Nachklingen.
            var resonance = 0.0
            for m in modes {
                let d = decay / (1.0 + (m.ratio - 1.0) * 1.4)
                resonance += m.gain * sin(2 * .pi * freq * m.ratio * t) * exp(-t / d)
            }
            resonance *= 0.32   // Ton stark zurück → weniger Trommel

            // Anschlag-Geräusch dominiert (der eigentliche „Klopf"), dunkel gefiltert.
            let rawNoise = Double.random(in: -1...1) * exp(-t / 0.009)
            nlp += noiseAlpha * (rawNoise - nlp)
            let knock = nlp * 0.68

            let raw = resonance + knock
            lp += alpha * (raw - lp)
            let value = Float(lp * 0.15)
            channels[0][i] = value
            if format.channelCount > 1 { channels[1][i] = value }
        }
        return buffer
    }
}
