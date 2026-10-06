import Foundation
import CryptoKit

/// Frühere Stände einer Notiz — lokal im App-Support, nicht im Notizordner
/// (sonst bläht sich der Sync auf). Ein Ordner je Dateiname (SHA-1, ohne
/// Groß-/Kleinschreibung), darin `<ISO-Zeit>.md` und `name.txt`.
@MainActor
final class NoteVersions {

    struct Version: Identifiable, Equatable {
        let url: URL
        let date: Date
        var id: URL { url }

        func text() -> String? { try? String(contentsOf: url, encoding: .utf8) }

        /// Für die Liste: die erste Zeile mit Inhalt.
        var firstLine: String {
            (text() ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
        }
    }

    static let maxCount = 30
    static let minInterval: TimeInterval = 10 * 60
    static let orphanAge: TimeInterval = 30 * 24 * 60 * 60
    private static let nameFile = "name.txt"
    private static let orphanFile = "verwaist.txt"

    nonisolated static var defaultRoot: URL {
        StoreIO.directory().appendingPathComponent("Notizversionen", isDirectory: true)
    }

    let root: URL
    private let fileManager: FileManager
    private let now: () -> Date

    init(root: URL = NoteVersions.defaultRoot, fileManager: FileManager = .default,
         now: @escaping () -> Date = Date.init) {
        self.root = root
        self.fileManager = fileManager
        self.now = now
    }

    func folder(for fileName: String) -> URL {
        let normalized = fileName.precomposedStringWithCanonicalMapping.lowercased()
        let hash = Insecure.SHA1.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash, isDirectory: true)
    }

    /// Sichert einen Stand — außer er ist leer oder gleicht dem neuesten.
    @discardableResult
    func save(_ text: String, for fileName: String) -> URL? {
        guard !fileName.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let ordner = folder(for: fileName)
        if versions(in: ordner).first?.text() == text { return nil }
        do {
            try fileManager.createDirectory(at: ordner, withIntermediateDirectories: true)
            try Data(fileName.utf8).write(to: ordner.appendingPathComponent(Self.nameFile), options: .atomic)
            var stempel = Self.stamp(now())
            // Wenn die Uhr zurückgeht: neuer Stand kriegt den Stempel des neuesten + nächste Ordnung
            if let neuester = versions(in: ordner).first, now() < neuester.date {
                stempel = Self.stamp(neuester.date)
            }
            let maxOrd = maxOrdinalForStamp(stempel, in: ordner)
            let name = maxOrd == 0 ? stempel + ".md" : "\(stempel)-\(maxOrd + 1).md"
            let url = ordner.appendingPathComponent(name)
            try Data(text.utf8).write(to: url, options: .atomic)
            prune(ordner)
            return url
        } catch {
            NSLog("shout: Notizversion nicht gesichert: \(error)")
            return nil
        }
    }

    /// Beim Bearbeiten: höchstens alle zehn Minuten ein Stand.
    @discardableResult
    func saveIfDue(_ text: String, for fileName: String) -> URL? {
        if let neueste = list(for: fileName).first, now().timeIntervalSince(neueste.date) < Self.minInterval {
            return nil
        }
        return save(text, for: fileName)
    }

    func list(for fileName: String) -> [Version] { versions(in: folder(for: fileName)) }

    /// Umbenennen nimmt die Stände mit. Hat der neue Name schon Stände (eine
    /// frühere Notiz gleichen Namens), werden beide zusammengelegt.
    func moveVersions(from old: String, to new: String) {
        let alt = folder(for: old)
        let neu = folder(for: new)
        guard alt != neu, fileManager.fileExists(atPath: alt.path) else { return }
        if !fileManager.fileExists(atPath: neu.path) {
            do { try fileManager.moveItem(at: alt, to: neu) } catch {
                NSLog("shout: Notizversionen nicht umbenannt: \(error)")
                return
            }
        } else {
            for stand in versions(in: alt) {
                let standBase = stand.url.deletingPathExtension().lastPathComponent
                if let date = Self.date(fromFileName: standBase) {
                    let stempel = Self.stamp(date)
                    let maxOrd = maxOrdinalForStamp(stempel, in: neu)
                    let zielName = maxOrd == 0 ? stempel + ".md" : "\(stempel)-\(maxOrd + 1).md"
                    let ziel = neu.appendingPathComponent(zielName)
                    try? fileManager.moveItem(at: stand.url, to: ziel)
                }
            }
            // Nur löschen wenn keine .md Dateien mehr im alten Ordner sind
            let altUrls = (try? fileManager.contentsOfDirectory(at: alt, includingPropertiesForKeys: nil)) ?? []
            if !altUrls.contains(where: { $0.pathExtension == "md" }) {
                try? fileManager.removeItem(at: alt)
            }
            prune(neu)
        }
        try? fileManager.removeItem(at: neu.appendingPathComponent(Self.orphanFile))
        try? Data(new.utf8).write(to: neu.appendingPathComponent(Self.nameFile), options: .atomic)
    }

    /// Beim Start: Stände ohne zugehörige Datei fallen nach 30 Tagen weg.
    /// `fileNames` sind die Dateinamen im Notizordner.
    func cleanUp(keeping fileNames: Set<String>) {
        var hashesToKeep = Set<String>()
        for fileName in fileNames {
            hashesToKeep.insert(folder(for: fileName).lastPathComponent)
            // iCloud Placeholder: ".X.md.icloud" → auch X.md behalten
            if fileName.hasPrefix(".") && fileName.hasSuffix(".icloud") {
                if let target = NoteFile.placeholderTarget(fileName) {
                    hashesToKeep.insert(folder(for: target).lastPathComponent)
                }
            }
        }

        let inhalt = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for ordner in inhalt {
            guard (try? ordner.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let ordnerHash = ordner.lastPathComponent
            let marke = ordner.appendingPathComponent(Self.orphanFile)

            // Hauptprüfung: Ordner-Hash stimmt mit einem bekannten Dateinamen überein
            if hashesToKeep.contains(ordnerHash) {
                try? fileManager.removeItem(at: marke)
                continue
            }

            // Aufräumen wenn zu lange verwaist
            if let text = try? String(contentsOf: marke, encoding: .utf8),
               let seit = ISO8601DateFormatter().date(from: text) {
                if now().timeIntervalSince(seit) > Self.orphanAge { try? fileManager.removeItem(at: ordner) }
            } else {
                try? Data(ISO8601DateFormatter().string(from: now()).utf8).write(to: marke, options: .atomic)
            }
        }
    }

    // MARK: - Intern

    private func versions(in ordner: URL) -> [Version] {
        let urls = (try? fileManager.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "md" }
            .compactMap { url in
                Self.date(fromFileName: url.deletingPathExtension().lastPathComponent).map { Version(url: url, date: $0) }
            }
            .sorted {
                if $0.date != $1.date {
                    return $0.date > $1.date
                }
                let ord0 = Self.ordinal(fromFileName: $0.url.deletingPathExtension().lastPathComponent)
                let ord1 = Self.ordinal(fromFileName: $1.url.deletingPathExtension().lastPathComponent)
                return Self.ordinalGreater(ord0, ord1)
            }
    }

    private func prune(_ ordner: URL) {
        for alt in versions(in: ordner).dropFirst(Self.maxCount) {
            try? fileManager.removeItem(at: alt.url)
        }
    }

    private func maxOrdinalForStamp(_ stempel: String, in ordner: URL) -> Int {
        let urls = (try? fileManager.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)) ?? []
        var maxOrd = 0
        for url in urls where url.pathExtension == "md" {
            let baseName = url.deletingPathExtension().lastPathComponent
            if baseName.hasPrefix(stempel) {
                let suffix = String(baseName.dropFirst(stempel.count))
                if suffix.isEmpty {
                    maxOrd = max(maxOrd, 1)
                } else if suffix.hasPrefix("-") {
                    let numStr = String(suffix.dropFirst())
                    if let num = Int(numStr) {
                        maxOrd = max(maxOrd, num)
                    }
                }
            }
        }
        return maxOrd
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return f
    }()

    static func stamp(_ date: Date) -> String { dateFormatter.string(from: date) }

    /// „2026-10-05T14-32-10Z" oder „…Z-2".
    static func date(fromFileName name: String) -> Date? {
        guard let z = name.firstIndex(of: "Z") else { return nil }
        return dateFormatter.date(from: String(name[...z]))
    }

    /// Ordinalzähler aus der Dateiendung für Stände in der gleichen Sekunde.
    /// „2026-10-05T14-32-10Z" → [], „…Z-2" → [2], „…Z-10" → [10], „…Z-2-2" → [2, 2].
    static func ordinal(fromFileName name: String) -> [Int] {
        guard let z = name.firstIndex(of: "Z") else { return [] }
        let suffix = String(name[name.index(after: z)...])
        guard !suffix.isEmpty else { return [] }
        return suffix.split(separator: "-").compactMap { Int($0) }
    }

    /// Vergleicht zwei Ordinalzähler lexikographisch: true wenn lhs > rhs.
    static func ordinalGreater(_ lhs: [Int], _ rhs: [Int]) -> Bool {
        for i in 0..<min(lhs.count, rhs.count) {
            if lhs[i] != rhs[i] {
                return lhs[i] > rhs[i]
            }
        }
        return lhs.count > rhs.count
    }
}
