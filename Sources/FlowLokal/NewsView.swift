import SwiftUI

/// Rendert den Markdown eines Update-Log-Eintrags: Absätze, `- `-Listen und
/// Inline-Auszeichnung (fett, kursiv, Code, Links).
struct ChangelogText: View {
    private let blocks: [Block]

    enum Block: Equatable {
        case paragraph(String)
        case list([String])
    }

    init(_ markdown: String) {
        blocks = Self.blocks(of: markdown)
    }

    /// Teilt an Leerzeilen in Absätze; zusammenhängende `- `-Zeilen werden eine Liste.
    static func blocks(of markdown: String) -> [Block] {
        let zeilen = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var ergebnis: [Block] = []
        var absatz: [String] = []
        var liste: [String] = []

        func abschliessen() {
            if !absatz.isEmpty { ergebnis.append(.paragraph(absatz.joined(separator: "\n"))); absatz = [] }
            if !liste.isEmpty { ergebnis.append(.list(liste)); liste = [] }
        }

        for zeile in zeilen {
            let t = zeile.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                abschliessen()
            } else if t.hasPrefix("- ") {
                if !absatz.isEmpty { ergebnis.append(.paragraph(absatz.joined(separator: "\n"))); absatz = [] }
                liste.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if !liste.isEmpty, zeile.first?.isWhitespace == true {
                // eingerückte Fortsetzung eines Listenpunkts
                liste[liste.count - 1] += " " + t
            } else {
                if !liste.isEmpty { ergebnis.append(.list(liste)); liste = [] }
                absatz.append(t)
            }
        }
        abschliessen()
        return ergebnis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    inline(text)
                case .list(let punkte):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(punkte.enumerated()), id: \.offset) { _, punkt in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(Color(white: 0.55))
                                inline(punkt)
                            }
                        }
                    }
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color(white: 0.85))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ text: String) -> some View {
        let attributed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        return Text(attributed)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Dashboard-Seite „Neuigkeiten“: alle Einträge aus `CHANGELOG.md`, neueste zuerst.
struct NewsView: View {
    let entries: [ChangelogEntry]
    let keys: [String]

    @State private var videoEntry: ChangelogEntry?

    init(entries: [ChangelogEntry], keys: [String]) {
        self.entries = entries
        self.keys = keys
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(Loc.t("Neuigkeiten")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))

                if entries.isEmpty {
                    Text(Loc.t("Keine Neuigkeiten gefunden."))
                        .font(.system(size: 12)).foregroundStyle(Color(white: 0.5))
                } else {
                    ForEach(entries) { entry in
                        entryView(entry)
                    }
                }
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
        .sheet(item: $videoEntry) { entry in
            if let name = entry.video {
                ExplainerSheet(name: name, keys: keys) { videoEntry = nil }
            }
        }
    }

    private func entryView(_ entry: ChangelogEntry) -> some View {
        ConsolePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(entry.version.description)
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Color(white: 0.95))
                    Text("·").foregroundStyle(Color(white: 0.4))
                    Text(entry.date).font(.system(size: 12)).foregroundStyle(Color(white: 0.5))
                    Spacer()
                }
                ChangelogText(entry.text(german: Loc.isGerman))
                if let name = entry.video, ExplainerController.url(for: name) != nil {
                    Button { videoEntry = entry } label: {
                        Label(Loc.t("Video ansehen"), systemImage: "play.rectangle.fill")
                    }
                    .buttonStyle(ConsoleButtonStyle())
                }
            }
            .padding(16)
        }
    }
}

/// Der Player im Sheet: 720 breit, darunter „Schließen“.
private struct ExplainerSheet: View {
    let name: String
    let keys: [String]
    let onClose: () -> Void
    /// Entsteht erst beim Erscheinen — nicht im `init`, das SwiftUI oft mehrfach aufruft.
    @State private var controller: ExplainerController?

    init(name: String, keys: [String], onClose: @escaping () -> Void) {
        self.name = name
        self.keys = keys
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 14) {
            if let controller {
                ExplainerView(controller: controller)
            }
            HStack {
                Spacer()
                Button(Loc.t("Schließen"), action: onClose)
                    .buttonStyle(ConsoleButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 720)
        .background(Color.shoutWindow)
        .preferredColorScheme(.dark)
        .onAppear {
            if controller == nil {
                controller = ExplainerController(name: name, german: Loc.isGerman, keys: keys, autoplay: true)
            }
        }
        .onDisappear { controller?.stop() }
    }
}
