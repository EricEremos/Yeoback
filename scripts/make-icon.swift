import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/make-icon.swift <output.iconset>\n", stderr)
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Brand")
func source(_ name: String) -> NSImage {
    let url = assets.appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url),
          let bitmap = NSBitmapImageRep(data: data),
          bitmap.pixelsWide == 1024, bitmap.pixelsHigh == 1024,
          let image = NSImage(data: data) else {
        fatalError("Expected a 1024 × 1024 icon master at \(url.path)")
    }
    return image
}
let detailed = source("Yeoback-icon-1024.png")
let simplified = source("Yeoback-icon-small-1024.png")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = base * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let image = base <= 32 ? simplified : detailed
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
        try png.write(to: output.appendingPathComponent("icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"))
    }
}
