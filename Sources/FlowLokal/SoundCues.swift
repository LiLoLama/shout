import AVFoundation

/// Leise, synthetisierte Klang-Signale: dumpfe Wood-Taps statt Piepsen.
///
/// Jeder Cue ist ein kleines, gefiltertes Rauschereignis mit mehreren breiten
/// Holz-Resonanzen. Dadurch entsteht ein weicher, tiefer perkussiver Körper,
/// aber keine stabile Tonhöhe und kein harter Klick.
@MainActor
final class SoundCues {
    enum Cue { case start, stop, done, error }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44_100.0
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var playToken = 0   // erkennt, ob seit dem Scheduling ein neuer Cue kam

    private var enabled: Bool { UserDefaults.standard.object(forKey: "soundCuesEnabled") as? Bool ?? true }

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()

        buffers[.start] = renderWoodCue(
            taps: [
                WoodTap(
                    offset: 0,
                    seed: 0xA17B_01,
                    gain: 1,
                    duration: 0.155,
                    bodyBurstDecay: 0.040,
                    contactFrequency: 640,
                    contactGain: 0.008,
                    warmthCutoff: 1_050,
                    modes: [
                        WoodMode(frequency: 155, q: 0.44, gain: 0.54, decay: 0.070),
                        WoodMode(frequency: 315, q: 0.48, gain: 0.34, decay: 0.055),
                        WoodMode(frequency: 520, q: 0.42, gain: 0.16, decay: 0.040),
                        WoodMode(frequency: 760, q: 0.35, gain: 0.045, decay: 0.024)
                    ]
                )
            ],
            peak: 0.090,
            format: format
        )

        buffers[.stop] = renderWoodCue(
            taps: [
                WoodTap(
                    offset: 0,
                    seed: 0x570F_02,
                    gain: 1,
                    duration: 0.175,
                    bodyBurstDecay: 0.046,
                    contactFrequency: 520,
                    contactGain: 0.007,
                    warmthCutoff: 890,
                    modes: [
                        WoodMode(frequency: 120, q: 0.46, gain: 0.58, decay: 0.084),
                        WoodMode(frequency: 245, q: 0.50, gain: 0.35, decay: 0.064),
                        WoodMode(frequency: 430, q: 0.42, gain: 0.15, decay: 0.044),
                        WoodMode(frequency: 660, q: 0.35, gain: 0.040, decay: 0.026)
                    ]
                )
            ],
            peak: 0.088,
            format: format
        )

        buffers[.done] = renderWoodCue(
            taps: [
                WoodTap(
                    offset: 0,
                    seed: 0xD0AE_03,
                    gain: 1,
                    duration: 0.140,
                    bodyBurstDecay: 0.034,
                    contactFrequency: 720,
                    contactGain: 0.006,
                    warmthCutoff: 1_160,
                    modes: [
                        WoodMode(frequency: 185, q: 0.42, gain: 0.50, decay: 0.062),
                        WoodMode(frequency: 370, q: 0.46, gain: 0.32, decay: 0.048),
                        WoodMode(frequency: 610, q: 0.40, gain: 0.13, decay: 0.034),
                        WoodMode(frequency: 850, q: 0.34, gain: 0.035, decay: 0.020)
                    ]
                )
            ],
            peak: 0.080,
            format: format
        )

        // Fehler: ein sehr dunkles Doppelklopfen, bewusst ohne Alarm- oder Klick-Anteil.
        buffers[.error] = renderWoodCue(
            taps: [
                WoodTap(
                    offset: 0,
                    seed: 0xE440_04,
                    gain: 1,
                    duration: 0.185,
                    bodyBurstDecay: 0.052,
                    contactFrequency: 420,
                    contactGain: 0.006,
                    warmthCutoff: 780,
                    modes: [
                        WoodMode(frequency: 105, q: 0.48, gain: 0.60, decay: 0.090),
                        WoodMode(frequency: 215, q: 0.48, gain: 0.35, decay: 0.068),
                        WoodMode(frequency: 380, q: 0.40, gain: 0.14, decay: 0.045),
                        WoodMode(frequency: 560, q: 0.34, gain: 0.035, decay: 0.026)
                    ]
                ),
                WoodTap(
                    offset: 0.105,
                    seed: 0xE440_05,
                    gain: 0.64,
                    duration: 0.175,
                    bodyBurstDecay: 0.046,
                    contactFrequency: 380,
                    contactGain: 0.004,
                    warmthCutoff: 720,
                    modes: [
                        WoodMode(frequency: 98, q: 0.46, gain: 0.60, decay: 0.086),
                        WoodMode(frequency: 205, q: 0.46, gain: 0.34, decay: 0.064),
                        WoodMode(frequency: 360, q: 0.40, gain: 0.13, decay: 0.043),
                        WoodMode(frequency: 520, q: 0.34, gain: 0.030, decay: 0.025)
                    ]
                )
            ],
            peak: 0.090,
            format: format
        )
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

    // MARK: - Wood-tap rendering

    private func renderWoodCue(taps: [WoodTap], peak: Float, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let total = (taps.map { $0.offset + $0.duration }.max() ?? 0.100) + 0.012
        let frames = AVAudioFrameCount(ceil(total * sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames

        let count = Int(frames)
        var samples = [Double](repeating: 0, count: count)
        for tap in taps {
            render(tap, into: &samples)
        }

        let maxAbs = samples.reduce(0.0) { Swift.max($0, abs($1)) }
        let scale = maxAbs > 0 ? Double(peak) / maxAbs : 1
        for i in 0..<count {
            let v = Float(samples[i] * scale)
            channels[0][i] = v
            if format.channelCount > 1 { channels[1][i] = v }
        }
        return buffer
    }

    private func render(_ tap: WoodTap, into samples: inout [Double]) {
        let start = Int(tap.offset * sampleRate)
        guard start < samples.count else { return }

        var noise = SeededNoise(seed: tap.seed)
        var bodyNoiseLowpass = OnePoleLowpass(cutoff: tap.warmthCutoff * 0.52, sampleRate: sampleRate)
        var outputLowpass = OnePoleLowpass(cutoff: tap.warmthCutoff, sampleRate: sampleRate)
        var dcBlocker = OnePoleHighpass(cutoff: 65, sampleRate: sampleRate)
        var contact = Biquad(bandpass: tap.contactFrequency, q: 0.30, sampleRate: sampleRate)
        var voices = tap.modes.map { WoodVoice(mode: $0, sampleRate: sampleRate) }

        let frameCount = min(Int(tap.duration * sampleRate), samples.count - start)
        for localFrame in 0..<frameCount {
            let t = Double(localFrame) / sampleRate
            let warmNoise = bodyNoiseLowpass.process(noise.nextBipolar())
            let strike = softEnvelope(t, attack: 0.0075, decay: tap.bodyBurstDecay)
            let contactEnvelope = softEnvelope(t, attack: 0.0050, decay: 0.0110)

            var body = 0.0
            for i in voices.indices {
                let mode = tap.modes[i]
                let modeEnvelope = exp(-t / mode.decay)
                body += voices[i].process(warmNoise * strike) * mode.gain * modeEnvelope
            }

            let contactNoise = noise.nextBipolar() * 0.25 + warmNoise * 0.75
            let contactLayer = contact.process(contactNoise) * contactEnvelope * tap.contactGain
            var value = (body + contactLayer) * tap.gain
            value = outputLowpass.process(value)
            value = dcBlocker.process(value)
            value = softLimit(value)
            value *= tailFade(t, duration: tap.duration, fade: 0.026)
            samples[start + localFrame] += value
        }
    }

    private func softEnvelope(_ t: Double, attack: Double, decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        let attackShape = t < attack ? 0.5 - 0.5 * cos(.pi * t / attack) : 1.0
        return attackShape * exp(-Swift.max(0, t - attack) / decay)
    }

    private func tailFade(_ t: Double, duration: Double, fade: Double) -> Double {
        let remaining = duration - t
        guard remaining < fade else { return 1 }
        let progress = Swift.max(0, remaining / fade)
        return 0.5 - 0.5 * cos(.pi * progress)
    }

    private func softLimit(_ x: Double) -> Double {
        let driven = x * 0.95
        return driven / (1 + abs(driven) * 0.35)
    }
}

private struct WoodTap {
    let offset: Double
    let seed: UInt64
    let gain: Double
    let duration: Double
    let bodyBurstDecay: Double
    let contactFrequency: Double
    let contactGain: Double
    let warmthCutoff: Double
    let modes: [WoodMode]
}

private struct WoodMode {
    let frequency: Double
    let q: Double
    let gain: Double
    let decay: Double
}

private struct WoodVoice {
    private var filter: Biquad

    init(mode: WoodMode, sampleRate: Double) {
        filter = Biquad(bandpass: mode.frequency, q: mode.q, sampleRate: sampleRate)
    }

    mutating func process(_ x: Double) -> Double {
        filter.process(x)
    }
}

/// Repeatable noise keeps the app cue identical between launches.
private struct SeededNoise {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func nextBipolar() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let mantissa = state >> 11
        let unit = Double(mantissa) / 9_007_199_254_740_992.0
        return unit * 2 - 1
    }
}

private struct OnePoleLowpass {
    private let alpha: Double
    private var y = 0.0

    init(cutoff: Double, sampleRate: Double) {
        let dt = 1 / sampleRate
        let rc = 1 / (2 * .pi * cutoff)
        alpha = dt / (rc + dt)
    }

    mutating func process(_ x: Double) -> Double {
        y += alpha * (x - y)
        return y
    }
}

private struct OnePoleHighpass {
    private let alpha: Double
    private var previousX = 0.0
    private var previousY = 0.0

    init(cutoff: Double, sampleRate: Double) {
        let dt = 1 / sampleRate
        let rc = 1 / (2 * .pi * cutoff)
        alpha = rc / (rc + dt)
    }

    mutating func process(_ x: Double) -> Double {
        let y = alpha * (previousY + x - previousX)
        previousX = x
        previousY = y
        return y
    }
}

/// Minimaler Biquad-Bandpass (Audio-EQ-Cookbook) fuer breite Holzfaerbung.
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
