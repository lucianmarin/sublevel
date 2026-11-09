import XCTest
import simd
@testable import Sublevel

final class SublevelTests: XCTestCase {

    func testMovementConfigMatchesSpecification() {
        let cfg = MovementConfig()
        XCTAssertEqual(cfg.maxGroundSpeed, 10.5, accuracy: 0.001)
        XCTAssertEqual(cfg.groundAccel, 12.0, accuracy: 0.001)
        XCTAssertEqual(cfg.friction, 6.0, accuracy: 0.001)
        XCTAssertEqual(cfg.stopSpeed, 3.2, accuracy: 0.001)
        XCTAssertEqual(cfg.maxAirWishSpeed, 1.25, accuracy: 0.001)
        XCTAssertEqual(cfg.airAccel, 2.5, accuracy: 0.001)
        XCTAssertEqual(cfg.cpmAirControl, 150.0, accuracy: 0.001)
        XCTAssertEqual(cfg.gravity, 24.0, accuracy: 0.001)
        XCTAssertEqual(cfg.jumpImpulse, 8.8, accuracy: 0.001)
        XCTAssertEqual(cfg.dodgeImpulseHorizontal, 13.5, accuracy: 0.001)
        XCTAssertEqual(cfg.dodgeImpulseVertical, 5.2, accuracy: 0.001)
        XCTAssertEqual(cfg.dodgeCooldown, 0.35, accuracy: 0.001)
        XCTAssertEqual(cfg.wallDodgeMaxCount, 2)
        XCTAssertEqual(cfg.slideFrictionMultiplier, 0.15, accuracy: 0.001)
    }

    func testQuake3StrafeJumpingExceedsGroundSpeedCap() {
        let cfg = MovementConfig()
        var vel = SIMD3<Float>(0, 0, -cfg.maxGroundSpeed)

        // Simulate 30 air frames where player steers wishDir at the optimal Q3 strafe angle (projection < maxAirWishSpeed)
        for _ in 0..<30 {
            let vNorm = simd_normalize(SIMD3<Float>(vel.x, 0, vel.z))
            let perp = SIMD3<Float>(-vNorm.z, 0, vNorm.x)
            let wishDir = simd_normalize(vNorm * 0.05 + perp * 0.998)
            MovementSolver.accelerate(
                velocity: &vel,
                wishDir: wishDir,
                wishSpeed: cfg.maxAirWishSpeed,
                accel: cfg.airAccel,
                delta: 1.0 / 60.0,
                baseScaleSpeed: cfg.maxGroundSpeed
            )
        }

        let newSpeed = simd_length(SIMD2<Float>(vel.x, vel.z))
        XCTAssertGreaterThan(newSpeed, cfg.maxGroundSpeed + 0.8, "Q3 air strafe-jumping should exceed ground speed cap")
    }

    func testAutoHopPreservesHorizontalMomentumOnLandingFrame() {
        let cfg = MovementConfig()
        let floor = WorldBoxCollider(
            id: 0,
            center: SIMD3<Float>(0, -0.5, 0),
            size: SIMD3<Float>(100, 1.0, 100),
            color: SublevelPalette.starkWhite
        )
        var state = KinematicState(position: SIMD3<Float>(0, 0.0, 0))
        state.velocity = SIMD3<Float>(15.0, 0.0, 0.0) // Above max ground speed (e.g. bunny-hopping at 457 u/s)
        state.isOnFloor = true

        var input = MovementInput()
        input.jumpHeld = true

        MovementSolver.step(state: &state, input: input, config: cfg, colliders: [floor], delta: 1.0 / 60.0)

        XCTAssertFalse(state.isOnFloor)
        XCTAssertEqual(state.velocity.x, 15.0, accuracy: 0.001, "Auto-hop must skip ground friction and preserve 100% horizontal speed")
        XCTAssertGreaterThan(state.velocity.y, 8.0)
    }

    func testUT99GroundAndWallDodge() {
        let cfg = MovementConfig()
        let floor = WorldBoxCollider(
            id: 0,
            center: SIMD3<Float>(0, -0.5, 0),
            size: SIMD3<Float>(100, 1.0, 100),
            color: SublevelPalette.starkWhite
        )
        let wall = WorldBoxCollider(
            id: 1,
            center: SIMD3<Float>(-1.0, 3.0, 0),
            size: SIMD3<Float>(1.0, 6.0, 20.0),
            color: SublevelPalette.signalRed,
            kind: .kineticPanel
        )

        var state = KinematicState(position: SIMD3<Float>(0, 0.0, 0))
        var input = MovementInput()
        input.dodgeRequested = true
        input.dodgeDirectionLocal = SIMD2<Float>(1, 0)

        // Ground dodge
        MovementSolver.step(state: &state, input: input, config: cfg, colliders: [floor, wall], delta: 1.0 / 60.0)
        XCTAssertTrue(state.lastDodgeTriggered)
        XCTAssertGreaterThan(state.horizontalSpeed, 13.0)

        // Airborne wall dodge near wall at x = -0.5
        state.position = SIMD3<Float>(-0.2, 2.5, 0)
        state.isOnFloor = false
        state.dodgeCooldownTimer = 0.0
        MovementSolver.step(state: &state, input: input, config: cfg, colliders: [floor, wall], delta: 1.0 / 60.0)
        XCTAssertTrue(state.lastWallDodgeTriggered)
        XCTAssertEqual(state.wallDodgesUsed, 1)
    }

    func testStairSteppingPreservesVelocity() {
        let cfg = MovementConfig()
        let floor = WorldBoxCollider(
            id: 0,
            center: SIMD3<Float>(0, -0.5, 0),
            size: SIMD3<Float>(100, 1.0, 100),
            color: SublevelPalette.starkWhite
        )
        // 0.35m step (within 0.45m maxStepHeight)
        let stair = WorldBoxCollider(
            id: 1,
            center: SIMD3<Float>(1.0, 0.175, 0),
            size: SIMD3<Float>(1.2, 0.35, 4.0),
            color: SublevelPalette.warmGray
        )

        var state = KinematicState(position: SIMD3<Float>(0.1, 0.0, 0))
        state.velocity = SIMD3<Float>(12.0, 0, 0)
        state.isOnFloor = true

        let input = MovementInput()
        MovementSolver.step(state: &state, input: input, config: cfg, colliders: [floor, stair], delta: 1.0 / 60.0)

        XCTAssertEqual(state.position.y, 0.35, accuracy: 0.01, "Should step up 0.35m stair")
        XCTAssertGreaterThan(state.velocity.x, 10.0, "Horizontal speed should not be zeroed by stair")
    }

    func testPrismRifleShockComboAndDynamicBreach() {
        var arena = ArenaMap()
        // Place a Shock Orb right above the B1 North Skylight shatterFloor (0, 11.65, -7.75)
        let orbPos = SIMD3<Float>(0, 12.2, -7.75)
        var projectiles: [Projectile] = [
            Projectile(
                id: 1,
                ownerID: 0,
                kind: .shockOrb,
                position: orbPos,
                velocity: SIMD3<Float>(0, 0, 10),
                damage: 55.0,
                splashRadius: 3.2,
                comboHitboxRadius: 1.55,
                color: SublevelPalette.electricCyan
            )
        ]
        let botTarget = CombatActorTarget(id: 1, feetPosition: SIMD3<Float>(1.5, 12.0, -7.75))
        var beams: [BeamSegmentFX] = []
        var spheres: [ShockSphereFX] = []

        let result = WeaponSystem.firePrismBeam(
            shooterID: 0,
            origin: SIMD3<Float>(0, 12.2, -16.0),
            direction: SIMD3<Float>(0, 0, 1),
            damageMultiplier: 1.0,
            arena: &arena,
            projectiles: &projectiles,
            actors: [botTarget],
            beams: &beams,
            spheres: &spheres
        )

        XCTAssertTrue(result.triggeredShockCombo, "Primary beam hitting Alt-Fire Shock Orb must trigger Shock Combo")
        XCTAssertTrue(projectiles.isEmpty, "Detonated Shock Orb should be consumed")
        XCTAssertGreaterThanOrEqual(result.breachedCount, 1, "Shock Combo should shatter nearby B1 skylight glass plate")
        XCTAssertEqual(result.events.count, 1)
        XCTAssertGreaterThan(result.events[0].damage, 120.0, "Shock Combo deals up to 160 splash damage")
    }

    func testRocketJumpReducedSelfDamage() {
        let selfTarget = CombatActorTarget(id: 0, feetPosition: SIMD3<Float>(0, 0, 0))
        let enemyTarget = CombatActorTarget(id: 1, feetPosition: SIMD3<Float>(0, 0, 0))
        let events = WeaponSystem.evaluateRadialExplosion(
            attackerID: 0,
            center: SIMD3<Float>(0, 0.1, 0),
            radius: 5.8,
            baseDamage: 100.0,
            baseImpulse: 16.8,
            selfDamageMultiplier: WeaponSystem.rocketSelfDamageMultiplier,
            weapon: .vectorLauncher,
            isShockCombo: false,
            actors: [selfTarget, enemyTarget]
        )

        let selfEv = events.first(where: { $0.targetID == 0 })!
        let enemyEv = events.first(where: { $0.targetID == 1 })!
        XCTAssertEqual(selfEv.damage / enemyEv.damage, 0.40, accuracy: 0.01, "Rocket self-damage must be 0.4x")
        XCTAssertGreaterThan(selfEv.knockback.y, 10.0, "Rocket jump must grant strong vertical impulse")
    }

    func testStratumClassificationAndReverb() {
        XCTAssertEqual(Stratum.forElevation(14.0), .b1Atrium)
        XCTAssertEqual(Stratum.forElevation(2.0), .b2Concourse)
        XCTAssertEqual(Stratum.forElevation(-10.0), .b3Sump)
        XCTAssertLessThan(Stratum.b1Atrium.reverbWetMix, Stratum.b2Concourse.reverbWetMix)
        XCTAssertLessThan(Stratum.b2Concourse.reverbWetMix, Stratum.b3Sump.reverbWetMix)
    }

    func testFullSimulationWeaponsAndBotsTick() {
        let sim = SublevelSimulation()
        var input = MovementInput()
        input.moveForward = 1.0
        input.jumpHeld = true

        // Cycle and fire all 5 weapons across simulation ticks
        for slot in WeaponSlot.allCases {
            sim.currentWeapon = slot
            sim.primaryCooldownTimer = 0
            sim.altCooldownTimer = 0
            sim.triggerPlayerPrimaryFire()
            sim.triggerPlayerAltFire()
        }

        for _ in 0..<30 {
            sim.update(
                input: input,
                primaryFireHeld: false,
                altFireHeld: false,
                altFireJustReleased: false,
                delta: 1.0 / 60.0
            )
        }

        XCTAssertEqual(sim.currentTick, 30)
        XCTAssertEqual(sim.tickHistory.count, 30)
        XCTAssertEqual(sim.bots.count, 4)
    }
}
