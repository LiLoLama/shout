import SwiftUI

/// Die Stände einer Notiz: links Zeit und erste Zeile, rechts die Vorschau.
struct NoteVersionsSheet: View {
    let title: String
    let versions: [NoteVersions.Version]
    /// `true`, wenn wiederhergestellt — dann schließt das Blatt.
    let onRestore: (NoteVersions.Version) -> Bool
    let onClose: () -> Void

    @State private var auswahl: NoteVersions.Version.ID?
    @State private var gescheitert = false

    private var gewaehlt: NoteVersions.Version? { versions.first { $0.id == auswahl } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Loc.f("Versionen von „%@“", title)).font(.system(size: 15, weight: .semibold))
            if versions.isEmpty {
                Text(Loc.t("Noch keine Versionen"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    List(versions, selection: $auswahl) { stand in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stand.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12, weight: .medium))
                            Text(stand.firstLine).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .tag(stand.id)
                    }
                    .frame(width: 230)
                    ScrollView {
                        Text(gewaehlt?.text() ?? "")
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            }
            if gescheitert {
                Text(Loc.t("Konnte nicht wiederhergestellt werden.")).font(.system(size: 12)).foregroundStyle(Color.shoutLive)
            }
            HStack {
                Spacer()
                Button(Loc.t("Schließen"), action: onClose).keyboardShortcut(.cancelAction)
                Button(Loc.t("Wiederherstellen")) {
                    if let stand = gewaehlt, onRestore(stand) { onClose() } else { gescheitert = true }
                }
                .disabled(gewaehlt == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 660, height: 460)
        .onAppear { auswahl = versions.first?.id }
    }
}
