import SwiftUI
import AppKit
import Contacts
import UniformTypeIdentifiers

/// Wörterbuch im Mischpult-Look: Begriffe + Korrekturen selbst verwalten.
struct DictionaryView: View {
    @ObservedObject var dictionary: PersonalDictionary

    @State private var newTerm = ""
    @State private var newWrong = ""
    @State private var newRight = ""
    @State private var importStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ConsolePanel(title: "Wörter, die shout. richtig schreiben soll") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            consoleField("Neuer Begriff (z. B. inthezone)", text: $newTerm) { addTerm() }
                            Button("Hinzufügen", action: addTerm)
                                .buttonStyle(ConsoleButtonStyle())
                                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        HStack(spacing: 8) {
                            Button("Aus Datei (CSV/TXT) …", action: importFromFile).buttonStyle(ConsoleButtonStyle())
                            Button("Aus Kontakten …", action: importFromContacts).buttonStyle(ConsoleButtonStyle())
                            if !importStatus.isEmpty {
                                Text(importStatus).font(.system(size: 11)).foregroundStyle(Color.shoutLive)
                            }
                        }
                        if dictionary.contents.terms.isEmpty {
                            Text("Noch keine Begriffe.").font(.system(size: 12)).foregroundStyle(Color(white: 0.5))
                        } else {
                            FlowChips(terms: dictionary.contents.terms) { dictionary.removeTerm($0) }
                        }
                    }
                    .padding(16)
                }

                ConsolePanel(title: "Automatisch verbessert") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            consoleField("falsch", text: $newWrong) {}
                            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                            consoleField("richtig", text: $newRight) { addCorrection() }
                            Button("Hinzufügen", action: addCorrection)
                                .buttonStyle(ConsoleButtonStyle())
                                .disabled(newWrong.trimmingCharacters(in: .whitespaces).isEmpty
                                          || newRight.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if dictionary.contents.corrections.isEmpty {
                            Text("Noch keine Korrekturen — shout. lernt sie auch automatisch, wenn du ein Wort ausbesserst.")
                                .font(.system(size: 12)).foregroundStyle(Color(white: 0.5))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(dictionary.contents.corrections) { c in
                                HStack(spacing: 9) {
                                    Text(c.wrong).foregroundStyle(Color(white: 0.55)).strikethrough()
                                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Color(white: 0.45))
                                    Text(c.right).fontWeight(.semibold).foregroundStyle(Color.shoutLive)
                                    Spacer()
                                    Button { dictionary.removeCorrection(c) } label: {
                                        Image(systemName: "trash").foregroundStyle(Color(white: 0.5))
                                    }.buttonStyle(.borderless)
                                }
                                .font(.system(size: 13))
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
    }

    private func consoleField(_ placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Color(white: 0.92))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.07)))
            .onSubmit(onSubmit)
    }

    private func addTerm() {
        dictionary.addTerm(newTerm); newTerm = ""
    }
    private func addCorrection() {
        dictionary.addCorrection(wrong: newWrong, right: newRight); newWrong = ""; newRight = ""
    }

    // MARK: - Massen-Import

    /// Importiert Begriffe aus einer CSV/TXT — jeweils das erste Feld pro Zeile.
    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .text]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let before = dictionary.contents.terms.count
        for line in content.split(whereSeparator: \.isNewline) {
            let field = line.split(separator: ",", maxSplits: 1).first.map(String.init) ?? String(line)
            let term = field.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            if !term.isEmpty { dictionary.addTerm(term) }
        }
        importStatus = "\(dictionary.contents.terms.count - before) neue Begriffe."
    }

    /// Importiert Vor-/Nachnamen und Firmen aus den lokalen Kontakten (bleiben on-device).
    private func importFromContacts() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            guard granted else {
                Task { @MainActor in importStatus = "Kein Zugriff auf Kontakte." }
                return
            }
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                        CNContactOrganizationNameKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var names = Set<String>()
            try? store.enumerateContacts(with: request) { c, _ in
                for n in [c.givenName, c.familyName, c.organizationName]
                where !n.trimmingCharacters(in: .whitespaces).isEmpty {
                    names.insert(n)
                }
            }
            Task { @MainActor in
                let before = dictionary.contents.terms.count
                for n in names { dictionary.addTerm(n) }
                importStatus = "\(dictionary.contents.terms.count - before) Namen aus Kontakten."
            }
        }
    }
}

/// Begriffe als umbrechende „Chips" mit Löschen-Button.
private struct FlowChips: View {
    let terms: [String]
    let onDelete: (String) -> Void

    var body: some View {
        FlexWrap(spacing: 7, lineSpacing: 7) {
            ForEach(terms, id: \.self) { term in
                HStack(spacing: 6) {
                    Text(term).font(.system(size: 13))
                    Button { onDelete(term) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }.buttonStyle(.borderless).foregroundStyle(Color(white: 0.5))
                }
                .foregroundStyle(Color(white: 0.9))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(Color(white: 0.11)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.07)))
            }
        }
    }
}

/// Einfaches umbrechendes Layout für die Chips.
private struct FlexWrap: Layout {
    var spacing: CGFloat = 7
    var lineSpacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += lineH + lineSpacing; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
    }
}
