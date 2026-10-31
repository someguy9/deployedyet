import SwiftUI

@main
struct DeployedYetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        let store = delegate.store
        let shows = store.showsIcon // read here, in body, so SwiftUI tracks it
        // isInserted lets the icon step out of the menu bar when "only while building or failed" is on.
        // ⌘-dragging it out of the menu bar means the same thing: hide until something needs a look.
        MenuBarExtra(isInserted: Binding(get: { shows }, set: { if !$0 { store.iconOnlyWhenBusy = true } })) {
            MenuView().environment(store)
        } label: {
            Image(nsImage: store.monitoringDegraded
                ? Glyph.image(.failed, frame: 0, style: store.iconStyle, color: store.iconColor, fresh: false)
                : (store.morph.map { Glyph.morph(to: $0.to, frame: $0.frame, style: store.iconStyle, color: store.iconColor) }
                    ?? Glyph.image(store.overall, frame: store.wobbleFrame, style: store.iconStyle, color: store.iconColor, fresh: store.freshLanding)))
                .accessibilityLabel(store.headline)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Analytics.shared.start { [weak store] in
            .init(accounts: store?.accounts.count ?? 0, projects: store?.selected.count ?? 0)
        }
        Updater.shared.start(store: store)
        for (name, sleeping) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Analytics.shared.setSleeping(sleeping) }
            }
        }
        // The MenuBarExtra's window is a panel and is key while the menu is open (Settings is a plain window).
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [store] note in
            guard note.object is NSPanel else { return }
            MainActor.assumeIsolated { store.menuOpen = true }
        }
        center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [store] note in
            guard note.object is NSPanel else { return }
            MainActor.assumeIsolated { store.menuOpen = false }
        }
        // First launch ever: nothing to show in the menu yet, so open Settings on Add Account.
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            if store.accounts.isEmpty { SettingsWindow.show(store) }
        }
    }

    /// Opening the app again (Spotlight, Finder, Dock) is how you reach Settings while the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindow.show(store)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Analytics.shared.stop()
    }
}

/// Settings in a plain AppKit window, so anything (first run, reopen, the menu) can open it.
/// SwiftUI's Settings scene can only be opened from inside a view, and not at all while the icon is hidden.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(_ store: Store) {
        Analytics.shared.capture(.settingsOpened)
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environment(store))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.title = "Deployed Yet? Settings"
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 860, height: 620))
            w.center()
            w.setFrameAutosaveName("DeployedYetSettings")
            // The window is kept, not released, so its views may never disappear: settle half-typed names on close.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated { store.accounts.forEach { store.finishRename($0.id) } }
            }
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    static func setTitle(_ title: String) {
        window?.title = title
    }
}

/// The name asks "Deployed yet?", the glyph answers: ? building, ✓ live, ! failed.
/// When a build lands, the ? morphs into the answer. Pre-rendered images, since the menu bar ignores SwiftUI transforms.
@MainActor
enum Glyph {
    static let wobbleFrames = 12
    static let morphFrames = 9

    private struct Layer {
        var symbol: String
        var degrees = 0.0
        var alpha = 1.0
        var scale = 1.0
    }

    private static var cache: [String: NSImage] = [:]
    private static var bases: [String: NSImage] = [:]

    static func image(_ state: DeployState?, frame: Int, style: IconStyle, color: IconColor, fresh: Bool) -> NSImage {
        let symbol = style.symbol(state)
        switch state {
        case nil: return render("idle\(symbol)", [Layer(symbol: symbol, alpha: 0.45)], tint: nil)
        case .building:
            let i = frame % wobbleFrames
            let degrees = 14 * sin(2 * .pi * Double(i) / Double(wobbleFrames))
            return render("wobble\(i)\(symbol)\(color)", [Layer(symbol: symbol, degrees: degrees)], tint: tint(.building, color))
        case .failed: return render("failed\(symbol)\(color)", [Layer(symbol: symbol)], tint: tint(.failed, color))
        case .ready, .canceled: return render("ready\(symbol)\(color)\(fresh)", [Layer(symbol: symbol)], tint: tint(.ready, color, fresh: fresh))
        }
    }

    /// The building symbol shrinks and tips away while the answer grows in with a little overshoot.
    static func morph(to state: DeployState, frame: Int, style: IconStyle, color: IconColor) -> NSImage {
        let t = Double(min(frame, morphFrames - 1) + 1) / Double(morphFrames)
        let ease = 1 - pow(1 - t, 3) // ease-out cubic
        let target = style.symbol(state)
        let grow = 0.55 + 0.45 * ease + 0.12 * sin(.pi * t) // overshoot mid-way, settle at 1
        return render("morph\(target)\(frame)\(color)", [
            Layer(symbol: style.symbol(.building), degrees: 25 * ease, alpha: 1 - ease, scale: 1 - 0.45 * ease),
            Layer(symbol: target, alpha: ease, scale: grow),
        ], tint: tint(state, color, fresh: true)) // the morph only plays as a build lands
    }

    /// The same colors as the menu: amber building, green live, red failed. nil keeps the menu bar's own ink.
    /// Automatic greens a ✓ only while it's fresh (a few minutes after landing); building and failed always show.
    private static func tint(_ state: DeployState, _ color: IconColor, fresh: Bool = false) -> NSColor? {
        let full: NSColor = state == .building ? .systemOrange : state == .failed ? .systemRed : .systemGreen
        switch color {
        case .never: return nil
        case .automatic: return state == .ready && !fresh ? nil : full
        case .always: return full
        }
    }

    private static func render(_ key: String, _ layers: [Layer], tint: NSColor?) -> NSImage {
        if let hit = cache[key] { return hit }
        let parts = layers.map { (layer: $0, base: base($0.symbol)) }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            for (layer, base) in parts {
                NSGraphicsContext.saveGraphicsState()
                let t = NSAffineTransform()
                t.translateX(by: rect.midX, yBy: rect.minY + 3) // pivot at the base, like a head tilt
                t.rotate(byDegrees: layer.degrees)
                t.scale(by: layer.scale)
                t.translateX(by: -rect.midX, yBy: -(rect.minY + 3))
                t.concat()
                let s = base.size
                base.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                          from: .zero, operation: .sourceOver, fraction: layer.alpha)
                NSGraphicsContext.restoreGraphicsState()
            }
            if let tint {
                tint.set()
                rect.fill(using: .sourceAtop)
            }
            return true
        }
        image.isTemplate = tint == nil
        cache[key] = image
        return image
    }

    /// Symbol supersampled to a 4x bitmap; drawing a symbol image rotated otherwise rasterizes at 1x and goes blurry.
    private static func base(_ name: String) -> NSImage {
        if let hit = bases[name] { return hit }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
        let s = symbol.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s.width * 4), pixelsHigh: Int(s.height * 4),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = s
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        symbol.draw(in: NSRect(origin: .zero, size: s))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: s)
        image.addRepresentation(rep)
        bases[name] = image
        return image
    }
}
