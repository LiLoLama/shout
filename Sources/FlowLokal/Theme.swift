import SwiftUI

/// Farbwelt „Mischpult, sanft": dunkles Graphit-Panel, ein warmes Vermillion
/// als „live"/Aktiv-Akzent.
extension Color {
    /// „live"-Signalfarbe (kräftiges, sattes Rot-Orange) — Aufnahme, aktive Schalter, Lern-Akzent.
    static let shoutLive = Color(red: 1.0, green: 0.29, blue: 0.04)
    /// Fenster-/Panel-Hintergrund (Graphit).
    static let shoutPanel = Color(red: 0.145, green: 0.145, blue: 0.165)
    static let shoutPanelHi = Color(red: 0.19, green: 0.19, blue: 0.21)
    /// Vertiefte Flächen (Inset).
    static let shoutInset = Color(red: 0.10, green: 0.10, blue: 0.12)
    /// Fenster-Hintergrund (dunkler als die Panels, damit sie sich abheben).
    static let shoutWindow = Color(red: 0.105, green: 0.105, blue: 0.125)
    /// Seitenleisten-Hintergrund (noch etwas dunkler).
    static let shoutSidebar = Color(red: 0.085, green: 0.085, blue: 0.10)
}
