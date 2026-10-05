import Foundation

/// Wo die Notizen liegen. Die Mac-App läuft ohne Sandbox, der Pfad steht als
/// Klartext in den UserDefaults — ein Security-scoped Bookmark ist nicht nötig.
@MainActor
enum NotesFolder {

    static let defaultsKey = "notesFolderPath"

    /// `~/Documents/shout Notizen` (im Finder „Dokumente"), bei englischer
    /// Oberfläche `shout Notes`.
    ///
    /// `german` als `Bool?` mit Nil-Standard: `Loc.isGerman` ist Main-Actor-isoliert und kann nicht
    /// als Default-Parameter verwendet werden. Im Funktionskörper wird es aufgelöst (läuft auf dem Main Actor).
    static func defaultURL(german: Bool? = nil,
                           home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let deutsch = german ?? Loc.isGerman
        return home.appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(deutsch ? "shout Notizen" : "shout Notes", isDirectory: true)
    }

    /// Der eingestellte Ordner. Beim allerersten Aufruf wird die Vorgabe
    /// festgeschrieben, damit ein späterer Sprachwechsel sie nicht verschiebt.
    ///
    /// `german` als `Bool?` mit Nil-Standard: `Loc.isGerman` ist Main-Actor-isoliert und kann nicht
    /// als Default-Parameter verwendet werden. Im Funktionskörper wird es aufgelöst (läuft auf dem Main Actor).
    static func current(defaults: UserDefaults = .standard,
                        german: Bool? = nil,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let path = defaults.string(forKey: defaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let deutsch = german ?? Loc.isGerman
        let vorgabe = defaultURL(german: deutsch, home: home)
        defaults.set(vorgabe.path, forKey: defaultsKey)
        return vorgabe
    }

    static func set(_ url: URL, defaults: UserDefaults = .standard) {
        defaults.set(url.standardizedFileURL.path, forKey: defaultsKey)
    }

    /// Nur die Vorgabe darf der Store selbst anlegen. Ein gewählter Ordner, der
    /// fehlt, liegt vermutlich auf einem abgesteckten Laufwerk.
    static func isDefault(_ url: URL,
                          home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let pfad = url.standardizedFileURL.path
        return [true, false].contains { defaultURL(german: $0, home: home).standardizedFileURL.path == pfad }
    }
}
