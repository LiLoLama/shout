import Foundation

/// Gemeinsame, robuste JSON-Persistenz für die lokalen Stores.
///
/// Wichtig gegenüber der früheren `try?`-Variante:
///  - „Datei fehlt" (Erststart) wird von „Datei defekt" unterschieden.
///  - Eine defekte Datei wird zur Beweissicherung umbenannt statt beim nächsten
///    Speichern stillschweigend überschrieben.
///  - Schreib-/Verzeichnisfehler werden geloggt (nicht verschluckt).
enum StoreIO {

    /// App-Support-Verzeichnis der App (`…/Application Support/shout/`), angelegt falls nötig.
    static func directory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("shout", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("shout: App-Support-Ordner konnte nicht erstellt werden: \(error)")
        }
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL,
                                   decoder: JSONDecoder = JSONDecoder()) -> T? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }   // Erststart – normal
        guard let data = try? Data(contentsOf: url) else {
            NSLog("shout: \(url.lastPathComponent) existiert, ist aber nicht lesbar.")
            return nil
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Defekte/inkompatible Datei sichern, damit save() sie nicht überschreibt.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + ".corrupt-\(stamp)")
            try? fm.moveItem(at: url, to: backup)
            NSLog("shout: \(url.lastPathComponent) defekt (\(error)) → gesichert als \(backup.lastPathComponent)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to url: URL,
                                   encoder: JSONEncoder = JSONEncoder()) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("shout: Schreiben von \(url.lastPathComponent) fehlgeschlagen: \(error)")
        }
    }
}
