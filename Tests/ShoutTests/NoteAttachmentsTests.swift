import XCTest
import AppKit

final class NoteAttachmentsTests: XCTestCase {

    private var ordner: URL!

    override func setUpWithError() throws {
        ordner = FileManager.default.temporaryDirectory.appendingPathComponent("shout-anhaenge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: ordner)
        super.tearDown()
    }

    static func bild(_ typ: NSBitmapImageRep.FileType, breite: Int = 4, hoehe: Int = 3) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: breite, pixelsHigh: hoehe,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: typ, properties: [:])!
    }

    private let zeit = Date(timeIntervalSince1970: 1_791_210_730)   // 2026-10-05 14:32:10 UTC
    private let utc = TimeZone(identifier: "UTC")!

    func testDateinameUndZaehler() {
        XCTAssertEqual(NoteAttachments.fileName(at: zeit, timeZone: utc) { _ in false }, "2026-10-05-143210.png")
        let belegt: Set = ["2026-10-05-143210.png", "2026-10-05-143210-2.png"]
        XCTAssertEqual(NoteAttachments.fileName(at: zeit, timeZone: utc) { belegt.contains($0) }, "2026-10-05-143210-3.png")
    }

    func testPNGBleibtTIFFWirdPNG() throws {
        let png = Self.bild(.png)
        XCTAssertEqual(NoteAttachments.pngData(from: png), png)
        let umgewandelt = try XCTUnwrap(NoteAttachments.pngData(from: Self.bild(.tiff)))
        XCTAssertTrue(umgewandelt.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    func testDatenLandenInAnhaenge() throws {
        let ergebnis = NoteAttachments.store(.data(Self.bild(.png)), in: ordner, now: zeit)
        let pfad = try ergebnis.get()
        XCTAssertTrue(pfad.hasPrefix("Anhänge/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ordner.appendingPathComponent(pfad).path))
    }

    func testZweimalInDerselbenSekunde() throws {
        let a = try NoteAttachments.store(.data(Self.bild(.png)), in: ordner, now: zeit).get()
        let b = try NoteAttachments.store(.data(Self.bild(.png)), in: ordner, now: zeit).get()
        XCTAssertNotEqual(a, b)
    }

    func testZuGrossWirdNichtGesichert() {
        let gross = Data(count: NoteAttachments.maxSourceBytes + 1)
        XCTAssertEqual(NoteAttachments.store(.data(gross), in: ordner), .failure(.tooLarge))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ordner.appendingPathComponent("Anhänge").path))
    }

    func testZuGrosseDatei() throws {
        let datei = ordner.appendingPathComponent("riesig.png")
        try Data(count: NoteAttachments.maxSourceBytes + 1).write(to: datei)
        XCTAssertEqual(NoteAttachments.store(.file(datei), in: ordner), .failure(.tooLarge))
    }

    /// Roh über 10 MB (TIFF aus der Zwischenablage), als PNG winzig: gilt die PNG.
    func testGrosserTIFFMitKleinerPNGWirdAngenommen() throws {
        let tiff = Self.bild(.tiff, breite: 2000, hoehe: 1500)
        XCTAssertGreaterThan(tiff.count, NoteAttachments.maxBytes)
        XCTAssertLessThan(tiff.count, NoteAttachments.maxSourceBytes)
        let pfad = try NoteAttachments.store(.data(tiff), in: ordner, now: zeit).get()
        let png = try Data(contentsOf: ordner.appendingPathComponent(pfad))
        XCTAssertLessThan(png.count, NoteAttachments.maxBytes)
    }

    /// Rauschen lässt sich nicht verlustfrei packen: Die PNG ist größer als 10 MB.
    func testPNGUeberZehnMBWirdNichtGesichert() {
        let rauschen = Self.rauschen(breite: 3000, hoehe: 2000)
        XCTAssertEqual(NoteAttachments.store(.data(rauschen), in: ordner), .failure(.tooLarge))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ordner.appendingPathComponent("Anhänge").path))
    }

    static func rauschen(breite: Int, hoehe: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: breite, pixelsHigh: hoehe,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var zufall = SystemRandomNumberGenerator()
        let daten = rep.bitmapData!
        // Deckend, sonst dämpft die vormultiplizierte Alpha das Rauschen.
        for i in 0..<(rep.bytesPerRow * hoehe) { daten[i] = i % 4 == 3 ? 255 : UInt8.random(in: 0...255, using: &zufall) }
        return rep.representation(using: .tiff, properties: [:])!
    }

    func testKeinBild() {
        XCTAssertEqual(NoteAttachments.store(.data(Data("kein bild".utf8)), in: ordner), .failure(.unreadable))
    }

    func testBilddatei() throws {
        let datei = ordner.appendingPathComponent("foto.tiff")
        try Self.bild(.tiff).write(to: datei)
        XCTAssertNoThrow(try NoteAttachments.store(.file(datei), in: ordner).get())
    }

    func testEigeneZeile() {
        let md = "![](Anhänge/a.png)"
        XCTAssertEqual(NoteAttachments.insertion(for: "Anhänge/a.png", after: nil, before: nil), md + "\n")
        XCTAssertEqual(NoteAttachments.insertion(for: "Anhänge/a.png", after: "x", before: "y"), "\n" + md + "\n")
        XCTAssertEqual(NoteAttachments.insertion(for: "Anhänge/a.png", after: "\n", before: "\n"), md)
    }

    func testPfadeNurImNotizordner() {
        XCTAssertEqual(NoteAttachments.resolve("Anhänge/a.png", in: ordner)?.lastPathComponent, "a.png")
        XCTAssertNotNil(NoteAttachments.resolve("Anh%C3%A4nge/a.png", in: ordner))
        XCTAssertNil(NoteAttachments.resolve("../a.png", in: ordner))
        XCTAssertNil(NoteAttachments.resolve("/etc/a.png", in: ordner))
        XCTAssertNil(NoteAttachments.resolve("https://x.de/a.png", in: ordner))
    }

    func testQuelleAusDerZwischenablage() throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("shout-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setData(Self.bild(.png), forType: .png)
        XCTAssertEqual(NoteAttachments.source(from: pb), .data(Self.bild(.png)))

        pb.clearContents()
        pb.declareTypes([.png, .string], owner: nil)
        pb.setData(Self.bild(.png), forType: .png)
        pb.setString("Text aus dem Browser", forType: .string)
        XCTAssertNil(NoteAttachments.source(from: pb), "Text geht vor")

        let datei = ordner.appendingPathComponent("b.png")
        try Self.bild(.png).write(to: datei)
        pb.clearContents()
        pb.writeObjects([datei as NSURL])
        XCTAssertEqual(NoteAttachments.source(from: pb), .file(datei))
    }

    @MainActor
    func testDragTypenBleibenNachSperreErhalten() {
        let tv = NoteTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        for typ in [NSPasteboard.PasteboardType.png, .tiff, .fileURL] {
            XCTAssertTrue(tv.acceptableDragTypes.contains(typ))
        }
        XCTAssertEqual(tv.acceptableDragTypes.count, Set(tv.acceptableDragTypes).count)
        tv.isEditable = false
        tv.isEditable = true
        XCTAssertTrue(tv.acceptableDragTypes.contains(.png))
    }
}
