import SwiftUI

/// Diktat-Verlauf: kopieren, teilen, löschen.
struct MobileHistoryView: View {
    @ObservedObject var history: DictationHistory

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    // Loc.t liefert einen String — der Titel-Initializer erwartet einen
                    // LocalizedStringKey. Darum der label:-Initializer mit eigenem Label.
                    ContentUnavailableView {
                        Label(Loc.t("Noch keine Diktate"), systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text(Loc.t("Deine Diktate erscheinen hier."))
                    }
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
                                    Label(Loc.t("Löschen"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    UIPasteboard.general.string = entry.text
                                } label: {
                                    Label(Loc.t("Kopieren"), systemImage: "doc.on.doc")
                                }
                                .tint(Color.shoutLive)
                            }
                            .contextMenu {
                                Button { UIPasteboard.general.string = entry.text } label: {
                                    Label(Loc.t("Kopieren"), systemImage: "doc.on.doc")
                                }
                                ShareLink(item: entry.text) { Label(Loc.t("Teilen"), systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { history.delete(entry) } label: {
                                    Label(Loc.t("Löschen"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(Loc.t("Verlauf"))
            .toolbar {
                if !history.entries.isEmpty {
                    Button(Loc.t("Alle löschen"), role: .destructive) { history.clear() }
                }
            }
        }
    }
}
