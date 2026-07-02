import Foundation

/// Ein von Hugging Face live entdecktes Modell (MLX, 4-bit, instruction-tuned).
struct RemoteModel: Identifiable, Hashable {
    let id: String          // vollständige Repo-ID, z. B. "mlx-community/gemma-4-31b-it-4bit"
    let downloads: Int
    let likes: Int
    let paramsB: Double?    // aus dem Namen geschätzte Parameterzahl (Mrd.)

    /// Kurzname ohne Organisation.
    var shortName: String { id.split(separator: "/").last.map(String.init) ?? id }

    /// Grobe Größe der 4-bit-Gewichte in GB (≈ 0,55 GB je Mrd. Parameter + Overhead).
    var estimatedGB: Double? { paramsB.map { $0 * 0.55 + 1.0 } }

    /// Empfohlener Mindest-RAM (Gewichte + Kontext/Headroom).
    var minRAMGB: Int? { estimatedGB.map { Int(($0 * 1.7).rounded()) } }
}

/// Fragt die Hugging-Face-Hub-API nach aktuellen, beliebten lokalen Textmodellen
/// ab, damit die App immer ein zeitgemäßes Modell empfehlen und anbieten kann.
/// Reine Lese-API, kein Token nötig; die Modelle laufen anschließend lokal (MLX).
enum HuggingFaceModels {

    private struct APIModel: Decodable {
        let id: String
        let downloads: Int?
        let likes: Int?
    }

    /// Begriffe, die auf nicht als Formatter nutzbare Repos hindeuten.
    private static let excluded = [
        "diffusion", "embed", "whisper", "-tts", "-stt", "flux", "stable-",
        "reranker", "-bge", "clip", "vae", "audio", "sana", "wan2", "-vl-", "vision",
    ]

    /// Holt beliebte MLX-Instruct-4-bit-Textmodelle, nach Downloads sortiert.
    static func fetchFormatting(limit: Int = 24) async throws -> [RemoteModel] {
        var comps = URLComponents(string: "https://huggingface.co/api/models")!
        comps.queryItems = [
            .init(name: "author", value: "mlx-community"),
            .init(name: "search", value: "it-4bit"),
            .init(name: "sort", value: "downloads"),
            .init(name: "direction", value: "-1"),
            .init(name: "limit", value: "\(limit * 4)"),
        ]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let raw = try JSONDecoder().decode([APIModel].self, from: data)

        var seen = Set<String>()
        var out: [RemoteModel] = []
        for m in raw {
            let lower = m.id.lowercased()
            guard lower.contains("it-4bit") else { continue }
            guard !excluded.contains(where: { lower.contains($0) }) else { continue }
            guard seen.insert(lower).inserted else { continue }
            out.append(RemoteModel(id: m.id, downloads: m.downloads ?? 0,
                                   likes: m.likes ?? 0, paramsB: parseParams(from: lower)))
            if out.count >= limit { break }
        }
        return out
    }

    /// Schätzt die Parameterzahl (Mrd.) aus dem Repo-Namen. Bei MoE-Namen wie
    /// „26b-a4b" zählt die größere Zahl (Gesamtgewichte bestimmen den Speicher).
    private static func parseParams(from lower: String) -> Double? {
        var best: Double?
        let scalars = Array(lower)
        var i = 0
        while i < scalars.count {
            if scalars[i].isNumber {
                var j = i
                while j < scalars.count, scalars[j].isNumber || scalars[j] == "." { j += 1 }
                // „…b" gefolgt von einem Buchstaben ist keine Größe, sondern ein
                // Suffix wie „4bit" → nur echte Parameterzahlen zählen.
                if j < scalars.count, scalars[j] == "b",
                   j + 1 >= scalars.count || !scalars[j + 1].isLetter {
                    if let v = Double(String(scalars[i..<j])), v >= 0.5, v <= 500 {
                        best = max(best ?? 0, v)
                    }
                }
                i = j
            } else {
                i += 1
            }
        }
        return best
    }
}
