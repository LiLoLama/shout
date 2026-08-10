import AVFoundation
import Foundation

/// Ein Block dekodierter Samples mit seiner Startzeit in der Datei.
struct MediaBlock: Sendable {
    let samples: [Float]
    let startTime: Double
}

/// Bewusst ohne `LocalizedError`: `Loc` ist an den Main-Actor gebunden, dieser
/// Fehler entsteht aber im Decoder-actor. Übersetzt wird erst dort, wo der Text
/// angezeigt wird (`FileTranscriptionQueue.message(for:)`).
enum MediaDecoderError: Error {
    case noAudioTrack
    case unreadable(String)
}

/// Liest eine Audio- oder Videodatei als Folge von 16-kHz-Mono-Blöcken.
///
/// Bewusst blockweise statt „ganze Datei in den Speicher": Eine Stunde Audio wären
/// 230 MB als `[Float]`, und WhisperKits eigene Zerlegung legt eine zweite Kopie
/// daneben. Wichtiger noch — der `Transcriber` ist ein actor, ein Diktat per Hotkey
/// muss also auf den laufenden Aufruf warten. Bei Blöcken von zwei Minuten sind das
/// Sekunden statt der ganzen Datei.
///
/// `AVAssetReader` statt `AVAudioFile`: nur so kommt auch die Tonspur aus
/// Videodateien (MP4, MOV) heraus.
actor MediaDecoder {

    static let sampleRate: Double = 16_000

    private let url: URL
    private let blockSamples: Int
    private let searchSamples: Int

    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// Noch nicht ausgegebene Samples (Rest des letzten Blocks + neu gelesene).
    private var pending: [Float] = []
    /// Bereits ausgegebene Samples — daraus entsteht die Startzeit des nächsten Blocks.
    private var emitted = 0
    private var finished = false

    init(url: URL, blockSeconds: Double = 120, searchSeconds: Double = 30) {
        self.url = url
        self.blockSamples = Int(blockSeconds * Self.sampleRate)
        self.searchSamples = Int(searchSeconds * Self.sampleRate)
    }

    /// Öffnet die Datei und liefert ihre Dauer in Sekunden.
    func open() async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration: Double
        do {
            duration = try await CMTimeGetSeconds(asset.load(.duration))
        } catch {
            throw MediaDecoderError.unreadable(error.localizedDescription)
        }
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw MediaDecoderError.unreadable(error.localizedDescription)
        }
        guard let track = tracks.first else { throw MediaDecoderError.noAudioTrack }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw MediaDecoderError.unreadable(error.localizedDescription)
        }
        // AVAssetReaderTrackOutput rechnet beim Lesen auf das Zielformat um —
        // Abtastrate, Kanalzahl und Float-Format in einem Schritt.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw MediaDecoderError.unreadable("Format nicht unterstützt")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw MediaDecoderError.unreadable(reader.error?.localizedDescription ?? "unbekannt")
        }
        self.reader = reader
        self.output = output
        return duration.isFinite ? max(0, duration) : 0
    }

    /// Nächster Block — `nil`, wenn die Datei zu Ende ist.
    func next() throws -> MediaBlock? {
        guard let reader, let output, !finished else { return nil }

        while pending.count < blockSamples, let buffer = output.copyNextSampleBuffer() {
            pending.append(contentsOf: Self.floats(from: buffer))
        }
        if reader.status == .failed {
            throw MediaDecoderError.unreadable(reader.error?.localizedDescription ?? "unbekannt")
        }

        guard !pending.isEmpty else { finished = true; return nil }

        let cut = pending.count >= blockSamples
            ? Self.cutIndex(in: pending, blockSamples: blockSamples,
                            searchSamples: searchSamples, windowSamples: Int(0.5 * Self.sampleRate))
            : pending.count
        let block = MediaBlock(samples: Array(pending[0..<cut]),
                               startTime: Double(emitted) / Self.sampleRate)
        emitted += cut
        pending.removeFirst(cut)
        if pending.isEmpty, reader.status == .completed { finished = true }
        return block
    }

    // MARK: - Rechnen

    /// Schnittstelle für einen vollen Block: die Mitte des leisesten Fensters im
    /// hinteren Bereich. So fällt die Blockgrenze auf eine Sprechpause statt mitten
    /// in ein Wort. Ist der Puffer kürzer als ein Block, wird gar nicht geschnitten.
    static func cutIndex(in samples: [Float], blockSamples: Int,
                         searchSamples: Int, windowSamples: Int) -> Int {
        guard samples.count >= blockSamples, windowSamples > 1 else { return samples.count }
        let searchStart = max(0, blockSamples - searchSamples)
        guard searchStart + windowSamples <= blockSamples else { return blockSamples }

        var bestIndex = -1
        var bestRMS = Float.greatestFiniteMagnitude
        var i = searchStart
        let step = max(1, windowSamples / 2)      // 50 % Überlappung
        while i + windowSamples <= blockSamples {
            var sum: Float = 0
            for j in i..<(i + windowSamples) { sum += samples[j] * samples[j] }
            let rms = (sum / Float(windowSamples)).squareRoot()
            if rms < bestRMS { bestRMS = rms; bestIndex = i }
            i += step
        }
        guard bestIndex >= 0 else { return blockSamples }
        return min(blockSamples, bestIndex + windowSamples / 2)
    }

    /// Samples aus einem CMSampleBuffer holen (Float32, mono, wie oben angefordert).
    private static func floats(from buffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length,
                                          dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let pointer, length > 0 else { return [] }
        let count = length / MemoryLayout<Float>.size
        return pointer.withMemoryRebound(to: Float.self, capacity: count) {
            Array(UnsafeBufferPointer(start: $0, count: count))
        }
    }
}
