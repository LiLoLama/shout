import SwiftUI

/// Statistiken + „Dein Sprachprofil" (KI, lokal via Gemma).
struct StatisticsView: View {
    @ObservedObject var stats: StatsStore
    @ObservedObject var history: DictationHistory
    @ObservedObject var dictionary: PersonalDictionary
    /// Erzeugt das Sprachprofil aus einem Text-Sample (lokales LLM).
    let generateProfile: (String) async -> String?

    @AppStorage("voiceProfile") private var voiceProfile = ""
    @State private var generating = false

    private let unlockAt = 5   // Diktate bis „Dein Sprachprofil"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Statistiken").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    statCard(value: stats.data.totalWords.formatted(), label: "Wörter gesamt")
                    statCard(value: "\(stats.averageWPM)", label: "Ø Wörter/Minute")
                    statCard(value: "\(stats.data.totalDictations)", label: "Diktate")
                    statCard(value: "\(dictionary.contents.corrections.count)", label: "Korrekturen gelernt")
                }

                ConsolePanel(title: "Streak") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            metric("\(stats.currentStreak)", "Tage aktuell")
                            metric("\(stats.longestStreak)", "längster")
                        }
                        Heatmap(stats: stats)
                    }
                    .padding(16)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    infoCard(title: "Meistgenutztes Wort", value: mostUsedWord ?? "—")
                    infoCard(title: "Aktivste Zeit", value: peakTime ?? "—")
                }

                voiceSection
            }
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Karten

    private func statCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 28, weight: .semibold)).foregroundStyle(Color(white: 0.95))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.165)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07)))
    }

    private func infoCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).tracking(0.4).foregroundStyle(Color(white: 0.5))
            Text(value).font(.system(size: 17, weight: .medium)).foregroundStyle(Color(white: 0.92)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.165)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07)))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.shoutLive)
            Text(label).font(.system(size: 12)).foregroundStyle(Color(white: 0.6))
        }
    }

    // MARK: - Sprachprofil

    @ViewBuilder private var voiceSection: some View {
        ConsolePanel(title: "Dein Sprachprofil") {
            VStack(alignment: .leading, spacing: 12) {
                if stats.data.totalDictations < unlockAt {
                    let remaining = unlockAt - stats.data.totalDictations
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill").foregroundStyle(Color(white: 0.5))
                        Text("Wird nach \(remaining) weiteren Diktaten freigeschaltet.")
                            .font(.system(size: 13)).foregroundStyle(Color(white: 0.6))
                    }
                } else {
                    if voiceProfile.isEmpty {
                        Text("shout. kann aus deinen Diktaten ein kurzes Profil deines Sprachstils erstellen — vollständig lokal.")
                            .font(.system(size: 13)).foregroundStyle(Color(white: 0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(voiceProfile)
                            .font(.system(size: 14)).foregroundStyle(Color(white: 0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        Task { await makeProfile() }
                    } label: {
                        HStack(spacing: 6) {
                            if generating { ProgressView().controlSize(.small) }
                            Text(generating ? "Erstelle …" : (voiceProfile.isEmpty ? "Profil erstellen" : "Aktualisieren"))
                        }
                    }
                    .buttonStyle(ConsoleButtonStyle())
                    .disabled(generating)
                }
            }
            .padding(16)
        }
    }

    private func makeProfile() async {
        generating = true
        defer { generating = false }
        let sample = history.entries.prefix(25).map(\.text).joined(separator: "\n").prefix(2000)
        if let profile = await generateProfile(String(sample)), !profile.isEmpty {
            voiceProfile = profile
        }
    }

    // MARK: - Ableitungen aus dem Verlauf

    private var mostUsedWord: String? {
        var counts: [String: Int] = [:]
        for entry in history.entries {
            for raw in entry.text.lowercased().split(whereSeparator: { !$0.isLetter }) {
                let w = String(raw)
                guard w.count >= 4, !Self.stopwords.contains(w) else { continue }
                counts[w, default: 0] += 1
            }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    private var peakTime: String? {
        guard !history.entries.isEmpty else { return nil }
        let cal = Calendar.current
        var buckets: [Int: Int] = [:]
        for e in history.entries { buckets[cal.component(.hour, from: e.date), default: 0] += 1 }
        guard let hour = buckets.max(by: { $0.value < $1.value })?.key else { return nil }
        switch hour {
        case 5..<11: return "Vormittags"
        case 11..<14: return "Mittags"
        case 14..<18: return "Nachmittags"
        case 18..<23: return "Abends"
        default: return "Nachts"
        }
    }

    private static let stopwords: Set<String> = [
        "und", "oder", "aber", "dass", "eine", "einen", "einem", "einer", "nicht", "auch",
        "dann", "wenn", "also", "dieser", "diese", "dieses", "noch", "schon", "sein", "sind",
        "haben", "hier", "dort", "mein", "dein", "kann", "können", "wird", "werden", "mich",
        "dich", "sich", "wir", "ihr", "ihre", "über", "unter", "beim", "vom", "zum", "zur",
    ]
}

/// Kleiner Aktivitäts-Kalender (letzte 8 Wochen).
private struct Heatmap: View {
    @ObservedObject var stats: StatsStore

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<56).map { cal.date(byAdding: .day, value: -55 + $0, to: today)! }
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        return HStack(spacing: 3) {
            ForEach(weeks.indices, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(weeks[w], id: \.self) { day in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(stats.isActive(day) ? Color.shoutLive : Color(white: 0.18))
                            .frame(width: 13, height: 13)
                    }
                }
            }
        }
    }
}
