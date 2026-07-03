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

        // freq = Körper-Tonhöhe, decay = Abfall (perkussiv), cutoff = Dämpfung (klein = dumpfer).
        buffers[.start] = renderHit(freq: 250, decay: 0.075, cutoff: 1400, click: 0.30, format: format) // „tuk" – mittig
        buffers[.stop]  = renderHit(freq: 165, decay: 0.105, cutoff: 900,  click: 0.20, format: format) // „tok" – tiefer, schließend
        buffers[.done]  = renderHit(freq: 320, decay: 0.060, cutoff: 1600, click: 0.34, format: format) // kurzer, heller Anschlag
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

    // MARK: - Perkussions-Synthese

    private func renderHit(freq: Double, decay: Double, cutoff: Double,
                           click: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let total = decay * 4 + 0.02
        let frames = AVAudioFrameCount(total * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames

        // Ein-Pol-Tiefpass (rundet den Anschlag ab → dumpf/wertig).
        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2 * .pi * cutoff)
        let alpha = dt / (rc + dt)
        var lp = 0.0

        let count = Int(frames)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let env = exp(-t / decay)                                   // perkussiver Abfall
            let body = sin(2 * .pi * freq * t)
                     + 0.45 * sin(2 * .pi * (freq / 2) * t)             // Sub-Oktave = Gewicht
            let clickEnv = exp(-t / 0.005)                              // sehr kurzer Anschlag
            let clk = click * sin(2 * .pi * freq * 4 * t) * clickEnv
            let noise = (Double.random(in: -1...1)) * exp(-t / 0.010) * 0.12  // „Tap"-Textur

            let raw = env * (body * 0.9 + noise) + clk * 0.5
            lp += alpha * (raw - lp)                                    // Tiefpass
            let value = Float(lp * 0.26)                               // leiser Master-Pegel
            channels[0][i] = value
            if format.channelCount > 1 { channels[1][i] = value }
        }
        return buffer
    }
}
