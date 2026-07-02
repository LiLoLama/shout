import Foundation
import Combine
import CryptoKit

/// Lizenzmodell: **Einmalkauf mit 14-Tage-Testphase.**
/// - Während der Testphase (14 Tage ab erstem Start) volle Funktion.
/// - Ein gekaufter, offline signierter Schlüssel (Ed25519) schaltet dauerhaft frei.
/// - Nach Ablauf ohne Lizenz ist das Diktieren gesperrt.
/// Alles lokal, kein Server.
@MainActor
final class LicenseStore: ObservableObject {

    @Published private(set) var isLicensed = false
    @Published private(set) var licensedTo = ""
    @Published private(set) var trialStart: Date

    let trialDays = 14
    private let publicKeyBase64 = "uKfo4VRAeKx1cfne/qrmje7WAWqrnKUjzRJr1Owhvts="
    private let storageKey = "licenseKey"
    private let trialFileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("shout", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        trialFileURL = dir.appendingPathComponent("trial.json")

        // Trial-Start laden oder beim ersten Mal setzen.
        if let raw = try? Data(contentsOf: trialFileURL),
           let stored = try? JSONDecoder().decode([String: Date].self, from: raw),
           let start = stored["start"] {
            trialStart = start
        } else {
            let now = Date()
            trialStart = now
            if let data = try? JSONEncoder().encode(["start": now]) {
                try? data.write(to: trialFileURL, options: .atomic)
            }
        }

        if let stored = UserDefaults.standard.string(forKey: storageKey),
           let licensee = verify(stored) {
            isLicensed = true
            licensedTo = licensee
        }
    }

    // MARK: - Status

    var trialDaysRemaining: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
        return max(0, trialDays - elapsed)
    }
    var isTrialActive: Bool { trialDaysRemaining > 0 }
    /// Darf die App genutzt werden (Diktieren)? Lizenz oder laufende Testphase.
    var isActive: Bool { isLicensed || isTrialActive }

    // MARK: - Lizenz

    @discardableResult
    func activate(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let licensee = verify(trimmed) else { return false }
        UserDefaults.standard.set(trimmed, forKey: storageKey)
        isLicensed = true
        licensedTo = licensee
        return true
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        isLicensed = false
        licensedTo = ""
    }

    private func verify(_ key: String) -> String? {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let payload = Data(base64Encoded: parts[0]),
              let signature = Data(base64Encoded: parts[1]),
              let pubData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData),
              publicKey.isValidSignature(signature, for: payload),
              let licensee = String(data: payload, encoding: .utf8)
        else { return nil }
        return licensee
    }
}
