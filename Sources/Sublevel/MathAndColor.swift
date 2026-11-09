import Foundation
import simd

public enum SublevelPalette {
    // Core Semantic Colors ("Sublevel Vision")
    public static let starkWhite = SIMD3<Float>(0.957, 0.961, 0.969)      // #F4F5F7
    public static let warmGray = SIMD3<Float>(0.820, 0.835, 0.855)        // Brutalist concrete shadow tone
    public static let darkSlate = SIMD3<Float>(0.14, 0.16, 0.20)          // Sump / structural trim
    public static let signalRed = SIMD3<Float>(1.000, 0.165, 0.098)       // #FF2A19 Kinetic flow: Jump pads, wall-dodge panels, ramps
    public static let cobaltBlue = SIMD3<Float>(0.000, 0.341, 1.000)      // #0057FF Vertical transitions: Drop shafts, teleporters, lifts
    public static let amberGold = SIMD3<Float>(1.000, 0.722, 0.000)       // #FFB800 High-tier pickups: Mega-health, Armor, Powerups
    public static let acidMagenta = SIMD3<Float>(1.000, 0.000, 0.478)     // #FF007A Enemy silhouette Alpha
    public static let electricCyan = SIMD3<Float>(0.000, 0.941, 1.000)    // #00F0FF Enemy silhouette Beta / Prism Rifle
    public static let amberOrange = SIMD3<Float>(1.000, 0.480, 0.050)     // Shard Cannon
    public static let crimson = SIMD3<Float>(1.000, 0.120, 0.220)         // Vector Launcher
    public static let cobaltViolet = SIMD3<Float>(0.520, 0.180, 1.000)    // Sub-Rail
}

public enum Stratum: Int, CaseIterable, Sendable {
    case b1Atrium = 1     // Y >= 12.0: Bright skylight atrium, long sightlines
    case b2Concourse = 2  // 0.0 <= Y < 12.0: Kinetic red/orange corridors, wall-dodge shafts
    case b3Sump = 3       // Y < 0.0: High-risk cobalt/amber core over lethal abyss

    public var code: String {
        switch self {
        case .b1Atrium: return "B1 // ATRIUM"
        case .b2Concourse: return "B2 // CONCOURSE"
        case .b3Sump: return "B3 // THE SUMP"
        }
    }

    public var shortCode: String {
        switch self {
        case .b1Atrium: return "B1"
        case .b2Concourse: return "B2"
        case .b3Sump: return "B3"
        }
    }

    public var reverbWetMix: Float {
        switch self {
        case .b1Atrium: return 18.0
        case .b2Concourse: return 34.0
        case .b3Sump: return 55.0
        }
    }

    public static func forElevation(_ y: Float) -> Stratum {
        if y >= 11.0 {
            return .b1Atrium
        } else if y >= -0.5 {
            return .b2Concourse
        } else {
            return .b3Sump
        }
    }
}

public struct RayHit: Sendable {
    public var hit: Bool
    public var distance: Float
    public var point: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var colliderIndex: Int

    public init(hit: Bool = false, distance: Float = .greatestFiniteMagnitude, point: SIMD3<Float> = .zero, normal: SIMD3<Float> = SIMD3<Float>(0, 1, 0), colliderIndex: Int = -1) {
        self.hit = hit
        self.distance = distance
        self.point = point
        self.normal = normal
        self.colliderIndex = colliderIndex
    }
}

public enum Math3D {
    public static let upsPerMeter: Float = 30.47619 // 10.5 m/s == 320 ups

    public static func perspective(fovYRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let yScale = 1.0 / tan(fovYRadians * 0.5)
        let xScale = yScale / max(aspect, 0.001)
        let zRange = farZ - nearZ
        let zScale = -(farZ + nearZ) / zRange
        let wzScale = -2.0 * farZ * nearZ / zRange

        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        ))
    }

    public static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(target - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)

        return simd_float4x4(columns: (
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }

    public static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        ))
    }

    public static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(s.x, 0, 0, 0),
            SIMD4<Float>(0, s.y, 0, 0),
            SIMD4<Float>(0, 0, s.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    public static func rotationY(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4<Float>(c, 0, -s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    public static func rotationZ(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4<Float>(c, s, 0, 0),
            SIMD4<Float>(-s, c, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    public static func rotationX(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, s, 0),
            SIMD4<Float>(0, -s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    public static func rayIntersectAABB(
        origin: SIMD3<Float>,
        dir: SIMD3<Float>,
        minBounds: SIMD3<Float>,
        maxBounds: SIMD3<Float>,
        maxDist: Float = 1000.0
    ) -> (hit: Bool, distance: Float, normal: SIMD3<Float>) {
        var tMin: Float = 0.0
        var tMax: Float = maxDist
        var hitNormal = SIMD3<Float>(0, 1, 0)

        for axis in 0..<3 {
            let o = origin[axis]
            let d = dir[axis]
            let bMin = minBounds[axis]
            let bMax = maxBounds[axis]

            if abs(d) < 1e-6 {
                if o < bMin || o > bMax {
                    return (false, .greatestFiniteMagnitude, .zero)
                }
            } else {
                let invD = 1.0 / d
                var t1 = (bMin - o) * invD
                var t2 = (bMax - o) * invD
                var n = SIMD3<Float>.zero
                n[axis] = d < 0 ? 1.0 : -1.0
                if t1 > t2 {
                    swap(&t1, &t2)
                }
                if t1 > tMin {
                    tMin = t1
                    hitNormal = n
                }
                tMax = min(tMax, t2)
                if tMin > tMax {
                    return (false, .greatestFiniteMagnitude, .zero)
                }
            }
        }

        if tMin >= 0 && tMin <= maxDist {
            return (true, tMin, hitNormal)
        }
        return (false, .greatestFiniteMagnitude, .zero)
    }

    public static func rayIntersectSphere(
        origin: SIMD3<Float>,
        dir: SIMD3<Float>,
        center: SIMD3<Float>,
        radius: Float,
        maxDist: Float = 1000.0
    ) -> (hit: Bool, distance: Float, point: SIMD3<Float>) {
        let oc = origin - center
        let b = simd_dot(oc, dir)
        let c = simd_dot(oc, oc) - radius * radius
        let h = b * b - c
        if h < 0.0 {
            return (false, .greatestFiniteMagnitude, .zero)
        }
        let sqrtH = sqrt(h)
        var t = -b - sqrtH
        if t < 0.0 {
            t = -b + sqrtH
        }
        if t >= 0.0 && t <= maxDist {
            return (true, t, origin + dir * t)
        }
        return (false, .greatestFiniteMagnitude, .zero)
    }
}
