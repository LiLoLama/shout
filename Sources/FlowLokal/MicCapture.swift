#if os(macOS)
import AVFoundation
import os

/// Mikrofon-Aufnahme am Mac über `AVCaptureSession`, geliefert als 16-kHz-Mono-Float.
///
/// Warum nicht `AVAudioEngine` wie am iPhone: Am Mac baut die Engine aus Ein- und
/// Ausgabe ein gemeinsames Aggregat und will bei Bluetooth-Geräten das Format der
/// Kopfhörer selbst umstellen. Mit AirPods führte das zu drei Fehlerbildern
/// (04.11.2026): Die Aufnahme verstummte, sobald die AirPods ins Headset-Profil
/// wechselten. Bei ausdrücklich gewählten AirPods wartete die Engine bis zu drei
/// Sekunden auf dem Hauptthread auf einen Formatwechsel. Danach meldete sie 48 kHz,
/// während die Hardware mit 24 kHz lief, und die Aufnahme kam gar nicht in Gang.
///
/// Die Capture-Session fasst die Ausgabe nicht an, wählt das Gerät direkt über
/// seine Core-Audio-UID und rechnet selbst ins Zielformat um, auch wenn das Gerät
/// mittendrin die Rate wechselt.
final class MicCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {

    private static let log = Logger(subsystem: "com.inthezone.flowlokal", category: "aufnahme")

    /// Start und Stopp blockieren — deshalb eine eigene Warteschlange, getrennt von
    /// der, auf der die Puffer ankommen.
    private let sessionQueue = DispatchQueue(label: "shout.mic.session")
    private let sampleQueue = DispatchQueue(label: "shout.mic.samples", qos: .userInteractive)

    private var session: AVCaptureSession?
    private var onSamples: (([Float]) -> Void)?
    private var runtimeObserver: NSObjectProtocol?

    /// Baut die Session für `deviceUID` (nil oder nicht angeschlossen = Systemstandard)
    /// und startet sie im Hintergrund. Wirft, wenn das Gerät sich nicht öffnen lässt.
    /// `onSamples` läuft auf einer eigenen Warteschlange, nie auf dem Main-Thread.
    func start(deviceUID: String?, onSamples: @escaping ([Float]) -> Void) throws {
        stop()

        let device = deviceUID.flatMap { AVCaptureDevice(uniqueID: $0) }
            ?? AVCaptureDevice.default(for: .audio)
        guard let device else {
            throw NSError(domain: "shout.MicCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Kein Mikrofon gefunden."])
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "shout.MicCapture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Mikrofon „\(device.localizedName)“ lässt sich nicht verwenden."])
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        // Gleich im Format, das Whisper braucht. Die Umrechnung übernimmt die
        // Session, auch wenn das Gerät während der Aufnahme die Rate wechselt.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "shout.MicCapture", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Audio-Ausgang der Aufnahme ließ sich nicht anlegen."])
        }
        session.addOutput(output)
        session.commitConfiguration()

        sampleQueue.sync { self.onSamples = onSamples }
        self.session = session

        runtimeObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { [weak self, weak session] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            Self.log.error("Aufnahme-Session meldet einen Fehler, starte neu: \(error?.localizedDescription ?? "unbekannt", privacy: .public)")
            self?.sessionQueue.async { session?.startRunning() }
        }

        let name = device.localizedName
        sessionQueue.async {
            let started = Date()
            session.startRunning()
            Self.log.info("Mikrofon „\(name, privacy: .public)“ offen nach \(Date().timeIntervalSince(started) * 1000, format: .fixed(precision: 0), privacy: .public) ms")
        }
    }

    /// Hält die Session an. Kehrt erst zurück, wenn auch der letzte schon
    /// gelieferte Puffer bei `onSamples` angekommen ist.
    func stop() {
        if let runtimeObserver { NotificationCenter.default.removeObserver(runtimeObserver) }
        runtimeObserver = nil
        guard let session else { return }
        self.session = nil
        sessionQueue.sync { session.stopRunning() }
        sampleQueue.sync { self.onSamples = nil }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let onSamples, let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(block)
        let count = length / MemoryLayout<Float>.size
        guard count > 0 else { return }
        var chunk = [Float](repeating: 0, count: count)
        let status = chunk.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                       destination: raw.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { return }
        onSamples(chunk)
    }
}
#endif
