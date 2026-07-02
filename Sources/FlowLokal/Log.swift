import Foundation

/// Einfaches Datei-Log für die Diagnose (unabhängig vom Unified Log).
/// Schreibt nach /tmp/shout-debug.log — nur Zustände/Längen, keine Diktatinhalte.
func dlog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/shout-debug.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}
