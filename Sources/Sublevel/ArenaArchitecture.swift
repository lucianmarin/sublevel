import Foundation
import simd

/// Builds high-polygon static and dynamic Mirror's Edge ("City of Glass") arena structures.
enum ArenaArchitecture {
    static let quarterTurn: Float = .pi * 0.5

    // MARK: - Static Architectural World Batch (Built Once & Cached on GPU)

    static func buildStaticArchitecture(arena: ArenaMap) -> ModelBatch {
        var b = ModelBatch()
        let idMat = matrix_identity_float4x4

        let whiteArch = PartMaterial.arch(SublevelPalette.starkWhite, roughness: 0.20, metallic: 0.04)
        let coolArch = PartMaterial.arch(SublevelPalette.coolConcrete, roughness: 0.24, metallic: 0.05)
        let slateHw = PartMaterial.hardware(SublevelPalette.darkSlate, roughness: 0.34, metallic: 0.72)
        let steelHw = PartMaterial.brushedSteel
        let redMat = PartMaterial.arch(SublevelPalette.signalRed, roughness: 0.14, metallic: 0.08, emissive: 0.22)
        let orangeMat = PartMaterial.arch(SublevelPalette.runnerOrange, roughness: 0.16, metallic: 0.10, emissive: 0.16)
        let yellowMat = PartMaterial.arch(SublevelPalette.canaryYellow, roughness: 0.16, metallic: 0.10, emissive: 0.14)
        let ceruleanMat = PartMaterial.arch(SublevelPalette.skyCerulean, roughness: 0.15, metallic: 0.12, emissive: 0.16)
        let cobaltMat = PartMaterial.arch(SublevelPalette.cobaltBlue, roughness: 0.14, metallic: 0.18, emissive: 0.35)
        let emeraldMat = PartMaterial.arch(SublevelPalette.atriumEmerald, roughness: 0.18, metallic: 0.08, emissive: 0.14)
        let glassRail = PartMaterial.holoGlass(SublevelPalette.skyCerulean, alpha: 0.28)

        // 1. Static Colliders: Real Sloped Wedges for Ramps + Chamfered Architectural Slabs
        for box in arena.colliders where !box.isDynamic && box.kind != .shatterFloor {
            let c = box.center
            let s = box.size
            let mat = PartMaterial.arch(box.color, roughness: box.roughness, metallic: box.metallic, emissive: box.emissiveStrength)

            switch box.kind {
            case .rampPosX:
                appendDetailedRamp(&b, center: c, size: s, yaw: 0.0, lengthAxisX: true, mat: mat)
            case .rampNegX:
                appendDetailedRamp(&b, center: c, size: s, yaw: .pi, lengthAxisX: true, mat: mat)
            case .rampPosZ:
                appendDetailedRamp(&b, center: c, size: s, yaw: -quarterTurn, lengthAxisX: false, mat: mat)
            case .rampNegZ:
                appendDetailedRamp(&b, center: c, size: s, yaw: quarterTurn, lengthAxisX: false, mat: mat)
            default:
                b.archBlock(idMat, c, s, mat, extra: Float(box.kind.rawValue))
            }
        }

        // 2. Skylight Roof Space-Frame Trusses (Y = 26.0 .. 28.6)
        for zTruss in stride(from: -24, through: 24, by: 12) {
            let z = Float(zTruss)
            // Upper & lower horizontal tubular chords
            b.cylinder(idMat, SIMD3<Float>(0, 28.4, z), radius: 0.18, length: 58.0, steelHw, rotation: Math3D.rotationY(quarterTurn))
            b.cylinder(idMat, SIMD3<Float>(0, 25.8, z), radius: 0.16, length: 58.0, slateHw, rotation: Math3D.rotationY(quarterTurn))
            // Diagonal Warren-truss web struts across the 56m span
            var x: Float = -28.0
            var up = true
            while x < 27.9 {
                let nextX = x + 4.0
                let p0 = SIMD3<Float>(x, up ? 25.8 : 28.4, z)
                let p1 = SIMD3<Float>(nextX, up ? 28.4 : 25.8, z)
                b.strut(idMat, from: p0, to: p1, radius: 0.095, steelHw)
                b.sphere(idMat, p0, SIMD3<Float>(0.36, 0.36, 0.36), slateHw)
                x = nextX
                up.toggle()
            }
            // Suspended minimalist linear LED architectural light bars
            b.box(idMat, SIMD3<Float>(0, 25.2, z), SIMD3<Float>(42.0, 0.14, 0.32), .glow(SIMD3<Float>(0.98, 0.99, 1.0), intensity: 1.5))
        }
        // Longitudinal roof purlins
        for xPurlin in stride(from: -24, through: 24, by: 12) {
            b.cylinder(idMat, SIMD3<Float>(Float(xPurlin), 28.4, 0), radius: 0.14, length: 58.0, steelHw)
        }

        // 3. Mirror's Edge "City of Glass" Exterior Skyline & Tower Crane (Visible Above Skylight!)
        let towers: [(pos: SIMD3<Float>, size: SIMD3<Float>, accent: PartMaterial)] = [
            (SIMD3<Float>(-46, 52, -48), SIMD3<Float>(16, 68, 16), ceruleanMat),
            (SIMD3<Float>( 48, 58, -44), SIMD3<Float>(18, 80, 15), whiteArch),
            (SIMD3<Float>(-52, 48,  42), SIMD3<Float>(15, 60, 18), yellowMat),
            (SIMD3<Float>( 46, 62,  50), SIMD3<Float>(19, 88, 17), redMat),
            (SIMD3<Float>(  0, 66, -64), SIMD3<Float>(22, 96, 16), ceruleanMat),
            (SIMD3<Float>(-64, 55,  -4), SIMD3<Float>(14, 74, 20), orangeMat),
            (SIMD3<Float>( 64, 57,   8), SIMD3<Float>(16, 78, 18), cobaltMat),
            (SIMD3<Float>( 12, 54,  64), SIMD3<Float>(20, 72, 15), emeraldMat)
        ]
        for t in towers {
            b.archBlock(idMat, t.pos, t.size, whiteArch)
            // Stepped penthouse crown + bold vertical Mirror's Edge color stripe + spire antenna
            let topY = t.pos.y + t.size.y * 0.5
            b.archBlock(idMat, SIMD3<Float>(t.pos.x, topY + 3.5, t.pos.z), SIMD3<Float>(t.size.x * 0.68, 7.0, t.size.z * 0.68), coolArch)
            b.archBlock(idMat, SIMD3<Float>(t.pos.x, topY - t.size.y * 0.15, t.pos.z), SIMD3<Float>(t.size.x * 1.02, 3.2, t.size.z * 1.02), t.accent)
            b.cylinder(idMat, SIMD3<Float>(t.pos.x, topY + 13.0, t.pos.z), radius: 0.22, length: 14.0, steelHw, rotation: Math3D.rotationX(quarterTurn))
            b.sphere(idMat, SIMD3<Float>(t.pos.x, topY + 20.2, t.pos.z), SIMD3<Float>(0.9, 0.9, 0.9), .glow(SublevelPalette.signalRed, intensity: 2.2))
        }

        // Iconic Canary-Yellow Construction Tower Crane overhanging the City of Glass skylight
        let craneBase = SIMD3<Float>(36, 44, -34)
        b.box(idMat, craneBase, SIMD3<Float>(2.2, 34.0, 2.2), yellowMat)
        let craneTop = SIMD3<Float>(36, 61, -34)
        let jibDir = Math3D.rotationY(0.58)
        b.box(idMat * Math3D.translation(craneTop) * jibDir, SIMD3<Float>(-16.0, 0, 0), SIMD3<Float>(52.0, 1.4, 1.4), yellowMat)
        b.box(idMat * Math3D.translation(craneTop) * jibDir, SIMD3<Float>(8.0, -1.2, 0), SIMD3<Float>(6.5, 2.6, 2.4), slateHw)
        b.cone(idMat, craneTop + SIMD3<Float>(0, 3.5, 0), radius: 1.3, length: 6.0, yellowMat, rotation: Math3D.rotationX(-quarterTurn))
        b.strut(idMat * Math3D.translation(craneTop) * jibDir, from: SIMD3<Float>(0, 6.2, 0), to: SIMD3<Float>(-34.0, 0.7, 0), radius: 0.10, steelHw)
        b.strut(idMat * Math3D.translation(craneTop) * jibDir, from: SIMD3<Float>(0, 6.2, 0), to: SIMD3<Float>(9.5, 0.7, 0), radius: 0.10, steelHw)

        // 4. Mega-Column Fluted Ribs, Recessed Light Strips & Diagonal Flying Buttresses
        let colPositions: [SIMD2<Float>] = [
            SIMD2<Float>(-16, -16), SIMD2<Float>(16, -16),
            SIMD2<Float>(-16,  16), SIMD2<Float>(16,  16)
        ]
        for p in colPositions {
            let sx: Float = p.x < 0 ? -1 : 1
            let sz: Float = p.y < 0 ? -1 : 1
            // Vertical corner chamfer ribs + recessed daylight LED strips
            for rx: Float in [-1, 1] {
                for rz: Float in [-1, 1] {
                    b.box(idMat, SIMD3<Float>(p.x + rx * 1.78, 5.5, p.y + rz * 1.78), SIMD3<Float>(0.32, 38.0, 0.32), steelHw)
                }
            }
            b.box(idMat, SIMD3<Float>(p.x - sx * 1.80, 6.0, p.y), SIMD3<Float>(0.08, 30.0, 0.24), .glow(SIMD3<Float>(0.85, 0.94, 1.0), intensity: 1.4))
            b.box(idMat, SIMD3<Float>(p.x, 6.0, p.y - sz * 1.80), SIMD3<Float>(0.24, 30.0, 0.08), .glow(SIMD3<Float>(0.85, 0.94, 1.0), intensity: 1.4))

            // Diagonal structural flying buttresses into B1 & B2 soffits
            b.beamStrut(
                idMat,
                from: SIMD3<Float>(p.x + sx * 1.6, 7.5, p.y),
                to: SIMD3<Float>(p.x + sx * 8.5, 11.3, p.y),
                width: 0.65,
                height: 0.85,
                coolArch
            )
            b.beamStrut(
                idMat,
                from: SIMD3<Float>(p.x, -4.5, p.y + sz * 1.6),
                to: SIMD3<Float>(p.x, -0.7, p.y + sz * 8.5),
                width: 0.65,
                height: 0.85,
                coolArch
            )
        }

        // 5. Mirror's Edge Cylindrical HVAC Ventilation Ducts & Flanged Color-Coded Pipes
        // Under B1 North/South Soffits (Y = 9.9): Canary Yellow & Sky Cerulean Twin Duct Runs
        for (zDuct, ductMat) in [(-24.5 as Float, yellowMat), (24.5 as Float, ceruleanMat)] {
            b.tube(idMat, SIMD3<Float>(0, 9.9, zDuct), radius: 0.68, length: 50.0, ductMat, rotation: Math3D.rotationY(quarterTurn))
            b.cylinder(idMat, SIMD3<Float>(0, 8.8, zDuct), radius: 0.32, length: 50.0, steelHw, rotation: Math3D.rotationY(quarterTurn))
            for fx in stride(from: -20, through: 20, by: 8) {
                let x = Float(fx)
                b.torus(idMat, SIMD3<Float>(x, 9.9, zDuct), outerRadius: 0.76, thicknessScale: 0.45, slateHw, rotation: Math3D.rotationY(quarterTurn))
                b.strut(idMat, from: SIMD3<Float>(x, 11.2, zDuct), to: SIMD3<Float>(x, 9.9, zDuct), radius: 0.07, slateHw)
            }
        }
        // East & West Runner-Orange HVAC Trunk + Vertical Cobalt/Red Pipe Risers (B3 -> B1)
        for sx: Float in [-1, 1] {
            let xWall = 28.3 * sx
            b.tube(idMat, SIMD3<Float>(xWall, 10.2, 0), radius: 0.62, length: 48.0, orangeMat)
            for fz in stride(from: -18, through: 18, by: 9) {
                b.torus(idMat, SIMD3<Float>(xWall, 10.2, Float(fz)), outerRadius: 0.70, thicknessScale: 0.45, slateHw)
            }
            // Triple vertical industrial pipe risers in corners
            for (zOff, pipeMat) in [(-24.0 as Float, redMat), (-25.2 as Float, cobaltMat), (24.5 as Float, cobaltMat)] {
                b.cylinder(idMat, SIMD3<Float>(xWall, 5.0, zOff), radius: 0.28, length: 36.0, pipeMat, rotation: Math3D.rotationX(quarterTurn))
                for ringY in stride(from: -8, through: 20, by: 7) {
                    b.torus(idMat, SIMD3<Float>(xWall, Float(ringY), zOff), outerRadius: 0.35, thicknessScale: 0.5, steelHw, rotation: Math3D.rotationX(quarterTurn))
                }
            }
        }

        // 6. Hydraulic Lift Guide Towers (X = ±10.8) & Aerial Shuttle Monorail I-Beams (Z = ±11.8, Y = 9.4)
        for sx: Float in [-1, 1] {
            let lx = 10.8 * sx
            for rz: Float in [-2.25, 2.25] {
                b.box(idMat, SIMD3<Float>(lx, 5.5, rz), SIMD3<Float>(0.24, 13.5, 0.24), steelHw)
                b.box(idMat, SIMD3<Float>(lx, 5.5, rz + (rz < 0 ? -0.14 : 0.14)), SIMD3<Float>(0.08, 13.2, 0.08), .glow(SublevelPalette.cobaltBlue, intensity: 1.5))
            }
        }
        for sz: Float in [-1, 1] {
            let mz = 11.8 * sz
            let railGlow = sz < 0 ? SublevelPalette.runnerOrange : SublevelPalette.skyCerulean
            b.box(idMat, SIMD3<Float>(0, 9.6, mz), SIMD3<Float>(22.0, 0.28, 0.42), slateHw)
            b.box(idMat, SIMD3<Float>(0, 9.42, mz), SIMD3<Float>(21.6, 0.08, 0.14), .glow(railGlow, intensity: 1.4))
        }

        // 7. Sleek Glass & Steel Architectural Balustrades on Elevated Sniper Overlooks (Y = 16.0)
        for sz: Float in [-1, 1] {
            let zEdge = 22.65 * sz
            b.sharpBox(idMat, SIMD3<Float>(0, 16.48, zEdge), SIMD3<Float>(12.8, 0.88, 0.06), glassRail)
            b.cylinder(idMat, SIMD3<Float>(0, 16.95, zEdge), radius: 0.045, length: 13.2, steelHw, rotation: Math3D.rotationY(quarterTurn))
            for px in stride(from: -6, through: 6, by: 3) {
                b.box(idMat, SIMD3<Float>(Float(px), 16.48, zEdge), SIMD3<Float>(0.09, 0.96, 0.09), steelHw)
            }
        }

        // 8. Architectural Stratum Supergraphic Bars & Mirror's Edge Runner Floor Guide Stripes
        let strataMarkers: [(y: Float, bars: Int, mat: PartMaterial)] = [
            (18.5, 1, ceruleanMat),
            ( 4.2, 2, redMat),
            (-7.8, 3, cobaltMat)
        ]
        for m in strataMarkers {
            for idx in 0..<m.bars {
                let by = m.y - Float(idx) * 0.75
                b.box(idMat, SIMD3<Float>(0, by, -28.92), SIMD3<Float>(8.5, 0.38, 0.14), m.mat)
                b.box(idMat, SIMD3<Float>(0, by,  28.92), SIMD3<Float>(8.5, 0.38, 0.14), m.mat)
            }
        }

        // Dark-slate shaft coping curbs & bold Runner Vision floor guide stripes on B1 / B2 decks!
        for sz: Float in [-1, 1] {
            b.box(idMat, SIMD3<Float>(0, 12.01, 13.05 * sz), SIMD3<Float>(26.4, 0.04, 0.32), slateHw)
            b.box(idMat, SIMD3<Float>(0, 12.01, 2.52 * sz), SIMD3<Float>(26.0, 0.04, 0.24), redMat)
            b.box(idMat, SIMD3<Float>(0, 0.01, 9.05 * sz), SIMD3<Float>(18.4, 0.04, 0.32), slateHw)
        }
        for sx: Float in [-1, 1] {
            b.box(idMat, SIMD3<Float>(13.05 * sx, 12.01, 0), SIMD3<Float>(0.32, 0.04, 26.4), slateHw)
            b.box(idMat, SIMD3<Float>(9.05 * sx, 0.01, 0), SIMD3<Float>(0.32, 0.04, 18.4), slateHw)
            // Runner Red kinetic lead-in lanes to ramps & jump pads
            b.archBlock(idMat, SIMD3<Float>(-17.5 * sx, 12.008, -17.0 * sx), SIMD3<Float>(9.0, 0.025, 2.2), redMat)
            b.archBlock(idMat, SIMD3<Float>(21.0 * sx, 0.008, 0), SIMD3<Float>(2.4, 0.025, 36.0), orangeMat)
        }
        b.archBlock(idMat, SIMD3<Float>(0, 12.008, -21.0), SIMD3<Float>(38.0, 0.025, 1.4), yellowMat)
        b.archBlock(idMat, SIMD3<Float>(0, 12.008,  21.0), SIMD3<Float>(38.0, 0.025, 1.4), ceruleanMat)

        return b
    }

    private static func appendDetailedRamp(
        _ b: inout ModelBatch,
        center: SIMD3<Float>,
        size: SIMD3<Float>,
        yaw: Float,
        lengthAxisX: Bool,
        mat: PartMaterial
    ) {
        let len = lengthAxisX ? size.x : size.z
        let width = lengthAxisX ? size.z : size.x
        let height = size.y
        let localScale = SIMD3<Float>(len, height, width)
        let root = Math3D.translation(center) * Math3D.rotationY(yaw)

        // True sloped wedge body!
        b.wedge(root, .zero, localScale, mat)

        // Brushed-steel side curbs along the sloped edges + twin under-ramp chrome hydraulic struts
        let slopeAngle = atan2(height, len)
        let hypo = hypot(len, height)
        for side: Float in [-1, 1] {
            let zOff = (width * 0.5 + 0.08) * side
            b.box(
                root,
                SIMD3<Float>(0, 0.05, zOff),
                SIMD3<Float>(hypo, 0.16, 0.14),
                .brushedSteel,
                rotation: Math3D.rotationZ(slopeAngle)
            )
            b.strut(
                root,
                from: SIMD3<Float>(len * 0.15, -height * 0.48, zOff * 0.72),
                to: SIMD3<Float>(len * 0.36, height * 0.28, zOff * 0.72),
                radius: 0.09,
                .chrome
            )
        }

        // 3 Glowing white/amber launch chevrons flush with the ramp slope
        let chevGlow = PartMaterial.glow(SIMD3<Float>(1.0, 0.92, 0.85), intensity: 1.55)
        for k in -1...1 {
            let frac = Float(k) * 0.26
            let xPos = frac * len
            let yPos = frac * height + 0.02
            let cRoot = root * Math3D.translation(SIMD3<Float>(xPos, yPos, 0)) * Math3D.rotationZ(slopeAngle)
            b.box(cRoot, SIMD3<Float>(0, 0, -width * 0.16), SIMD3<Float>(0.22, 0.03, width * 0.36), chevGlow, rotation: Math3D.rotationY(0.45))
            b.box(cRoot, SIMD3<Float>(0, 0,  width * 0.16), SIMD3<Float>(0.22, 0.03, width * 0.36), chevGlow, rotation: Math3D.rotationY(-0.45))
        }
    }

    // MARK: - Per-Frame Dynamic Arena Structures (Elevators, Shuttles, Turbines, Louvers, Portals, Pickups, Debris)

    static func appendDynamicArchitecture(
        arena: ArenaMap,
        debris: [DebrisShard],
        time: Float,
        into b: inout ModelBatch
    ) {
        let idMat = matrix_identity_float4x4

        // 1. Shatterable Glass Skylights & Reinforced Grates (with steel mullion frames + damage stress glow)
        for box in arena.colliders where box.kind == .shatterFloor && !box.isDestroyed {
            let c = box.center
            let s = box.size
            let dmgRatio = simd_clamp(1.0 - box.health / max(box.maxHealth, 1.0), 0.0, 1.0)
            let isGlass = box.color.z > box.color.x

            // Perimeter steel frame + internal cross-mullions
            b.box(idMat, SIMD3<Float>(c.x, c.y, c.z - s.z * 0.49), SIMD3<Float>(s.x, s.y * 1.15, 0.22), .gunmetal)
            b.box(idMat, SIMD3<Float>(c.x, c.y, c.z + s.z * 0.49), SIMD3<Float>(s.x, s.y * 1.15, 0.22), .gunmetal)
            b.box(idMat, SIMD3<Float>(c.x - s.x * 0.49, c.y, c.z), SIMD3<Float>(0.22, s.y * 1.15, s.z), .gunmetal)
            b.box(idMat, SIMD3<Float>(c.x + s.x * 0.49, c.y, c.z), SIMD3<Float>(0.22, s.y * 1.15, s.z), .gunmetal)
            for m in -1...1 {
                b.box(idMat, SIMD3<Float>(c.x + Float(m) * (s.x * 0.26), c.y, c.z), SIMD3<Float>(0.12, s.y * 1.08, s.z), .brushedSteel)
                b.box(idMat, SIMD3<Float>(c.x, c.y, c.z + Float(m) * (s.z * 0.26)), SIMD3<Float>(s.x, s.y * 1.08, 0.12), .brushedSteel)
            }

            let tint = simd_mix(box.color, SublevelPalette.signalRed, SIMD3<Float>(repeating: dmgRatio * 0.65))
            if isGlass {
                b.sharpBox(idMat, c, s * SIMD3<Float>(0.98, 0.75, 0.98), .holoGlass(tint, alpha: 0.44 + dmgRatio * 0.2))
            } else {
                b.archBlock(idMat, c, s * SIMD3<Float>(0.97, 0.85, 0.97), .arch(tint, roughness: 0.22, metallic: 0.35, emissive: 0.32 + dmgRatio * 0.7))
            }
        }

        // 2. Dynamic Moving Platforms (Hydraulic Lifts, Aerial Shuttles, Sump Pistons)
        for mover in arena.dynamicMovers {
            let box = arena.colliders[mover.colliderIndex]
            let c = box.center
            let s = box.size
            let accentGlow = PartMaterial.glow(mover.accentColor, intensity: 1.55)
            let accentArch = PartMaterial.arch(mover.accentColor, roughness: 0.16, metallic: 0.20, emissive: 0.24)

            // Main beveled platform deck + perimeter bumper frame + corner beacon lights
            b.box(idMat, c, s, .arch(box.color, roughness: 0.18, metallic: 0.15, emissive: box.emissiveStrength))
            b.box(idMat, c - SIMD3<Float>(0, s.y * 0.32, 0), SIMD3<Float>(s.x * 1.04, s.y * 0.48, s.z * 1.04), .gunmetal)
            b.box(idMat, SIMD3<Float>(c.x, c.y + 0.02, c.z - s.z * 0.48), SIMD3<Float>(s.x * 0.85, 0.08, 0.08), accentGlow)
            b.box(idMat, SIMD3<Float>(c.x, c.y + 0.02, c.z + s.z * 0.48), SIMD3<Float>(s.x * 0.85, 0.08, 0.08), accentGlow)

            switch mover.kind {
            case .hydraulicLift:
                // Telescoping chrome hydraulic cylinder plunging down to B2 (-0.6) + guide shoes
                let bottomY: Float = -0.8
                let rodLen = max(0.3, (c.y - s.y * 0.5) - bottomY)
                b.cylinder(idMat, SIMD3<Float>(c.x, bottomY + rodLen * 0.5, c.z), radius: 0.22, length: rodLen, .chrome, rotation: Math3D.rotationX(quarterTurn))
                b.tube(idMat, SIMD3<Float>(c.x, bottomY + min(rodLen, 3.8) * 0.5, c.z), radius: 0.34, length: min(rodLen, 3.8), .gunmetal, rotation: Math3D.rotationX(quarterTurn))
                for rz: Float in [-2.25, 2.25] {
                    b.box(idMat, SIMD3<Float>(c.x, c.y, rz), SIMD3<Float>(0.55, 0.75, 0.45), accentArch)
                }

            case .aerialShuttle:
                // Overhead monorail bogie carriage at Y = 9.5 + twin diagonal suspension struts + hover thrusters
                let railY: Float = 9.5
                b.box(idMat, SIMD3<Float>(c.x, railY, c.z), SIMD3<Float>(1.8, 0.48, 0.72), .gunmetal)
                b.strut(idMat, from: SIMD3<Float>(c.x - 0.7, railY - 0.2, c.z), to: SIMD3<Float>(c.x - 1.6, c.y + 0.1, c.z), radius: 0.065, .brushedSteel)
                b.strut(idMat, from: SIMD3<Float>(c.x + 0.7, railY - 0.2, c.z), to: SIMD3<Float>(c.x + 1.6, c.y + 0.1, c.z), radius: 0.065, .brushedSteel)
                for tx: Float in [-1.4, 1.4] {
                    b.tube(idMat, SIMD3<Float>(c.x + tx, c.y - 0.42, c.z), radius: 0.36, length: 0.32, .gunmetal, rotation: Math3D.rotationX(quarterTurn))
                    b.cone(idMat, SIMD3<Float>(c.x + tx, c.y - 0.82, c.z), radius: 0.30, length: 0.55, .energyField(mover.accentColor, intensity: 1.8, alpha: 0.65), rotation: Math3D.rotationX(quarterTurn))
                }

            case .sumpPiston:
                // Heavy dual-shaft Sump abyss piston plunging to Y = -16.5
                for pz: Float in [-1.1, 1.1] {
                    let baseDepth: Float = -16.5
                    let pLen = max(0.5, c.y - baseDepth)
                    b.cylinder(idMat, SIMD3<Float>(c.x, baseDepth + pLen * 0.5, c.z + pz), radius: 0.26, length: pLen, .chrome, rotation: Math3D.rotationX(quarterTurn))
                    b.torus(idMat, SIMD3<Float>(c.x, c.y - 0.45, c.z + pz), outerRadius: 0.34, thicknessScale: 0.5, accentGlow, rotation: Math3D.rotationX(quarterTurn))
                }
            }
        }

        // 3. Spinning Industrial HVAC Extraction Turbines
        for turb in arena.turbines {
            let root = Math3D.translation(turb.position) * Math3D.rotationY(turb.yaw)
            let r = turb.radius
            let accent = PartMaterial.arch(turb.accentColor, roughness: 0.16, metallic: 0.2, emissive: 0.25)
            // Outer cowling ring + hollow shroud + spinner cone + 7 rotating pitched airfoil blades
            b.tube(root, .zero, radius: r, length: 0.85, .gunmetal)
            b.torus(root, SIMD3<Float>(0, 0, 0.42), outerRadius: r * 1.04, thicknessScale: 0.35, accent)
            let spin = Math3D.rotationZ(time * turb.spinSpeed)
            let rotor = root * spin
            b.cone(rotor, SIMD3<Float>(0, 0, 0.18), radius: r * 0.26, length: 0.62, .brushedSteel)
            b.torus(rotor, SIMD3<Float>(0, 0, 0.10), outerRadius: r * 0.28, thicknessScale: 0.45, .glow(turb.accentColor, intensity: 1.5))
            for blade in 0..<7 {
                let ang = Float(blade) * (2.0 * .pi / 7.0)
                let bRoot = rotor * Math3D.rotationZ(ang)
                b.box(bRoot, SIMD3<Float>(0, r * 0.54, 0.04), SIMD3<Float>(r * 0.24, r * 0.72, 0.06), .whiteShell, rotation: Math3D.rotationY(0.48))
            }
        }

        // 4. Articulating Skylight Louvers + Volumetric Diagonal Atrium Sunbeams!
        let whiteLouver = PartMaterial.arch(SublevelPalette.starkWhite, roughness: 0.18, metallic: 0.06)
        for (idx, lx) in arena.louverBaseX.enumerated() {
            let tilt = 0.28 + 0.14 * sin(time * 0.42 + Float(idx) * 0.5)
            let lRoot = Math3D.translation(SIMD3<Float>(lx, 26.8, 0)) * Math3D.rotationZ(tilt)
            b.box(lRoot, .zero, SIMD3<Float>(0.42, 2.2, 57.5), whiteLouver)
            b.cylinder(idMat, SIMD3<Float>(lx, 26.8, 0), radius: 0.12, length: 58.6, .brushedSteel)

            // Every other louver casts a soft glowing diagonal sunlight shaft into B1 Atrium
            if idx % 2 == 1 {
                let beamCenter = SIMD3<Float>(lx - 2.6, 19.2, 0)
                let sunRot = Math3D.rotationZ(0.25)
                b.sharpBox(
                    idMat,
                    beamCenter,
                    SIMD3<Float>(1.65, 14.5, 22.0),
                    .glow(SIMD3<Float>(0.95, 0.98, 1.0), intensity: 0.85, alpha: 0.045),
                    rotation: sunRot
                )
            }
        }

        // 5. B3 Sump Core Gyroscopic Reactor Rings (Suspended Around & Below the Quad Overdrive Dais)
        let coreOrigin = Math3D.translation(SIMD3<Float>(0, -12.6, 0))
        b.torus(coreOrigin, .zero, outerRadius: 4.2, thicknessScale: 0.16, .glow(SublevelPalette.cobaltBlue, intensity: 1.7), rotation: Math3D.rotationX(quarterTurn + sin(time * 0.9) * 0.22) * Math3D.rotationZ(time * 0.8))
        b.torus(coreOrigin, .zero, outerRadius: 5.4, thicknessScale: 0.12, .brushedSteel, rotation: Math3D.rotationX(quarterTurn - cos(time * 0.7) * 0.20) * Math3D.rotationZ(-time * 0.55))
        b.torus(coreOrigin, SIMD3<Float>(0, -1.6, 0), outerRadius: 6.4, thicknessScale: 0.10, .glow(SublevelPalette.amberGold, intensity: 1.5), rotation: Math3D.rotationX(quarterTurn))
        b.cone(coreOrigin, SIMD3<Float>(0, -3.2, 0), radius: 1.8, length: 6.0, .energyField(SublevelPalette.cobaltBlue, intensity: 1.8, alpha: 0.55), rotation: Math3D.rotationX(quarterTurn))

        // 6. High-Polygon Animated Jump Pads (Turbine Base + Concentric Rising Pulse Rings)
        let basePulse = 0.65 + 0.35 * sin(time * 5.2)
        for pad in arena.jumpPads {
            let root = Math3D.translation(pad.position)
            let r = pad.radius * 0.92
            let boost = pad.pulseTimer * 1.4
            let redGlow = PartMaterial.glow(SublevelPalette.signalRed, intensity: 1.55 + boost)

            b.cylinder(root, SIMD3<Float>(0, -0.04, 0), radius: r * 1.06, length: 0.22, .gunmetal, rotation: Math3D.rotationX(quarterTurn))
            b.torus(root, SIMD3<Float>(0, 0.06, 0), outerRadius: r * 1.05, thicknessScale: 0.22, .brushedSteel, rotation: Math3D.rotationX(quarterTurn))
            b.cylinder(root, SIMD3<Float>(0, 0.04, 0), radius: r * 0.82, length: 0.10, .arch(SublevelPalette.signalRed, roughness: 0.12, emissive: 0.55 * basePulse), rotation: Math3D.rotationX(quarterTurn))

            // 3 Concentric rising holographic shock-rings above the pad
            for k in 0..<3 {
                let phase = fmod(time * 1.6 + Float(k) * 0.33, 1.0)
                let ringY = 0.10 + phase * (0.65 + boost * 0.8)
                let ringRad = r * (0.85 - phase * 0.35)
                let ringAlpha = (1.0 - phase) * 0.85
                b.torus(
                    root,
                    SIMD3<Float>(0, ringY, 0),
                    outerRadius: ringRad,
                    thicknessScale: 0.24,
                    .glow(SublevelPalette.signalRed, intensity: 1.8 + boost, alpha: ringAlpha),
                    rotation: Math3D.rotationX(quarterTurn)
                )
            }
            b.octahedron(root, SIMD3<Float>(0, 0.18 + boost * 0.3, 0), SIMD3<Float>(0.36, 0.24, 0.36), redGlow, rotation: Math3D.rotationY(time * 4.0))
        }

        // 7. Twin-Arch Cobalt Blue Teleporter Gates
        for tp in arena.teleporters {
            let root = Math3D.translation(tp.position)
            let blueGlow = PartMaterial.glow(SublevelPalette.cobaltBlue, intensity: 1.85)
            // Floor pad + twin angled architectural pylons + counter-rotating portal rings + vortex lens
            b.cylinder(root, SIMD3<Float>(0, 0.05, 0), radius: 1.45, length: 0.16, .gunmetal, rotation: Math3D.rotationX(quarterTurn))
            b.torus(root, SIMD3<Float>(0, 0.12, 0), outerRadius: 1.38, thicknessScale: 0.22, blueGlow, rotation: Math3D.rotationX(quarterTurn))
            for side: Float in [-1, 1] {
                b.box(root, SIMD3<Float>(1.28 * side, 1.35, 0), SIMD3<Float>(0.26, 2.5, 0.42), .whiteShell, rotation: Math3D.rotationZ(-0.10 * side))
                b.box(root, SIMD3<Float>(1.14 * side, 1.35, 0), SIMD3<Float>(0.08, 2.2, 0.18), blueGlow, rotation: Math3D.rotationZ(-0.10 * side))
            }
            let portalCenter = SIMD3<Float>(0, 1.38, 0)
            b.torus(root, portalCenter, outerRadius: 1.15, thicknessScale: 0.20, .brushedSteel, rotation: Math3D.rotationZ(time * 1.6))
            b.torus(root, portalCenter, outerRadius: 0.96, thicknessScale: 0.18, blueGlow, rotation: Math3D.rotationZ(-time * 2.5))
            b.sphere(root, portalCenter, SIMD3<Float>(1.78, 2.05, 0.28), .energyField(SublevelPalette.cobaltBlue, intensity: 1.95, alpha: 0.72))
        }

        // 8. High-Polygon 3D Pickups + Floor Holographic Projector Pedestals
        for pickup in arena.pickups {
            let col = pickup.kind.color
            // Floor projector base (always visible; dims while item is respawning)
            let basePos = pickup.position - SIMD3<Float>(0, 0.52, 0)
            let baseRoot = Math3D.translation(basePos)
            b.cylinder(baseRoot, .zero, radius: 0.56, length: 0.12, .gunmetal, rotation: Math3D.rotationX(quarterTurn))
            let baseGlow = pickup.isActive ? PartMaterial.glow(col, intensity: 1.5) : PartMaterial.hardware(col * 0.4, roughness: 0.4, metallic: 0.3)
            b.torus(baseRoot, SIMD3<Float>(0, 0.06, 0), outerRadius: 0.50, thicknessScale: 0.25, baseGlow, rotation: Math3D.rotationX(quarterTurn))

            guard pickup.isActive else { continue }

            let bobY = sin(time * 3.2 + Float(pickup.id)) * 0.16
            let itemRoot = Math3D.translation(pickup.position + SIMD3<Float>(0, bobY, 0)) * Math3D.rotationY(pickup.rotationAngle)
            let glow = PartMaterial.glow(col, intensity: 1.75)

            switch pickup.kind {
            case .megaHealth:
                // 3D Stark-White & Amber-Gold Medical Cross inside dual gyro rings
                b.box(itemRoot, .zero, SIMD3<Float>(0.24, 0.68, 0.24), glow)
                b.box(itemRoot, .zero, SIMD3<Float>(0.68, 0.24, 0.24), glow)
                b.box(itemRoot, .zero, SIMD3<Float>(0.24, 0.24, 0.68), .whiteShell)
                b.torus(itemRoot, .zero, outerRadius: 0.52, thicknessScale: 0.24, .brushedSteel, rotation: Math3D.rotationX(time * 2.2))

            case .armorShard:
                // Sculpted Multi-Plate Ballistic Cuirass Crest
                b.octahedron(itemRoot, .zero, SIMD3<Float>(0.62, 0.76, 0.36), glow)
                b.wedge(itemRoot, SIMD3<Float>(-0.24, 0.12, -0.12), SIMD3<Float>(0.26, 0.44, 0.14), .brushedSteel, rotation: Math3D.rotationZ(0.25))
                b.wedge(itemRoot, SIMD3<Float>( 0.24, 0.12, -0.12), SIMD3<Float>(0.26, 0.44, 0.14), .brushedSteel, rotation: Math3D.rotationY(.pi) * Math3D.rotationZ(0.25))

            case .quadOverdrive:
                // Blazing Star Core + 3 Rapid Gyroscopic Power Rings
                b.octahedron(itemRoot, .zero, SIMD3<Float>(0.52, 0.52, 0.52), .glow(SIMD3<Float>(1, 1, 1), intensity: 2.3))
                b.torus(itemRoot, .zero, outerRadius: 0.52, thicknessScale: 0.28, glow, rotation: Math3D.rotationX(time * 3.5))
                b.torus(itemRoot, .zero, outerRadius: 0.64, thicknessScale: 0.24, glow, rotation: Math3D.rotationY(time * 2.8) * Math3D.rotationZ(0.8))
                b.torus(itemRoot, .zero, outerRadius: 0.76, thicknessScale: 0.20, .glow(SublevelPalette.signalRed, intensity: 1.8), rotation: Math3D.rotationZ(-time * 2.2) * Math3D.rotationX(0.7))

            case .subShield:
                // Geodesic Cobalt Force-Bubble + 6 Orbiting Emitter Nodes
                b.octahedron(itemRoot, .zero, SIMD3<Float>(0.42, 0.42, 0.42), glow)
                b.sphere(itemRoot, .zero, SIMD3<Float>(repeating: 0.88), .energyField(col, intensity: 1.85, alpha: 0.68))
                for n in 0..<6 {
                    let a = Float(n) * (.pi / 3.0) + time
                    b.octahedron(itemRoot, SIMD3<Float>(cos(a) * 0.54, sin(a * 2.0) * 0.14, sin(a) * 0.54), SIMD3<Float>(0.14, 0.14, 0.14), .whiteShell)
                }

            case .ammoPack:
                // Dual Electric-Cyan Plasma Cells in Machined Battery Carrier
                b.box(itemRoot, .zero, SIMD3<Float>(0.52, 0.18, 0.34), .gunmetal)
                for sx: Float in [-0.14, 0.14] {
                    b.cylinder(itemRoot, SIMD3<Float>(sx, 0.08, 0), radius: 0.10, length: 0.48, glow, rotation: Math3D.rotationX(quarterTurn))
                    b.torus(itemRoot, SIMD3<Float>(sx, 0.30, 0), outerRadius: 0.11, thicknessScale: 0.5, .brushedSteel, rotation: Math3D.rotationX(quarterTurn))
                }
            }
        }

        // 9. Tumbling 3D Breach Debris Shards
        for shard in debris {
            let fade = simd_clamp(shard.lifetime / max(shard.maxLifetime, 0.01), 0.0, 1.0)
            let rot = Math3D.rotationX(shard.angles.x) * Math3D.rotationY(shard.angles.y) * Math3D.rotationZ(shard.angles.z)
            let root = Math3D.translation(shard.position) * rot
            if shard.isGlass {
                b.sharpBox(root, .zero, shard.size, .holoGlass(shard.color, alpha: 0.62 * fade))
            } else {
                b.octahedron(root, .zero, shard.size * 1.25, .arch(shard.color, roughness: 0.25, metallic: 0.2, emissive: 0.25 * fade))
            }
        }
    }
}
