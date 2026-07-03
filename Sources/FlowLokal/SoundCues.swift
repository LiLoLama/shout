import AVFoundation

/// Dezente, synthetisierte Klang-Signale (à la Wispr Flow): ein kurzes, weiches
/// GERÄUSCH — kein Ton. Erzeugt wie ein Tastatur-Anschlag / Holzklopfen aus
/// resonanzgefiltertem Rauschen (Biquad-Bandpass färbt das Noise „holzig", ohne
/// eine echte Tonhöhe): eine kurze Klick-Schicht (Kontakt) plus ein warmer
/// Körper (Bottom-out). Alles zur Laufzeit gerendert, keine Asset-Dateien.
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

        // bodyFreq = Färbung (tief = dumpfer), clickGain = Anteil des Kontakt-Klicks
        // (klein = sanfter), peak = Lautheit (klein = leiser).
        buffers[.start] = renderKey(bodyFreq: 460, bodyDecay: 0.028, clickFreq: 1600, clickGain: 0.14, peak: 0.15, format: format)
        buffers[.stop]  = renderKey(bodyFreq: 340, bodyDecay: 0.034, clickFreq: 1300, clickGain: 0.12, peak: 0.15, format: format)
        buffers[.done]  = renderKey(bodyFreq: 560, bodyDecay: 0.024, clickFreq: 1900, clickGain: 0.17, peak: 0.13, format: format)
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

    // MARK: - Tasten-/Klopf-Geräusch (gefiltertes Rauschen, kein Ton)

    private func renderKey(bodyFreq: Double, bodyDecay: Double, clickFreq: Double,
                           clickGain: Double, peak: Float, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let clickDecay = 0.004
        let total = bodyDecay * 5 + 0.02
        let frames = AVAudioFrameCount(total * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames

        var body = Biquad(bandpass: bodyFreq, q: 1.0, sampleRate: sampleRate)   // weicher Körper (wenig Resonanz)
        var click = Biquad(bandpass: clickFreq, q: 0.7, sampleRate: sampleRate) // dezenter Kontakt-Klick
        // Warme End-Dämpfung (dunkler als zuvor) gegen harsche Höhen.
        let warmAlpha = 1.0 / sampleRate / (1.0 / (2 * .pi * 2200) + 1.0 / sampleRate)
        let attack = 0.004   // sanfter Anschlag statt hartem Einsatz
        var lp = 0.0

        let count = Int(frames)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let atk = t < attack ? 0.5 - 0.5 * cos(.pi * t / attack) : 1.0
            let b = body.process(Double.random(in: -1...1)) * exp(-t / bodyDecay)
            let c = click.process(Double.random(in: -1...1)) * exp(-t / clickDecay) * clickGain
            lp += warmAlpha * ((b + c) * atk - lp)
            samples[i] = Float(lp)
        }

        // Auf Zielpegel normalisieren (Bandpass-Ausgang variiert stark) → verlässliche Lautheit.
        let maxAbs = samples.reduce(Float(0)) { Swift.max($0, abs($1)) }
        let scale = maxAbs > 0 ? peak / maxAbs : 1
        for i in 0..<count {
            let v = samples[i] * scale
            channels[0][i] = v
            if format.channelCount > 1 { channels[1][i] = v }
        }
        return buffer
    }
}

/// Minimaler Biquad-Bandpass (Audio-EQ-Cookbook) — färbt Rauschen ohne echten Ton.
private struct Biquad {
    private let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(bandpass f0: Double, q: Double, sampleRate: Double) {
        let w0 = 2 * .pi * f0 / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        b0 = alpha / a0
        b1 = 0
        b2 = -alpha / a0
        a1 = (-2 * cos(w0)) / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}
