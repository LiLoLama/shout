import AppIntents

/// „Diktieren"-Kurzbefehl: startbar über den Action Button (iPhone 15 Pro+),
/// Kurzbefehle, „Beim Antippen der Rückseite" oder Siri. Öffnet die App und
/// beginnt sofort mit der Aufnahme — der iOS-Ersatz für den globalen Hotkey.
struct DictateIntent: AppIntent {
    static let title: LocalizedStringResource = "Diktieren"
    static let description = IntentDescription("Öffnet shout. und startet sofort eine Aufnahme.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Kleiner Aufschub, damit die App/Engine sicher im Vordergrund ist.
        try? await Task.sleep(nanoseconds: 300_000_000)
        NotificationCenter.default.post(name: .shoutStartDictation, object: nil)
        return .result()
    }
}

struct ShoutShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DictateIntent(),
            phrases: ["Diktieren mit \(.applicationName)", "Start dictation with \(.applicationName)"],
            shortTitle: "Diktieren",
            systemImageName: "mic.fill"
        )
    }
}
