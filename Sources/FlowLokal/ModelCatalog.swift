import Foundation

/// Hardware-Infos für die Modell-Empfehlung.
enum Hardware {
    static var physicalMemoryGB: Int {
        Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
    }

    static var chip: String {
        #if os(iOS)
        // iOS kennt kein machdep.cpu.brand_string → Geräte-Identifier (z. B. "iPhone17,1").
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.compactMap { element -> String? in
            guard let value = element.value as? Int8, value != 0 else { return nil }
            return String(UnicodeScalar(UInt8(value)))
        }.joined()
        return identifier.isEmpty ? "iPhone" : identifier
        #else
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let name = String(cString: buffer)
        return name.isEmpty ? "Apple Silicon" : name
        #endif
    }
}

/// Auswählbare lokale Modelle für Transkription und Formatierung.
/// Die Kataloge sind plattformspezifisch: iPhones haben 4–8 GB RAM und harte
/// Jetsam-Limits — dort gelten kleinere Modelle und konservativere Empfehlungen.
enum ModelCatalog {
    struct Option: Identifiable, Hashable {
        let id: String       // Modell-Identifier (WhisperKit- bzw. MLX-ID)
        let name: String
        let note: String
        let minRAMGB: Int
    }

    #if os(iOS)

    // Aufs iPhone gehört TEMPO: Diktieren muss schneller sein als Tippen, sonst
    // ist es sinnlos. Empfohlen werden darum die schnellen Modelle; die großen
    // bleiben als „genauer, aber deutlich langsamer" wählbar.
    static let defaultASR = "small"
    static let defaultFormatting = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    static let asr: [Option] = [
        .init(id: "base", name: "Whisper Base", note: "~150 MB · am schnellsten, einfache Sätze", minRAMGB: 3),
        .init(id: "small", name: "Whisper Small", note: "~500 MB · schnell & solide — guter Alltag", minRAMGB: 4),
        .init(id: "large-v3-v20240930_626MB", name: "Whisper Turbo (kompakt)", note: "~600 MB · sehr genau, aber deutlich langsamer", minRAMGB: 6),
        .init(id: "large-v3-v20240930_turbo", name: "Whisper Turbo", note: "~1,5 GB · maximale Genauigkeit, langsam am iPhone", minRAMGB: 8),
    ]

    static let formatting: [Option] = [
        .init(id: "mlx-community/Llama-3.2-1B-Instruct-4bit", name: "Llama 3.2 · 1B", note: "~0,7 GB · am schnellsten", minRAMGB: 4),
        .init(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", name: "Qwen 2.5 · 1.5B", note: "~1 GB · besser im Deutschen, langsamer", minRAMGB: 6),
        .init(id: "mlx-community/gemma-4-e2b-it-4bit", name: "Gemma 4 · E2B", note: "~2 GB · beste Qualität, am langsamsten", minRAMGB: 8),
    ]

    static func recommendedASR(ramGB: Int) -> Option {
        ramGB >= 4 ? asr[1] : asr[0]      // Small: der beste Tempo/Qualität-Deal am iPhone
    }
    static func recommendedFormatting(ramGB: Int) -> Option {
        formatting[0]                      // Llama 1B: Aufbereitung darf nicht bremsen
    }

    #else

    static let defaultASR = "large-v3-v20240930_turbo"
    static let defaultFormatting = "mlx-community/gemma-4-e4b-it-4bit"

    static let asr: [Option] = [
        .init(id: "large-v3-v20240930_626MB", name: "Whisper Turbo (kompakt)", note: "~600 MB · schnell", minRAMGB: 8),
        .init(id: "large-v3-v20240930_turbo", name: "Whisper Turbo", note: "~1,5 GB · schnell & sehr genau", minRAMGB: 16),
        .init(id: "large-v3", name: "Whisper Large v3", note: "~3 GB · maximale Genauigkeit, langsamer", minRAMGB: 16),
    ]

    static let formatting: [Option] = [
        .init(id: "mlx-community/gemma-4-e2b-it-4bit", name: "Gemma 4 · E2B", note: "~2 GB · sehr schnell", minRAMGB: 8),
        .init(id: "mlx-community/gemma-4-e4b-it-4bit", name: "Gemma 4 · E4B", note: "~5 GB · guter Standard", minRAMGB: 16),
        .init(id: "mlx-community/gemma-2-9b-it-4bit", name: "Gemma 2 · 9B", note: "~5,5 GB · mehr Qualität", minRAMGB: 24),
        .init(id: "mlx-community/gemma-4-12B-it-4bit", name: "Gemma 4 · 12B", note: "~8 GB · sehr gute Aufbereitung", minRAMGB: 32),
        .init(id: "mlx-community/gemma-4-31b-it-4bit", name: "Gemma 4 · 31B", note: "~18 GB · High-End, beste Qualität", minRAMGB: 48),
    ]

    static func recommendedASR(ramGB: Int) -> Option { ramGB >= 16 ? asr[1] : asr[0] }
    static func recommendedFormatting(ramGB: Int) -> Option {
        if ramGB >= 48 { return formatting[4] }   // 31B High-End
        if ramGB >= 32 { return formatting[3] }   // 12B
        if ramGB >= 24 { return formatting[2] }   // 9B
        if ramGB >= 16 { return formatting[1] }   // E4B
        return formatting[0]                       // E2B
    }

    #endif

    static func asrName(_ id: String) -> String { asr.first { $0.id == id }?.name ?? id }
    static func formattingName(_ id: String) -> String { formatting.first { $0.id == id }?.name ?? id }
}
