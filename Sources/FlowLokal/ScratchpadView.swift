import SwiftUI
import AppKit

/// Inhalt des Panels: Tabs oben, optional die Liste links, der Editor, unten
/// Mikrofon und Anheften. Die Tastenkürzel wirken, sobald das Panel den Fokus hat.
struct ScratchpadView: View {
    @ObservedObject var model: ScratchpadModel
    @ObservedObject var store: NoteStore
    @ObservedObject var mic: ScratchpadMicState
    let onMic: () -> Void

    @FocusState private var searchFocused: Bool
    /// Fokus-Anstoß je Tab: Wird ein Tab vorne, bekommt sein Editor den Fokus —
    /// sonst tippte man unsichtbar in den vorigen.
    @State private var fokus: [UUID: Int] = [:]

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            HStack(spacing: 0) {
                if model.showsList {
                    list.frame(width: 200)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                }
                editors.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            footer
        }
        .background(Color.shoutWindow)
        .background(shortcuts)
        .preferredColorScheme(.dark)
        .onChange(of: model.active?.id) { _, id in
            if let id { fokus[id, default: 0] += 1 }
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                TabChip(session: tab, active: index == model.activeIndex,
                        onSelect: { model.select(index) }, onClose: { model.close(index) })
            }
            Button { model.newTab() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless).foregroundStyle(Color(white: 0.6))
                .help(Loc.t("Neuer Tab"))
            Spacer(minLength: 0)
            Button { model.showsList.toggle() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.borderless).foregroundStyle(Color(white: 0.6))
                .help(Loc.t("Liste ein/aus"))
        }
        // Platz für die Fensterknöpfe (Titelleiste liegt über dem Inhalt).
        .padding(.leading, 78).padding(.trailing, 10).padding(.vertical, 8)
    }

    // MARK: Liste

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Color(white: 0.45))
                TextField(Loc.t("Notizen durchsuchen"), text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.10)))
            .padding(8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.results) { ergebnis in row(ergebnis.note) }
                }
                .padding(.horizontal, 6).padding(.bottom, 6)
            }
        }
    }

    private func row(_ note: Note) -> some View {
        let vorne = model.active?.id == note.id
        return Button {
            // ⌘-Klick: in einem neuen Tab.
            model.open(note.id, inNewTab: NSEvent.modifierFlags.contains(.command))
        } label: {
            HStack(spacing: 5) {
                if note.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Color.shoutLive)
                }
                Text(note.title).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(vorne ? Color.white : Color(white: 0.7))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(vorne ? Color.shoutLive.opacity(0.14) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Editoren

    /// Jeder Tab behält seinen Editor (und damit sein Rückgängig); sichtbar und
    /// klickbar ist nur der vordere.
    @ViewBuilder private var editors: some View {
        if model.tabs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "note.text").font(.system(size: 28, weight: .light)).foregroundStyle(Color(white: 0.4))
                Text(Loc.t("Noch keine Notiz offen. ⌘N legt eine neue an."))
                    .font(.system(size: 12)).foregroundStyle(Color(white: 0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                ForEach(model.tabs, id: \.id) { tab in
                    let vorne = tab === model.active
                    VStack(spacing: 0) {
                        NoteNoticesView(session: tab, onDiscard: { model.discard(tab) })
                        NoteEditorView(session: tab, focusRequest: fokus[tab.id] ?? 0)
                            .id(ObjectIdentifier(tab))
                    }
                    .opacity(vorne ? 1 : 0)
                    .allowsHitTesting(vorne)
                    .accessibilityHidden(!vorne)
                }
            }
        }
    }

    // MARK: Fußleiste

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: onMic) {
                Image(systemName: mic.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 13))
                    .foregroundStyle(mic.isRecording ? Color.shoutLive : Color(white: 0.7))
                    .symbolEffect(.pulse, isActive: mic.isRecording)
            }
            .buttonStyle(.borderless)
            .help(mic.isRecording ? Loc.t("Diktat beenden") : Loc.t("In diese Notiz diktieren"))
            if let vorne = model.active { PinButton(session: vorne) }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    // MARK: Tastenkürzel

    /// Unsichtbare Knöpfe tragen die Kürzel; sie wirken, sobald das Panel Key-Fenster ist.
    private var shortcuts: some View {
        ZStack {
            Button("") { model.newTab() }.keyboardShortcut("n", modifiers: .command)
            Button("") { if let i = model.activeIndex { model.close(i) } }.keyboardShortcut("w", modifiers: .command)
            ForEach(0..<ScratchpadModel.maxTabs, id: \.self) { i in
                Button("") { model.select(i) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Button("") { model.selectNext(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            Button("") { model.selectNext(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("") { model.showsList.toggle() }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("") {
                model.showsList = true
                searchFocused = true
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// Ein Tab-Reiter. Eigene View, damit er seine Sitzung beobachtet — der Titel
/// ändert sich beim ersten Sichern, der Punkt zeigt Ungesichertes.
private struct TabChip: View {
    @ObservedObject var session: NoteEditorSession
    let active: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(session.note.isNew ? Loc.t("Neue Notiz") : session.note.title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 120)
            if session.hasUnsavedText {
                Circle().fill(Color.shoutLive).frame(width: 5, height: 5)
            }
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                .buttonStyle(.borderless)
                .help(Loc.t("Tab schließen"))
        }
        .foregroundStyle(active ? Color.white : Color(white: 0.6))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(active ? Color.shoutLive.opacity(0.18) : Color.white.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

/// Anheften der vorderen Notiz — über die Sitzung, damit ungesicherter Text mitkommt.
private struct PinButton: View {
    @ObservedObject var session: NoteEditorSession

    var body: some View {
        Button { session.setPinned(!session.note.pinned) } label: {
            Image(systemName: session.note.pinned ? "pin.fill" : "pin").font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(session.note.pinned ? Color.shoutLive : Color(white: 0.7))
        .help(session.note.pinned ? Loc.t("Lösen") : Loc.t("Anheften"))
    }
}
