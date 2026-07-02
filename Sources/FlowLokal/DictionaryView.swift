import SwiftUI

/// Verwaltungs-Oberfläche fürs persönliche Wörterbuch: Begriffe und
/// Korrektur-Paare (falsch → richtig) selbst anlegen und löschen.
struct DictionaryView: View {
    @ObservedObject var dictionary: PersonalDictionary

    @State private var newTerm = ""
    @State private var newWrong = ""
    @State private var newRight = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                GroupBox(label: Label("Begriffe", systemImage: "text.book.closed")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Eigennamen & Fachbegriffe, die exakt so geschrieben werden sollen.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            TextField("Neuer Begriff (z. B. inthezone)", text: $newTerm)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addTerm)
                            Button("Hinzufügen", action: addTerm)
                                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if dictionary.contents.terms.isEmpty {
                            Text("Noch keine Begriffe.").font(.caption).foregroundStyle(.tertiary)
                        } else {
                            ForEach(dictionary.contents.terms, id: \.self) { term in
                                HStack {
                                    Text(term)
                                    Spacer()
                                    Button {
                                        dictionary.removeTerm(term)
                                    } label: {
                                        Image(systemName: "trash").foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Divider()
                            }
                        }
                    }
                    .padding(6)
                }

                GroupBox(label: Label("Korrekturen", systemImage: "arrow.triangle.2.circlepath")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Falsch erkanntes Wort → richtige Schreibweise. Wird künftig automatisch ersetzt.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            TextField("falsch", text: $newWrong).textFieldStyle(.roundedBorder)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TextField("richtig", text: $newRight).textFieldStyle(.roundedBorder)
                            Button("Hinzufügen", action: addCorrection)
                                .disabled(newWrong.trimmingCharacters(in: .whitespaces).isEmpty
                                          || newRight.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if dictionary.contents.corrections.isEmpty {
                            Text("Noch keine Korrekturen.").font(.caption).foregroundStyle(.tertiary)
                        } else {
                            ForEach(dictionary.contents.corrections) { c in
                                HStack {
                                    Text(c.wrong).foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                                    Text(c.right)
                                    Spacer()
                                    Button {
                                        dictionary.removeCorrection(c)
                                    } label: {
                                        Image(systemName: "trash").foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Divider()
                            }
                        }
                    }
                    .padding(6)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 440, minHeight: 500)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Wörterbuch").font(.title2).bold()
            Text("shout. merkt sich diese Begriffe und Korrekturen für künftige Diktate.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addTerm() {
        dictionary.addTerm(newTerm)
        newTerm = ""
    }

    private func addCorrection() {
        dictionary.addCorrection(wrong: newWrong, right: newRight)
        newWrong = ""
        newRight = ""
    }
}
