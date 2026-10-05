import Foundation

/// Wie ein Diktat an den Cursor anschließt: mit einem Leerzeichen, wenn es sonst
/// am Wort davor klebte; ohne, wenn davor schon Leerraum oder eine eindeutig
/// öffnende Klammer/Anführung steht oder das Diktat mit Leerraum oder einem
/// Satzzeichen beginnt. Gerade Anführungszeichen und „“ schließen oft
/// („Hallo“) und zählen deshalb nicht als öffnend.
enum DictationInsertion {

    static func text(_ text: String, after previous: Character?) -> String {
        guard let previous, let erstes = text.first else { return text }
        if previous.isWhitespace || erstes.isWhitespace { return text }
        if ",.;:!?)]}…".contains(erstes) { return text }
        if "([{„‚«".contains(previous) { return text }
        return " " + text
    }
}
