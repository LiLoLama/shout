import SwiftUI
import AppKit

/// Verlauf der Diktate — nach Tagen gruppiert, mit Kopieren/Löschen.
struct HistoryView: View {
    @ObservedObject var history: DictationHistory
    let onInsert: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Verlauf").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))
                    Spacer()
                    if !history.entries.isEmpty {
                        Button("Alle löschen") { history.clear() }.buttonStyle(ConsoleButtonStyle())
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
            Text(entry.text)
                .font(.system(size: 13.5)).foregroundStyle(Color(white: 0.9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button { onInsert(entry.text) } label: { Image(systemName: "arrow.down.doc") }
                    .help("Am Cursor einfügen (in der zuletzt aktiven App)")
                Button { copy(entry.text) } label: { Image(systemName: "doc.on.doc") }
                    .help("In die Zwischenablage kopieren")
                Button { history.delete(entry) } label: { Image(systemName: "trash") }
                    .help("Löschen")
            }
            .buttonStyle(.borderless).foregroundStyle(Color(white: 0.5)).font(.system(size: 12))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.165)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .light)).foregroundStyle(Color(white: 0.4))
            Text("Noch keine Diktate").font(.system(size: 15, weight: .medium)).foregroundStyle(Color(white: 0.75))
            Text("Was du diktierst, erscheint hier — zum Nachlesen und erneut Kopieren.")
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

    private static func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Heute" }
        if cal.isDateInYesterday(day) { return "Gestern" }
        return dateFmt.string(from: day)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        f.locale = Locale(identifier: "de_DE"); return f
    }()
}
