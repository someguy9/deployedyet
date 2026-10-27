// Draws every app and site icon: a soft cone of green light falling on a white ✓ (the site's hero light, calmed).
// Each size is drawn natively at its own pixel count, the way a real .icns ships, so 16px stays crisp.
// Run from the repo root:  swift app/make-icon.swift
import AppKit
import CoreImage

let green = NSColor(srgbRed: 0.379, green: 0.797, blue: 0.488, alpha: 1) // the site's --color-ship
let topInk = NSColor(srgbRed: 0.150, green: 0.158, blue: 0.180, alpha: 1)
let bottomInk = NSColor(srgbRed: 0.045, green: 0.050, blue: 0.062, alpha: 1)

/// mac: Apple's icon grid (824 of 1024, margin and shadow). tight: favicons fill the square. bleed: iOS rounds it itself.
enum Layout { case mac, tight, bleed }

func body(_ s: CGFloat, _ l: Layout) -> NSRect {
    switch l {
    case .mac: NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    case .tight, .bleed: NSRect(x: 0, y: 0, width: s, height: s)
    }
}
func shape(_ s: CGFloat, _ l: Layout) -> NSBezierPath {
    let b = body(s, l)
    return l == .bleed ? NSBezierPath(rect: b) : NSBezierPath(roundedRect: b, xRadius: b.width * 0.2245, yRadius: b.width * 0.2245)
}
/// A point in the body: (0,0) bottom-left, (1,1) top-right.
func u(_ s: CGFloat, _ l: Layout, _ x: CGFloat, _ y: CGFloat) -> NSPoint {
    let b = body(s, l); return NSPoint(x: b.minX + b.width * x, y: b.minY + b.height * y)
}

func draw(_ s: CGFloat, _ l: Layout) {
    let path = shape(s, l)
    if l == .mac && s >= 64 { // the drop shadow is for Dock sizes; small renditions stay crisp
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
        sh.shadowBlurRadius = s * 0.027; sh.shadowOffset = NSSize(width: 0, height: -s * 0.012); sh.set()
        NSColor.black.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGradient(colors: [topInk, bottomInk])!.draw(in: path, angle: -90)
    if l != .bleed {
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let rim = shape(s, l); rim.lineWidth = max(1, s * 0.004); rim.stroke()
    }

    // The light: one cone, blurred for real, that fades slowly so it keeps its shape where it's wide.
    let px = Int(s)
    let layer = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: layer)
    NSColor.clear.set(); NSRect(x: 0, y: 0, width: s, height: s).fill(using: .copy)
    let fan = NSBezierPath()
    fan.move(to: u(s, l, 0.5, 1.1)); fan.line(to: u(s, l, -0.02, -0.1)); fan.line(to: u(s, l, 1.02, -0.1)); fan.close()
    NSGradient(colors: [green.withAlphaComponent(0.9), green.withAlphaComponent(0.38), green.withAlphaComponent(0.1)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: fan, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    let blurred = CIImage(bitmapImageRep: layer)!.clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: s * 0.06])
        .cropped(to: CGRect(x: 0, y: 0, width: s, height: s))
    let beam = CIContext().createCGImage(blurred, from: CGRect(x: 0, y: 0, width: s, height: s))!
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSImage(cgImage: beam, size: NSSize(width: s, height: s))
        .draw(in: NSRect(x: 0, y: 0, width: s, height: s), from: .zero, operation: .sourceOver, fraction: 0.55)
    let source = u(s, l, 0.5, 1.08)
    NSGradient(colors: [green.withAlphaComponent(0.16), green.withAlphaComponent(0)])!
        .draw(fromCenter: source, radius: 0, toCenter: source, radius: body(s, l).width * 0.55, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // The answer: the site's ✓ (Lucide "check"), off-white, with a faint green halo at Dock sizes.
    NSGraphicsContext.saveGraphicsState()
    if s >= 64 { let g = NSShadow(); g.shadowColor = green.withAlphaComponent(0.35); g.shadowBlurRadius = s * 0.03; g.shadowOffset = .zero; g.set() }
    let c = u(s, l, 0.5, 0.44), w = body(s, l).width * 0.52
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: c.x + w * (x - 12) / 24, y: c.y - w * (y - 12) / 24) }
    let check = NSBezierPath()
    check.move(to: pt(4.5, 12.5)); check.line(to: pt(9.5, 17.5)); check.line(to: pt(19.5, 6.5))
    check.lineWidth = max(1.8, s * (s <= 32 ? 0.09 : 0.062)) // heavier when small, so it survives 16px
    check.lineCapStyle = .round; check.lineJoinStyle = .round
    NSColor(white: 0.95, alpha: 1).setStroke(); check.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func write(_ px: Int, _ l: Layout, _ path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set(); NSRect(x: 0, y: 0, width: px, height: px).fill(using: .copy) // new reps aren't transparent
    draw(CGFloat(px), l)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let set = "app/Resources/Assets.xcassets/AppIcon.appiconset"
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    write(points * scale, .mac, "\(set)/icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png")
}
write(16, .tight, "site/public/icon-16.png")
write(32, .tight, "site/public/icon-32.png")
write(192, .tight, "site/public/icon-192.png")
write(512, .tight, "site/public/icon-512.png")
write(180, .bleed, "site/public/apple-touch-icon.png")
print("wrote 10 app icon sizes and 5 site icons")
