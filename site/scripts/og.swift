// Draws the share image (1200x630, shipped as public/og.jpg): the hero's real vgpu light (green, "live") with the headline over it.
// The light comes from the shader itself, rendered headlessly:
//   node scripts/render-light.mjs /tmp/og-light 1200 630
//   swiftc scripts/og.swift -o /tmp/og && /tmp/og /tmp/og-light/light-live.png /tmp/og.png
//   sips -s format jpeg -s formatOptions 90 /tmp/og.png --out public/og.jpg
import AppKit

let args = CommandLine.arguments
let background = NSImage(contentsOfFile: args[1])!
let W = 1200.0, H = 630.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

background.draw(in: NSRect(x: 0, y: 0, width: W, height: H))

let ink = NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
let muted = NSColor(red: 0.70, green: 0.71, blue: 0.75, alpha: 1)
let green = NSColor(srgbRed: 0.379, green: 0.797, blue: 0.488, alpha: 1) // --color-ship

func centered(_ s: String, size: Double, weight: NSFont.Weight, color: NSColor, y: Double, kern: Double) {
    let text = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: kern])
    text.draw(at: NSPoint(x: (W - text.size().width) / 2, y: y))
}

// App mark and name, top centre.
let iconSize = 56.0
let name = NSAttributedString(string: "Deployed Yet?", attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: ink, .kern: -0.4])
let rowWidth = iconSize + 14 + name.size().width
let rowX = (W - rowWidth) / 2
// The nav's ✓ chip, so the card matches the site (the app icon is a separate thing).
let mark = NSRect(x: rowX, y: 470, width: iconSize, height: iconSize)
green.withAlphaComponent(0.16).setFill(); NSBezierPath(ovalIn: mark).fill()
func tickPoint(_ x: Double, _ y: Double) -> NSPoint {
    NSPoint(x: mark.minX + mark.width * (0.2 + 0.6 * x / 24), y: mark.maxY - mark.height * (0.2 + 0.6 * y / 24))
}
let tick = NSBezierPath()
tick.move(to: tickPoint(4.5, 12.5)); tick.line(to: tickPoint(9.5, 17.5)); tick.line(to: tickPoint(19.5, 6.5))
tick.lineWidth = 4.4; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
green.setStroke(); tick.stroke()
name.draw(at: NSPoint(x: rowX + iconSize + 14, y: 470 + (iconSize - name.size().height) / 2))

// The claim, tight and medium like the site.
centered("Your menu bar knows", size: 76, weight: .semibold, color: ink, y: 330, kern: -3.6)
centered("if it shipped.", size: 76, weight: .semibold, color: ink, y: 248, kern: -3.6)

// A finished deploy, the ticker's last frame.
let chipText = NSAttributedString(string: "✓  Live in 31s", attributes: [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: green])
let chip = NSRect(x: (W - chipText.size().width - 44) / 2, y: 150, width: chipText.size().width + 44, height: 52)
NSColor(srgbRed: 0.089, green: 0.095, blue: 0.108, alpha: 0.94).setFill() // --color-tile, like the ticker card
NSBezierPath(roundedRect: chip, xRadius: 14, yRadius: 14).fill()
NSColor(white: 1, alpha: 0.10).setStroke()
let edge = NSBezierPath(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
edge.lineWidth = 1
edge.stroke()
chipText.draw(at: NSPoint(x: chip.minX + 22, y: chip.minY + (chip.height - chipText.size().height) / 2))

centered("Vercel, Cloudflare and GitHub Actions. Free for Mac.", size: 24, weight: .regular, color: muted, y: 80, kern: 0)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
