import SwiftUI
import AppKit

/// Die Hinweise einer geöffneten Notiz — Konflikt, fehlende Datei, iCloud,
/// gescheitertes Sichern mit Ausweg. Auf der Seite und im Panel gleich.
struct NoteNoticesView: View {
    @ObservedObject var session: NoteEditorSession
    /// Schließt die Sitzung, ohne zu sichern (nach Rückfrage).
    let onDiscard: () -> Void

    @State private var confirmDiscard = false

    var body: some View {
        VStack(spacing: 0) { notices }
            .alert(Loc.t("Ungesicherten Text verwerfen?"), isPresented: $confirmDiscard) {
                Button(Loc.t("Verwerfen"), role: .destructive, action: onDiscard)
                Button(Loc.t("Abbrechen"), role: .cancel) {}
            } message: {
                Text(Loc.t("Der Text dieser Notiz ist nirgends gesichert. Kopiere ihn vorher, wenn du ihn behalten willst."))
            }
    }
}

private extension NoteNoticesView {
    @ViewBuilder var notices: some View {
        if session.saveFailed {
            saveFailedNotice
        }
        if let name = session.conflictNotice {
            notice(Loc.f("Diese Notiz wurde auch anderswo geändert. Deine Fassung liegt als „%@“ daneben.",
                         (name as NSString).deletingPathExtension),
                   button: Loc.t("OK"), action: session.dismissNotice)
        }
        if session.status == .missing {
            // Mit ungesichertem Text ist die Seite gesperrt — dann auch hier der
            // Ausweg. Steht schon der Hinweis „Konnte nicht gesichert …“, hat der
            // ihn bereits; die Knöpfe erscheinen nicht doppelt.
            if session.hasUnsavedText, !session.saveFailed {
                escapeNotice(Loc.t("Diese Notiz ist nicht mehr im Ordner."),
                             retry: Loc.t("Wieder sichern"), action: session.restoreMissing)
            } else {
                notice(Loc.t("Diese Notiz ist nicht mehr im Ordner."),
                       button: Loc.t("Wieder sichern"), action: session.restoreMissing)
            }
        }
        if session.status == .placeholder {
            notice(Loc.t("Wird aus iCloud geladen …"), button: nil, action: {})
        }
    }

    /// Bleibt stehen, solange das Sichern scheitert. Die Seite ist dann gesperrt
    /// (kein Wechsel, kein Löschen, kein Ordnerwechsel); hier geht es weiter:
    /// noch einmal versuchen, den Text mitnehmen oder ihn bewusst verwerfen.
    var saveFailedNotice: some View {
        escapeNotice(Loc.t("Konnte nicht gesichert werden. Wechseln, Löschen und Ordnerwechsel sind gesperrt, bis gesichert ist."),
                     retry: Loc.t("Erneut sichern"), action: session.flush)
    }

    /// Hinweis mit Ausweg: erneut versuchen, den Text mitnehmen oder ihn nach
    /// Rückfrage verwerfen. Die Knöpfe stehen in einer zweiten Zeile.
    func escapeNotice(_ text: String, retry: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.shoutLive).font(.system(size: 11))
                Text(text).font(.system(size: 12)).foregroundStyle(Color(white: 0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(retry, action: action)
                    .buttonStyle(ConsoleButtonStyle())
                Button(Loc.t("Text kopieren")) {
                    let ablage = NSPasteboard.general
                    ablage.clearContents()
                    ablage.setString(session.note.body, forType: .string)
                }
                .buttonStyle(ConsoleButtonStyle())
                Button(Loc.t("Verwerfen …")) { confirmDiscard = true }
                    .buttonStyle(ConsoleButtonStyle())
                Spacer(minLength: 0)
            }
            .padding(.leading, 21)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.shoutLive.opacity(0.10))
    }

    func notice(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.shoutLive).font(.system(size: 11))
            Text(text).font(.system(size: 12)).foregroundStyle(Color(white: 0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let button { Button(button, action: action).buttonStyle(ConsoleButtonStyle()) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.shoutLive.opacity(0.10))
    }
}
