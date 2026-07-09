import SwiftUI

/// Wörterbuch: Begriffe (Whisper-Bias + LLM-Hinweis) und Korrekturen (falsch→richtig).
struct MobileDictionaryView: View {
    @ObservedObject var dictionary: PersonalDictionary

    @State private var newTerm = ""
    @State private var newWrong = ""
    @State private var newRight = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Neuer Begriff (z. B. inthezone)", text: $newTerm)
                            .autocorrectionDisabled()
                            .onSubmit(addTerm)
                        Button("Hinzufügen", action: addTerm)
                            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(dictionary.contents.terms, id: \.self) { term in
                        Text(term)
                            .swipeActions {
                                Button(role: .destructive) { dictionary.removeTerm(term) } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("Begriffe")
                } footer: {
                    Text("Eigennamen und Fachbegriffe, die shout. richtig schreiben soll.")
                }

                Section {
                    VStack(spacing: 8) {
                        TextField("falsch", text: $newWrong).autocorrectionDisabled()
                        TextField("richtig", text: $newRight).autocorrectionDisabled()
                        Button("Korrektur hinzufügen", action: addCorrection)
                            .disabled(newWrong.trimmingCharacters(in: .whitespaces).isEmpty
                                      || newRight.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(dictionary.contents.corrections) { c in
                        HStack(spacing: 8) {
                            Text(c.wrong).strikethrough().foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                            Text(c.right).fontWeight(.medium).foregroundStyle(Color.shoutLive)
                        }
                        .swipeActions {
                            Button(role: .destructive) { dictionary.removeCorrection(c) } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Automatisch verbessert")
                } footer: {
                    Text("Diese Ersetzungen werden nach jeder Transkription angewendet.")
                }
            }
            .navigationTitle("Wörterbuch")
        }
    }

    private func addTerm() {
        dictionary.addTerm(newTerm); newTerm = ""
    }
    private func addCorrection() {
        dictionary.addCorrection(wrong: newWrong, right: newRight); newWrong = ""; newRight = ""
    }
}
