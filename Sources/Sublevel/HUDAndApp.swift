import AppKit
import MetalKit
import simd

/// Interactive MTKView handling Mouse-Look, Double-Tap Directional Dodge (UT99), Scroll/Number Weapon Switching, and HUD Overlay
public final class SublevelGameView: MTKView {
    public var renderer: MetalArenaRenderer!
    public let hudView = SublevelHUDOverlayView()
    private var isMouseCaptured: Bool = false {
        didSet {
            hudView.isMouseCaptured = isMouseCaptured
            hudView.needsDisplay = true
        }
    }

    // UT99 Double-Tap Directional Dodge Detector (WASD double-tap within 0.26s)
    private var lastTapKeyTime: [UInt16: CFTimeInterval] = [:]
    private let doubleTapWindow: CFTimeInterval = 0.26

    public override var acceptsFirstResponder: Bool { true }

    public func configure(renderer: MetalArenaRenderer) {
        self.renderer = renderer
        self.delegate = renderer

        hudView.frame = bounds
        hudView.autoresizingMask = [.width, .height]
        hudView.simulation = renderer.simulation
        hudView.audioEngine = renderer.audioEngine
        hudView.renderer = renderer
        addSubview(hudView)

        renderer.onFrameUpdated = { [weak self] in
            self?.hudView.needsDisplay = true
        }

        updateTrackingAreas()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    public func setMouseCaptured(_ captured: Bool) {
        guard isMouseCaptured != captured else { return }
        isMouseCaptured = captured
        CGAssociateMouseAndMouseCursorPosition(captured ? 0 : 1)
        if captured {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
            hudView.showScoreboard = false
            renderer?.keysHeld.removeAll()
            renderer?.primaryFireHeld = false
            renderer?.altFireHeld = false
        }
        hudView.needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if !isMouseCaptured {
            setMouseCaptured(true)
            return
        }
        renderer.primaryFireHeld = true
    }

    public override func mouseUp(with event: NSEvent) {
        renderer.primaryFireHeld = false
    }

    public override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if !isMouseCaptured {
            setMouseCaptured(true)
            return
        }
        renderer.altFireHeld = true
    }

    public override func rightMouseUp(with event: NSEvent) {
        if renderer.altFireHeld {
            renderer.altFireJustReleased = true
        }
        renderer.altFireHeld = false
    }

    public override func mouseMoved(with event: NSEvent) {
        handleMouseDelta(event)
    }

    public override func mouseDragged(with event: NSEvent) {
        handleMouseDelta(event)
    }

    public override func rightMouseDragged(with event: NSEvent) {
        handleMouseDelta(event)
    }

    private func handleMouseDelta(_ event: NSEvent) {
        guard isMouseCaptured else { return }
        let sens: Float = renderer.simulation.isSubRailZoomed ? 0.0014 : 0.0030
        renderer.simulation.playerYaw -= Float(event.deltaX) * sens
        renderer.simulation.playerPitch = simd_clamp(
            renderer.simulation.playerPitch - Float(event.deltaY) * sens,
            -1.48,
            1.48
        )
    }

    public override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 0.1 else { return }
        let slots = WeaponSlot.allCases
        guard let idx = slots.firstIndex(of: renderer.simulation.currentWeapon) else { return }
        let step = event.scrollingDeltaY > 0 ? -1 : 1
        let nextIdx = (idx + step + slots.count) % slots.count
        renderer.simulation.currentWeapon = slots[nextIdx]
    }

    public override func keyDown(with event: NSEvent) {
        let code = event.keyCode

        // ESC (53) releases mouse capture
        if code == 53 {
            setMouseCaptured(false)
            return
        }

        if !event.isARepeat {
            // Check UT99 Double-Tap on W (13), A (0), S (1), D (2)
            if let dir = Self.localDodgeDir(forKeyCode: code) {
                let now = CACurrentMediaTime()
                if let prev = lastTapKeyTime[code], (now - prev) <= doubleTapWindow {
                    renderer.dodgeRequested = true
                    renderer.dodgeDirectionLocal = dir
                    lastTapKeyTime[code] = 0
                } else {
                    lastTapKeyTime[code] = now
                }
            }

            switch code {
            case 49: // Space (Jump + Auto-hop on hold)
                renderer.jumpJustPressed = true
            case 56, 60, 9: // Shift or V (Dedicated Dodge key)
                renderer.dodgeRequested = true
                renderer.dodgeDirectionLocal = .zero
            case 18: renderer.simulation.currentWeapon = .kineticGauntlet // 1
            case 19: renderer.simulation.currentWeapon = .prismRifle      // 2
            case 20: renderer.simulation.currentWeapon = .shardCannon     // 3
            case 21: renderer.simulation.currentWeapon = .vectorLauncher  // 4
            case 23: renderer.simulation.currentWeapon = .subRail         // 5
            case 14: // E = Alt-Fire key (convenient for trackpad users!)
                renderer.altFireHeld = true
            case 12: // Q = Cycle weapon
                let slots = WeaponSlot.allCases
                if let idx = slots.firstIndex(of: renderer.simulation.currentWeapon) {
                    renderer.simulation.currentWeapon = slots[(idx + 1) % slots.count]
                }
            case 15: // R = Reset Match & Dynamic Breaches
                renderer.simulation.resetMatch()
            case 11: // B = Toggle Arena Bots
                renderer.simulation.botsEnabled.toggle()
            case 46: // M = Mute/Unmute Audio
                renderer.audioEngine.isMuted.toggle()
            case 4: // H = Toggle Help Overlay
                hudView.showHelpOverlay.toggle()
                hudView.needsDisplay = true
            case 48: // Tab (hold) = Scoreboard
                hudView.showScoreboard = true
                hudView.needsDisplay = true
            default:
                break
            }
        }

        renderer.keysHeld.insert(code)
    }

    public override func keyUp(with event: NSEvent) {
        let code = event.keyCode
        renderer.keysHeld.remove(code)
        if code == 48 {
            hudView.showScoreboard = false
            hudView.needsDisplay = true
        }
        if code == 14 { // E Alt-Fire release
            if renderer.altFireHeld {
                renderer.altFireJustReleased = true
            }
            renderer.altFireHeld = false
        }
    }

    public override func flagsChanged(with event: NSEvent) {
        // Handle Shift (dodge) and Control (crouch/slam/slide) modifier flags cleanly
        if event.modifierFlags.contains(.shift) {
            if !renderer.keysHeld.contains(56) {
                renderer.keysHeld.insert(56)
                renderer.dodgeRequested = true
                renderer.dodgeDirectionLocal = .zero
            }
        } else {
            renderer.keysHeld.remove(56)
        }

        if event.modifierFlags.contains(.control) {
            renderer.keysHeld.insert(59)
        } else {
            renderer.keysHeld.remove(59)
        }
    }

    private static func localDodgeDir(forKeyCode code: UInt16) -> SIMD2<Float>? {
        switch code {
        case 13: return SIMD2<Float>(0, 1)   // W
        case 1:  return SIMD2<Float>(0, -1)  // S
        case 0:  return SIMD2<Float>(-1, 0)  // A
        case 2:  return SIMD2<Float>(1, 0)   // D
        default: return nil
        }
    }
}

/// Minimalist High-Contrast Diegetic HUD (Speedometer u/s, Sublevel Flow Multiplier, Crosshairs, Strata & Arsenal)
public final class SublevelHUDOverlayView: NSView {
    public weak var simulation: SublevelSimulation?
    public weak var audioEngine: AudioSynthEngine?
    public weak var renderer: MetalArenaRenderer?
    public var isMouseCaptured: Bool = false
    public var showHelpOverlay: Bool = false
    public var showScoreboard: Bool = false

    // Cache HUD fonts so we do not re-create 30+ NSFont instances per frame at 120 FPS
    private static let fontDigit24Black = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .black)
    private static let fontDigit22Black = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .black)
    private static let fontDigit20Black = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .black)
    private static let fontDigit16Bold = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .bold)
    private static let fontDigit13Black = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .black)
    private static let fontDigit13Semibold = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    private static let fontDigit11Bold = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
    private static let fontDigit11Semibold = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let fontDigit10Bold = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)

    private static let fontMono16Black = NSFont.monospacedSystemFont(ofSize: 16, weight: .black)
    private static let fontMono15Black = NSFont.monospacedSystemFont(ofSize: 15, weight: .black)
    private static let fontMono11_5Semibold = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
    private static let fontMono11Black = NSFont.monospacedSystemFont(ofSize: 11, weight: .black)
    private static let fontMono11Medium = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    private static let fontMono10_5Semibold = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold)
    private static let fontMono10Bold = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
    private static let fontMono9_5Semibold = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold)
    private static let fontMono9_5Medium = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func draw(_ dirtyRect: NSRect) {
        guard let sim = simulation, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height
        guard w > 1, h > 1 else { return }
        let center = CGPoint(x: w * 0.5, y: h * 0.5)

        // 1. Damage / Powerup Vignette Flash
        if sim.cameraFX.damageFlash > 0.01 {
            ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.12, blue: 0.08, alpha: CGFloat(sim.cameraFX.damageFlash * 0.35)).cgColor)
            ctx.fill(bounds)
        }
        if sim.isSubRailZoomed {
            // Sub-Rail Cobalt Violet Scope Overlay
            ctx.setStrokeColor(NSColor(calibratedRed: 0.52, green: 0.18, blue: 1.0, alpha: 0.65).cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: center.x - 210, y: center.y - 210, width: 420, height: 420))
        }

        // 2. High-Contrast Weapon Crosshair
        if !showScoreboard {
            drawCrosshair(ctx: ctx, center: center, weapon: sim.currentWeapon, charge: sim.rocketChargeCount)
        }

        // 3. Diegetic Speedometer (u/s) & Momentum Bar (Bottom-Center above Weapon Bar)
        let ups = Int(sim.playerKinematic.speedUPS.rounded())
        let peakUps = Int(sim.peakSpeedUPS.rounded())
        let speedRatio = CGFloat(min(sim.playerKinematic.speedUPS / 750.0, 1.0))
        let speedColor = ups >= 450
            ? NSColor(calibratedRed: 1.0, green: 0.165, blue: 0.098, alpha: 1.0)
            : (ups >= 330 ? NSColor(calibratedRed: 0.0, green: 0.94, blue: 1.0, alpha: 1.0) : NSColor.white)

        drawPanel(ctx: ctx, rect: CGRect(x: center.x - 125, y: 82, width: 250, height: 56), accent: speedColor)
        drawText(
            "\(ups) u/s",
            at: CGPoint(x: center.x - 110, y: 106),
            font: Self.fontDigit22Black,
            color: speedColor
        )
        drawText(
            "PEAK \(peakUps) // \(sim.playerKinematic.isOnFloor ? (sim.playerKinematic.isSliding ? "SLIDE" : "GROUND") : "AIRBORNE")",
            at: CGPoint(x: center.x - 110, y: 89),
            font: Self.fontMono10Bold,
            color: NSColor(white: 0.82, alpha: 1.0)
        )
        // Speed gauge bar
        ctx.setFillColor(NSColor(white: 1.0, alpha: 0.16).cgColor)
        ctx.fill(CGRect(x: center.x + 25, y: 112, width: 88, height: 8))
        ctx.setFillColor(speedColor.cgColor)
        ctx.fill(CGRect(x: center.x + 25, y: 112, width: 88 * speedRatio, height: 8))

        // 4. Bottom-Left: Health, Armor & Powerups
        let hpCol = sim.playerHealth > 35
            ? NSColor.white
            : NSColor(calibratedRed: 1.0, green: 0.165, blue: 0.098, alpha: 1.0)
        drawPanel(ctx: ctx, rect: CGRect(x: 24, y: 22, width: 250, height: 64), accent: hpCol)
        drawText(
            "HP \(Int(ceil(sim.playerHealth)))",
            at: CGPoint(x: 38, y: 50),
            font: Self.fontDigit24Black,
            color: hpCol
        )
        drawText(
            "ARMOR \(Int(ceil(sim.playerArmor)))",
            at: CGPoint(x: 152, y: 54),
            font: Self.fontDigit16Bold,
            color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
        )
        let dodgeReady = sim.playerKinematic.dodgeCooldownTimer <= 0.0
            ? "DODGE READY [2-WALL: \(2 - sim.playerKinematic.wallDodgesUsed)]"
            : String(format: "DODGE %.1fs", sim.playerKinematic.dodgeCooldownTimer)
        drawText(
            dodgeReady,
            at: CGPoint(x: 38, y: 30),
            font: Self.fontMono10_5Semibold,
            color: NSColor(white: 0.80, alpha: 1.0)
        )

        // Active Powerup badges
        if sim.quadOverdriveTimer > 0 {
            drawText(
                String(format: "QUAD OVERDRIVE 3X [%.1fs]", sim.quadOverdriveTimer),
                at: CGPoint(x: 28, y: 96),
                font: Self.fontDigit13Black,
                color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
            )
        }
        if sim.subShieldTimer > 0 {
            drawText(
                String(format: "SUB-SHIELD INVULN [%.1fs]", sim.subShieldTimer),
                at: CGPoint(x: 28, y: 116),
                font: Self.fontDigit13Black,
                color: NSColor(calibratedRed: 0.25, green: 0.65, blue: 1.0, alpha: 1.0)
            )
        }

        // 5. Bottom-Center: 5-Weapon Arsenal Bar
        let barW: CGFloat = 510
        let startX = center.x - barW * 0.5
        for (i, slot) in WeaponSlot.allCases.enumerated() {
            let isSelected = (slot == sim.currentWeapon)
            let slotX = startX + CGFloat(i) * 104
            let c = slot.accentColor
            let nsCol = NSColor(calibratedRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1.0)
            drawPanel(
                ctx: ctx,
                rect: CGRect(x: slotX, y: 22, width: 96, height: isSelected ? 48 : 38),
                accent: isSelected ? nsCol : NSColor(white: 0.45, alpha: 0.7)
            )
            drawText(
                "[\(slot.rawValue)] \(slot.shortName)",
                at: CGPoint(x: slotX + 10, y: isSelected ? 44 : 36),
                font: isSelected ? Self.fontMono11Black : Self.fontMono11Medium,
                color: isSelected ? nsCol : NSColor(white: 0.85, alpha: 0.85)
            )
            if isSelected {
                drawText(
                    "LMB / RMB",
                    at: CGPoint(x: slotX + 10, y: 28),
                    font: Self.fontMono9_5Semibold,
                    color: NSColor(white: 0.75, alpha: 1.0)
                )
            }
        }

        // 6. Top-Left: Stratum Depth Indicator (B1 -> B2 -> B3) & Match Scoreboard
        let stratum = sim.playerStratum
        let stratumColor: NSColor = {
            switch stratum {
            case .b1Atrium:    return .white
            case .b2Concourse: return NSColor(calibratedRed: 1.0, green: 0.165, blue: 0.098, alpha: 1.0)
            case .b3Sump:      return NSColor(calibratedRed: 0.15, green: 0.55, blue: 1.0, alpha: 1.0)
            }
        }()
        drawPanel(ctx: ctx, rect: CGRect(x: 24, y: h - 94, width: 315, height: 70), accent: stratumColor)
        drawText(
            "STRATUM \(stratum.code)",
            at: CGPoint(x: 38, y: h - 52),
            font: Self.fontMono15Black,
            color: stratumColor
        )
        let totalBreaches = sim.arena.colliders.filter { $0.kind == .shatterFloor }.count
        let intactBreaches = sim.arena.colliders.filter { $0.kind == .shatterFloor && !$0.isDestroyed }.count
        let polyK = max(1, (renderer?.lastFrameTriangleCount ?? 0) / 1000)
        drawText(
            String(format: "ELEV %.1fm  |  PLATES %d/%d  |  %dK POLYS", sim.playerKinematic.position.y, intactBreaches, totalBreaches, polyK),
            at: CGPoint(x: 38, y: h - 72),
            font: Self.fontDigit11Semibold,
            color: NSColor(white: 0.88, alpha: 1.0)
        )
        drawText(
            "REVERB WET: \(Int(stratum.reverbWetMix))%  |  [TAB] SCORES  [H] HELP",
            at: CGPoint(x: 38, y: h - 88),
            font: Self.fontMono9_5Medium,
            color: NSColor(white: 0.68, alpha: 1.0)
        )

        // 7. Top-Right: Sublevel Flow Multiplier, Frags & Style Feed
        let flowCol = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
        drawPanel(ctx: ctx, rect: CGRect(x: w - 284, y: h - 94, width: 260, height: 70), accent: flowCol)
        drawText(
            String(format: "FLOW %.2fX", sim.flowMultiplier),
            at: CGPoint(x: w - 270, y: h - 52),
            font: Self.fontDigit20Black,
            color: flowCol
        )
        drawText(
            "FRAGS \(sim.playerFrags)/\(sim.fragLimit)  |  COMBOS \(sim.totalShockCombos)  |  MULTI-LVL \(sim.totalMultiStratumKills)",
            at: CGPoint(x: w - 270, y: h - 76),
            font: Self.fontDigit10Bold,
            color: .white
        )

        // Style Feed Notifications
        for (idx, item) in sim.styleFeed.enumerated() {
            let y = h - 132 - CGFloat(idx) * 38
            let alpha = CGFloat(min(1.0, item.remainingTime))
            let c = NSColor(
                calibratedRed: CGFloat(item.color.x),
                green: CGFloat(item.color.y),
                blue: CGFloat(item.color.z),
                alpha: alpha
            )
            drawPanel(ctx: ctx, rect: CGRect(x: w - 390, y: y, width: 366, height: 32), accent: c)
            drawText(
                "\(item.title) — \(item.subtitle)",
                at: CGPoint(x: w - 378, y: y + 9),
                font: Self.fontMono10Bold,
                color: c
            )
        }

        // 8. Click-to-Capture or Help Banner, otherwise the Tab scoreboard
        if !isMouseCaptured || showHelpOverlay {
            drawHelpModal(ctx: ctx, center: center)
        } else if showScoreboard {
            drawScoreboard(ctx: ctx, center: center, sim: sim)
        }
    }

    private func drawCrosshair(ctx: CGContext, center: CGPoint, weapon: WeaponSlot, charge: Int) {
        let c = weapon.accentColor
        let col = NSColor(calibratedRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 0.95)
        ctx.setStrokeColor(col.cgColor)
        ctx.setFillColor(col.cgColor)
        ctx.setLineWidth(2.0)

        let gap: CGFloat = 6
        let len: CGFloat = 11
        ctx.move(to: CGPoint(x: center.x - gap - len, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x - gap, y: center.y))
        ctx.move(to: CGPoint(x: center.x + gap, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x + gap + len, y: center.y))
        ctx.move(to: CGPoint(x: center.x, y: center.y - gap - len))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y - gap))
        ctx.move(to: CGPoint(x: center.x, y: center.y + gap))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y + gap + len))
        ctx.strokePath()

        ctx.fillEllipse(in: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))

        if weapon == .prismRifle {
            ctx.strokeEllipse(in: CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28))
        } else if weapon == .vectorLauncher && charge > 0 {
            for i in 0..<charge {
                ctx.fill(CGRect(x: center.x - 14 + CGFloat(i) * 11, y: center.y - 24, width: 7, height: 4))
            }
        }
    }

    private func drawHelpModal(ctx: CGContext, center: CGPoint) {
        let box = CGRect(x: center.x - 265, y: center.y - 165, width: 530, height: 330)
        drawPanel(ctx: ctx, rect: box, accent: NSColor(calibratedRed: 1.0, green: 0.165, blue: 0.098, alpha: 1.0))

        let lines: [(String, Bool)] = [
            ("SUBLEVEL // HYPER-KINETIC BRUTALIST ARENA", true),
            (isMouseCaptured ? "CONTROLS & MECHANICS REFERENCE" : "CLICK ANYWHERE IN THE ARENA TO LOCK MOUSE & PLAY", false),
            ("", false),
            ("WASD + MOUSE       Move & Aim (Strafe-Jump in air for uncapped u/s)", false),
            ("HOLD SPACE         Auto-Hop (skips ground friction) + Ramp Trimping", false),
            ("DOUBLE-TAP WASD    UT99 Directional Dodge & Airborne Wall-Dodge (Shift/V)", false),
            ("HOLD CTRL / C      Airborne Sublevel Slam (2.2x grav) / Ground Crouch-Slide", false),
            ("LMB / RMB (or E)   Primary Fire / Alt-Fire (Weapon Combos)", false),
            ("KEYS 1 - 5 / Q     1:Gauntlet  2:Prism(Shock Combo)  3:Shard  4:Vector  5:Sub-Rail", false),
            ("R / B / M / ESC    R:Reset Match  B:Toggle Bots  M:Mute  ESC:Release Cursor", false),
            ("HOLD TAB / H       Scoreboard / Toggle this Help Overlay", false)
        ]

        for (i, entry) in lines.enumerated() where !entry.0.isEmpty {
            let y = box.maxY - 38 - CGFloat(i) * 27
            drawText(
                entry.0,
                at: CGPoint(x: box.minX + 24, y: y),
                font: entry.1 ? Self.fontMono15Black : Self.fontMono11_5Semibold,
                color: entry.1 ? NSColor(calibratedRed: 0.0, green: 0.94, blue: 1.0, alpha: 1.0) : .white
            )
        }
    }

    private func drawScoreboard(ctx: CGContext, center: CGPoint, sim: SublevelSimulation) {
        struct Row { let name: String; let frags: Int; let deaths: Int; let color: SIMD3<Float>; let isPlayer: Bool; let isAlive: Bool }
        var rows = [Row(name: "YOU", frags: sim.playerFrags, deaths: sim.playerDeaths, color: SIMD3<Float>(1, 1, 1), isPlayer: true, isAlive: sim.playerHealth > 0)]
        if sim.botsEnabled {
            rows += sim.bots.map { Row(name: $0.name, frags: $0.frags, deaths: $0.deaths, color: $0.teamColor, isPlayer: false, isAlive: $0.isAlive) }
        }
        rows.sort { ($0.frags, -$0.deaths) > ($1.frags, -$1.deaths) }

        let rowH: CGFloat = 30
        let boxH = 104 + CGFloat(rows.count) * rowH
        let box = CGRect(x: center.x - 260, y: center.y - boxH * 0.5, width: 520, height: boxH)
        let amber = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
        drawPanel(ctx: ctx, rect: box, accent: amber)

        let minutes = Int(sim.elapsedMatchTime) / 60
        let seconds = Int(sim.elapsedMatchTime) % 60
        drawText("SCOREBOARD", at: CGPoint(x: box.minX + 24, y: box.maxY - 36), font: Self.fontMono16Black, color: amber)
        drawText(
            String(format: "FRAG LIMIT %d  |  %02d:%02d", sim.fragLimit, minutes, seconds),
            at: CGPoint(x: box.maxX - 210, y: box.maxY - 33),
            font: Self.fontDigit11Bold,
            color: NSColor(white: 0.8, alpha: 1.0)
        )

        let headerY = box.maxY - 66
        let headerFont = Self.fontMono10Bold
        let headerColor = NSColor(white: 0.6, alpha: 1.0)
        drawText("#", at: CGPoint(x: box.minX + 24, y: headerY), font: headerFont, color: headerColor)
        drawText("PILOT", at: CGPoint(x: box.minX + 56, y: headerY), font: headerFont, color: headerColor)
        drawText("FRAGS", at: CGPoint(x: box.minX + 300, y: headerY), font: headerFont, color: headerColor)
        drawText("DEATHS", at: CGPoint(x: box.minX + 370, y: headerY), font: headerFont, color: headerColor)
        drawText("K/D", at: CGPoint(x: box.minX + 450, y: headerY), font: headerFont, color: headerColor)
        ctx.setFillColor(NSColor(white: 1.0, alpha: 0.18).cgColor)
        ctx.fill(CGRect(x: box.minX + 20, y: headerY - 8, width: box.width - 40, height: 1))

        for (i, row) in rows.enumerated() {
            let y = headerY - 34 - CGFloat(i) * rowH
            if row.isPlayer {
                ctx.setFillColor(NSColor(white: 1.0, alpha: 0.10).cgColor)
                ctx.fill(CGRect(x: box.minX + 20, y: y - 8, width: box.width - 40, height: rowH - 2))
            }
            let c = NSColor(calibratedRed: CGFloat(row.color.x), green: CGFloat(row.color.y), blue: CGFloat(row.color.z), alpha: row.isAlive ? 1.0 : 0.45)
            let font = row.isPlayer ? Self.fontDigit13Black : Self.fontDigit13Semibold
            ctx.setFillColor(c.cgColor)
            ctx.fill(CGRect(x: box.minX + 42, y: y - 2, width: 4, height: 16))
            drawText("\(i + 1)", at: CGPoint(x: box.minX + 24, y: y), font: font, color: .white)
            drawText(row.isAlive ? row.name : "\(row.name)  [DOWN]", at: CGPoint(x: box.minX + 56, y: y), font: font, color: c)
            drawText("\(row.frags)", at: CGPoint(x: box.minX + 300, y: y), font: font, color: .white)
            drawText("\(row.deaths)", at: CGPoint(x: box.minX + 370, y: y), font: font, color: .white)
            drawText(
                String(format: "%.2f", Float(row.frags) / Float(max(row.deaths, 1))),
                at: CGPoint(x: box.minX + 450, y: y),
                font: font,
                color: NSColor(white: 0.85, alpha: 1.0)
            )
        }
    }

    private func drawPanel(ctx: CGContext, rect: CGRect, accent: NSColor) {
        ctx.setFillColor(NSColor(calibratedWhite: 0.06, alpha: 0.80).cgColor)
        ctx.fill(rect)
        ctx.setFillColor(accent.cgColor)
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: 4, height: rect.height))
    }

    @inline(never)
    private func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor) {
        guard !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}
