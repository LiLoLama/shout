import CoreGraphics

/// Wo die Aufnahme-Pille sitzt — als **Anteil** des sichtbaren Bildschirms und
/// nicht in absoluten Punkten.
///
/// Der Unterschied ist nicht kosmetisch: Absolut gespeichert wanderte die Pille
/// beim Abstecken eines breiten Monitors an den rechten Rand. „Unten Mitte" eines
/// 3440 Punkt breiten Schirms liegt bei x ≈ 1720 — auf dem eingebauten Display
/// gibt es diesen Punkt nicht, also fand die Suche keinen passenden Bildschirm und
/// klemmte auf dessen Kante. Als Anteil bleibt „unten Mitte" überall unten Mitte.
///
/// Reine Geometrie, ohne AppKit — deshalb testbar.
enum PillPlacement {

    /// Anteil (0…1) eines Punktes innerhalb der sichtbaren Fläche.
    static func fraction(of center: CGPoint, in visible: CGRect) -> CGPoint {
        CGPoint(x: visible.width > 0 ? (center.x - visible.minX) / visible.width : 0.5,
                y: visible.height > 0 ? (center.y - visible.minY) / visible.height : 0.05)
    }

    /// Der Punkt zu einem Anteil auf einer (womöglich anderen) Fläche.
    static func center(for fraction: CGPoint, in visible: CGRect) -> CGPoint {
        let f = clamped(fraction)
        return CGPoint(x: visible.minX + f.x * visible.width,
                       y: visible.minY + f.y * visible.height)
    }

    static func clamped(_ fraction: CGPoint) -> CGPoint {
        CGPoint(x: min(max(fraction.x, 0), 1), y: min(max(fraction.y, 0), 1))
    }

    /// Soll die Pille senkrecht stehen?
    ///
    /// An einer Seitenkante ja, oben oder unten nein — sie soll dort schmal sein,
    /// wo sonst am meisten verdeckt würde. Verglichen wird, welche Kante näher
    /// liegt; bei Gleichstand (Ecke) bleibt es waagerecht, weil die waagerechte
    /// Pille die gewohnte ist.
    static func prefersVertical(at fraction: CGPoint) -> Bool {
        let f = clamped(fraction)
        let toSide = min(f.x, 1 - f.x)   // Abstand zur linken/rechten Kante
        let toEdge = min(f.y, 1 - f.y)   // Abstand zu oben/unten
        return toSide < toEdge
    }
}
