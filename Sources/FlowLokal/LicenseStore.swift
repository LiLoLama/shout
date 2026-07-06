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

    // Keychain-Konten (Zweitanker gegen einfaches Löschen der Klartext-Datei).
    private static let kcTrialStart = "trialStart"
    private static let kcLastSeen = "trialLastSeen"
    private static let kcLicense = "licenseKey"

    /// Zuletzt gesehene Zeit (Monotonie-Anker gegen Zurückstellen der Systemuhr).
    private var lastSeen: Date

    init() {
        let url = StoreIO.directory().appendingPathComponent("trial.json")
        trialFileURL = url

        // Trial-Start aus beiden Ankern lesen und den FRÜHESTEN nehmen — so setzt
        // das Löschen einer einzelnen Quelle die Testphase nicht mehr zurück.
        let fromFile: Date? = {
            guard let raw = try? Data(contentsOf: url),
                  let stored = try? JSONDecoder().decode([String: Date].self, from: raw) else { return nil }
            return stored["start"]
        }()
        let fromKeychain = Keychain.get(Self.kcTrialStart).flatMap(Double.init)
            .map { Date(timeIntervalSinceReferenceDate: $0) }

        let resolvedStart = [fromFile, fromKeychain].compactMap { $0 }.min() ?? Date()
        trialStart = resolvedStart

        // Monotonie: gespeicherte "zuletzt gesehen"-Zeit; künftig nie kleiner als jetzt.
        let storedLastSeen = Keychain.get(Self.kcLastSeen).flatMap(Double.init)
            .map { Date(timeIntervalSinceReferenceDate: $0) }
        lastSeen = max(Date(), storedLastSeen ?? Date())

        // Beide Anker (heilend) zurückschreiben.
        Self.writeTrialFile(resolvedStart, to: trialFileURL)
        Keychain.set(String(resolvedStart.timeIntervalSinceReferenceDate), for: Self.kcTrialStart)
        Keychain.set(String(lastSeen.timeIntervalSinceReferenceDate), for: Self.kcLastSeen)

        // Lizenzschlüssel: bevorzugt aus der Keychain; Altbestand aus UserDefaults migrieren.
        if let stored = Keychain.get(Self.kcLicense) ?? UserDefaults.standard.string(forKey: storageKey),
           let licensee = verify(stored) {
            isLicensed = true
            licensedTo = licensee
            Keychain.set(stored, for: Self.kcLicense)
            UserDefaults.standard.removeObject(forKey: storageKey)   // Klartext entfernen
        }
    }

    // MARK: - Status

    var trialDaysRemaining: Int {
        // Uhr-Rückstellung abfangen: nie „jünger" als der Monotonie-Anker rechnen.
        let now = max(Date(), lastSeen)
        let elapsed = Calendar.current.dateComponents([.day], from: trialStart, to: now).day ?? 0
        return max(0, trialDays - max(0, elapsed))
    }
    var isTrialActive: Bool { trialDaysRemaining > 0 }
    /// Darf die App genutzt werden (Diktieren)? Lizenz oder laufende Testphase.
    var isActive: Bool { isLicensed || isTrialActive }

    /// Aktualisiert den Monotonie-Anker auf „jetzt". Bei länger laufender App
    /// regelmäßig aufrufen (z. B. nach jedem Diktat, beim Beenden), sonst hinkt
    /// der Anker hinterher und der Uhr-Zurückstell-Schutz greift schlechter.
    func touch() {
        let now = Date()
        guard now > lastSeen else { return }
        lastSeen = now
        Keychain.set(String(now.timeIntervalSinceReferenceDate), for: Self.kcLastSeen)
    }

    /// Schlüssel für den (nutzereigenen) Backup-Export.
    var exportKey: String? { Keychain.get(Self.kcLicense) }

    // MARK: - Lizenz

    @discardableResult
    func activate(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let licensee = verify(trimmed) else { return false }
        if !Keychain.set(trimmed, for: Self.kcLicense) {
            // Schlüssel ist gültig → Session freischalten, aber Persistenz scheiterte
            // (gesperrte Keychain o. Ä.): nach Neustart ggf. erneut nötig.
            NSLog("shout: Lizenz aktiviert, aber Keychain-Persistenz fehlgeschlagen — nach Neustart evtl. erneut aktivieren.")
        }
        UserDefaults.standard.removeObject(forKey: storageKey)
        isLicensed = true
        licensedTo = licensee
        return true
    }

    func deactivate() {
        Keychain.delete(Self.kcLicense)
        UserDefaults.standard.removeObject(forKey: storageKey)
        isLicensed = false
        licensedTo = ""
    }

    private static func writeTrialFile(_ start: Date, to url: URL) {
        if let data = try? JSONEncoder().encode(["start": start]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Signiertes Payload-Format v1: JSON `{"v":1,"email":"…"}`. Zusätzliche Felder
    /// (Ablauf, Gerätebindung) lassen sich später ergänzen, ohne die Signatur alter
    /// Schlüssel zu brechen — die Signatur deckt die übertragenen Bytes ab, das
    /// Format ist ihr egal.
    private struct LicensePayload: Decodable {
        let v: Int?
        let email: String?
    }

    private func verify(_ key: String) -> String? {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let payload = Data(base64Encoded: parts[0]),
              let signature = Data(base64Encoded: parts[1]),
              let pubData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData),
              publicKey.isValidSignature(signature, for: payload),
              let text = String(data: payload, encoding: .utf8)
        else { return nil }

        // v1: JSON mit E-Mail. Ältere Schlüssel tragen die E-Mail als rohen Text —
        // beide werden akzeptiert (abwärtskompatibel).
        if let decoded = try? JSONDecoder().decode(LicensePayload.self, from: payload),
           let email = decoded.email?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return email
        }
        let legacy = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return legacy.isEmpty ? nil : legacy
    }
}
