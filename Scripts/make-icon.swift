#!/usr/bin/env swift
//
// Render Gamely's app icon at 1024×1024 as Resources/icon-1024.png.
// Run via `swift Scripts/make-icon.swift` from the project root.
//
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let inset: CGFloat = 96
let corner: CGFloat = 228   // macOS Tahoe squircle proportion

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("CGContext") }

ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

// Purple → indigo background, with a soft top sheen.
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let bg = [
    NSColor(red: 0.49, green: 0.31, blue: 0.97, alpha: 1).cgColor,
    NSColor(red: 0.30, green: 0.13, blue: 0.72, alpha: 1).cgColor,
] as CFArray
ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: bg, locations: [0, 1])!,
                       start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
let sheen = [NSColor.white.withAlphaComponent(0.20).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: sheen, locations: [0, 0.55])!,
                       start: CGPoint(x: rect.midX, y: rect.maxY),
                       end: CGPoint(x: rect.midX, y: rect.midY), options: [])
ctx.restoreGState()

// White game controller glyph, centered, with a soft drop shadow.
func whiteSymbol(_ name: String, point: CGFloat) -> CGImage? {
    let conf = NSImage.SymbolConfiguration(pointSize: point, weight: .semibold)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(conf) else { return nil }
    let sz = base.size
    let img = NSImage(size: sz)
    img.lockFocus()
    NSColor.white.set()
    let r = NSRect(origin: .zero, size: sz)
    base.draw(in: r)
    r.fill(using: .sourceAtop)
    img.unlockFocus()
    var rr = NSRect(origin: .zero, size: sz)
    return img.cgImage(forProposedRect: &rr, context: nil, hints: nil)
}

if let glyph = whiteSymbol("gamecontroller.fill", point: 512) {
    // Scale the glyph to a fixed share of the canvas so the squircle stays visible.
    let targetWidth: CGFloat = 560
    let scale = targetWidth / CGFloat(glyph.width)
    let w = CGFloat(glyph.width) * scale, h = CGFloat(glyph.height) * scale
    let dst = CGRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36,
                  color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.draw(glyph, in: dst)
    ctx.restoreGState()
}

guard let cg = ctx.makeImage() else { fatalError("makeImage") }
let rep = NSBitmapImageRep(cgImage: cg)
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: "Resources/icon-1024.png"))
print("Wrote Resources/icon-1024.png")
