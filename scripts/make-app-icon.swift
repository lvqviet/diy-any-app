#!/usr/bin/env swift
// Generates the macOS AppIcon.appiconset from one square source image.
//
//     swift scripts/make-app-icon.swift Design/app-icon-source.png App/Assets.xcassets/AppIcon.appiconset
//
// The artwork is placed on a white rounded-rectangle tile with a soft shadow, following
// Apple's macOS icon grid (824 pt tile on a 1024 pt canvas), then rendered at every size.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]) else {
    print("usage: make-app-icon.swift <source.png> <AppIcon.appiconset>")
    exit(64)
}
let outputDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

/// Draws the icon on a 1024-unit canvas scaled to `pixels`.
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    // Tile with a soft drop shadow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Artwork clipped to the tile, inset slightly so it does not touch the edges.
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let inset = tile.insetBy(dx: 824 * 0.04, dy: 824 * 0.04)
    source.draw(in: inset, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // Hairline edge so the white tile stays visible on light backgrounds.
    NSColor.black.withAlphaComponent(0.08).setStroke()
    path.lineWidth = 2
    path.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes = [16, 32, 128, 256, 512]
var images: [[String: String]] = []
var rendered: [Int: Data] = [:]
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let data = rendered[pixels] ?? render(pixels: pixels)
        rendered[pixels] = data
        try data.write(to: outputDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDir.appendingPathComponent("Contents.json"))
print("wrote \(images.count) images to \(outputDir.path)")
