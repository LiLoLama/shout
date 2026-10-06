import SwiftUI

/// Eigene Transforms: Liste, Hinzufügen, Bearbeiten, Löschen.
struct TransformSettingsSection: View {
    @ObservedObject var store: TransformStore

    /// Was das Blatt gerade bearbeitet. `transformID == nil`: ein neuer.
    private struct Entwurf: Identifiable {
        let id = UUID()
        let transformID: UUID?
        var name: String
        var prompt: String
    }

    @State private var entwurf: Entwurf?

    var body: some View {
        ConsolePanel(title: Loc.t("Eigene Transforms")) {
            if store.custom.isEmpty {
                FieldRow(title: Loc.t("Noch keine eigenen Transforms."),
                         help: Loc.t("Erscheinen im Zauberstab und wirken auf die Auswahl oder die ganze Notiz.")) {
                    EmptyView()
                }
            }
            ForEach(store.custom) { t in
                FieldRow(title: t.name, help: t.prompt) {
                    HStack(spacing: 8) {
                        Button(Loc.t("Bearbeiten")) {
                            entwurf = Entwurf(transformID: t.id, name: t.name, prompt: t.prompt)
                        }
                        .buttonStyle(ConsoleButtonStyle())
                        Button(Loc.t("Löschen")) { store.remove(t.id) }.buttonStyle(ConsoleButtonStyle())
                    }
                }
                ConsoleDivider()
            }
            HStack {
                Spacer()
                Button(Loc.t("Hinzufügen")) { entwurf = Entwurf(transformID: nil, name: "", prompt: "") }
                    .buttonStyle(ConsoleButtonStyle())
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
        }
        .sheet(item: $entwurf) { e in
            TransformEditor(entwurf: e) { name, prompt in
                if let id = e.transformID {
                    return store.update(id, name: name, prompt: prompt)
                }
                return store.add(name: name, prompt: prompt) != nil
            } onClose: { entwurf = nil }
        }
    }

    private struct TransformEditor: View {
        @State var name: String
        @State var prompt: String
        @State private var fehlgeschlagen = false
        let neu: Bool
        let onSave: (String, String) -> Bool
        let onClose: () -> Void

        init(entwurf: Entwurf, onSave: @escaping (String, String) -> Bool, onClose: @escaping () -> Void) {
            _name = State(initialValue: entwurf.name)
            _prompt = State(initialValue: entwurf.prompt)
            neu = entwurf.transformID == nil
            self.onSave = onSave
            self.onClose = onClose
        }

        private var leer: Bool {
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(neu ? Loc.t("Neuer Transform") : Loc.t("Transform bearbeiten"))
                    .font(.system(size: 15, weight: .semibold))
                TextField(Loc.t("Name"), text: $name)
                Text(Loc.t("Anweisung")).font(.system(size: 12, weight: .medium))
                TextEditor(text: $prompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.1)))
                Text(Loc.t("Was soll mit dem Text passieren? Zum Beispiel: „Kürze auf drei Sätze.“"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if fehlgeschlagen {
                    Text(Loc.t("Konnte nicht gesichert werden.")).font(.system(size: 11)).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button(Loc.t("Abbrechen"), action: onClose).keyboardShortcut(.cancelAction)
                    Button(Loc.t("Sichern")) { if onSave(name, prompt) { onClose() } else { fehlgeschlagen = true } }
                        .disabled(leer)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 460)
        }
    }
}
