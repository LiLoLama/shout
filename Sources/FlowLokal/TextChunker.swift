import Foundation

/// Teilt langen Text in Abschnitte, die einzeln durchs Formatierungs-Modell passen.
///
/// Ein einstündiges Transkript in einem Rutsch ans Modell zu geben, sprengt das
/// Kontextfenster des kleinen quantisierten Modells. Geschnitten wird an
/// Satzgrenzen, damit die Aufbereitung nicht mitten im Satz neu ansetzt.
///
/// Die Satzgrenze ist eine Heuristik: „.!?" gefolgt von Leerraum und einem
/// Großbuchstaben, wobei bekannte Abkürzungen und einzelne Buchstaben davor
/// ausgeschlossen sind („z. B.", „Dr."). Sie kann danebenliegen — schlimmstenfalls
/// steht ein Absatzumbruch an einer unschönen Stelle. Am Wortlaut ändert sich nichts.
enum TextChunker {

    /// Wörter, nach denen ein Punkt kein Satzende ist. Einzelne Buchstaben werden
    /// separat behandelt (deckt „z. B.", „u. a." und Initialen ab).
    private static let abbreviations: Set<String> = [
        "ca", "bzw", "usw", "etc", "vgl", "ggf", "inkl", "evtl", "sog", "bspw",
        "dr", "prof", "nr", "abb", "bzgl", "mr", "mrs", "st", "vs", "approx"
    ]

    /// Zerlegt den Text. Abschnitte werden so nah wie möglich am Zielmaß
    /// geschnitten, aber nie kürzer als `minLength` — sonst zerfiele ein Text mit
    /// vielen kurzen Sätzen in lauter Schnipsel.
    static func chunks(of text: String, targetLength: Int = 1500, minLength: Int = 1000) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > targetLength else { return [trimmed] }

        var result: [String] = []
        var rest = Substring(trimmed)
        while rest.count > targetLength {
            let limit = rest.index(rest.startIndex, offsetBy: targetLength)
            let floor = rest.index(rest.startIndex, offsetBy: min(minLength, targetLength))
            let cut = sentenceBreak(in: rest, before: limit, notBefore: floor) ?? limit
            let piece = rest[rest.startIndex..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { result.append(piece) }
            rest = rest[cut...]
        }
        let tail = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    /// Fügt abschnittsweise formatierte Stücke wieder zu einem Text zusammen.
    ///
    /// Normalfall ist ein Leerzeichen (die Schnitte liegen an Satzgrenzen, der
    /// Fließtext soll wieder einer werden). Endet ein Stück aber mit einer
    /// Aufzählung oder beginnt das nächste mit einer, kommt ein Zeilenumbruch —
    /// sonst klebt der Folgetext am letzten Listenpunkt („3. das Feedback Für …").
    static func joinFormatted(_ pieces: [String]) -> String {
        let parts = pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard var result = parts.first else { return "" }
        for piece in parts.dropFirst() {
            let lineStart = result.lastIndex(of: "\n").map { result.index(after: $0) } ?? result.startIndex
            let lastLine = result[lineStart...]
            let firstLine = piece.prefix(while: { $0 != "\n" })
            let needsBreak = isListItem(lastLine) || isListItem(firstLine)
            result += (needsBreak ? "\n" : " ") + piece
        }
        return result
    }

    /// Sieht die Zeile wie ein Listenpunkt aus? („1. ", „2) ", „- ", „• ")
    private static func isListItem<S: StringProtocol>(_ line: S) -> Bool {
        let trimmed = line.drop(while: \.isWhitespace)
        guard let first = trimmed.first else { return false }
        if first == "-" || first == "•" || first == "*" { return true }
        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        let after = trimmed.dropFirst(digits.count)
        return after.first == "." || after.first == ")"
    }

    /// Letzte Satzgrenze im Bereich [notBefore, before). Zurück kommt der Index des
    /// ersten Zeichens des FOLGENDEN Satzes — der Leerraum dazwischen fällt weg.
    private static func sentenceBreak(in text: Substring, before limit: Substring.Index,
                                      notBefore floor: Substring.Index) -> Substring.Index? {
        var i = limit
        while i > floor {
            i = text.index(before: i)
            guard ".!?".contains(text[i]) else { continue }
            guard !isAbbreviation(in: text, periodAt: i) else { continue }
            var j = text.index(after: i)
            guard j < text.endIndex, text[j].isWhitespace else { continue }
            while j < text.endIndex, text[j].isWhitespace { j = text.index(after: j) }
            guard j < text.endIndex, text[j].isUppercase else { continue }
            return j
        }
        return nil
    }

    /// Prüft das Wort unmittelbar vor dem Punkt. Ein einzelner Buchstabe („z.", „B.")
    /// oder eine bekannte Abkürzung („Dr.") beendet keinen Satz.
    private static func isAbbreviation(in text: Substring, periodAt index: Substring.Index) -> Bool {
        guard text[index] == "." else { return false }
        var start = index
        var word = ""
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous].isLetter else { break }
            word.insert(text[previous], at: word.startIndex)
            start = previous
        }
        guard !word.isEmpty else { return false }
        return word.count == 1 || abbreviations.contains(word.lowercased())
    }
}
