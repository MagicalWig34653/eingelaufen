#!/usr/bin/env swift
// Erzeugt das App-Icon (1024x1024, ohne Alpha) deterministisch aus Code.
// Aufruf: swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("context") }

// Hintergrund: Verlauf in der Akzentfarbe der App (Türkis, siehe AccentColor).
let colors = [CGColor(red: 0.16, green: 0.66, blue: 0.60, alpha: 1), CGColor(red: 0.03, green: 0.30, blue: 0.29, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

// Weißer Ring mit Lücke (kein Prozentwert) = zurückgelegter Weg; Punkt an der Lücke = „eingelaufen“.
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(88)
ctx.setLineCap(.round)
let center = CGPoint(x: 512, y: 512), radius: CGFloat = 340
ctx.addArc(center: center, radius: radius, startAngle: .pi * 0.15, endAngle: .pi * 1.7, clockwise: false)
ctx.strokePath()
let dot = CGPoint(x: center.x + radius * cos(.pi * 1.9), y: center.y + radius * sin(.pi * 1.9))
ctx.fillEllipse(in: CGRect(x: dot.x - 44, y: dot.y - 44, width: 88, height: 88))

// Drei Profilstollen in der Mitte (Sohle), mittig gestapelt.
for (i, w) in [CGFloat(320), CGFloat(240), CGFloat(160)].enumerated() {
    let rect = CGRect(x: 512 - w / 2, y: 592 - CGFloat(i) * 110 - 35, width: w, height: 70)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 35, cornerHeight: 35, transform: nil))
    ctx.fillPath()
}

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("image") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write") }
print("geschrieben: \(out)")
