import SwiftUI

@main
struct ShoutMobileApp: App {
    @StateObject private var engine = MobileEngine()
    @AppStorage("didCompleteOnboardingIOS") private var didOnboard = false
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                HomeView(engine: engine)
                    .tabItem { Label("Diktieren", systemImage: "mic.fill") }
                    .tag(0)
                MobileHistoryView(history: engine.history)
                    .tabItem { Label("Verlauf", systemImage: "clock.arrow.circlepath") }
                    .tag(1)
                MobileDictionaryView(dictionary: engine.dictionary)
                    .tabItem { Label("Wörterbuch", systemImage: "text.book.closed.fill") }
                    .tag(2)
                MobileSettingsView(engine: engine)
                    .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
                    .tag(3)
            }
            .tint(Color.shoutLive)
            .sheet(isPresented: .init(get: { !didOnboard }, set: { didOnboard = !$0 })) {
                MobileOnboardingView(engine: engine) { didOnboard = true }
                    .interactiveDismissDisabled()
            }
            // Aus der shout-Tastatur geöffnet: auf den Diktier-Tab und aufnehmen.
            .onOpenURL { url in
                guard url.scheme == "shout", url.host == "dictate" else { return }
                selectedTab = 0
                engine.requestDictation(fromKeyboard: true)
            }
        }
    }
}
