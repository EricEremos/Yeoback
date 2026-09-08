import AppKit

// Transparent 1080p typography for the brand film; coordinates share hero.html's 1600 × 900 grid.
let width = 1920, height = 1080
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.scaleBy(x: 1.2, y: 1.2)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}
let ivory = color(245,243,239), coral = color(250,156,141), muted = color(203,209,199)
func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, ink: NSColor, tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: ink, .kern: tracking]
    let string = NSAttributedString(string: value, attributes: attributes)
    let measured = string.size()
    string.draw(at: NSPoint(x: x, y: 900-top-measured.height))
}
text("Yeoback", x: 76, top: 68, size: 36, weight: .semibold, ink: ivory, tracking: -1.2)
text("여백", x: 238, top: 82, size: 18, ink: color(189,198,185))
text("Keep the work.", x: 76, top: 245, size: 83, weight: .semibold, ink: ivory, tracking: -4.4)
text("Lose the leftovers.", x: 76, top: 331.3, size: 83, weight: .semibold, ink: coral, tracking: -4.4)
text("Storage review for your Mac.", x: 80, top: 492, size: 24, ink: muted)
text("Room for your next idea.", x: 99, top: 819, size: 16, ink: muted)
text("Made for macOS", x: 1405, top: 819, size: 16, ink: muted)
color(229,129,112).setFill()
NSRect(x: 80, y: 62, width: 3, height: 19).fill()
NSGraphicsContext.restoreGraphicsState()
guard CommandLine.arguments.count == 2 else { fatalError("Pass a destination PNG path") }
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
