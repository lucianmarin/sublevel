import Foundation
import Metal
import MetalKit
import simd

public struct GPUVertex {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var uvAndEdge: SIMD3<Float> // (u, v, edgeFactor)

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, uvAndEdge: SIMD3<Float>) {
        self.position = position
        self.normal = normal
        self.uvAndEdge = uvAndEdge
    }
}

public struct GPUPointLight {
    public var positionAndRadius: SIMD4<Float>
    public var colorAndIntensity: SIMD4<Float>
}

public struct GPUSceneUniforms {
    public var viewProjMatrix: simd_float4x4
    public var cameraPosition: SIMD4<Float>
    public var sunDirection: SIMD4<Float>
    public var timeAndLightCount: SIMD4<Float> // x = time, y = lightCount, z = quadOverdrive, w = subShield
    public var lights: (
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight
    )
}

public struct GPUInstanceData {
    public var modelMatrix: simd_float4x4
    public var boxCenterAndKind: SIMD4<Float>   // xyz = center, w = shaderMode (0=arch, 1=silhouette, 2=shockSphere, 3=unlitEmissive)
    public var boxHalfExtents: SIMD4<Float>     // xyz = halfSize, w = progress/pulse
    public var colorAndRoughness: SIMD4<Float>  // rgb = albedo, w = roughness
    public var materialParams: SIMD4<Float>     // x = metallic, y = emissive, z = alpha, w = unused
}

public final class MetalArenaRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var opaquePipeline: MTLRenderPipelineState!
    private var translucentPipeline: MTLRenderPipelineState!
    private var depthStencilOpaque: MTLDepthStencilState!
    private var depthStencilTranslucent: MTLDepthStencilState!

    private var cubeVertexBuffer: MTLBuffer!
    private var cubeVertexCount: Int = 0
    private var sphereVertexBuffer: MTLBuffer!
    private var sphereVertexCount: Int = 0

    public let simulation: SublevelSimulation
    public let audioEngine: AudioSynthEngine
    public var onFrameUpdated: (() -> Void)?

    // Input state polled each frame
    public var keysHeld: Set<UInt16> = []
    public var jumpJustPressed: Bool = false
    public var dodgeRequested: Bool = false
    public var dodgeDirectionLocal: SIMD2<Float> = .zero
    public var primaryFireHeld: Bool = false
    public var altFireHeld: Bool = false
    public var altFireJustReleased: Bool = false

    private var lastFrameTimestamp: CFTimeInterval = CACurrentMediaTime()

    public init?(mtkView: MTKView, simulation: SublevelSimulation, audioEngine: AudioSynthEngine) {
        guard let dev = mtkView.device ?? MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else {
            return nil
        }
        self.device = dev
        self.commandQueue = queue
        self.simulation = simulation
        self.audioEngine = audioEngine
        super.init()

        mtkView.device = dev
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.sampleCount = 4
        mtkView.preferredFramesPerSecond = 120
        mtkView.clearColor = MTLClearColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1.0)

        buildMeshes()
        buildPipelines(mtkView: mtkView)
    }

    private func buildMeshes() {
        let cubeVerts = Self.makeUnitCubeVertices()
        cubeVertexCount = cubeVerts.count
        cubeVertexBuffer = device.makeBuffer(
            bytes: cubeVerts,
            length: MemoryLayout<GPUVertex>.stride * cubeVerts.count,
            options: .storageModeShared
        )

        let sphereVerts = Self.makeUnitSphereVertices(latSegments: 16, lonSegments: 24)
        sphereVertexCount = sphereVerts.count
        sphereVertexBuffer = device.makeBuffer(
            bytes: sphereVerts,
            length: MemoryLayout<GPUVertex>.stride * sphereVerts.count,
            options: .storageModeShared
        )
    }

    private func buildPipelines(mtkView: MTKView) {
        let library = try! device.makeLibrary(source: Self.metalShaderSource, options: nil)
        let vertexFn = library.makeFunction(name: "sublevel_vertex")!
        let fragmentFn = library.makeFunction(name: "sublevel_fragment")!

        let opaqueDesc = MTLRenderPipelineDescriptor()
        opaqueDesc.vertexFunction = vertexFn
        opaqueDesc.fragmentFunction = fragmentFn
        opaqueDesc.rasterSampleCount = mtkView.sampleCount
        opaqueDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        opaqueDesc.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        opaquePipeline = try! device.makeRenderPipelineState(descriptor: opaqueDesc)

        let transDesc = MTLRenderPipelineDescriptor()
        transDesc.vertexFunction = vertexFn
        transDesc.fragmentFunction = fragmentFn
        transDesc.rasterSampleCount = mtkView.sampleCount
        transDesc.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        if let att = transDesc.colorAttachments[0] {
            att.pixelFormat = mtkView.colorPixelFormat
            att.isBlendingEnabled = true
            att.sourceRGBBlendFactor = .sourceAlpha
            att.destinationRGBBlendFactor = .oneMinusSourceAlpha
            att.rgbBlendOperation = .add
            att.sourceAlphaBlendFactor = .one
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            att.alphaBlendOperation = .add
        }
        translucentPipeline = try! device.makeRenderPipelineState(descriptor: transDesc)

        let depthOpaqueDesc = MTLDepthStencilDescriptor()
        depthOpaqueDesc.depthCompareFunction = .lessEqual
        depthOpaqueDesc.isDepthWriteEnabled = true
        depthStencilOpaque = device.makeDepthStencilState(descriptor: depthOpaqueDesc)

        let depthTransDesc = MTLDepthStencilDescriptor()
        depthTransDesc.depthCompareFunction = .lessEqual
        depthTransDesc.isDepthWriteEnabled = false
        depthStencilTranslucent = device.makeDepthStencilState(descriptor: depthTransDesc)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(max(now - lastFrameTimestamp, 1.0 / 240.0), 0.05))
        lastFrameTimestamp = now

        // 1. Sample keyboard movement input & step simulation
        var moveInput = MovementInput()
        // W = 13, S = 1, A = 0, D = 2, Space = 49, C/Ctrl = 8/59, Shift/V = 56/9
        if keysHeld.contains(13) || keysHeld.contains(126) { moveInput.moveForward += 1.0 }
        if keysHeld.contains(1)  || keysHeld.contains(125) { moveInput.moveForward -= 1.0 }
        if keysHeld.contains(2)  || keysHeld.contains(124) { moveInput.moveRight += 1.0 }
        if keysHeld.contains(0)  || keysHeld.contains(123) { moveInput.moveRight -= 1.0 }
        moveInput.jumpHeld = keysHeld.contains(49)
        moveInput.jumpJustPressed = jumpJustPressed
        moveInput.crouchHeld = keysHeld.contains(8) || keysHeld.contains(59)
        moveInput.dodgeRequested = dodgeRequested
        moveInput.dodgeDirectionLocal = dodgeDirectionLocal

        jumpJustPressed = false
        dodgeRequested = false
        let releasedAlt = altFireJustReleased
        altFireJustReleased = false

        simulation.update(
            input: moveInput,
            primaryFireHeld: primaryFireHeld,
            altFireHeld: altFireHeld,
            altFireJustReleased: releasedAlt,
            delta: dt
        )

        // Dispatch procedural synth audio & dynamic B1/B2/B3 reverb
        audioEngine.updateStratumReverb(simulation.playerStratum)
        for snd in simulation.pendingSounds {
            audioEngine.play(snd)
        }
        simulation.pendingSounds.removeAll()

        onFrameUpdated?()

        // 2. Render Frame via Metal
        guard let passDesc = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            return
        }

        let aspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1.0))
        encodeWorldAndViewmodel(encoder: encoder, aspect: aspect)

        encoder.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    private func encodeWorldAndViewmodel(encoder: MTLRenderCommandEncoder, aspect: Float) {
        let eye = simulation.playerKinematic.eyePosition + SIMD3<Float>(
            0,
            simulation.cameraFX.landingPunchOffset + sin(simulation.cameraFX.bobPhase) * 0.035,
            0
        )
        let pitchWithRecoil = simd_clamp(simulation.playerPitch + simulation.cameraFX.recoilPitch, -1.48, 1.48)
        let cosPitch = cos(pitchWithRecoil)
        let lookDir = simd_normalize(SIMD3<Float>(
            -sin(simulation.playerYaw) * cosPitch,
            sin(pitchWithRecoil),
            -cos(simulation.playerYaw) * cosPitch
        ))

        let fovRad = simulation.cameraFX.currentFOVDegrees * (.pi / 180.0)
        let proj = Math3D.perspective(fovYRadians: fovRad, aspect: aspect, nearZ: 0.12, farZ: 240.0)
        let rollMat = Math3D.rotationZ(simulation.cameraFX.rollAngleRadians)
        let viewMat = rollMat * Math3D.lookAt(eye: eye, target: eye + lookDir, up: SIMD3<Float>(0, 1, 0))
        var sceneUniforms = buildSceneUniforms(viewProj: proj * viewMat, eye: eye)

        var opaqueCubes: [GPUInstanceData] = []
        var translucentCubes: [GPUInstanceData] = []
        var sphereInstances: [GPUInstanceData] = []

        // A. Arena Colliders (Brutalist geometry + kinetic panels + shatter skylights)
        for box in simulation.arena.colliders where !box.isDestroyed {
            let center = box.center
            let size = box.size
            let model = Math3D.translation(center) * Math3D.scale(size)
            let isGlass = (box.kind == .shatterFloor)
            let inst = GPUInstanceData(
                modelMatrix: model,
                boxCenterAndKind: SIMD4<Float>(center.x, center.y, center.z, 0.0),
                boxHalfExtents: SIMD4<Float>(size.x * 0.5, size.y * 0.5, size.z * 0.5, Float(box.kind.rawValue)),
                colorAndRoughness: SIMD4<Float>(box.color.x, box.color.y, box.color.z, box.roughness),
                materialParams: SIMD4<Float>(box.metallic, box.emissiveStrength, isGlass ? 0.58 : 1.0, 0.0)
            )
            if isGlass {
                translucentCubes.append(inst)
            } else {
                opaqueCubes.append(inst)
            }
        }

        // B. Jump Pads (Signal Red glowing chevrons) & Teleporters (Cobalt Blue portals)
        let pulse = 0.65 + 0.35 * sin(simulation.elapsedMatchTime * 5.0)
        for pad in simulation.arena.jumpPads {
            let size = SIMD3<Float>(pad.radius * 1.65, 0.24, pad.radius * 1.65)
            let model = Math3D.translation(pad.position) * Math3D.scale(size)
            opaqueCubes.append(GPUInstanceData(
                modelMatrix: model,
                boxCenterAndKind: SIMD4<Float>(pad.position.x, pad.position.y, pad.position.z, 0.0),
                boxHalfExtents: SIMD4<Float>(size.x * 0.5, size.y * 0.5, size.z * 0.5, 1.0),
                colorAndRoughness: SIMD4<Float>(SublevelPalette.signalRed.x, SublevelPalette.signalRed.y, SublevelPalette.signalRed.z, 0.12),
                materialParams: SIMD4<Float>(0.2, 0.85 * pulse, 1.0, 0.0)
            ))
        }

        for tp in simulation.arena.teleporters {
            let pos = tp.position + SIMD3<Float>(0, 1.2, 0)
            let size = SIMD3<Float>(1.8, 2.4, 0.35)
            let model = Math3D.translation(pos) * Math3D.scale(size)
            translucentCubes.append(GPUInstanceData(
                modelMatrix: model,
                boxCenterAndKind: SIMD4<Float>(pos.x, pos.y, pos.z, 3.0),
                boxHalfExtents: SIMD4<Float>(size.x * 0.5, size.y * 0.5, size.z * 0.5, pulse),
                colorAndRoughness: SIMD4<Float>(SublevelPalette.cobaltBlue.x, SublevelPalette.cobaltBlue.y, SublevelPalette.cobaltBlue.z, 0.05),
                materialParams: SIMD4<Float>(0.5, 1.25, 0.72, 0.0)
            ))
        }

        // C. Pickups (Rotating Amber Gold / Cobalt Blue octahedrons/cubes)
        for pickup in simulation.arena.pickups where pickup.isActive {
            let bobY = sin(simulation.elapsedMatchTime * 3.2 + Float(pickup.id)) * 0.18
            let pos = pickup.position + SIMD3<Float>(0, bobY, 0)
            let size = SIMD3<Float>(0.72, 0.72, 0.72)
            let model = Math3D.translation(pos) * Math3D.rotationY(pickup.rotationAngle) * Math3D.rotationX(0.6) * Math3D.scale(size)
            let col = pickup.kind.color
            opaqueCubes.append(GPUInstanceData(
                modelMatrix: model,
                boxCenterAndKind: SIMD4<Float>(pos.x, pos.y, pos.z, 3.0),
                boxHalfExtents: SIMD4<Float>(0.36, 0.36, 0.36, 1.0),
                colorAndRoughness: SIMD4<Float>(col.x, col.y, col.z, 0.10),
                materialParams: SIMD4<Float>(0.6, 1.15, 1.0, 0.0)
            ))
        }

        // D. Enemy Bots (`player_silhouette` shader mode = 1.0 with Fresnel rim + high-contrast team color)
        for bot in simulation.bots where bot.isAlive {
            let base = bot.kinematic.position
            let col = bot.hitFlashTimer > 0 ? SIMD3<Float>(1, 1, 1) : bot.teamColor
            let rot = Math3D.rotationY(bot.yaw)

            // Torso
            let torsoPos = base + SIMD3<Float>(0, 0.95, 0)
            let torsoSize = SIMD3<Float>(0.72, 1.05, 0.44)
            opaqueCubes.append(GPUInstanceData(
                modelMatrix: Math3D.translation(torsoPos) * rot * Math3D.scale(torsoSize),
                boxCenterAndKind: SIMD4<Float>(torsoPos.x, torsoPos.y, torsoPos.z, 1.0),
                boxHalfExtents: SIMD4<Float>(torsoSize.x * 0.5, torsoSize.y * 0.5, torsoSize.z * 0.5, 0.0),
                colorAndRoughness: SIMD4<Float>(col.x, col.y, col.z, 0.2),
                materialParams: SIMD4<Float>(0.1, 0.85, 1.0, 0.0)
            ))
            // Head
            let headPos = base + SIMD3<Float>(0, 1.68, 0)
            let headSize = SIMD3<Float>(0.42, 0.42, 0.42)
            opaqueCubes.append(GPUInstanceData(
                modelMatrix: Math3D.translation(headPos) * rot * Math3D.scale(headSize),
                boxCenterAndKind: SIMD4<Float>(headPos.x, headPos.y, headPos.z, 1.0),
                boxHalfExtents: SIMD4<Float>(0.21, 0.21, 0.21, 0.0),
                colorAndRoughness: SIMD4<Float>(col.x, col.y, col.z, 0.15),
                materialParams: SIMD4<Float>(0.2, 1.1, 1.0, 0.0)
            ))
        }

        // E. Active Projectiles & Beams
        for proj in simulation.projectiles {
            let radius: Float = (proj.kind == .shockOrb) ? 0.58 : (proj.kind == .vectorRocket ? 0.26 : 0.16)
            let scaleVec = SIMD3<Float>(repeating: radius * 2.0)
            sphereInstances.append(GPUInstanceData(
                modelMatrix: Math3D.translation(proj.position) * Math3D.scale(scaleVec),
                boxCenterAndKind: SIMD4<Float>(proj.position.x, proj.position.y, proj.position.z, 2.0),
                boxHalfExtents: SIMD4<Float>(radius, radius, radius, 0.25),
                colorAndRoughness: SIMD4<Float>(proj.color.x, proj.color.y, proj.color.z, 0.05),
                materialParams: SIMD4<Float>(0.0, 1.6, 0.92, 0.0)
            ))
        }

        for beam in simulation.beams {
            let delta = beam.end - beam.start
            let len = simd_length(delta)
            guard len > 0.05 else { continue }
            let mid = (beam.start + beam.end) * 0.5
            let forward = delta / len
            let upRef: SIMD3<Float> = abs(forward.y) > 0.95 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            let right = simd_normalize(simd_cross(forward, upRef))
            let up = simd_cross(right, forward)
            let rotMat = simd_float4x4(columns: (
                SIMD4<Float>(right.x, right.y, right.z, 0),
                SIMD4<Float>(up.x, up.y, up.z, 0),
                SIMD4<Float>(forward.x, forward.y, forward.z, 0),
                SIMD4<Float>(0, 0, 0, 1)
            ))
            let alpha = simd_clamp(beam.remainingLife / max(beam.maxLife, 0.01), 0.0, 1.0)
            let model = Math3D.translation(mid) * rotMat * Math3D.scale(SIMD3<Float>(beam.thickness, beam.thickness, len))
            translucentCubes.append(GPUInstanceData(
                modelMatrix: model,
                boxCenterAndKind: SIMD4<Float>(mid.x, mid.y, mid.z, 3.0),
                boxHalfExtents: SIMD4<Float>(beam.thickness, beam.thickness, len * 0.5, 1.0),
                colorAndRoughness: SIMD4<Float>(beam.color.x, beam.color.y, beam.color.z, 0.0),
                materialParams: SIMD4<Float>(0.0, 1.8, alpha, 0.0)
            ))
        }

        // F. Shock Combo & Explosion Volumetric Spheres (`shock_sphere.gdshader` equivalent)
        for sphere in simulation.shockSpheres {
            let r = max(sphere.currentRadius, 0.1)
            let scaleVec = SIMD3<Float>(repeating: r * 2.0)
            let alpha = (1.0 - sphere.progress) * (sphere.isShockCombo ? 0.88 : 0.68)
            sphereInstances.append(GPUInstanceData(
                modelMatrix: Math3D.translation(sphere.center) * Math3D.scale(scaleVec),
                boxCenterAndKind: SIMD4<Float>(sphere.center.x, sphere.center.y, sphere.center.z, 2.0),
                boxHalfExtents: SIMD4<Float>(r, r, r, sphere.progress),
                colorAndRoughness: SIMD4<Float>(sphere.color.x, sphere.color.y, sphere.color.z, 0.0),
                materialParams: SIMD4<Float>(0.0, sphere.isShockCombo ? 2.2 : 1.4, alpha, 0.0)
            ))
        }

        // Encode Opaque Pass
        encoder.setRenderPipelineState(opaquePipeline)
        encoder.setDepthStencilState(depthStencilOpaque)
        encoder.setVertexBytes(&sceneUniforms, length: MemoryLayout<GPUSceneUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&sceneUniforms, length: MemoryLayout<GPUSceneUniforms>.stride, index: 1)

        drawInstanced(encoder: encoder, vertexBuffer: cubeVertexBuffer, vertexCount: cubeVertexCount, instances: opaqueCubes)

        // Encode Translucent Pass (Skylights, Beams, Shock Spheres)
        encoder.setRenderPipelineState(translucentPipeline)
        encoder.setDepthStencilState(depthStencilTranslucent)
        drawInstanced(encoder: encoder, vertexBuffer: cubeVertexBuffer, vertexCount: cubeVertexCount, instances: translucentCubes)
        drawInstanced(encoder: encoder, vertexBuffer: sphereVertexBuffer, vertexCount: sphereVertexCount, instances: sphereInstances)

        // G. First-Person Viewmodel Pass (FOV 75°, rendered in view space with near depth range so weapon never clips walls)
        encodeViewmodelPass(encoder: encoder, aspect: aspect, baseSceneUniforms: sceneUniforms)
    }

    private func encodeViewmodelPass(
        encoder: MTLRenderCommandEncoder,
        aspect: Float,
        baseSceneUniforms: GPUSceneUniforms
    ) {
        guard !simulation.isSubRailZoomed else { return }

        var vmUniforms = baseSceneUniforms
        // Viewmodel Camera uses 75° FOV per README Section 7
        vmUniforms.viewProjMatrix = Math3D.perspective(fovYRadians: 75.0 * (.pi / 180.0), aspect: aspect, nearZ: 0.02, farZ: 10.0)
        vmUniforms.cameraPosition = SIMD4<Float>(0, 0, 0, 1)

        let bobX = cos(simulation.cameraFX.bobPhase) * 0.014
        let bobY = abs(sin(simulation.cameraFX.bobPhase)) * -0.016
        let kickZ = simulation.weaponSwingOffset * 0.085
        let kickPitch = simulation.weaponSwingOffset * 0.16
        let accent = simulation.currentWeapon.accentColor

        let mountPos = SIMD3<Float>(0.26 + bobX, -0.24 + bobY, -0.48 + kickZ)
        let mountRot = Math3D.rotationX(kickPitch) * Math3D.rotationZ(simulation.cameraFX.rollAngleRadians * 0.5)

        // Receiver body (Stark White brutalist chassis)
        let bodyModel = Math3D.translation(mountPos) * mountRot * Math3D.scale(SIMD3<Float>(0.11, 0.13, 0.44))
        // Glowing weapon core / barrel rails
        let railModel = Math3D.translation(mountPos + SIMD3<Float>(0, 0.045, -0.08)) * mountRot * Math3D.scale(SIMD3<Float>(0.125, 0.045, 0.48))

        var vmInstances: [GPUInstanceData] = [
            GPUInstanceData(
                modelMatrix: bodyModel,
                boxCenterAndKind: SIMD4<Float>(mountPos.x, mountPos.y, mountPos.z, 0.0),
                boxHalfExtents: SIMD4<Float>(0.055, 0.065, 0.22, 0.0),
                colorAndRoughness: SIMD4<Float>(0.92, 0.93, 0.95, 0.25),
                materialParams: SIMD4<Float>(0.2, 0.1, 1.0, 0.0)
            ),
            GPUInstanceData(
                modelMatrix: railModel,
                boxCenterAndKind: SIMD4<Float>(mountPos.x, mountPos.y, mountPos.z, 3.0),
                boxHalfExtents: SIMD4<Float>(0.062, 0.022, 0.24, 1.0),
                colorAndRoughness: SIMD4<Float>(accent.x, accent.y, accent.z, 0.10),
                materialParams: SIMD4<Float>(0.4, 1.35 + simulation.weaponSwingOffset * 0.8, 1.0, 0.0)
            )
        ]

        // Vector Launcher multi-rocket charge pips on top of weapon
        if simulation.currentWeapon == .vectorLauncher && simulation.rocketChargeCount > 0 {
            for c in 0..<simulation.rocketChargeCount {
                let pipPos = mountPos + SIMD3<Float>(-0.04 + Float(c) * 0.04, 0.09, -0.05)
                let pipModel = Math3D.translation(pipPos) * Math3D.scale(SIMD3<Float>(0.028, 0.028, 0.06))
                vmInstances.append(GPUInstanceData(
                    modelMatrix: pipModel,
                    boxCenterAndKind: SIMD4<Float>(pipPos.x, pipPos.y, pipPos.z, 3.0),
                    boxHalfExtents: SIMD4<Float>(0.014, 0.014, 0.03, 1.0),
                    colorAndRoughness: SIMD4<Float>(1.0, 0.8, 0.1, 0.05),
                    materialParams: SIMD4<Float>(0.0, 1.9, 1.0, 0.0)
                ))
            }
        }

        encoder.setRenderPipelineState(opaquePipeline)
        encoder.setDepthStencilState(depthStencilTranslucent)
        encoder.setVertexBytes(&vmUniforms, length: MemoryLayout<GPUSceneUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&vmUniforms, length: MemoryLayout<GPUSceneUniforms>.stride, index: 1)
        drawInstanced(encoder: encoder, vertexBuffer: cubeVertexBuffer, vertexCount: cubeVertexCount, instances: vmInstances)
    }

    private func drawInstanced(
        encoder: MTLRenderCommandEncoder,
        vertexBuffer: MTLBuffer,
        vertexCount: Int,
        instances: [GPUInstanceData]
    ) {
        guard !instances.isEmpty else { return }
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        let chunkSize = 64
        var offset = 0
        while offset < instances.count {
            let end = min(offset + chunkSize, instances.count)
            var slice = Array(instances[offset..<end])
            encoder.setVertexBytes(&slice, length: MemoryLayout<GPUInstanceData>.stride * slice.count, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount, instanceCount: slice.count)
            offset = end
        }
    }

    private func buildSceneUniforms(viewProj: simd_float4x4, eye: SIMD3<Float>) -> GPUSceneUniforms {
        let emptyLight = GPUPointLight(positionAndRadius: .zero, colorAndIntensity: .zero)
        var lightArray = Array(repeating: emptyLight, count: 16)
        var count = 0

        // Static GI Radiosity bounce lights (B1 White Skylight, B2 Signal Red, B3 Cobalt Blue & Amber Gold)
        for l in simulation.arena.staticLights where count < 16 {
            lightArray[count] = GPUPointLight(
                positionAndRadius: SIMD4<Float>(l.position.x, l.position.y, l.position.z, l.radius),
                colorAndIntensity: SIMD4<Float>(l.color.x, l.color.y, l.color.z, l.intensity)
            )
            count += 1
        }

        // Dynamic projectile & Shock Combo emissive flashes onto white walls (Section 2.3)
        for sphere in simulation.shockSpheres where count < 16 {
            lightArray[count] = GPUPointLight(
                positionAndRadius: SIMD4<Float>(sphere.center.x, sphere.center.y, sphere.center.z, sphere.maxRadius * 3.2),
                colorAndIntensity: SIMD4<Float>(sphere.color.x, sphere.color.y, sphere.color.z, (1.0 - sphere.progress) * 3.8)
            )
            count += 1
        }
        for proj in simulation.projectiles where count < 16 {
            lightArray[count] = GPUPointLight(
                positionAndRadius: SIMD4<Float>(proj.position.x, proj.position.y, proj.position.z, 11.0),
                colorAndIntensity: SIMD4<Float>(proj.color.x, proj.color.y, proj.color.z, 1.8)
            )
            count += 1
        }

        return GPUSceneUniforms(
            viewProjMatrix: viewProj,
            cameraPosition: SIMD4<Float>(eye.x, eye.y, eye.z, 1.0),
            sunDirection: SIMD4<Float>(simd_normalize(SIMD3<Float>(0.24, 0.92, -0.28)), 0.0),
            timeAndLightCount: SIMD4<Float>(
                simulation.elapsedMatchTime,
                Float(count),
                simulation.quadOverdriveTimer > 0 ? 1.0 : 0.0,
                simulation.subShieldTimer > 0 ? 1.0 : 0.0
            ),
            lights: (
                lightArray[0], lightArray[1], lightArray[2], lightArray[3],
                lightArray[4], lightArray[5], lightArray[6], lightArray[7],
                lightArray[8], lightArray[9], lightArray[10], lightArray[11],
                lightArray[12], lightArray[13], lightArray[14], lightArray[15]
            )
        )
    }

    // MARK: - Procedural Primitives

    private static func makeUnitCubeVertices() -> [GPUVertex] {
        let faces: [(normal: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>)] = [
            (SIMD3<Float>( 0,  1,  0), SIMD3<Float>( 1, 0, 0), SIMD3<Float>(0, 0,  1)),
            (SIMD3<Float>( 0, -1,  0), SIMD3<Float>( 1, 0, 0), SIMD3<Float>(0, 0, -1)),
            (SIMD3<Float>( 1,  0,  0), SIMD3<Float>( 0, 0, -1), SIMD3<Float>(0, 1, 0)),
            (SIMD3<Float>(-1,  0,  0), SIMD3<Float>( 0, 0,  1), SIMD3<Float>(0, 1, 0)),
            (SIMD3<Float>( 0,  0,  1), SIMD3<Float>( 1, 0, 0), SIMD3<Float>(0, 1,  0)),
            (SIMD3<Float>( 0,  0, -1), SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 1,  0))
        ]
        var verts: [GPUVertex] = []
        let quadUVs: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1),
            SIMD2<Float>(0, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1)
        ]
        for f in faces {
            for uv in quadUVs {
                let su = (uv.x - 0.5)
                let sv = (uv.y - 0.5)
                let pos = f.normal * 0.5 + f.u * su + f.v * sv
                verts.append(GPUVertex(position: pos, normal: f.normal, uvAndEdge: SIMD3<Float>(uv.x, uv.y, 1.0)))
            }
        }
        return verts
    }

    private static func makeUnitSphereVertices(latSegments: Int, lonSegments: Int) -> [GPUVertex] {
        var verts: [GPUVertex] = []
        for i in 0..<latSegments {
            let theta1 = Float(i) * .pi / Float(latSegments)
            let theta2 = Float(i + 1) * .pi / Float(latSegments)
            for j in 0..<lonSegments {
                let phi1 = Float(j) * 2.0 * .pi / Float(lonSegments)
                let phi2 = Float(j + 1) * 2.0 * .pi / Float(lonSegments)

                let p1 = spherePoint(theta1, phi1)
                let p2 = spherePoint(theta2, phi1)
                let p3 = spherePoint(theta2, phi2)
                let p4 = spherePoint(theta1, phi2)

                verts.append(GPUVertex(position: p1 * 0.5, normal: p1, uvAndEdge: SIMD3<Float>(0, 0, 0)))
                verts.append(GPUVertex(position: p2 * 0.5, normal: p2, uvAndEdge: SIMD3<Float>(0, 1, 0)))
                verts.append(GPUVertex(position: p3 * 0.5, normal: p3, uvAndEdge: SIMD3<Float>(1, 1, 0)))

                verts.append(GPUVertex(position: p1 * 0.5, normal: p1, uvAndEdge: SIMD3<Float>(0, 0, 0)))
                verts.append(GPUVertex(position: p3 * 0.5, normal: p3, uvAndEdge: SIMD3<Float>(1, 1, 0)))
                verts.append(GPUVertex(position: p4 * 0.5, normal: p4, uvAndEdge: SIMD3<Float>(1, 0, 0)))
            }
        }
        return verts
    }

    private static func spherePoint(_ theta: Float, _ phi: Float) -> SIMD3<Float> {
        SIMD3<Float>(
            sin(theta) * cos(phi),
            cos(theta),
            sin(theta) * sin(phi)
        )
    }

    // MARK: - Unified Metal Shader Library (`arch_surface`, `player_silhouette`, `shock_sphere`)

    private static let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct GPUVertex {
        float3 position;
        float3 normal;
        float3 uvAndEdge;
    };

    struct GPUPointLight {
        float4 positionAndRadius;
        float4 colorAndIntensity;
    };

    struct GPUSceneUniforms {
        float4x4 viewProjMatrix;
        float4 cameraPosition;
        float4 sunDirection;
        float4 timeAndLightCount;
        GPUPointLight lights[16];
    };

    struct GPUInstanceData {
        float4x4 modelMatrix;
        float4 boxCenterAndKind;
        float4 boxHalfExtents;
        float4 colorAndRoughness;
        float4 materialParams;
    };

    struct Varyings {
        float4 position [[position]];
        float3 worldPos;
        float3 localPos;
        float3 worldNormal;
        float3 boxCenter;
        float3 boxHalfExtents;
        float4 colorAndRoughness;
        float4 materialParams;
        float shaderMode;
        float extraParam;
    };

    // Procedural 3D value noise for triplanar micro-detail (0.015 normal strength per README 2.1)
    float hash31(float3 p) {
        p = fract(p * 0.1031);
        p += dot(p, p.yzx + 33.33);
        return fract((p.x + p.y) * p.z);
    }

    float noise3D(float3 p) {
        float3 i = floor(p);
        float3 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(
            mix(mix(hash31(i + float3(0,0,0)), hash31(i + float3(1,0,0)), f.x),
                mix(hash31(i + float3(0,1,0)), hash31(i + float3(1,1,0)), f.x), f.y),
            mix(mix(hash31(i + float3(0,0,1)), hash31(i + float3(1,0,1)), f.x),
                mix(hash31(i + float3(0,1,1)), hash31(i + float3(1,1,1)), f.x), f.y),
            f.z
        );
    }

    // AgX-inspired high-contrast bright exposure tonemapper (README 2.3)
    float3 tonemapAgX(float3 x) {
        x = max(x, float3(0.0));
        float3 num = x * (x + 0.18);
        float3 den = x * (0.92 * x + 0.52) + 0.14;
        return clamp(pow(num / den, float3(1.0 / 2.15)), 0.0, 1.0);
    }

    vertex Varyings sublevel_vertex(
        uint vid [[vertex_id]],
        uint iid [[instance_id]],
        constant GPUVertex *vertices [[buffer(0)]],
        constant GPUSceneUniforms &scene [[buffer(1)]],
        constant GPUInstanceData *instances [[buffer(2)]]
    ) {
        GPUVertex v = vertices[vid];
        GPUInstanceData inst = instances[iid];

        float4 worldPos4 = inst.modelMatrix * float4(v.position, 1.0);
        float3 worldN = normalize((inst.modelMatrix * float4(v.normal, 0.0)).xyz);

        Varyings out;
        out.position = scene.viewProjMatrix * worldPos4;
        out.worldPos = worldPos4.xyz;
        out.localPos = v.position;
        out.worldNormal = worldN;
        out.boxCenter = inst.boxCenterAndKind.xyz;
        out.shaderMode = inst.boxCenterAndKind.w;
        out.boxHalfExtents = inst.boxHalfExtents.xyz;
        out.extraParam = inst.boxHalfExtents.w;
        out.colorAndRoughness = inst.colorAndRoughness;
        out.materialParams = inst.materialParams;
        return out;
    }

    fragment float4 sublevel_fragment(
        Varyings in [[stage_in]],
        constant GPUSceneUniforms &scene [[buffer(1)]]
    ) {
        float3 V = normalize(scene.cameraPosition.xyz - in.worldPos);
        float3 N = normalize(in.worldNormal);
        float3 baseColor = in.colorAndRoughness.rgb;
        float roughness = clamp(in.colorAndRoughness.w, 0.04, 1.0);
        float emissive = in.materialParams.y;
        float alpha = in.materialParams.z;

        // MODE 1: player_silhouette.gdshader (High-visibility team color + unshaded Fresnel rim light)
        if (in.shaderMode > 0.5 && in.shaderMode < 1.5) {
            float fresnel = pow(1.0 - saturate(dot(N, V)), 2.2);
            float3 rim = float3(1.0, 1.0, 1.0) * fresnel * 1.45;
            float3 lit = baseColor * (0.65 + 0.35 * saturate(dot(N, scene.sunDirection.xyz))) + baseColor * emissive * 0.55 + rim;
            return float4(tonemapAgX(lit), 1.0);
        }

        // MODE 2: shock_sphere.gdshader (Volumetric sphere distortion & Fresnel wave rings for Shock Combos)
        if (in.shaderMode > 1.5 && in.shaderMode < 2.5) {
            float ndotv = abs(dot(N, V));
            float rim = pow(1.0 - ndotv, 1.85);
            float wave = 0.5 + 0.5 * sin(in.worldPos.y * 6.5 - scene.timeAndLightCount.x * 18.0);
            float core = pow(ndotv, 3.0) * 0.45;
            float3 col = baseColor * (rim * 2.4 + core + wave * 0.4) * emissive + float3(rim * 0.65);
            float finalAlpha = clamp(alpha * (rim * 1.15 + 0.28), 0.08, 0.96);
            return float4(tonemapAgX(col), finalAlpha);
        }

        // MODE 3: Pure emissive energy (Beams, Pickups, Teleporters)
        if (in.shaderMode > 2.5) {
            float fresnel = pow(1.0 - abs(dot(N, V)), 2.0);
            float3 col = baseColor * (1.1 + emissive * 0.85) + float3(fresnel * 0.45);
            return float4(tonemapAgX(col), alpha);
        }

        // MODE 0: arch_surface.gdshader (Textureless Triplanar Micro-Normal + Edge Curvature + Radiosity GI)
        // 1. Sub-perceptual procedural world-space micro-normal (0.015 strength per README 2.1)
        float3 sampleP = in.worldPos * 3.8;
        float nx = noise3D(sampleP + float3(0.15, 0, 0)) - noise3D(sampleP - float3(0.15, 0, 0));
        float ny = noise3D(sampleP + float3(0, 0.15, 0)) - noise3D(sampleP - float3(0, 0.15, 0));
        float nz = noise3D(sampleP + float3(0, 0, 0.15)) - noise3D(sampleP - float3(0, 0, 0.15));
        N = normalize(N + float3(nx, ny, nz) * 0.015);

        // 2. Brutalist World-Space Box Edge Bevel Highlighting & Corner AO
        float3 dEdge = abs(in.worldPos - in.boxCenter) - in.boxHalfExtents;
        float3 distToEdge = abs(dEdge);
        // Count how many axes are within 0.09m of a box corner/crease
        float nearX = 1.0 - smoothstep(0.0, 0.11, distToEdge.x);
        float nearY = 1.0 - smoothstep(0.0, 0.11, distToEdge.y);
        float nearZ = 1.0 - smoothstep(0.0, 0.11, distToEdge.z);
        float creaseFactor = saturate((nearX * nearY) + (nearY * nearZ) + (nearX * nearZ));

        // 3. Stratum Elevation Radiosity & Sun Skylight Illumination
        float3 Lsun = normalize(scene.sunDirection.xyz);
        float sunNdotL = saturate(dot(N, Lsun));
        // Skylight reaches B1 strongly, B2 moderately, B3 dimly
        float skyVisibility = smoothstep(-14.0, 16.0, in.worldPos.y);
        float3 ambientSky = mix(float3(0.20, 0.25, 0.36), float3(0.84, 0.87, 0.92), skyVisibility);

        // 4. Accumulate Static Radiosity Bounce Lights + Dynamic Projectile Emissives (2.0+ GI bounce look)
        int lightCount = int(scene.timeAndLightCount.y);
        float3 giRadiosity = float3(0.0);
        float3 specularSum = float3(0.0);

        for (int i = 0; i < lightCount; ++i) {
            float3 lPos = scene.lights[i].positionAndRadius.xyz;
            float lRad = max(scene.lights[i].positionAndRadius.w, 0.5);
            float3 lCol = scene.lights[i].colorAndIntensity.rgb;
            float lInt = scene.lights[i].colorAndIntensity.w;

            float3 toL = lPos - in.worldPos;
            float dist = length(toL);
            if (dist < lRad) {
                float3 L = toL / max(dist, 0.001);
                float atten = pow(1.0 - dist / lRad, 1.75) * lInt;
                // Wrap diffuse (0.45 wrap) simulates multi-bounce Mirror's Edge radiosity bleeding onto white walls
                float wrapDiff = saturate((dot(N, L) + 0.45) / 1.45);
                giRadiosity += lCol * wrapDiff * atten * 0.58;

                // Crisp specular highlight catching micro-detail
                float3 H = normalize(L + V);
                float specPow = mix(96.0, 14.0, roughness);
                float spec = pow(saturate(dot(N, H)), specPow) * (1.0 - roughness * 0.7);
                specularSum += lCol * spec * atten * 0.35;
            }
        }

        // Sun specular
        float3 Hsun = normalize(Lsun + V);
        float sunSpec = pow(saturate(dot(N, Hsun)), mix(72.0, 12.0, roughness)) * skyVisibility * 0.25;

        // Subtle architectural grid lines every 4m on floors/walls for speed perception
        float3 gridMod = abs(fract(in.worldPos * 0.25 + 0.5) - 0.5) / 0.25;
        float minGrid = min(min(gridMod.x, gridMod.z), gridMod.y);
        float seamDarken = smoothstep(0.0, 0.035, minGrid);

        // Combine Direct + Radiosity GI + Crease AO + Edge Bevel Highlight + Emissive
        float ao = mix(1.0, 0.78, seamDarken < 0.5 ? 1.0 : 0.0) * (1.0 - creaseFactor * 0.14);
        float3 edgeHighlight = float3(0.14) * creaseFactor * (1.0 - roughness * 0.5);

        float3 directSun = float3(1.0, 0.98, 0.95) * sunNdotL * (0.45 + 0.55 * skyVisibility);
        float3 litColor = baseColor * (ambientSky * 0.72 + directSun + giRadiosity) * ao
                        + baseColor * emissive * 0.95
                        + specularSum + sunSpec + edgeHighlight;

        // Distance atmospheric fog in deep B3 Sump abyss
        {
            float depthFog = saturate((-in.worldPos.y - 6.0) / 14.0);
            litColor = mix(litColor, float3(0.02, 0.18, 0.55), depthFog * 0.38);
        }

        return float4(tonemapAgX(litColor), alpha);
    }
    """
}
