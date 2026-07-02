import Foundation
import Combine
import CryptoKit

/// Lokales Lizenzsystem — kein Server nötig. Lizenzschlüssel sind offline mit
/// einem privaten Ed25519-Schlüssel signiert; die App prüft die Signatur gegen
/// den eingebetteten Public Key. Format: "<payloadBase64>.<signaturBase64>",
/// wobei payload der Lizenznehmer-Text ist.
@MainActor
final class LicenseStore: ObservableObject {

    @Published private(set) var isPro = false
    @Published private(set) var licensedTo = ""

    private let publicKeyBase64 = "uKfo4VRAeKx1cfne/qrmje7WAWqrnKUjzRJr1Owhvts="
    private let storageKey = "licenseKey"

    init() {
        // Beim Start den gespeicherten Schlüssel erneut verifizieren (nicht nur ein Flag).
        if let stored = UserDefaults.standard.string(forKey: storageKey),
           let licensee = verify(stored) {
            isPro = true
            licensedTo = licensee
        }
    }

    /// Prüft und aktiviert einen Schlüssel. Gibt true bei gültiger Signatur zurück.
    @discardableResult
    func activate(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let licensee = verify(trimmed) else { return false }
        UserDefaults.standard.set(trimmed, forKey: storageKey)
        isPro = true
        licensedTo = licensee
        return true
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        isPro = false
        licensedTo = ""
    }

    // MARK: - Verifikation

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
