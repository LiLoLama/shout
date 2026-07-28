import SwiftUI

@main
struct ShoutMobileApp: App {
    @StateObject private var engine = MobileEngine()

    var body: some Scene {
        WindowGroup {
            RootView(engine: engine)
        }
    }
}

/// Eigene View statt direkt in der Scene, damit der Sprachwechsel greifen kann:
/// `.id(loc.language)` baut den Baum neu auf, weil die Texte schon in den
/// fertigen Views stecken (wie am Mac in DashboardView).
private struct RootView: View {
    @ObservedObject var engine: MobileEngine
    @ObservedObject private var loc = Loc.shared
    @AppStorage("didCompleteOnboardingIOS") private var didOnboard = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(engine: engine)
                .tabItem { Label(Loc.t("Diktieren"), systemImage: "mic.fill") }
                .tag(0)
            MobileHistoryView(history: engine.history)
                .tabItem { Label(Loc.t("Verlauf"), systemImage: "clock.arrow.circlepath") }
                .tag(1)
            MobileDictionaryView(dictionary: engine.dictionary)
                .tabItem { Label(Loc.t("Wörterbuch"), systemImage: "text.book.closed.fill") }
                .tag(2)
            MobileSettingsView(engine: engine)
                .tabItem { Label(Loc.t("Einstellungen"), systemImage: "gearshape.fill") }
                .tag(3)
        }
        .id(loc.language)
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
