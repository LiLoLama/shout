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

        // Weicher, hoher „Pop": freq = Tonhöhe, glide = organischer Pitch-Settle,
        // decay = Länge (kurz), cutoff = Dämpfung der Höhen.
        buffers[.start] = renderBlip(freq: 659, glide: 0.05, decay: 0.055, cutoff: 4200, format: format) // E5 – sanfter Pop
        buffers[.stop]  = renderBlip(freq: 523, glide: 0.05, decay: 0.060, cutoff: 3600, format: format) // C5 – tiefer, schließend
        buffers[.done]  = renderBlip(freq: 880, glide: -0.04, decay: 0.050, cutoff: 4800, format: format) // A5 – heller, steigend
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

    // MARK: - Weicher „Pop" (wertig, organisch, warm)

    /// Ein kurzer, runder Ton mit weicher Hüllkurve und leichtem Pitch-Settle
    /// (organisch, „tröpfchenhaft"). Grundton + warme Sub-Oktave + dezenter
    /// Oktav-Schimmer, sanft tiefpassgefiltert. `glide` > 0 = fällt leicht ein,
    /// `glide` < 0 = steigt leicht (positiver Abschluss).
    private func renderBlip(freq: Double, glide: Double, decay: Double, cutoff: Double,
                            format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let total = decay * 4 + 0.03
        let frames = AVAudioFrameCount(total * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames

        let dt = 1.0 / sampleRate
        let alpha = dt / (1.0 / (2 * .pi * cutoff) + dt)
        let attack = 0.008
        var lp = 0.0
        var phase = 0.0   // integrierte Phase (nötig wegen Pitch-Glide)

        let count = Int(frames)
        for i in 0..<count {
            let t = Double(i) / sampleRate

            // Tonhöhe pendelt in ~35 ms organisch auf den Zielton ein.
            let f = freq * (1 + glide * exp(-t / 0.035))
            phase += 2 * .pi * f * dt

            // Weiche Hüllkurve: sanfter (Cosinus-)Attack, exponentieller Abfall,
            // kurzer End-Fade gegen Knacken.
            let a = t < attack ? 0.5 - 0.5 * cos(.pi * t / attack) : 1.0
            let endFade = min(1.0, max(0.0, (total - t) / 0.012))
            let env = a * exp(-t / decay) * endFade

            // Warm & rund: Grundton + Sub-Oktave (Wärme) + leiser Oktav-Schimmer.
            let s = sin(phase) + 0.25 * sin(0.5 * phase) + 0.12 * sin(2 * phase)

            lp += alpha * (env * s - lp)
            let value = Float(lp * 0.16)
            channels[0][i] = value
            if format.channelCount > 1 { channels[1][i] = value }
        }
        return buffer
    }
}
