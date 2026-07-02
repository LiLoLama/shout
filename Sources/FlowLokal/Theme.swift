import SwiftUI

/// Farbwelt „Mischpult, sanft": dunkles Graphit-Panel, ein warmes Vermillion
/// als „live"/Aktiv-Akzent.
extension Color {
    /// „live"-Signalfarbe (kräftiges Rot-Orange) — Aufnahme, aktive Schalter, Lern-Akzent.
    static let shoutLive = Color(red: 1.0, green: 0.36, blue: 0.10)
    /// Fenster-/Panel-Hintergrund (Graphit).
    static let shoutPanel = Color(red: 0.145, green: 0.145, blue: 0.165)
    static let shoutPanelHi = Color(red: 0.19, green: 0.19, blue: 0.21)
    /// Vertiefte Flächen (Inset).
    static let shoutInset = Color(red: 0.10, green: 0.10, blue: 0.12)
}
