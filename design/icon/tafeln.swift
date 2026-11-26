#!/usr/bin/env swift
// Rendert jeden Entwurf mit ictool (Icon Composer) und setzt daraus die Vorschau-Tafeln zusammen:
// <entwurf>/tafel.png und uebersicht.png. Aufruf über build.py oder: swift tafeln.swift <design/icon>
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let fm = FileManager.default

func shell(_ path: String, _ arguments: [String]) -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = pipe
    try! process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("\(path) \(arguments): Status \(process.terminationStatus)") }
    return String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
}

let developer = URL(fileURLWithPath: shell("/usr/bin/xcode-select", ["-p"]))
let ictool = developer.deletingLastPathComponent().appending(path: "Applications/Icon Composer.app/Contents/Executables/ictool").path

struct Design { let folder: URL; let icon: URL; let title: String; let idea: String }

let designs: [Design] = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.range(of: "^[1-9]-", options: .regularExpression) != nil }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .map { folder in
        let icon = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first { $0.pathExtension == "icon" }!
        let lines = try String(contentsOf: folder.appending(path: "idee.txt"), encoding: .utf8).split(separator: "\n")
        return Design(folder: folder, icon: icon, title: "\(folder.lastPathComponent.prefix(1)) · \(lines[0])", idea: String(lines[1]))
    }

/// Rendering in Gerätepixeln (Punkte × Skalierung), im Ordner render/ zwischengespeichert pro Lauf.
func render(_ design: Design, _ appearance: String, _ points: Int, _ scale: Int = 3, generation: Int = 27) -> NSImage {
    let dir = design.folder.appending(path: "render")
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let out = dir.appending(path: "\(appearance)-\(points)@\(scale)x-ios\(generation).png")
    var arguments = [design.icon.path, "--export-image", "--output-file", out.path, "--platform", "iOS",
                     "--rendition", appearance, "--width", "\(points)", "--height", "\(points)", "--scale", "\(scale)",
                     "--design-generation", "\(generation)"]
    if appearance.hasPrefix("Tinted") { arguments += ["--tint-color", "0.55", "--tint-strength", "0.75"] }
    _ = shell(ictool, arguments)
    return NSImage(contentsOf: out)!
}

// MARK: Zeichnen (Koordinaten von oben links)

final class Canvas {
    let width: Int, height: Int
    let rep: NSBitmapImageRep
    init(_ width: Int, _ height: Int, background: NSColor) {
        self.width = width; self.height = height
        rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current!.imageInterpolation = .high
        fill(0, 0, width, height, background)
    }
    private func frame(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> NSRect { NSRect(x: x, y: height - y - h, width: w, height: h) }
    func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: NSColor, radius: Int = 0) {
        color.setFill()
        NSBezierPath(roundedRect: frame(x, y, w, h), xRadius: CGFloat(radius), yRadius: CGFloat(radius)).fill()
    }
    func gradient(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ top: NSColor, _ bottom: NSColor, radius: Int) {
        NSGradient(starting: top, ending: bottom)!.draw(
            in: NSBezierPath(roundedRect: frame(x, y, w, h), xRadius: CGFloat(radius), yRadius: CGFloat(radius)), angle: -90)
    }
    func image(_ image: NSImage, _ x: Int, _ y: Int, _ size: Int) { image.draw(in: frame(x, y, size, size)) }
    func text(_ string: String, _ x: Int, _ y: Int, size: CGFloat, color: NSColor = .black, bold: Bool = false, center: Int? = nil) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
                                                         .foregroundColor: color]
        let measured = (string as NSString).size(withAttributes: attributes)
        let left = center.map { $0 - Int(measured.width / 2) } ?? x
        (string as NSString).draw(at: NSPoint(x: CGFloat(left), y: CGFloat(height - y) - measured.height), withAttributes: attributes)
    }
    func save(_ url: URL) {
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        print("geschrieben: \(url.lastPathComponent) \(width)x\(height)")
    }
}

func gray(_ value: CGFloat) -> NSColor { NSColor(srgbRed: value, green: value, blue: value, alpha: 1) }
func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}

/// Homescreen-Ausschnitt mit neutralen Platzhalter-Apps (keine echten Apps oder Marken).
func homescreen(_ c: Canvas, _ design: Design, _ x: Int, _ y: Int, dark: Bool) {
    c.gradient(x, y, 1110, 900, dark ? color(0x1B2236) : color(0x9CC4E8), dark ? color(0x05070C) : color(0xE9D8F0), radius: 64)
    let tones: [(Int, Int)] = [(0x8E9AAF, 0x5C677D), (0xA3B18A, 0x588157), (0xE5989B, 0xB5838D), (0xFFCB77, 0xE09F3E),
                               (0x90CAF9, 0x4A7FB5), (0xCDB4DB, 0x8E7DBE), (0x9AD1C9, 0x4F9D95), (0xD6CCC2, 0x9C8F84)]
    let icon = render(design, dark ? "Dark" : "Default", 64)
    for row in 0..<3 {
        for column in 0..<4 {
            let left = x + 66 + column * 262, top = y + 70 + row * 270
            if row == 1 && column == 1 {
                c.image(icon, left, top, 192)
                c.text("Eingelaufen", 0, top + 202, size: 32, color: .white, center: left + 96)
            } else {
                let tone = tones[(row * 4 + column) % tones.count]
                let shade: CGFloat = dark ? 0.55 : 0
                c.gradient(left + 4, top + 4, 184, 184, color(tone.0).blended(withFraction: shade, of: .black)!,
                           color(tone.1).blended(withFraction: shade, of: .black)!, radius: 48)
                c.fill(left + 66, top + 214, 60, 14, NSColor(white: 1, alpha: 0.55), radius: 7)
            }
        }
    }
}

// MARK: Tafel je Entwurf

let appearances = [("Default", "Hell"), ("Dark", "Dunkel"), ("ClearLight", "Klar hell"), ("ClearDark", "Klar dunkel"),
                   ("TintedLight", "Getönt hell"), ("TintedDark", "Getönt dunkel")]
let sizes = [(60, "Homescreen 60 pt"), (40, "Spotlight 40 pt"), (29, "Einstellungen 29 pt"), (20, "Mitteilung 20 pt")]

for design in designs {
    let c = Canvas(2400, 2900, background: gray(0.94))
    c.text(design.title, 60, 40, size: 64, bold: true)
    c.text(design.idea, 60, 128, size: 34, color: gray(0.3))
    // Große Darstellungen
    for (i, appearance) in appearances.enumerated() {
        let x = 60 + (i % 3) * 780, y = 210 + (i / 3) * 440
        let darkBackdrop = appearance.0.hasSuffix("Dark")
        if appearance.0.hasPrefix("Clear") {
            c.gradient(x, y, 720, 410, darkBackdrop ? color(0x2B3A55) : color(0xA8CBEA), darkBackdrop ? color(0x0A0D14) : color(0xF1DDEB), radius: 40)
        } else {
            c.fill(x, y, 720, 410, darkBackdrop ? gray(0.07) : .white, radius: 40)
        }
        c.image(render(design, appearance.0, 110), x + 195, y + 14, 330)
        c.text(appearance.1, 0, y + 360, size: 28, color: darkBackdrop ? .white : gray(0.2), center: x + 360)
    }
    // Kleingrößen in echten Gerätepixeln (@3x)
    c.text("Kleingrößen in echten Pixeln (@3x)", 60, 1110, size: 40, bold: true)
    for (row, entry) in [("Default", "Hell", NSColor.white), ("Dark", "Dunkel", gray(0.07)), ("TintedDark", "Getönt", gray(0.07))].enumerated() {
        let y = 1180 + row * 220
        let ink: NSColor = entry.0 == "Default" ? gray(0.2) : .white
        c.fill(60, y, 1500, 205, entry.2, radius: 32)
        c.text(entry.1, 90, y + 82, size: 30, color: ink)
        var x = 330
        for (points, label) in sizes {
            c.image(render(design, entry.0, points), x, y + 8 + (180 - points * 3) / 2, points * 3)
            if row == 2 { c.text(label, 0, y + 205 + 8, size: 24, color: gray(0.3), center: x + points * 3 / 2) }
            x += 320
        }
    }
    // Mitteilung und Einstellungszeile
    for (row, dark) in [false, true].enumerated() {
        let y = 1180 + row * 330, ink: NSColor = dark ? .white : .black
        c.fill(1620, y, 720, 150, dark ? gray(0.16) : .white, radius: 48)
        c.image(render(design, dark ? "Dark" : "Default", 38), 1650, y + 18, 114)
        c.text("Eingelaufen", 1790, y + 26, size: 32, color: ink, bold: true)
        c.text("Wartung fällig: Laufschuhe", 1790, y + 78, size: 30, color: ink)
        c.fill(1620, y + 170, 720, 130, dark ? gray(0.11) : .white, radius: 32)
        c.image(render(design, dark ? "Dark" : "Default", 29), 1650, y + 192, 87)
        c.text("Eingelaufen", 1765, y + 214, size: 34, color: ink)
        c.text("›", 2290, y + 206, size: 44, color: gray(0.55))
    }
    // Homescreen
    c.text("Homescreen (Mockup, Platzhalter-Apps)", 60, 1890, size: 40, bold: true)
    homescreen(c, design, 60, 1960, dark: false)
    homescreen(c, design, 1230, 1960, dark: true)
    c.save(design.folder.appending(path: "tafel.png"))
}

// MARK: Übersicht aller Entwürfe neben dem aktuellen Icon

let overview = Canvas(2400, 170 + designs.count * 330, background: gray(0.94))
overview.text("Eingelaufen · Icon-Entwürfe", 60, 36, size: 56, bold: true)
for (x, label) in [(520, "Hell"), (880, "Dunkel"), (1240, "Getönt"), (1600, "iOS 26 hell"), (2030, "29 pt · 20 pt")] {
    overview.text(label, 0, 112, size: 30, color: gray(0.3), center: x + 140)
}
for (row, design) in designs.enumerated() {
    let y = 170 + row * 330
    overview.fill(40, y, 2320, 310, row % 2 == 0 ? .white : gray(0.98), radius: 40)
    overview.text(design.title, 80, y + 130, size: 42, bold: true)
    for (i, appearance) in ["Default", "Dark", "TintedDark"].enumerated() {
        overview.image(render(design, appearance, 90), 525 + i * 360, y + 20, 270)
    }
    overview.image(render(design, "Default", 90, generation: 26), 1605, y + 20, 270)
    overview.fill(2020, y + 40, 320, 230, gray(0.07), radius: 32)
    overview.image(render(design, "Default", 29), 2060, y + 112, 87)
    overview.image(render(design, "Dark", 29), 2160, y + 112, 87)
    overview.image(render(design, "Default", 20), 2262, y + 126, 60)
}
overview.save(root.appending(path: "uebersicht.png"))
