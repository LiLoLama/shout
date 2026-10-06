import AppKit

/// Der Text-Editor der Notizen: nimmt Bilder per Einfügen und Hineinziehen an.
final class NoteTextView: NSTextView {

    /// Übernimmt ein Bild. `true`, wenn es behandelt wurde — auch mit Fehlermeldung.
    var onImage: ((NoteAttachments.Source) -> Bool)?

    override func paste(_ sender: Any?) {
        if isEditable, let quelle = NoteAttachments.source(from: .general), onImage?(quelle) == true { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if isEditable, NoteAttachments.source(from: sender.draggingPasteboard) != nil { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if isEditable, NoteAttachments.source(from: sender.draggingPasteboard) != nil { return .copy }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if isEditable, let quelle = NoteAttachments.source(from: sender.draggingPasteboard) {
            let punkt = convert(sender.draggingLocation, from: nil)
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: punkt), length: 0))
            if onImage?(quelle) == true { return true }
        }
        return super.performDragOperation(sender)
    }
}
