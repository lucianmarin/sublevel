import Foundation
import simd

public struct ArenaBot: Sendable {
    public var id: Int
    public var name: String
    public var teamColor: SIMD3<Float>
    public var kinematic: KinematicState
    public var health: Float = 100.0
    public var armor: Float = 50.0
    public var weapon: WeaponSlot
    public var fireCooldown: Float = 0.0
    public var dodgeTimer: Float = 0.0
    public var strafePhase: Float = 0.0
    public var yaw: Float = 0.0
    public var pitch: Float = 0.0
    public var frags: Int = 0
    public var deaths: Int = 0
    public var respawnTimer: Float = 0.0
    public var hitFlashTimer: Float = 0.0

    public init(id: Int, name: String, teamColor: SIMD3<Float>, position: SIMD3<Float>, weapon: WeaponSlot) {
        self.id = id
        self.name = name
        self.teamColor = teamColor
        self.kinematic = KinematicState(position: position)
        self.weapon = weapon
        self.strafePhase = Float(id) * 1.57
    }

    public var isAlive: Bool {
        respawnTimer <= 0.0 && health > 0.0
    }

    public var stratum: Stratum {
        Stratum.forElevation(kinematic.position.y)
    }
}

public struct StyleFeedEntry: Sendable {
    public var title: String
    public var subtitle: String
    public var color: SIMD3<Float>
    public var remainingTime: Float

    public init(title: String, subtitle: String, color: SIMD3<Float>, remainingTime: Float = 3.6) {
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.remainingTime = remainingTime
    }
}

/// 60Hz Tick-Rollback Snapshot for M4 Network Foundation
public struct NetworkTickSnapshot: Sendable {
    public var tick: UInt64
    public var playerPosition: SIMD3<Float>
    public var playerVelocity: SIMD3<Float>
    public var playerYaw: Float
    public var playerHealth: Float
    public var playerFlowMultiplier: Float
    public var activeProjectilesCount: Int
    public var intactShatterFloorsMask: UInt32
}

public enum SoundEventKind: Sendable {
    case footstep
    case jump
    case dodge(wall: Bool)
    case jumpPad
    case teleport
    case weaponFire(WeaponSlot, alt: Bool)
    case shockCombo
    case explosion
    case breachShatter
    case pickup
    case hitMarker(kill: Bool)
}

public final class SublevelSimulation {
    public var config = MovementConfig()
    public var arena = ArenaMap()
    public var playerKinematic = KinematicState(position: SIMD3<Float>(0, 12.1, -21.0))
    public var cameraFX = CameraFXState()
    public var playerYaw: Float = .pi // Facing +Z across B1 Atrium toward center
    public var playerPitch: Float = -0.06
    public var playerHealth: Float = 100.0
    public var playerArmor: Float = 50.0
    public var playerFrags: Int = 0
    public var playerDeaths: Int = 0

    // Arsenal & Combat State
    public var currentWeapon: WeaponSlot = .prismRifle
    public var primaryCooldownTimer: Float = 0.0
    public var altCooldownTimer: Float = 0.0
    public var isSubRailZoomed: Bool = false
    public var rocketChargeCount: Int = 0
    public var isChargingRockets: Bool = false
    public var rocketChargeTimer: Float = 0.0
    public var weaponSwingOffset: Float = 0.0

    // Powerups
    public var quadOverdriveTimer: Float = 0.0
    public var subShieldTimer: Float = 0.0

    // Sublevel Flow & Style Meter (Section 5.3)
    public var flowMultiplier: Float = 1.0
    public var flowDecayTimer: Float = 0.0
    public var peakSpeedUPS: Float = 320.0
    public var totalShockCombos: Int = 0
    public var totalMultiStratumKills: Int = 0
    public var totalBreachesTriggered: Int = 0

    // Entities & VFX
    public var bots: [ArenaBot] = []
    public var projectiles: [Projectile] = []
    public var beams: [BeamSegmentFX] = []
    public var shockSpheres: [ShockSphereFX] = []
    public var styleFeed: [StyleFeedEntry] = []
    public var pendingSounds: [SoundEventKind] = []

    // Network Ring Buffer (60Hz Tick Snapshots)
    public var currentTick: UInt64 = 0
    public private(set) var tickHistory: [NetworkTickSnapshot] = []

    private var nextProjectileID: Int = 1
    private var footstepDistanceAccum: Float = 0.0
    private var lastJumpPadTriggerTime: Float = -10.0
    private var lastTeleporterTriggerTime: Float = -10.0
    public var elapsedMatchTime: Float = 0.0
    public var fragLimit: Int = 25
    public var botsEnabled: Bool = true

    public init() {
        spawnInitialBots()
        pushFeed(
            title: "SUBLEVEL // SL_ATRIUM ONLINE",
            subtitle: "B1 SKYLIGHT -> B2 CONCOURSE -> B3 THE SUMP",
            color: SublevelPalette.electricCyan
        )
    }

    public var playerStratum: Stratum {
        Stratum.forElevation(playerKinematic.position.y)
    }

    public var playerDamageMultiplier: Float {
        let quad: Float = quadOverdriveTimer > 0 ? 3.0 : 1.0
        let flowBonus: Float = 1.0 + min((flowMultiplier - 1.0) * 0.12, 0.5)
        return quad * flowBonus
    }

    public func spawnInitialBots() {
        bots = [
            ArenaBot(
                id: 1,
                name: "VEX // ALPHA",
                teamColor: SublevelPalette.acidMagenta,
                position: SIMD3<Float>(0, 12.1, 21.0),
                weapon: .prismRifle
            ),
            ArenaBot(
                id: 2,
                name: "KRON // BETA",
                teamColor: SublevelPalette.electricCyan,
                position: SIMD3<Float>(-20.0, 0.1, -18.0),
                weapon: .vectorLauncher
            ),
            ArenaBot(
                id: 3,
                name: "NYX // GAMMA",
                teamColor: SublevelPalette.acidMagenta,
                position: SIMD3<Float>(20.0, 0.1, 18.0),
                weapon: .shardCannon
            ),
            ArenaBot(
                id: 4,
                name: "SOL // DELTA",
                teamColor: SublevelPalette.electricCyan,
                position: SIMD3<Float>(16.0, -10.8, -4.0),
                weapon: .subRail
            )
        ]
    }

    public func resetMatch() {
        arena.resetBreaches()
        playerKinematic = KinematicState(position: SIMD3<Float>(0, 12.1, -21.0))
        playerYaw = .pi
        playerPitch = -0.06
        playerHealth = 100.0
        playerArmor = 50.0
        playerFrags = 0
        playerDeaths = 0
        flowMultiplier = 1.0
        peakSpeedUPS = 320.0
        projectiles.removeAll()
        beams.removeAll()
        shockSpheres.removeAll()
        styleFeed.removeAll()
        spawnInitialBots()
        pushFeed(title: "STRATA RESET // NEW MATCH", subtitle: "ALL SKYLIGHT & CONCOURSE BREACHES RESTORED", color: SublevelPalette.amberGold)
    }

    public func pushFeed(title: String, subtitle: String, color: SIMD3<Float>) {
        styleFeed.insert(StyleFeedEntry(title: title, subtitle: subtitle, color: color), at: 0)
        if styleFeed.count > 5 {
            styleFeed.removeLast()
        }
    }

    public func boostFlow(_ amount: Float, reason: String? = nil, color: SIMD3<Float> = SublevelPalette.amberGold) {
        flowMultiplier = min(5.0, flowMultiplier + amount)
        flowDecayTimer = 5.5
        if let reason = reason {
            pushFeed(title: reason, subtitle: String(format: "FLOW MULTIPLIER %.1fX", flowMultiplier), color: color)
        }
    }

    public func cameraLookVector() -> SIMD3<Float> {
        let cosPitch = cos(playerPitch)
        return simd_normalize(SIMD3<Float>(
            -sin(playerYaw) * cosPitch,
            sin(playerPitch),
            -cos(playerYaw) * cosPitch
        ))
    }

    /// Main 60Hz/120Hz/240Hz Simulation Tick
    public func update(
        input: MovementInput,
        primaryFireHeld: Bool,
        altFireHeld: Bool,
        altFireJustReleased: Bool,
        delta: Float
    ) {
        let dt = min(delta, 0.05)
        elapsedMatchTime += dt
        currentTick &+= 1

        // 1. Update Player Kinematics via MovementSolver
        var playerInput = input
        playerInput.yaw = playerYaw
        playerInput.pitch = playerPitch
        let prevOnFloor = playerKinematic.isOnFloor
        let prevStratum = playerStratum

        MovementSolver.step(
            state: &playerKinematic,
            input: playerInput,
            config: config,
            colliders: arena.colliders,
            delta: dt
        )

        let curUPS = playerKinematic.speedUPS
        if curUPS > peakSpeedUPS {
            peakSpeedUPS = curUPS
        }

        // Trigger movement audio & flow bonuses
        if playerKinematic.lastDodgeTriggered {
            pendingSounds.append(.dodge(wall: false))
            boostFlow(0.15)
        } else if playerKinematic.lastWallDodgeTriggered {
            pendingSounds.append(.dodge(wall: true))
            boostFlow(0.35, reason: "WALL DODGE // KINETIC REDIRECT", color: SublevelPalette.signalRed)
        } else if prevOnFloor && !playerKinematic.isOnFloor && playerKinematic.velocity.y > 4.0 {
            pendingSounds.append(.jump)
        }

        if playerKinematic.isOnFloor && playerKinematic.horizontalSpeed > 2.0 && !playerKinematic.isSliding {
            footstepDistanceAccum += playerKinematic.horizontalSpeed * dt
            if footstepDistanceAccum >= 2.9 {
                footstepDistanceAccum = 0.0
                pendingSounds.append(.footstep)
            }
        }

        // Sublevel Slam Shockwave when diving across strata with Crouch held!
        if !prevOnFloor && playerKinematic.isOnFloor && playerKinematic.lastLandingImpactSpeed > 18.0 && input.crouchHeld {
            shockSpheres.append(ShockSphereFX(
                center: playerKinematic.position,
                maxRadius: 5.5,
                color: SublevelPalette.cobaltBlue,
                duration: 0.38
            ))
            let breached = arena.applyStructuralDamage(
                at: playerKinematic.position - SIMD3<Float>(0, 0.25, 0),
                radius: 3.2,
                damage: 95.0
            )
            if breached > 0 {
                totalBreachesTriggered += breached
                pendingSounds.append(.breachShatter)
                boostFlow(0.65, reason: "SUBLEVEL SLAM BREACH!", color: SublevelPalette.cobaltBlue)
            }
        }

        if prevStratum != playerStratum {
            // Announce vertical stratum transition when moving fast
            if playerKinematic.horizontalSpeed > 8.0 || abs(playerKinematic.velocity.y) > 9.0 {
                boostFlow(0.10)
            }
        }

        // Check Abyss Fall
        if playerKinematic.position.y < arena.abyssLethalY {
            respawnPlayer(fellIntoAbyss: true)
        }

        // 2. Check Jump Pads, Teleporters, and Pickups for Player
        checkInteractablesForPlayer(dt: dt)

        // 3. Update Weapon Cooldowns & Firing
        updatePlayerWeapons(
            primaryFireHeld: primaryFireHeld,
            altFireHeld: altFireHeld,
            altFireJustReleased: altFireJustReleased,
            dt: dt
        )

        // 4. Update AI Bots across B1/B2/B3
        if botsEnabled {
            updateBots(dt: dt)
        }

        // 5. Update Projectiles, Ricochets, Rockets & Combos
        updateProjectiles(dt: dt)

        // 6. Update Visual FX, Pickups, Flow Decay & Camera FX
        updateFXAndTimers(input: playerInput, dt: dt)

        // 7. Record 60Hz Network Tick Snapshot
        recordTickSnapshot()
    }

    private func checkInteractablesForPlayer(dt: Float) {
        // Jump Pads
        if elapsedMatchTime - lastJumpPadTriggerTime > 0.28 {
            for pad in arena.jumpPads {
                let horizDist = simd_distance(
                    SIMD2<Float>(playerKinematic.position.x, playerKinematic.position.z),
                    SIMD2<Float>(pad.position.x, pad.position.z)
                )
                let vertDist = abs(playerKinematic.position.y - pad.position.y)
                if horizDist <= pad.radius && vertDist <= 1.6 {
                    playerKinematic.velocity.x = playerKinematic.velocity.x * 0.45 + pad.launchVelocity.x
                    playerKinematic.velocity.z = playerKinematic.velocity.z * 0.45 + pad.launchVelocity.z
                    playerKinematic.velocity.y = pad.launchVelocity.y
                    playerKinematic.isOnFloor = false
                    playerKinematic.wallDodgesUsed = 0
                    lastJumpPadTriggerTime = elapsedMatchTime
                    pendingSounds.append(.jumpPad)
                    boostFlow(0.20, reason: pad.label, color: SublevelPalette.signalRed)
                    break
                }
            }
        }

        // Teleporters
        if elapsedMatchTime - lastTeleporterTriggerTime > 0.75 {
            for tp in arena.teleporters {
                let dist = simd_distance(playerKinematic.position, tp.position)
                if dist <= tp.radius {
                    let speed = max(playerKinematic.horizontalSpeed, 12.5)
                    playerKinematic.position = tp.destination
                    playerYaw = tp.exitYaw
                    let exitDir = SIMD3<Float>(-sin(tp.exitYaw), 0, -cos(tp.exitYaw))
                    playerKinematic.velocity = exitDir * speed + SIMD3<Float>(0, 3.0, 0)
                    lastTeleporterTriggerTime = elapsedMatchTime
                    pendingSounds.append(.teleport)
                    shockSpheres.append(ShockSphereFX(center: tp.destination, maxRadius: 2.6, color: SublevelPalette.cobaltBlue, duration: 0.35))
                    boostFlow(0.25, reason: tp.label, color: SublevelPalette.cobaltBlue)
                    break
                }
            }
        }

        // Pickups
        for i in arena.pickups.indices {
            arena.pickups[i].rotationAngle += dt * 2.2
            if !arena.pickups[i].isActive {
                arena.pickups[i].respawnTimer -= dt
                if arena.pickups[i].respawnTimer <= 0.0 {
                    arena.pickups[i].isActive = true
                }
                continue
            }

            let dist = simd_distance(playerKinematic.eyePosition, arena.pickups[i].position)
            if dist <= 1.85 {
                let kind = arena.pickups[i].kind
                arena.pickups[i].isActive = false
                arena.pickups[i].respawnTimer = kind.respawnDuration
                pendingSounds.append(.pickup)

                switch kind {
                case .megaHealth:
                    playerHealth = min(200.0, playerHealth + 100.0)
                case .armorShard:
                    playerArmor = min(200.0, playerArmor + 50.0)
                case .quadOverdrive:
                    quadOverdriveTimer = 15.0
                case .subShield:
                    subShieldTimer = 12.0
                case .ammoPack:
                    primaryCooldownTimer = 0.0
                    altCooldownTimer = 0.0
                    playerArmor = min(200.0, playerArmor + 25.0)
                }
                boostFlow(0.30, reason: kind.rawValue, color: kind.color)
            }
        }
    }

    private func updatePlayerWeapons(
        primaryFireHeld: Bool,
        altFireHeld: Bool,
        altFireJustReleased: Bool,
        dt: Float
    ) {
        primaryCooldownTimer = max(0.0, primaryCooldownTimer - dt)
        altCooldownTimer = max(0.0, altCooldownTimer - dt)
        weaponSwingOffset = max(0.0, weaponSwingOffset - dt * 4.0)

        if currentWeapon != .subRail {
            isSubRailZoomed = false
        }

        // Handle Vector Launcher Alt-Fire multi-rocket loading (up to 3 rockets)
        if currentWeapon == .vectorLauncher {
            if altFireHeld && altCooldownTimer <= 0.0 {
                if !isChargingRockets {
                    isChargingRockets = true
                    rocketChargeCount = 1
                    rocketChargeTimer = 0.38
                } else {
                    rocketChargeTimer -= dt
                    if rocketChargeTimer <= 0.0 && rocketChargeCount < 3 {
                        rocketChargeCount += 1
                        rocketChargeTimer = 0.38
                        pendingSounds.append(.pickup)
                    }
                }
                if rocketChargeCount == 3 && rocketChargeTimer <= 0.05 {
                    releaseChargedRocketVolley()
                }
                return
            } else if isChargingRockets && (altFireJustReleased || !altFireHeld) {
                releaseChargedRocketVolley()
                return
            }
        } else {
            isChargingRockets = false
            rocketChargeCount = 0
        }

        if primaryFireHeld && primaryCooldownTimer <= 0.0 {
            triggerPlayerPrimaryFire()
        } else if altFireHeld && altCooldownTimer <= 0.0 {
            triggerPlayerAltFire()
        }
    }

    private func releaseChargedRocketVolley() {
        let count = max(1, rocketChargeCount)
        isChargingRockets = false
        rocketChargeCount = 0
        altCooldownTimer = WeaponSlot.vectorLauncher.altCooldown
        primaryCooldownTimer = 0.45
        cameraFX.recoilPitch += 0.065 * Float(count)
        weaponSwingOffset = 1.0
        pendingSounds.append(.weaponFire(.vectorLauncher, alt: true))

        let origin = playerKinematic.eyePosition
        let forward = cameraLookVector()
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))

        for i in 0..<count {
            let spreadOffset = Float(i) - Float(count - 1) * 0.5
            let dir = simd_normalize(forward + right * (spreadOffset * 0.055))
            let spawnPos = origin + dir * 0.65 + right * (spreadOffset * 0.22)
            let id = nextProjectileID
            nextProjectileID += 1
            projectiles.append(Projectile(
                id: id,
                ownerID: 0,
                kind: .vectorRocket,
                position: spawnPos,
                velocity: dir * 32.0,
                damage: 95.0 * playerDamageMultiplier,
                splashRadius: 5.4,
                lifetime: 6.0,
                color: SublevelPalette.crimson,
                spiralPhase: Float(i) * 2.09
            ))
        }
    }

    public func triggerPlayerPrimaryFire() {
        primaryCooldownTimer = currentWeapon.primaryCooldown
        weaponSwingOffset = 1.0
        let origin = playerKinematic.eyePosition
        let dir = cameraLookVector()
        let actors = buildActorTargets()
        pendingSounds.append(.weaponFire(currentWeapon, alt: false))

        switch currentWeapon {
        case .kineticGauntlet:
            // High-knockback melee dash
            let horizDir = simd_normalize(SIMD3<Float>(dir.x, 0, dir.z))
            playerKinematic.velocity += horizDir * 9.5 + SIMD3<Float>(0, 2.2, 0)
            cameraFX.recoilPitch += 0.035
            beams.append(BeamSegmentFX(
                start: origin - SIMD3<Float>(0, 0.2, 0),
                end: origin + dir * 4.2,
                color: SublevelPalette.signalRed,
                thickness: 0.18,
                life: 0.18
            ))
            for actor in actors where actor.id != 0 {
                if simd_distance(origin, actor.center) <= 4.6 {
                    applyDamageEvents([
                        DamageEvent(
                            attackerID: 0,
                            targetID: actor.id,
                            damage: 75.0 * playerDamageMultiplier,
                            knockback: dir * 20.0 + SIMD3<Float>(0, 7.5, 0),
                            weapon: .kineticGauntlet,
                            isShockCombo: false,
                            isHeadshotOrMidair: !playerKinematic.isOnFloor,
                            hitPoint: actor.center
                        )
                    ])
                }
            }

        case .prismRifle:
            // Instant hitscan beam (45 dmg) OR 160-dmg Shock Combo if intersecting a Shock Orb!
            cameraFX.recoilPitch += 0.028
            let result = WeaponSystem.firePrismBeam(
                shooterID: 0,
                origin: origin,
                direction: dir,
                damageMultiplier: playerDamageMultiplier,
                arena: &arena,
                projectiles: &projectiles,
                actors: actors,
                beams: &beams,
                spheres: &shockSpheres
            )
            if result.triggeredShockCombo {
                totalShockCombos += 1
                cameraFX.breachShake = 0.65
                pendingSounds.append(.shockCombo)
                boostFlow(0.75, reason: "SHOCK COMBO // 160 DMG DETONATION", color: SublevelPalette.electricCyan)
            }
            if result.breachedCount > 0 {
                totalBreachesTriggered += result.breachedCount
                pendingSounds.append(.breachShatter)
                pushFeed(title: "DYNAMIC BREACH!", subtitle: "STRATUM FLOOR SHATTERED BY SHOCK COMBO", color: SublevelPalette.cobaltBlue)
            }
            applyDamageEvents(result.events)

        case .shardCannon:
            // 9-pellet ricocheting geometric shrapnel spread
            cameraFX.recoilPitch += 0.052
            let right = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
            let up = simd_normalize(simd_cross(right, dir))
            let offsets: [SIMD2<Float>] = [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(-0.045,  0.025), SIMD2<Float>(0.045,  0.025),
                SIMD2<Float>(-0.045, -0.025), SIMD2<Float>(0.045, -0.025),
                SIMD2<Float>(-0.075,  0.0),   SIMD2<Float>(0.075,  0.0),
                SIMD2<Float>(0.0,     0.055), SIMD2<Float>(0.0,   -0.055)
            ]
            for off in offsets {
                let pelletDir = simd_normalize(dir + right * off.x + up * off.y)
                let id = nextProjectileID
                nextProjectileID += 1
                projectiles.append(Projectile(
                    id: id,
                    ownerID: 0,
                    kind: .shardPellet,
                    position: origin + pelletDir * 0.5,
                    velocity: pelletDir * 44.0,
                    damage: 16.0 * playerDamageMultiplier,
                    splashRadius: 0.0,
                    bouncesRemaining: 1, // Bounces once off white walls!
                    lifetime: 2.2,
                    color: SublevelPalette.amberOrange
                ))
            }

        case .vectorLauncher:
            // Fast linear rocket (100 dmg, high splash, 0.4x self-damage rocket jumping)
            cameraFX.recoilPitch += 0.060
            let id = nextProjectileID
            nextProjectileID += 1
            projectiles.append(Projectile(
                id: id,
                ownerID: 0,
                kind: .vectorRocket,
                position: origin + dir * 0.65,
                velocity: dir * 33.0,
                damage: 100.0 * playerDamageMultiplier,
                splashRadius: 5.8,
                lifetime: 6.0,
                color: SublevelPalette.crimson
            ))

        case .subRail:
            // Piercing 90-dmg slug with persistent volumetric beam
            cameraFX.recoilPitch += 0.075
            let res = WeaponSystem.fireSubRailSlug(
                shooterID: 0,
                origin: origin,
                direction: dir,
                pierceFloors: isSubRailZoomed,
                damageMultiplier: playerDamageMultiplier,
                arena: &arena,
                actors: actors,
                beams: &beams,
                spheres: &shockSpheres
            )
            if res.breachedCount > 0 {
                totalBreachesTriggered += res.breachedCount
                pendingSounds.append(.breachShatter)
            }
            applyDamageEvents(res.events)
        }
    }

    public func triggerPlayerAltFire() {
        altCooldownTimer = currentWeapon.altCooldown
        weaponSwingOffset = 0.85
        let origin = playerKinematic.eyePosition
        let dir = cameraLookVector()
        let actors = buildActorTargets()
        pendingSounds.append(.weaponFire(currentWeapon, alt: true))

        switch currentWeapon {
        case .kineticGauntlet:
            // Focused air-blast cone: Blast floors for zero-self-damage vertical hops or knock enemies off sublevels!
            cameraFX.recoilPitch += 0.045
            let worldHit = arena.raycast(origin: origin, dir: dir, maxDist: 5.2)
            if worldHit.hit || dir.y < -0.35 {
                // Zero-self-damage vertical + recoil impulse hop!
                playerKinematic.velocity -= dir * 13.5
                playerKinematic.velocity.y = max(playerKinematic.velocity.y, 11.2)
                playerKinematic.isOnFloor = false
                boostFlow(0.20, reason: "IMPULSE BLAST HOP", color: SublevelPalette.signalRed)
            }
            shockSpheres.append(ShockSphereFX(center: origin + dir * 1.8, maxRadius: 2.4, color: SublevelPalette.signalRed, duration: 0.25))
            // Knock enemies in cone off sublevels
            for actor in actors where actor.id != 0 {
                let toTarget = actor.center - origin
                let dist = simd_length(toTarget)
                if dist <= 7.5 && simd_dot(simd_normalize(toTarget), dir) > 0.55 {
                    applyDamageEvents([
                        DamageEvent(
                            attackerID: 0,
                            targetID: actor.id,
                            damage: 35.0 * playerDamageMultiplier,
                            knockback: simd_normalize(toTarget) * 24.0 + SIMD3<Float>(0, 9.0, 0),
                            weapon: .kineticGauntlet,
                            isShockCombo: false,
                            isHeadshotOrMidair: false,
                            hitPoint: actor.center
                        )
                    ])
                }
            }

        case .prismRifle:
            // Slow-moving unstable Plasma Orb (55 dmg, 1.45m Shock Combo hurtbox)
            cameraFX.recoilPitch += 0.032
            let id = nextProjectileID
            nextProjectileID += 1
            projectiles.append(Projectile(
                id: id,
                ownerID: 0,
                kind: .shockOrb,
                position: origin + dir * 0.85,
                velocity: dir * 15.5,
                damage: 55.0 * playerDamageMultiplier,
                splashRadius: 3.2,
                comboHitboxRadius: 1.55,
                lifetime: 6.5,
                color: SublevelPalette.electricCyan
            ))

        case .shardCannon:
            // Arcing fragmentation grenade
            cameraFX.recoilPitch += 0.055
            let id = nextProjectileID
            nextProjectileID += 1
            let launchVel = dir * 23.0 + SIMD3<Float>(0, 5.8, 0)
            projectiles.append(Projectile(
                id: id,
                ownerID: 0,
                kind: .flakGrenade,
                position: origin + dir * 0.65,
                velocity: launchVel,
                damage: 85.0 * playerDamageMultiplier,
                splashRadius: 5.0,
                bouncesRemaining: 1,
                lifetime: 3.5,
                color: SublevelPalette.amberOrange
            ))

        case .vectorLauncher:
            break // Handled via charge / release

        case .subRail:
            // Toggle zoom + fire vertical penetrator shot if already zoomed
            isSubRailZoomed.toggle()
            if isSubRailZoomed {
                // Immediately fire a vertical floor-penetrating slug on zoom-in snap!
                let res = WeaponSystem.fireSubRailSlug(
                    shooterID: 0,
                    origin: origin,
                    direction: dir,
                    pierceFloors: true,
                    damageMultiplier: playerDamageMultiplier,
                    arena: &arena,
                    actors: actors,
                    beams: &beams,
                    spheres: &shockSpheres
                )
                if res.breachedCount > 0 {
                    totalBreachesTriggered += res.breachedCount
                    pendingSounds.append(.breachShatter)
                    pushFeed(title: "SUB-RAIL PENETRATOR!", subtitle: "PIERCED SUBLEVEL FLOOR PLATE", color: SublevelPalette.cobaltViolet)
                }
                applyDamageEvents(res.events)
            }
        }
    }

    private func buildActorTargets() -> [CombatActorTarget] {
        var list: [CombatActorTarget] = [
            CombatActorTarget(id: 0, feetPosition: playerKinematic.position, radius: config.hullRadius, height: config.hullHeight)
        ]
        for bot in bots where bot.isAlive {
            list.append(CombatActorTarget(id: bot.id, feetPosition: bot.kinematic.position, radius: 0.55, height: 1.85))
        }
        return list
    }

    private func updateProjectiles(dt: Float) {
        let actors = buildActorTargets()
        var surviving: [Projectile] = []

        for var proj in projectiles {
            proj.lifetime -= dt
            if proj.lifetime <= 0.0 {
                continue
            }

            proj.prevPosition = proj.position

            // Apply gravity to arcing flak grenade
            if proj.kind == .flakGrenade {
                proj.velocity.y -= 19.5 * dt
            } else if proj.kind == .vectorRocket && abs(proj.spiralPhase) > 0.001 {
                // Subtle spiral corkscrew on multi-rocket alt-fire
                proj.spiralPhase += dt * 10.0
            }

            let stepVec = proj.velocity * dt
            let stepLen = simd_length(stepVec)
            let stepDir = stepLen > 1e-5 ? (stepVec / stepLen) : SIMD3<Float>(0, 0, -1)

            // Check direct actor hit
            var hitTarget: CombatActorTarget? = nil
            for actor in actors where actor.id != proj.ownerID {
                let hit = Math3D.rayIntersectSphere(
                    origin: proj.position,
                    dir: stepDir,
                    center: actor.center,
                    radius: actor.radius + (proj.kind == .shockOrb ? 0.55 : 0.25),
                    maxDist: max(stepLen, 0.25)
                )
                if hit.hit {
                    hitTarget = actor
                    break
                }
            }

            if let target = hitTarget {
                detonateOrApplyProjectile(&proj, at: target.center, directHitActor: target, actors: actors)
                continue
            }

            // Check world collider hit
            let worldHit = arena.raycast(origin: proj.position, dir: stepDir, maxDist: stepLen + 0.12)
            if worldHit.hit {
                if proj.bouncesRemaining > 0 {
                    // Ricochet off white brutalist walls with glowing trail!
                    proj.bouncesRemaining -= 1
                    proj.position = worldHit.point + worldHit.normal * 0.08
                    let reflected = proj.velocity - 2.0 * simd_dot(proj.velocity, worldHit.normal) * worldHit.normal
                    proj.velocity = reflected * (proj.kind == .flakGrenade ? 0.65 : 0.88)
                    beams.append(BeamSegmentFX(
                        start: proj.prevPosition,
                        end: proj.position,
                        color: proj.color,
                        thickness: 0.06,
                        life: 0.25
                    ))
                    surviving.append(proj)
                } else {
                    detonateOrApplyProjectile(&proj, at: worldHit.point, directHitActor: nil, actors: actors)
                }
                continue
            }

            proj.position += stepVec
            if proj.kind == .shardPellet {
                beams.append(BeamSegmentFX(
                    start: proj.prevPosition,
                    end: proj.position,
                    color: SublevelPalette.amberOrange,
                    thickness: 0.045,
                    life: 0.14
                ))
            }
            surviving.append(proj)
        }

        projectiles = surviving
    }

    private func detonateOrApplyProjectile(
        _ proj: inout Projectile,
        at point: SIMD3<Float>,
        directHitActor: CombatActorTarget?,
        actors: [CombatActorTarget]
    ) {
        switch proj.kind {
        case .shardPellet:
            if let target = directHitActor {
                let dir = simd_normalize(proj.velocity)
                applyDamageEvents([
                    DamageEvent(
                        attackerID: proj.ownerID,
                        targetID: target.id,
                        damage: proj.damage,
                        knockback: dir * 3.2 + SIMD3<Float>(0, 1.0, 0),
                        weapon: .shardCannon,
                        isShockCombo: false,
                        isHeadshotOrMidair: false,
                        hitPoint: point
                    )
                ])
            }
            shockSpheres.append(ShockSphereFX(center: point, maxRadius: 0.35, color: SublevelPalette.amberOrange, duration: 0.12))

        case .shockOrb:
            shockSpheres.append(ShockSphereFX(center: point, maxRadius: proj.splashRadius, color: SublevelPalette.electricCyan, duration: 0.32))
            let events = WeaponSystem.evaluateRadialExplosion(
                attackerID: proj.ownerID,
                center: point,
                radius: proj.splashRadius,
                baseDamage: proj.damage,
                baseImpulse: 9.5,
                selfDamageMultiplier: 0.35,
                weapon: .prismRifle,
                isShockCombo: false,
                actors: actors
            )
            applyDamageEvents(events)

        case .flakGrenade:
            pendingSounds.append(.explosion)
            shockSpheres.append(ShockSphereFX(center: point, maxRadius: proj.splashRadius, color: SublevelPalette.amberOrange, duration: 0.38))
            let breached = arena.applyStructuralDamage(at: point, radius: proj.splashRadius * 0.7, damage: 70.0)
            if breached > 0 {
                totalBreachesTriggered += breached
                pendingSounds.append(.breachShatter)
            }
            let events = WeaponSystem.evaluateRadialExplosion(
                attackerID: proj.ownerID,
                center: point,
                radius: proj.splashRadius,
                baseDamage: proj.damage,
                baseImpulse: 13.5,
                selfDamageMultiplier: 0.45,
                weapon: .shardCannon,
                isShockCombo: false,
                actors: actors
            )
            applyDamageEvents(events)

        case .vectorRocket:
            pendingSounds.append(.explosion)
            shockSpheres.append(ShockSphereFX(center: point, maxRadius: proj.splashRadius, color: SublevelPalette.crimson, duration: 0.42))
            let breached = arena.applyStructuralDamage(at: point, radius: proj.splashRadius * 0.85, damage: 95.0)
            if breached > 0 {
                totalBreachesTriggered += breached
                pendingSounds.append(.breachShatter)
                pushFeed(title: "ROCKET BREACH!", subtitle: "FLOOR GRATE SHATTERED INTO SUBLEVEL", color: SublevelPalette.crimson)
            }
            let events = WeaponSystem.evaluateRadialExplosion(
                attackerID: proj.ownerID,
                center: point,
                radius: proj.splashRadius,
                baseDamage: proj.damage,
                baseImpulse: 16.8,
                selfDamageMultiplier: WeaponSystem.rocketSelfDamageMultiplier,
                weapon: .vectorLauncher,
                isShockCombo: false,
                actors: actors
            )
            // Detect Rocket Jump if player boosted self upward
            for ev in events where ev.attackerID == 0 && ev.targetID == 0 && ev.knockback.y > 7.5 {
                boostFlow(0.30, reason: "ROCKET JUMP // 0.4X SELF-DMG", color: SublevelPalette.crimson)
            }
            applyDamageEvents(events)
        }
    }

    private func applyDamageEvents(_ events: [DamageEvent]) {
        for ev in events {
            if ev.targetID == 0 {
                // Damage & Knockback to Local Player
                playerKinematic.velocity += ev.knockback
                if ev.knockback.y > 2.5 {
                    playerKinematic.isOnFloor = false
                }
                if subShieldTimer <= 0.0 {
                    let armorAbsorb = min(playerArmor, ev.damage * 0.66)
                    playerArmor -= armorAbsorb
                    playerHealth -= (ev.damage - armorAbsorb)
                    cameraFX.damageFlash = min(1.0, cameraFX.damageFlash + 0.45)
                    if playerHealth <= 0.0 {
                        playerDeaths += 1
                        if ev.attackerID > 0, let idx = bots.firstIndex(where: { $0.id == ev.attackerID }) {
                            bots[idx].frags += 1
                        }
                        respawnPlayer(fellIntoAbyss: false)
                    }
                }
            } else if let idx = bots.firstIndex(where: { $0.id == ev.targetID }), bots[idx].isAlive {
                bots[idx].kinematic.velocity += ev.knockback
                if ev.knockback.y > 2.5 {
                    bots[idx].kinematic.isOnFloor = false
                }
                bots[idx].hitFlashTimer = 0.20
                let armorAbsorb = min(bots[idx].armor, ev.damage * 0.5)
                bots[idx].armor -= armorAbsorb
                bots[idx].health -= (ev.damage - armorAbsorb)

                let killed = bots[idx].health <= 0.0
                if ev.attackerID == 0 {
                    pendingSounds.append(.hitMarker(kill: killed))
                }

                if killed {
                    bots[idx].deaths += 1
                    bots[idx].respawnTimer = 3.2
                    shockSpheres.append(ShockSphereFX(
                        center: bots[idx].kinematic.position + SIMD3<Float>(0, 0.9, 0),
                        maxRadius: 2.4,
                        color: bots[idx].teamColor,
                        duration: 0.40
                    ))

                    if ev.attackerID == 0 {
                        playerFrags += 1
                        let victimStratum = bots[idx].stratum
                        let killerStratum = playerStratum
                        let isCrossStratum = (victimStratum != killerStratum)
                        let isAirborneKill = (!playerKinematic.isOnFloor || !bots[idx].kinematic.isOnFloor)

                        if ev.isShockCombo {
                            boostFlow(1.0, reason: "SHOCK COMBO FRAG // \(bots[idx].name)", color: SublevelPalette.electricCyan)
                        } else if isCrossStratum {
                            totalMultiStratumKills += 1
                            boostFlow(
                                0.85,
                                reason: "SUBLEVEL DESCENDANT (\(killerStratum.shortCode) -> \(victimStratum.shortCode))",
                                color: SublevelPalette.amberGold
                            )
                        } else if isAirborneKill {
                            boostFlow(0.60, reason: "MID-AIR INTERCEPT // \(bots[idx].name)", color: ev.weapon.accentColor)
                        } else {
                            boostFlow(0.40, reason: "FRAGGED \(bots[idx].name)", color: ev.weapon.accentColor)
                        }
                    }
                }
            }
        }
    }

    private func respawnPlayer(fellIntoAbyss: Bool) {
        if fellIntoAbyss {
            playerDeaths += 1
            pushFeed(title: "ABYSS TERMINATION", subtitle: "FELL BELOW B3 SUMP STRATUM", color: SublevelPalette.signalRed)
        }
        let spawn = arena.spawnPoints[Int(currentTick) % arena.spawnPoints.count]
        playerKinematic = KinematicState(position: spawn.position)
        playerYaw = spawn.yaw
        playerPitch = -0.05
        playerHealth = 100.0
        playerArmor = 50.0
        flowMultiplier = max(1.0, flowMultiplier * 0.5)
    }

    /// M4 Arena Bot AI: Navmesh/Jump-Link steering, jump pad usage, wall-dodging, and airborne target tracking
    private func updateBots(dt: Float) {
        for i in bots.indices {
            bots[i].hitFlashTimer = max(0.0, bots[i].hitFlashTimer - dt)

            if !bots[i].isAlive {
                bots[i].respawnTimer -= dt
                if bots[i].respawnTimer <= 0.0 {
                    let spawn = arena.spawnPoints[(i + Int(currentTick)) % arena.spawnPoints.count]
                    bots[i].kinematic = KinematicState(position: spawn.position)
                    bots[i].yaw = spawn.yaw
                    bots[i].health = 100.0
                    bots[i].armor = 50.0
                }
                continue
            }

            if bots[i].kinematic.position.y < arena.abyssLethalY {
                bots[i].deaths += 1
                bots[i].respawnTimer = 2.0
                continue
            }

            bots[i].fireCooldown = max(0.0, bots[i].fireCooldown - dt)
            bots[i].dodgeTimer = max(0.0, bots[i].dodgeTimer - dt)
            bots[i].strafePhase += dt * 2.4

            // Determine desired target point: if below player's stratum, steer toward nearest JumpPad!
            let botPos = bots[i].kinematic.position
            let toPlayer = playerKinematic.eyePosition - (botPos + SIMD3<Float>(0, 1.5, 0))
            let distToPlayer = simd_length(toPlayer)

            var moveTarget = playerKinematic.position
            if botPos.y + 6.0 < playerKinematic.position.y {
                // Find closest JumpPad on the bot's stratum to ascend strata!
                if let bestPad = arena.jumpPads.min(by: {
                    simd_distance($0.position, botPos) < simd_distance($1.position, botPos)
                }) {
                    moveTarget = bestPad.position
                }
            }

            let toMove = moveTarget - botPos
            let desiredYaw = atan2(-toMove.x, -toMove.z)
            bots[i].yaw = desiredYaw

            var botInput = MovementInput()
            botInput.yaw = desiredYaw
            botInput.moveForward = distToPlayer > 7.5 ? 1.0 : (distToPlayer < 4.5 ? -0.6 : 0.35)
            botInput.moveRight = sin(bots[i].strafePhase) * 0.85
            botInput.jumpHeld = (Int(currentTick) + i * 17) % 45 == 0

            if bots[i].dodgeTimer <= 0.0 && distToPlayer < 22.0 {
                botInput.dodgeRequested = true
                botInput.dodgeDirectionLocal = SIMD2<Float>(sin(bots[i].strafePhase) >= 0 ? 1 : -1, 0.3)
                bots[i].dodgeTimer = 2.4
            }

            MovementSolver.step(
                state: &bots[i].kinematic,
                input: botInput,
                config: config,
                colliders: arena.colliders,
                delta: dt
            )

            // Bot Jump Pad interactions
            for pad in arena.jumpPads {
                let hDist = simd_distance(
                    SIMD2<Float>(bots[i].kinematic.position.x, bots[i].kinematic.position.z),
                    SIMD2<Float>(pad.position.x, pad.position.z)
                )
                if hDist <= pad.radius && abs(bots[i].kinematic.position.y - pad.position.y) <= 1.5 {
                    bots[i].kinematic.velocity = pad.launchVelocity
                    bots[i].kinematic.isOnFloor = false
                    break
                }
            }

            // Bot Predictive Firing at Player
            if bots[i].fireCooldown <= 0.0 && distToPlayer < 46.0 {
                let eye = bots[i].kinematic.position + SIMD3<Float>(0, 1.55, 0)
                // Lead airborne targets using player's velocity
                let leadTime = min(distToPlayer / 34.0, 0.55)
                let predictedTarget = playerKinematic.eyePosition + playerKinematic.velocity * leadTime * 0.45
                let aimVec = predictedTarget - eye
                let aimDir = simd_normalize(aimVec)
                let los = arena.raycast(origin: eye, dir: aimDir, maxDist: distToPlayer)

                if !los.hit || los.distance >= distToPlayer - 1.0 {
                    bots[i].fireCooldown = 1.65
                    let spread = SIMD3<Float>(
                        sin(Float(currentTick) * 1.3 + Float(i)) * 0.045,
                        cos(Float(currentTick) * 1.7 + Float(i)) * 0.035,
                        sin(Float(currentTick) * 0.9) * 0.045
                    )
                    let shotDir = simd_normalize(aimDir + spread)
                    let id = nextProjectileID
                    nextProjectileID += 1
                    projectiles.append(Projectile(
                        id: id,
                        ownerID: bots[i].id,
                        kind: bots[i].weapon == .vectorLauncher ? .vectorRocket : .shockOrb,
                        position: eye + shotDir * 0.75,
                        velocity: shotDir * (bots[i].weapon == .vectorLauncher ? 25.0 : 17.5),
                        damage: bots[i].weapon == .vectorLauncher ? 22.0 : 16.0,
                        splashRadius: 3.6,
                        comboHitboxRadius: 1.45,
                        lifetime: 5.0,
                        color: bots[i].teamColor
                    ))
                }
            }
        }
    }

    private func updateFXAndTimers(input: MovementInput, dt: Float) {
        quadOverdriveTimer = max(0.0, quadOverdriveTimer - dt)
        subShieldTimer = max(0.0, subShieldTimer - dt)

        if flowDecayTimer > 0.0 {
            flowDecayTimer -= dt
        } else if flowMultiplier > 1.0 {
            flowMultiplier = max(1.0, flowMultiplier - dt * 0.22)
        }

        // Keep flow multiplier alive while maintaining high Quake 3 strafe-jump speed (> 420 u/s)
        if playerKinematic.speedUPS > 420.0 {
            flowDecayTimer = max(flowDecayTimer, 0.5)
            flowMultiplier = min(5.0, flowMultiplier + dt * 0.08)
        }

        beams = beams.compactMap { var b = $0; b.remainingLife -= dt; return b.remainingLife > 0 ? b : nil }
        shockSpheres = shockSpheres.compactMap { var s = $0; s.elapsed += dt; return s.elapsed < s.duration ? s : nil }
        styleFeed = styleFeed.compactMap { var f = $0; f.remainingTime -= dt; return f.remainingTime > 0 ? f : nil }

        cameraFX.update(
            kinematic: playerKinematic,
            input: input,
            isZoomed: isSubRailZoomed,
            delta: dt
        )
    }

    private func recordTickSnapshot() {
        var mask: UInt32 = 0
        var shatterIdx: UInt32 = 0
        for c in arena.colliders where c.kind == .shatterFloor {
            if !c.isDestroyed && shatterIdx < 32 {
                mask |= (1 << shatterIdx)
            }
            shatterIdx += 1
        }

        let snap = NetworkTickSnapshot(
            tick: currentTick,
            playerPosition: playerKinematic.position,
            playerVelocity: playerKinematic.velocity,
            playerYaw: playerYaw,
            playerHealth: playerHealth,
            playerFlowMultiplier: flowMultiplier,
            activeProjectilesCount: projectiles.count,
            intactShatterFloorsMask: mask
        )
        tickHistory.append(snap)
        if tickHistory.count > 120 {
            tickHistory.removeFirst(tickHistory.count - 120)
        }
    }
}
