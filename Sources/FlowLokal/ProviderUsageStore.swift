import Foundation
import Combine

struct TokenCount: Codable, Equatable, Sendable {
    var prompt = 0
    var completion = 0

    static func + (a: TokenCount, b: TokenCount) -> TokenCount {
        TokenCount(prompt: a.prompt + b.prompt, completion: a.completion + b.completion)
    }
}

/// Verbrauch eines Monats, aufgeschlüsselt nach „anbieter · modell".
struct ProviderMonth: Codable, Equatable, Sendable {
    var tokens: [String: TokenCount] = [:]
    var seconds: [String: Double] = [:]

    var totalTokens: Int {
        tokens.values.reduce(0) { $0 + $1.prompt + $1.completion }
    }
    var totalSeconds: Double { seconds.values.reduce(0, +) }
    var isEmpty: Bool { tokens.isEmpty && seconds.isEmpty }
}

/// Zählt, was bei Anbietern verbraucht wurde — **gemessen, nicht geschätzt**:
/// Jede Antwort liefert die echten Token-Zahlen mit, und für Transkription
/// zählen wir die verschickten Sekunden. Dafür braucht es kein Netz.
///
/// Eigene Datei und **nicht** Teil von `StatsStore`, mit Absicht:
///
/// 1. Ausgaben sind gerätebezogen. Sie über die Sicherungsdatei auf ein zweites
///    Gerät zu tragen und dort zu addieren würde eine Zahl ergeben, die nichts
///    beschreibt.
/// 2. `BackupBundle` bleibt damit unverändert bei Version 1 — kein neues Feld,
///    kein Migrationspfad, ältere Sicherungen lesen sich wie bisher.
/// 3. Die Engines sind Actors und können hier ohne Umweg melden, statt an
///    `StatsStore` gekoppelt zu werden.
///
/// Monate werden nebeneinander behalten, nicht überschrieben: Ein Monatswechsel
/// setzt die Anzeige zurück, ohne die Vorgeschichte zu verlieren.
@MainActor
final class ProviderUsageStore: ObservableObject {

    static let shared = ProviderUsageStore()

    @Published private(set) var months: [String: ProviderMonth] = [:]
    /// Preistabelle — mitgeliefert, bis sie einmal aktualisiert wurde.
    @Published private(set) var prices: PriceTable = .bundled

    private let usageURL: URL
    private let priceURL: URL

    init(directory: URL = StoreIO.directory()) {
        usageURL = directory.appendingPathComponent("anbieter-verbrauch.json")
        priceURL = directory.appendingPathComponent("anbieter-preise.json")
        if let geladen = StoreIO.load([String: ProviderMonth].self, from: usageURL) {
            months = geladen
        }
        // Eine gespeicherte Tabelle gewinnt nur, wenn sie NEUER ist als die
        // mitgelieferte. Sonst würde ein Programm-Update mit frischen Preisen von
        // einem alten Abruf überstimmt.
        if let geladen = StoreIO.load(PriceTable.self, from: priceURL),
           geladen.updated > PriceTable.bundled.updated {
            prices = geladen
        }
    }

    // MARK: - Aufzeichnen

    static func key(provider: String, model: String) -> String { "\(provider) · \(model)" }

    static func monthKey(_ date: Date) -> String { monthFormatter.string(from: date) }

    func record(tokens: TokenUsage, provider: String, model: String, date: Date = Date()) {
        guard tokens.total > 0 else { return }
        let monat = Self.monthKey(date)
        let eintrag = Self.key(provider: provider, model: model)
        var m = months[monat] ?? ProviderMonth()
        m.tokens[eintrag] = (m.tokens[eintrag] ?? TokenCount())
            + TokenCount(prompt: tokens.prompt, completion: tokens.completion)
        months[monat] = m
        save()
    }

    func record(seconds: Double, provider: String, model: String, date: Date = Date()) {
        guard seconds > 0 else { return }
        let monat = Self.monthKey(date)
        let eintrag = Self.key(provider: provider, model: model)
        var m = months[monat] ?? ProviderMonth()
        m.seconds[eintrag] = (m.seconds[eintrag] ?? 0) + seconds
        months[monat] = m
        save()
    }

    // MARK: - Abfragen

    func month(_ date: Date = Date()) -> ProviderMonth? { months[Self.monthKey(date)] }

    /// Kosten eines Monats. `nil` bei den Anteilen, deren Preis unbekannt ist —
    /// deshalb kommt zusätzlich zurück, ob etwas ungerechnet blieb.
    func cost(for date: Date = Date()) -> (usd: Double, unknown: Bool) {
        guard let m = month(date) else { return (0, false) }
        var summe = 0.0
        var unbekannt = false

        for (eintrag, tokens) in m.tokens {
            let modell = Self.model(from: eintrag)
            if let teil = ProviderCosts.cost(tokens: tokens, price: prices.price(forText: modell)) {
                summe += teil
            } else {
                unbekannt = true
            }
        }
        for (eintrag, sekunden) in m.seconds {
            let modell = Self.model(from: eintrag)
            if let teil = ProviderCosts.cost(seconds: sekunden,
                                             price: prices.price(forAudio: modell)) {
                summe += teil
            } else {
                unbekannt = true
            }
        }
        return (summe, unbekannt)
    }

    /// Modell-ID aus einem Eintragsschlüssel „Anbieter · Modell".
    static func model(from key: String) -> String {
        guard let bereich = key.range(of: " · ") else { return key }
        return String(key[bereich.upperBound...])
    }

    // MARK: - Preise

    func replacePrices(_ neu: PriceTable) {
        prices = neu
        StoreIO.save(neu, to: priceURL)
    }

    // MARK: - Persistenz

    private func save() { StoreIO.save(months, to: usageURL) }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
