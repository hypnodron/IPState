import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: background.swift output.tiff\n", stderr)
    exit(2)
}

let width = 640.0
let height = 420.0
let scale = 2.0
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale),
    pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width, height: height)
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.current = context
context.cgContext.setShouldAntialias(true)
let canvas = NSRect(x: 0, y: 0, width: width, height: height)

func color(_ hex: UInt32, alpha: Double = 1) -> NSColor {
    NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255, alpha: alpha)
}

NSGradient(colors: [color(0xFFFFFF), color(0xEDF3FD), color(0xE2ECFC)])!
    .draw(in: canvas, angle: 115)
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [color(0x93B8FA, alpha: 0.30).cgColor, color(0x93B8FA, alpha: 0).cgColor] as CFArray,
    locations: [0, 1])!
context.cgContext.drawRadialGradient(glow, startCenter: CGPoint(x: 160, y: 206), startRadius: 0,
    endCenter: CGPoint(x: 160, y: 206), endRadius: 260, options: [])

for (radius, opacity, thickness) in [(80.0, 0.11, 1.1), (113.0, 0.06, 0.9), (148.0, 0.025, 0.7)] {
    let ring = NSBezierPath(ovalIn: NSRect(x: 160 - radius, y: 206 - radius,
        width: radius * 2, height: radius * 2))
    color(0x2860C4, alpha: opacity).setStroke()
    ring.lineWidth = thickness
    ring.stroke()
}

for (radius, opacity, thickness) in [(29.0, 0.19, 1.2), (57.0, 0.10, 0.9), (88.0, 0.05, 0.7)] {
    let ring = NSBezierPath(ovalIn: NSRect(x: 552 - radius, y: 351 - radius,
        width: radius * 2, height: radius * 2))
    color(0x3768BC, alpha: opacity).setStroke()
    ring.lineWidth = thickness
    ring.stroke()
}
color(0xE8AD36).setFill()
NSBezierPath(ovalIn: NSRect(x: 546, y: 345, width: 12, height: 12)).fill()

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0x244C8F, alpha: 0.18)
shadow.shadowBlurRadius = 16
shadow.shadowOffset = .zero
shadow.set()
color(0x31548F, alpha: 0.06).setFill()
NSBezierPath(ovalIn: NSRect(x: 114, y: 145, width: 92, height: 8)).fill()
NSGraphicsContext.restoreGraphicsState()

// Blend into Finder's white canvas when fewer bars leave more space below the artwork.
NSGradient(colors: [color(0xFFFFFF), color(0xFFFFFF, alpha: 0)])!
    .draw(in: NSRect(x: 0, y: 0, width: width, height: 64), angle: 90)

func text(_ value: String, top: Double, size: Double, weight: NSFont.Weight,
          opacity: Double = 1, hex: UInt32 = 0x193D78, alignment: NSTextAlignment = .center) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color(hex, alpha: opacity), .paragraphStyle: style
    ]
    NSAttributedString(string: value, attributes: attributes).draw(in:
        NSRect(x: 52, y: height - top - size * 1.5, width: width - 104, height: size * 1.5))
}

text("IP State", top: 39, size: 34, weight: .semibold, alignment: .left)
text("Your public IP, at a glance.", top: 89, size: 15, weight: .regular,
     hex: 0x607394, alignment: .left)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 274, y: 206))
arrow.line(to: NSPoint(x: 366, y: 206))
arrow.move(to: NSPoint(x: 351, y: 221))
arrow.line(to: NSPoint(x: 366, y: 206))
arrow.line(to: NSPoint(x: 351, y: 191))
arrow.lineWidth = 3.0
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
color(0xCC931F).setStroke()
arrow.stroke()

text("Drag IP State to Applications", top: 331, size: 20, weight: .semibold)
text("Then open IP State from Applications.", top: 366, size: 13, weight: .regular, hex: 0x657794)

let image = bitmap.representation(using: .tiff, properties: [:])!
try image.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
