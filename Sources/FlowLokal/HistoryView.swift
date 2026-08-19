import SwiftUI
import AppKit

/// Verlauf der Diktate — nach Tagen gruppiert, mit Kopieren/Löschen.
struct HistoryView: View {
    @ObservedObject var history: DictationHistory
    let onInsert: (String) -> Void

    /// Einträge, deren Roh-Transkript gerade aufgeklappt ist.
    @State private var expandedRaw: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(Loc.t("Verlauf")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))
                    Spacer()
                    if !history.entries.isEmpty {
                        Button(Loc.t("Alle löschen")) { history.clear() }.buttonStyle(ConsoleButtonStyle())
                    }
                }

                if history.entries.isEmpty {
                    emptyState
                } else {
                    ForEach(groups, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.label.uppercased())
                                .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                                .foregroundStyle(Color(white: 0.45)).padding(.leading, 4)
                            ForEach(group.items) { entry in row(entry) }
                        }
                    }
                }
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
    }

    private func row(_ entry: DictationHistory.Entry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(Self.time.string(from: entry.date))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(white: 0.5))
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.text)
                    .font(.system(size: 13.5)).foregroundStyle(Color(white: 0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let raw = entry.raw { rawSection(raw, id: entry.id) }
            }
            HStack(spacing: 8) {
                Button { onInsert(entry.text) } label: { Image(systemName: "arrow.down.doc") }
                    .help(Loc.t("Am Cursor einfügen (in der zuletzt aktiven App)"))
                Button { copy(entry.text) } label: { Image(systemName: "doc.on.doc") }
                    .help(Loc.t("In die Zwischenablage kopieren"))
                Button { history.delete(entry) } label: { Image(systemName: "trash") }
                    .help(Loc.t("Löschen"))
            }
            .buttonStyle(.borderless).foregroundStyle(Color(white: 0.5)).font(.system(size: 12))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.165)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
    }

    /// Roh-Transkript der Spracherkennung, auf-/zuklappbar. Sichtbar nur, wenn es
    /// sich vom Ergebnis unterscheidet (sonst speichert der Verlauf gar kein `raw`).
    private func rawSection(_ raw: String, id: UUID) -> some View {
        let expanded = expandedRaw.contains(id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    if expanded { expandedRaw.remove(id) } else { expandedRaw.insert(id) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(expanded ? Loc.t("Original ausblenden") : Loc.t("Original anzeigen"))
                            .font(.system(size: 11.5))
                    }
                }
                .buttonStyle(.plain).foregroundStyle(Color(white: 0.55))
                .help(Loc.t("Rohtext der Spracherkennung — vor Befehlen, Aufbereitung und Korrekturen."))
                if expanded {
                    Button { copy(raw) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).foregroundStyle(Color(white: 0.5))
                        .font(.system(size: 11))
                        .help(Loc.t("Original in die Zwischenablage kopieren"))
                }
            }
            if expanded {
                Text(raw)
                    .font(.system(size: 12.5)).foregroundStyle(Color(white: 0.62))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.12)))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .light)).foregroundStyle(Color(white: 0.4))
            Text(Loc.t("Noch keine Diktate")).font(.system(size: 15, weight: .medium)).foregroundStyle(Color(white: 0.75))
            Text(Loc.t("Was du diktierst, erscheint hier — zum Nachlesen und erneut Kopieren."))
                .font(.system(size: 12)).foregroundStyle(Color(white: 0.55))
                .multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    // MARK: - Gruppierung nach Tag

    private struct Group { let label: String; let items: [DictationHistory.Entry] }

    private var groups: [Group] {
        let cal = Calendar.current
        var order: [Date] = []
        var map: [Date: [DictationHistory.Entry]] = [:]
        for entry in history.entries {
            let day = cal.startOfDay(for: entry.date)
            if map[day] == nil { order.append(day) }
            map[day, default: []].append(entry)
        }
        return order.map { Group(label: Self.dayLabel($0), items: map[$0] ?? []) }
    }

    @MainActor
    private static func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return Loc.t("Heute") }
        if cal.isDateInYesterday(day) { return Loc.t("Gestern") }
        return dateFmt.string(from: day)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    /// Berechnet, damit ein Sprachwechsel sofort greift (statt beim ersten
    /// Zugriff einzufrieren wie ein `static let`).
    @MainActor
    private static var dateFmt: DateFormatter {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        f.locale = Locale(identifier: Loc.isGerman ? "de_DE" : "en_US"); return f
    }
}
