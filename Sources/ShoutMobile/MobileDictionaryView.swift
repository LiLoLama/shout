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
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(Loc.t("Neuer Begriff (z. B. inthezone)"), text: $newTerm)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .onSubmit(addTerm)
                        Button(Loc.t("Hinzufügen"), action: addTerm)
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if dictionary.contents.terms.isEmpty {
                        Label(Loc.t("Noch keine Begriffe"), systemImage: "text.book.closed")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(dictionary.contents.terms, id: \.self) { term in
                        Text(term)
                            .swipeActions {
                                Button(role: .destructive) { dictionary.removeTerm(term) } label: {
                                    Label(Loc.t("Löschen"), systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text(Loc.t("Begriffe"))
                } footer: {
                    Text(Loc.t("Eigennamen und Fachbegriffe, die shout. richtig schreiben soll."))
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(Loc.t("falsch"), text: $newWrong)
                            .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        TextField(Loc.t("richtig"), text: $newRight)
                            .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        Button(Loc.t("Korrektur hinzufügen"), action: addCorrection)
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                            .disabled(newWrong.trimmingCharacters(in: .whitespaces).isEmpty
                                      || newRight.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if dictionary.contents.corrections.isEmpty {
                        Label(Loc.t("Noch keine Korrekturen"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(dictionary.contents.corrections) { c in
                        HStack(spacing: 8) {
                            Text(c.wrong).strikethrough().foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(c.right).fontWeight(.medium).foregroundStyle(.primary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { dictionary.removeCorrection(c) } label: {
                                Label(Loc.t("Löschen"), systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(Loc.t("Automatisch verbessert"))
                } footer: {
                    Text(Loc.t("Diese Ersetzungen werden nach jeder Transkription angewendet."))
                }
            }
            .navigationTitle(Loc.t("Wörterbuch"))
        }
    }

    private func addTerm() {
        dictionary.addTerm(newTerm); newTerm = ""
    }
    private func addCorrection() {
        dictionary.addCorrection(wrong: newWrong, right: newRight); newWrong = ""; newRight = ""
    }
}
