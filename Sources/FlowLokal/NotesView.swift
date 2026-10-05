import SwiftUI
import AppKit

/// Seite „Notizen“: oben der Ordner, links die Liste mit Suche, rechts der Editor.
struct NotesView: View {
    @ObservedObject var model: NotesPageModel
    @ObservedObject var store: NoteStore

    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var editorFocus = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !model.rescuedFiles.isEmpty { rescueBanner }
            folderPanel
            if store.folderState == .unreachable {
                banner(Loc.t("Der Ordner ist nicht erreichbar. Änderungen werden zwischengespeichert und landen dort, sobald er wieder da ist."))
            }
            HStack(spacing: 0) {
                list.frame(width: 250)
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.135)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.shoutWindow)
        .overlay(alignment: .bottom) { undoBar }
        .alert(Loc.t("Notiz umbenennen"), isPresented: renameBinding) {
            TextField(Loc.t("Titel"), text: $renameText)
            Button(Loc.t("Umbenennen")) {
                if let id = renaming { model.rename(id, to: renameText) }
                renaming = nil
            }
            Button(Loc.t("Abbrechen"), role: .cancel) { renaming = nil }
        }
        .onAppear { model.refreshRescuedFiles() }
        .onDisappear { model.flush() }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    // MARK: - Kopf und Ordner

    private var header: some View {
        HStack {
            Text(Loc.t("Notizen")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))
            Spacer()
            Button {
                model.createNote()
            } label: {
                Label(Loc.t("Neue Notiz"), systemImage: "square.and.pencil")
            }
            .buttonStyle(ConsoleButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var folderPanel: some View {
        ConsolePanel {
            FieldRow(title: Loc.t("Ordner"),
                     help: Loc.t("Jede Notiz ist eine Markdown-Datei in diesem Ordner. Liegt er in iCloud Drive oder einem Obsidian-Vault, findest du die Notizen auch dort.")) {
                HStack(spacing: 8) {
                    Text((store.folder.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(white: 0.6))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 220, alignment: .trailing)
                        .help(store.folder.path)
                    Button(Loc.t("Im Finder zeigen")) { NSWorkspace.shared.open(store.folder) }
                        .buttonStyle(ConsoleButtonStyle())
                        .disabled(store.folderState == .unreachable
                                  || !FileManager.default.fileExists(atPath: store.folder.path))
                    Button(Loc.t("Wählen …")) {
                        if let url = chooseFolder() { model.changeFolder(to: url) }
                    }
                    .buttonStyle(ConsoleButtonStyle())
                }
            }
        }
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = Loc.t("Wählen")
        panel.directoryURL = store.folder
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Liste

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
                TextField(Loc.t("Notizen durchsuchen"), text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 12.5))
                    .focused($searchFocused)
                    .onSubmit { listFocused = true; model.moveSelection(by: 0) }
                    .onKeyPress(.escape) { model.query = ""; listFocused = true; return .handled }
                    .onKeyPress(.downArrow) { listFocused = true; model.moveSelection(by: 0); return .handled }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.10)))
            .padding(10)

            listBody
        }
    }

    /// Eigene Fokus-Einheit ohne das Suchfeld: Sonst landete jedes „j“ beim
    /// Tippen in der Suche als Pfeil nach unten.
    private var listBody: some View {
        let ergebnisse = model.results
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if ergebnisse.isEmpty {
                        Text(model.query.isEmpty ? Loc.t("Noch keine Notizen") : Loc.t("Keine Treffer"))
                            .font(.system(size: 12)).foregroundStyle(Color(white: 0.5)).padding(.top, 20)
                    }
                    ForEach(ergebnisse) { row($0) }
                }
                .padding(.horizontal, 6).padding(.bottom, 8)
            }
            .onChange(of: model.session?.id) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.downArrow, .upArrow, .return]) { press in
            switch press.key {
            case .downArrow: model.moveSelection(by: 1)
            case .upArrow: model.moveSelection(by: -1)
            default: if model.session != nil { editorFocus += 1 }
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "jkc/f")) { press in
            // ⌘C, ⌘J, ⌘K … gehören dem Menü (⌘C legte sonst eine Notiz an); nur ⌘F sucht.
            if press.modifiers.contains(.command), press.characters != "f" { return .ignored }
            switch press.characters {
            case "j": model.moveSelection(by: 1)
            case "k": model.moveSelection(by: -1)
            case "c": model.createNote()
            case "/": searchFocused = true
            case "f" where press.modifiers.contains(.command): searchFocused = true
            default: return .ignored
            }
            return .handled
        }
    }

    private func row(_ ergebnis: NoteSearch.Result) -> some View {
        let note = ergebnis.note
        let aktiv = model.session?.id == note.id
        return Button {
            model.select(note.id)
            listFocused = true
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if note.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Color.shoutLive)
                    }
                    if note.isPlaceholder {
                        Image(systemName: "icloud.and.arrow.down").font(.system(size: 10)).foregroundStyle(Color(white: 0.5))
                    }
                    Text(note.title).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.92)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.relative(note.modified)).font(.system(size: 10.5)).foregroundStyle(Color(white: 0.45))
                }
                snippetText(ergebnis)
                    .font(.system(size: 11.5)).foregroundStyle(Color(white: 0.55)).lineLimit(2)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(aktiv ? Color.shoutLive.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(note.id)
        .contextMenu { menu(for: note) }
    }

    private func snippetText(_ ergebnis: NoteSearch.Result) -> Text {
        guard let s = ergebnis.snippet else { return Text(NoteSearch.preview(ergebnis.note.body)) }
        return Text(s.before) + Text(s.match).foregroundColor(Color.shoutLive).bold() + Text(s.after)
    }

    @ViewBuilder private func menu(for note: Note) -> some View {
        Button(note.pinned ? Loc.t("Lösen") : Loc.t("Anheften")) { model.togglePin(note.id) }
        Button(Loc.t("Umbenennen …")) { renameText = note.title; renaming = note.id }
        Button(Loc.t("Im Finder zeigen")) {
            NSWorkspace.shared.activateFileViewerSelecting([store.url(for: note)])
        }
        Divider()
        Button(Loc.t("Löschen"), role: .destructive) { model.delete(note.id) }
    }

    // MARK: - Editor

    @ViewBuilder private var editor: some View {
        if let session = model.session {
            NoteEditorPane(session: session, store: store, focusRequest: editorFocus,
                           onRename: { renameText = session.note.title; renaming = session.id },
                           onTogglePin: { model.togglePin(session.id) },
                           onDelete: { model.delete(session.id) },
                           onDiscard: { model.discardSession() })
                // An das Objekt gebunden, nicht an die Notiz-ID: Eine neue Sitzung
                // derselben Notiz bekommt so sicher einen frischen Editor, dessen
                // Coordinator nicht mehr in die alte schreibt.
                .id(ObjectIdentifier(session))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "note.text").font(.system(size: 36, weight: .light)).foregroundStyle(Color(white: 0.4))
                Text(store.notes.isEmpty ? Loc.t("Noch keine Notizen") : Loc.t("Wähle links eine Notiz oder lege eine neue an."))
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Color(white: 0.75))
                if store.notes.isEmpty {
                    Text(Loc.t("Diktiere oder tippe eine neue Notiz — sie landet als Datei in deinem Ordner."))
                        .font(.system(size: 12)).foregroundStyle(Color(white: 0.55))
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Hinweise

    private func banner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(Color.shoutLive)
            Text(text).font(.system(size: 12)).foregroundStyle(Color(white: 0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.shoutLive.opacity(0.10)))
    }

    /// Beim Beenden gerettete Notizen liegen im App-Support, nicht im Ordner.
    /// Ohne diesen Hinweis fände sie niemand.
    private var rescueBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lifepreserver").foregroundStyle(Color.shoutLive)
            Text(Loc.t("Beim letzten Beenden wurden ungesicherte Notizen gerettet."))
                .font(.system(size: 12)).foregroundStyle(Color(white: 0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(Loc.t("Im Finder zeigen")) { NSWorkspace.shared.open(model.rescueDirectory) }
                .buttonStyle(ConsoleButtonStyle())
            Button(Loc.t("In den Notizordner holen")) { model.adoptRescuedNotes() }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(store.folderState == .unreachable)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.shoutLive.opacity(0.10)))
    }

    @ViewBuilder private var undoBar: some View {
        if let geloescht = model.lastDeleted {
            HStack(spacing: 12) {
                Text(Loc.f("„%@“ gelöscht", geloescht.title))
                    .font(.system(size: 12.5)).foregroundStyle(Color(white: 0.9))
                Button(Loc.t("Rückgängig")) { model.undoDelete() }.buttonStyle(ConsoleButtonStyle())
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Color(white: 0.2)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
            .padding(.bottom, 26)
            .task(id: geloescht) {
                try? await Task.sleep(for: .seconds(8))
                // Abgebrochen (Seite verlassen): Der Balken bleibt für die Rückkehr stehen.
                guard !Task.isCancelled else { return }
                if model.lastDeleted == geloescht { model.dismissUndo() }
            }
        }
    }

    private static func relative(_ datum: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: Loc.isGerman ? "de_DE" : "en_US")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: datum, relativeTo: Date())
    }
}

/// Kopfzeile, Hinweise und Editor einer geöffneten Notiz. Eigene View, damit sie
/// die Sitzung beobachtet — der Titel ändert sich beim ersten Sichern.
private struct NoteEditorPane: View {
    @ObservedObject var session: NoteEditorSession
    @ObservedObject var store: NoteStore
    let focusRequest: Int
    let onRename: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    /// Schließt die Sitzung, ohne zu sichern (nach Rückfrage).
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onRename) {
                    HStack(spacing: 6) {
                        Text(session.note.isNew ? Loc.t("Neue Notiz") : session.note.title)
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(white: 0.92))
                            .lineLimit(1)
                        if !session.note.isNew {
                            Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(Color(white: 0.45))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(session.note.isNew)
                .help(Loc.t("Umbenennen …"))
                Spacer()
                Group {
                    Button(action: onTogglePin) { Image(systemName: session.note.pinned ? "pin.fill" : "pin") }
                        .help(session.note.pinned ? Loc.t("Lösen") : Loc.t("Anheften"))
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([store.url(for: session.note)])
                    } label: { Image(systemName: "folder") }
                        .help(Loc.t("Im Finder zeigen"))
                        .disabled(session.note.isNew)
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .help(Loc.t("Löschen"))
                }
                .buttonStyle(.borderless).foregroundStyle(Color(white: 0.55)).font(.system(size: 12))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            NoteNoticesView(session: session, onDiscard: onDiscard)
            NoteEditorView(session: session,
                           autofocus: session.note.isNew && session.note.body.isEmpty,
                           focusRequest: focusRequest)
        }
    }
}
