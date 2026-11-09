import Foundation
import simd

/// Material description for a single procedural model part.
/// Shader modes: 1 = team-color silhouette armor, 3 = unlit emissive glow, 4 = lit robot hardware.
struct PartMaterial {
    var color: SIMD3<Float>
    var roughness: Float
    var metallic: Float
    var emissive: Float
    var mode: Float
    var alpha: Float = 1.0

    static func hardware(_ color: SIMD3<Float>, roughness: Float = 0.38, metallic: Float = 0.6, emissive: Float = 0.0) -> PartMaterial {
        PartMaterial(color: color, roughness: roughness, metallic: metallic, emissive: emissive, mode: 4.0)
    }

    static func armor(_ color: SIMD3<Float>) -> PartMaterial {
        PartMaterial(color: color, roughness: 0.2, metallic: 0.1, emissive: 0.85, mode: 1.0)
    }

    static func glow(_ color: SIMD3<Float>, intensity: Float = 1.35) -> PartMaterial {
        PartMaterial(color: color, roughness: 0.05, metallic: 0.0, emissive: intensity, mode: 3.0)
    }

    static let gunmetal = PartMaterial.hardware(SIMD3<Float>(0.15, 0.16, 0.19), roughness: 0.42, metallic: 0.85)
    static let darkJoint = PartMaterial.hardware(SIMD3<Float>(0.08, 0.085, 0.10), roughness: 0.55, metallic: 0.7)
    static let whiteShell = PartMaterial.hardware(SublevelPalette.starkWhite, roughness: 0.3, metallic: 0.15)
}

/// Accumulates instanced parts for each primitive mesh (unit cube, unit Z-axis cylinder, unit sphere).
struct ModelBatch {
    var cubes: [GPUInstanceData] = []
    var cylinders: [GPUInstanceData] = []
    var spheres: [GPUInstanceData] = []

    /// When set, every non-glow part is rendered with this color (hit flash).
    var flashOverride: SIMD3<Float>? = nil

    mutating func box(_ parent: simd_float4x4, _ offset: SIMD3<Float>, _ size: SIMD3<Float>, _ mat: PartMaterial, rotation: simd_float4x4 = matrix_identity_float4x4) {
        cubes.append(makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat))
    }

    /// Cylinder aligned to the local Z axis; `radius` and `length` are in parent units.
    mutating func cylinder(_ parent: simd_float4x4, _ offset: SIMD3<Float>, radius: Float, length: Float, _ mat: PartMaterial, rotation: simd_float4x4 = matrix_identity_float4x4) {
        let size = SIMD3<Float>(radius * 2.0, radius * 2.0, length)
        cylinders.append(makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat))
    }

    mutating func sphere(_ parent: simd_float4x4, _ offset: SIMD3<Float>, _ size: SIMD3<Float>, _ mat: PartMaterial, rotation: simd_float4x4 = matrix_identity_float4x4) {
        spheres.append(makeInstance(parent * Math3D.translation(offset) * rotation * Math3D.scale(size), mat))
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
            // Large half-extents disable the axis-aligned crease shading for rotated parts.
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

    // MARK: - Weapons
    // Local space: origin at the pistol grip/hand, +Y up, -Z toward the muzzle. Roughly 1 unit ≈ 1 meter.

    static func appendWeapon(
        _ weapon: WeaponSlot,
        root: simd_float4x4,
        into batch: inout ModelBatch,
        time: Float,
        fireKick: Float = 0.0,
        rocketCharges: Int = 0,
        glowBoost: Float = 0.0
    ) {
        let accent = weapon.accentColor
        let glow = PartMaterial.glow(accent, intensity: 1.35 + glowBoost)
        let paint = PartMaterial.hardware(accent * 0.85, roughness: 0.3, metallic: 0.35, emissive: 0.12)

        switch weapon {
        case .kineticGauntlet:
            appendGauntlet(root, &batch, glow: glow, paint: paint, fireKick: fireKick, time: time)
        case .prismRifle:
            appendPrismRifle(root, &batch, glow: glow, paint: paint, time: time)
        case .shardCannon:
            appendShardCannon(root, &batch, glow: glow, paint: paint)
        case .vectorLauncher:
            appendVectorLauncher(root, &batch, glow: glow, paint: paint, rocketCharges: rocketCharges)
        case .subRail:
            appendSubRail(root, &batch, glow: glow, paint: paint, time: time)
        }
    }

    private static func appendGrip(_ root: simd_float4x4, _ b: inout ModelBatch, at offset: SIMD3<Float> = .zero) {
        b.box(root, offset + SIMD3<Float>(0, -0.09, 0.02), SIMD3<Float>(0.06, 0.17, 0.08), .darkJoint, rotation: Math3D.rotationX(-0.28))
        // Trigger guard
        b.box(root, offset + SIMD3<Float>(0, -0.04, -0.07), SIMD3<Float>(0.03, 0.015, 0.1), .gunmetal)
    }

    private static func appendGauntlet(_ r: simd_float4x4, _ b: inout ModelBatch, glow: PartMaterial, paint: PartMaterial, fireKick: Float, time: Float) {
        // Armored forearm sleeve wrapping the hand
        b.box(r, SIMD3<Float>(0, 0.0, 0.12), SIMD3<Float>(0.2, 0.18, 0.42), .whiteShell)
        b.box(r, SIMD3<Float>(0, 0.1, 0.1), SIMD3<Float>(0.16, 0.04, 0.36), paint)
        b.cylinder(r, SIMD3<Float>(-0.115, 0.0, 0.12), radius: 0.05, length: 0.3, .gunmetal)
        b.cylinder(r, SIMD3<Float>(-0.115, 0.0, 0.12), radius: 0.035, length: 0.32, glow)
        // Fist / knuckle block
        b.box(r, SIMD3<Float>(0, -0.01, -0.16), SIMD3<Float>(0.22, 0.17, 0.16), .gunmetal)
        for i in 0..<4 {
            let x = -0.075 + Float(i) * 0.05
            b.box(r, SIMD3<Float>(x, 0.035, -0.245), SIMD3<Float>(0.042, 0.06, 0.03), .darkJoint)
        }
        // Three hydraulic piston rams that punch forward on attack
        let extend = fireKick * 0.12
        for i in -1...1 {
            let x = Float(i) * 0.065
            b.cylinder(r, SIMD3<Float>(x, 0.115, -0.02), radius: 0.03, length: 0.3, .gunmetal)
            b.cylinder(r, SIMD3<Float>(x, 0.115, -0.2 - extend), radius: 0.018, length: 0.16, .whiteShell)
        }
        // Kinetic impact plate driven by the rams
        b.box(r, SIMD3<Float>(0, 0.05, -0.29 - extend), SIMD3<Float>(0.24, 0.2, 0.025), .gunmetal)
        b.box(r, SIMD3<Float>(0, 0.05, -0.305 - extend), SIMD3<Float>(0.18, 0.14, 0.012), glow)
    }

    private static func appendPrismRifle(_ r: simd_float4x4, _ b: inout ModelBatch, glow: PartMaterial, paint: PartMaterial, time: Float) {
        // Receiver and stock
        b.box(r, SIMD3<Float>(0, 0.04, -0.12), SIMD3<Float>(0.1, 0.13, 0.5), .whiteShell)
        b.box(r, SIMD3<Float>(0, 0.005, 0.26), SIMD3<Float>(0.07, 0.11, 0.28), .gunmetal, rotation: Math3D.rotationX(0.08))
        b.box(r, SIMD3<Float>(0, -0.01, 0.41), SIMD3<Float>(0.08, 0.15, 0.04), .darkJoint)
        appendGrip(r, &b)
        // Energy cell magazine
        b.box(r, SIMD3<Float>(0, -0.06, -0.2), SIMD3<Float>(0.06, 0.12, 0.08), .gunmetal, rotation: Math3D.rotationX(0.18))
        b.box(r, SIMD3<Float>(0.032, -0.06, -0.2), SIMD3<Float>(0.004, 0.08, 0.04), glow, rotation: Math3D.rotationX(0.18))
        // Barrel shroud with glowing side rails
        b.box(r, SIMD3<Float>(0, 0.05, -0.52), SIMD3<Float>(0.085, 0.085, 0.32), .gunmetal)
        b.box(r, SIMD3<Float>(0.045, 0.05, -0.5), SIMD3<Float>(0.01, 0.025, 0.28), glow)
        b.box(r, SIMD3<Float>(-0.045, 0.05, -0.5), SIMD3<Float>(0.01, 0.025, 0.28), glow)
        b.cylinder(r, SIMD3<Float>(0, 0.05, -0.74), radius: 0.028, length: 0.16, .darkJoint)
        // Prism emitter crystal held by two prongs at the muzzle
        b.box(r, SIMD3<Float>(0, 0.1, -0.8), SIMD3<Float>(0.014, 0.05, 0.08), .gunmetal)
        b.box(r, SIMD3<Float>(0, 0.0, -0.8), SIMD3<Float>(0.014, 0.05, 0.08), .gunmetal)
        let spin = Math3D.rotationZ(time * 2.4) * Math3D.rotationX(0.785) * Math3D.rotationY(0.785)
        b.box(r, SIMD3<Float>(0, 0.05, -0.84), SIMD3<Float>(0.055, 0.055, 0.055), glow, rotation: spin)
        // Scope
        b.box(r, SIMD3<Float>(0, 0.125, -0.12), SIMD3<Float>(0.03, 0.04, 0.08), .darkJoint)
        b.cylinder(r, SIMD3<Float>(0, 0.165, -0.12), radius: 0.03, length: 0.2, .gunmetal)
        b.cylinder(r, SIMD3<Float>(0, 0.165, -0.222), radius: 0.022, length: 0.006, glow)
    }

    private static func appendShardCannon(_ r: simd_float4x4, _ b: inout ModelBatch, glow: PartMaterial, paint: PartMaterial) {
        // Chunky receiver with amber heat vents
        b.box(r, SIMD3<Float>(0, 0.05, -0.1), SIMD3<Float>(0.18, 0.17, 0.42), .whiteShell)
        for i in 0..<3 {
            b.box(r, SIMD3<Float>(0, 0.14, -0.2 + Float(i) * 0.08), SIMD3<Float>(0.12, 0.012, 0.03), glow)
        }
        b.box(r, SIMD3<Float>(0, 0.02, 0.2), SIMD3<Float>(0.1, 0.12, 0.2), .gunmetal)
        appendGrip(r, &b)
        // Rotating shell drum (axis across the gun)
        b.cylinder(r, SIMD3<Float>(0, -0.06, -0.15), radius: 0.09, length: 0.16, paint, rotation: Math3D.rotationY(quarterTurn))
        b.cylinder(r, SIMD3<Float>(0, -0.06, -0.15), radius: 0.04, length: 0.17, .darkJoint, rotation: Math3D.rotationY(quarterTurn))
        // Barrel clamp and triple flak barrels
        b.box(r, SIMD3<Float>(0, 0.06, -0.36), SIMD3<Float>(0.2, 0.18, 0.06), .gunmetal)
        let barrelOffsets: [SIMD2<Float>] = [SIMD2(-0.05, 0.03), SIMD2(0.05, 0.03), SIMD2(0, 0.115)]
        for o in barrelOffsets {
            b.cylinder(r, SIMD3<Float>(o.x, o.y, -0.52), radius: 0.042, length: 0.34, .gunmetal)
            b.cylinder(r, SIMD3<Float>(o.x, o.y, -0.7), radius: 0.05, length: 0.04, .darkJoint)
            b.cylinder(r, SIMD3<Float>(o.x, o.y, -0.722), radius: 0.03, length: 0.006, glow)
        }
        b.box(r, SIMD3<Float>(0, 0.07, -0.62), SIMD3<Float>(0.15, 0.03, 0.04), .darkJoint)
    }

    private static func appendVectorLauncher(_ r: simd_float4x4, _ b: inout ModelBatch, glow: PartMaterial, paint: PartMaterial, rocketCharges: Int) {
        let tubeY: Float = 0.12
        // Main launch tube
        b.cylinder(r, SIMD3<Float>(0, tubeY, -0.12), radius: 0.1, length: 0.9, .whiteShell)
        // Reinforcement bands
        for z: Float in [-0.38, 0.0, 0.18] {
            b.cylinder(r, SIMD3<Float>(0, tubeY, z), radius: 0.108, length: 0.035, paint)
        }
        // Muzzle flare with a visible loaded warhead
        b.cylinder(r, SIMD3<Float>(0, tubeY, -0.59), radius: 0.125, length: 0.08, .gunmetal)
        b.cylinder(r, SIMD3<Float>(0, tubeY, -0.632), radius: 0.09, length: 0.006, .darkJoint)
        b.sphere(r, SIMD3<Float>(0, tubeY, -0.6), SIMD3<Float>(0.13, 0.13, 0.16), glow)
        // Rear exhaust venturi
        b.cylinder(r, SIMD3<Float>(0, tubeY, 0.36), radius: 0.12, length: 0.1, .gunmetal)
        b.cylinder(r, SIMD3<Float>(0, tubeY, 0.4), radius: 0.135, length: 0.03, .darkJoint)
        b.cylinder(r, SIMD3<Float>(0, tubeY, 0.418), radius: 0.07, length: 0.006, glow)
        // Pistol grip + forward grip under the tube
        b.box(r, SIMD3<Float>(0, 0.035, -0.02), SIMD3<Float>(0.08, 0.06, 0.2), .gunmetal)
        appendGrip(r, &b)
        b.box(r, SIMD3<Float>(0, -0.02, -0.3), SIMD3<Float>(0.05, 0.16, 0.06), .darkJoint, rotation: Math3D.rotationX(-0.15))
        // Side-mounted targeting sight
        b.box(r, SIMD3<Float>(-0.12, tubeY + 0.06, -0.18), SIMD3<Float>(0.04, 0.08, 0.14), .gunmetal)
        b.box(r, SIMD3<Float>(-0.12, tubeY + 0.08, -0.252), SIMD3<Float>(0.026, 0.035, 0.005), glow)
        // Three rocket-charge indicator lamps along the tube
        for i in 0..<3 {
            let lit = i < rocketCharges
            let mat = lit ? PartMaterial.glow(SublevelPalette.amberGold, intensity: 1.9) : PartMaterial.darkJoint
            b.box(r, SIMD3<Float>(0.098, tubeY + 0.03, -0.2 + Float(i) * 0.07), SIMD3<Float>(0.02, 0.03, 0.045), mat)
        }
    }

    private static func appendSubRail(_ r: simd_float4x4, _ b: inout ModelBatch, glow: PartMaterial, paint: PartMaterial, time: Float) {
        // Receiver, power pack and skeletal stock
        b.box(r, SIMD3<Float>(0, 0.04, -0.06), SIMD3<Float>(0.11, 0.14, 0.44), .whiteShell)
        b.box(r, SIMD3<Float>(0, -0.05, -0.18), SIMD3<Float>(0.08, 0.08, 0.16), paint)
        b.box(r, SIMD3<Float>(0, 0.06, 0.3), SIMD3<Float>(0.05, 0.04, 0.26), .gunmetal)
        b.box(r, SIMD3<Float>(0, -0.03, 0.3), SIMD3<Float>(0.05, 0.04, 0.26), .gunmetal, rotation: Math3D.rotationX(-0.2))
        b.box(r, SIMD3<Float>(0, 0.0, 0.44), SIMD3<Float>(0.07, 0.17, 0.04), .darkJoint)
        appendGrip(r, &b)
        // Twin magnetic rails with a charged slug channel between them
        let railZ: Float = -0.66
        b.box(r, SIMD3<Float>(0.042, 0.05, railZ), SIMD3<Float>(0.026, 0.07, 0.72), .gunmetal)
        b.box(r, SIMD3<Float>(-0.042, 0.05, railZ), SIMD3<Float>(0.026, 0.07, 0.72), .gunmetal)
        b.box(r, SIMD3<Float>(0, 0.05, railZ), SIMD3<Float>(0.014, 0.014, 0.7), glow)
        // Accelerator coils
        for i in 0..<5 {
            let z = -0.36 - Float(i) * 0.13
            let pulse = 0.5 + 0.5 * sin(time * 9.0 - Float(i) * 0.9)
            b.cylinder(r, SIMD3<Float>(0, 0.05, z), radius: 0.068, length: 0.03, .darkJoint)
            b.cylinder(r, SIMD3<Float>(0, 0.05, z - 0.02), radius: 0.074, length: 0.012, PartMaterial.glow(glow.color, intensity: 0.9 + pulse))
        }
        // Long-range scope
        b.box(r, SIMD3<Float>(0, 0.13, -0.06), SIMD3<Float>(0.025, 0.04, 0.1), .darkJoint)
        b.cylinder(r, SIMD3<Float>(0, 0.175, -0.06), radius: 0.035, length: 0.32, .gunmetal)
        b.cylinder(r, SIMD3<Float>(0, 0.175, -0.225), radius: 0.042, length: 0.04, .darkJoint)
        b.cylinder(r, SIMD3<Float>(0, 0.175, -0.247), radius: 0.03, length: 0.006, glow)
    }

    // MARK: - Robot bots
    // Local space: origin at the feet, +Y up, -Z forward. Fits the 1.85m × 0.55m-radius combat hitbox.

    static func appendRobot(_ bot: ArenaBot, time: Float, into b: inout ModelBatch) {
        let base = bot.kinematic.position
        let root = Math3D.translation(base) * Math3D.rotationY(bot.yaw)
        let team = bot.teamColor
        let armor = PartMaterial.armor(team)
        let visor = PartMaterial.glow(team, intensity: 1.6)
        let white = PartMaterial.glow(SIMD3<Float>(1, 1, 1), intensity: 1.2)

        b.flashOverride = bot.hitFlashTimer > 0 ? SIMD3<Float>(1, 1, 1) : nil

        let vel = bot.kinematic.velocity
        let speed = simd_length(SIMD2<Float>(vel.x, vel.z))
        let grounded = bot.kinematic.isOnFloor
        let stride = grounded ? min(speed / 9.0, 1.0) * 0.6 : 0.0
        let cycle = time * (6.0 + speed * 0.45) + bot.strafePhase
        let bob = grounded ? abs(sin(cycle)) * 0.035 * min(speed / 6.0, 1.0) : 0.0
        let tuck: Float = grounded ? 0.0 : 0.45

        // Legs (hip pivot → thigh, knee, shin, foot)
        for side in [-1, 1] {
            let s = Float(side)
            let swing = sin(cycle + (side < 0 ? 0 : .pi)) * stride + tuck * 0.6
            let hip = root * Math3D.translation(SIMD3<Float>(0.14 * s, 0.9 + bob, 0)) * Math3D.rotationX(swing)
            b.box(hip, SIMD3<Float>(0, -0.2, 0), SIMD3<Float>(0.16, 0.4, 0.18), .gunmetal)
            b.cylinder(hip, SIMD3<Float>(0, 0, 0), radius: 0.08, length: 0.2, .darkJoint, rotation: Math3D.rotationY(quarterTurn))
            let kneeBend = max(0.0, -sin(cycle + (side < 0 ? 0 : .pi))) * stride * 1.1 + tuck
            let knee = hip * Math3D.translation(SIMD3<Float>(0, -0.42, 0)) * Math3D.rotationX(-kneeBend)
            b.sphere(knee, .zero, SIMD3<Float>(0.15, 0.15, 0.15), .darkJoint)
            b.box(knee, SIMD3<Float>(0, 0.0, -0.09), SIMD3<Float>(0.15, 0.13, 0.05), armor)
            b.box(knee, SIMD3<Float>(0, -0.22, 0), SIMD3<Float>(0.18, 0.4, 0.2), armor)
            b.box(knee, SIMD3<Float>(0, -0.22, 0.105), SIMD3<Float>(0.08, 0.3, 0.02), .darkJoint)
            b.box(knee, SIMD3<Float>(0, -0.44, -0.05), SIMD3<Float>(0.2, 0.08, 0.32), .darkJoint)
        }

        let torso = root * Math3D.translation(SIMD3<Float>(0, 0.95 + bob, 0)) * Math3D.rotationX(-min(speed / 18.0, 0.18)) * Math3D.translation(SIMD3<Float>(0, -0.95, 0))
        // Pelvis and segmented spine
        b.box(torso, SIMD3<Float>(0, 0.95, 0), SIMD3<Float>(0.44, 0.16, 0.26), .gunmetal)
        b.cylinder(torso, SIMD3<Float>(0, 1.08, 0), radius: 0.13, length: 0.16, .darkJoint, rotation: Math3D.rotationX(quarterTurn))
        // Armored chest with glowing reactor core
        b.box(torso, SIMD3<Float>(0, 1.34, 0), SIMD3<Float>(0.62, 0.42, 0.38), armor)
        b.box(torso, SIMD3<Float>(0, 1.25, -0.03), SIMD3<Float>(0.5, 0.2, 0.36), .gunmetal)
        b.box(torso, SIMD3<Float>(0, 1.37, -0.19), SIMD3<Float>(0.18, 0.14, 0.02), .darkJoint)
        b.box(torso, SIMD3<Float>(0, 1.37, -0.2), SIMD3<Float>(0.12, 0.08, 0.02), visor)
        // Back-mounted thruster pack
        b.box(torso, SIMD3<Float>(0, 1.33, 0.25), SIMD3<Float>(0.4, 0.36, 0.14), .gunmetal)
        for s: Float in [-1, 1] {
            b.cylinder(torso, SIMD3<Float>(0.11 * s, 1.15, 0.27), radius: 0.06, length: 0.14, .darkJoint, rotation: Math3D.rotationX(quarterTurn))
            b.cylinder(torso, SIMD3<Float>(0.11 * s, 1.075, 0.27), radius: 0.04, length: 0.01, visor, rotation: Math3D.rotationX(quarterTurn))
        }

        // Head with visor slit and antenna, tracking aim pitch
        let neck = torso * Math3D.translation(SIMD3<Float>(0, 1.58, -0.02))
        b.cylinder(neck, .zero, radius: 0.07, length: 0.1, .darkJoint, rotation: Math3D.rotationX(quarterTurn))
        let head = neck * Math3D.rotationX(simd_clamp(bot.pitch, -0.6, 0.6)) * Math3D.translation(SIMD3<Float>(0, 0.15, 0))
        b.box(head, .zero, SIMD3<Float>(0.28, 0.22, 0.3), .whiteShell)
        b.box(head, SIMD3<Float>(0, 0.12, 0.02), SIMD3<Float>(0.06, 0.04, 0.26), armor)
        b.box(head, SIMD3<Float>(0, 0.015, -0.152), SIMD3<Float>(0.24, 0.06, 0.012), visor)
        b.box(head, SIMD3<Float>(0, -0.075, -0.15), SIMD3<Float>(0.18, 0.06, 0.02), .darkJoint)
        b.cylinder(head, SIMD3<Float>(0.1, 0.2, 0.08), radius: 0.008, length: 0.2, .darkJoint, rotation: Math3D.rotationX(quarterTurn))
        b.sphere(head, SIMD3<Float>(0.1, 0.3, 0.08), SIMD3<Float>(0.025, 0.025, 0.025), white)

        // Arms raised to hold the weapon toward the aim direction
        let aim = Math3D.rotationX(simd_clamp(bot.pitch, -0.7, 0.7))
        for side in [-1, 1] {
            let s = Float(side)
            let shoulder = torso * Math3D.translation(SIMD3<Float>(0.4 * s, 1.47, 0))
            b.box(shoulder, SIMD3<Float>(0.02 * s, 0.04, 0), SIMD3<Float>(0.22, 0.14, 0.3), armor)
            b.sphere(shoulder, SIMD3<Float>(0, -0.06, 0), SIMD3<Float>(0.15, 0.15, 0.15), .darkJoint)
            let upper = shoulder * aim * Math3D.rotationX(0.35) * Math3D.rotationZ(0.12 * s)
            b.box(upper, SIMD3<Float>(0, -0.2, 0), SIMD3<Float>(0.12, 0.3, 0.12), .gunmetal)
            let elbow = upper * Math3D.translation(SIMD3<Float>(0, -0.36, 0)) * Math3D.rotationX(1.2) * Math3D.rotationZ(-0.45 * s)
            b.sphere(elbow, .zero, SIMD3<Float>(0.11, 0.11, 0.11), .darkJoint)
            b.box(elbow, SIMD3<Float>(0, -0.15, 0), SIMD3<Float>(0.14, 0.28, 0.14), armor)
            b.box(elbow, SIMD3<Float>(0, -0.32, 0), SIMD3<Float>(0.1, 0.08, 0.1), .darkJoint)
        }

        // Weapon held at chest height
        let weaponRoot = torso * Math3D.translation(SIMD3<Float>(0.12, 1.22, -0.42)) * aim * Math3D.scale(SIMD3<Float>(repeating: 0.85))
        appendWeapon(bot.weapon, root: weaponRoot, into: &b, time: time)

        b.flashOverride = nil
    }

    // MARK: - Projectiles

    /// Rocket body oriented along its velocity (nose at local +Z).
    static func appendRocket(position: SIMD3<Float>, velocity: SIMD3<Float>, color: SIMD3<Float>, time: Float, into b: inout ModelBatch) {
        let dir = simd_length(velocity) > 0.01 ? velocity : SIMD3<Float>(0, 0, -1)
        let root = Math3D.translation(position) * orientation(forward: dir) * Math3D.rotationZ(time * 8.0)
        b.cylinder(root, .zero, radius: 0.075, length: 0.46, .whiteShell)
        b.cylinder(root, SIMD3<Float>(0, 0, 0.08), radius: 0.079, length: 0.05, PartMaterial.hardware(color * 0.85, roughness: 0.3, metallic: 0.3))
        b.sphere(root, SIMD3<Float>(0, 0, 0.23), SIMD3<Float>(0.15, 0.15, 0.24), PartMaterial.glow(color, intensity: 1.6))
        b.cylinder(root, SIMD3<Float>(0, 0, -0.25), radius: 0.06, length: 0.06, .darkJoint)
        for i in 0..<4 {
            let fin = Math3D.rotationZ(Float(i) * quarterTurn)
            b.box(root * fin, SIMD3<Float>(0, 0.1, -0.17), SIMD3<Float>(0.012, 0.09, 0.12), .gunmetal)
        }
    }
}
