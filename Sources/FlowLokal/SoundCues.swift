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

        // Holz-Knock: freq = Resonanz-Tonhöhe, decay = (kurzer) Abfall, cutoff = Dämpfung.
        buffers[.start] = renderKnock(freq: 430, decay: 0.050, cutoff: 2400, format: format) // Klopfen, mittig
        buffers[.stop]  = renderKnock(freq: 300, decay: 0.060, cutoff: 1900, format: format) // tiefer, schließend
        buffers[.done]  = renderKnock(freq: 540, decay: 0.038, cutoff: 2700, format: format) // kurz & leicht
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

    // Inharmonische Moden (wie ein angeschlagener Holzkörper) — bewusst NICHT
    // ganzzahlig, damit es hölzern statt tonal klingt.
    private let modes: [(ratio: Double, gain: Double)] = [(1.0, 1.0), (2.42, 0.5), (4.10, 0.28)]

    private func renderKnock(freq: Double, decay: Double, cutoff: Double,
                             format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let total = decay * 3 + 0.02
        let frames = AVAudioFrameCount(total * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames

        // Ein-Pol-Tiefpass gegen harsche Höhen (hält es weich/hölzern).
        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2 * .pi * cutoff)
        let alpha = dt / (rc + dt)
        var lp = 0.0

        let count = Int(frames)
        for i in 0..<count {
            let t = Double(i) / sampleRate

            // Kurze, inharmonische Resonanz — höhere Moden klingen schneller ab.
            var resonance = 0.0
            for m in modes {
                let d = decay / (1.0 + (m.ratio - 1.0) * 0.7)
                resonance += m.gain * sin(2 * .pi * freq * m.ratio * t) * exp(-t / d)
            }
            resonance *= 0.40   // Ton bewusst zurücknehmen

            // Anschlag-Geräusch: prägt den „Klopf"-Charakter, dominiert kurz.
            let knock = Double.random(in: -1...1) * exp(-t / 0.006) * 0.75

            let raw = resonance + knock
            lp += alpha * (raw - lp)
            let value = Float(lp * 0.17)   // leiser als zuvor
            channels[0][i] = value
            if format.channelCount > 1 { channels[1][i] = value }
        }
        return buffer
    }
}
