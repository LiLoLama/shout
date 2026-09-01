import Foundation

/// Packt Float-Samples als WAV in den Speicher — für den Upload zu einem
/// Transkriptions-Endpunkt.
///
/// WAV und nicht AAC: Die Endpunkte nehmen es alle, es braucht keinen Encoder
/// (der am Mac den ganzen Strom am Stück verlangen würde) und die Rechnung ist
/// nachvollziehbar — 16 kHz, Mono, 16 bit sind genau 32.000 Byte je Sekunde.
/// Das ist die Grundlage der Fensterung in `AudioWindows`: Die
/// Größenbeschränkung der Endpunkte (25 MB) entspricht damit rund 13 Minuten.
enum WAVEncoder {

    /// Fester Kopf einer unkomprimierten Mono-WAV-Datei.
    static let headerBytes = 44

    static func data(from samples: [Float], sampleRate: Int = 16_000) -> Data {
        let bitsPerSample = 16
        let channels = 1
        let bytesPerSample = bitsPerSample / 8
        let dataBytes = samples.count * bytesPerSample
        let byteRate = sampleRate * channels * bytesPerSample

        var out = Data(capacity: headerBytes + dataBytes)

        func append(_ text: String) { out.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: Int) {
            var v = UInt32(truncatingIfNeeded: value).littleEndian
            withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
        }
        func append16(_ value: Int) {
            var v = UInt16(truncatingIfNeeded: value).littleEndian
            withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
        }

        append("RIFF")
        append32(36 + dataBytes)        // Restlänge ab hier
        append("WAVE")
        append("fmt ")
        append32(16)                    // Länge des fmt-Blocks
        append16(1)                     // PCM, unkomprimiert
        append16(channels)
        append32(sampleRate)
        append32(byteRate)
        append16(channels * bytesPerSample)   // Bytes je Rahmen
        append16(bitsPerSample)
        append("data")
        append32(dataBytes)

        for sample in samples {
            // Begrenzen, nicht überlaufen lassen: Ein übersteuertes Diktat würde
            // sonst als Krachen ankommen statt als lautes Sprechen.
            let clamped = max(-1, min(1, sample))
            append16(Int(clamped * 32_767))
        }
        return out
    }

    /// Wie viele Sekunden Audio in `maxBytes` passen (Kopf eingerechnet).
    static func seconds(fitting maxBytes: Int, sampleRate: Int = 16_000) -> Double {
        Double(max(0, maxBytes - headerBytes)) / Double(sampleRate * 2)
    }
}
