import SwiftUI

/// „Modelle" — erkennt die Hardware, empfiehlt das passende lokale Modell für
/// Transkription und Aufbereitung und lässt frei umschalten. Beim Umschalten
/// wird das Modell (falls nötig heruntergeladen und) neu in den Prozess geladen.
struct ModelsView: View {
    @ObservedObject var model: DashboardModel
    /// Wechselt das Transkriptions- bzw. Formatierungs-Modell und lädt neu.
    let onSelectASR: (String) async -> Void
    let onSelectFormat: (String) async -> Void

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
                        ForEach(ModelCatalog.asr.indices, id: \.self) { i in
                            let o = ModelCatalog.asr[i]
                            modelRow(o, selected: asrID == o.id, recommended: recASR.id == o.id,
                                     loading: loadingASR == o.id,
                                     progress: loadingASR == o.id ? model.asrProgress : nil) { selectASR(o.id) }
                            if i < ModelCatalog.asr.count - 1 { ConsoleDivider() }
                        }
                    }
                }

                ConsolePanel(title: Loc.t("Aufbereitung & Formatierung (KI-Textmodell)")) {
                    VStack(spacing: 0) {
                        ForEach(ModelCatalog.formatting.indices, id: \.self) { i in
                            let o = ModelCatalog.formatting[i]
                            modelRow(o, selected: formatID == o.id, recommended: recFormat.id == o.id,
                                     loading: loadingFormat == o.id,
                                     progress: loadingFormat == o.id ? model.formatProgress : nil) { selectFormat(o.id) }
                            if i < ModelCatalog.formatting.count - 1 { ConsoleDivider() }
                        }
                    }
                }

                remotePanel

                Text(Loc.t("Modelle werden beim ersten Auswählen einmalig von Hugging Face geladen und danach lokal gespeichert. Alles läuft anschließend komplett offline auf deinem Mac."))
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
                                  loading: loadingFormat == m.id,
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
                           loading: Bool, progress: Double?, action: @escaping () -> Void) -> some View {
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
                    }
                    Text(remoteSubtitle(m)).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
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
                          loading: Bool, progress: Double?, action: @escaping () -> Void) -> some View {
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
                    }
                    Text(Loc.t(o.note)).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
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

    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
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
