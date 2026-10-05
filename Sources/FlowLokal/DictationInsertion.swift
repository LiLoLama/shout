import Foundation

/// Wie ein Diktat an den Cursor anschließt: mit einem Leerzeichen, wenn es sonst
/// am Wort davor klebte; ohne, wenn davor schon Leerraum oder eine öffnende
/// Klammer/Anführung steht oder das Diktat mit einem Satzzeichen beginnt.
enum DictationInsertion {

    static func text(_ text: String, after previous: Character?) -> String {
        guard let previous, let erstes = text.first else { return text }
        if previous.isWhitespace { return text }
        if ",.;:!?)]}…".contains(erstes) { return text }
        if "([{\"„‚'“".contains(previous) { return text }
        return " " + text
    }
}
