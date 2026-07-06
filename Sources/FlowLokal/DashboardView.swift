import SwiftUI

/// Hält die ausgewählte Dashboard-Seite (von Menüpunkten steuerbar).
@MainActor
final class DashboardModel: ObservableObject {
    enum Tab: Hashable { case aufnahme, woerterbuch, verlauf, statistik, modelle, sync, konto }
    @Published var tab: Tab = .aufnahme

    // Modell-Zustand zentral (überlebt Tab-Wechsel, damit Spinner/Auswahl
    // konsistent bleiben und Modellwechsel sich nicht überlappen können).
    @Published var activeASR = UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR
    @Published var activeFormat = UserDefaults.standard.string(forKey: "formatModel") ?? ModelCatalog.defaultFormatting
    @Published var asrLoadingID: String?      // gerade ladende ASR-Modell-ID
    @Published var formatLoadingID: String?   // gerade ladende Format-Modell-ID
    @Published var asrProgress: Double?       // Download-/Ladefortschritt 0…1
    @Published var formatProgress: Double?
    @Published var modelNote: String?         // z. B. Hinweis „Wechsel während Aufnahme nicht möglich"
    @Published var transcriberReady = false   // Transkriptions-Modell geladen (fürs Onboarding)
    @Published var asrLoadFailed = false      // Laden des ASR-Modells fehlgeschlagen (Onboarding zeigt Wiederholen)

    var isSwitchingModel: Bool { asrLoadingID != nil || formatLoadingID != nil }
}

/// Hauptfenster im Mischpult-Look: eigene Graphit-Seitenleiste mit Wortmarke,
/// rechts die Einstellungs-Panels.
struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var dictionary: PersonalDictionary
    @ObservedObject var history: DictationHistory
    @ObservedObject var stats: StatsStore
    @ObservedObject var license: LicenseStore
    let onRecordHotkey: () -> Void
    let generateProfile: (String) async -> String?
    let onExport: () -> String
    let onImport: () -> String
    let onInsertHistory: (String) -> Void
    let onSelectASR: (String) async -> Void
    let onSelectFormat: (String) async -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 224)
                .background(Color.shoutSidebar)
            Rectangle().fill(Color.black.opacity(0.45)).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.shoutWindow)
        }
        .frame(minWidth: 780, minHeight: 580)
        .tint(Color.shoutLive)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    // MARK: - Seitenleiste

    private var statusText: String {
        let verb = settings.mode == .hold ? "halten" : "drücken"
        return "\(settings.hotkeyDescription) \(verb)"
    }

    private var planActive: Bool { license.isLicensed || license.isTrialActive }
    private var planBadge: String {
        if license.isLicensed { return "Aktiv" }
        if license.isTrialActive { return "Test · \(license.trialDaysRemaining)d" }
        return "Abgelaufen"
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kopfbereich: Wortmarke + Status
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Text("shout").font(.system(size: 23, weight: .bold))
                        Text(".").font(.system(size: 23, weight: .bold)).foregroundStyle(Color.shoutLive)
                    }
                    Text(planBadge)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(planActive ? Color.shoutLive.opacity(0.20) : Color.white.opacity(0.10)))
                        .foregroundStyle(planActive ? Color.shoutLive : Color(white: 0.6))
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.shoutLive).frame(width: 6, height: 6)
                    Text("Bereit · \(statusText)").font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                }
            }
            .padding(.horizontal, 18).padding(.top, 42).padding(.bottom, 20)

            navRow(.aufnahme, "Aufnahme & Text", "mic.fill")
            navRow(.woerterbuch, "Wörterbuch", "text.book.closed.fill")
            navRow(.verlauf, "Verlauf", "clock.arrow.circlepath")
            navRow(.statistik, "Statistiken", "chart.bar.xaxis")
            navRow(.modelle, "Modelle", "cpu")
            navRow(.sync, "Sync & Geräte", "arrow.triangle.2.circlepath")
            navRow(.konto, "Konto & Lizenz", "person.crop.circle")

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func navRow(_ tab: DashboardModel.Tab, _ title: String, _ icon: String, soon: Bool = false) -> some View {
        let active = model.tab == tab
        return Button { model.tab = tab } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 20)
                Text(title).font(.system(size: 13, weight: active ? .semibold : .regular))
                Spacer(minLength: 4)
                if soon {
                    Text("Bald").font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .foregroundStyle(Color(white: 0.5))
                }
            }
            .foregroundStyle(active ? Color.white : Color(white: 0.64))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.shoutLive.opacity(0.18) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        switch model.tab {
        case .aufnahme:
            SettingsView(settings: settings, onRecordHotkey: onRecordHotkey)
        case .woerterbuch:
            DictionaryView(dictionary: dictionary)
        case .verlauf:
            HistoryView(history: history, onInsert: onInsertHistory)
        case .statistik:
            StatisticsView(stats: stats, history: history, dictionary: dictionary, generateProfile: generateProfile)
        case .modelle:
            ModelsView(model: model, onSelectASR: onSelectASR, onSelectFormat: onSelectFormat)
        case .sync:
            SyncView(onExport: onExport, onImport: onImport)
        case .konto:
            LicenseView(license: license)
        }
    }
}
