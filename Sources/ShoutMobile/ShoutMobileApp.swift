import SwiftUI

@main
struct ShoutMobileApp: App {
    @StateObject private var engine = MobileEngine()
    @AppStorage("didCompleteOnboardingIOS") private var didOnboard = false

    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView(engine: engine)
                    .tabItem { Label("Diktieren", systemImage: "mic.fill") }
                MobileHistoryView(history: engine.history)
                    .tabItem { Label("Verlauf", systemImage: "clock.arrow.circlepath") }
                MobileDictionaryView(dictionary: engine.dictionary)
                    .tabItem { Label("Wörterbuch", systemImage: "text.book.closed.fill") }
                MobileSettingsView(engine: engine)
                    .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
            }
            .tint(Color.shoutLive)
            .sheet(isPresented: .init(get: { !didOnboard }, set: { didOnboard = !$0 })) {
                MobileOnboardingView(engine: engine) { didOnboard = true }
                    .interactiveDismissDisabled()
            }
        }
    }
}
