import Foundation

/// Eine Notiz im Speicher. Auf der Platte ist sie eine `.md`-Datei im
/// Notizordner; die `id` lebt nur zur Laufzeit und hält Editor und Liste
/// zusammen, auch wenn die Datei umbenannt wird.
struct Note: Identifiable, Equatable {
    let id: UUID
    /// „Newsletter-Idee Oktober.md" — leer, solange die Notiz nie gesichert wurde.
    var fileName: String
    /// Der Text ohne Frontmatter.
    var body: String
    var created: Date
    /// mtime der Datei beim letzten Lesen oder Schreiben. Daran erkennt der
    /// Store, ob jemand anderes die Datei inzwischen geändert hat.
    var modified: Date
    var pinned: Bool
    /// Unbekannte Frontmatter-Zeilen (z. B. `tags` aus Obsidian), wörtlich.
    var extraFrontmatter: [String]
    /// Ab drei Wörtern steht der Dateiname fest; vorher wandert er mit dem Text.
    var titleIsFixed: Bool
    /// iCloud hat die Datei ausgelagert; der Inhalt ist noch nicht da.
    var isPlaceholder: Bool = false

    var title: String { (fileName as NSString).deletingPathExtension }
    var isNew: Bool { fileName.isEmpty }

    static func blank(now: Date = Date()) -> Note {
        Note(id: UUID(), fileName: "", body: "", created: now, modified: now,
             pinned: false, extraFrontmatter: [], titleIsFixed: false)
    }
}
