import SwiftUI

/// Kleiner Editor für das letzte Diktat. Der Nutzer bessert falsch erkannte
/// Wörter aus; beim Übernehmen werden die Korrekturen gelernt. Funktioniert in
/// jeder App, weil die Bearbeitung hier in shout.s eigenem Fenster passiert.
struct CorrectionView: View {
    let original: String
    let onApply: (String) -> Void
    let onCancel: () -> Void

    @State private var edited: String

    init(original: String, onApply: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.original = original
        self.onApply = onApply
        self.onCancel = onCancel
        _edited = State(initialValue: original)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Letztes Diktat korrigieren").font(.headline)
            Text("Bessere falsch erkannte Wörter aus. shout. lernt die Korrekturen fürs nächste Mal — in jeder App.")
                .font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $edited)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                Spacer()
                Button("Abbrechen", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Übernehmen") { onApply(edited) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(edited == original)
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}
