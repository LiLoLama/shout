import Foundation

/// Was das Fenster „Neu in shout.“ zeigt.
enum WhatsNewDecider {
    /// Die letzte Version vor diesem Fenster. Wer von dort (oder früher)
    /// aktualisiert, hat sich noch nichts gemerkt — für ihn gilt diese.
    static let baseline = AppVersion("1.12.0")!

    static func entriesToShow(all: [ChangelogEntry], lastSeen: AppVersion?,
                              current: AppVersion, onboardingDone: Bool) -> [ChangelogEntry] {
        // Neuinstallation: Das Onboarding stellt alles vor.
        guard onboardingDone else { return [] }
        let ab = lastSeen ?? baseline
        return all.filter { $0.highlight && $0.version > ab && $0.version <= current }
            .sorted { $0.version > $1.version }
    }
}

/// Die zuletzt gesehene Version, in den UserDefaults.
struct WhatsNewState {
    static let key = "whatsNew.lastSeenVersion"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var lastSeen: AppVersion? { defaults.string(forKey: Self.key).flatMap(AppVersion.init) }

    func markSeen(_ version: AppVersion) { defaults.set(version.description, forKey: Self.key) }
}

extension AppVersion {
    /// Die Version dieser App (`CFBundleShortVersionString`).
    static var running: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }
}
