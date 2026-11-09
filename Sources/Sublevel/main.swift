import AppKit
import MetalKit

enum IconsetExporter {
    static func exportIconset(to folderPath: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

        let specs: [(name: String, pixels: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for spec in specs {
            let data = try renderIconPNG(size: spec.pixels)
            let url = URL(fileURLWithPath: folderPath).appendingPathComponent(spec.name)
            try data.write(to: url)
        }
    }

    private static func renderIconPNG(size: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
            throw NSError(domain: "SublevelIcon", code: 1)
        }

        let s = CGFloat(size)
        let pad = s * 0.08
        let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
        let corner = s * 0.22

        // Rounded squircle background (Stark White architectural concrete #F4F5F7)
        let bgPath = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        ctx.addPath(bgPath)
        ctx.clip()

        ctx.setFillColor(CGColor(red: 0.957, green: 0.961, blue: 0.969, alpha: 1.0))
        ctx.fill(rect)

        // Three descending brutalist strata bars (B1 White/Slate, B2 Signal Red, B3 Cobalt Blue)
        // Stratum B1 (Top architectural beam)
        ctx.setFillColor(CGColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0))
        ctx.fill(CGRect(x: s * 0.20, y: s * 0.64, width: s * 0.60, height: s * 0.11))

        // Stratum B2 (Middle Signal Red #FF2A19 kinetic ramp)
        ctx.setFillColor(CGColor(red: 1.0, green: 0.165, blue: 0.098, alpha: 1.0))
        ctx.fill(CGRect(x: s * 0.26, y: s * 0.45, width: s * 0.54, height: s * 0.11))

        // Stratum B3 (Lower Cobalt Blue #0057FF Sump core)
        ctx.setFillColor(CGColor(red: 0.0, green: 0.341, blue: 1.0, alpha: 1.0))
        ctx.fill(CGRect(x: s * 0.20, y: s * 0.26, width: s * 0.48, height: s * 0.11))

        // Electric Cyan Shock Orb accent in bottom-right
        ctx.setFillColor(CGColor(red: 0.0, green: 0.941, blue: 1.0, alpha: 1.0))
        ctx.fillEllipse(in: CGRect(x: s * 0.68, y: s * 0.24, width: s * 0.14, height: s * 0.14))

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SublevelIcon", code: 2)
        }
        return png
    }
}

final class SublevelAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var gameView: SublevelGameView!
    private var renderer: MetalArenaRenderer!
    private let simulation = SublevelSimulation()
    private let audioEngine = AudioSynthEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        let rect = NSRect(x: 0, y: 0, width: 1360, height: 840)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sublevel — SL_ATRIUM (B1 // B2 // B3)"
        window.center()
        window.delegate = self
        window.collectionBehavior = [.fullScreenPrimary]
        window.acceptsMouseMovedEvents = true

        gameView = SublevelGameView(frame: rect, device: MTLCreateSystemDefaultDevice())
        gameView.autoresizingMask = [.width, .height]

        guard let metalRenderer = MetalArenaRenderer(mtkView: gameView, simulation: simulation, audioEngine: audioEngine) else {
            fatalError("Metal device unavailable on this Mac.")
        }
        renderer = metalRenderer
        gameView.configure(renderer: metalRenderer)

        window.contentView = gameView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(gameView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        gameView?.setMouseCaptured(false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func resetMatchAction() {
        simulation.resetMatch()
    }

    @objc private func toggleBotsAction() {
        simulation.botsEnabled.toggle()
    }

    @objc private func toggleMuteAction() {
        audioEngine.isMuted.toggle()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Reset Arena & Breaches", action: #selector(resetMatchAction), keyEquivalent: "r")
        appMenu.addItem(withTitle: "Toggle Arena Bots", action: #selector(toggleBotsAction), keyEquivalent: "b")
        appMenu.addItem(withTitle: "Mute / Unmute Synth Audio", action: #selector(toggleMuteAction), keyEquivalent: "m")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Sublevel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }
}

// Entrypoint handling CLI flags or launching the macOS application
let args = CommandLine.arguments
if let idx = args.firstIndex(of: "--export-iconset"), idx + 1 < args.count {
    try IconsetExporter.exportIconset(to: args[idx + 1])
    exit(0)
}
if args.contains("--self-test-metal") {
    let sim = SublevelSimulation()
    let audio = AudioSynthEngine()
    audio.isMuted = true
    let view = SublevelGameView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), device: MTLCreateSystemDefaultDevice())
    guard let renderer = MetalArenaRenderer(mtkView: view, simulation: sim, audioEngine: audio) else {
        fputs("Metal initialization failed\n", stderr)
        exit(1)
    }
    view.drawableSize = CGSize(width: 640, height: 480)
    view.configure(renderer: renderer)
    for _ in 0..<10 {
        renderer.draw(in: view)
    }
    print("Metal shader pipeline and 10 simulation frames verified successfully on \(renderer.device.name).")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = SublevelAppDelegate()
app.delegate = delegate
app.run()
