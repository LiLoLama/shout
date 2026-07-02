import SwiftUI

/// „Modelle" — erkennt die Hardware, empfiehlt das passende lokale Modell für
/// Transkription und Aufbereitung und lässt frei umschalten. Beim Umschalten
/// wird das Modell (falls nötig heruntergeladen und) neu in den Prozess geladen.
struct ModelsView: View {
    /// Wechselt das Transkriptions- bzw. Formatierungs-Modell und lädt neu.
    let onSelectASR: (String) async -> Void
    let onSelectFormat: (String) async -> Void

    @State private var asrID = UserDefaults.standard.string(forKey: "asrModel") ?? ModelCatalog.defaultASR
    @State private var formatID = UserDefaults.standard.string(forKey: "formatModel") ?? ModelCatalog.defaultFormatting
    @State private var loadingASR: String?      // gerade ladende Modell-ID (ASR)
    @State private var loadingFormat: String?   // gerade ladende Modell-ID (Format)

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
                Text("Modelle").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))

                hardwarePanel

                ConsolePanel(title: "Transkription (Sprache → Text)") {
                    VStack(spacing: 0) {
                        ForEach(ModelCatalog.asr.indices, id: \.self) { i in
                            let o = ModelCatalog.asr[i]
                            modelRow(o, selected: asrID == o.id, recommended: recASR.id == o.id,
                                     loading: loadingASR == o.id) { selectASR(o.id) }
                            if i < ModelCatalog.asr.count - 1 { ConsoleDivider() }
                        }
                    }
                }

                ConsolePanel(title: "Aufbereitung & Formatierung (KI-Textmodell)") {
                    VStack(spacing: 0) {
                        ForEach(ModelCatalog.formatting.indices, id: \.self) { i in
                            let o = ModelCatalog.formatting[i]
                            modelRow(o, selected: formatID == o.id, recommended: recFormat.id == o.id,
                                     loading: loadingFormat == o.id) { selectFormat(o.id) }
                            if i < ModelCatalog.formatting.count - 1 { ConsoleDivider() }
                        }
                    }
                }

                remotePanel

                Text("Modelle werden beim ersten Auswählen einmalig von Hugging Face geladen und danach lokal gespeichert. Alles läuft anschließend komplett offline auf deinem Mac.")
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

    /// Beliebtestes live entdecktes Modell, das auf diesen Mac passt.
    private var remoteRecommended: RemoteModel? {
        remote.first { ($0.minRAMGB ?? 0) <= ram }
    }

    private var remotePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("AKTUELLE MODELLE · HUGGING FACE")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Color(white: 0.45)).padding(.leading, 4)
                Spacer()
                Button(action: { Task { await refreshRemote() } }) {
                    HStack(spacing: 5) {
                        if remoteLoading { ProgressView().controlSize(.small).tint(Color.shoutLive) }
                        else { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)) }
                        Text(remoteLoading ? "Lädt …" : "Aktualisieren")
                    }
                }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(remoteLoading)
            }

            VStack(spacing: 0) {
                if let remoteError {
                    infoLine("Keine Verbindung zu Hugging Face. \(remoteError)")
                } else if remote.isEmpty && remoteLoading {
                    infoLine("Suche aktuelle Modelle …")
                } else if remote.isEmpty {
                    infoLine("Keine Modelle gefunden.")
                } else {
                    ForEach(remote.indices, id: \.self) { i in
                        let m = remote[i]
                        remoteRow(m, selected: formatID == m.id,
                                  recommended: remoteRecommended?.id == m.id,
                                  loading: loadingFormat == m.id) { selectFormat(m.id) }
                        if i < remote.count - 1 { ConsoleDivider() }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.165)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.07)))

            Text("Live aus der Hugging-Face-Bibliothek „mlx-community“ (Instruct-Modelle, 4-bit). Größe geschätzt — für die Aufbereitung; die Transkription bleibt bei den geprüften Whisper-Modellen oben.")
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
                           loading: Bool, action: @escaping () -> Void) -> some View {
        let tooBig = (m.minRAMGB ?? 0) > ram
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16)).foregroundStyle(selected ? Color.shoutLive : Color(white: 0.4))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(m.shortName).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(white: 0.9))
                            .lineLimit(1).truncationMode(.middle)
                        if recommended { tag("Aktuell beliebt", color: .shoutLive) }
                        if tooBig { tag("Viel RAM nötig", color: Color(white: 0.55)) }
                    }
                    Text(remoteSubtitle(m)).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                }
                Spacer(minLength: 8)
                if loading { ProgressView().controlSize(.small).tint(Color.shoutLive) }
            }
            .padding(.horizontal, 15).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loadingASR != nil || loadingFormat != nil)
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
                        Text("\(ram) GB Arbeitsspeicher").font(.system(size: 12)).foregroundStyle(Color(white: 0.58))
                    }
                    Spacer()
                }
                ConsoleDivider().padding(.horizontal, -15)
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Color.shoutLive)
                    Text("Empfohlen für deinen Mac: **\(recASR.name)** zum Transkribieren, **\(recFormat.name)** zum Aufbereiten.")
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
                          loading: Bool, action: @escaping () -> Void) -> some View {
        let tooBig = ram < o.minRAMGB
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16)).foregroundStyle(selected ? Color.shoutLive : Color(white: 0.4))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(o.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Color(white: 0.9))
                        if recommended { tag("Empfohlen", color: .shoutLive) }
                        if tooBig { tag("Viel RAM nötig", color: Color(white: 0.55)) }
                    }
                    Text(o.note).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                }
                Spacer(minLength: 8)
                if loading {
                    ProgressView().controlSize(.small).tint(Color.shoutLive)
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loadingASR != nil || loadingFormat != nil)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    // MARK: - Auswahl

    private func selectASR(_ id: String) {
        guard id != asrID, loadingASR == nil, loadingFormat == nil else { return }
        asrID = id
        loadingASR = id
        Task { await onSelectASR(id); loadingASR = nil }
    }

    private func selectFormat(_ id: String) {
        guard id != formatID, loadingASR == nil, loadingFormat == nil else { return }
        formatID = id
        loadingFormat = id
        Task { await onSelectFormat(id); loadingFormat = nil }
    }
}
