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

public enum DynamicMoverKind: Int, Sendable {
    case hydraulicLift = 0
    case aerialShuttle = 1
    case sumpPiston = 2
}

public struct DynamicMover: Sendable {
    public var colliderIndex: Int
    public var kind: DynamicMoverKind
    public var startCenter: SIMD3<Float>
    public var endCenter: SIMD3<Float>
    public var frequency: Float
    public var phase: Float
    public var accentColor: SIMD3<Float>

    public init(
        colliderIndex: Int,
        kind: DynamicMoverKind,
        startCenter: SIMD3<Float>,
        endCenter: SIMD3<Float>,
        frequency: Float,
        phase: Float,
        accentColor: SIMD3<Float>
    ) {
        self.colliderIndex = colliderIndex
        self.kind = kind
        self.startCenter = startCenter
        self.endCenter = endCenter
        self.frequency = frequency
        self.phase = phase
        self.accentColor = accentColor
    }
}

public struct ArenaTurbine: Sendable {
    public var position: SIMD3<Float>
    public var yaw: Float
    public var radius: Float
    public var spinSpeed: Float
    public var accentColor: SIMD3<Float>

    public init(position: SIMD3<Float>, yaw: Float, radius: Float, spinSpeed: Float, accentColor: SIMD3<Float>) {
        self.position = position
        self.yaw = yaw
        self.radius = radius
        self.spinSpeed = spinSpeed
        self.accentColor = accentColor
    }
}

public struct DebrisShard: Sendable {
    public var position: SIMD3<Float>
    public var velocity: SIMD3<Float>
    public var angles: SIMD3<Float>
    public var angularVelocity: SIMD3<Float>
    public var size: SIMD3<Float>
    public var color: SIMD3<Float>
    public var isGlass: Bool
    public var lifetime: Float
    public var maxLifetime: Float

    public init(
        position: SIMD3<Float>,
        velocity: SIMD3<Float>,
        angles: SIMD3<Float>,
        angularVelocity: SIMD3<Float>,
        size: SIMD3<Float>,
        color: SIMD3<Float>,
        isGlass: Bool,
        lifetime: Float
    ) {
        self.position = position
        self.velocity = velocity
        self.angles = angles
        self.angularVelocity = angularVelocity
        self.size = size
        self.color = color
        self.isGlass = isGlass
        self.lifetime = lifetime
        self.maxLifetime = lifetime
    }
}

/// Multi-stratum arena `sl_atrium` with B1 (Atrium/Skylight), B2 (Concourse), and B3 (The Sump/Core)
public struct ArenaMap: Sendable {
    public var name: String = "SL_ATRIUM // CITY OF GLASS STRATA 01"
    public var colliders: [WorldBoxCollider] = []
    public var dynamicMovers: [DynamicMover] = []
    public var turbines: [ArenaTurbine] = []
    public var louverBaseX: [Float] = []
    public var jumpPads: [JumpPad] = []
    public var teleporters: [Teleporter] = []
    public var pickups: [PickupSpawner] = []
    public var staticLights: [PointLightSource] = []
    public var recentlyBreachedBoxes: [WorldBoxCollider] = []
    public var spawnPoints: [(position: SIMD3<Float>, yaw: Float, stratum: Stratum)] = []
    public var abyssLethalY: Float = -18.5

    public init() {
        buildAtriumArena()
    }

    @discardableResult
    private mutating func addBox(
        center: SIMD3<Float>,
        size: SIMD3<Float>,
        color: SIMD3<Float> = SublevelPalette.starkWhite,
        kind: ColliderSurfaceKind = .standard,
        health: Float = 100.0,
        roughness: Float = 0.28,
        metallic: Float = 0.04,
        emissive: Float = 0.0,
        isDynamic: Bool = false
    ) -> Int {
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
            emissiveStrength: emissive,
            isDynamic: isDynamic
        ))
        return id
    }

    private mutating func buildAtriumArena() {
        let white = SublevelPalette.starkWhite
        let coolSlab = SublevelPalette.coolConcrete
        let gray = SublevelPalette.warmGray
        let red = SublevelPalette.signalRed
        let orange = SublevelPalette.runnerOrange
        let yellow = SublevelPalette.canaryYellow
        let emerald = SublevelPalette.atriumEmerald
        let blue = SublevelPalette.cobaltBlue
        let cerulean = SublevelPalette.skyCerulean
        let gold = SublevelPalette.amberGold
        let slate = SublevelPalette.darkSlate
        let glassBlue = SIMD3<Float>(0.32, 0.74, 1.0)

        // =========================================================================
        // OUTER MIRROR'S EDGE ATRIUM ENCLOSURE & COLOR-BLOCKED FEATURE WALLS
        // =========================================================================
        let halfSpan: Float = 30.0
        let wallHeight: Float = 44.0
        let wallCenterY: Float = 6.0

        // 4 Perimeter enclosure walls (Gleaming sunlit Stark White concrete)
        addBox(center: SIMD3<Float>(0, wallCenterY, -halfSpan), size: SIMD3<Float>(60, wallHeight, 2.0), color: white, roughness: 0.24)
        addBox(center: SIMD3<Float>(0, wallCenterY,  halfSpan), size: SIMD3<Float>(60, wallHeight, 2.0), color: white, roughness: 0.24)
        addBox(center: SIMD3<Float>(-halfSpan, wallCenterY, 0), size: SIMD3<Float>(2.0, wallHeight, 60), color: white, roughness: 0.24)
        addBox(center: SIMD3<Float>( halfSpan, wallCenterY, 0), size: SIMD3<Float>(2.0, wallHeight, 60), color: white, roughness: 0.24)

        // Mirror's Edge Color-Blocked Architectural Feature Walls (bleed saturated radiosity!)
        // North Wing: Canary Yellow Stairwell & Industrial Conduit Feature Band
        addBox(center: SIMD3<Float>(-18.5, 16.5, -28.85), size: SIMD3<Float>(16.0, 7.2, 0.35), color: yellow, roughness: 0.16, emissive: 0.18)
        addBox(center: SIMD3<Float>( 18.5, 5.2,  -28.85), size: SIMD3<Float>(15.0, 6.4, 0.35), color: yellow, roughness: 0.16, emissive: 0.16)
        // South Wing: Sky Cerulean & Atrium Emerald Sky-Lobby Panels
        addBox(center: SIMD3<Float>( 18.5, 16.5,  28.85), size: SIMD3<Float>(16.0, 7.2, 0.35), color: cerulean, roughness: 0.15, emissive: 0.18)
        addBox(center: SIMD3<Float>(-18.5, 5.2,   28.85), size: SIMD3<Float>(15.0, 6.4, 0.35), color: emerald, roughness: 0.16, emissive: 0.16)
        // East & West Upper Atrium Runner-Orange Acoustic Baffles
        addBox(center: SIMD3<Float>(-28.85, 17.5, -14.0), size: SIMD3<Float>(0.35, 6.5, 14.0), color: orange, roughness: 0.16, emissive: 0.18)
        addBox(center: SIMD3<Float>( 28.85, 17.5,  14.0), size: SIMD3<Float>(0.35, 6.5, 14.0), color: orange, roughness: 0.16, emissive: 0.18)

        // Articulated Skylight Louver coordinates at Y = 26.8 (animated dynamically in renderer)
        louverBaseX = stride(from: -22, through: 22, by: 5.5).map { Float($0) }

        // Four Monumental Corner Mega-Columns spanning B3 -> B1
        let colPositions: [SIMD2<Float>] = [
            SIMD2<Float>(-16, -16), SIMD2<Float>(16, -16),
            SIMD2<Float>(-16,  16), SIMD2<Float>(16,  16)
        ]
        for p in colPositions {
            addBox(center: SIMD3<Float>(p.x, 5.5, p.y), size: SIMD3<Float>(3.5, 38.0, 3.5), color: coolSlab, roughness: 0.26)
            // Signal Red wall-dodge accent bands on columns at B2 & B1 heights
            addBox(
                center: SIMD3<Float>(p.x, 4.5, p.y),
                size: SIMD3<Float>(3.85, 3.2, 3.85),
                color: red,
                kind: .kineticPanel,
                roughness: 0.14,
                emissive: 0.38
            )
            addBox(
                center: SIMD3<Float>(p.x, 15.5, p.y),
                size: SIMD3<Float>(3.85, 2.6, 3.85),
                color: red,
                kind: .kineticPanel,
                roughness: 0.14,
                emissive: 0.34
            )
            // Dark structural collar trims
            addBox(center: SIMD3<Float>(p.x, -4.5, p.y), size: SIMD3<Float>(3.75, 0.7, 3.75), color: slate, roughness: 0.35, metallic: 0.5)
        }

        // =========================================================================
        // STRATUM B1 (Y = 12.0): ATRIUM / SKYLIGHT DECK (Rail / Prism Territory)
        // =========================================================================
        // North, South, East, West perimeter skywalks leaving a massive central shaft + 2 shatter skylights
        addBox(center: SIMD3<Float>(0, 11.6, -21.0), size: SIMD3<Float>(56.0, 0.8, 16.0), color: white, roughness: 0.20)
        addBox(center: SIMD3<Float>(0, 11.6,  21.0), size: SIMD3<Float>(56.0, 0.8, 16.0), color: white, roughness: 0.20)
        addBox(center: SIMD3<Float>(-21.0, 11.6, 0), size: SIMD3<Float>(16.0, 0.8, 26.0), color: white, roughness: 0.20)
        addBox(center: SIMD3<Float>( 21.0, 11.6, 0), size: SIMD3<Float>(16.0, 0.8, 26.0), color: white, roughness: 0.20)

        // Central B1 Sniper Bridge (X-axis catwalk)
        addBox(center: SIMD3<Float>(0, 11.6, 0), size: SIMD3<Float>(26.0, 0.8, 5.0), color: white, roughness: 0.18)

        // Destructible Skylight Glass Breaches on B1 (North-Center & South-Center openings)
        addBox(
            center: SIMD3<Float>(0, 11.65, -7.75),
            size: SIMD3<Float>(12.0, 0.35, 10.2),
            color: glassBlue,
            kind: .shatterFloor,
            health: 80.0,
            roughness: 0.06,
            metallic: 0.25,
            emissive: 0.42
        )
        addBox(
            center: SIMD3<Float>(0, 11.65, 7.75),
            size: SIMD3<Float>(12.0, 0.35, 10.2),
            color: glassBlue,
            kind: .shatterFloor,
            health: 80.0,
            roughness: 0.06,
            metallic: 0.25,
            emissive: 0.42
        )

        // B1 Trimping Ramps (Signal Red sloped wedges for converting strafe speed into vertical arcs)
        addBox(
            center: SIMD3<Float>(-10.0, 12.8, -17.0),
            size: SIMD3<Float>(6.5, 1.8, 4.0),
            color: red,
            kind: .rampPosX,
            roughness: 0.14,
            emissive: 0.36
        )
        addBox(
            center: SIMD3<Float>(10.0, 12.8, 17.0),
            size: SIMD3<Float>(6.5, 1.8, 4.0),
            color: red,
            kind: .rampNegX,
            roughness: 0.14,
            emissive: 0.36
        )
        // Additional East & West B1 Mezzanine Launch Ramps
        addBox(
            center: SIMD3<Float>(-22.5, 12.65, -8.5),
            size: SIMD3<Float>(3.8, 1.5, 5.6),
            color: orange,
            kind: .rampPosZ,
            roughness: 0.15,
            emissive: 0.30
        )
        addBox(
            center: SIMD3<Float>(22.5, 12.65, 8.5),
            size: SIMD3<Float>(3.8, 1.5, 5.6),
            color: orange,
            kind: .rampNegZ,
            roughness: 0.15,
            emissive: 0.30
        )

        // B1 Elevated Sniper Perches (Y = 15.5) with Canary Yellow & Cerulean step-up stairs
        addBox(center: SIMD3<Float>(0, 14.0, -25.5), size: SIMD3<Float>(14.0, 4.0, 6.0), color: white, roughness: 0.22)
        addBox(center: SIMD3<Float>(0, 14.0,  25.5), size: SIMD3<Float>(14.0, 4.0, 6.0), color: white, roughness: 0.22)
        for s in 0..<8 {
            let stepH: Float = 0.38
            let y = 12.0 + Float(s) * stepH
            addBox(
                center: SIMD3<Float>(-9.0 - Float(s) * 0.7, y + stepH * 0.5, -25.0),
                size: SIMD3<Float>(0.8, stepH, 4.0),
                color: s % 2 == 0 ? yellow : white,
                roughness: 0.22
            )
            addBox(
                center: SIMD3<Float>( 9.0 + Float(s) * 0.7, y + stepH * 0.5,  25.0),
                size: SIMD3<Float>(0.8, stepH, 4.0),
                color: s % 2 == 0 ? cerulean : white,
                roughness: 0.22
            )
        }

        // =========================================================================
        // STRATUM B2 (Y = 0.0): CONCOURSE (Kinetic Corridors, Wall-Dodge Shafts, Flak/Rocket)
        // =========================================================================
        addBox(center: SIMD3<Float>(0, -0.4, -18.5), size: SIMD3<Float>(52.0, 0.8, 19.0), color: coolSlab, roughness: 0.22)
        addBox(center: SIMD3<Float>(0, -0.4,  18.5), size: SIMD3<Float>(52.0, 0.8, 19.0), color: coolSlab, roughness: 0.22)
        addBox(center: SIMD3<Float>(-18.5, -0.4, 0), size: SIMD3<Float>(19.0, 0.8, 22.0), color: coolSlab, roughness: 0.22)
        addBox(center: SIMD3<Float>( 18.5, -0.4, 0), size: SIMD3<Float>(19.0, 0.8, 22.0), color: coolSlab, roughness: 0.22)

        // B2 Destructible Concrete/Amber Grate Bridge over B3 Sump
        addBox(
            center: SIMD3<Float>(0, -0.35, 0),
            size: SIMD3<Float>(9.0, 0.45, 18.0),
            color: gold,
            kind: .shatterFloor,
            health: 110.0,
            roughness: 0.20,
            emissive: 0.32
        )

        // B2 Signal Red Wall-Dodge Kinetic Corridors (East & West vertical bounce walls)
        addBox(
            center: SIMD3<Float>(-27.8, 5.5, 0),
            size: SIMD3<Float>(1.2, 8.5, 24.0),
            color: red,
            kind: .kineticPanel,
            roughness: 0.14,
            emissive: 0.52
        )
        addBox(
            center: SIMD3<Float>( 27.8, 5.5, 0),
            size: SIMD3<Float>(1.2, 8.5, 24.0),
            color: red,
            kind: .kineticPanel,
            roughness: 0.14,
            emissive: 0.52
        )

        // B2 Trimping Ramps launching across the central shaft
        addBox(
            center: SIMD3<Float>(0, 0.75, -10.5),
            size: SIMD3<Float>(6.0, 1.6, 4.5),
            color: red,
            kind: .rampPosZ,
            roughness: 0.14,
            emissive: 0.42
        )
        addBox(
            center: SIMD3<Float>(0, 0.75, 10.5),
            size: SIMD3<Float>(6.0, 1.6, 4.5),
            color: red,
            kind: .rampNegZ,
            roughness: 0.14,
            emissive: 0.42
        )

        // B2 Sculpted Tactical Cover Bulkheads with color-coded top caps
        let bulkheadCoords: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3<Float>(-11.0, 1.4, -13.5), yellow),
            (SIMD3<Float>( 11.0, 1.4, -13.5), orange),
            (SIMD3<Float>(-11.0, 1.4,  13.5), emerald),
            (SIMD3<Float>( 11.0, 1.4,  13.5), cerulean)
        ]
        for (pos, capCol) in bulkheadCoords {
            addBox(center: pos, size: SIMD3<Float>(4.4, 2.8, 1.5), color: white, roughness: 0.22)
            addBox(center: pos + SIMD3<Float>(0, 1.52, 0), size: SIMD3<Float>(4.55, 0.28, 1.65), color: capCol, roughness: 0.16, emissive: 0.22)
        }

        // =========================================================================
        // STRATUM B3 (Y = -11.0): THE SUMP / CORE (High-Risk Cobalt/Amber Over Abyss)
        // =========================================================================
        addBox(center: SIMD3<Float>(0, -11.4, 0), size: SIMD3<Float>(14.0, 0.9, 14.0), color: white, roughness: 0.22)
        addBox(
            center: SIMD3<Float>(0, -10.9, 0),
            size: SIMD3<Float>(4.5, 0.3, 4.5),
            color: gold,
            roughness: 0.12,
            metallic: 0.45,
            emissive: 0.68
        )

        // 4 Outer Sump Islands connected by narrow gap jumps & dynamic pistons
        addBox(center: SIMD3<Float>(-18.0, -11.4, 0), size: SIMD3<Float>(10.0, 0.9, 14.0), color: coolSlab)
        addBox(center: SIMD3<Float>( 18.0, -11.4, 0), size: SIMD3<Float>(10.0, 0.9, 14.0), color: coolSlab)
        addBox(center: SIMD3<Float>(0, -11.4, -18.0), size: SIMD3<Float>(14.0, 0.9, 10.0), color: coolSlab)
        addBox(center: SIMD3<Float>(0, -11.4,  18.0), size: SIMD3<Float>(14.0, 0.9, 10.0), color: coolSlab)

        // 4 Cobalt Blue Gravity Lift Pylons in B3 corners
        for signX: Float in [-1, 1] {
            for signZ: Float in [-1, 1] {
                if signX * signZ > 0 {
                    addBox(
                        center: SIMD3<Float>(18.0 * signX, -5.5, 18.0 * signZ),
                        size: SIMD3<Float>(3.0, 12.0, 3.0),
                        color: blue,
                        roughness: 0.14,
                        emissive: 0.72
                    )
                } else {
                    addBox(
                        center: SIMD3<Float>(18.0 * signX, -6.5, 18.0 * signZ),
                        size: SIMD3<Float>(2.6, 10.0, 2.6),
                        color: gray,
                        roughness: 0.28
                    )
                }
            }
        }

        // =========================================================================
        // DYNAMIC MOVING ARENA STRUCTURES (Hydraulic Lifts, Aerial Shuttles, Pistons)
        // =========================================================================
        let westLiftIdx = addBox(
            center: SIMD3<Float>(-10.8, -0.25, 0),
            size: SIMD3<Float>(3.6, 0.55, 4.2),
            color: white,
            roughness: 0.16,
            metallic: 0.2,
            isDynamic: true
        )
        let eastLiftIdx = addBox(
            center: SIMD3<Float>(10.8, 11.55, 0),
            size: SIMD3<Float>(3.6, 0.55, 4.2),
            color: white,
            roughness: 0.16,
            metallic: 0.2,
            isDynamic: true
        )
        let northShuttleIdx = addBox(
            center: SIMD3<Float>(-8.2, 6.1, -11.8),
            size: SIMD3<Float>(4.8, 0.50, 3.4),
            color: orange,
            roughness: 0.16,
            emissive: 0.25,
            isDynamic: true
        )
        let southShuttleIdx = addBox(
            center: SIMD3<Float>(8.2, 6.1, 11.8),
            size: SIMD3<Float>(4.8, 0.50, 3.4),
            color: cerulean,
            roughness: 0.16,
            emissive: 0.25,
            isDynamic: true
        )
        let westPistonIdx = addBox(
            center: SIMD3<Float>(-10.0, -11.3, 0),
            size: SIMD3<Float>(3.8, 0.65, 4.0),
            color: yellow,
            roughness: 0.18,
            emissive: 0.28,
            isDynamic: true
        )
        let eastPistonIdx = addBox(
            center: SIMD3<Float>(10.0, -9.2, 0),
            size: SIMD3<Float>(3.8, 0.65, 4.0),
            color: yellow,
            roughness: 0.18,
            emissive: 0.28,
            isDynamic: true
        )

        dynamicMovers = [
            DynamicMover(
                colliderIndex: westLiftIdx,
                kind: .hydraulicLift,
                startCenter: SIMD3<Float>(-10.8, -0.25, 0),
                endCenter: SIMD3<Float>(-10.8, 11.55, 0),
                frequency: 0.65,
                phase: 0.0,
                accentColor: blue
            ),
            DynamicMover(
                colliderIndex: eastLiftIdx,
                kind: .hydraulicLift,
                startCenter: SIMD3<Float>(10.8, -0.25, 0),
                endCenter: SIMD3<Float>(10.8, 11.55, 0),
                frequency: 0.65,
                phase: .pi,
                accentColor: blue
            ),
            DynamicMover(
                colliderIndex: northShuttleIdx,
                kind: .aerialShuttle,
                startCenter: SIMD3<Float>(-8.2, 6.1, -11.8),
                endCenter: SIMD3<Float>(8.2, 6.1, -11.8),
                frequency: 0.82,
                phase: 0.0,
                accentColor: orange
            ),
            DynamicMover(
                colliderIndex: southShuttleIdx,
                kind: .aerialShuttle,
                startCenter: SIMD3<Float>(-8.2, 6.1, 11.8),
                endCenter: SIMD3<Float>(8.2, 6.1, 11.8),
                frequency: 0.82,
                phase: .pi,
                accentColor: cerulean
            ),
            DynamicMover(
                colliderIndex: westPistonIdx,
                kind: .sumpPiston,
                startCenter: SIMD3<Float>(-10.0, -11.35, 0),
                endCenter: SIMD3<Float>(-10.0, -8.4, 0),
                frequency: 1.15,
                phase: 0.4,
                accentColor: yellow
            ),
            DynamicMover(
                colliderIndex: eastPistonIdx,
                kind: .sumpPiston,
                startCenter: SIMD3<Float>(10.0, -11.35, 0),
                endCenter: SIMD3<Float>(10.0, -8.4, 0),
                frequency: 1.15,
                phase: 0.4 + .pi,
                accentColor: yellow
            )
        ]

        // Industrial HVAC Extraction Turbines spinning inside the Concourse & Atrium walls
        turbines = [
            ArenaTurbine(position: SIMD3<Float>(-28.7, 17.5, 14.0), yaw: .pi * 0.5, radius: 2.3, spinSpeed: 3.4, accentColor: red),
            ArenaTurbine(position: SIMD3<Float>( 28.7, 17.5, -14.0), yaw: -.pi * 0.5, radius: 2.3, spinSpeed: -3.4, accentColor: red),
            ArenaTurbine(position: SIMD3<Float>( 0.0, 5.8, -28.7), yaw: 0.0, radius: 2.5, spinSpeed: 2.8, accentColor: yellow),
            ArenaTurbine(position: SIMD3<Float>( 0.0, 5.8,  28.7), yaw: .pi, radius: 2.5, spinSpeed: -2.8, accentColor: cerulean),
            ArenaTurbine(position: SIMD3<Float>(-28.7, -5.5, 0.0), yaw: .pi * 0.5, radius: 2.1, spinSpeed: 4.2, accentColor: blue),
            ArenaTurbine(position: SIMD3<Float>( 28.7, -5.5, 0.0), yaw: -.pi * 0.5, radius: 2.1, spinSpeed: -4.2, accentColor: blue)
        ]

        // =========================================================================
        // JUMP PADS (Signal Red #FF2216) & TELEPORTERS (Cobalt Blue #005DFF)
        // =========================================================================
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
        // HIGH-TIER PICKUPS
        // =========================================================================
        pickups = [
            PickupSpawner(id: 0, position: SIMD3<Float>(0, -10.2, 0), kind: .quadOverdrive),
            PickupSpawner(id: 1, position: SIMD3<Float>(0, 12.6, 0), kind: .megaHealth),
            PickupSpawner(id: 2, position: SIMD3<Float>(-21.0, 0.6, 0), kind: .subShield),
            PickupSpawner(id: 3, position: SIMD3<Float>( 21.0, 0.6, 0), kind: .armorShard),
            PickupSpawner(id: 4, position: SIMD3<Float>(0, 0.6, -21.0), kind: .armorShard),
            PickupSpawner(id: 5, position: SIMD3<Float>(0, 0.6,  21.0), kind: .ammoPack),
            PickupSpawner(id: 6, position: SIMD3<Float>(-21.0, 12.6, 0), kind: .ammoPack),
            PickupSpawner(id: 7, position: SIMD3<Float>( 21.0, 12.6, 0), kind: .armorShard)
        ]

        // =========================================================================
        // MIRROR'S EDGE RADIOSITY BOUNCE LIGHTS (20 Static GI Bounce Sources)
        // =========================================================================
        staticLights = [
            // B1 Sunlit Atrium Skylight Shafts (Crisp daylight + sky-cyan bounce)
            PointLightSource(position: SIMD3<Float>(0, 24.5, 0), color: SIMD3<Float>(1.0, 0.99, 0.95), intensity: 2.1, radius: 46.0),
            PointLightSource(position: SIMD3<Float>(-18, 21.0, -18), color: SIMD3<Float>(0.92, 0.96, 1.0), intensity: 1.4, radius: 30.0),
            PointLightSource(position: SIMD3<Float>( 18, 21.0,  18), color: SIMD3<Float>(0.92, 0.96, 1.0), intensity: 1.4, radius: 30.0),
            // North Canary Yellow Stairwell & Conduit Radiosity Bleed
            PointLightSource(position: SIMD3<Float>(-17.0, 15.5, -26.0), color: yellow, intensity: 2.1, radius: 20.0),
            PointLightSource(position: SIMD3<Float>( 17.0, 5.0,  -26.0), color: yellow, intensity: 1.9, radius: 19.0),
            // South Sky Cerulean & Atrium Emerald Radiosity Bleed
            PointLightSource(position: SIMD3<Float>( 17.0, 15.5,  26.0), color: cerulean, intensity: 2.1, radius: 20.0),
            PointLightSource(position: SIMD3<Float>(-17.0, 5.0,   26.0), color: emerald, intensity: 1.9, radius: 19.0),
            // East & West Runner Red + Vibrant Orange Kinetic Corridor Bounce
            PointLightSource(position: SIMD3<Float>(-25.5, 5.5, 0), color: red, intensity: 2.6, radius: 23.0),
            PointLightSource(position: SIMD3<Float>( 25.5, 5.5, 0), color: red, intensity: 2.6, radius: 23.0),
            PointLightSource(position: SIMD3<Float>(-25.5, 16.5, -13.0), color: orange, intensity: 2.0, radius: 20.0),
            PointLightSource(position: SIMD3<Float>( 25.5, 16.5,  13.0), color: orange, intensity: 2.0, radius: 20.0),
            // B1 Ramp & Skylight Glass Radiosity Accents
            PointLightSource(position: SIMD3<Float>(0, 11.2, -7.75), color: cerulean, intensity: 1.5, radius: 14.0),
            PointLightSource(position: SIMD3<Float>(0, 11.2,  7.75), color: cerulean, intensity: 1.5, radius: 14.0),
            // B2 Concourse Jump-Pad Corner Glows
            PointLightSource(position: SIMD3<Float>(-22.0, 2.0, -22.0), color: red, intensity: 1.6, radius: 14.0),
            PointLightSource(position: SIMD3<Float>( 22.0, 2.0,  22.0), color: red, intensity: 1.6, radius: 14.0),
            // B3 Sump Deep Cobalt Blue & Amber Gold Core Radiosity
            PointLightSource(position: SIMD3<Float>(0, -8.5, 0), color: gold, intensity: 2.8, radius: 22.0),
            PointLightSource(position: SIMD3<Float>(-16, -8.0, -16), color: blue, intensity: 2.6, radius: 25.0),
            PointLightSource(position: SIMD3<Float>( 16, -8.0,  16), color: blue, intensity: 2.6, radius: 25.0),
            PointLightSource(position: SIMD3<Float>(-18, -9.5, 0), color: red, intensity: 1.8, radius: 15.0),
            PointLightSource(position: SIMD3<Float>( 18, -9.5, 0), color: red, intensity: 1.8, radius: 15.0)
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

    /// Steps all dynamic moving platforms, elevators, and pistons with smooth dwell curves at endpoints
    public mutating func updateDynamicStructures(time: Float, dt: Float) {
        for mover in dynamicMovers {
            let raw = 0.5 - 0.5 * cos(time * mover.frequency + mover.phase)
            // Smoothstep dwell at top/bottom stops so players can board lifts comfortably
            let t = raw * raw * (3.0 - 2.0 * raw)
            let target = mover.startCenter + (mover.endCenter - mover.startCenter) * t
            colliders[mover.colliderIndex].moveCenter(to: target, dt: dt)
        }
        for i in jumpPads.indices {
            jumpPads[i].pulseTimer = max(0.0, jumpPads[i].pulseTimer - dt)
        }
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
                    recentlyBreachedBoxes.append(colliders[i])
                    breachedCount += 1
                }
            }
        }
        return breachedCount
    }

    public mutating func resetBreaches() {
        recentlyBreachedBoxes.removeAll()
        for i in colliders.indices where colliders[i].kind == .shatterFloor {
            colliders[i].isDestroyed = false
            colliders[i].health = colliders[i].maxHealth
        }
    }
}
