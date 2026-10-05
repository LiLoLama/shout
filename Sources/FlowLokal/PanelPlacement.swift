import CoreGraphics

/// Wo das Panel steht — als Anteil der sichtbaren Bildschirmfläche plus
/// Bildschirm-Kennung, wie bei der Pille. So übersteht es das Abstecken eines
/// großen Bildschirms und bleibt immer ganz sichtbar.
enum PanelPlacement {

    struct Saved: Codable, Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var screen: String?
    }

    static func save(_ rahmen: CGRect, in sichtbar: CGRect, screen: String?) -> Saved {
        Saved(x: (rahmen.minX - sichtbar.minX) / sichtbar.width,
              y: (rahmen.minY - sichtbar.minY) / sichtbar.height,
              width: rahmen.width / sichtbar.width,
              height: rahmen.height / sichtbar.height,
              screen: screen)
    }

    /// Größe zwischen `minSize` und der sichtbaren Fläche, Lage ganz darin.
    static func restore(_ gesichert: Saved, in sichtbar: CGRect, minSize: CGSize) -> CGRect {
        let breite = min(max(gesichert.width * sichtbar.width, minSize.width), sichtbar.width)
        let hoehe = min(max(gesichert.height * sichtbar.height, minSize.height), sichtbar.height)
        let x = min(max(sichtbar.minX + gesichert.x * sichtbar.width, sichtbar.minX), sichtbar.maxX - breite)
        let y = min(max(sichtbar.minY + gesichert.y * sichtbar.height, sichtbar.minY), sichtbar.maxY - hoehe)
        return CGRect(x: x, y: y, width: breite, height: hoehe)
    }

    /// Erster Start: oben rechts mit etwas Abstand zum Rand.
    static func initial(in sichtbar: CGRect, size: CGSize, margin: CGFloat = 16) -> CGRect {
        let breite = min(size.width, sichtbar.width)
        let hoehe = min(size.height, sichtbar.height)
        return CGRect(x: max(sichtbar.maxX - breite - margin, sichtbar.minX),
                      y: max(sichtbar.maxY - hoehe - margin, sichtbar.minY),
                      width: breite, height: hoehe)
    }
}
