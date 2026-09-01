import SwiftUI

/// Der Anbieter-Block auf dem iPhone — inhaltlich derselbe wie am Mac
/// (`ProviderPanel`), aber im `Form`/`Section`-Idiom von iOS statt in den
/// Konsolen-Bausteinen, die es nur am Mac gibt.
///
/// Am iPhone ist das Argument sogar stärker als am Mac: Ein iPhone hat 4–8 GB
/// RAM und harte Jetsam-Grenzen, ein großes Modell läuft dort nicht.
struct MobileProviderSection: View {

    let purpose: EnginePurpose
    let onChanged: () async -> Void

    @State private var config: RemoteConfig
    @State private var keyEntry = ""
    @State private var maskedKey: String?
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var statusText: String?
    @State private var statusOK: Bool?
    @State private var probing = false

    init(purpose: EnginePurpose, onChanged: @escaping () async -> Void) {
        self.purpose = purpose
        self.onChanged = onChanged
        let start = RemoteConfig.load(purpose: purpose)
            ?? RemoteConfig(template: ProviderCatalog.templates(for: purpose)[0], purpose: purpose)
        _config = State(initialValue: start)
        _maskedKey = State(initialValue: ProviderKeychain.masked(for: start.templateID))
    }

    private var template: ProviderTemplate? { ProviderCatalog.template(id: config.templateID) }

    private var addressEditable: Bool {
        guard let template else { return true }
        return template.baseURL.isEmpty || !template.needsKey
    }

    var body: some View {
        Group {
            Section {
                Picker(Loc.t("Anbieter"), selection: Binding(
                    get: { config.templateID },
                    set: { wechselVorlage(zu: $0) })) {
                    ForEach(ProviderCatalog.templates(for: purpose)) { vorlage in
                        Text(vorlage.name).tag(vorlage.id)
                    }
                }

                if addressEditable {
                    TextField(Loc.t("Adresse"), text: Binding(
                        get: { config.baseURL },
                        set: { config.baseURL = $0; speichern() }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } else {
                    LabeledContent(Loc.t("Adresse"), value: config.baseURL)
                        .font(.caption)
                }

                if template?.needsKey == true { keyRow }

                TextField(Loc.t("Modell"), text: Binding(
                    get: { config.model },
                    set: { config.model = $0; speichern() }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !vorschlaege.isEmpty {
                    Picker(Loc.t("Vorschläge"), selection: Binding(
                        get: { config.model },
                        set: { config.model = $0; speichern() })) {
                        ForEach(vorschlaege, id: \.self) { Text($0).tag($0) }
                    }
                }

                Button(action: { Task { await modelleLaden() } }) {
                    HStack {
                        Text(Loc.t("Modelle laden"))
                        if loadingModels { Spacer(); ProgressView() }
                    }
                }
                .disabled(loadingModels)

                Button(action: { Task { await testen() } }) {
                    HStack {
                        Text(Loc.t("Verbindung testen"))
                        Spacer()
                        if probing {
                            ProgressView()
                        } else if let statusOK {
                            Image(systemName: statusOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(statusOK ? Color.green : Color.orange)
                        }
                    }
                }
                .disabled(probing)
            } header: {
                Text(purpose == .text ? Loc.t("Aufbereitung (KI-Textmodell)")
                                      : Loc.t("Transkription (Sprache → Text)"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let statusText {
                        Text(statusText)
                    }
                    if let note = template?.note {
                        Text(Loc.t(note))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var keyRow: some View {
        if let maskedKey {
            LabeledContent(Loc.t("Schlüssel")) {
                HStack(spacing: 12) {
                    Text(maskedKey).font(.caption.monospaced())
                    Button(Loc.t("Entfernen")) { schluesselEntfernen() }
                        .font(.caption)
                }
            }
        } else {
            HStack {
                SecureField(Loc.t("Schlüssel"), text: $keyEntry)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(Loc.t("Speichern")) { schluesselSpeichern() }
                    .font(.caption)
                    .disabled(keyEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var vorschlaege: [String] {
        if !models.isEmpty { return models }
        guard let template else { return [] }
        return purpose == .text ? template.chatModels : template.audioModels
    }

    // MARK: - Aktionen

    private func wechselVorlage(zu id: String) {
        guard let vorlage = ProviderCatalog.template(id: id) else { return }
        config = RemoteConfig(template: vorlage, purpose: purpose)
        maskedKey = ProviderKeychain.masked(for: id)
        models = []
        statusText = nil
        statusOK = nil
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
            statusText = nil
            Task { await onChanged() }
        } catch {
            statusOK = false
            statusText = Loc.t("Der Schlüssel konnte nicht in der Keychain gespeichert werden.")
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
            statusText = nil
        } catch {
            statusOK = false
            statusText = ProviderText.describe(error)
        }
    }

    private func testen() async {
        guard let template else { return }
        probing = true
        statusOK = nil
        defer { probing = false }
        let ergebnis = await ProviderProbe.run(
            config: config,
            key: ProviderKeychain.read(for: template.id),
            needsKey: template.needsKey)

        switch ergebnis {
        case .ok(let sekunden, let gelistet):
            statusOK = gelistet != false
            let dauer = String(format: "%.1f", sekunden)
            switch gelistet {
            case true: statusText = Loc.f("Verbindung steht · %@ s", dauer)
            case false: statusText = Loc.f("Verbindung steht, aber „%@“ steht nicht in der Modell-Liste des Anbieters.", config.model)
            case nil: statusText = Loc.f("Verbindung steht · %@ s. Der Anbieter liefert keine Modell-Liste — ob das Modell stimmt, zeigt erst der erste Versuch.", dauer)
            }
        case .failed(let fehler):
            statusOK = false
            statusText = ProviderText.describe(fehler)
        }
    }
}
