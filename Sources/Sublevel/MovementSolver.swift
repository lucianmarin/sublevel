import Foundation
import simd

/// Exact Kinematic Constants from README.md Section 3.1
public struct MovementConfig: Sendable {
    // Ground Movement
    public var maxGroundSpeed: Float = 10.5      // m/s (~320 ups equivalent)
    public var groundAccel: Float = 12.0
    public var friction: Float = 6.0
    public var stopSpeed: Float = 3.2

    // Air / Quake 3 Physics
    public var maxAirWishSpeed: Float = 1.25     // Low wish-speed cap enables Q3 strafe-jumping
    public var airAccel: Float = 2.5
    public var cpmAirControl: Float = 150.0      // Optional CPMA W-only air turning
    public var gravity: Float = 24.0
    public var jumpImpulse: Float = 8.8          // Auto-hop on hold

    // UT99 Dodge & Wall Tech
    public var dodgeImpulseHorizontal: Float = 13.5
    public var dodgeImpulseVertical: Float = 5.2
    public var dodgeCooldown: Float = 0.35
    public var wallDodgeMaxCount: Int = 2
    public var slideFrictionMultiplier: Float = 0.15

    // Additional Sublevel constants from Section 3.2 & 7
    public var jumpBufferWindow: Float = 0.10
    public var slamGravityMultiplier: Float = 2.2
    public var maxStepHeight: Float = 0.45
    public var hullRadius: Float = 0.40          // 0.8m diameter capsule
    public var hullHeight: Float = 1.80          // 1.8m height

    public init() {}
}

public enum ColliderSurfaceKind: Int, Sendable {
    case standard = 0
    case kineticPanel = 1   // Signal Red wall-dodge / ramp surface
    case rampPosX = 2       // Upward slope toward +X (trimping ramp)
    case rampNegX = 3       // Upward slope toward -X
    case rampPosZ = 4       // Upward slope toward +Z
    case rampNegZ = 5       // Upward slope toward -Z
    case shatterFloor = 6   // Destructible glass skylight / concrete floor plate
}

public struct WorldBoxCollider: Sendable {
    public var id: Int
    public var minBounds: SIMD3<Float>
    public var maxBounds: SIMD3<Float>
    public var color: SIMD3<Float>
    public var kind: ColliderSurfaceKind
    public var isDestroyed: Bool
    public var health: Float
    public var metallic: Float
    public var roughness: Float
    public var emissiveStrength: Float

    public init(
        id: Int,
        center: SIMD3<Float>,
        size: SIMD3<Float>,
        color: SIMD3<Float>,
        kind: ColliderSurfaceKind = .standard,
        health: Float = 100.0,
        roughness: Float = 0.35,
        metallic: Float = 0.05,
        emissiveStrength: Float = 0.0
    ) {
        self.id = id
        let half = size * 0.5
        self.minBounds = center - half
        self.maxBounds = center + half
        self.color = color
        self.kind = kind
        self.isDestroyed = false
        self.health = health
        self.roughness = roughness
        self.metallic = metallic
        self.emissiveStrength = emissiveStrength
    }

    public var center: SIMD3<Float> {
        (minBounds + maxBounds) * 0.5
    }

    public var size: SIMD3<Float> {
        maxBounds - minBounds
    }

    /// Evaluates ramp top height at a given (x, z)
    public func surfaceHeight(atX x: Float, z: Float) -> Float {
        switch kind {
        case .rampPosX:
            let t = simd_clamp((x - minBounds.x) / max(maxBounds.x - minBounds.x, 0.001), 0.0, 1.0)
            return minBounds.y + t * (maxBounds.y - minBounds.y)
        case .rampNegX:
            let t = simd_clamp((maxBounds.x - x) / max(maxBounds.x - minBounds.x, 0.001), 0.0, 1.0)
            return minBounds.y + t * (maxBounds.y - minBounds.y)
        case .rampPosZ:
            let t = simd_clamp((z - minBounds.z) / max(maxBounds.z - minBounds.z, 0.001), 0.0, 1.0)
            return minBounds.y + t * (maxBounds.y - minBounds.y)
        case .rampNegZ:
            let t = simd_clamp((maxBounds.z - z) / max(maxBounds.z - minBounds.z, 0.001), 0.0, 1.0)
            return minBounds.y + t * (maxBounds.y - minBounds.y)
        default:
            return maxBounds.y
        }
    }

    public var rampNormal: SIMD3<Float> {
        let dx = max(maxBounds.x - minBounds.x, 0.001)
        let dy = max(maxBounds.y - minBounds.y, 0.001)
        let dz = max(maxBounds.z - minBounds.z, 0.001)
        switch kind {
        case .rampPosX:
            return simd_normalize(SIMD3<Float>(-dy, dx, 0))
        case .rampNegX:
            return simd_normalize(SIMD3<Float>(dy, dx, 0))
        case .rampPosZ:
            return simd_normalize(SIMD3<Float>(0, dz, -dy))
        case .rampNegZ:
            return simd_normalize(SIMD3<Float>(0, dz, dy))
        default:
            return SIMD3<Float>(0, 1, 0)
        }
    }
}

public struct MovementInput: Sendable {
    public var moveForward: Float = 0.0  // -1..1
    public var moveRight: Float = 0.0    // -1..1
    public var yaw: Float = 0.0          // radians
    public var pitch: Float = 0.0        // radians
    public var jumpHeld: Bool = false
    public var jumpJustPressed: Bool = false
    public var crouchHeld: Bool = false
    public var dodgeRequested: Bool = false
    public var dodgeDirectionLocal: SIMD2<Float> = .zero // (right, forward)

    public init() {}
}

public struct KinematicState: Sendable {
    public var position: SIMD3<Float>      // Feet position
    public var velocity: SIMD3<Float>
    public var isOnFloor: Bool
    public var floorNormal: SIMD3<Float>
    public var jumpBufferTimer: Float
    public var dodgeCooldownTimer: Float
    public var wallDodgesUsed: Int
    public var isSliding: Bool
    public var isSlamming: Bool
    public var airtime: Float
    public var lastDodgeTriggered: Bool
    public var lastWallDodgeTriggered: Bool
    public var lastStepUpAmount: Float
    public var lastLandingImpactSpeed: Float

    public init(position: SIMD3<Float> = SIMD3<Float>(0, 12.5, 0)) {
        self.position = position
        self.velocity = .zero
        self.isOnFloor = true
        self.floorNormal = SIMD3<Float>(0, 1, 0)
        self.jumpBufferTimer = 0.0
        self.dodgeCooldownTimer = 0.0
        self.wallDodgesUsed = 0
        self.isSliding = false
        self.isSlamming = false
        self.airtime = 0.0
        self.lastDodgeTriggered = false
        self.lastWallDodgeTriggered = false
        self.lastStepUpAmount = 0.0
        self.lastLandingImpactSpeed = 0.0
    }

    public var horizontalSpeed: Float {
        simd_length(SIMD2<Float>(velocity.x, velocity.z))
    }

    public var speedUPS: Float {
        horizontalSpeed * Math3D.upsPerMeter
    }

    public var eyePosition: SIMD3<Float> {
        let eyeHeight: Float = isSliding ? 1.05 : 1.62
        return position + SIMD3<Float>(0, eyeHeight, 0)
    }
}

/// Pure math Q3 (`PM_Accelerate`) + CPMA + UT99 Dodge + Ramp Trimping + Stair Stepping Solver
public enum MovementSolver {

    /// Exact Quake 3 PM_Accelerate / PM_AirAccelerate implementation from README Section 3.2
    public static func accelerate(
        velocity: inout SIMD3<Float>,
        wishDir: SIMD3<Float>,
        wishSpeed: Float,
        accel: Float,
        delta: Float,
        baseScaleSpeed: Float? = nil
    ) {
        let currentSpeed = simd_dot(velocity, wishDir)
        let addSpeed = wishSpeed - currentSpeed
        if addSpeed <= 0.0 {
            return
        }
        let refSpeed = baseScaleSpeed ?? wishSpeed
        let accelSpeed = min(accel * delta * refSpeed, addSpeed)
        velocity += wishDir * accelSpeed
    }

    /// Ground friction with slide multiplier support
    public static func applyFriction(
        velocity: inout SIMD3<Float>,
        config: MovementConfig,
        isSliding: Bool,
        delta: Float
    ) {
        let horiz = SIMD2<Float>(velocity.x, velocity.z)
        let speed = simd_length(horiz)
        if speed < 0.001 {
            velocity.x = 0
            velocity.z = 0
            return
        }

        let effectiveFriction = isSliding ? (config.friction * config.slideFrictionMultiplier) : config.friction
        let control = max(speed, config.stopSpeed)
        let drop = control * effectiveFriction * delta
        let newSpeed = max(speed - drop, 0.0) / speed
        velocity.x *= newSpeed
        velocity.z *= newSpeed
    }

    /// CPMA W-only / air-control turning so players can carve tight corners at 600+ ups
    public static func applyCPMAirControl(
        velocity: inout SIMD3<Float>,
        wishDir: SIMD3<Float>,
        wishSpeed: Float,
        moveForward: Float,
        moveRight: Float,
        config: MovementConfig,
        delta: Float
    ) {
        guard abs(moveRight) < 0.01 && abs(moveForward) > 0.1 && wishSpeed > 0.001 else { return }
        let zSpeed = velocity.y
        velocity.y = 0
        let speed = simd_length(velocity)
        guard speed > 0.1 else {
            velocity.y = zSpeed
            return
        }
        let velDir = velocity / speed
        let dot = simd_dot(velDir, wishDir)
        if dot > 0.0 {
            let k: Float = 32.0 * config.cpmAirControl * dot * dot * delta
            let combined = simd_normalize(velDir * speed + wishDir * k)
            velocity = combined * speed
        }
        velocity.y = zSpeed
    }

    /// Computes world-space wish direction from local (moveRight, moveForward) and yaw
    public static func computeWishDir(yaw: Float, moveRight: Float, moveForward: Float) -> SIMD3<Float> {
        let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let raw = right * moveRight + forward * moveForward
        let len = simd_length(raw)
        return len > 0.001 ? (raw / len) : .zero
    }

    /// ShapeCast3D-equivalent cylinder ring wall detector for UT99 Wall-Dodge
    public static func detectNearbyWallNormal(
        position: SIMD3<Float>,
        radius: Float,
        height: Float,
        colliders: [WorldBoxCollider]
    ) -> SIMD3<Float>? {
        let probeRadius = radius + 0.55
        let waistY = position.y + height * 0.5
        var bestDist: Float = probeRadius
        var bestNormal: SIMD3<Float>? = nil

        for box in colliders where !box.isDestroyed {
            guard waistY >= box.minBounds.y && waistY <= box.maxBounds.y else { continue }
            let clampedX = simd_clamp(position.x, box.minBounds.x, box.maxBounds.x)
            let clampedZ = simd_clamp(position.z, box.minBounds.z, box.maxBounds.z)
            let dx = position.x - clampedX
            let dz = position.z - clampedZ
            let dist = hypot(dx, dz)
            if dist < bestDist && dist > 1e-4 {
                bestDist = dist
                bestNormal = SIMD3<Float>(dx / dist, 0, dz / dist)
            }
        }
        return bestNormal
    }

    /// Full physics tick pipeline matching README Section 3.2
    public static func step(
        state: inout KinematicState,
        input: MovementInput,
        config: MovementConfig,
        colliders: [WorldBoxCollider],
        delta: Float
    ) {
        state.lastDodgeTriggered = false
        state.lastWallDodgeTriggered = false
        state.lastStepUpAmount = 0.0
        state.lastLandingImpactSpeed = 0.0

        // 1. Input Sampling & Timers
        if input.jumpJustPressed {
            state.jumpBufferTimer = config.jumpBufferWindow
        } else {
            state.jumpBufferTimer = max(0.0, state.jumpBufferTimer - delta)
        }
        state.dodgeCooldownTimer = max(0.0, state.dodgeCooldownTimer - delta)

        let wishDir = computeWishDir(yaw: input.yaw, moveRight: input.moveRight, moveForward: input.moveForward)
        let dodgeDir: SIMD3<Float> = {
            if simd_length(input.dodgeDirectionLocal) > 0.01 {
                return computeWishDir(
                    yaw: input.yaw,
                    moveRight: input.dodgeDirectionLocal.x,
                    moveForward: input.dodgeDirectionLocal.y
                )
            }
            return wishDir != .zero ? wishDir : computeWishDir(yaw: input.yaw, moveRight: 0, moveForward: 1)
        }()

        // 2. Ground Check & Queue Jump (Auto-hop on hold or buffered jump skips ground friction!)
        var skippedFrictionForJump = false
        if state.isOnFloor {
            state.wallDodgesUsed = 0
            state.airtime = 0.0
            state.isSlamming = false

            if input.jumpHeld || state.jumpBufferTimer > 0.0 {
                // Trimping: if jumping on an upward ramp with horizontal velocity moving up the slope,
                // add ramp-deflected vertical velocity on top of jump impulse!
                if state.floorNormal.y < 0.99 {
                    let slopeBoost = max(0.0, -simd_dot(SIMD3<Float>(state.velocity.x, 0, state.velocity.z), SIMD3<Float>(state.floorNormal.x, 0, state.floorNormal.z))) * 0.45
                    state.velocity.y = config.jumpImpulse + slopeBoost
                } else {
                    state.velocity.y = config.jumpImpulse
                }
                state.isOnFloor = false
                state.jumpBufferTimer = 0.0
                skippedFrictionForJump = true
            }
        } else {
            state.airtime += delta
        }

        // 3. UT99 Dodge & Wall-Dodge
        if input.dodgeRequested && state.dodgeCooldownTimer <= 0.0 && dodgeDir != .zero {
            if state.isOnFloor {
                // Ground Dodge: Instant horizontal burst + low vertical hop
                state.velocity.x = dodgeDir.x * config.dodgeImpulseHorizontal + state.velocity.x * 0.35
                state.velocity.z = dodgeDir.z * config.dodgeImpulseHorizontal + state.velocity.z * 0.35
                state.velocity.y = config.dodgeImpulseVertical
                state.isOnFloor = false
                state.dodgeCooldownTimer = config.dodgeCooldown
                state.lastDodgeTriggered = true
                skippedFrictionForJump = true
            } else if state.wallDodgesUsed < config.wallDodgeMaxCount {
                // Wall Dodge: Check nearby wall via cylinder detector
                if let wallNormal = detectNearbyWallNormal(
                    position: state.position,
                    radius: config.hullRadius,
                    height: config.hullHeight,
                    colliders: colliders
                ) {
                    // Combine wall normal push with desired directional input
                    var pushDir = wallNormal * 0.65 + dodgeDir * 0.75
                    pushDir.y = 0
                    if simd_length(pushDir) < 0.01 {
                        pushDir = wallNormal
                    } else {
                        pushDir = simd_normalize(pushDir)
                    }
                    let preservedSpeed = max(state.horizontalSpeed * 0.7, config.dodgeImpulseHorizontal)
                    state.velocity.x = pushDir.x * preservedSpeed
                    state.velocity.z = pushDir.z * preservedSpeed
                    state.velocity.y = max(state.velocity.y * 0.4 + config.dodgeImpulseVertical, config.dodgeImpulseVertical)
                    state.wallDodgesUsed += 1
                    state.dodgeCooldownTimer = config.dodgeCooldown
                    state.lastWallDodgeTriggered = true
                }
            }
        }

        // 4. Sublevel Slam / Slide & Ground vs. Air Acceleration
        if state.isOnFloor && !skippedFrictionForJump {
            state.isSliding = input.crouchHeld && state.horizontalSpeed > (config.maxGroundSpeed * 0.65)
            applyFriction(velocity: &state.velocity, config: config, isSliding: state.isSliding, delta: delta)
            if wishDir != .zero {
                accelerate(
                    velocity: &state.velocity,
                    wishDir: wishDir,
                    wishSpeed: config.maxGroundSpeed,
                    accel: config.groundAccel,
                    delta: delta
                )
            }
        } else {
            state.isSliding = false
            // Air acceleration with low wishSpeed cap (1.25 m/s) for Q3 strafe-jumping
            if wishDir != .zero {
                accelerate(
                    velocity: &state.velocity,
                    wishDir: wishDir,
                    wishSpeed: config.maxAirWishSpeed,
                    accel: config.airAccel,
                    delta: delta,
                    baseScaleSpeed: config.maxGroundSpeed
                )
                applyCPMAirControl(
                    velocity: &state.velocity,
                    wishDir: wishDir,
                    wishSpeed: config.maxAirWishSpeed,
                    moveForward: input.moveForward,
                    moveRight: input.moveRight,
                    config: config,
                    delta: delta
                )
            }

            // Sublevel Slam: Holding crouch mid-air increases downward gravity (2.2x)
            state.isSlamming = input.crouchHeld
            let gravMult: Float = state.isSlamming ? config.slamGravityMultiplier : 1.0
            state.velocity.y -= config.gravity * gravMult * delta
        }

        // 5. Move, Collide, Stair Stepping (up to 0.45m) & Ramp Trimping
        resolveMovementAndCollisions(
            state: &state,
            input: input,
            config: config,
            colliders: colliders,
            delta: delta
        )
    }

    private static func resolveMovementAndCollisions(
        state: inout KinematicState,
        input: MovementInput,
        config: MovementConfig,
        colliders: [WorldBoxCollider],
        delta: Float
    ) {
        let prevVelY = state.velocity.y
        let wasOnFloor = state.isOnFloor
        var nextPos = state.position + state.velocity * delta
        let r = config.hullRadius
        let h = config.hullHeight

        // Horizontal collision & Stair Stepper (up to 0.45m)
        for box in colliders where !box.isDestroyed {
            // Skip pure ramps for wall blocking if within ramp height
            if box.kind == .rampPosX || box.kind == .rampNegX || box.kind == .rampPosZ || box.kind == .rampNegZ {
                continue
            }

            let expandedMinX = box.minBounds.x - r
            let expandedMaxX = box.maxBounds.x + r
            let expandedMinZ = box.minBounds.z - r
            let expandedMaxZ = box.maxBounds.z + r

            guard nextPos.x > expandedMinX && nextPos.x < expandedMaxX &&
                  nextPos.z > expandedMinZ && nextPos.z < expandedMaxZ else {
                continue
            }

            // Check vertical overlap
            if nextPos.y < box.maxBounds.y && (nextPos.y + h) > box.minBounds.y {
                let stepDelta = box.maxBounds.y - nextPos.y
                // Stair stepping: if obstacle top is within maxStepHeight (0.45m), step up seamlessly!
                if stepDelta > 0.0 && stepDelta <= config.maxStepHeight && state.velocity.y <= 0.5 {
                    nextPos.y = box.maxBounds.y
                    state.lastStepUpAmount = max(state.lastStepUpAmount, stepDelta)
                    continue
                }

                // Push out along minimal penetration axis on XZ
                let penLeft = nextPos.x - expandedMinX
                let penRight = expandedMaxX - nextPos.x
                let penBack = nextPos.z - expandedMinZ
                let penFront = expandedMaxZ - nextPos.z
                let minPen = min(min(penLeft, penRight), min(penBack, penFront))

                if minPen == penLeft {
                    nextPos.x = expandedMinX
                    if state.velocity.x > 0 { state.velocity.x = 0 }
                } else if minPen == penRight {
                    nextPos.x = expandedMaxX
                    if state.velocity.x < 0 { state.velocity.x = 0 }
                } else if minPen == penBack {
                    nextPos.z = expandedMinZ
                    if state.velocity.z > 0 { state.velocity.z = 0 }
                } else {
                    nextPos.z = expandedMaxZ
                    if state.velocity.z < 0 { state.velocity.z = 0 }
                }
            }
        }

        // Vertical floor / ramp / ceiling resolution
        var grounded = false
        var bestFloorY: Float = -10000.0
        var bestFloorNormal = SIMD3<Float>(0, 1, 0)

        for box in colliders where !box.isDestroyed {
            let expandedMinX = box.minBounds.x - r * 0.75
            let expandedMaxX = box.maxBounds.x + r * 0.75
            let expandedMinZ = box.minBounds.z - r * 0.75
            let expandedMaxZ = box.maxBounds.z + r * 0.75

            guard nextPos.x >= expandedMinX && nextPos.x <= expandedMaxX &&
                  nextPos.z >= expandedMinZ && nextPos.z <= expandedMaxZ else {
                continue
            }

            let topY = box.surfaceHeight(atX: nextPos.x, z: nextPos.z)
            let isRamp = (box.kind == .rampPosX || box.kind == .rampNegX || box.kind == .rampPosZ || box.kind == .rampNegZ)

            // Check landing / riding floor or ramp
            let snapTolerance: Float = (wasOnFloor || isRamp) ? config.maxStepHeight : 0.20
            if state.position.y >= topY - snapTolerance && nextPos.y <= topY + 0.08 && state.velocity.y <= 3.5 {
                if topY > bestFloorY {
                    bestFloorY = topY
                    bestFloorNormal = box.rampNormal
                    grounded = true
                }
            } else if !isRamp && state.velocity.y > 0 && (state.position.y + h) <= box.minBounds.y + 0.15 && (nextPos.y + h) > box.minBounds.y {
                // Ceiling hit
                nextPos.y = box.minBounds.y - h
                state.velocity.y = 0
            }
        }

        if grounded {
            nextPos.y = bestFloorY
            // Trimping on upward ramps: when moving fast up a ramp while jumping or skimming, convert horizontal speed into vertical launch
            if bestFloorNormal.y < 0.99 {
                let horizVel = SIMD3<Float>(state.velocity.x, 0, state.velocity.z)
                let intoSlope = -simd_dot(horizVel, SIMD3<Float>(bestFloorNormal.x, 0, bestFloorNormal.z))
                if intoSlope > config.maxGroundSpeed * 1.05 && input.jumpHeld {
                    // Launch off ramp ("trimping")
                    state.velocity.y = intoSlope * (1.0 - bestFloorNormal.y * 0.35) + config.jumpImpulse * 0.55
                    state.isOnFloor = false
                    state.position = nextPos
                    return
                }
            }

            if !wasOnFloor && prevVelY < -2.0 {
                state.lastLandingImpactSpeed = -prevVelY
                // Landing while holding crouch or on a ramp converts vertical velocity into horizontal slide boost!
                if input.crouchHeld || bestFloorNormal.y < 0.99 {
                    let boost = min(-prevVelY * 0.28, 7.5)
                    let horiz = SIMD2<Float>(state.velocity.x, state.velocity.z)
                    let len = simd_length(horiz)
                    if len > 0.5 {
                        let dir = horiz / len
                        state.velocity.x += dir.x * boost
                        state.velocity.z += dir.y * boost
                    }
                    state.isSliding = true
                }
            }
            state.velocity.y = 0
            state.isOnFloor = true
            state.floorNormal = bestFloorNormal
        } else {
            state.isOnFloor = false
            state.floorNormal = SIMD3<Float>(0, 1, 0)
        }

        state.position = nextPos
    }
}

/// Camera FX: Strafe roll tilt, FOV speed scaling, landing punch, and weapon recoil/bob
public struct CameraFXState: Sendable {
    public var baseFOVDegrees: Float = 105.0
    public var currentFOVDegrees: Float = 105.0
    public var rollAngleRadians: Float = 0.0
    public var landingPunchOffset: Float = 0.0
    public var landingPunchVelocity: Float = 0.0
    public var recoilPitch: Float = 0.0
    public var bobPhase: Float = 0.0
    public var damageFlash: Float = 0.0
    public var breachShake: Float = 0.0

    public init() {}

    public mutating func update(
        kinematic: KinematicState,
        input: MovementInput,
        isZoomed: Bool,
        delta: Float
    ) {
        // 1. Strafe Roll Tilt
        let targetRoll = -input.moveRight * 0.038 - (kinematic.isSliding ? 0.045 : 0.0)
        rollAngleRadians += (targetRoll - rollAngleRadians) * min(1.0, delta * 12.0)

        // 2. Speed-scaled FOV (105 base -> up to 122 at high u/s, or 48 when Sub-Rail zoomed)
        let speedExcess = max(0.0, kinematic.horizontalSpeed - 10.5)
        let speedFOVBoost = min(speedExcess * 0.95, 17.0)
        let targetFOV: Float = isZoomed ? 46.0 : (baseFOVDegrees + speedFOVBoost)
        currentFOVDegrees += (targetFOV - currentFOVDegrees) * min(1.0, delta * 10.0)

        // 3. Landing punch spring
        if kinematic.lastLandingImpactSpeed > 3.0 {
            landingPunchVelocity -= min(kinematic.lastLandingImpactSpeed * 0.035, 0.45)
        }
        let springK: Float = 140.0
        let damping: Float = 16.0
        let springAccel = -springK * landingPunchOffset - damping * landingPunchVelocity
        landingPunchVelocity += springAccel * delta
        landingPunchOffset += landingPunchVelocity * delta

        // 4. Recoil recovery & Bob
        recoilPitch = max(0.0, recoilPitch - delta * 4.5)
        damageFlash = max(0.0, damageFlash - delta * 2.8)
        breachShake = max(0.0, breachShake - delta * 2.2)

        if kinematic.isOnFloor && kinematic.horizontalSpeed > 0.5 && !kinematic.isSliding {
            bobPhase += kinematic.horizontalSpeed * delta * 1.35
        }
    }
}
