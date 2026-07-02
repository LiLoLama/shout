import SwiftUI

/// Hält die ausgewählte Dashboard-Seite (von Menüpunkten steuerbar).
@MainActor
final class DashboardModel: ObservableObject {
    enum Tab: Hashable { case aufnahme, woerterbuch, verlauf, statistik, sync, konto }
    @Published var tab: Tab = .aufnahme
}

/// Hauptfenster im Mischpult-Look: eigene Graphit-Seitenleiste mit Wortmarke,
/// rechts die Einstellungs-Panels.
struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var dictionary: PersonalDictionary
    let onRecordHotkey: () -> Void

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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kopfbereich: Wortmarke + Status
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Text("shout").font(.system(size: 23, weight: .bold))
                    Text(".").font(.system(size: 23, weight: .bold)).foregroundStyle(Color.shoutLive)
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.shoutLive).frame(width: 6, height: 6)
                    Text("Bereit · \(statusText)").font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                }
            }
            .padding(.horizontal, 18).padding(.top, 42).padding(.bottom, 20)

            navRow(.aufnahme, "Aufnahme & Text", "mic.fill")
            navRow(.woerterbuch, "Wörterbuch", "text.book.closed.fill")

            Text("BALD VERFÜGBAR")
                .font(.system(size: 10, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Color(white: 0.38))
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 6)

            navRow(.verlauf, "Verlauf", "clock.arrow.circlepath", soon: true)
            navRow(.statistik, "Statistiken", "chart.bar.xaxis", soon: true)
            navRow(.sync, "Sync & Geräte", "arrow.triangle.2.circlepath", soon: true)
            navRow(.konto, "Konto & Lizenz", "person.crop.circle", soon: true)

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
            Text(title).font(.title2).fontWeight(.semibold).foregroundStyle(Color(white: 0.92))
            Text(desc)
                .font(.callout).foregroundStyle(Color(white: 0.6))
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
