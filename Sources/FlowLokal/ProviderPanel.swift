import SwiftUI

/// Der Anbieter-Block in der Modell-Ansicht — einmal für die Aufbereitung,
/// einmal für die Transkription.
///
/// Er lebt hier und nicht in den Einstellungen, weil die Modell-Ansicht schon
/// die Frage beantwortet „welches Modell macht welchen Schritt". Die
/// Anbieterwahl ist dieselbe Frage; sie auf zwei Ansichten zu verteilen würde
/// eine Entscheidung zerreißen.
struct ProviderPanel: View {

    let purpose: EnginePurpose
    /// Wird gerufen, wenn sich etwas geändert hat, das ein Neuladen der Engine
    /// braucht. Der Aufrufer stößt damit `reload()` am Router an.
    let onChanged: () async -> Void

    @State private var config: RemoteConfig
    @State private var keyEntry = ""
    @State private var maskedKey: String?
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var probeText: String?
    @State private var probeOK: Bool?
    @State private var probing = false
    @State private var lastError: String?
    @ObservedObject private var usage = ProviderUsageStore.shared
    @State private var loadingPrices = false

    init(purpose: EnginePurpose, onChanged: @escaping () async -> Void) {
        self.purpose = purpose
        self.onChanged = onChanged
        let gespeichert = RemoteConfig.load(purpose: purpose)
        let start = gespeichert
            ?? RemoteConfig(template: ProviderCatalog.templates(for: purpose)[0], purpose: purpose)
        _config = State(initialValue: start)
        _maskedKey = State(initialValue: ProviderKeychain.masked(for: start.templateID))
    }

    private var template: ProviderTemplate? { ProviderCatalog.template(id: config.templateID) }

    /// Adresse selbst eintragen: bei „Eigener Endpunkt" und bei Anbietern auf dem
    /// eigenen Rechner, wo Host und Port abweichen können.
    private var addressEditable: Bool {
        guard let template else { return true }
        return template.baseURL.isEmpty || !template.needsKey
    }

    var body: some View {
        VStack(spacing: 0) {
            providerRow
            ConsoleDivider()
            addressRow
            if template?.needsKey == true {
                ConsoleDivider()
                keyRow
            }
            ConsoleDivider()
            modelRow
            ConsoleDivider()
            probeRow
            if template?.needsKey == true {
                ConsoleDivider()
                costRow
            }
            if let note = template?.note {
                ConsoleDivider()
                noteRow(note)
            }
            if let lastError {
                ConsoleDivider()
                errorRow(lastError)
            }
        }
    }

    // MARK: - Zeilen

    private var providerRow: some View {
        FieldRow(title: Loc.t("Anbieter"),
                 help: purpose == .audio
                     ? Loc.t("Nur Anbieter, die transkribieren können, stehen hier.")
                     : nil) {
            Picker("", selection: Binding(
                get: { config.templateID },
                set: { neu in wechselVorlage(zu: neu) })) {
                ForEach(ProviderCatalog.templates(for: purpose)) { vorlage in
                    Text(vorlage.name).tag(vorlage.id)
                }
            }
            .labelsHidden().frame(minWidth: 150, idealWidth: 200, maxWidth: 220)
        }
    }

    private var addressRow: some View {
        FieldRow(title: Loc.t("Adresse"),
                 help: addressEditable
                     ? Loc.t("Die Basis-Adresse. „/chat/completions“ wird selbst angehängt.")
                     : nil) {
            if addressEditable {
                TextField("", text: Binding(
                    get: { config.baseURL },
                    set: { config.baseURL = $0; speichern() }))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160, idealWidth: 260, maxWidth: 300)
            } else {
                // Umbrechen statt abschneiden: Die Adressen im Katalog passen
                // alle in eine Zeile (die längste ist Google mit 54 Zeichen),
                // aber ein eigener Endpunkt kann länger sein.
                Text(config.baseURL)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var keyRow: some View {
        FieldRow(title: Loc.t("Schlüssel"), help: schluesselHilfe) {
            if let maskedKey {
                HStack(spacing: 8) {
                    Text(maskedKey)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(white: 0.7))
                    Button(Loc.t("Ersetzen")) { self.maskedKey = nil }
                        .buttonStyle(ConsoleButtonStyle()).fixedSize()
                    Button(Loc.t("Entfernen")) { schluesselEntfernen() }
                        .buttonStyle(ConsoleButtonStyle()).fixedSize()
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("", text: $keyEntry)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 120, idealWidth: 200, maxWidth: 240)
                    Button(Loc.t("Speichern")) { schluesselSpeichern() }
                        .buttonStyle(ConsoleButtonStyle()).fixedSize()
                        .disabled(keyEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var schluesselHilfe: String? {
        guard maskedKey == nil, let template, !template.keyURL.isEmpty else { return nil }
        return Loc.f("Bekommst du bei: %@", template.keyURL)
    }

    /// Nur Textfeld und Vorschlagsmenü.
    ///
    /// „Modelle laden" saß hier ursprünglich mit in der Zeile — bei 640 Punkten
    /// Ansichtsbreite passten Hilfetext, Feld, Menü und Knopf nicht nebeneinander,
    /// und SwiftUI staucht dann den Knopf zu einer Buchstabensäule statt den Text
    /// umzubrechen. Der Knopf steht jetzt bei „Verbindung", wo er inhaltlich
    /// ohnehin hingehört: beides holt etwas beim Anbieter.
    private var modelRow: some View {
        FieldRow(title: Loc.t("Modell"),
                 help: Loc.t("Kennung frei eintragbar.")) {
            HStack(spacing: 8) {
                TextField("", text: Binding(
                    get: { config.model },
                    set: { config.model = $0; speichern() }))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, idealWidth: 190, maxWidth: 220)

                if !vorschlaege.isEmpty {
                    Menu {
                        ForEach(vorschlaege, id: \.self) { id in
                            Button(id) { config.model = id; speichern() }
                        }
                    } label: {
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .menuStyle(.borderlessButton).frame(width: 18).fixedSize()
                }
            }
        }
    }

    /// Erst die geladene Liste, sonst die handverlesenen Vorschläge der Vorlage.
    private var vorschlaege: [String] {
        if !models.isEmpty { return models }
        guard let template else { return [] }
        return purpose == .text ? template.chatModels : template.audioModels
    }

    private var probeRow: some View {
        FieldRow(title: Loc.t("Verbindung"), help: probeText) {
            HStack(spacing: 8) {
                if probing || loadingModels {
                    ProgressView().controlSize(.small).tint(Color.shoutLive)
                } else if let probeOK {
                    Image(systemName: probeOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(probeOK ? Color.shoutLive : Color(white: 0.6))
                }
                Button(Loc.t("Modelle laden")) { Task { await modelleLaden() } }
                    .buttonStyle(ConsoleButtonStyle()).disabled(loadingModels).fixedSize()
                Button(Loc.t("Verbindung testen")) { Task { await testen() } }
                    .buttonStyle(ConsoleButtonStyle()).disabled(probing).fixedSize()
            }
        }
    }

    /// Kosten — gemessen, nicht geschätzt: Die Token stehen in jeder Antwort.
    /// Bei Anbietern auf dem eigenen Rechner entfällt die Zeile ganz.
    private var costRow: some View {
        FieldRow(title: Loc.t("Kosten"), help: kostenHilfe) {
            HStack(spacing: 8) {
                if loadingPrices { ProgressView().controlSize(.small).tint(Color.shoutLive) }
                Button(Loc.t("Preise aktualisieren")) { Task { await preiseLaden() } }
                    .buttonStyle(ConsoleButtonStyle()).disabled(loadingPrices).fixedSize()
            }
        }
    }

    private var kostenHilfe: String {
        let (monat, unbekannt) = usage.cost()
        var zeilen: [String] = []

        if purpose == .text, let preis = usage.prices.price(forText: config.model),
           let jeDiktat = ProviderCosts.cost(tokens: ProviderCosts.typicalDictation,
                                             price: preis) {
            zeilen.append(Loc.f("ca. %@ je Diktat", ProviderCosts.format(usd: jeDiktat)))
        } else if purpose == .audio, let preis = usage.prices.price(forAudio: config.model),
                  let jeMinute = ProviderCosts.cost(seconds: 60, price: preis) {
            zeilen.append(Loc.f("ca. %@ je Minute Audio", ProviderCosts.format(usd: jeMinute)))
        } else {
            zeilen.append(Loc.t("Preis dieses Modells unbekannt."))
        }

        zeilen.append(Loc.f("Diesen Monat: %@", ProviderCosts.format(usd: monat))
                      + (unbekannt ? " " + Loc.t("(ohne die Modelle mit unbekanntem Preis)") : ""))
        zeilen.append(Loc.f("Näherung — abgerechnet wird beim Anbieter. Preise: Stand %@",
                            Self.datum.string(from: usage.prices.updated)))
        return zeilen.joined(separator: "\n")
    }

    private static let datum: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private func preiseLaden() async {
        loadingPrices = true
        defer { loadingPrices = false }
        do {
            usage.replacePrices(try await PriceFetch.fetch())
            lastError = nil
        } catch {
            lastError = ProviderText.describe(error)
        }
    }

    private func noteRow(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 11))
                .foregroundStyle(Color(white: 0.45))
            Text(Loc.t(note)).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    private func errorRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                .foregroundStyle(Color.shoutLive)
            Text(text).font(.system(size: 11)).foregroundStyle(Color(white: 0.7))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    // MARK: - Aktionen

    private func wechselVorlage(zu id: String) {
        guard let vorlage = ProviderCatalog.template(id: id) else { return }
        config = RemoteConfig(template: vorlage, purpose: purpose)
        maskedKey = ProviderKeychain.masked(for: id)
        models = []
        probeText = nil
        probeOK = nil
        lastError = nil
        speichern()
    }

    private func speichern() {
        config.save(purpose: purpose)
        Task { await onChanged() }
    }

    private func schluesselSpeichern() {
        let wert = keyEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wert.isEmpty else { return }
        do {
            try ProviderKeychain.store(wert, for: config.templateID)
            maskedKey = ProviderKeychain.mask(wert)
            keyEntry = ""
            lastError = nil
            Task { await onChanged() }
        } catch {
            lastError = Loc.t("Der Schlüssel konnte nicht in der Keychain gespeichert werden.")
        }
    }

    private func schluesselEntfernen() {
        try? ProviderKeychain.delete(for: config.templateID)
        maskedKey = nil
        keyEntry = ""
        Task { await onChanged() }
    }

    private func modelleLaden() async {
        guard let template else { return }
        loadingModels = true
        defer { loadingModels = false }
        do {
            let ids = try await ProviderModels.fetch(
                config: config,
                key: ProviderKeychain.read(for: template.id),
                needsKey: template.needsKey)
            models = purpose == .audio ? AudioModelFilter.apply(ids) : ids
            lastError = nil
        } catch {
            lastError = ProviderText.describe(error)
        }
    }

    private func testen() async {
        guard let template else { return }
        probing = true
        probeOK = nil
        defer { probing = false }
        let ergebnis = await ProviderProbe.run(
            config: config,
            key: ProviderKeychain.read(for: template.id),
            needsKey: template.needsKey)

        switch ergebnis {
        case .ok(let sekunden, let gelistet):
            probeOK = gelistet != false
            let dauer = String(format: "%.1f", sekunden)
            switch gelistet {
            case true:
                probeText = Loc.f("Verbindung steht · %@ s", dauer)
            case false:
                probeText = Loc.f("Verbindung steht, aber „%@“ steht nicht in der Modell-Liste des Anbieters.",
                                  config.model)
            case nil:
                probeText = Loc.f("Verbindung steht · %@ s. Der Anbieter liefert keine Modell-Liste — ob das Modell stimmt, zeigt erst der erste Versuch.",
                                  dauer)
            }
            lastError = nil
        case .failed(let fehler):
            probeOK = false
            probeText = nil
            lastError = ProviderText.describe(fehler)
        }
    }
}
