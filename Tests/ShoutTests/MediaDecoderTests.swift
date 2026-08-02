import AVFoundation
import XCTest

final class MediaDecoderTests: XCTestCase {

    // MARK: - Hilfsmittel

    /// Schreibt eine WAV-Datei: Sinuston, unterbrochen von einer Stille-Lücke.
    /// `silence` ist der Bereich in Sekunden, der stumm bleibt.
    private func writeWAV(seconds: Double, sampleRate: Double = 44_100,
                          silence: ClosedRange<Double>? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mediadecoder-\(UUID().uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let total = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total)!
        buffer.frameLength = total
        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(total) {
            let t = Double(frame) / sampleRate
            let quiet = silence?.contains(t) ?? false
            channel[frame] = quiet ? 0 : Float(sin(2 * Double.pi * 440 * t)) * 0.5
        }
        try file.write(from: buffer)
        return url
    }

    /// Schreibt eine echte Videodatei (.mov) mit Bild- UND Tonspur. Damit ist geprüft,
    /// dass `AVAssetReader` die Tonspur aus einem Videocontainer zieht — der Grund,
    /// warum der Dekoder nicht auf `AVAudioFile` aufsetzt.
    private func writeMovieWithAudio(seconds: Double) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mediadecoder-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let sampleRate = 44_100.0
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ])
        audioInput.expectsMediaDataInRealTime = false
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160,
            AVVideoHeightKey: 120,
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String:
                                            kCVPixelFormatType_32ARGB])
        writer.add(audioInput)
        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Bildspur: ein schwarzes Bild pro Sekunde reicht — geprüft wird der Ton.
        var pool: CVPixelBuffer?
        CVPixelBufferCreate(nil, 160, 120, kCVPixelFormatType_32ARGB, nil, &pool)
        if let pixelBuffer = pool {
            for second in 0..<Int(seconds) {
                while !videoInput.isReadyForMoreMediaData { await Task.yield() }
                adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(second), timescale: 1))
            }
        }
        videoInput.markAsFinished()

        // Tonspur: aus einer WAV-Datei einlesen und durchreichen — so entstehen die
        // CMSampleBuffer, die der Writer erwartet, ohne Handarbeit an CMBlockBuffern.
        let wav = try writeWAV(seconds: seconds, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: wav) }
        let source = AVURLAsset(url: wav)
        let sourceTracks = try await source.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: source)
        let readerOutput = AVAssetReaderTrackOutput(track: sourceTracks[0], outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(readerOutput)
        reader.startReading()
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            while !audioInput.isReadyForMoreMediaData { await Task.yield() }
            audioInput.append(sampleBuffer)
        }
        audioInput.markAsFinished()

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                                        writer.error?.localizedDescription ?? "Schreiben fehlgeschlagen"])
        }
        return url
    }

    // MARK: - Schnitt an der leisesten Stelle

    func testSchnittLandetInDerStilleLuecke() {
        // 10 Blöcke à 1000 Samples: laut, außer Block 8 (Index 8000…8999).
        var samples = [Float](repeating: 0.5, count: 10_000)
        for i in 8_000..<9_000 { samples[i] = 0 }
        let cut = MediaDecoder.cutIndex(in: samples, blockSamples: 10_000,
                                        searchSamples: 4_000, windowSamples: 1_000)
        XCTAssertGreaterThanOrEqual(cut, 8_000)
        XCTAssertLessThanOrEqual(cut, 9_500)
    }

    func testZuKurzerPufferWirdNichtGeschnitten() {
        let samples = [Float](repeating: 0.5, count: 500)
        XCTAssertEqual(MediaDecoder.cutIndex(in: samples, blockSamples: 10_000,
                                             searchSamples: 4_000, windowSamples: 1_000), 500)
    }

    func testSchnittLiegtImmerImSuchbereich() {
        let samples = [Float](repeating: 0.5, count: 10_000)   // gleichmäßig laut
        let cut = MediaDecoder.cutIndex(in: samples, blockSamples: 10_000,
                                        searchSamples: 4_000, windowSamples: 1_000)
        XCTAssertGreaterThanOrEqual(cut, 6_000)
        XCTAssertLessThanOrEqual(cut, 10_000)
    }

    // MARK: - Dekodieren

    func testDauerUndAbtastrate() async throws {
        let url = try writeWAV(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = MediaDecoder(url: url, blockSeconds: 10, searchSeconds: 1)
        let duration = try await decoder.open()
        XCTAssertEqual(duration, 3, accuracy: 0.1)

        var total = 0
        while let block = try await decoder.next() { total += block.samples.count }
        // 3 s bei 16 kHz — Umrechnung darf ein paar Puffer Toleranz haben.
        XCTAssertEqual(Double(total) / MediaDecoder.sampleRate, 3, accuracy: 0.2)
    }

    func testBlockgrenzenUndStartzeiten() async throws {
        let url = try writeWAV(seconds: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = MediaDecoder(url: url, blockSeconds: 1, searchSeconds: 0.25)
        _ = try await decoder.open()

        var blocks: [MediaBlock] = []
        while let block = try await decoder.next() { blocks.append(block) }

        XCTAssertGreaterThanOrEqual(blocks.count, 4, "5 s bei 1-s-Blöcken → mindestens 4 Blöcke")
        // Startzeiten laufen lückenlos: jede Startzeit = Summe der bisherigen Längen.
        var expected = 0.0
        for block in blocks {
            XCTAssertEqual(block.startTime, expected, accuracy: 0.001)
            expected += Double(block.samples.count) / MediaDecoder.sampleRate
        }
    }

    /// Der eigentliche Grund für AVAssetReader: die Tonspur aus einem Video.
    func testVideodateiWirdGelesen() async throws {
        let url = try await writeMovieWithAudio(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = MediaDecoder(url: url, blockSeconds: 10, searchSeconds: 1)
        let duration = try await decoder.open()
        XCTAssertEqual(duration, 3, accuracy: 0.3)

        var total = 0
        while let block = try await decoder.next() { total += block.samples.count }
        XCTAssertEqual(Double(total) / MediaDecoder.sampleRate, 3, accuracy: 0.3)
    }

    func testDateiOhneTonspurWirftFehler() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kein-audio-\(UUID().uuidString).txt")
        try "kein Audio".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = MediaDecoder(url: url)
        do {
            _ = try await decoder.open()
            XCTFail("Erwartet: Fehler für eine Datei ohne Tonspur")
        } catch {
            // erwartet
        }
    }
}
