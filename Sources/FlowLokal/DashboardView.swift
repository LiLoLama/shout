import SwiftUI

/// Hält die ausgewählte Dashboard-Seite (von Menüpunkten steuerbar).
@MainActor
final class DashboardModel: ObservableObject {
    enum Tab: Hashable { case aufnahme, woerterbuch, verlauf, statistik, sync, konto }
    @Published var tab: Tab = .aufnahme
}

/// Das Hauptfenster von shout. — ein echtes, öffenbares App-Fenster mit den
/// wichtigsten Einstellungen und Platzhaltern für künftige (Pro-)Funktionen.
struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var dictionary: PersonalDictionary
    let onRecordHotkey: () -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: $model.tab) {
                Section {
                    row(.aufnahme, "Aufnahme & Text", "mic.fill")
                    row(.woerterbuch, "Wörterbuch", "text.book.closed.fill")
                }
                Section("Bald verfügbar") {
                    row(.verlauf, "Verlauf", "clock.arrow.circlepath", soon: true)
                    row(.statistik, "Statistiken", "chart.bar.xaxis", soon: true)
                    row(.sync, "Sync & Geräte", "arrow.triangle.2.circlepath", soon: true)
                    row(.konto, "Konto & Lizenz", "person.crop.circle", soon: true)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 208, ideal: 216, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.shoutPanel)
        }
        .frame(minWidth: 720, minHeight: 540)
        .tint(Color.shoutLive)
        .preferredColorScheme(.dark)
    }

    private func row(_ tab: DashboardModel.Tab, _ title: String, _ icon: String, soon: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: icon)
            if soon {
                Spacer()
                Text("Bald")
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.22), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .tag(tab)
    }

    @ViewBuilder private var detail: some View {
        switch model.tab {
        case .aufnahme:
            ScrollView { SettingsView(settings: settings, onRecordHotkey: onRecordHotkey).padding(.vertical, 8) }
        case .woerterbuch:
            DictionaryView(dictionary: dictionary)
        case .verlauf:
            ComingSoon(icon: "clock.arrow.circlepath", title: "Verlauf",
                       desc: "Deine letzten Diktate an einem Ort — durchsuchen, erneut einfügen und exportieren.")
        case .statistik:
            ComingSoon(icon: "chart.bar.xaxis", title: "Statistiken",
                       desc: "Wörter pro Tag, gesparte Tipp-Zeit und deine häufigsten Korrekturen.")
        case .sync:
            ComingSoon(icon: "arrow.triangle.2.circlepath", title: "Sync & Geräte",
                       desc: "Wörterbuch und Einstellungen sicher zwischen deinen Macs abgleichen.")
        case .konto:
            ComingSoon(icon: "person.crop.circle", title: "Konto & Lizenz",
                       desc: "Lizenz verwalten, shout. Pro freischalten und Team-Plätze vergeben.")
        }
    }
}

/// Platzhalter-Seite für noch nicht gebaute Funktionen.
private struct ComingSoon: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Color.shoutLive.opacity(0.9))
            Text(title).font(.title2).fontWeight(.semibold)
            Text(desc)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            Text("Bald verfügbar · shout. Pro")
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.shoutLive.opacity(0.16), in: Capsule())
                .foregroundStyle(Color.shoutLive)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
