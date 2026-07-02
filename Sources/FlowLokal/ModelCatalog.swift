import Foundation

/// Hardware-Infos für die Modell-Empfehlung.
enum Hardware {
    static var physicalMemoryGB: Int {
        Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
    }
    static var chip: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let name = String(cString: buffer)
        return name.isEmpty ? "Apple Silicon" : name
    }
}

/// Auswählbare lokale Modelle für Transkription und Formatierung.
enum ModelCatalog {
    struct Option: Identifiable, Hashable {
        let id: String       // Modell-Identifier (WhisperKit- bzw. MLX-ID)
        let name: String
        let note: String
        let minRAMGB: Int
    }

    static let defaultASR = "large-v3-v20240930_turbo"
    static let defaultFormatting = "mlx-community/gemma-4-e4b-it-4bit"

    static let asr: [Option] = [
        .init(id: "large-v3-v20240930_626MB", name: "Whisper Turbo (kompakt)", note: "~600 MB · schnell", minRAMGB: 8),
        .init(id: "large-v3-v20240930_turbo", name: "Whisper Turbo", note: "~1,5 GB · schnell & sehr genau", minRAMGB: 16),
        .init(id: "large-v3", name: "Whisper Large v3", note: "~3 GB · maximale Genauigkeit, langsamer", minRAMGB: 16),
    ]

    static let formatting: [Option] = [
        .init(id: "mlx-community/gemma-4-e2b-it-4bit", name: "Gemma 4 · E2B", note: "~2 GB · sehr schnell", minRAMGB: 8),
        .init(id: "mlx-community/gemma-4-e4b-it-4bit", name: "Gemma 4 · E4B", note: "~3 GB · guter Standard", minRAMGB: 16),
        .init(id: "mlx-community/gemma-2-9b-it-4bit", name: "Gemma 2 · 9B", note: "~5,5 GB · beste Formatierung", minRAMGB: 24),
    ]

    static func recommendedASR(ramGB: Int) -> Option { ramGB >= 16 ? asr[1] : asr[0] }
    static func recommendedFormatting(ramGB: Int) -> Option {
        if ramGB >= 24 { return formatting[2] }
        if ramGB >= 16 { return formatting[1] }
        return formatting[0]
    }

    static func asrName(_ id: String) -> String { asr.first { $0.id == id }?.name ?? id }
    static func formattingName(_ id: String) -> String { formatting.first { $0.id == id }?.name ?? id }
}
