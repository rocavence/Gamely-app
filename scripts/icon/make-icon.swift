#!/usr/bin/env swift
//
// Render Gamely's app icon at 1024×1024 as scripts/icon/icon-1024.png.
// Run via `scripts/icon/make-icon.sh` from the project root.
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

// White Reicon gamepad3 (bold), the same glyph as the menu bar, with a soft drop shadow.
let glyphPath = "Gamely/Resources/Assets.xcassets/Reicon/gamepad3-bold.outline.imageset/gamepad3-bold.outline.svg"
// Reicon clips the cable's rounded end at the top of its box. Unclip it and
// widen the box upward 1.5 units so the whole glyph shows.
guard var source = try? String(contentsOfFile: glyphPath, encoding: .utf8) else {
    fatalError("missing \(glyphPath); run scripts/reicon/generate.py")
}
source = source.replacingOccurrences(of: #" clip-path="url\(#[^)]*\)""#, with: "", options: .regularExpression)
    .replacingOccurrences(of: #"viewBox="0 0 24 24""#, with: #"viewBox="0 -1.5 24 24""#)
guard let svg = NSImage(data: Data(source.utf8)) else { fatalError("bad SVG") }

func white(_ image: NSImage, side: CGFloat) -> CGImage? {
    let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
        image.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    var rr = NSRect(x: 0, y: 0, width: side, height: side)
    return img.cgImage(forProposedRect: &rr, context: nil, hints: nil)
}

if let glyph = white(svg, side: 500) {
    // With the box widened, the drawing (y -1.05…21.05) sits centred in it.
    let side: CGFloat = 500
    let dst = CGRect(x: (size - side) / 2, y: (size - side) / 2, width: side, height: side)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36,
                  color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.draw(glyph, in: dst)
    ctx.restoreGState()
}

guard let cg = ctx.makeImage() else { fatalError("makeImage") }
let rep = NSBitmapImageRep(cgImage: cg)
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: "scripts/icon/icon-1024.png"))
print("Wrote scripts/icon/icon-1024.png")
