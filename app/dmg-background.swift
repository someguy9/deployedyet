// Draws the DMG window background (640x400pt at 1x and 2x): the site's near-black, a soft green light from above,
// and an arrow from the app to Applications. release.sh runs it and packs both into one Retina TIFF.
// Usage: swift app/dmg-background.swift <out-1x.png> <out-2x.png>
import AppKit

let W = 640.0, H = 400.0
let green = NSColor(srgbRed: 0.379, green: 0.797, blue: 0.488, alpha: 1) // the site's --color-ship
// Finder puts icon centres at y = 190 from the top (release.sh sets the same positions).
let iconY = H - 190, appX = 170.0, appsX = 470.0

func draw(scale: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H) // draw in points; the rep holds the pixels
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let all = NSRect(x: 0, y: 0, width: W, height: H)
    NSGradient(colors: [NSColor(srgbRed: 0.111, green: 0.118, blue: 0.133, alpha: 1),
                        NSColor(srgbRed: 0.043, green: 0.048, blue: 0.058, alpha: 1)])!.draw(in: all, angle: -90)
    let source = NSPoint(x: W / 2, y: H + 40)
    NSGradient(colors: [green.withAlphaComponent(0.2), green.withAlphaComponent(0)])!
        .draw(fromCenter: source, radius: 0, toCenter: source, radius: 330, options: [])

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: appX + 92, y: iconY)); arrow.line(to: NSPoint(x: appsX - 92, y: iconY))
    arrow.move(to: NSPoint(x: appsX - 104, y: iconY + 10)); arrow.line(to: NSPoint(x: appsX - 92, y: iconY)); arrow.line(to: NSPoint(x: appsX - 104, y: iconY - 10))
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.35).setStroke(); arrow.stroke()

    let caption = NSAttributedString(string: "Drag Deployed Yet? into Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.5)])
    caption.draw(at: NSPoint(x: (W - caption.size().width) / 2, y: 40))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let args = CommandLine.arguments
draw(scale: 1, to: args[1])
draw(scale: 2, to: args[2])
