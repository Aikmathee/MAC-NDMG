import AppKit

// Generate a native, resolution-independent source icon using system drawing APIs.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = NSRect(x: 72, y: 72, width: 880, height: 880)
        let path = NSBezierPath(roundedRect: rect, xRadius: 195, yRadius: 195)
        NSGradient(starting: NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.86, alpha: 1),
                   ending: NSColor(calibratedRed: 0.25, green: 0.69, blue: 1, alpha: 1))!.draw(in: path, angle: 65)
        NSColor.white.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 3
        path.stroke()
        if let symbol = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 440, weight: .light))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white])) {
            symbol.draw(in: NSRect(x: 252, y: 266, width: 520, height: 492))
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
