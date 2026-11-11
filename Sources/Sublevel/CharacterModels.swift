import Foundation
import simd

/// Material description for a single procedural model part.
/// Shader modes:
///   0 = Mirror's Edge architectural surface (radiosity GI + micro-normal + crisp bevels + sky Fresnel)
///   1 = High-contrast team silhouette armor + unshaded Fresnel rim light
///   2 = Volumetric energy field / Fresnel distortion wave
///   3 = Pure radiant emissive neon / reticle / plasma core
///   4 = Precision machined hardware, brushed steel, polymer, tinted glass
public struct PartMaterial: Sendable {
    public var color: SIMD3<Float>
    public var roughness: Float
    public var metallic: Float
    public var emissive: Float
    public var mode: Float
    public var alpha: Float

    public init(
        color: SIMD3<Float>,
        roughness: Float,
        metallic: Float,
        emissive: Float,
        mode: Float,
        alpha: Float = 1.0
    ) {
        self.color = color
        self.roughness = roughness
        self.metallic = metallic
        self.emissive = emissive
        self.mode = mode
        self.alpha = alpha
    }

    public static func arch(_ color: SIMD3<Float>, roughness: Float = 0.22, metallic: Float = 0.05, emissive: Float = 0.0, alpha: Float = 1.0) -> PartMaterial {
        PartMaterial(color: color, roughness: roughness, metallic: metallic, emissive: emissive, mode: 0.0, alpha: alpha)
    }

    public static func hardware(_ color: SIMD3<Float>, roughness: Float = 0.34, metallic: Float = 0.65, emissive: Float = 0.0, alpha: Float = 1.0) -> PartMaterial {
        PartMaterial(color: color, roughness: roughness, metallic: metallic, emissive: emissive, mode: 4.0, alpha: alpha)
    }

    public static func armor(_ color: SIMD3<Float>) -> PartMaterial {
        PartMaterial(color: color, roughness: 0.16, metallic: 0.15, emissive: 0.85, mode: 1.0)
    }

    public static func energyField(_ color: SIMD3<Float>, intensity: Float = 1.5, alpha: Float = 0.65) -> PartMaterial {
        PartMaterial(color: color, roughness: 0.05, metallic: 0.0, emissive: intensity, mode: 2.0, alpha: alpha)
    }

    public static func glow(_ color: SIMD3<Float>, intensity: Float = 1.45, alpha: Float = 1.0) -> PartMaterial {
        PartMaterial(color: color, roughness: 0.04, metallic: 0.0, emissive: intensity, mode: 3.0, alpha: alpha)
    }

    public static func holoGlass(_ color: SIMD3<Float>, alpha: Float = 0.30) -> PartMaterial {
        PartMaterial(color: color, roughness: 0.06, metallic: 0.25, emissive: 0.55, mode: 4.0, alpha: alpha)
    }

    public static let gunmetal = PartMaterial.hardware(SIMD3<Float>(0.14, 0.155, 0.185), roughness: 0.36, metallic: 0.88)
    public static let brushedSteel = PartMaterial.hardware(SIMD3<Float>(0.64, 0.68, 0.74), roughness: 0.22, metallic: 0.92)
    public static let chrome = PartMaterial.hardware(SIMD3<Float>(0.84, 0.87, 0.92), roughness: 0.10, metallic: 0.96)
    public static let darkJoint = PartMaterial.hardware(SIMD3<Float>(0.075, 0.082, 0.098), roughness: 0.52, metallic: 0.45)
    public static let whiteShell = PartMaterial.hardware(SublevelPalette.starkWhite, roughness: 0.20, metallic: 0.12)
    public static let runnerGlove = PartMaterial.hardware(SIMD3<Float>(0.10, 0.11, 0.13), roughness: 0.46, metallic: 0.18)
    public static let runnerSuitWhite = PartMaterial.hardware(SIMD3<Float>(0.93, 0.95, 0.98), roughness: 0.28, metallic: 0.08)
    public static let runnerRedTrim = PartMaterial.hardware(SublevelPalette.signalRed, roughness: 0.20, metallic: 0.15, emissive: 0.18)
}

/// Accumulates instanced high-polygon parts across all procedural primitive meshes.
public struct ModelBatch {
    // Opaque mesh batches
    public var archBlocks: [GPUInstanceData] = []
    public var cubes: [GPUInstanceData] = []       // High-poly rounded/beveled box
    public var sharpCubes: [GPUInstanceData] = []  // Crisp 6-face box
    public var wedges: [GPUInstanceData] = []      // Sloped beveled wedge (+X ascent)
    public var cylinders: [GPUInstanceData] = []   // 40-seg chamfered cylinder
    public var tubes: [GPUInstanceData] = []       // 36-seg hollow barrel/pipe
    public var tori: [GPUInstanceData] = []        // 36x18 torus ring
    public var cones: [GPUInstanceData] = []       // 36-seg tapered cone/frustum
    public var octahedra: [GPUInstanceData] = []   // Faceted crystal / polyhedron
    public var spheres: [GPUInstanceData] = []     // 28x42 smooth sphere

    // Translucent mesh batches (auto-routed when alpha < 0.98)
    public var translucentCubes: [GPUInstanceData] = []
    public var translucentTori: [GPUInstanceData] = []
    public var translucentCones: [GPUInstanceData] = []
    public var translucentSpheres: [GPUInstanceData] = []

    /// When set, every non-glow part is rendered with this color (hit flash).
    public var flashOverride: SIMD3<Float>? = nil

    public init() {}

    public mutating func archBlock(
        _ parent: simd_float4x4,
        _ offset: SIMD3<Float>,
        _ size: SIMD3<Float>,
        _ mat: PartMaterial,
        extra: Float = 0.0,
        rotation: simd_float4x4 = matrix_identity_float4x4
    ) {
        let model = parent * Math3D.translation(offset) * rotation * Math3D.scale(size)
        let c = model.columns.3
        let half = size * 0.5
        let inst = GPUInstanceData(
            modelMatrix: model,
            boxCenterAndKind: SIMD4<Float>(c.x, c.y, c.z, mat.mode),
            boxHalfExtents: SIMD4<Float>(half.x, half.y, half.z, extra),
            colorAndRoughness: SIMD4<Float>(mat.color.x, mat.color.y, mat.color.z, mat.roughness),
            materialParams: SIMD4<Float>(mat.metallic, mat.emissive, mat.alpha, 0.0)
        )
        if mat.alpha < 0.98 {
            translucentCubes.append(inst)
        } else {
            archBlocks.append(inst)
        }
    }

    public mutating func box(
        _ parent: simd_float4x4,
        _ offset: SIMD3<Float>,
        _ size: SIMD3<Float>,
        _ mat: PartMaterial,
        rotation: simd_float4x4 = matrix_identity_float4x4
    ) {
        let inst = makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat)
        if mat.alpha < 0.98 {
            translucentCubes.append(inst)
        } else {
            cubes.append(inst)
        }
    }

    public mutating func sharpBox(
        _ parent: simd_float4x4,
        _ offset: SIMD3<Float>,
        _ size: SIMD3<Float>,
        _ mat: PartMaterial,
        rotation: simd_float4x4 = matrix_identity_float4x4
    ) {
        let inst = makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat)
        if mat.alpha < 0.98 {
            translucentCubes.append(inst)
        } else {
            sharpCubes.append(inst)
        }
    }

    /// Sloped wedge rising along local +X from -0.5 to +0.5.
    public mutating func wedge(
        _ parent: simd_float4x4,
        _ offset: SIMD3<Float>,
        _ size: SIMD3<Float>,
        _ mat: PartMaterial,
        rotation: simd_float4x4 = matrix_identity_float4x4
    ) {
        let model = parent * Math3D.translation(offset) * rotation * Math3D.scale(size)
        wedges.append(makeInstance(model, mat))
    }

    /// Solid chamfered cylinder aligned to local Z axis.
    public mutating func cylinder(
        _ parent: simd_float4x4,
        _ offset: SIMD3<Float>,
        radius: Float,
        length: Float,
        _ mat: PartMaterial,
        rotation: simd_float4x4 = matrix_identity_float4x4
    ) {
        let size = SIMD3<Float>(radius * 2.0, radius * 2.0, length)
        cylinders.append(makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat))
    }

    /// Hollow barrel / pipe aligned to local Z axis (inner bore visible!).
    public mutating func tube(
        _ parent: simd_float4x4,
        _ offset: SIMD3<Float>,
        radius: Float,
        length: Float,
        _ mat: PartMaterial,
        rotation: simd_float4x4 = matrix_identity_float4x4
    ) {
        let size = SIMD3<Float>(radius * 2.0, radius * 2.0, length)
        tubes.append(makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat))
    }

    /// Torus ring in local XY plane (axis along local Z). `outerRadius` is total outer radius.
    public mutating func torus(
        _ parent: simd_float4x4,
        _ offset: SIMD3<Float>,
        outerRadius: Float,
        thicknessScale: Float = 1.0,
        _ mat: PartMaterial,
        rotation: simd_float4x4 = matrix_identity_float4x4
    ) {
        let d = outerRadius * 2.0
        let size = SIMD3<Float>(d, d, d * thicknessScale)
        let inst = makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat)
        if mat.alpha < 0.98 {
            translucentTori.append(inst)
        } else {
            tori.append(inst)
        }
    }

    /// Tapered cone/frustum along local Z (wide base at -Z, narrow tip at +Z).
    public mutating func cone(
        _ parent: simd_float4x4,
        _ offset: SIMD3<Float>,
        radius: Float,
        length: Float,
        _ mat: PartMaterial,
        rotation: simd_float4x4 = matrix_identity_float4x4
    ) {
        let size = SIMD3<Float>(radius * 2.0, radius * 2.0, length)
        let inst = makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat)
        if mat.alpha < 0.98 {
            translucentCones.append(inst)
        } else {
            cones.append(inst)
        }
    }

    public mutating func octahedron(
        _ parent: simd_float4x4,
        _ offset: SIMD3<Float>,
        _ size: SIMD3<Float>,
        _ mat: PartMaterial,
        rotation: simd_float4x4 = matrix_identity_float4x4
    ) {
        octahedra.append(makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat))
    }

    public mutating func sphere(
        _ parent: simd_float4x4,
        _ offset: SIMD3<Float>,
        _ size: SIMD3<Float>,
        _ mat: PartMaterial,
        rotation: simd_float4x4 = matrix_identity_float4x4
    ) {
        let inst = makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat)
        if mat.alpha < 0.98 {
            translucentSpheres.append(inst)
        } else {
            spheres.append(inst)
        }
    }

    /// Connects `from` -> `to` in `parent` space with a cylindrical rod / strut.
    public mutating func strut(
        _ parent: simd_float4x4,
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        _ mat: PartMaterial
    ) {
        let seg = Math3D.segmentTransform(from: start, to: end, width: radius * 2.0, height: radius * 2.0)
        cylinders.append(makeInstance(parent * seg, mat))
    }

    /// Connects `from` -> `to` in `parent` space with a beveled structural beam.
    public mutating func beamStrut(
        _ parent: simd_float4x4,
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        width: Float,
        height: Float,
        _ mat: PartMaterial
    ) {
        let seg = Math3D.segmentTransform(from: start, to: end, width: width, height: height)
        let inst = makeInstance(parent * seg, mat)
        if mat.alpha < 0.98 {
            translucentCubes.append(inst)
        } else {
            cubes.append(inst)
        }
    }

    private func makeInstance(_ model: simd_float4x4, _ mat: PartMaterial) -> GPUInstanceData {
        let c = model.columns.3
        var color = mat.color
        if let flash = flashOverride, mat.mode < 2.5 || mat.mode > 3.5 {
            color = flash
        }
        return GPUInstanceData(
            modelMatrix: model,
            boxCenterAndKind: SIMD4<Float>(c.x, c.y, c.z, mat.mode),
            boxHalfExtents: SIMD4<Float>(100, 100, 100, 1.0),
            colorAndRoughness: SIMD4<Float>(color.x, color.y, color.z, mat.roughness),
            materialParams: SIMD4<Float>(mat.metallic, mat.emissive, mat.alpha, 0.0)
        )
    }
}

enum CharacterModels {
    static let quarterTurn: Float = .pi * 0.5

    /// Builds an orthonormal basis whose local +Z axis points along `forward`.
    static func orientation(forward: SIMD3<Float>) -> simd_float4x4 {
        let lenSq = simd_length_squared(forward)
        let f = lenSq > 1e-8 ? forward * (1.0 / sqrt(lenSq)) : SIMD3<Float>(0, 0, -1)
        let upRef: SIMD3<Float> = abs(f.y) > 0.95 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(f, upRef))
        let up = simd_cross(right, f)
        return simd_float4x4(columns: (
            SIMD4<Float>(right.x, right.y, right.z, 0),
            SIMD4<Float>(up.x, up.y, up.z, 0),
            SIMD4<Float>(f.x, f.y, f.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    // MARK: - Authentic High-Polygon Weapons + First-Person Runner Hands
    // Local space: origin at the pistol grip/hand, +Y up, -Z toward the muzzle.

    static func appendWeapon(
        _ weapon: WeaponSlot,
        root: simd_float4x4,
        into batch: inout ModelBatch,
        time: Float,
        fireKick: Float = 0.0,
        rocketCharges: Int = 0,
        glowBoost: Float = 0.0,
        includeHands: Bool = false
    ) {
        let accent = weapon.accentColor
        let glow = PartMaterial.glow(accent, intensity: 1.45 + glowBoost)
        let paint = PartMaterial.hardware(accent * 0.92, roughness: 0.24, metallic: 0.28, emissive: 0.14)

        switch weapon {
        case .kineticGauntlet:
            appendGauntlet(root, &batch, glow: glow, paint: paint, fireKick: fireKick, time: time, includeHands: includeHands)
        case .prismRifle:
            appendPrismRifle(root, &batch, glow: glow, paint: paint, fireKick: fireKick, time: time, includeHands: includeHands)
        case .shardCannon:
            appendShardCannon(root, &batch, glow: glow, paint: paint, fireKick: fireKick, time: time, includeHands: includeHands)
        case .vectorLauncher:
            appendVectorLauncher(root, &batch, glow: glow, paint: paint, fireKick: fireKick, rocketCharges: rocketCharges, time: time, includeHands: includeHands)
        case .subRail:
            appendSubRail(root, &batch, glow: glow, paint: paint, fireKick: fireKick, time: time, includeHands: includeHands)
        }
    }

    /// Ergonomic stippled pistol grip + trigger + curved trigger guard
    private static func appendGrip(_ root: simd_float4x4, _ b: inout ModelBatch, at offset: SIMD3<Float> = .zero) {
        b.box(root, offset + SIMD3<Float>(0, -0.095, 0.025), SIMD3<Float>(0.056, 0.18, 0.078), .darkJoint, rotation: Math3D.rotationX(-0.30))
        b.box(root, offset + SIMD3<Float>(0, -0.095, 0.052), SIMD3<Float>(0.058, 0.15, 0.022), .runnerRedTrim, rotation: Math3D.rotationX(-0.30))
        // Trigger & milled guard loop
        b.box(root, offset + SIMD3<Float>(0, -0.032, -0.042), SIMD3<Float>(0.014, 0.042, 0.016), .chrome, rotation: Math3D.rotationX(0.32))
        b.box(root, offset + SIMD3<Float>(0, -0.058, -0.055), SIMD3<Float>(0.028, 0.014, 0.105), .gunmetal)
        b.box(root, offset + SIMD3<Float>(0, -0.035, -0.102), SIMD3<Float>(0.028, 0.052, 0.014), .gunmetal, rotation: Math3D.rotationX(-0.25))
    }

    /// Machined Picatinny accessory rail with cross-slots
    private static func appendPicatinnyRail(_ root: simd_float4x4, _ b: inout ModelBatch, y: Float, zStart: Float, length: Float, teeth: Int) {
        b.box(root, SIMD3<Float>(0, y, zStart - length * 0.5), SIMD3<Float>(0.038, 0.014, length), .gunmetal)
        let step = length / Float(max(teeth, 1))
        for i in 0..<teeth {
            let z = zStart - (Float(i) + 0.5) * step
            b.box(root, SIMD3<Float>(0, y + 0.010, z), SIMD3<Float>(0.044, 0.009, step * 0.58), .brushedSteel)
        }
    }

    /// Sleek Mirror's Edge Runner gloved hands & athletic forearms gripping grip + forend
    private static func appendRunnerHands(
        _ root: simd_float4x4,
        _ b: inout ModelBatch,
        rightGrip: SIMD3<Float>,
        leftSupport: SIMD3<Float>?
    ) {
        // Right firing hand + red Runner knuckle wrap + white forearm cuff
        let rHand = root * Math3D.translation(rightGrip)
        b.box(rHand, SIMD3<Float>(0.01, -0.075, 0.01), SIMD3<Float>(0.082, 0.095, 0.098), .runnerGlove, rotation: Math3D.rotationX(-0.28))
        b.box(rHand, SIMD3<Float>(0.012, -0.048, -0.02), SIMD3<Float>(0.088, 0.032, 0.078), .runnerRedTrim, rotation: Math3D.rotationX(-0.28))
        // Articulated wrapped fingers around pistol grip
        for f in 0..<4 {
            let fy = -0.045 - Float(f) * 0.021
            b.box(rHand, SIMD3<Float>(-0.022, fy, -0.028), SIMD3<Float>(0.048, 0.017, 0.045), .runnerGlove)
        }
        // Right wrist & forearm extending back toward camera shoulder
        b.strut(root, from: rightGrip + SIMD3<Float>(0.02, -0.09, 0.05), to: rightGrip + SIMD3<Float>(0.18, -0.22, 0.52), radius: 0.052, .runnerSuitWhite)
        b.torus(root, rightGrip + SIMD3<Float>(0.04, -0.105, 0.10), outerRadius: 0.058, thicknessScale: 0.7, .runnerRedTrim, rotation: Math3D.rotationX(0.25))

        // Left support hand & angled athletic forearm reaching naturally from lower-left shoulder
        if let lPos = leftSupport {
            let lHand = root * Math3D.translation(lPos)
            b.box(lHand, SIMD3<Float>(-0.018, -0.02, 0.0), SIMD3<Float>(0.084, 0.074, 0.112), .runnerGlove, rotation: Math3D.rotationZ(0.25))
            b.box(lHand, SIMD3<Float>(-0.025, -0.008, 0.01), SIMD3<Float>(0.088, 0.026, 0.082), .runnerRedTrim, rotation: Math3D.rotationZ(0.25))
            for f in 0..<4 {
                let fz = -0.038 + Float(f) * 0.024
                b.box(lHand, SIMD3<Float>(0.022, -0.005, fz), SIMD3<Float>(0.042, 0.020, 0.020), .runnerGlove)
            }
            let wrist = lPos + SIMD3<Float>(-0.045, -0.035, 0.04)
            let elbow = lPos + SIMD3<Float>(-0.46, -0.26, 0.34)
            b.strut(root, from: wrist, to: elbow, radius: 0.044, .darkJoint)
            b.torus(root, lPos + SIMD3<Float>(-0.08, -0.055, 0.08), outerRadius: 0.050, thicknessScale: 0.9, .runnerRedTrim, rotation: Math3D.rotationY(0.65))
        }
    }

    // 1. KINETIC GAUNTLET — Pneumatic Exo-Frame Power Fist + Flywheel Rotor + 3 Telescoping Rams
    private static func appendGauntlet(_ r: simd_float4x4, _ b: inout ModelBatch, glow: PartMaterial, paint: PartMaterial, fireKick: Float, time: Float, includeHands: Bool) {
        let extend = fireKick * 0.16

        // Sculpted stark-white exo-forearm chassis + underside carbon cradle
        b.box(r, SIMD3<Float>(0, -0.005, 0.16), SIMD3<Float>(0.21, 0.17, 0.44), .whiteShell)
        b.box(r, SIMD3<Float>(0, -0.075, 0.16), SIMD3<Float>(0.18, 0.06, 0.40), .gunmetal)
        b.wedge(r, SIMD3<Float>(0, 0.095, 0.14), SIMD3<Float>(0.28, 0.045, 0.16), paint, rotation: Math3D.rotationY(quarterTurn))
        appendPicatinnyRail(r, &b, y: 0.088, zStart: 0.0, length: 0.18, teeth: 6)

        // Spinning wrist flywheel gyro-turbine visible in open top housing
        let wheelSpin = Math3D.rotationX(quarterTurn) * Math3D.rotationZ(time * (6.5 + fireKick * 18.0))
        b.torus(r, SIMD3<Float>(0, 0.085, 0.24), outerRadius: 0.072, thicknessScale: 0.65, .brushedSteel, rotation: Math3D.rotationX(quarterTurn))
        b.torus(r, SIMD3<Float>(0, 0.092, 0.24), outerRadius: 0.052, thicknessScale: 0.55, glow, rotation: wheelSpin)
        b.cylinder(r, SIMD3<Float>(0, 0.085, 0.24), radius: 0.024, length: 0.05, .chrome, rotation: Math3D.rotationX(quarterTurn))

        // Twin side-mounted pneumatic pressure cylinders + torus cooling collars
        for side: Float in [-1, 1] {
            let sx = side * 0.122
            b.cylinder(r, SIMD3<Float>(sx, 0.005, 0.14), radius: 0.042, length: 0.34, .gunmetal)
            b.cylinder(r, SIMD3<Float>(sx, 0.005, -0.06 - extend * 0.6), radius: 0.024, length: 0.20, .chrome)
            for ringZ: Float in [0.04, 0.14, 0.24] {
                b.torus(r, SIMD3<Float>(sx, 0.005, ringZ), outerRadius: 0.048, thicknessScale: 0.55, side < 0 ? glow : .brushedSteel)
            }
        }

        // Articulated 5-digit armored power-glove knuckles
        b.box(r, SIMD3<Float>(0, -0.015, -0.14), SIMD3<Float>(0.22, 0.16, 0.16), .runnerGlove)
        b.box(r, SIMD3<Float>(0, 0.055, -0.13), SIMD3<Float>(0.20, 0.045, 0.14), .runnerRedTrim)
        for i in 0..<4 {
            let x = -0.075 + Float(i) * 0.05
            b.box(r, SIMD3<Float>(x, 0.025, -0.235), SIMD3<Float>(0.044, 0.068, 0.048), .brushedSteel, rotation: Math3D.rotationX(0.25))
            b.box(r, SIMD3<Float>(x, -0.028, -0.255), SIMD3<Float>(0.040, 0.058, 0.042), .gunmetal, rotation: Math3D.rotationX(0.65))
        }
        // Thumb armor
        b.box(r, SIMD3<Float>(-0.125, -0.025, -0.16), SIMD3<Float>(0.048, 0.055, 0.11), .gunmetal, rotation: Math3D.rotationY(0.35))

        // Three telescoping hollow tungsten impact rams + shock emitter ring
        for i in -1...1 {
            let x = Float(i) * 0.068
            b.tube(r, SIMD3<Float>(x, 0.108, -0.03), radius: 0.028, length: 0.28, .gunmetal)
            b.cylinder(r, SIMD3<Float>(x, 0.108, -0.19 - extend), radius: 0.017, length: 0.20, .chrome)
        }
        // Beveled kinetic strike anvil + glowing impulse ring
        b.box(r, SIMD3<Float>(0, 0.045, -0.295 - extend), SIMD3<Float>(0.25, 0.19, 0.034), .brushedSteel)
        b.torus(r, SIMD3<Float>(0, 0.045, -0.316 - extend), outerRadius: 0.088, thicknessScale: 0.45, glow)
        b.octahedron(r, SIMD3<Float>(0, 0.045, -0.318 - extend), SIMD3<Float>(0.065, 0.065, 0.028), glow)

        if includeHands {
            b.strut(r, from: SIMD3<Float>(0.02, -0.02, 0.36), to: SIMD3<Float>(0.18, -0.18, 0.72), radius: 0.068, .runnerSuitWhite)
        }
    }

    // 2. PRISM RIFLE — Bullpup Precision Energy Carbine with Holo Reflex Sight & Fluted Barrel Shroud
    private static func appendPrismRifle(_ r: simd_float4x4, _ b: inout ModelBatch, glow: PartMaterial, paint: PartMaterial, fireKick: Float, time: Float, includeHands: Bool) {
        let boltTravel = fireKick * 0.085

        // Bullpup Stark-White ergonomic upper/lower receiver & thumbhole stock
        b.box(r, SIMD3<Float>(0, 0.048, -0.10), SIMD3<Float>(0.096, 0.118, 0.52), .whiteShell)
        b.wedge(r, SIMD3<Float>(0, 0.095, -0.32), SIMD3<Float>(0.14, 0.04, 0.092), .whiteShell, rotation: Math3D.rotationY(-quarterTurn))
        b.box(r, SIMD3<Float>(0, 0.012, 0.24), SIMD3<Float>(0.078, 0.125, 0.26), .gunmetal)
        b.box(r, SIMD3<Float>(0, 0.078, 0.24), SIMD3<Float>(0.084, 0.036, 0.22), .darkJoint) // Cheek rest
        b.box(r, SIMD3<Float>(0, -0.008, 0.39), SIMD3<Float>(0.086, 0.168, 0.042), .darkJoint) // Rubber buttpad
        b.beamStrut(r, from: SIMD3<Float>(0, -0.14, 0.06), to: SIMD3<Float>(0, -0.07, 0.36), width: 0.044, height: 0.032, .whiteShell)

        appendGrip(r, &b)
        appendPicatinnyRail(r, &b, y: 0.114, zStart: 0.10, length: 0.52, teeth: 14)

        // Reciprocating side charging handle + ejection/cooling port
        b.box(r, SIMD3<Float>(0.050, 0.062, -0.08 + boltTravel), SIMD3<Float>(0.012, 0.032, 0.11), .brushedSteel)
        b.cylinder(r, SIMD3<Float>(0.068, 0.062, -0.11 + boltTravel), radius: 0.011, length: 0.038, .darkJoint, rotation: Math3D.rotationY(quarterTurn))

        // Bullpup translucent Electric-Cyan energy cell magazine behind grip + forward angled magwell
        b.box(r, SIMD3<Float>(0, -0.075, 0.20), SIMD3<Float>(0.058, 0.14, 0.088), .gunmetal, rotation: Math3D.rotationX(-0.18))
        b.box(r, SIMD3<Float>(0, -0.082, 0.20), SIMD3<Float>(0.062, 0.10, 0.056), .holoGlass(glow.color, alpha: 0.55), rotation: Math3D.rotationX(-0.18))
        b.cylinder(r, SIMD3<Float>(0, -0.082, 0.20), radius: 0.018, length: 0.09, glow, rotation: Math3D.rotationX(quarterTurn - 0.18))

        // Angled tactical foregrip
        b.box(r, SIMD3<Float>(0, -0.038, -0.34), SIMD3<Float>(0.048, 0.085, 0.095), .darkJoint, rotation: Math3D.rotationX(0.38))

        // Ventilated hollow barrel shroud + fluted chrome inner barrel + side energy busbars
        b.tube(r, SIMD3<Float>(0, 0.048, -0.52), radius: 0.052, length: 0.36, .gunmetal)
        b.cylinder(r, SIMD3<Float>(0, 0.048, -0.58), radius: 0.024, length: 0.44, .brushedSteel)
        for k in 0..<4 {
            let ringZ = -0.38 - Float(k) * 0.085
            b.torus(r, SIMD3<Float>(0, 0.048, ringZ), outerRadius: 0.055, thicknessScale: 0.45, .darkJoint)
        }
        b.box(r, SIMD3<Float>( 0.054, 0.048, -0.52), SIMD3<Float>(0.012, 0.022, 0.34), glow)
        b.box(r, SIMD3<Float>(-0.054, 0.048, -0.52), SIMD3<Float>(0.012, 0.022, 0.34), glow)

        // 3-Prong Muzzle Emitter Fork + Levitating Multi-Faceted Spinning Prism Crystal
        b.tube(r, SIMD3<Float>(0, 0.048, -0.78), radius: 0.034, length: 0.09, .darkJoint)
        for prong in 0..<3 {
            let ang = Float(prong) * (2.0 * .pi / 3.0)
            let rot = Math3D.rotationZ(ang)
            b.box(r * Math3D.translation(SIMD3<Float>(0, 0.048, -0.84)) * rot, SIMD3<Float>(0, 0.052, 0), SIMD3<Float>(0.016, 0.022, 0.12), .brushedSteel)
            b.box(r * Math3D.translation(SIMD3<Float>(0, 0.048, -0.89)) * rot, SIMD3<Float>(0, 0.040, 0), SIMD3<Float>(0.010, 0.012, 0.04), glow)
        }
        let crystalSpin = Math3D.rotationZ(time * 2.8) * Math3D.rotationX(time * 1.9)
        b.octahedron(r, SIMD3<Float>(0, 0.048, -0.865), SIMD3<Float>(0.068, 0.068, 0.092), glow, rotation: crystalSpin)
        b.torus(r, SIMD3<Float>(0, 0.048, -0.865), outerRadius: 0.048, thicknessScale: 0.35, glow, rotation: Math3D.rotationY(time * 4.2))

        // Open Holographic Reflex Sight (Anodized protective hood + translucent glass + projected cyan reticle!)
        let sightZ: Float = -0.10
        b.box(r, SIMD3<Float>(0, 0.132, sightZ), SIMD3<Float>(0.056, 0.022, 0.115), .darkJoint)
        b.box(r, SIMD3<Float>(-0.028, 0.168, sightZ), SIMD3<Float>(0.008, 0.058, 0.095), .gunmetal)
        b.box(r, SIMD3<Float>( 0.028, 0.168, sightZ), SIMD3<Float>(0.008, 0.058, 0.095), .gunmetal)
        b.box(r, SIMD3<Float>(0, 0.196, sightZ), SIMD3<Float>(0.064, 0.008, 0.095), .gunmetal)
        b.sharpBox(r, SIMD3<Float>(0, 0.168, sightZ - 0.01), SIMD3<Float>(0.048, 0.048, 0.004), .holoGlass(glow.color, alpha: 0.26), rotation: Math3D.rotationX(-0.12))
        b.torus(r, SIMD3<Float>(0, 0.168, sightZ - 0.013), outerRadius: 0.014, thicknessScale: 0.35, glow)
        b.sphere(r, SIMD3<Float>(0, 0.168, sightZ - 0.013), SIMD3<Float>(0.005, 0.005, 0.005), glow)

        if includeHands {
            appendRunnerHands(r, &b, rightGrip: SIMD3<Float>(0, -0.02, 0.02), leftSupport: SIMD3<Float>(0, -0.035, -0.34))
        }
    }

    // 3. SHARD CANNON — Heavy Rotary 6-Chamber Drum + Triple Perforated Flak Barrels + Under-Barrel GL
    private static func appendShardCannon(_ r: simd_float4x4, _ b: inout ModelBatch, glow: PartMaterial, paint: PartMaterial, fireKick: Float, time: Float, includeHands: Bool) {
        let pumpSlide = fireKick * 0.075

        // Industrial milled receiver + white composite upper shell + glowing thermal vents
        b.box(r, SIMD3<Float>(0, 0.055, -0.08), SIMD3<Float>(0.165, 0.155, 0.40), .whiteShell)
        b.box(r, SIMD3<Float>(0, -0.01, -0.08), SIMD3<Float>(0.145, 0.085, 0.38), .gunmetal)
        b.box(r, SIMD3<Float>(0, 0.015, 0.22), SIMD3<Float>(0.095, 0.13, 0.24), .gunmetal, rotation: Math3D.rotationX(0.06))
        b.box(r, SIMD3<Float>(0, 0.0, 0.35), SIMD3<Float>(0.105, 0.165, 0.045), .darkJoint)
        appendGrip(r, &b)
        appendPicatinnyRail(r, &b, y: 0.138, zStart: 0.08, length: 0.34, teeth: 9)

        for i in 0..<4 {
            let vz = -0.22 + Float(i) * 0.065
            b.box(r, SIMD3<Float>(0, 0.134, vz), SIMD3<Float>(0.115, 0.012, 0.026), glow)
        }

        // 6-Chamber Revolving Flak Drum (rotates dynamically on fireKick!)
        let drumCenter = SIMD3<Float>(0, -0.055, -0.16)
        let drumRot = Math3D.rotationZ(fireKick * 1.05)
        let drumRoot = r * Math3D.translation(drumCenter) * drumRot
        b.cylinder(drumRoot, .zero, radius: 0.086, length: 0.165, paint)
        b.cylinder(drumRoot, .zero, radius: 0.032, length: 0.185, .brushedSteel)
        for ch in 0..<6 {
            let a = Float(ch) * (.pi / 3.0)
            let cx = cos(a) * 0.055
            let cy = sin(a) * 0.055
            b.tube(drumRoot, SIMD3<Float>(cx, cy, 0), radius: 0.022, length: 0.170, .gunmetal)
            b.cylinder(drumRoot, SIMD3<Float>(cx, cy, 0), radius: 0.014, length: 0.158, glow)
        }

        // Heavy CNC Front Trunnion Block + Triple Hollow Flak Barrels + Slotted Muzzle Brakes
        b.box(r, SIMD3<Float>(0, 0.068, -0.33), SIMD3<Float>(0.19, 0.175, 0.075), .gunmetal)
        b.box(r, SIMD3<Float>(0, 0.068, -0.58), SIMD3<Float>(0.175, 0.155, 0.042), .brushedSteel)

        let barrelOffsets: [SIMD2<Float>] = [SIMD2(-0.048, 0.038), SIMD2(0.048, 0.038), SIMD2(0, 0.118)]
        for o in barrelOffsets {
            // Outer heavy fluted barrel + hollow glowing bore + ventilated muzzle compensator
            b.tube(r, SIMD3<Float>(o.x, o.y, -0.52), radius: 0.038, length: 0.38, .brushedSteel)
            b.tube(r, SIMD3<Float>(o.x, o.y, -0.73), radius: 0.045, length: 0.075, .gunmetal)
            b.torus(r, SIMD3<Float>(o.x, o.y, -0.765), outerRadius: 0.046, thicknessScale: 0.45, .darkJoint)
            b.cylinder(r, SIMD3<Float>(o.x, o.y, -0.68), radius: 0.022, length: 0.04, glow)
        }

        // Under-barrel 40mm Fragmentation Grenade Launcher Tube + Ribbed Pump Forend
        b.tube(r, SIMD3<Float>(0, -0.035, -0.49), radius: 0.042, length: 0.30, .gunmetal)
        b.torus(r, SIMD3<Float>(0, -0.035, -0.64), outerRadius: 0.044, thicknessScale: 0.5, paint)
        b.box(r, SIMD3<Float>(0, -0.078, -0.44 + pumpSlide), SIMD3<Float>(0.095, 0.058, 0.18), .darkJoint)
        for rib in 0..<5 {
            b.box(r, SIMD3<Float>(0, -0.106, -0.50 + Float(rib) * 0.03 + pumpSlide), SIMD3<Float>(0.10, 0.012, 0.014), .gunmetal)
        }

        // Flip-up Iron Sights (Front blade + glowing amber fiber-optic dot, Rear peep ring)
        b.torus(r, SIMD3<Float>(0, 0.168, 0.02), outerRadius: 0.020, thicknessScale: 0.5, .gunmetal)
        b.box(r, SIMD3<Float>(0, 0.168, -0.60), SIMD3<Float>(0.036, 0.038, 0.016), .gunmetal)
        b.sphere(r, SIMD3<Float>(0, 0.176, -0.60), SIMD3<Float>(0.012, 0.012, 0.012), glow)

        if includeHands {
            appendRunnerHands(r, &b, rightGrip: SIMD3<Float>(0, -0.02, 0.02), leftSupport: SIMD3<Float>(0, -0.078, -0.44 + pumpSlide))
        }
    }

    // 4. VECTOR LAUNCHER — Shoulder-Fired Multi-Tube Guided Missile System with Optical Rangefinder HUD
    private static func appendVectorLauncher(_ r: simd_float4x4, _ b: inout ModelBatch, glow: PartMaterial, paint: PartMaterial, fireKick: Float, rocketCharges: Int, time: Float, includeHands: Bool) {
        let tubeY: Float = 0.125

        // Composite filament-wound hollow main launch tube + inner tri-barrel cluster
        b.tube(r, SIMD3<Float>(0, tubeY, -0.10), radius: 0.108, length: 0.92, .whiteShell)
        b.tube(r, SIMD3<Float>(0, tubeY, -0.58), radius: 0.122, length: 0.09, .gunmetal)

        // Structural clamp collars + top Picatinny rail + shoulder pad
        for z: Float in [-0.42, -0.16, 0.10, 0.30] {
            b.torus(r, SIMD3<Float>(0, tubeY, z), outerRadius: 0.118, thicknessScale: 0.45, z < -0.1 ? paint : .gunmetal)
        }
        appendPicatinnyRail(r, &b, y: tubeY + 0.112, zStart: -0.02, length: 0.42, teeth: 10)
        b.box(r, SIMD3<Float>(0, tubeY - 0.105, 0.18), SIMD3<Float>(0.13, 0.045, 0.24), .darkJoint) // Contoured shoulder pad

        // Tri-chamber rotary missile cluster inside the muzzle (shows 1..3 armed warheads!)
        let visibleWarheads = max(1, rocketCharges)
        for i in 0..<3 {
            let a = Float(i) * (2.0 * .pi / 3.0) + .pi * 0.5
            let subX = cos(a) * 0.048
            let subY = tubeY + sin(a) * 0.048
            b.tube(r, SIMD3<Float>(subX, subY, -0.52), radius: 0.040, length: 0.22, .darkJoint)
            if i < visibleWarheads {
                let warheadGlow = rocketCharges > 0 ? PartMaterial.glow(SublevelPalette.amberGold, intensity: 1.8) : glow
                b.cone(r, SIMD3<Float>(subX, subY, -0.58 + fireKick * 0.06), radius: 0.034, length: 0.09, warheadGlow, rotation: Math3D.rotationY(.pi))
            }
        }

        // Flared rear Venturi exhaust bell
        b.cone(r, SIMD3<Float>(0, tubeY, 0.42), radius: 0.138, length: 0.15, .gunmetal, rotation: Math3D.rotationY(.pi))
        b.tube(r, SIMD3<Float>(0, tubeY, 0.48), radius: 0.136, length: 0.04, .brushedSteel)
        b.torus(r, SIMD3<Float>(0, tubeY, 0.49), outerRadius: 0.095, thicknessScale: 0.45, glow)

        // Lower fire-control housing + dual grips
        b.box(r, SIMD3<Float>(0, 0.022, -0.14), SIMD3<Float>(0.088, 0.065, 0.46), .gunmetal)
        appendGrip(r, &b)
        b.box(r, SIMD3<Float>(0, -0.055, -0.32), SIMD3<Float>(0.052, 0.155, 0.068), .darkJoint, rotation: Math3D.rotationX(-0.18))

        // Left-side flip-out Optical Rangefinder & Laser Target Designator Pod
        b.box(r, SIMD3<Float>(-0.135, tubeY + 0.02, -0.20), SIMD3<Float>(0.068, 0.085, 0.19), .gunmetal)
        b.cylinder(r, SIMD3<Float>(-0.145, tubeY + 0.045, -0.31), radius: 0.022, length: 0.06, .brushedSteel)
        b.sphere(r, SIMD3<Float>(-0.145, tubeY + 0.045, -0.34), SIMD3<Float>(0.026, 0.026, 0.012), glow)
        // Translucent flip-out smart-HUD glass screen facing the shooter
        b.box(r, SIMD3<Float>(-0.165, tubeY + 0.085, -0.14), SIMD3<Float>(0.075, 0.062, 0.010), .gunmetal)
        b.sharpBox(r, SIMD3<Float>(-0.165, tubeY + 0.085, -0.132), SIMD3<Float>(0.064, 0.050, 0.004), .holoGlass(glow.color, alpha: 0.34))
        b.torus(r, SIMD3<Float>(-0.165, tubeY + 0.085, -0.129), outerRadius: 0.016, thicknessScale: 0.35, glow)

        // Three physical LED charge cells along the right side of the launcher
        for i in 0..<3 {
            let lit = i < rocketCharges
            let mat = lit ? PartMaterial.glow(SublevelPalette.amberGold, intensity: 2.1) : PartMaterial.darkJoint
            b.box(r, SIMD3<Float>(0.112, tubeY + 0.025, -0.26 + Float(i) * 0.075), SIMD3<Float>(0.024, 0.036, 0.052), mat)
        }

        if includeHands {
            appendRunnerHands(r, &b, rightGrip: SIMD3<Float>(0, -0.02, 0.02), leftSupport: SIMD3<Float>(0, -0.055, -0.32))
        }
    }

    // 5. SUB-RAIL — Precision Anti-Materiel Electromagnetic Rail Sniper with Dual-Bell Scope & 8 Toroidal Coils
    private static func appendSubRail(_ r: simd_float4x4, _ b: inout ModelBatch, glow: PartMaterial, paint: PartMaterial, fireKick: Float, time: Float, includeHands: Bool) {
        let boltCycle = fireKick * 0.095

        // Skeletonized precision chassis, capacitor bank & adjustable sniper stock
        b.box(r, SIMD3<Float>(0, 0.048, -0.06), SIMD3<Float>(0.104, 0.132, 0.46), .whiteShell)
        b.box(r, SIMD3<Float>(0, -0.048, -0.18), SIMD3<Float>(0.088, 0.082, 0.20), paint)
        // Bolt-action cycling handle
        b.cylinder(r, SIMD3<Float>(0.065, 0.065, 0.04 + boltCycle), radius: 0.009, length: 0.055, .chrome, rotation: Math3D.rotationY(quarterTurn))
        b.sphere(r, SIMD3<Float>(0.095, 0.065, 0.04 + boltCycle), SIMD3<Float>(0.028, 0.028, 0.028), .darkJoint)

        // Adjustable skeletonized stock + cheek riser + rear monopod
        b.strut(r, from: SIMD3<Float>(0, 0.072, 0.16), to: SIMD3<Float>(0, 0.062, 0.44), radius: 0.018, .gunmetal)
        b.strut(r, from: SIMD3<Float>(0, -0.022, 0.14), to: SIMD3<Float>(0, -0.055, 0.44), radius: 0.018, .gunmetal)
        b.box(r, SIMD3<Float>(0, 0.098, 0.30), SIMD3<Float>(0.068, 0.032, 0.16), .darkJoint)
        b.box(r, SIMD3<Float>(0, 0.005, 0.45), SIMD3<Float>(0.076, 0.185, 0.038), .darkJoint)
        b.cylinder(r, SIMD3<Float>(0, -0.095, 0.41), radius: 0.012, length: 0.09, .brushedSteel, rotation: Math3D.rotationX(quarterTurn))

        appendGrip(r, &b)
        appendPicatinnyRail(r, &b, y: 0.120, zStart: 0.12, length: 0.42, teeth: 11)

        // Twin 0.80m Slotted Electromagnetic Rails + Ionized Plasma Core Channel
        let railZ: Float = -0.68
        for side: Float in [-1, 1] {
            b.box(r, SIMD3<Float>(0.046 * side, 0.062, railZ), SIMD3<Float>(0.024, 0.032, 0.80), .brushedSteel)
            b.box(r, SIMD3<Float>(0.046 * side, 0.028, railZ), SIMD3<Float>(0.024, 0.024, 0.78), .gunmetal)
        }
        b.cylinder(r, SIMD3<Float>(0, 0.046, railZ), radius: 0.010, length: 0.78, glow)

        // 8 Sequential Toroidal Accelerator Coils pulsing down the barrel + Slotted Muzzle Compensator
        for i in 0..<8 {
            let z = -0.32 - Float(i) * 0.095
            let pulse = 0.5 + 0.5 * sin(time * 10.5 - Float(i) * 0.75)
            let coilGlow = PartMaterial.glow(glow.color, intensity: 0.95 + pulse * 1.15)
            b.torus(r, SIMD3<Float>(0, 0.046, z), outerRadius: 0.068, thicknessScale: 0.55, .gunmetal)
            b.torus(r, SIMD3<Float>(0, 0.046, z - 0.016), outerRadius: 0.072, thicknessScale: 0.38, coilGlow)
        }
        // Heavy anti-materiel arrowhead muzzle brake
        b.box(r, SIMD3<Float>(0, 0.046, -1.10), SIMD3<Float>(0.135, 0.075, 0.085), .gunmetal)
        b.tube(r, SIMD3<Float>(0, 0.046, -1.12), radius: 0.028, length: 0.095, .brushedSteel)

        // Folded Front Tactical Bipod Legs under handguard
        for side: Float in [-1, 1] {
            b.strut(r, from: SIMD3<Float>(0.04 * side, -0.01, -0.44), to: SIMD3<Float>(0.075 * side, -0.045, -0.72), radius: 0.012, .gunmetal)
            b.cylinder(r, SIMD3<Float>(0.075 * side, -0.045, -0.73), radius: 0.018, length: 0.025, .darkJoint)
        }

        // Variable-Zoom Dual-Bell Illuminated Sniper Scope on Cantilever Mount
        b.torus(r, SIMD3<Float>(0, 0.178, 0.02), outerRadius: 0.036, thicknessScale: 0.65, .gunmetal)
        b.torus(r, SIMD3<Float>(0, 0.178, -0.14), outerRadius: 0.036, thicknessScale: 0.65, .gunmetal)
        b.cylinder(r, SIMD3<Float>(0, 0.178, -0.06), radius: 0.028, length: 0.30, .gunmetal)
        // Ocular & Objective flared bells + lenses + windage/elevation turrets
        b.tube(r, SIMD3<Float>(0, 0.178, 0.11), radius: 0.038, length: 0.08, .gunmetal)
        b.sphere(r, SIMD3<Float>(0, 0.178, 0.145), SIMD3<Float>(0.056, 0.056, 0.010), .holoGlass(glow.color, alpha: 0.42))
        b.cone(r, SIMD3<Float>(0, 0.178, -0.25), radius: 0.048, length: 0.11, .gunmetal)
        b.tube(r, SIMD3<Float>(0, 0.178, -0.31), radius: 0.048, length: 0.05, .darkJoint)
        b.sphere(r, SIMD3<Float>(0, 0.178, -0.325), SIMD3<Float>(0.072, 0.072, 0.010), glow)
        b.cylinder(r, SIMD3<Float>(0, 0.218, -0.06), radius: 0.016, length: 0.026, .brushedSteel, rotation: Math3D.rotationX(quarterTurn))
        b.cylinder(r, SIMD3<Float>(0.038, 0.178, -0.06), radius: 0.016, length: 0.026, .brushedSteel, rotation: Math3D.rotationY(quarterTurn))

        if includeHands {
            appendRunnerHands(r, &b, rightGrip: SIMD3<Float>(0, -0.02, 0.02), leftSupport: SIMD3<Float>(0, -0.055, -0.22))
        }
    }

    // MARK: - 4 Distinct Multi-Shape Opponent Archetypes (`BotChassis`)

    static func appendRobot(_ bot: ArenaBot, time: Float, into b: inout ModelBatch) {
        // Hover Seraph projects a glowing anti-gravity ring onto the deck below
        if bot.chassis == .hoverSeraph {
            let shadowPos = SIMD3<Float>(bot.kinematic.position.x, bot.kinematic.position.y + 0.02, bot.kinematic.position.z)
            let rad = bot.chassis.hitRadius * 1.15
            b.torus(
                Math3D.translation(shadowPos),
                .zero,
                outerRadius: rad,
                thicknessScale: 0.45,
                .glow(bot.teamColor, intensity: 1.45, alpha: 0.72),
                rotation: Math3D.rotationX(quarterTurn)
            )
        }

        b.flashOverride = bot.hitFlashTimer > 0 ? SIMD3<Float>(1, 1, 1) : nil
        switch bot.chassis {
        case .strikerBiped:
            appendStrikerBiped(bot, time: time, into: &b)
        case .heavyJuggernaut:
            appendHeavyJuggernaut(bot, time: time, into: &b)
        case .arachnidStrider:
            appendArachnidStrider(bot, time: time, into: &b)
        case .hoverSeraph:
            appendHoverSeraph(bot, time: time, into: &b)
        }
        b.flashOverride = nil
    }

    // CHASSIS 1: STRIKER BIPED (`VEX // STRIKER`) — Sleek Reverse-Jointed Agile Pursuit Android
    private static func appendStrikerBiped(_ bot: ArenaBot, time: Float, into b: inout ModelBatch) {
        let root = Math3D.translation(bot.kinematic.position) * Math3D.rotationY(bot.yaw)
        let team = bot.teamColor
        let armor = PartMaterial.armor(team)
        let visor = PartMaterial.glow(team, intensity: 1.75)

        let vel = bot.kinematic.velocity
        let speed = simd_length(SIMD2<Float>(vel.x, vel.z))
        let grounded = bot.kinematic.isOnFloor
        let stride = grounded ? min(speed / 8.5, 1.0) * 0.68 : 0.0
        let cycle = time * (6.4 + speed * 0.48) + bot.strafePhase
        let bob = grounded ? abs(sin(cycle)) * 0.042 * min(speed / 6.0, 1.0) : 0.0
        let tuck: Float = grounded ? 0.0 : 0.42

        // Digitigrade reverse-joint sprint legs + chrome Achilles hydraulic pistons
        for side in [-1, 1] {
            let s = Float(side)
            let phase = cycle + (side < 0 ? 0 : .pi)
            let swing = sin(phase) * stride + tuck * 0.55
            let hip = root * Math3D.translation(SIMD3<Float>(0.15 * s, 0.94 + bob, 0)) * Math3D.rotationX(swing)
            b.sphere(hip, .zero, SIMD3<Float>(0.15, 0.15, 0.15), .darkJoint)
            b.box(hip, SIMD3<Float>(0, -0.18, -0.03), SIMD3<Float>(0.15, 0.36, 0.18), .whiteShell, rotation: Math3D.rotationX(-0.22))
            b.box(hip, SIMD3<Float>(0.02 * s, -0.16, -0.09), SIMD3<Float>(0.12, 0.28, 0.06), armor, rotation: Math3D.rotationX(-0.22))

            let kneeBend = max(0.0, -sin(phase)) * stride * 1.15 + tuck
            let knee = hip * Math3D.translation(SIMD3<Float>(0, -0.36, -0.08)) * Math3D.rotationX(-kneeBend)
            b.sphere(knee, .zero, SIMD3<Float>(0.13, 0.13, 0.13), .gunmetal)
            // Reverse-angled hock / carbon-blade lower shin + hydraulic strut
            b.box(knee, SIMD3<Float>(0, -0.19, 0.07), SIMD3<Float>(0.12, 0.38, 0.13), armor, rotation: Math3D.rotationX(0.35))
            b.strut(knee, from: SIMD3<Float>(0, 0.02, 0.06), to: SIMD3<Float>(0, -0.34, 0.14), radius: 0.022, .chrome)
            // Split claw sprint foot
            b.wedge(knee, SIMD3<Float>(0, -0.45, 0.02), SIMD3<Float>(0.28, 0.08, 0.16), .gunmetal, rotation: Math3D.rotationY(quarterTurn))
            b.box(knee, SIMD3<Float>(0, -0.45, 0.16), SIMD3<Float>(0.10, 0.06, 0.10), .darkJoint)
        }

        let torso = root * Math3D.translation(SIMD3<Float>(0, 0.98 + bob, 0)) * Math3D.rotationX(-min(speed / 16.0, 0.22)) * Math3D.translation(SIMD3<Float>(0, -0.98, 0))
        // V-tapered athletic pelvis & glowing segmented spine
        b.box(torso, SIMD3<Float>(0, 0.96, 0), SIMD3<Float>(0.38, 0.15, 0.24), .gunmetal)
        for seg in 0..<3 {
            let sy = 1.07 + Float(seg) * 0.075
            b.cylinder(torso, SIMD3<Float>(0, sy, 0.02), radius: 0.10, length: 0.055, .darkJoint, rotation: Math3D.rotationX(quarterTurn))
            b.torus(torso, SIMD3<Float>(0, sy, 0.02), outerRadius: 0.108, thicknessScale: 0.35, visor, rotation: Math3D.rotationX(quarterTurn))
        }

        // Sculpted Mirror's Edge chest carapace + circular arc-reactor ring
        b.box(torso, SIMD3<Float>(0, 1.38, -0.01), SIMD3<Float>(0.54, 0.36, 0.32), .whiteShell)
        b.wedge(torso, SIMD3<Float>(-0.18, 1.38, -0.14), SIMD3<Float>(0.22, 0.30, 0.12), armor, rotation: Math3D.rotationY(-0.35))
        b.wedge(torso, SIMD3<Float>( 0.18, 1.38, -0.14), SIMD3<Float>(0.22, 0.30, 0.12), armor, rotation: Math3D.rotationY(.pi + 0.35))
        b.torus(torso, SIMD3<Float>(0, 1.39, -0.175), outerRadius: 0.075, thicknessScale: 0.45, visor)
        b.octahedron(torso, SIMD3<Float>(0, 1.39, -0.18), SIMD3<Float>(0.07, 0.07, 0.04), visor)

        // Swept-back twin dorsal aero-fins + jet nozzles
        for s: Float in [-1, 1] {
            b.box(torso, SIMD3<Float>(0.14 * s, 1.44, 0.24), SIMD3<Float>(0.04, 0.38, 0.24), armor, rotation: Math3D.rotationX(-0.32) * Math3D.rotationZ(-0.22 * s))
            b.tube(torso, SIMD3<Float>(0.11 * s, 1.20, 0.22), radius: 0.052, length: 0.14, .gunmetal, rotation: Math3D.rotationX(quarterTurn - 0.3))
            b.cone(torso, SIMD3<Float>(0.11 * s, 1.11, 0.25), radius: 0.042, length: 0.10, visor, rotation: Math3D.rotationX(-quarterTurn - 0.3))
        }

        // Streamlined spherical aero-helmet + curved wrap-around visor + swept sensor ears
        let head = torso * Math3D.translation(SIMD3<Float>(0, 1.68, -0.02)) * Math3D.rotationX(simd_clamp(bot.pitch, -0.6, 0.6))
        b.sphere(head, SIMD3<Float>(0, 0.04, 0.02), SIMD3<Float>(0.27, 0.25, 0.33), .whiteShell)
        b.sphere(head, SIMD3<Float>(0, 0.035, -0.04), SIMD3<Float>(0.255, 0.13, 0.28), visor)
        for s: Float in [-1, 1] {
            b.box(head, SIMD3<Float>(0.145 * s, 0.09, 0.09), SIMD3<Float>(0.025, 0.08, 0.22), armor, rotation: Math3D.rotationX(0.38))
        }

        // Articulated dual arms aiming weapon
        let aim = Math3D.rotationX(simd_clamp(bot.pitch, -0.7, 0.7))
        for side in [-1, 1] {
            let s = Float(side)
            let shoulder = torso * Math3D.translation(SIMD3<Float>(0.34 * s, 1.48, 0))
            b.wedge(shoulder, SIMD3<Float>(0.04 * s, 0.05, 0), SIMD3<Float>(0.22, 0.13, 0.26), armor, rotation: side < 0 ? Math3D.rotationY(.pi) : matrix_identity_float4x4)
            let upper = shoulder * aim * Math3D.rotationX(0.36) * Math3D.rotationZ(0.12 * s)
            b.strut(upper, from: .zero, to: SIMD3<Float>(0, -0.32, 0), radius: 0.052, .gunmetal)
            let elbow = upper * Math3D.translation(SIMD3<Float>(0, -0.34, 0)) * Math3D.rotationX(1.18) * Math3D.rotationZ(-0.42 * s)
            b.sphere(elbow, .zero, SIMD3<Float>(0.10, 0.10, 0.10), .darkJoint)
            b.box(elbow, SIMD3<Float>(0, -0.15, 0), SIMD3<Float>(0.11, 0.26, 0.12), .whiteShell)
        }

        let weaponRoot = torso * Math3D.translation(SIMD3<Float>(0.10, 1.24, -0.40)) * aim * Math3D.scale(SIMD3<Float>(repeating: 0.88))
        appendWeapon(bot.weapon, root: weaponRoot, into: &b, time: time, fireKick: bot.fireKickTimer)
    }

    // CHASSIS 2: HEAVY JUGGERNAUT (`KRON // TITAN`) — Hulking Broad-Shouldered Siege Mech with Missile Pauldrons
    private static func appendHeavyJuggernaut(_ bot: ArenaBot, time: Float, into b: inout ModelBatch) {
        let root = Math3D.translation(bot.kinematic.position) * Math3D.rotationY(bot.yaw)
        let team = bot.teamColor
        let armor = PartMaterial.armor(team)
        let visor = PartMaterial.glow(team, intensity: 1.85)
        let hazard = PartMaterial.hardware(SublevelPalette.amberGold, roughness: 0.25, metallic: 0.4, emissive: 0.15)

        let vel = bot.kinematic.velocity
        let speed = simd_length(SIMD2<Float>(vel.x, vel.z))
        let grounded = bot.kinematic.isOnFloor
        let stride = grounded ? min(speed / 9.0, 1.0) * 0.46 : 0.0
        let cycle = time * (4.8 + speed * 0.35) + bot.strafePhase
        let stompBob = grounded ? abs(sin(cycle)) * 0.055 * min(speed / 5.0, 1.0) : 0.0

        // Massive wide-stance hydraulic siege legs + armored sabatons
        for side in [-1, 1] {
            let s = Float(side)
            let phase = cycle + (side < 0 ? 0 : .pi)
            let swing = sin(phase) * stride
            let hip = root * Math3D.translation(SIMD3<Float>(0.26 * s, 1.02 + stompBob, 0)) * Math3D.rotationX(swing)
            b.cylinder(hip, .zero, radius: 0.12, length: 0.26, .gunmetal, rotation: Math3D.rotationY(quarterTurn))
            b.box(hip, SIMD3<Float>(0, -0.22, 0), SIMD3<Float>(0.28, 0.42, 0.30), .gunmetal)
            b.box(hip, SIMD3<Float>(0.03 * s, -0.20, -0.14), SIMD3<Float>(0.24, 0.34, 0.08), armor)

            let kneeBend = max(0.0, -sin(phase)) * stride * 0.95 + (grounded ? 0.0 : 0.30)
            let knee = hip * Math3D.translation(SIMD3<Float>(0, -0.45, 0)) * Math3D.rotationX(-kneeBend)
            b.box(knee, SIMD3<Float>(0, 0.02, -0.15), SIMD3<Float>(0.26, 0.22, 0.10), hazard)
            b.box(knee, SIMD3<Float>(0, -0.26, 0), SIMD3<Float>(0.32, 0.46, 0.34), .whiteShell)
            b.box(knee, SIMD3<Float>(0.04 * s, -0.26, -0.02), SIMD3<Float>(0.30, 0.38, 0.28), armor)
            // Dual external chrome shock pistons on outer shins
            b.cylinder(knee, SIMD3<Float>(0.18 * s, -0.22, 0.06), radius: 0.038, length: 0.36, .chrome, rotation: Math3D.rotationX(quarterTurn))
            // Heavy 3-toed siege sabaton
            b.box(knee, SIMD3<Float>(0, -0.51, -0.06), SIMD3<Float>(0.34, 0.12, 0.46), .gunmetal)
            b.wedge(knee, SIMD3<Float>(0, -0.50, -0.30), SIMD3<Float>(0.18, 0.10, 0.30), .brushedSteel, rotation: Math3D.rotationY(quarterTurn))
        }

        // Barrel-chested siege hull + spinning chest turbine + recessed cyclops turret head
        let torso = root * Math3D.translation(SIMD3<Float>(0, stompBob, 0))
        b.box(torso, SIMD3<Float>(0, 1.06, 0), SIMD3<Float>(0.68, 0.22, 0.42), .gunmetal)
        b.cylinder(torso, SIMD3<Float>(0, 1.22, 0), radius: 0.24, length: 0.20, .darkJoint, rotation: Math3D.rotationX(quarterTurn))
        b.box(torso, SIMD3<Float>(0, 1.54, -0.02), SIMD3<Float>(0.92, 0.56, 0.56), .whiteShell)
        b.box(torso, SIMD3<Float>(0, 1.56, -0.28), SIMD3<Float>(0.76, 0.44, 0.12), armor)
        // Chest reactor turbine
        b.tube(torso, SIMD3<Float>(0, 1.52, -0.33), radius: 0.14, length: 0.08, .gunmetal)
        b.torus(torso, SIMD3<Float>(0, 1.52, -0.35), outerRadius: 0.12, thicknessScale: 0.5, visor, rotation: Math3D.rotationZ(time * 5.0))
        b.sphere(torso, SIMD3<Float>(0, 1.52, -0.34), SIMD3<Float>(0.12, 0.12, 0.08), visor)

        // Twin Dorsal Reactor Smokestacks & Cooling Pack
        b.box(torso, SIMD3<Float>(0, 1.56, 0.34), SIMD3<Float>(0.66, 0.50, 0.26), .gunmetal)
        for s: Float in [-1, 1] {
            b.tube(torso, SIMD3<Float>(0.22 * s, 1.94, 0.36), radius: 0.075, length: 0.42, .brushedSteel, rotation: Math3D.rotationX(quarterTurn - 0.18))
            b.torus(torso, SIMD3<Float>(0.22 * s, 2.13, 0.40), outerRadius: 0.082, thicknessScale: 0.5, visor, rotation: Math3D.rotationX(quarterTurn - 0.18))
        }

        // Recessed Armored Dome Head + Cyclops Laser Eye
        let head = torso * Math3D.translation(SIMD3<Float>(0, 1.90, -0.08)) * Math3D.rotationX(simd_clamp(bot.pitch, -0.45, 0.45))
        b.sphere(head, SIMD3<Float>(0, 0.02, 0), SIMD3<Float>(0.42, 0.32, 0.42), .gunmetal)
        b.box(head, SIMD3<Float>(0, 0.04, -0.18), SIMD3<Float>(0.32, 0.10, 0.10), .darkJoint)
        b.sphere(head, SIMD3<Float>(0, 0.04, -0.22), SIMD3<Float>(0.11, 0.11, 0.08), visor)

        // Huge Sloped Shoulder Pauldrons + Micro-Missile Pods + Gorilla Hydraulic Arms
        let aim = Math3D.rotationX(simd_clamp(bot.pitch, -0.6, 0.6))
        for side in [-1, 1] {
            let s = Float(side)
            let sh = torso * Math3D.translation(SIMD3<Float>(0.58 * s, 1.72, 0))
            b.box(sh, SIMD3<Float>(0.05 * s, 0.08, 0), SIMD3<Float>(0.34, 0.30, 0.46), armor, rotation: Math3D.rotationZ(-0.22 * s))
            b.box(sh, SIMD3<Float>(0.04 * s, 0.25, -0.02), SIMD3<Float>(0.22, 0.14, 0.24), .gunmetal)
            for m in 0..<3 {
                b.cylinder(sh, SIMD3<Float>((-0.02 + Float(m) * 0.06) * s, 0.25, -0.145), radius: 0.022, length: 0.02, hazard)
            }
            let arm = sh * aim * Math3D.rotationX(0.32)
            b.box(arm, SIMD3<Float>(0.02 * s, -0.24, 0), SIMD3<Float>(0.20, 0.36, 0.22), .gunmetal)
            let forearm = arm * Math3D.translation(SIMD3<Float>(0, -0.44, 0)) * Math3D.rotationX(1.05) * Math3D.rotationZ(-0.34 * s)
            b.box(forearm, SIMD3<Float>(0, -0.20, 0), SIMD3<Float>(0.24, 0.38, 0.24), .whiteShell)
            b.torus(forearm, SIMD3<Float>(0, -0.34, 0), outerRadius: 0.13, thicknessScale: 0.45, armor, rotation: Math3D.rotationX(quarterTurn))
        }

        let weaponRoot = torso * Math3D.translation(SIMD3<Float>(0.18, 1.38, -0.52)) * aim * Math3D.scale(SIMD3<Float>(repeating: 1.08))
        appendWeapon(bot.weapon, root: weaponRoot, into: &b, time: time, fireKick: bot.fireKickTimer)
    }

    // CHASSIS 3: ARACHNID STRIDER (`NYX // STRIDER`) — 4-Legged Scuttling Spider/Mantis Turret Construct
    private static func appendArachnidStrider(_ bot: ArenaBot, time: Float, into b: inout ModelBatch) {
        let base = bot.kinematic.position
        let vel = bot.kinematic.velocity
        let speed = simd_length(SIMD2<Float>(vel.x, vel.z))
        let scuttleCycle = time * (8.5 + speed * 0.65) + bot.strafePhase
        let bodyBob = bot.kinematic.isOnFloor ? sin(scuttleCycle * 2.0) * 0.035 : 0.0

        let root = Math3D.translation(base + SIMD3<Float>(0, 0.72 + bodyBob, 0)) * Math3D.rotationY(bot.yaw)
        let team = bot.teamColor
        let armor = PartMaterial.armor(team)
        let visor = PartMaterial.glow(team, intensity: 1.8)

        // Low-slung faceted insectoid cephalothorax + rear glowing abdomen reactor
        b.octahedron(root, SIMD3<Float>(0, 0.04, -0.04), SIMD3<Float>(0.76, 0.42, 0.88), .whiteShell)
        b.box(root, SIMD3<Float>(0, 0.14, -0.02), SIMD3<Float>(0.58, 0.18, 0.68), armor)
        b.sphere(root, SIMD3<Float>(0, 0.08, 0.52), SIMD3<Float>(0.48, 0.36, 0.58), .gunmetal, rotation: Math3D.rotationX(0.22))
        b.octahedron(root, SIMD3<Float>(0, 0.10, 0.78), SIMD3<Float>(0.24, 0.22, 0.32), visor, rotation: Math3D.rotationX(0.22))
        b.torus(root, SIMD3<Float>(0, -0.10, 0), outerRadius: 0.34, thicknessScale: 0.45, .gunmetal, rotation: Math3D.rotationX(quarterTurn))

        // Compound 5-eye optical sensor cluster + front pincer mandibles
        let head = root * Math3D.translation(SIMD3<Float>(0, 0.06, -0.44)) * Math3D.rotationX(simd_clamp(bot.pitch * 0.5, -0.4, 0.4))
        b.box(head, .zero, SIMD3<Float>(0.34, 0.20, 0.24), .gunmetal)
        let eyeOffsets: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0.02, -0.125),
            SIMD3<Float>(-0.09, 0.04, -0.115), SIMD3<Float>(0.09, 0.04, -0.115),
            SIMD3<Float>(-0.14, -0.02, -0.10), SIMD3<Float>(0.14, -0.02, -0.10)
        ]
        for (idx, eo) in eyeOffsets.enumerated() {
            let es: Float = idx == 0 ? 0.085 : 0.055
            b.sphere(head, eo, SIMD3<Float>(es, es, es * 0.6), visor)
        }
        for s: Float in [-1, 1] {
            b.cone(head, SIMD3<Float>(0.14 * s, -0.06, -0.20), radius: 0.038, length: 0.22, .brushedSteel, rotation: Math3D.rotationY(.pi - 0.28 * s))
        }

        // 4 Articulated Multi-Jointed Spider Legs (Tetrapod Scuttle Gait!)
        let legMounts: [(x: Float, z: Float, yaw: Float, phaseOff: Float)] = [
            (-0.28, -0.22,  0.68, 0.0),
            ( 0.28, -0.22, -0.68, .pi),
            (-0.30,  0.22,  2.35, .pi),
            ( 0.30,  0.22, -2.35, 0.0)
        ]
        let stepAmp = bot.kinematic.isOnFloor ? min(speed / 8.0, 1.0) * 0.34 + 0.06 : 0.22
        for leg in legMounts {
            let p = scuttleCycle + leg.phaseOff
            let swingYaw = sin(p) * stepAmp
            let lift = max(0.0, cos(p)) * stepAmp * 0.55

            let coxa = root * Math3D.translation(SIMD3<Float>(leg.x, -0.04, leg.z)) * Math3D.rotationY(leg.yaw + swingYaw)
            b.sphere(coxa, .zero, SIMD3<Float>(0.14, 0.14, 0.14), .darkJoint)

            // Upward-arching femur + chrome hydraulic cylinder
            let femurEnd = SIMD3<Float>(0, 0.30 + lift, -0.46)
            b.beamStrut(coxa, from: .zero, to: femurEnd, width: 0.10, height: 0.12, armor)
            b.strut(coxa, from: SIMD3<Float>(0, -0.06, -0.04), to: femurEnd + SIMD3<Float>(0, -0.06, 0.06), radius: 0.022, .chrome)
            b.sphere(coxa, femurEnd, SIMD3<Float>(0.12, 0.12, 0.12), .gunmetal)

            // Sharp downward-stabbing tibia + glowing ankle ring + pointed claw tip
            let footTip = SIMD3<Float>(0, -0.68 + lift * 0.7, -0.78)
            b.strut(coxa, from: femurEnd, to: footTip, radius: 0.048, .whiteShell)
            b.cone(coxa, footTip + SIMD3<Float>(0, 0.06, 0.02), radius: 0.055, length: 0.22, .gunmetal, rotation: Math3D.rotationX(quarterTurn + 0.35))
            b.torus(coxa, femurEnd * 0.4 + footTip * 0.6, outerRadius: 0.058, thicknessScale: 0.5, visor, rotation: Math3D.rotationX(quarterTurn))
        }

        // Dorsal 360° Gimbal Weapon Turret on top of carapace
        let aim = Math3D.rotationX(simd_clamp(bot.pitch, -0.7, 0.7))
        let turret = root * Math3D.translation(SIMD3<Float>(0, 0.30, -0.04))
        b.cylinder(turret, .zero, radius: 0.18, length: 0.12, .gunmetal, rotation: Math3D.rotationX(quarterTurn))
        b.torus(turret, SIMD3<Float>(0, 0.04, 0), outerRadius: 0.19, thicknessScale: 0.4, visor, rotation: Math3D.rotationX(quarterTurn))
        let weaponRoot = turret * Math3D.translation(SIMD3<Float>(0, 0.16, 0.08)) * aim * Math3D.scale(SIMD3<Float>(repeating: 0.96))
        appendWeapon(bot.weapon, root: weaponRoot, into: &b, time: time, fireKick: bot.fireKickTimer)
    }

    // CHASSIS 4: HOVER SERAPH (`SOL // SERAPH`) — Airborne Polyhedral Sentinel with Counter-Rotating Gyro Halos
    private static func appendHoverSeraph(_ bot: ArenaBot, time: Float, into b: inout ModelBatch) {
        let hoverBob = sin(time * 3.4 + bot.strafePhase) * 0.11
        let vel = bot.kinematic.velocity
        let bankZ = simd_clamp(-vel.x * 0.02, -0.22, 0.22)
        let tiltX = simd_clamp(vel.z * 0.02, -0.22, 0.22)

        let centerPos = bot.kinematic.position + SIMD3<Float>(0, 1.18 + hoverBob, 0)
        let root = Math3D.translation(centerPos) * Math3D.rotationY(bot.yaw) * Math3D.rotationX(tiltX) * Math3D.rotationZ(bankZ)
        let team = bot.teamColor
        let armor = PartMaterial.armor(team)
        let visor = PartMaterial.glow(team, intensity: 1.9)

        // Central radiant octahedral star-core + glossy white geometric upper/lower obelisks
        let coreSpin = Math3D.rotationY(time * 2.4) * Math3D.rotationZ(time * 1.6)
        b.octahedron(root, .zero, SIMD3<Float>(0.36, 0.44, 0.36), visor, rotation: coreSpin)
        b.sphere(root, .zero, SIMD3<Float>(0.24, 0.24, 0.24), .glow(SIMD3<Float>(1, 1, 1), intensity: 2.0))

        // Upper monolithic sentinel head crest + vertical laser eye-slit
        let head = root * Math3D.translation(SIMD3<Float>(0, 0.48, 0)) * Math3D.rotationX(simd_clamp(bot.pitch * 0.5, -0.45, 0.45))
        b.cone(head, SIMD3<Float>(0, 0.14, 0), radius: 0.20, length: 0.46, .gunmetal, rotation: Math3D.rotationX(-quarterTurn))
        b.box(head, SIMD3<Float>(0, 0.10, -0.14), SIMD3<Float>(0.055, 0.28, 0.06), visor)
        b.torus(head, SIMD3<Float>(0, 0.40, 0), outerRadius: 0.14, thicknessScale: 0.8, visor, rotation: Math3D.rotationX(quarterTurn))

        // Lower thruster skirt + translucent downward ion jet plume!
        b.tube(root, SIMD3<Float>(0, -0.46, 0), radius: 0.20, length: 0.24, .gunmetal, rotation: Math3D.rotationX(quarterTurn))
        b.torus(root, SIMD3<Float>(0, -0.56, 0), outerRadius: 0.22, thicknessScale: 0.8, visor, rotation: Math3D.rotationX(quarterTurn))
        let plumeLen: Float = 0.48 + 0.12 * sin(time * 22.0)
        b.cone(root, SIMD3<Float>(0, -0.56 - plumeLen * 0.5, 0), radius: 0.16, length: plumeLen, .energyField(team, intensity: 2.0, alpha: 0.68), rotation: Math3D.rotationX(quarterTurn))

        // 3 Nested Counter-Rotating Gyroscopic Halo Rings!
        let ring1Rot = Math3D.rotationY(time * 1.9) * Math3D.rotationX(0.55)
        let ring2Rot = Math3D.rotationZ(-time * 2.3) * Math3D.rotationY(0.85)
        let ring3Rot = Math3D.rotationX(quarterTurn + sin(time * 1.8) * 0.22)
        b.torus(root, .zero, outerRadius: 0.46, thicknessScale: 0.75, .gunmetal, rotation: ring1Rot)
        b.torus(root, .zero, outerRadius: 0.56, thicknessScale: 0.70, armor, rotation: ring2Rot)
        b.torus(root, SIMD3<Float>(0, -0.08, 0), outerRadius: 0.66, thicknessScale: 0.65, visor, rotation: ring3Rot)

        // 4 Levitating X-Wing Shield Blades flanking the Seraph
        let flare = 0.04 * sin(time * 4.2)
        for sx: Float in [-1, 1] {
            for sy: Float in [-1, 1] {
                let wingPos = SIMD3<Float>((0.56 + flare) * sx, 0.12 + 0.34 * sy, 0.08)
                let wingRot = Math3D.rotationZ(-0.55 * sx * sy) * Math3D.rotationY(0.25 * sx)
                b.box(root, wingPos, SIMD3<Float>(0.10, 0.46, 0.18), .gunmetal, rotation: wingRot)
                b.box(root, wingPos + SIMD3<Float>(0.035 * sx, 0, -0.07), SIMD3<Float>(0.045, 0.40, 0.05), armor, rotation: wingRot)
            }
        }

        // Side-mounted precision Sub-Rail gimbal arm
        let aim = Math3D.rotationX(simd_clamp(bot.pitch, -0.75, 0.75))
        let weaponRoot = root * Math3D.translation(SIMD3<Float>(0.38, -0.02, -0.24)) * aim * Math3D.scale(SIMD3<Float>(repeating: 0.88))
        b.sphere(root, SIMD3<Float>(0.34, -0.02, -0.04), SIMD3<Float>(0.16, 0.16, 0.16), .gunmetal)
        appendWeapon(bot.weapon, root: weaponRoot, into: &b, time: time, fireKick: bot.fireKickTimer)
    }

    // MARK: - Detailed High-Polygon 3D Projectiles

    static func appendProjectile(_ proj: Projectile, time: Float, into b: inout ModelBatch) {
        let pos = proj.position
        let dir = simd_length_squared(proj.velocity) > 1e-4 ? simd_normalize(proj.velocity) : SIMD3<Float>(0, 0, -1)

        switch proj.kind {
        case .vectorRocket:
            let root = Math3D.translation(pos) * orientation(forward: dir) * Math3D.rotationZ(time * 9.0 + proj.spiralPhase)
            // Composite missile body + armor band + tapered nosecone + seeker lens + 4 swept fins + hollow nozzle + jet plume
            b.cylinder(root, .zero, radius: 0.072, length: 0.44, .whiteShell)
            b.torus(root, SIMD3<Float>(0, 0, 0.10), outerRadius: 0.078, thicknessScale: 0.55, .hardware(proj.color, roughness: 0.25, metallic: 0.4))
            b.cone(root, SIMD3<Float>(0, 0, 0.31), radius: 0.072, length: 0.20, .glow(proj.color, intensity: 1.7))
            b.tube(root, SIMD3<Float>(0, 0, -0.25), radius: 0.062, length: 0.08, .gunmetal)
            for i in 0..<4 {
                let fin = Math3D.rotationZ(Float(i) * quarterTurn)
                b.wedge(root * fin, SIMD3<Float>(0, 0.105, -0.16), SIMD3<Float>(0.14, 0.09, 0.016), .brushedSteel, rotation: Math3D.rotationY(quarterTurn))
            }
            b.cone(root, SIMD3<Float>(0, 0, -0.42), radius: 0.088, length: 0.30, .energyField(proj.color, intensity: 2.0, alpha: 0.82), rotation: Math3D.rotationY(.pi))

        case .shockOrb:
            let root = Math3D.translation(pos)
            let glow = PartMaterial.glow(proj.color, intensity: 2.0)
            // Blazing inner core + 2 counter-spinning plasma containment rings + translucent outer combo shell
            b.octahedron(root, .zero, SIMD3<Float>(0.42, 0.42, 0.42), .glow(SIMD3<Float>(1, 1, 1), intensity: 2.2), rotation: Math3D.rotationY(time * 5.0) * Math3D.rotationX(time * 3.5))
            b.torus(root, .zero, outerRadius: 0.48, thicknessScale: 0.32, glow, rotation: Math3D.rotationX(time * 6.5) * Math3D.rotationY(time * 4.0))
            b.torus(root, .zero, outerRadius: 0.54, thicknessScale: 0.28, glow, rotation: Math3D.rotationZ(-time * 5.5) * Math3D.rotationX(0.9))
            b.sphere(root, .zero, SIMD3<Float>(repeating: 1.18), .energyField(proj.color, intensity: 1.75, alpha: 0.78))

        case .flakGrenade:
            let spin = Math3D.rotationX(time * 9.5) * Math3D.rotationZ(time * 6.2)
            let root = Math3D.translation(pos) * spin
            let blink: Float = sin(time * 24.0) > 0 ? 2.2 : 1.1
            b.cylinder(root, .zero, radius: 0.11, length: 0.26, .gunmetal)
            b.torus(root, SIMD3<Float>(0, 0, 0.06), outerRadius: 0.12, thicknessScale: 0.55, .glow(proj.color, intensity: blink))
            b.torus(root, SIMD3<Float>(0, 0, -0.06), outerRadius: 0.12, thicknessScale: 0.55, .glow(proj.color, intensity: blink))
            b.sphere(root, SIMD3<Float>(0, 0, 0.13), SIMD3<Float>(0.20, 0.20, 0.12), .brushedSteel)

        case .shardPellet:
            let root = Math3D.translation(pos) * orientation(forward: dir) * Math3D.rotationZ(time * 14.0 + Float(proj.id))
            b.octahedron(root, .zero, SIMD3<Float>(0.14, 0.14, 0.34), .glow(proj.color, intensity: 2.1))
        }
    }
}

