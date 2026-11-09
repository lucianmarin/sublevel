import Foundation
import simd

public enum WeaponSlot: Int, CaseIterable, Sendable {
    case kineticGauntlet = 1
    case prismRifle = 2
    case shardCannon = 3
    case vectorLauncher = 4
    case subRail = 5

    public var displayName: String {
        switch self {
        case .kineticGauntlet: return "1 // KINETIC GAUNTLET"
        case .prismRifle:      return "2 // PRISM RIFLE"
        case .shardCannon:     return "3 // SHARD CANNON"
        case .vectorLauncher: return "4 // VECTOR LAUNCHER"
        case .subRail:         return "5 // SUB-RAIL"
        }
    }

    public var shortName: String {
        switch self {
        case .kineticGauntlet: return "GAUNTLET"
        case .prismRifle:      return "PRISM"
        case .shardCannon:     return "SHARD"
        case .vectorLauncher: return "VECTOR"
        case .subRail:         return "SUB-RAIL"
        }
    }

    public var accentColor: SIMD3<Float> {
        switch self {
        case .kineticGauntlet: return SublevelPalette.signalRed
        case .prismRifle:      return SublevelPalette.electricCyan
        case .shardCannon:     return SublevelPalette.amberOrange
        case .vectorLauncher: return SublevelPalette.crimson
        case .subRail:         return SublevelPalette.cobaltViolet
        }
    }

    public var primaryCooldown: Float {
        switch self {
        case .kineticGauntlet: return 0.42
        case .prismRifle:      return 0.55
        case .shardCannon:     return 0.68
        case .vectorLauncher: return 0.75
        case .subRail:         return 1.15
        }
    }

    public var altCooldown: Float {
        switch self {
        case .kineticGauntlet: return 0.55
        case .prismRifle:      return 0.52
        case .shardCannon:     return 0.82
        case .vectorLauncher: return 1.10
        case .subRail:         return 0.95
        }
    }
}

public enum ProjectileKind: Int, Sendable {
    case shockOrb = 0       // Prism Rifle Alt-Fire (55 dmg, 1.35m combo hurtbox for 160-dmg Shock Combo)
    case shardPellet = 1    // Shard Cannon Primary (bounces once off walls with glowing orange trail)
    case flakGrenade = 2    // Shard Cannon Alt-Fire (arcing fragmentation grenade)
    case vectorRocket = 3   // Vector Launcher (100 dmg, 0.4x self-damage rocket jump)
}

public struct Projectile: Sendable {
    public var id: Int
    public var ownerID: Int // 0 = local player, >0 = bot id
    public var kind: ProjectileKind
    public var position: SIMD3<Float>
    public var prevPosition: SIMD3<Float>
    public var velocity: SIMD3<Float>
    public var damage: Float
    public var splashRadius: Float
    public var comboHitboxRadius: Float
    public var bouncesRemaining: Int
    public var lifetime: Float
    public var color: SIMD3<Float>
    public var spiralPhase: Float

    public init(
        id: Int,
        ownerID: Int,
        kind: ProjectileKind,
        position: SIMD3<Float>,
        velocity: SIMD3<Float>,
        damage: Float,
        splashRadius: Float,
        comboHitboxRadius: Float = 0.0,
        bouncesRemaining: Int = 0,
        lifetime: Float = 6.0,
        color: SIMD3<Float>,
        spiralPhase: Float = 0.0
    ) {
        self.id = id
        self.ownerID = ownerID
        self.kind = kind
        self.position = position
        self.prevPosition = position
        self.velocity = velocity
        self.damage = damage
        self.splashRadius = splashRadius
        self.comboHitboxRadius = comboHitboxRadius
        self.bouncesRemaining = bouncesRemaining
        self.lifetime = lifetime
        self.color = color
        self.spiralPhase = spiralPhase
    }
}

public struct BeamSegmentFX: Sendable {
    public var start: SIMD3<Float>
    public var end: SIMD3<Float>
    public var color: SIMD3<Float>
    public var thickness: Float
    public var remainingLife: Float
    public var maxLife: Float

    public init(start: SIMD3<Float>, end: SIMD3<Float>, color: SIMD3<Float>, thickness: Float, life: Float) {
        self.start = start
        self.end = end
        self.color = color
        self.thickness = thickness
        self.remainingLife = life
        self.maxLife = life
    }
}

public struct ShockSphereFX: Sendable {
    public var center: SIMD3<Float>
    public var maxRadius: Float
    public var color: SIMD3<Float>
    public var elapsed: Float
    public var duration: Float
    public var isShockCombo: Bool

    public init(center: SIMD3<Float>, maxRadius: Float, color: SIMD3<Float>, duration: Float = 0.48, isShockCombo: Bool = false) {
        self.center = center
        self.maxRadius = maxRadius
        self.color = color
        self.elapsed = 0.0
        self.duration = duration
        self.isShockCombo = isShockCombo
    }

    public var progress: Float {
        simd_clamp(elapsed / max(duration, 0.001), 0.0, 1.0)
    }

    public var currentRadius: Float {
        let t = 1.0 - pow(1.0 - progress, 3.0)
        return maxRadius * t
    }
}

public struct CombatActorTarget: Sendable {
    public var id: Int
    public var feetPosition: SIMD3<Float>
    public var radius: Float
    public var height: Float

    public init(id: Int, feetPosition: SIMD3<Float>, radius: Float = 0.55, height: Float = 1.85) {
        self.id = id
        self.feetPosition = feetPosition
        self.radius = radius
        self.height = height
    }

    public var center: SIMD3<Float> {
        feetPosition + SIMD3<Float>(0, height * 0.5, 0)
    }
}

public struct DamageEvent: Sendable {
    public var attackerID: Int
    public var targetID: Int
    public var damage: Float
    public var knockback: SIMD3<Float>
    public var weapon: WeaponSlot
    public var isShockCombo: Bool
    public var isHeadshotOrMidair: Bool
    public var hitPoint: SIMD3<Float>
}

public enum WeaponSystem {
    public static let shockComboDamage: Float = 160.0
    public static let shockComboRadius: Float = 7.8
    public static let rocketSelfDamageMultiplier: Float = 0.40

    /// Fires a hitscan ray that checks both Shock Orbs (for Shock Combos), actors, and arena geometry
    public static func firePrismBeam(
        shooterID: Int,
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        damageMultiplier: Float,
        arena: inout ArenaMap,
        projectiles: inout [Projectile],
        actors: [CombatActorTarget],
        beams: inout [BeamSegmentFX],
        spheres: inout [ShockSphereFX]
    ) -> (events: [DamageEvent], triggeredShockCombo: Bool, breachedCount: Int) {
        let dir = simd_normalize(direction)
        let worldHit = arena.raycast(origin: origin, dir: dir, maxDist: 250.0)
        var maxRayDist = worldHit.hit ? worldHit.distance : 250.0

        // 1. Check intersection with any active Shock Orb (`shock_combo_orb.gd` equivalent)
        var hitOrbIndex: Int? = nil
        var hitOrbDist: Float = maxRayDist

        for (idx, proj) in projectiles.enumerated() where proj.kind == .shockOrb {
            let sphereHit = Math3D.rayIntersectSphere(
                origin: origin,
                dir: dir,
                center: proj.position,
                radius: max(proj.comboHitboxRadius, 1.35),
                maxDist: hitOrbDist
            )
            if sphereHit.hit && sphereHit.distance < hitOrbDist {
                hitOrbDist = sphereHit.distance
                hitOrbIndex = idx
            }
        }

        if let orbIdx = hitOrbIndex {
            let orbPos = projectiles[orbIdx].position
            projectiles.remove(at: orbIdx)

            // Spawn Shock Combo volumetric sphere FX & beam
            beams.append(BeamSegmentFX(
                start: origin - SIMD3<Float>(0, 0.15, 0),
                end: orbPos,
                color: SublevelPalette.electricCyan,
                thickness: 0.16,
                life: 0.45
            ))
            spheres.append(ShockSphereFX(
                center: orbPos,
                maxRadius: shockComboRadius,
                color: SublevelPalette.electricCyan,
                duration: 0.58,
                isShockCombo: true
            ))

            // Shatter any nearby dynamic breach floors/skylights
            let breached = arena.applyStructuralDamage(at: orbPos, radius: shockComboRadius, damage: shockComboDamage)

            // Apply 160-dmg Shock Combo sphere explosion to all actors in radius
            let events = evaluateRadialExplosion(
                attackerID: shooterID,
                center: orbPos,
                radius: shockComboRadius,
                baseDamage: shockComboDamage * damageMultiplier,
                baseImpulse: 18.5,
                selfDamageMultiplier: 0.35,
                weapon: .prismRifle,
                isShockCombo: true,
                actors: actors
            )
            return (events, true, breached)
        }

        // 2. Otherwise check actor hitscan intersection
        var hitActor: CombatActorTarget? = nil
        var bestActorDist: Float = maxRayDist
        for actor in actors where actor.id != shooterID {
            let minB = actor.feetPosition - SIMD3<Float>(actor.radius, 0, actor.radius)
            let maxB = actor.feetPosition + SIMD3<Float>(actor.radius, actor.height, actor.radius)
            let hit = Math3D.rayIntersectAABB(origin: origin, dir: dir, minBounds: minB, maxBounds: maxB, maxDist: bestActorDist)
            if hit.hit && hit.distance < bestActorDist {
                bestActorDist = hit.distance
                hitActor = actor
            }
        }

        let endPoint = origin + dir * bestActorDist
        beams.append(BeamSegmentFX(
            start: origin - SIMD3<Float>(0, 0.14, 0),
            end: endPoint,
            color: SublevelPalette.electricCyan,
            thickness: 0.09,
            life: 0.30
        ))

        var events: [DamageEvent] = []
        if let target = hitActor {
            let dmg = 45.0 * damageMultiplier
            let kb = dir * 7.5 + SIMD3<Float>(0, 2.5, 0)
            events.append(DamageEvent(
                attackerID: shooterID,
                targetID: target.id,
                damage: dmg,
                knockback: kb,
                weapon: .prismRifle,
                isShockCombo: false,
                isHeadshotOrMidair: false,
                hitPoint: endPoint
            ))
            spheres.append(ShockSphereFX(center: endPoint, maxRadius: 1.2, color: SublevelPalette.electricCyan, duration: 0.22))
        } else if worldHit.hit {
            maxRayDist = worldHit.distance
            spheres.append(ShockSphereFX(center: worldHit.point, maxRadius: 0.7, color: SublevelPalette.electricCyan, duration: 0.18))
        }

        return (events, false, 0)
    }

    /// Fires Sub-Rail piercing 90-dmg slug (alt-fire pierces thin sublevel shatter floors!)
    public static func fireSubRailSlug(
        shooterID: Int,
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        pierceFloors: Bool,
        damageMultiplier: Float,
        arena: inout ArenaMap,
        actors: [CombatActorTarget],
        beams: inout [BeamSegmentFX],
        spheres: inout [ShockSphereFX]
    ) -> (events: [DamageEvent], breachedCount: Int) {
        let dir = simd_normalize(direction)
        var breached = 0

        if pierceFloors {
            // Check if ray intersects a shatterFloor and breach it while continuing through!
            let firstHit = arena.raycast(origin: origin, dir: dir, maxDist: 280.0, ignoreShatterFloors: false)
            if firstHit.hit && firstHit.colliderIndex >= 0 && arena.colliders[firstHit.colliderIndex].kind == .shatterFloor {
                breached += arena.applyStructuralDamage(at: firstHit.point, radius: 2.5, damage: 120.0)
                spheres.append(ShockSphereFX(center: firstHit.point, maxRadius: 2.8, color: SublevelPalette.cobaltViolet, duration: 0.35))
            }
        }

        let worldHit = arena.raycast(origin: origin, dir: dir, maxDist: 280.0, ignoreShatterFloors: pierceFloors)
        let maxDist = worldHit.hit ? worldHit.distance : 280.0
        let endPoint = origin + dir * maxDist

        beams.append(BeamSegmentFX(
            start: origin - SIMD3<Float>(0, 0.12, 0),
            end: endPoint,
            color: SublevelPalette.cobaltViolet,
            thickness: pierceFloors ? 0.14 : 0.10,
            life: 0.55
        ))

        // Pierces all actors along the ray up to wall hit!
        var events: [DamageEvent] = []
        for actor in actors where actor.id != shooterID {
            let minB = actor.feetPosition - SIMD3<Float>(actor.radius, 0, actor.radius)
            let maxB = actor.feetPosition + SIMD3<Float>(actor.radius, actor.height, actor.radius)
            let hit = Math3D.rayIntersectAABB(origin: origin, dir: dir, minBounds: minB, maxBounds: maxB, maxDist: maxDist)
            if hit.hit {
                let hitPt = origin + dir * hit.distance
                events.append(DamageEvent(
                    attackerID: shooterID,
                    targetID: actor.id,
                    damage: 90.0 * damageMultiplier,
                    knockback: dir * 11.0 + SIMD3<Float>(0, 3.8, 0),
                    weapon: .subRail,
                    isShockCombo: false,
                    isHeadshotOrMidair: true,
                    hitPoint: hitPt
                ))
                spheres.append(ShockSphereFX(center: hitPt, maxRadius: 1.6, color: SublevelPalette.cobaltViolet, duration: 0.30))
            }
        }

        if worldHit.hit {
            spheres.append(ShockSphereFX(center: worldHit.point, maxRadius: 0.9, color: SublevelPalette.cobaltViolet, duration: 0.25))
        }
        return (events, breached)
    }

    /// Evaluates radial splash damage & knockback (with 0.4x self-damage for Rocket Jumping)
    public static func evaluateRadialExplosion(
        attackerID: Int,
        center: SIMD3<Float>,
        radius: Float,
        baseDamage: Float,
        baseImpulse: Float,
        selfDamageMultiplier: Float,
        weapon: WeaponSlot,
        isShockCombo: Bool,
        actors: [CombatActorTarget]
    ) -> [DamageEvent] {
        var events: [DamageEvent] = []
        for actor in actors {
            let targetCenter = actor.center
            let dist = simd_distance(center, targetCenter)
            guard dist <= radius else { continue }

            let falloff = simd_clamp(1.0 - (dist / radius) * 0.72, 0.22, 1.0)
            let isSelf = (actor.id == attackerID)
            let dmgMult: Float = isSelf ? selfDamageMultiplier : 1.0
            let damage = baseDamage * falloff * dmgMult

            var pushDir = targetCenter - center
            if simd_length(pushDir) < 0.05 {
                pushDir = SIMD3<Float>(0, 1, 0)
            } else {
                pushDir = simd_normalize(pushDir)
            }
            // Boost vertical lift on rocket jumps
            if isSelf {
                pushDir.y = max(pushDir.y + 0.38, 0.65)
                pushDir = simd_normalize(pushDir)
            }
            let impulse = pushDir * (baseImpulse * falloff * (isSelf ? 1.22 : 1.0))

            events.append(DamageEvent(
                attackerID: attackerID,
                targetID: actor.id,
                damage: damage,
                knockback: impulse,
                weapon: weapon,
                isShockCombo: isShockCombo,
                isHeadshotOrMidair: false,
                hitPoint: center
            ))
        }
        return events
    }
}
