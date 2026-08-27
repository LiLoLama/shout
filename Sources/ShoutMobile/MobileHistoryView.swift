import SwiftUI

/// Diktat-Verlauf: kopieren, teilen, löschen.
struct MobileHistoryView: View {
    @ObservedObject var history: DictationHistory
    let onStartDictation: () -> Void

    @State private var confirmClear = false
    @State private var undoSnapshot: [DictationHistory.Entry]?
    @State private var undoMessage: String?
    @State private var undoToken = UUID()

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
                    } actions: {
                        Button(Loc.t("Erstes Diktat aufnehmen"), action: onStartDictation)
                            .buttonStyle(.borderedProminent)
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
                                Button(role: .destructive) { deleteWithUndo(entry) } label: {
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
                                Button(role: .destructive) { deleteWithUndo(entry) } label: {
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
                    Button(Loc.t("Alle löschen"), role: .destructive) { confirmClear = true }
                }
            }
            .confirmationDialog(Loc.t("Alle Diktate löschen?"),
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button(Loc.f("%d Diktate löschen", history.entries.count), role: .destructive) {
                    let snapshot = history.entries
                    history.clear()
                    offerUndo(snapshot, message: Loc.t("Alle Diktate gelöscht"))
                }
                Button(Loc.t("Abbrechen"), role: .cancel) {}
            } message: {
                Text(Loc.t("Du kannst das Löschen direkt danach rückgängig machen."))
            }
            .safeAreaInset(edge: .bottom) {
                if let undoMessage, let undoSnapshot {
                    HStack(spacing: 12) {
                        Text(undoMessage).font(.subheadline)
                        Spacer()
                        Button(Loc.t("Rückgängig")) {
                            history.replaceEntries(undoSnapshot)
                            clearUndo()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.bar)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func deleteWithUndo(_ entry: DictationHistory.Entry) {
        let snapshot = history.entries
        history.delete(entry)
        offerUndo(snapshot, message: Loc.t("Diktat gelöscht"))
    }

    private func offerUndo(_ snapshot: [DictationHistory.Entry], message: String) {
        undoSnapshot = snapshot
        undoMessage = message
        let token = UUID()
        undoToken = token
        Task {
            try? await Task.sleep(for: .seconds(6))
            guard undoToken == token else { return }
            clearUndo()
        }
    }

    private func clearUndo() {
        undoSnapshot = nil
        undoMessage = nil
        undoToken = UUID()
    }
}
