import AppKit
import HuggingFace
import SwiftUI

/// „Modelle" — erkennt die Hardware, empfiehlt das passende lokale Modell für
/// Transkription und Aufbereitung und lässt frei umschalten. Beim Umschalten
/// wird das Modell (falls nötig heruntergeladen und) neu in den Prozess geladen.
struct ModelsView: View {
    @ObservedObject var model: DashboardModel
    /// Wechselt das Transkriptions- bzw. Formatierungs-Modell und lädt neu.
    let onSelectASR: (String) async -> Void
    let onSelectFormat: (String) async -> Void
    /// Lädt die Engine des Schrittes neu — nach einem Wechsel zwischen „auf
    /// diesem Gerät" und „Anbieter" oder einer Änderung an der Anbieter-Einstellung.
    let onEngineChanged: (EnginePurpose) async -> Void

    /// „local" oder „remote", je Verarbeitungsschritt.
    @AppStorage("asrEngine") private var asrEngine = "local"
    @AppStorage("formatEngine") private var formatEngine = "local"
    @ObservedObject private var loc = Loc.shared

    // Auswahl + Ladezustand kommen aus dem DashboardModel (überlebt Tab-Wechsel).
    private var asrID: String { model.activeASR }
    private var formatID: String { model.activeFormat }
    private var loadingASR: String? { model.asrLoadingID }
    private var loadingFormat: String? { model.formatLoadingID }

    // Live von Hugging Face entdeckte Modelle.
    @State private var remote: [RemoteModel] = []
    @State private var remoteLoading = false
    @State private var remoteError: String?
    @State private var didFetch = false

    // Modellverzeichnis: wohin shout. selbst ablegt und wo es zusätzlich
    // mitbenutzt. `pfade` wird nur über `basisordnerWechseln(zu:)` geändert —
    // `basisordner` hat mit Absicht keinen Setter (siehe ModelPaths.swift).
    @State private var pfade = ModelPaths.laden(aus: .standard,
                                                vorgabe: { HubCache.default.cacheDirectory })
    @State private var suchstand: [URL: Suchstand] = [:]
    @State private var durchsuchtGerade: URL?
    @State private var laufendeSuche: AbbruchFlagge?

    private var ram: Int { Hardware.physicalMemoryGB }
    private var recASR: ModelCatalog.Option { ModelCatalog.recommendedASR(ramGB: ram) }
    private var recFormat: ModelCatalog.Option { ModelCatalog.recommendedFormatting(ramGB: ram) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(Loc.t("Modelle")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))

                if let note = model.modelNote {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Color.shoutLive)
                        Text(note).font(.system(size: 12)).foregroundStyle(Color(white: 0.8))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.shoutLive.opacity(0.12)))
                }

                hardwarePanel

                ConsolePanel(title: Loc.t("Transkription (Sprache → Text)")) {
                    VStack(spacing: 0) {
                        engineSwitch(for: .audio, selection: $asrEngine)
                        ConsoleDivider()
                        if asrEngine == "remote" {
                            ProviderPanel(purpose: .audio) { await onEngineChanged(.audio) }
                        } else {
                            ForEach(ModelCatalog.asr.indices, id: \.self) { i in
                                let o = ModelCatalog.asr[i]
                                // Ohne Herkunft: Die Whisper-Modelle legt WhisperKit in
                                // einem eigenen Format ab (`<basis>/models/org/repo/`),
                                // das `ModelStore` nicht auflöst — ein Abzeichen wäre
                                // hier bestenfalls geraten.
                                modelRow(o, selected: asrID == o.id, recommended: recASR.id == o.id,
                                         loading: loadingASR == o.id, zustand: .nichtVorhanden,
                                         progress: loadingASR == o.id ? model.asrProgress : nil) { selectASR(o.id) }
                                if i < ModelCatalog.asr.count - 1 { ConsoleDivider() }
                            }
                        }
                    }
                }

                ConsolePanel(title: Loc.t("Aufbereitung & Formatierung (KI-Textmodell)")) {
                    VStack(spacing: 0) {
                        engineSwitch(for: .text, selection: $formatEngine)
                        ConsoleDivider()
                        if formatEngine == "remote" {
                            ProviderPanel(purpose: .text) { await onEngineChanged(.text) }
                        } else {
                            ForEach(ModelCatalog.formatting.indices, id: \.self) { i in
                                let o = ModelCatalog.formatting[i]
                                modelRow(o, selected: formatID == o.id, recommended: recFormat.id == o.id,
                                         loading: loadingFormat == o.id, zustand: zustand(fuer: o.id),
                                         progress: loadingFormat == o.id ? model.formatProgress : nil) { selectFormat(o.id) }
                                if i < ModelCatalog.formatting.count - 1 { ConsoleDivider() }
                            }
                        }
                    }
                }

                if formatEngine == "local" { remotePanel }

                ordnerAbschnitt

                Text(asrEngine == "remote" || formatEngine == "remote"
                     ? Loc.t("Ein Schritt läuft bei einem Anbieter. Was dorthin geht, verlässt dein Gerät; abgerechnet wird beim Anbieter. Der andere Schritt und alles Übrige bleibt lokal.")
                     : Loc.t("Modelle werden beim ersten Auswählen einmalig von Hugging Face geladen und danach lokal gespeichert. Alles läuft anschließend komplett offline auf deinem Mac."))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
        .task { if !didFetch { didFetch = true; await refreshRemote() } }
    }

    // MARK: - Umschalter „auf diesem Gerät" / „Anbieter"

    private func engineSwitch(for purpose: EnginePurpose,
                              selection: Binding<String>) -> some View {
        FieldRow(title: Loc.t("Verarbeitung"),
                 help: selection.wrappedValue == "remote"
                     ? Loc.t("Läuft bei einem Anbieter deiner Wahl. Standard ist dein Gerät.")
                     : Loc.t("Läuft vollständig auf diesem Gerät. Nichts verlässt es.")) {
            ConsoleSegmented(selection: Binding(
                get: { selection.wrappedValue },
                set: { neu in
                    guard neu != selection.wrappedValue else { return }
                    selection.wrappedValue = neu
                    Task { await onEngineChanged(purpose) }
                }),
                options: [("local", Loc.t("Auf diesem Gerät")), ("remote", Loc.t("Anbieter"))])
        }
    }

    // MARK: - Live-Modelle von Hugging Face

    /// Beliebtestes live entdecktes Modell mit BEKANNTER Größe, das auf diesen Mac passt.
    /// Modelle ohne erkennbare Parameterzahl werden nicht empfohlen (könnten zu groß sein).
    private var remoteRecommended: RemoteModel? {
        remote.first { if let r = $0.minRAMGB { return r <= ram } else { return false } }
    }

    private var remotePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(Loc.t("AKTUELLE MODELLE · HUGGING FACE"))
                    .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Color(white: 0.45)).padding(.leading, 4)
                Spacer()
                Button(action: { Task { await refreshRemote() } }) {
                    HStack(spacing: 5) {
                        if remoteLoading { ProgressView().controlSize(.small).tint(Color.shoutLive) }
                        else { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)) }
                        Text(remoteLoading ? Loc.t("Lädt …") : Loc.t("Aktualisieren"))
                    }
                }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(remoteLoading)
            }

            VStack(spacing: 0) {
                if let remoteError {
                    infoLine(Loc.f("Keine Verbindung zu Hugging Face. %@", remoteError))
                } else if remote.isEmpty && remoteLoading {
                    infoLine(Loc.t("Suche aktuelle Modelle …"))
                } else if remote.isEmpty {
                    infoLine(Loc.t("Keine Modelle gefunden."))
                } else {
                    ForEach(Array(remote.enumerated()), id: \.element.id) { i, m in
                        remoteRow(m, selected: formatID == m.id,
                                  recommended: remoteRecommended?.id == m.id,
                                  loading: loadingFormat == m.id, zustand: zustand(fuer: m.id),
                                  progress: loadingFormat == m.id ? model.formatProgress : nil) { selectFormat(m.id) }
                        if i < remote.count - 1 { ConsoleDivider() }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.165)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.07)))

            Text(Loc.t("Live aus der Hugging-Face-Bibliothek „mlx-community“ (Instruct-Modelle, 4-bit). Größe geschätzt — für die Aufbereitung; die Transkription bleibt bei den geprüften Whisper-Modellen oben."))
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.42))
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 4)
        }
    }

    private func infoLine(_ text: String) -> some View {
        HStack { Text(text).font(.system(size: 12)).foregroundStyle(Color(white: 0.55)); Spacer() }
            .padding(.horizontal, 15).padding(.vertical, 14)
    }

    @ViewBuilder
    private func remoteRow(_ m: RemoteModel, selected: Bool, recommended: Bool,
                           loading: Bool, zustand: ModelZustand,
                           progress: Double?, action: @escaping () -> Void) -> some View {
        let known = m.minRAMGB != nil
        let tooBig = (m.minRAMGB ?? 0) > ram
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16)).foregroundStyle(selected ? Color.shoutLive : Color(white: 0.4))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(m.shortName).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(white: 0.9))
                            .lineLimit(1).truncationMode(.middle)
                        if recommended { tag(Loc.t("Aktuell beliebt"), color: .shoutLive) }
                        if tooBig { tag(Loc.t("Viel RAM nötig"), color: Color(white: 0.55)) }
                        else if !known { tag(Loc.t("Größe unbekannt"), color: Color(white: 0.55)) }
                        zustandsAbzeichen(zustand)
                    }
                    Text(remoteSubtitle(m)).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                    herkunftsZeile(zustand)
                }
                Spacer(minLength: 8)
                if loading { loadingIndicator(progress) }
            }
            .padding(.horizontal, 15).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSwitchingModel)
    }

    private func remoteSubtitle(_ m: RemoteModel) -> String {
        var parts: [String] = []
        if let gb = m.estimatedGB { parts.append("~\(Int(gb.rounded())) GB") }
        parts.append("\(formatCount(m.downloads))↓")
        if m.likes > 0 { parts.append("\(m.likes)♥") }
        return parts.joined(separator: " · ")
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private func refreshRemote() async {
        remoteLoading = true
        remoteError = nil
        do {
            remote = try await HuggingFaceModels.fetchFormatting()
        } catch {
            remoteError = error.localizedDescription
        }
        remoteLoading = false
    }

    // MARK: - Hardware

    private var hardwarePanel: some View {
        ConsolePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "cpu").font(.system(size: 26)).foregroundStyle(Color.shoutLive)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Hardware.chip).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.95))
                        Text(Loc.f("%d GB Arbeitsspeicher · %d Kerne", ram, Hardware.coreCount))
                            .font(.system(size: 12)).foregroundStyle(Color(white: 0.58))
                    }
                    Spacer()
                }
                ConsoleDivider().padding(.horizontal, -15)
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Color.shoutLive)
                    // .init(…) macht daraus eine LocalizedStringKey — SwiftUI parst
                    // das Markdown (**fett**) weiterhin.
                    Text(.init(Loc.f("Empfohlen für deinen Mac: **%@** zum Transkribieren, **%@** zum Aufbereiten.",
                                     recASR.name, recFormat.name)))
                        .font(.system(size: 12)).foregroundStyle(Color(white: 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Modell-Zeile

    @ViewBuilder
    private func modelRow(_ o: ModelCatalog.Option, selected: Bool, recommended: Bool,
                          loading: Bool, zustand: ModelZustand,
                          progress: Double?, action: @escaping () -> Void) -> some View {
        let tooBig = ram < o.minRAMGB
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16)).foregroundStyle(selected ? Color.shoutLive : Color(white: 0.4))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(o.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Color(white: 0.9))
                        if recommended { tag(Loc.t("Empfohlen"), color: .shoutLive) }
                        if tooBig { tag(Loc.t("Viel RAM nötig"), color: Color(white: 0.55)) }
                        zustandsAbzeichen(zustand)
                    }
                    Text(Loc.t(o.note)).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                    herkunftsZeile(zustand)
                }
                Spacer(minLength: 8)
                if loading { loadingIndicator(progress) }
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSwitchingModel)
    }

    /// Fortschrittsbalken mit Prozent während des Downloads, sonst unbestimmter Spinner.
    @ViewBuilder
    private func loadingIndicator(_ progress: Double?) -> some View {
        if let p = progress, p > 0.0001, p < 0.999 {
            HStack(spacing: 6) {
                ProgressView(value: p).progressViewStyle(.linear).frame(width: 66).tint(Color.shoutLive)
                Text("\(Int(p * 100)) %")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6)).monospacedDigit()
            }
        } else {
            ProgressView().controlSize(.small).tint(Color.shoutLive)
        }
    }

    // MARK: - Herkunft je Modell

    /// Wo dieses Modell steht. Fragt das Dateisystem über den `ModelStore` —
    /// ein Durchsuchen ist dafür nicht nötig, die Auflösung kennt die Orte.
    private func zustand(fuer kennung: String) -> ModelZustand {
        pfade.store.zustand(kennung, verknuepft: pfade.verknuepfungen[kennung])
    }

    @ViewBuilder
    private func zustandsAbzeichen(_ zustand: ModelZustand) -> some View {
        switch zustand {
        case .fremd:
            tag(Loc.t("Fremder Ordner"), color: Color(white: 0.55))
        case .nichtAuffindbar:
            // Deutlich ausgezeichnet, nicht nur ausgegraut: Hier fehlt eine
            // Platte, und das ist etwas anderes als „noch nicht geladen".
            tag(Loc.t("Nicht auffindbar"), color: .orange)
        case .eigen, .nichtVorhanden:
            EmptyView()
        }
    }

    /// Der Pfad eines mitbenutzten Modells — nur bei fremden Ordnern. Im
    /// eigenen Basisordner steht er schon oben im Abschnitt.
    @ViewBuilder
    private func herkunftsZeile(_ zustand: ModelZustand) -> some View {
        if case .fremd(let pfad) = zustand {
            Text(pfad.path).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.42))
                .lineLimit(1).truncationMode(.head)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    // MARK: - Modellverzeichnis

    /// Was zuletzt mit einem durchsuchten Ordner geschehen ist.
    ///
    /// Abbruch und Größengrenze sehen im Ergebnis von `ModelScan` gleich aus
    /// (beide liefern `grenzeErreicht == true`) — hier werden sie getrennt
    /// gehalten: Wer selbst abgebrochen hat, soll nicht lesen, sein Ordner sei
    /// zu groß.
    private enum Suchstand: Equatable {
        case laeuft
        case fertig([ModelFund])
        case unvollstaendig([ModelFund])
        case abgebrochen([ModelFund])
    }

    /// Basisordner und durchsuchte Ordner. Bewusst unterhalb der Modellliste:
    /// Es ist eine Einstellung, kein Hauptweg — wer nichts ändert, merkt nichts.
    private var ordnerAbschnitt: some View {
        ConsolePanel(title: Loc.t("Wo die Modelle liegen")) {
            VStack(spacing: 0) {
                basisordnerZeile
                ConsoleDivider()
                suchordnerKopf
                ForEach(pfade.suchordner, id: \.self) { ordner in
                    ConsoleDivider()
                    suchordnerZeile(ordner)
                }
            }
        }
    }

    private var basisordnerZeile: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(Loc.t("Basisordner")).font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color(white: 0.9))
                    // Ohne ausdrückliche Wahl steht hier der Ort, den Hugging
                    // Face ohnehin benutzt. Das ist etwas anderes als ein
                    // selbst gewählter Ordner, und nur `gewaehlterBasisordner`
                    // kennt den Unterschied.
                    if pfade.gewaehlterBasisordner == nil {
                        tag(Loc.t("Standardort"), color: Color(white: 0.55))
                    }
                }
                Text(pfade.basisordner.path).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55)).lineLimit(1).truncationMode(.head)
                Text(Loc.t("Hierhin lädt shout. selbst. Vorhandene Modelle bleiben, wo sie sind."))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(Loc.t("Ändern")) { basisordnerWaehlen() }
                .buttonStyle(ConsoleButtonStyle())
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
    }

    private var suchordnerKopf: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Loc.t("Durchsuchte Ordner")).font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color(white: 0.9))
                Text(pfade.suchordner.isEmpty
                     ? Loc.t("Noch keiner. Wer schon Modelle hat, spart sich den Download.")
                     : Loc.t("Modelle aus diesen Ordnern werden mitbenutzt statt neu geladen."))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(Loc.t("Ordner hinzufügen")) { suchordnerHinzufuegen() }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(durchsuchtGerade != nil)
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
    }

    private func suchordnerZeile(_ ordner: URL) -> some View {
        let laeuft = durchsuchtGerade == ordner
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ordner.path).font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(white: 0.85)).lineLimit(1).truncationMode(.head)
                Text(suchordnerHinweis(ordner)).font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if laeuft {
                ProgressView().controlSize(.small).tint(Color.shoutLive)
                Button(Loc.t("Abbrechen")) { laufendeSuche?.setzen() }
                    .buttonStyle(ConsoleButtonStyle())
            } else {
                Button(suchstand[ordner] == nil ? Loc.t("Durchsuchen") : Loc.t("Erneut durchsuchen")) {
                    durchsuchen(ordner)
                }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(durchsuchtGerade != nil)
                // Nimmt NUR den Eintrag aus der Liste. Die Dateien im Ordner
                // gehören jemand anderem und werden nicht angefasst.
                Button(Loc.t("Entfernen")) { suchordnerEntfernen(ordner) }
                    .buttonStyle(ConsoleButtonStyle())
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
    }

    private func suchordnerHinweis(_ ordner: URL) -> String {
        // Kein Stand heißt: noch nie durchsucht. „0 Modelle gefunden" wäre
        // hier gelogen — gesucht wurde ja nicht.
        switch suchstand[ordner] {
        case .none: return Loc.t("Noch nicht durchsucht.")
        case .laeuft: return Loc.t("Wird durchsucht …")
        case .fertig(let f): return Loc.f("%d Modelle gefunden", f.count)
        case .unvollstaendig(let f):
            return Loc.f("%d Modelle gefunden. Der Ordner ist sehr groß — es wurde nicht vollständig durchsucht.", f.count)
        case .abgebrochen(let f):
            return Loc.f("Abgebrochen bei %d Modellen.", f.count)
        }
    }

    private func basisordnerWaehlen() {
        guard let neu = ordnerAuswaehlen() else { return }
        // Ausschließlich über `basisordnerWechseln(zu:)`. Einen Setter für
        // `basisordner` gibt es mit Absicht nicht: Eine Zuweisung machte aus
        // der bloßen Vorgabe eine ausdrückliche Wahl — und damit aus jedem
        // vorhandenen Modell einen Multi-GB-Neu-Download.
        pfade.basisordnerWechseln(zu: neu)
        pfade.sichern(in: .standard)
    }

    private func suchordnerHinzufuegen() {
        guard let neu = ordnerAuswaehlen() else { return }
        // Ortsvergleiche über `ModelStore.vergleichsform`: `/tmp/x` und
        // `/private/tmp/x` sind derselbe Ordner und dürfen nicht zweimal in
        // der Liste landen.
        guard !pfade.suchordner.contains(where: {
                  ModelStore.vergleichsform($0) == ModelStore.vergleichsform(neu) }),
              ModelStore.vergleichsform(neu) != ModelStore.vergleichsform(pfade.basisordner)
        else { return }
        pfade.suchordner.append(neu)
        pfade.sichern(in: .standard)
        durchsuchen(neu)
    }

    /// Nimmt den Ordner aus der Liste. Löscht nichts — die Dateien darin
    /// gehören jemand anderem.
    private func suchordnerEntfernen(_ ordner: URL) {
        pfade.suchordner.removeAll {
            ModelStore.vergleichsform($0) == ModelStore.vergleichsform(ordner) }
        suchstand[ordner] = nil
        pfade.sichern(in: .standard)
    }

    private func ordnerAuswaehlen() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = Loc.t("Wählen")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Durchsuchen läuft abseits des Hauptstrangs — ein großer Ordner darf die
    /// Oberfläche nicht einfrieren. Immer nur einer zur Zeit: So gehört der
    /// „Abbrechen"-Knopf eindeutig zu der Suche, die gerade läuft.
    private func durchsuchen(_ ordner: URL) {
        guard durchsuchtGerade == nil else { return }
        let flagge = AbbruchFlagge()
        durchsuchtGerade = ordner
        laufendeSuche = flagge
        suchstand[ordner] = .laeuft
        Task { @MainActor in
            let ergebnis = await Task.detached(priority: .utility) {
                ModelScan.durchsuchen(ordner, abbruch: { flagge.istGesetzt })
            }.value
            if flagge.istGesetzt {
                suchstand[ordner] = .abgebrochen(ergebnis.funde)
            } else {
                suchstand[ordner] = ergebnis.grenzeErreicht
                    ? .unvollstaendig(ergebnis.funde)
                    : .fertig(ergebnis.funde)
            }
            durchsuchtGerade = nil
            laufendeSuche = nil
        }
    }

    // MARK: - Auswahl

    private func selectASR(_ id: String) {
        guard id != asrID, !model.isSwitchingModel else { return }
        Task { await onSelectASR(id) }
    }

    private func selectFormat(_ id: String) {
        guard id != formatID, !model.isSwitchingModel else { return }
        Task { await onSelectFormat(id) }
    }
}
