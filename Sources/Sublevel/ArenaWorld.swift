import Foundation
import simd

public struct JumpPad: Sendable {
    public var id: Int
    public var position: SIMD3<Float>
    public var radius: Float
    public var launchVelocity: SIMD3<Float>
    public var label: String
    public var pulseTimer: Float = 0.0

    public init(id: Int, position: SIMD3<Float>, radius: Float = 1.9, launchVelocity: SIMD3<Float>, label: String) {
        self.id = id
        self.position = position
        self.radius = radius
        self.launchVelocity = launchVelocity
        self.label = label
    }
}

public struct Teleporter: Sendable {
    public var id: Int
    public var position: SIMD3<Float>
    public var radius: Float
    public var destination: SIMD3<Float>
    public var exitYaw: Float
    public var label: String

    public init(id: Int, position: SIMD3<Float>, radius: Float = 1.6, destination: SIMD3<Float>, exitYaw: Float, label: String) {
        self.id = id
        self.position = position
        self.radius = radius
        self.destination = destination
        self.exitYaw = exitYaw
        self.label = label
    }
}

public enum PickupKind: String, CaseIterable, Sendable {
    case megaHealth = "MEGA-HEALTH (+100)"
    case armorShard = "ARMOR SHARD (+50)"
    case quadOverdrive = "QUAD OVERDRIVE (3X DMG)"
    case subShield = "SUB-SHIELD (INVULN)"
    case ammoPack = "ARSENAL CELLS"

    public var respawnDuration: Float {
        switch self {
        case .megaHealth: return 20.0
        case .armorShard: return 12.0
        case .quadOverdrive: return 35.0
        case .subShield: return 35.0
        case .ammoPack: return 10.0
        }
    }

    public var color: SIMD3<Float> {
        switch self {
        case .megaHealth, .armorShard, .quadOverdrive:
            return SublevelPalette.amberGold
        case .subShield:
            return SublevelPalette.cobaltBlue
        case .ammoPack:
            return SublevelPalette.electricCyan
        }
    }
}

public struct PickupSpawner: Sendable {
    public var id: Int
    public var position: SIMD3<Float>
    public var kind: PickupKind
    public var isActive: Bool
    public var respawnTimer: Float
    public var rotationAngle: Float

    public init(id: Int, position: SIMD3<Float>, kind: PickupKind) {
        self.id = id
        self.position = position
        self.kind = kind
        self.isActive = true
        self.respawnTimer = 0.0
        self.rotationAngle = 0.0
    }
}

public struct PointLightSource: Sendable {
    public var position: SIMD3<Float>
    public var color: SIMD3<Float>
    public var intensity: Float
    public var radius: Float

    public init(position: SIMD3<Float>, color: SIMD3<Float>, intensity: Float, radius: Float) {
        self.position = position
        self.color = color
        self.intensity = intensity
        self.radius = radius
    }
}

/// Multi-stratum arena `sl_atrium` with B1 (Atrium/Skylight), B2 (Concourse), and B3 (The Sump/Core)
public struct ArenaMap: Sendable {
    public var name: String = "SL_ATRIUM // BRUTALIST STRATA 01"
    public var colliders: [WorldBoxCollider] = []
    public var jumpPads: [JumpPad] = []
    public var teleporters: [Teleporter] = []
    public var pickups: [PickupSpawner] = []
    public var staticLights: [PointLightSource] = []
    public var spawnPoints: [(position: SIMD3<Float>, yaw: Float, stratum: Stratum)] = []
    public var abyssLethalY: Float = -18.5

    public init() {
        buildAtriumArena()
    }

    private mutating func addBox(
        center: SIMD3<Float>,
        size: SIMD3<Float>,
        color: SIMD3<Float> = SublevelPalette.starkWhite,
        kind: ColliderSurfaceKind = .standard,
        health: Float = 100.0,
        roughness: Float = 0.32,
        metallic: Float = 0.04,
        emissive: Float = 0.0
    ) {
        let id = colliders.count
        colliders.append(WorldBoxCollider(
            id: id,
            center: center,
            size: size,
            color: color,
            kind: kind,
            health: health,
            roughness: roughness,
            metallic: metallic,
            emissiveStrength: emissive
        ))
    }

    private mutating func buildAtriumArena() {
        let white = SublevelPalette.starkWhite
        let gray = SublevelPalette.warmGray
        let red = SublevelPalette.signalRed
        let blue = SublevelPalette.cobaltBlue
        let gold = SublevelPalette.amberGold
        let glassBlue = SIMD3<Float>(0.35, 0.72, 1.0)

        // =========================================================================
        // OUTER BRUTALIST ATRIUM ENCLOSURE & SKY-SHAFT BEAMS
        // =========================================================================
        let halfSpan: Float = 30.0
        let wallHeight: Float = 44.0
        let wallCenterY: Float = 6.0

        // 4 Perimeter enclosure walls (Stark White architectural concrete)
        addBox(center: SIMD3<Float>(0, wallCenterY, -halfSpan), size: SIMD3<Float>(60, wallHeight, 2.0), color: white)
        addBox(center: SIMD3<Float>(0, wallCenterY,  halfSpan), size: SIMD3<Float>(60, wallHeight, 2.0), color: white)
        addBox(center: SIMD3<Float>(-halfSpan, wallCenterY, 0), size: SIMD3<Float>(2.0, wallHeight, 60), color: white)
        addBox(center: SIMD3<Float>( halfSpan, wallCenterY, 0), size: SIMD3<Float>(2.0, wallHeight, 60), color: white)

        // Brutalist Skylight Louvers at Y = 26 (lets natural white sunlight shafts bleed down)
        for i in stride(from: -20, through: 20, by: 10) {
            addBox(center: SIMD3<Float>(Float(i), 26.5, 0), size: SIMD3<Float>(2.2, 1.8, 58.0), color: white)
        }

        // Four Monumental Corner Mega-Columns spanning B3 -> B1
        let colPositions: [SIMD2<Float>] = [
            SIMD2<Float>(-16, -16), SIMD2<Float>(16, -16),
            SIMD2<Float>(-16,  16), SIMD2<Float>(16,  16)
        ]
        for p in colPositions {
            addBox(center: SIMD3<Float>(p.x, 5.0, p.y), size: SIMD3<Float>(3.6, 36.0, 3.6), color: gray)
            // Signal Red wall-dodge accent bands on columns at B2 & B1 heights
            addBox(
                center: SIMD3<Float>(p.x, 4.5, p.y),
                size: SIMD3<Float>(3.8, 3.2, 3.8),
                color: red,
                kind: .kineticPanel,
                roughness: 0.2,
                emissive: 0.35
            )
            addBox(
                center: SIMD3<Float>(p.x, 15.5, p.y),
                size: SIMD3<Float>(3.8, 2.6, 3.8),
                color: red,
                kind: .kineticPanel,
                roughness: 0.2,
                emissive: 0.30
            )
        }

        // =========================================================================
        // STRATUM B1 (Y = 12.0): ATRIUM / SKYLIGHT DECK (Rail / Prism Territory)
        // =========================================================================
        // North, South, East, West perimeter skywalks leaving a massive central shaft + 2 shatter skylights
        addBox(center: SIMD3<Float>(0, 11.6, -21.0), size: SIMD3<Float>(56.0, 0.8, 16.0), color: white)
        addBox(center: SIMD3<Float>(0, 11.6,  21.0), size: SIMD3<Float>(56.0, 0.8, 16.0), color: white)
        addBox(center: SIMD3<Float>(-21.0, 11.6, 0), size: SIMD3<Float>(16.0, 0.8, 26.0), color: white)
        addBox(center: SIMD3<Float>( 21.0, 11.6, 0), size: SIMD3<Float>(16.0, 0.8, 26.0), color: white)

        // Central B1 Sniper Bridge (X-axis catwalk)
        addBox(center: SIMD3<Float>(0, 11.6, 0), size: SIMD3<Float>(26.0, 0.8, 5.0), color: white)

        // Destructible Skylight Glass Breaches on B1 (North-Center & South-Center openings)
        // Shatter when hit by Shock Combos, Rockets, or Sub-Rail Alt-Fire!
        addBox(
            center: SIMD3<Float>(0, 11.65, -7.75),
            size: SIMD3<Float>(12.0, 0.35, 10.2),
            color: glassBlue,
            kind: .shatterFloor,
            health: 80.0,
            roughness: 0.08,
            metallic: 0.2,
            emissive: 0.45
        )
        addBox(
            center: SIMD3<Float>(0, 11.65, 7.75),
            size: SIMD3<Float>(12.0, 0.35, 10.2),
            color: glassBlue,
            kind: .shatterFloor,
            health: 80.0,
            roughness: 0.08,
            metallic: 0.2,
            emissive: 0.45
        )

        // B1 Trimping Ramps (Signal Red launch ramps for converting strafe speed into vertical arcs)
        addBox(
            center: SIMD3<Float>(-10.0, 12.8, -17.0),
            size: SIMD3<Float>(6.5, 1.8, 4.0),
            color: red,
            kind: .rampPosX,
            roughness: 0.18,
            emissive: 0.40
        )
        addBox(
            center: SIMD3<Float>(10.0, 12.8, 17.0),
            size: SIMD3<Float>(6.5, 1.8, 4.0),
            color: red,
            kind: .rampNegX,
            roughness: 0.18,
            emissive: 0.40
        )

        // B1 Elevated Sniper Perches (Y = 15.5) with 0.35m step-up stairs
        addBox(center: SIMD3<Float>(0, 14.0, -25.5), size: SIMD3<Float>(14.0, 4.0, 6.0), color: white)
        addBox(center: SIMD3<Float>(0, 14.0,  25.5), size: SIMD3<Float>(14.0, 4.0, 6.0), color: white)
        // Stair steps up to North Perch (demonstrates 0.45m stair-stepping without losing bhop speed)
        for s in 0..<8 {
            let stepH: Float = 0.38
            let y = 12.0 + Float(s) * stepH
            addBox(
                center: SIMD3<Float>(-9.0 - Float(s) * 0.7, y + stepH * 0.5, -25.0),
                size: SIMD3<Float>(0.8, stepH, 4.0),
                color: gray
            )
            addBox(
                center: SIMD3<Float>( 9.0 + Float(s) * 0.7, y + stepH * 0.5,  25.0),
                size: SIMD3<Float>(0.8, stepH, 4.0),
                color: gray
            )
        }

        // =========================================================================
        // STRATUM B2 (Y = 0.0): CONCOURSE (Kinetic Corridors, Wall-Dodge Shafts, Flak/Rocket)
        // =========================================================================
        // B2 Main Concourse Ring Deck around central Sump drop shaft
        addBox(center: SIMD3<Float>(0, -0.4, -18.5), size: SIMD3<Float>(52.0, 0.8, 19.0), color: white)
        addBox(center: SIMD3<Float>(0, -0.4,  18.5), size: SIMD3<Float>(52.0, 0.8, 19.0), color: white)
        addBox(center: SIMD3<Float>(-18.5, -0.4, 0), size: SIMD3<Float>(19.0, 0.8, 22.0), color: white)
        addBox(center: SIMD3<Float>( 18.5, -0.4, 0), size: SIMD3<Float>(19.0, 0.8, 22.0), color: white)

        // B2 Destructible Concrete Grate Bridge over B3 Sump
        addBox(
            center: SIMD3<Float>(0, -0.35, 0),
            size: SIMD3<Float>(9.0, 0.45, 18.0),
            color: gold,
            kind: .shatterFloor,
            health: 110.0,
            roughness: 0.25,
            emissive: 0.30
        )

        // B2 Signal Red Wall-Dodge Kinetic Corridors (East & West vertical bounce walls)
        addBox(
            center: SIMD3<Float>(-27.8, 5.5, 0),
            size: SIMD3<Float>(1.2, 8.5, 24.0),
            color: red,
            kind: .kineticPanel,
            roughness: 0.18,
            emissive: 0.55
        )
        addBox(
            center: SIMD3<Float>( 27.8, 5.5, 0),
            size: SIMD3<Float>(1.2, 8.5, 24.0),
            color: red,
            kind: .kineticPanel,
            roughness: 0.18,
            emissive: 0.55
        )
        // B2 Trimping Ramps launching across the central shaft
        addBox(
            center: SIMD3<Float>(0, 0.75, -10.5),
            size: SIMD3<Float>(6.0, 1.6, 4.5),
            color: red,
            kind: .rampPosZ,
            roughness: 0.18,
            emissive: 0.45
        )
        addBox(
            center: SIMD3<Float>(0, 0.75, 10.5),
            size: SIMD3<Float>(6.0, 1.6, 4.5),
            color: red,
            kind: .rampNegZ,
            roughness: 0.18,
            emissive: 0.45
        )

        // B2 Cover Bulkheads
        addBox(center: SIMD3<Float>(-11.0, 1.6, -13.0), size: SIMD3<Float>(4.5, 3.2, 1.6), color: gray)
        addBox(center: SIMD3<Float>( 11.0, 1.6, -13.0), size: SIMD3<Float>(4.5, 3.2, 1.6), color: gray)
        addBox(center: SIMD3<Float>(-11.0, 1.6,  13.0), size: SIMD3<Float>(4.5, 3.2, 1.6), color: gray)
        addBox(center: SIMD3<Float>( 11.0, 1.6,  13.0), size: SIMD3<Float>(4.5, 3.2, 1.6), color: gray)

        // =========================================================================
        // STRATUM B3 (Y = -11.0): THE SUMP / CORE (High-Risk Cobalt/Amber Over Abyss)
        // =========================================================================
        // Central Core Dais suspended above the -18.5m lethal abyss
        addBox(center: SIMD3<Float>(0, -11.4, 0), size: SIMD3<Float>(14.0, 0.9, 14.0), color: white)
        addBox(
            center: SIMD3<Float>(0, -10.9, 0),
            size: SIMD3<Float>(4.5, 0.3, 4.5),
            color: gold,
            roughness: 0.15,
            metallic: 0.4,
            emissive: 0.65
        )

        // 4 Outer Sump Islands connected by narrow gap jumps (rewarding UT99 dodge-jumps & wall-dodges)
        addBox(center: SIMD3<Float>(-18.0, -11.4, 0), size: SIMD3<Float>(10.0, 0.9, 14.0), color: white)
        addBox(center: SIMD3<Float>( 18.0, -11.4, 0), size: SIMD3<Float>(10.0, 0.9, 14.0), color: white)
        addBox(center: SIMD3<Float>(0, -11.4, -18.0), size: SIMD3<Float>(14.0, 0.9, 10.0), color: white)
        addBox(center: SIMD3<Float>(0, -11.4,  18.0), size: SIMD3<Float>(14.0, 0.9, 10.0), color: white)

        // Cobalt Blue Gravity Lift Pillars in B3 corners
        addBox(
            center: SIMD3<Float>(-18.0, -5.5, -18.0),
            size: SIMD3<Float>(3.2, 12.0, 3.2),
            color: blue,
            roughness: 0.15,
            emissive: 0.75
        )
        addBox(
            center: SIMD3<Float>( 18.0, -5.5,  18.0),
            size: SIMD3<Float>(3.2, 12.0, 3.2),
            color: blue,
            roughness: 0.15,
            emissive: 0.75
        )

        // =========================================================================
        // JUMP PADS (Signal Red #FF2A19) & TELEPORTERS (Cobalt Blue #0057FF)
        // =========================================================================
        // B3 Sump -> B1/B2 Launch Pads
        jumpPads = [
            JumpPad(
                id: 0,
                position: SIMD3<Float>(-18.0, -10.9, 0),
                launchVelocity: SIMD3<Float>(5.0, 24.5, 0),
                label: "B3 -> B1 WEST LIFT"
            ),
            JumpPad(
                id: 1,
                position: SIMD3<Float>(18.0, -10.9, 0),
                launchVelocity: SIMD3<Float>(-5.0, 24.5, 0),
                label: "B3 -> B1 EAST LIFT"
            ),
            JumpPad(
                id: 2,
                position: SIMD3<Float>(0, -10.9, -18.0),
                launchVelocity: SIMD3<Float>(0, 17.5, -4.0),
                label: "B3 -> B2 NORTH PAD"
            ),
            JumpPad(
                id: 3,
                position: SIMD3<Float>(0, -10.9, 18.0),
                launchVelocity: SIMD3<Float>(0, 17.5, 4.0),
                label: "B3 -> B2 SOUTH PAD"
            ),
            // B2 Concourse -> B1 Atrium Launch Pads
            JumpPad(
                id: 4,
                position: SIMD3<Float>(-22.0, 0.05, -22.0),
                launchVelocity: SIMD3<Float>(4.0, 18.5, 4.0),
                label: "B2 -> B1 NW LAUNCH"
            ),
            JumpPad(
                id: 5,
                position: SIMD3<Float>(22.0, 0.05, 22.0),
                launchVelocity: SIMD3<Float>(-4.0, 18.5, -4.0),
                label: "B2 -> B1 SE LAUNCH"
            ),
            JumpPad(
                id: 6,
                position: SIMD3<Float>(-22.0, 0.05, 22.0),
                launchVelocity: SIMD3<Float>(4.0, 18.5, -4.0),
                label: "B2 -> B1 SW LAUNCH"
            ),
            JumpPad(
                id: 7,
                position: SIMD3<Float>(22.0, 0.05, -22.0),
                launchVelocity: SIMD3<Float>(-4.0, 18.5, 4.0),
                label: "B2 -> B1 NE LAUNCH"
            )
        ]

        // Cobalt Blue Teleporters / Gravity Shafts
        teleporters = [
            Teleporter(
                id: 0,
                position: SIMD3<Float>(0, -10.9, -5.8),
                destination: SIMD3<Float>(0, 16.2, -25.0),
                exitYaw: .pi,
                label: "SUMP -> B1 NORTH OVERLOOK"
            ),
            Teleporter(
                id: 1,
                position: SIMD3<Float>(0, -10.9, 5.8),
                destination: SIMD3<Float>(0, 16.2, 25.0),
                exitYaw: 0.0,
                label: "SUMP -> B1 SOUTH OVERLOOK"
            )
        ]

        // =========================================================================
        // HIGH-TIER PICKUPS (Amber Gold #FFB800 & Cobalt Blue #0057FF)
        // =========================================================================
        pickups = [
            // B3 Core: Quad Overdrive right in the center of the Sump
            PickupSpawner(id: 0, position: SIMD3<Float>(0, -10.2, 0), kind: .quadOverdrive),
            // B1 Sniper Bridge: Mega-Health
            PickupSpawner(id: 1, position: SIMD3<Float>(0, 12.6, 0), kind: .megaHealth),
            // B2 Concourse East & West: Sub-Shield & Armor Shards
            PickupSpawner(id: 2, position: SIMD3<Float>(-21.0, 0.6, 0), kind: .subShield),
            PickupSpawner(id: 3, position: SIMD3<Float>( 21.0, 0.6, 0), kind: .armorShard),
            PickupSpawner(id: 4, position: SIMD3<Float>(0, 0.6, -21.0), kind: .armorShard),
            PickupSpawner(id: 5, position: SIMD3<Float>(0, 0.6,  21.0), kind: .ammoPack),
            PickupSpawner(id: 6, position: SIMD3<Float>(-21.0, 12.6, 0), kind: .ammoPack),
            PickupSpawner(id: 7, position: SIMD3<Float>( 21.0, 12.6, 0), kind: .armorShard)
        ]

        // =========================================================================
        // STATIC GI / RADIOSITY LIGHT SOURCES (Mirror's Edge Color Bleeding)
        // =========================================================================
        staticLights = [
            // B1 Natural White Skylight shafts
            PointLightSource(position: SIMD3<Float>(0, 24.0, 0), color: SIMD3<Float>(1.0, 0.99, 0.96), intensity: 2.2, radius: 42.0),
            PointLightSource(position: SIMD3<Float>(-18, 20.0, -18), color: SIMD3<Float>(0.98, 0.98, 1.0), intensity: 1.4, radius: 28.0),
            PointLightSource(position: SIMD3<Float>( 18, 20.0,  18), color: SIMD3<Float>(0.98, 0.98, 1.0), intensity: 1.4, radius: 28.0),
            // B2 Signal Red Kinetic Bounce Lights (bleeds saturated red onto adjacent white walls)
            PointLightSource(position: SIMD3<Float>(-25.0, 5.0, 0), color: red, intensity: 2.4, radius: 22.0),
            PointLightSource(position: SIMD3<Float>( 25.0, 5.0, 0), color: red, intensity: 2.4, radius: 22.0),
            // B3 Cobalt Blue & Amber Gold Sump Radiosity Lights
            PointLightSource(position: SIMD3<Float>(0, -8.5, 0), color: gold, intensity: 2.6, radius: 20.0),
            PointLightSource(position: SIMD3<Float>(-16, -8.0, -16), color: blue, intensity: 2.5, radius: 24.0),
            PointLightSource(position: SIMD3<Float>( 16, -8.0,  16), color: blue, intensity: 2.5, radius: 24.0)
        ]

        // =========================================================================
        // SPAWN POINTS ACROSS ALL 3 STRATA
        // =========================================================================
        spawnPoints = [
            (SIMD3<Float>(0, 12.1, -21.0), .pi, .b1Atrium),
            (SIMD3<Float>(0, 12.1,  21.0), 0.0, .b1Atrium),
            (SIMD3<Float>(-21.0, 12.1, 0), -.pi * 0.5, .b1Atrium),
            (SIMD3<Float>( 21.0, 12.1, 0),  .pi * 0.5, .b1Atrium),
            (SIMD3<Float>(-20.0, 0.1, -18.0), -.pi * 0.75, .b2Concourse),
            (SIMD3<Float>( 20.0, 0.1,  18.0),  .pi * 0.25, .b2Concourse),
            (SIMD3<Float>(-20.0, 0.1,  18.0), -.pi * 0.25, .b2Concourse),
            (SIMD3<Float>( 20.0, 0.1, -18.0),  .pi * 0.75, .b2Concourse),
            (SIMD3<Float>(-16.0, -10.8, 4.0), -.pi * 0.5, .b3Sump),
            (SIMD3<Float>( 16.0, -10.8, -4.0), .pi * 0.5, .b3Sump)
        ]
    }

    /// Raycast against all active world colliders
    public func raycast(origin: SIMD3<Float>, dir: SIMD3<Float>, maxDist: Float = 500.0, ignoreShatterFloors: Bool = false) -> RayHit {
        var bestHit = RayHit()
        let normDir = simd_normalize(dir)

        for (idx, box) in colliders.enumerated() where !box.isDestroyed {
            if ignoreShatterFloors && box.kind == .shatterFloor {
                continue
            }
            let res = Math3D.rayIntersectAABB(
                origin: origin,
                dir: normDir,
                minBounds: box.minBounds,
                maxBounds: box.maxBounds,
                maxDist: bestHit.distance
            )
            if res.hit && res.distance < bestHit.distance {
                bestHit.hit = true
                bestHit.distance = res.distance
                bestHit.point = origin + normDir * res.distance
                bestHit.normal = res.normal
                bestHit.colliderIndex = idx
            }
        }
        return bestHit
    }

    /// Applies explosive or piercing damage to shatterable floors/skylights (`Dynamic Breaches`)
    @discardableResult
    public mutating func applyStructuralDamage(at point: SIMD3<Float>, radius: Float, damage: Float) -> Int {
        var breachedCount = 0
        for i in colliders.indices {
            guard colliders[i].kind == .shatterFloor && !colliders[i].isDestroyed else { continue }
            let clamped = simd_clamp(point, colliders[i].minBounds, colliders[i].maxBounds)
            let dist = simd_distance(point, clamped)
            if dist <= radius {
                colliders[i].health -= damage
                if colliders[i].health <= 0 {
                    colliders[i].isDestroyed = true
                    breachedCount += 1
                }
            }
        }
        return breachedCount
    }

    public mutating func resetBreaches() {
        for i in colliders.indices where colliders[i].kind == .shatterFloor {
            colliders[i].isDestroyed = false
            colliders[i].health = 90.0
        }
    }
}
