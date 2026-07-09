import SwiftUI

/// Diktat-Verlauf: kopieren, teilen, löschen.
struct MobileHistoryView: View {
    @ObservedObject var history: DictationHistory

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    ContentUnavailableView("Noch keine Diktate",
                                           systemImage: "clock.arrow.circlepath",
                                           description: Text("Deine Diktate erscheinen hier."))
                } else {
                    List {
                        ForEach(history.entries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.text).font(.body).lineLimit(4)
                                Text(entry.date, style: .relative)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { history.delete(entry) } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    UIPasteboard.general.string = entry.text
                                } label: {
                                    Label("Kopieren", systemImage: "doc.on.doc")
                                }
                                .tint(Color.shoutLive)
                            }
                            .contextMenu {
                                Button { UIPasteboard.general.string = entry.text } label: {
                                    Label("Kopieren", systemImage: "doc.on.doc")
                                }
                                ShareLink(item: entry.text) { Label("Teilen", systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { history.delete(entry) } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Verlauf")
            .toolbar {
                if !history.entries.isEmpty {
                    Button("Alle löschen", role: .destructive) { history.clear() }
                }
            }
        }
    }
}
