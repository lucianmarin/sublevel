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
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight
    )
}

public struct GPUInstanceData {
    public var modelMatrix: simd_float4x4
    public var boxCenterAndKind: SIMD4<Float>   // xyz = center, w = shaderMode (0=arch, 1=silhouette, 2=energyField, 3=emissive, 4=hardware, 5=skyDome)
    public var boxHalfExtents: SIMD4<Float>     // xyz = halfSize, w = progress/pulse
    public var colorAndRoughness: SIMD4<Float>  // rgb = albedo, w = roughness
    public var materialParams: SIMD4<Float>     // x = metallic, y = emissive, z = alpha, w = unused
}

private struct MeshBufferPair {
    let buffer: MTLBuffer
    let vertexCount: Int
    var triangleCount: Int { vertexCount / 3 }
}

private struct StaticInstancedCall {
    let mesh: MeshBufferPair
    let instanceBuffer: MTLBuffer
    let instanceCount: Int
}

public final class MetalArenaRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var opaquePipeline: MTLRenderPipelineState!
    private var translucentPipeline: MTLRenderPipelineState!
    private var depthStencilOpaque: MTLDepthStencilState!
    private var depthStencilTranslucent: MTLDepthStencilState!
    private var depthStencilSky: MTLDepthStencilState!

    // High-polygon procedural mesh library
    private var archBlockMesh: MeshBufferPair!
    private var beveledCubeMesh: MeshBufferPair!
    private var sharpCubeMesh: MeshBufferPair!
    private var wedgeMesh: MeshBufferPair!
    private var cylinderMesh: MeshBufferPair!
    private var tubeMesh: MeshBufferPair!
    private var torusMesh: MeshBufferPair!
    private var coneMesh: MeshBufferPair!
    private var octahedronMesh: MeshBufferPair!
    private var sphereMesh: MeshBufferPair!
    private var skyDomeMesh: MeshBufferPair!

    // Cached GPU buffers for static Mirror's Edge world architecture
    private var staticOpaqueCalls: [StaticInstancedCall] = []
    private var staticTranslucentCalls: [StaticInstancedCall] = []

    // Triple-buffered growable dynamic instance buffers
    private var dynamicInstanceBuffers: [MTLBuffer] = []
    private var frameRingIndex: Int = 0
    private var dynamicWriteByteOffset: Int = 0

    // Telemetry for rendered polygon richness
    public private(set) var lastFrameTriangleCount: Int = 0
    public private(set) var lastFrameInstanceCount: Int = 0

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
        mtkView.clearColor = MTLClearColor(red: 0.88, green: 0.94, blue: 1.0, alpha: 1.0)

        buildMeshes()
        buildStaticWorldBuffers()
        buildDynamicInstancePool()
        buildPipelines(mtkView: mtkView)
    }

    private func makeMeshPair(_ verts: [GPUVertex]) -> MeshBufferPair {
        let buf = device.makeBuffer(
            bytes: verts,
            length: MemoryLayout<GPUVertex>.stride * max(verts.count, 1),
            options: .storageModeShared
        )!
        return MeshBufferPair(buffer: buf, vertexCount: verts.count)
    }

    private func buildMeshes() {
        archBlockMesh   = makeMeshPair(Self.makeRoundedBoxVertices(bevelRadius: 0.022, edgeSteps: 3))
        beveledCubeMesh = makeMeshPair(Self.makeRoundedBoxVertices(bevelRadius: 0.082, edgeSteps: 4))
        sharpCubeMesh   = makeMeshPair(Self.makeUnitCubeVertices())
        wedgeMesh       = makeMeshPair(Self.makeSlopedWedgeVertices(gridSteps: 8))
        cylinderMesh    = makeMeshPair(Self.makeUnitCylinderVertices(segments: 40))
        tubeMesh        = makeMeshPair(Self.makeHollowTubeVertices(segments: 36, innerRatio: 0.66))
        torusMesh       = makeMeshPair(Self.makeUnitTorusVertices(majorSegments: 36, minorSegments: 18))
        coneMesh        = makeMeshPair(Self.makeTaperedConeVertices(segments: 36, tipRatio: 0.08))
        octahedronMesh  = makeMeshPair(Self.makeFacetedOctahedronVertices())
        sphereMesh      = makeMeshPair(Self.makeUnitSphereVertices(latSegments: 28, lonSegments: 42))
        skyDomeMesh     = makeMeshPair(Self.makeUnitSphereVertices(latSegments: 18, lonSegments: 36))
    }

    private func buildStaticWorldBuffers() {
        let staticBatch = ArenaArchitecture.buildStaticArchitecture(arena: simulation.arena)
        let opaquePairs: [(MeshBufferPair, [GPUInstanceData])] = [
            (archBlockMesh, staticBatch.archBlocks),
            (beveledCubeMesh, staticBatch.cubes),
            (sharpCubeMesh, staticBatch.sharpCubes),
            (wedgeMesh, staticBatch.wedges),
            (cylinderMesh, staticBatch.cylinders),
            (tubeMesh, staticBatch.tubes),
            (torusMesh, staticBatch.tori),
            (coneMesh, staticBatch.cones),
            (octahedronMesh, staticBatch.octahedra),
            (sphereMesh, staticBatch.spheres)
        ]
        staticOpaqueCalls = opaquePairs.compactMap { mesh, instances in
            guard !instances.isEmpty,
                  let buf = device.makeBuffer(
                      bytes: instances,
                      length: MemoryLayout<GPUInstanceData>.stride * instances.count,
                      options: .storageModeShared
                  ) else { return nil }
            return StaticInstancedCall(mesh: mesh, instanceBuffer: buf, instanceCount: instances.count)
        }

        let transPairs: [(MeshBufferPair, [GPUInstanceData])] = [
            (sharpCubeMesh, staticBatch.translucentCubes),
            (torusMesh, staticBatch.translucentTori),
            (coneMesh, staticBatch.translucentCones),
            (sphereMesh, staticBatch.translucentSpheres)
        ]
        staticTranslucentCalls = transPairs.compactMap { mesh, instances in
            guard !instances.isEmpty,
                  let buf = device.makeBuffer(
                      bytes: instances,
                      length: MemoryLayout<GPUInstanceData>.stride * instances.count,
                      options: .storageModeShared
                  ) else { return nil }
            return StaticInstancedCall(mesh: mesh, instanceBuffer: buf, instanceCount: instances.count)
        }
    }

    private func buildDynamicInstancePool() {
        let initialBytes = MemoryLayout<GPUInstanceData>.stride * 4096
        dynamicInstanceBuffers = (0..<3).map { _ in
            device.makeBuffer(length: initialBytes, options: .storageModeShared)!
        }
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

        let depthSkyDesc = MTLDepthStencilDescriptor()
        depthSkyDesc.depthCompareFunction = .always
        depthSkyDesc.isDepthWriteEnabled = false
        depthStencilSky = device.makeDepthStencilState(descriptor: depthSkyDesc)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(max(now - lastFrameTimestamp, 1.0 / 240.0), 0.05))
        lastFrameTimestamp = now

        // 1. Sample keyboard movement input & step simulation
        var moveInput = MovementInput()
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

        // 2. Render Frame via Metal
        guard let passDesc = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            onFrameUpdated?()
            return
        }

        frameRingIndex = (frameRingIndex + 1) % dynamicInstanceBuffers.count
        dynamicWriteByteOffset = 0
        lastFrameTriangleCount = 0
        lastFrameInstanceCount = 0

        let aspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1.0))
        encodeWorldAndViewmodel(encoder: encoder, aspect: aspect)

        encoder.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()

        onFrameUpdated?()
    }

    /// Renders the current simulation state offscreen (4x MSAA) and returns PNG data for visual verification.
    public func renderSnapshotPNG(width: Int = 1280, height: Int = 800) -> Data? {
        let msaaDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        msaaDesc.textureType = .type2DMultisample
        msaaDesc.sampleCount = 4
        msaaDesc.storageMode = .private
        msaaDesc.usage = .renderTarget

        let resolveDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        resolveDesc.storageMode = .shared
        resolveDesc.usage = .renderTarget

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        depthDesc.textureType = .type2DMultisample
        depthDesc.sampleCount = 4
        depthDesc.storageMode = .private
        depthDesc.usage = .renderTarget

        guard let msaaTex = device.makeTexture(descriptor: msaaDesc),
              let resolveTex = device.makeTexture(descriptor: resolveDesc),
              let depthTex = device.makeTexture(descriptor: depthDesc),
              let cmdBuf = commandQueue.makeCommandBuffer() else {
            return nil
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaaTex
        pass.colorAttachments[0].resolveTexture = resolveTex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.88, green: 0.94, blue: 1.0, alpha: 1.0)
        pass.depthAttachment.texture = depthTex
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1.0

        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        frameRingIndex = (frameRingIndex + 1) % dynamicInstanceBuffers.count
        dynamicWriteByteOffset = 0
        lastFrameTriangleCount = 0
        lastFrameInstanceCount = 0

        encodeWorldAndViewmodel(encoder: encoder, aspect: Float(width) / Float(height))
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        let bytesPerRow = width * 4
        var bgra = [UInt8](repeating: 0, count: bytesPerRow * height)
        resolveTex.getBytes(&bgra, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bytesPerRow,
            bitsPerPixel: 32
        ), let dst = rep.bitmapData else {
            return nil
        }
        // Swizzle BGRA -> RGBA
        for i in stride(from: 0, to: bgra.count, by: 4) {
            dst[i + 0] = bgra[i + 2]
            dst[i + 1] = bgra[i + 1]
            dst[i + 2] = bgra[i + 0]
            dst[i + 3] = 255
        }
        return rep.representation(using: .png, properties: [:])
    }

    private func encodeWorldAndViewmodel(encoder: MTLRenderCommandEncoder, aspect: Float) {
        let shakeOffset = simulation.cameraFX.breachShake > 0.01
            ? SIMD3<Float>(
                sin(simulation.elapsedMatchTime * 48.0) * simulation.cameraFX.breachShake * 0.08,
                cos(simulation.elapsedMatchTime * 54.0) * simulation.cameraFX.breachShake * 0.08,
                0
            )
            : .zero

        let eye = simulation.playerKinematic.eyePosition + SIMD3<Float>(
            0,
            simulation.cameraFX.landingPunchOffset + sin(simulation.cameraFX.bobPhase) * 0.032,
            0
        ) + shakeOffset

        let pitchWithRecoil = simd_clamp(simulation.playerPitch + simulation.cameraFX.recoilPitch, -1.48, 1.48)
        let cosPitch = cos(pitchWithRecoil)
        let lookDir = simd_normalize(SIMD3<Float>(
            -sin(simulation.playerYaw) * cosPitch,
            sin(pitchWithRecoil),
            -cos(simulation.playerYaw) * cosPitch
        ))

        let fovRad = simulation.cameraFX.currentFOVDegrees * (.pi / 180.0)
        let proj = Math3D.perspective(fovYRadians: fovRad, aspect: aspect, nearZ: 0.12, farZ: 340.0)
        let rollMat = Math3D.rotationZ(simulation.cameraFX.rollAngleRadians)
        let viewMat = rollMat * Math3D.lookAt(eye: eye, target: eye + lookDir, up: SIMD3<Float>(0, 1, 0))
        var sceneUniforms = buildSceneUniforms(viewProj: proj * viewMat, eye: eye)

        encoder.setVertexBytes(&sceneUniforms, length: MemoryLayout<GPUSceneUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&sceneUniforms, length: MemoryLayout<GPUSceneUniforms>.stride, index: 1)

        // 0. Mirror's Edge Luminous Sky Dome Pass (Azure zenith -> sunlit white horizon + solar halo)
        encoder.setRenderPipelineState(opaquePipeline)
        encoder.setDepthStencilState(depthStencilSky)
        let skyInst = GPUInstanceData(
            modelMatrix: Math3D.translation(eye) * Math3D.scale(SIMD3<Float>(repeating: 520.0)),
            boxCenterAndKind: SIMD4<Float>(eye.x, eye.y, eye.z, 5.0),
            boxHalfExtents: SIMD4<Float>(260, 260, 260, 0),
            colorAndRoughness: SIMD4<Float>(1, 1, 1, 1),
            materialParams: SIMD4<Float>(0, 1, 1, 0)
        )
        drawDynamicInstances(encoder: encoder, mesh: skyDomeMesh, instances: [skyInst])

        // 1. Accumulate Dynamic World Batch (Dynamic Lifts, Shuttles, Turbines, Louvers, Portals, Pickups, Debris, Multi-Shape Bots, Projectiles)
        var dynamicBatch = ModelBatch()
        ArenaArchitecture.appendDynamicArchitecture(
            arena: simulation.arena,
            debris: simulation.debrisShards,
            time: simulation.elapsedMatchTime,
            into: &dynamicBatch
        )

        for bot in simulation.bots where bot.isAlive {
            CharacterModels.appendRobot(bot, time: simulation.elapsedMatchTime, into: &dynamicBatch)
        }

        for proj in simulation.projectiles {
            CharacterModels.appendProjectile(proj, time: simulation.elapsedMatchTime, into: &dynamicBatch)
        }

        // Volumetric Energy Beams (Twin core + outer corona cylinder)
        for beam in simulation.beams {
            let len = simd_distance(beam.start, beam.end)
            guard len > 0.05 else { continue }
            let alpha = simd_clamp(beam.remainingLife / max(beam.maxLife, 0.01), 0.0, 1.0)
            let coreSeg = Math3D.segmentTransform(from: beam.start, to: beam.end, width: beam.thickness * 0.65, height: beam.thickness * 0.65)
            let haloSeg = Math3D.segmentTransform(from: beam.start, to: beam.end, width: beam.thickness * 1.65, height: beam.thickness * 1.65)
            let mid = (beam.start + beam.end) * 0.5
            dynamicBatch.translucentCubes.append(GPUInstanceData(
                modelMatrix: coreSeg,
                boxCenterAndKind: SIMD4<Float>(mid.x, mid.y, mid.z, 3.0),
                boxHalfExtents: SIMD4<Float>(100, 100, 100, 1.0),
                colorAndRoughness: SIMD4<Float>(1.0, 1.0, 1.0, 0.0),
                materialParams: SIMD4<Float>(0.0, 2.2, alpha, 0.0)
            ))
            dynamicBatch.translucentCubes.append(GPUInstanceData(
                modelMatrix: haloSeg,
                boxCenterAndKind: SIMD4<Float>(mid.x, mid.y, mid.z, 3.0),
                boxHalfExtents: SIMD4<Float>(100, 100, 100, 1.0),
                colorAndRoughness: SIMD4<Float>(beam.color.x, beam.color.y, beam.color.z, 0.0),
                materialParams: SIMD4<Float>(0.0, 1.85, alpha * 0.62, 0.0)
            ))
        }

        // Shock Combo & Explosion Volumetric Spheres + Shockwave Equatorial Rings
        for sphere in simulation.shockSpheres {
            let r = max(sphere.currentRadius, 0.1)
            let alpha = (1.0 - sphere.progress) * (sphere.isShockCombo ? 0.90 : 0.70)
            dynamicBatch.translucentSpheres.append(GPUInstanceData(
                modelMatrix: Math3D.translation(sphere.center) * Math3D.scale(SIMD3<Float>(repeating: r * 2.0)),
                boxCenterAndKind: SIMD4<Float>(sphere.center.x, sphere.center.y, sphere.center.z, 2.0),
                boxHalfExtents: SIMD4<Float>(r, r, r, sphere.progress),
                colorAndRoughness: SIMD4<Float>(sphere.color.x, sphere.color.y, sphere.color.z, 0.0),
                materialParams: SIMD4<Float>(0.0, sphere.isShockCombo ? 2.4 : 1.5, alpha, 0.0)
            ))
            if sphere.isShockCombo {
                dynamicBatch.translucentTori.append(GPUInstanceData(
                    modelMatrix: Math3D.translation(sphere.center) * Math3D.rotationX(.pi * 0.5) * Math3D.scale(SIMD3<Float>(r * 2.4, r * 2.4, r * 0.35)),
                    boxCenterAndKind: SIMD4<Float>(sphere.center.x, sphere.center.y, sphere.center.z, 3.0),
                    boxHalfExtents: SIMD4<Float>(100, 100, 100, 1.0),
                    colorAndRoughness: SIMD4<Float>(sphere.color.x, sphere.color.y, sphere.color.z, 0.0),
                    materialParams: SIMD4<Float>(0.0, 2.5, alpha * 0.85, 0.0)
                ))
            }
        }

        // 2. Encode Opaque Pass (Cached Static Mirror's Edge Architecture + Dynamic Opaque Meshes)
        encoder.setRenderPipelineState(opaquePipeline)
        encoder.setDepthStencilState(depthStencilOpaque)
        for call in staticOpaqueCalls {
            drawStaticCall(encoder: encoder, call: call)
        }
        drawOpaqueModelBatch(encoder: encoder, batch: dynamicBatch)

        // 3. Encode Translucent Pass (Glass Balustrades, Skylights, Sunbeam Shafts, Portals, Beams, Shock Spheres)
        encoder.setRenderPipelineState(translucentPipeline)
        encoder.setDepthStencilState(depthStencilTranslucent)
        for call in staticTranslucentCalls {
            drawStaticCall(encoder: encoder, call: call)
        }
        drawTranslucentModelBatch(encoder: encoder, batch: dynamicBatch)

        // 4. First-Person Viewmodel Pass (FOV 75°, Runner Hands + Real Weapons + Room Radiosity Bleed)
        encodeViewmodelPass(encoder: encoder, aspect: aspect, viewMatrix: viewMat, baseSceneUniforms: sceneUniforms)
    }

    private func encodeViewmodelPass(
        encoder: MTLRenderCommandEncoder,
        aspect: Float,
        viewMatrix: simd_float4x4,
        baseSceneUniforms: GPUSceneUniforms
    ) {
        guard !simulation.isSubRailZoomed else { return }

        var vmUniforms = baseSceneUniforms
        var vmProj = Math3D.perspective(fovYRadians: 75.0 * (.pi / 180.0), aspect: aspect, nearZ: 0.02, farZ: 10.0)
        vmProj.columns.0.z *= 0.04
        vmProj.columns.1.z *= 0.04
        vmProj.columns.2.z *= 0.04
        vmProj.columns.3.z *= 0.04
        vmUniforms.viewProjMatrix = vmProj
        vmUniforms.cameraPosition = SIMD4<Float>(0, 0, 0, 1)

        // Transform sun direction & nearby world radiosity lights into view space so weapon catches room color-bleed!
        let sunView = viewMatrix * SIMD4<Float>(baseSceneUniforms.sunDirection.x, baseSceneUniforms.sunDirection.y, baseSceneUniforms.sunDirection.z, 0)
        let sunVec = SIMD3<Float>(sunView.x, sunView.y, sunView.z)
        let sunDir = simd_length_squared(sunVec) > 1e-8 ? simd_normalize(sunVec) : SIMD3<Float>(0, 1, 0)
        vmUniforms.sunDirection = SIMD4<Float>(sunDir, 0)

        let emptyLight = GPUPointLight(positionAndRadius: .zero, colorAndIntensity: .zero)
        var vmLights = Array(repeating: emptyLight, count: 32)
        var vmLightCount = 0
        let eyeWorld = simulation.playerKinematic.eyePosition
        for l in simulation.arena.staticLights where vmLightCount < 6 {
            if simd_distance(eyeWorld, l.position) < l.radius {
                let pView = viewMatrix * SIMD4<Float>(l.position.x, l.position.y, l.position.z, 1.0)
                vmLights[vmLightCount] = GPUPointLight(
                    positionAndRadius: SIMD4<Float>(pView.x, pView.y, pView.z, l.radius),
                    colorAndIntensity: SIMD4<Float>(l.color.x, l.color.y, l.color.z, l.intensity * 0.65)
                )
                vmLightCount += 1
            }
        }
        vmUniforms.timeAndLightCount.y = Float(vmLightCount)
        vmUniforms.lights = Self.pack32Lights(vmLights)

        let bobX = cos(simulation.cameraFX.bobPhase) * 0.013
        let bobY = abs(sin(simulation.cameraFX.bobPhase)) * -0.015
        let kickZ = simulation.weaponSwingOffset * 0.082
        let kickPitch = simulation.weaponSwingOffset * 0.15
        let weapon = simulation.currentWeapon

        let mountPos = SIMD3<Float>(0.20 + bobX, -0.20 + bobY, -0.39 + kickZ)
        let mountRot = Math3D.rotationY(0.055) * Math3D.rotationX(kickPitch) * Math3D.rotationZ(simulation.cameraFX.rollAngleRadians * 0.5)
        let weaponOffset = weapon == .vectorLauncher ? SIMD3<Float>(0.03, -0.03, -0.13) : .zero
        let root = Math3D.translation(mountPos + weaponOffset) * mountRot * Math3D.scale(SIMD3<Float>(repeating: 0.50))

        var batch = ModelBatch()
        CharacterModels.appendWeapon(
            weapon,
            root: root,
            into: &batch,
            time: simulation.elapsedMatchTime,
            fireKick: simulation.weaponSwingOffset,
            rocketCharges: simulation.rocketChargeCount,
            glowBoost: simulation.weaponSwingOffset * 0.85,
            includeHands: true
        )

        encoder.setVertexBytes(&vmUniforms, length: MemoryLayout<GPUSceneUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&vmUniforms, length: MemoryLayout<GPUSceneUniforms>.stride, index: 1)

        encoder.setRenderPipelineState(opaquePipeline)
        encoder.setDepthStencilState(depthStencilOpaque)
        drawOpaqueModelBatch(encoder: encoder, batch: batch)

        encoder.setRenderPipelineState(translucentPipeline)
        encoder.setDepthStencilState(depthStencilTranslucent)
        drawTranslucentModelBatch(encoder: encoder, batch: batch)
    }

    private func drawStaticCall(encoder: MTLRenderCommandEncoder, call: StaticInstancedCall) {
        encoder.setVertexBuffer(call.mesh.buffer, offset: 0, index: 0)
        encoder.setVertexBuffer(call.instanceBuffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: call.mesh.vertexCount, instanceCount: call.instanceCount)
        lastFrameTriangleCount += call.mesh.triangleCount * call.instanceCount
        lastFrameInstanceCount += call.instanceCount
    }

    private func drawOpaqueModelBatch(encoder: MTLRenderCommandEncoder, batch: ModelBatch) {
        drawDynamicInstances(encoder: encoder, mesh: archBlockMesh, instances: batch.archBlocks)
        drawDynamicInstances(encoder: encoder, mesh: beveledCubeMesh, instances: batch.cubes)
        drawDynamicInstances(encoder: encoder, mesh: sharpCubeMesh, instances: batch.sharpCubes)
        drawDynamicInstances(encoder: encoder, mesh: wedgeMesh, instances: batch.wedges)
        drawDynamicInstances(encoder: encoder, mesh: cylinderMesh, instances: batch.cylinders)
        drawDynamicInstances(encoder: encoder, mesh: tubeMesh, instances: batch.tubes)
        drawDynamicInstances(encoder: encoder, mesh: torusMesh, instances: batch.tori)
        drawDynamicInstances(encoder: encoder, mesh: coneMesh, instances: batch.cones)
        drawDynamicInstances(encoder: encoder, mesh: octahedronMesh, instances: batch.octahedra)
        drawDynamicInstances(encoder: encoder, mesh: sphereMesh, instances: batch.spheres)
    }

    private func drawTranslucentModelBatch(encoder: MTLRenderCommandEncoder, batch: ModelBatch) {
        drawDynamicInstances(encoder: encoder, mesh: sharpCubeMesh, instances: batch.translucentCubes)
        drawDynamicInstances(encoder: encoder, mesh: torusMesh, instances: batch.translucentTori)
        drawDynamicInstances(encoder: encoder, mesh: coneMesh, instances: batch.translucentCones)
        drawDynamicInstances(encoder: encoder, mesh: sphereMesh, instances: batch.translucentSpheres)
    }

    private func drawDynamicInstances(
        encoder: MTLRenderCommandEncoder,
        mesh: MeshBufferPair,
        instances: [GPUInstanceData]
    ) {
        guard !instances.isEmpty else { return }

        let alignedOffset = (dynamicWriteByteOffset + 255) & ~255
        let byteLength = MemoryLayout<GPUInstanceData>.stride * instances.count
        var dynBuf = dynamicInstanceBuffers[frameRingIndex]

        if alignedOffset + byteLength > dynBuf.length {
            let newCap = max(dynBuf.length * 2, alignedOffset + byteLength + 131072)
            dynBuf = device.makeBuffer(length: newCap, options: .storageModeShared)!
            dynamicInstanceBuffers[frameRingIndex] = dynBuf
            dynamicWriteByteOffset = 0
            let freshOffset = 0
            instances.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    memcpy(dynBuf.contents().advanced(by: freshOffset), base, byteLength)
                }
            }
            dynamicWriteByteOffset = byteLength
            encoder.setVertexBuffer(mesh.buffer, offset: 0, index: 0)
            encoder.setVertexBuffer(dynBuf, offset: freshOffset, index: 2)
        } else {
            instances.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    memcpy(dynBuf.contents().advanced(by: alignedOffset), base, byteLength)
                }
            }
            dynamicWriteByteOffset = alignedOffset + byteLength
            encoder.setVertexBuffer(mesh.buffer, offset: 0, index: 0)
            encoder.setVertexBuffer(dynBuf, offset: alignedOffset, index: 2)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount, instanceCount: instances.count)
        lastFrameTriangleCount += mesh.triangleCount * instances.count
        lastFrameInstanceCount += instances.count
    }

    private static func pack32Lights(_ a: [GPUPointLight]) -> (
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight,
        GPUPointLight, GPUPointLight, GPUPointLight, GPUPointLight
    ) {
        (
            a[0],  a[1],  a[2],  a[3],  a[4],  a[5],  a[6],  a[7],
            a[8],  a[9],  a[10], a[11], a[12], a[13], a[14], a[15],
            a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23],
            a[24], a[25], a[26], a[27], a[28], a[29], a[30], a[31]
        )
    }

    private func buildSceneUniforms(viewProj: simd_float4x4, eye: SIMD3<Float>) -> GPUSceneUniforms {
        let emptyLight = GPUPointLight(positionAndRadius: .zero, colorAndIntensity: .zero)
        var lightArray = Array(repeating: emptyLight, count: 32)
        var count = 0

        for l in simulation.arena.staticLights where count < 32 {
            lightArray[count] = GPUPointLight(
                positionAndRadius: SIMD4<Float>(l.position.x, l.position.y, l.position.z, l.radius),
                colorAndIntensity: SIMD4<Float>(l.color.x, l.color.y, l.color.z, l.intensity)
            )
            count += 1
        }

        for sphere in simulation.shockSpheres where count < 32 {
            lightArray[count] = GPUPointLight(
                positionAndRadius: SIMD4<Float>(sphere.center.x, sphere.center.y, sphere.center.z, sphere.maxRadius * 3.4),
                colorAndIntensity: SIMD4<Float>(sphere.color.x, sphere.color.y, sphere.center.z == 0 ? sphere.color.z : sphere.color.z, (1.0 - sphere.progress) * 4.0)
            )
            count += 1
        }

        for proj in simulation.projectiles where count < 32 {
            lightArray[count] = GPUPointLight(
                positionAndRadius: SIMD4<Float>(proj.position.x, proj.position.y, proj.position.z, 12.0),
                colorAndIntensity: SIMD4<Float>(proj.color.x, proj.color.y, proj.color.z, 2.0)
            )
            count += 1
        }

        return GPUSceneUniforms(
            viewProjMatrix: viewProj,
            cameraPosition: SIMD4<Float>(eye.x, eye.y, eye.z, 1.0),
            sunDirection: SIMD4<Float>(simd_normalize(SIMD3<Float>(0.26, 0.90, -0.34)), 0.0),
            timeAndLightCount: SIMD4<Float>(
                simulation.elapsedMatchTime,
                Float(count),
                simulation.quadOverdriveTimer > 0 ? 1.0 : 0.0,
                simulation.subShieldTimer > 0 ? 1.0 : 0.0
            ),
            lights: Self.pack32Lights(lightArray)
        )
    }

    // MARK: - High-Polygon Procedural Mesh Library

    /// Watertight SDF-projected rounded/beveled box of size [-0.5, 0.5]^3 with smooth edges & spherical corners.
    private static func makeRoundedBoxVertices(bevelRadius: Float, edgeSteps: Int) -> [GPUVertex] {
        let b = simd_clamp(bevelRadius, 0.005, 0.24)
        let inner = 0.5 - b

        var coords: [Float] = []
        for s in 0...edgeSteps {
            let frac = Float(s) / Float(edgeSteps)
            coords.append(-0.5 + frac * b)
        }
        coords.append(0.0)
        for s in 0...edgeSteps {
            let frac = Float(s) / Float(edgeSteps)
            coords.append(inner + frac * b)
        }

        let faces: [(normal: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>)] = [
            (SIMD3<Float>( 0,  1,  0), SIMD3<Float>( 1, 0, 0), SIMD3<Float>(0, 0,  1)),
            (SIMD3<Float>( 0, -1,  0), SIMD3<Float>( 1, 0, 0), SIMD3<Float>(0, 0, -1)),
            (SIMD3<Float>( 1,  0,  0), SIMD3<Float>( 0, 0, -1), SIMD3<Float>(0, 1, 0)),
            (SIMD3<Float>(-1,  0,  0), SIMD3<Float>( 0, 0,  1), SIMD3<Float>(0, 1, 0)),
            (SIMD3<Float>( 0,  0,  1), SIMD3<Float>( 1, 0, 0), SIMD3<Float>(0, 1,  0)),
            (SIMD3<Float>( 0,  0, -1), SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 1,  0))
        ]

        func evalPoint(_ f: (normal: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>), _ cu: Float, _ cv: Float) -> GPUVertex {
            let cubePt = f.normal * 0.5 + f.u * cu + f.v * cv
            let clamped = simd_clamp(cubePt, SIMD3<Float>(repeating: -inner), SIMD3<Float>(repeating: inner))
            let diff = cubePt - clamped
            let n = simd_normalize(diff)
            let pos = clamped + n * b
            let isBevel: Float = (abs(cu) > inner + 1e-4 || abs(cv) > inner + 1e-4) ? 1.0 : 0.0
            return GPUVertex(position: pos, normal: n, uvAndEdge: SIMD3<Float>(cu + 0.5, cv + 0.5, isBevel))
        }

        var verts: [GPUVertex] = []
        let nSteps = coords.count - 1
        verts.reserveCapacity(6 * nSteps * nSteps * 6)

        for f in faces {
            for iu in 0..<nSteps {
                let u0 = coords[iu], u1 = coords[iu + 1]
                for iv in 0..<nSteps {
                    let v0 = coords[iv], v1 = coords[iv + 1]
                    let p00 = evalPoint(f, u0, v0)
                    let p10 = evalPoint(f, u1, v0)
                    let p11 = evalPoint(f, u1, v1)
                    let p01 = evalPoint(f, u0, v1)
                    verts += [p00, p10, p11, p00, p11, p01]
                }
            }
        }
        return verts
    }

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
                let pos = f.normal * 0.5 + f.u * (uv.x - 0.5) + f.v * (uv.y - 0.5)
                verts.append(GPUVertex(position: pos, normal: f.normal, uvAndEdge: SIMD3<Float>(uv.x, uv.y, 1.0)))
            }
        }
        return verts
    }

    /// Subdivided sloped ramp wedge [-0.5, 0.5]^3 ascending from y = -0.5 at x = -0.5 to y = +0.5 at x = +0.5.
    private static func makeSlopedWedgeVertices(gridSteps: Int) -> [GPUVertex] {
        var verts: [GPUVertex] = []
        let slopeN = simd_normalize(SIMD3<Float>(-1, 1, 0))
        let n = max(2, gridSteps)

        // 1. Sloped top ramp surface
        for ix in 0..<n {
            let x0 = -0.5 + Float(ix) / Float(n)
            let x1 = -0.5 + Float(ix + 1) / Float(n)
            for iz in 0..<n {
                let z0 = -0.5 + Float(iz) / Float(n)
                let z1 = -0.5 + Float(iz + 1) / Float(n)
                let p00 = GPUVertex(position: SIMD3<Float>(x0, x0, z0), normal: slopeN, uvAndEdge: SIMD3<Float>(x0 + 0.5, z0 + 0.5, 0))
                let p10 = GPUVertex(position: SIMD3<Float>(x1, x1, z0), normal: slopeN, uvAndEdge: SIMD3<Float>(x1 + 0.5, z0 + 0.5, 0))
                let p11 = GPUVertex(position: SIMD3<Float>(x1, x1, z1), normal: slopeN, uvAndEdge: SIMD3<Float>(x1 + 0.5, z1 + 0.5, 0))
                let p01 = GPUVertex(position: SIMD3<Float>(x0, x0, z1), normal: slopeN, uvAndEdge: SIMD3<Float>(x0 + 0.5, z1 + 0.5, 0))
                verts += [p00, p10, p11, p00, p11, p01]
            }
        }

        // 2. Back vertical face at x = +0.5 & Bottom face at y = -0.5
        let backN = SIMD3<Float>(1, 0, 0)
        let botN = SIMD3<Float>(0, -1, 0)
        for i in 0..<4 {
            let a0 = -0.5 + Float(i) * 0.25
            let a1 = -0.5 + Float(i + 1) * 0.25
            for j in 0..<4 {
                let b0 = -0.5 + Float(j) * 0.25
                let b1 = -0.5 + Float(j + 1) * 0.25
                verts += [
                    GPUVertex(position: SIMD3<Float>(0.5, a0, b0), normal: backN, uvAndEdge: .zero),
                    GPUVertex(position: SIMD3<Float>(0.5, a1, b0), normal: backN, uvAndEdge: .zero),
                    GPUVertex(position: SIMD3<Float>(0.5, a1, b1), normal: backN, uvAndEdge: .zero),
                    GPUVertex(position: SIMD3<Float>(0.5, a0, b0), normal: backN, uvAndEdge: .zero),
                    GPUVertex(position: SIMD3<Float>(0.5, a1, b1), normal: backN, uvAndEdge: .zero),
                    GPUVertex(position: SIMD3<Float>(0.5, a0, b1), normal: backN, uvAndEdge: .zero),

                    GPUVertex(position: SIMD3<Float>(a0, -0.5, b0), normal: botN, uvAndEdge: .zero),
                    GPUVertex(position: SIMD3<Float>(a1, -0.5, b0), normal: botN, uvAndEdge: .zero),
                    GPUVertex(position: SIMD3<Float>(a1, -0.5, b1), normal: botN, uvAndEdge: .zero),
                    GPUVertex(position: SIMD3<Float>(a0, -0.5, b0), normal: botN, uvAndEdge: .zero),
                    GPUVertex(position: SIMD3<Float>(a1, -0.5, b1), normal: botN, uvAndEdge: .zero),
                    GPUVertex(position: SIMD3<Float>(a0, -0.5, b1), normal: botN, uvAndEdge: .zero)
                ]
            }
        }

        // 3. Subdivided triangular side walls at z = +0.5 and z = -0.5
        for sz: Float in [-1, 1] {
            let z = 0.5 * sz
            let sideN = SIMD3<Float>(0, 0, sz)
            for ix in 0..<n {
                let x0 = -0.5 + Float(ix) / Float(n)
                let x1 = -0.5 + Float(ix + 1) / Float(n)
                let b0 = SIMD3<Float>(x0, -0.5, z)
                let b1 = SIMD3<Float>(x1, -0.5, z)
                let t1 = SIMD3<Float>(x1, x1, z)
                let t0 = SIMD3<Float>(x0, x0, z)
                if ix == 0 {
                    verts += [
                        GPUVertex(position: b0, normal: sideN, uvAndEdge: .zero),
                        GPUVertex(position: b1, normal: sideN, uvAndEdge: .zero),
                        GPUVertex(position: t1, normal: sideN, uvAndEdge: .zero)
                    ]
                } else {
                    verts += [
                        GPUVertex(position: b0, normal: sideN, uvAndEdge: .zero),
                        GPUVertex(position: b1, normal: sideN, uvAndEdge: .zero),
                        GPUVertex(position: t1, normal: sideN, uvAndEdge: .zero),
                        GPUVertex(position: b0, normal: sideN, uvAndEdge: .zero),
                        GPUVertex(position: t1, normal: sideN, uvAndEdge: .zero),
                        GPUVertex(position: t0, normal: sideN, uvAndEdge: .zero)
                    ]
                }
            }
        }
        return verts
    }

    private static func makeUnitSphereVertices(latSegments: Int, lonSegments: Int) -> [GPUVertex] {
        var verts: [GPUVertex] = []
        verts.reserveCapacity(latSegments * lonSegments * 6)
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

                verts += [
                    GPUVertex(position: p1 * 0.5, normal: p1, uvAndEdge: .zero),
                    GPUVertex(position: p2 * 0.5, normal: p2, uvAndEdge: .zero),
                    GPUVertex(position: p3 * 0.5, normal: p3, uvAndEdge: .zero),
                    GPUVertex(position: p1 * 0.5, normal: p1, uvAndEdge: .zero),
                    GPUVertex(position: p3 * 0.5, normal: p3, uvAndEdge: .zero),
                    GPUVertex(position: p4 * 0.5, normal: p4, uvAndEdge: .zero)
                ]
            }
        }
        return verts
    }

    /// High-resolution 40-segment Z-axis cylinder with chamfered end-cap bevels.
    private static func makeUnitCylinderVertices(segments: Int) -> [GPUVertex] {
        var verts: [GPUVertex] = []
        let front = SIMD3<Float>(0, 0, 1)
        let bev: Float = 0.045
        let rOuter: Float = 0.5
        let rInner: Float = 0.5 - bev
        let zBody: Float = 0.5 - bev

        for j in 0..<segments {
            let a1 = Float(j) * 2.0 * .pi / Float(segments)
            let a2 = Float(j + 1) * 2.0 * .pi / Float(segments)
            let n1 = SIMD3<Float>(cos(a1), sin(a1), 0)
            let n2 = SIMD3<Float>(cos(a2), sin(a2), 0)

            let b1 = n1 * rOuter - front * zBody, b2 = n2 * rOuter - front * zBody
            let t1 = n1 * rOuter + front * zBody, t2 = n2 * rOuter + front * zBody
            let bc1 = n1 * rInner - front * 0.5, bc2 = n2 * rInner - front * 0.5
            let tc1 = n1 * rInner + front * 0.5, tc2 = n2 * rInner + front * 0.5
            let bn1 = simd_normalize(n1 - front), bn2 = simd_normalize(n2 - front)
            let tn1 = simd_normalize(n1 + front), tn2 = simd_normalize(n2 + front)

            verts += [
                // Side wall
                GPUVertex(position: b1, normal: n1, uvAndEdge: .zero),
                GPUVertex(position: b2, normal: n2, uvAndEdge: .zero),
                GPUVertex(position: t2, normal: n2, uvAndEdge: .zero),
                GPUVertex(position: b1, normal: n1, uvAndEdge: .zero),
                GPUVertex(position: t2, normal: n2, uvAndEdge: .zero),
                GPUVertex(position: t1, normal: n1, uvAndEdge: .zero),
                // Front chamfer ring
                GPUVertex(position: t1, normal: tn1, uvAndEdge: .zero),
                GPUVertex(position: t2, normal: tn2, uvAndEdge: .zero),
                GPUVertex(position: tc2, normal: tn2, uvAndEdge: .zero),
                GPUVertex(position: t1, normal: tn1, uvAndEdge: .zero),
                GPUVertex(position: tc2, normal: tn2, uvAndEdge: .zero),
                GPUVertex(position: tc1, normal: tn1, uvAndEdge: .zero),
                // Back chamfer ring
                GPUVertex(position: bc1, normal: bn1, uvAndEdge: .zero),
                GPUVertex(position: bc2, normal: bn2, uvAndEdge: .zero),
                GPUVertex(position: b2, normal: bn2, uvAndEdge: .zero),
                GPUVertex(position: bc1, normal: bn1, uvAndEdge: .zero),
                GPUVertex(position: b2, normal: bn2, uvAndEdge: .zero),
                GPUVertex(position: b1, normal: bn1, uvAndEdge: .zero),
                // Front & Back flat caps
                GPUVertex(position: front * 0.5, normal: front, uvAndEdge: .zero),
                GPUVertex(position: tc1, normal: front, uvAndEdge: .zero),
                GPUVertex(position: tc2, normal: front, uvAndEdge: .zero),
                GPUVertex(position: -front * 0.5, normal: -front, uvAndEdge: .zero),
                GPUVertex(position: bc2, normal: -front, uvAndEdge: .zero),
                GPUVertex(position: bc1, normal: -front, uvAndEdge: .zero)
            ]
        }
        return verts
    }

    /// Hollow cylindrical pipe / gun barrel along Z axis with inner bore & annular front/back rims.
    private static func makeHollowTubeVertices(segments: Int, innerRatio: Float) -> [GPUVertex] {
        var verts: [GPUVertex] = []
        let rOut: Float = 0.5
        let rIn: Float = 0.5 * simd_clamp(innerRatio, 0.2, 0.92)
        let front = SIMD3<Float>(0, 0, 1)

        for j in 0..<segments {
            let a1 = Float(j) * 2.0 * .pi / Float(segments)
            let a2 = Float(j + 1) * 2.0 * .pi / Float(segments)
            let n1 = SIMD3<Float>(cos(a1), sin(a1), 0)
            let n2 = SIMD3<Float>(cos(a2), sin(a2), 0)

            let ob1 = n1 * rOut - front * 0.5, ob2 = n2 * rOut - front * 0.5
            let ot1 = n1 * rOut + front * 0.5, ot2 = n2 * rOut + front * 0.5
            let ib1 = n1 * rIn - front * 0.5,  ib2 = n2 * rIn - front * 0.5
            let it1 = n1 * rIn + front * 0.5,  it2 = n2 * rIn + front * 0.5

            verts += [
                // Outer wall
                GPUVertex(position: ob1, normal: n1, uvAndEdge: .zero),
                GPUVertex(position: ob2, normal: n2, uvAndEdge: .zero),
                GPUVertex(position: ot2, normal: n2, uvAndEdge: .zero),
                GPUVertex(position: ob1, normal: n1, uvAndEdge: .zero),
                GPUVertex(position: ot2, normal: n2, uvAndEdge: .zero),
                GPUVertex(position: ot1, normal: n1, uvAndEdge: .zero),
                // Inner bore wall (inward normals!)
                GPUVertex(position: ib2, normal: -n2, uvAndEdge: .zero),
                GPUVertex(position: ib1, normal: -n1, uvAndEdge: .zero),
                GPUVertex(position: it1, normal: -n1, uvAndEdge: .zero),
                GPUVertex(position: ib2, normal: -n2, uvAndEdge: .zero),
                GPUVertex(position: it1, normal: -n1, uvAndEdge: .zero),
                GPUVertex(position: it2, normal: -n2, uvAndEdge: .zero),
                // Front annular muzzle face
                GPUVertex(position: it1, normal: front, uvAndEdge: .zero),
                GPUVertex(position: ot1, normal: front, uvAndEdge: .zero),
                GPUVertex(position: ot2, normal: front, uvAndEdge: .zero),
                GPUVertex(position: it1, normal: front, uvAndEdge: .zero),
                GPUVertex(position: ot2, normal: front, uvAndEdge: .zero),
                GPUVertex(position: it2, normal: front, uvAndEdge: .zero),
                // Back annular face
                GPUVertex(position: ob1, normal: -front, uvAndEdge: .zero),
                GPUVertex(position: ib1, normal: -front, uvAndEdge: .zero),
                GPUVertex(position: ib2, normal: -front, uvAndEdge: .zero),
                GPUVertex(position: ob1, normal: -front, uvAndEdge: .zero),
                GPUVertex(position: ib2, normal: -front, uvAndEdge: .zero),
                GPUVertex(position: ob2, normal: -front, uvAndEdge: .zero)
            ]
        }
        return verts
    }

    /// Smooth torus ring in XY plane (outer radius 0.5 -> diameter 1.0).
    private static func makeUnitTorusVertices(majorSegments: Int, minorSegments: Int) -> [GPUVertex] {
        var verts: [GPUVertex] = []
        let R: Float = 0.442
        let r: Float = 0.058
        verts.reserveCapacity(majorSegments * minorSegments * 6)

        func torusPt(_ u: Float, _ v: Float) -> GPUVertex {
            let cu = cos(u), su = sin(u)
            let cv = cos(v), sv = sin(v)
            let center = SIMD3<Float>(cu * R, su * R, 0)
            let n = SIMD3<Float>(cu * cv, su * cv, sv)
            return GPUVertex(position: center + n * r, normal: n, uvAndEdge: .zero)
        }

        for i in 0..<majorSegments {
            let u0 = Float(i) * 2.0 * .pi / Float(majorSegments)
            let u1 = Float(i + 1) * 2.0 * .pi / Float(majorSegments)
            for j in 0..<minorSegments {
                let v0 = Float(j) * 2.0 * .pi / Float(minorSegments)
                let v1 = Float(j + 1) * 2.0 * .pi / Float(minorSegments)
                let p00 = torusPt(u0, v0), p10 = torusPt(u1, v0)
                let p11 = torusPt(u1, v1), p01 = torusPt(u0, v1)
                verts += [p00, p10, p11, p00, p11, p01]
            }
        }
        return verts
    }

    /// Tapered cone/frustum along Z from base radius 0.5 at z = -0.5 to tip at z = +0.5.
    private static func makeTaperedConeVertices(segments: Int, tipRatio: Float) -> [GPUVertex] {
        var verts: [GPUVertex] = []
        let r0: Float = 0.5
        let r1: Float = 0.5 * simd_clamp(tipRatio, 0.02, 0.9)
        let front = SIMD3<Float>(0, 0, 1)
        let slopeZ = (r0 - r1)

        for j in 0..<segments {
            let a1 = Float(j) * 2.0 * .pi / Float(segments)
            let a2 = Float(j + 1) * 2.0 * .pi / Float(segments)
            let c1 = SIMD3<Float>(cos(a1), sin(a1), 0)
            let c2 = SIMD3<Float>(cos(a2), sin(a2), 0)
            let n1 = simd_normalize(SIMD3<Float>(c1.x, c1.y, slopeZ))
            let n2 = simd_normalize(SIMD3<Float>(c2.x, c2.y, slopeZ))

            let b1 = c1 * r0 - front * 0.5, b2 = c2 * r0 - front * 0.5
            let t1 = c1 * r1 + front * 0.5, t2 = c2 * r1 + front * 0.5

            verts += [
                GPUVertex(position: b1, normal: n1, uvAndEdge: .zero),
                GPUVertex(position: b2, normal: n2, uvAndEdge: .zero),
                GPUVertex(position: t2, normal: n2, uvAndEdge: .zero),
                GPUVertex(position: b1, normal: n1, uvAndEdge: .zero),
                GPUVertex(position: t2, normal: n2, uvAndEdge: .zero),
                GPUVertex(position: t1, normal: n1, uvAndEdge: .zero),
                GPUVertex(position: front * 0.5, normal: front, uvAndEdge: .zero),
                GPUVertex(position: t1, normal: front, uvAndEdge: .zero),
                GPUVertex(position: t2, normal: front, uvAndEdge: .zero),
                GPUVertex(position: -front * 0.5, normal: -front, uvAndEdge: .zero),
                GPUVertex(position: b2, normal: -front, uvAndEdge: .zero),
                GPUVertex(position: b1, normal: -front, uvAndEdge: .zero)
            ]
        }
        return verts
    }

    /// Crisp 16-face faceted bipyramid / crystal prism with exact flat facet normals.
    private static func makeFacetedOctahedronVertices() -> [GPUVertex] {
        var verts: [GPUVertex] = []
        let sides = 8
        let top = SIMD3<Float>(0, 0.5, 0)
        let bot = SIMD3<Float>(0, -0.5, 0)
        for i in 0..<sides {
            let a0 = Float(i) * 2.0 * .pi / Float(sides)
            let a1 = Float(i + 1) * 2.0 * .pi / Float(sides)
            let p0 = SIMD3<Float>(cos(a0) * 0.5, 0, sin(a0) * 0.5)
            let p1 = SIMD3<Float>(cos(a1) * 0.5, 0, sin(a1) * 0.5)

            let nTop = simd_normalize(simd_cross(p1 - top, p0 - top))
            let fnTop = simd_dot(nTop, top + p0 + p1) >= 0 ? nTop : -nTop
            verts += [
                GPUVertex(position: top, normal: fnTop, uvAndEdge: .zero),
                GPUVertex(position: p0, normal: fnTop, uvAndEdge: .zero),
                GPUVertex(position: p1, normal: fnTop, uvAndEdge: .zero)
            ]

            let nBot = simd_normalize(simd_cross(p0 - bot, p1 - bot))
            let fnBot = simd_dot(nBot, bot + p0 + p1) >= 0 ? nBot : -nBot
            verts += [
                GPUVertex(position: bot, normal: fnBot, uvAndEdge: .zero),
                GPUVertex(position: p1, normal: fnBot, uvAndEdge: .zero),
                GPUVertex(position: p0, normal: fnBot, uvAndEdge: .zero)
            ]
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

    // MARK: - Unified Mirror's Edge Metal Shader Library

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
        GPUPointLight lights[32];
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
        float bevelFlag;
    };

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

    // Luminous Mirror's Edge high-key exposure & clean primary saturation curve (preserves crisp slab joints on sunlit white!)
    float3 tonemapMirrorsEdge(float3 x) {
        x = max(x, float3(0.0));
        float3 num = x * (0.94 * x + 0.18);
        float3 den = x * (0.96 * x + 0.58) + 0.18;
        float3 mapped = clamp(pow(num / den, float3(1.0 / 2.15)), 0.0, 1.0);
        float luma = dot(mapped, float3(0.2126, 0.7152, 0.0722));
        return clamp(mix(float3(luma), mapped, 1.15), 0.0, 1.0);
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

        // Exact adjugate / inverse-transpose normal transform so non-uniformly scaled wedges & bevels stay exact!
        float3 m0 = inst.modelMatrix[0].xyz;
        float3 m1 = inst.modelMatrix[1].xyz;
        float3 m2 = inst.modelMatrix[2].xyz;
        float3 c0 = cross(m1, m2);
        float3 c1 = cross(m2, m0);
        float3 c2 = cross(m0, m1);
        float detSign = dot(m0, c0) >= 0.0 ? 1.0 : -1.0;
        float3 worldN = normalize((c0 * v.normal.x + c1 * v.normal.y + c2 * v.normal.z) * detSign);

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
        out.bevelFlag = v.uvAndEdge.z;
        return out;
    }

    fragment float4 sublevel_fragment(
        Varyings in [[stage_in]],
        constant GPUSceneUniforms &scene [[buffer(1)]]
    ) {
        // MODE 5: City of Glass Procedural Sky Dome (Pure Cerulean Zenith -> Gleaming White Horizon + Sun Disc)
        if (in.shaderMode > 4.5) {
            float3 rayDir = normalize(in.worldPos - scene.cameraPosition.xyz);
            float upT = saturate(rayDir.y);
            float3 horizonWhite = float3(0.96, 0.985, 1.0);
            float3 midSky = float3(0.24, 0.63, 1.0);
            float3 zenithBlue = float3(0.05, 0.34, 0.95);
            float3 sky = mix(horizonWhite, midSky, pow(upT, 0.48));
            sky = mix(sky, zenithBlue, smoothstep(0.28, 0.92, upT));

            float3 sunDir = normalize(scene.sunDirection.xyz);
            float sunDot = saturate(dot(rayDir, sunDir));
            float sunHalo = pow(sunDot, 16.0) * 0.45 + pow(sunDot, 180.0) * 2.2;
            sky += float3(1.0, 0.98, 0.92) * sunHalo;

            // Below horizon: deep Sump cobalt reflection
            if (rayDir.y < 0.0) {
                sky = mix(horizonWhite, float3(0.03, 0.16, 0.48), saturate(-rayDir.y * 2.4));
            }
            return float4(tonemapMirrorsEdge(sky), 1.0);
        }

        float3 V = normalize(scene.cameraPosition.xyz - in.worldPos);
        float3 N = normalize(in.worldNormal);
        float3 baseColor = in.colorAndRoughness.rgb;
        float roughness = clamp(in.colorAndRoughness.w, 0.04, 1.0);
        float emissive = in.materialParams.y;
        float alpha = in.materialParams.z;

        // MODE 1: High-visibility opponent silhouette armor + crisp Fresnel rim
        if (in.shaderMode > 0.5 && in.shaderMode < 1.5) {
            float fresnel = pow(1.0 - saturate(dot(N, V)), 2.3);
            float3 rim = float3(1.0, 1.0, 1.0) * fresnel * 1.35;
            float3 L = normalize(scene.sunDirection.xyz);
            float3 H = normalize(L + V);
            float spec = pow(saturate(dot(N, H)), 48.0) * 0.45;
            float3 skyTint = mix(float3(0.55, 0.72, 0.98), float3(1.0, 0.99, 0.97), saturate(dot(N, L)));
            float3 lit = baseColor * (0.55 + 0.55 * skyTint) + baseColor * emissive * 0.52 + rim + spec;
            return float4(tonemapMirrorsEdge(lit), 1.0);
        }

        // MODE 2: Volumetric Fresnel energy field (Shock Combo spheres, portals, ion thruster plumes)
        if (in.shaderMode > 1.5 && in.shaderMode < 2.5) {
            float ndotv = abs(dot(N, V));
            float rim = pow(1.0 - ndotv, 1.80);
            float wave = 0.5 + 0.5 * sin(in.worldPos.y * 7.0 - scene.timeAndLightCount.x * 18.0);
            float core = pow(ndotv, 2.8) * 0.48;
            float3 col = baseColor * (rim * 2.4 + core + wave * 0.42) * emissive + float3(rim * 0.65);
            float finalAlpha = clamp(alpha * (rim * 1.15 + 0.30), 0.08, 0.96);
            return float4(tonemapMirrorsEdge(col), finalAlpha);
        }

        // MODE 4: Precision weapon & robot hardware (machined steel, polymer, tinted glass, room color-bleed)
        if (in.shaderMode > 3.5) {
            float metallic = in.materialParams.x;
            float3 L = normalize(scene.sunDirection.xyz);
            float ndl = saturate(dot(N, L));
            // Cool cerulean sky fill from above + crisp floor bounce from below
            float3 skyFill = mix(float3(0.42, 0.56, 0.78), float3(0.92, 0.96, 1.0), N.y * 0.5 + 0.5);
            float3 H = normalize(L + V + float3(0.0, 0.0001, 0.0));
            float specPow = mix(128.0, 14.0, roughness);
            float3 specCol = mix(float3(0.08), mix(float3(0.95, 0.97, 1.0), baseColor + 0.25, 0.65), metallic);
            float3 spec = specCol * pow(saturate(dot(N, H)), specPow) * (1.5 - roughness);

            float3 gi = float3(0.0);
            int lightCount = int(scene.timeAndLightCount.y);
            for (int i = 0; i < lightCount; ++i) {
                float3 toL = scene.lights[i].positionAndRadius.xyz - in.worldPos;
                float lRad = max(scene.lights[i].positionAndRadius.w, 0.5);
                float dist = length(toL);
                if (dist < lRad) {
                    float3 lDir = toL / max(dist, 0.001);
                    float atten = pow(1.0 - dist / lRad, 1.7) * scene.lights[i].colorAndIntensity.w;
                    gi += scene.lights[i].colorAndIntensity.rgb * saturate((dot(N, lDir) + 0.35) / 1.35) * atten * 0.48;
                    float3 Hl = normalize(lDir + V);
                    spec += scene.lights[i].colorAndIntensity.rgb * pow(saturate(dot(N, Hl)), specPow * 0.6) * atten * 0.25 * metallic;
                }
            }

            float fresnel = pow(1.0 - saturate(dot(N, V)), 3.2);
            float3 envReflect = float3(0.72, 0.86, 1.0) * fresnel * (1.0 - roughness * 0.7) * (0.28 + metallic * 0.42);
            float3 lit = baseColor * (skyFill * 0.68 + float3(1.0, 0.98, 0.95) * ndl * 0.90 + gi)
                       + spec + envReflect + baseColor * emissive;
            return float4(tonemapMirrorsEdge(lit), alpha);
        }

        // MODE 3: Pure radiant emissive neon / reticles / beams / sunbeam shafts
        if (in.shaderMode > 2.5) {
            float fresnel = pow(1.0 - abs(dot(N, V)), 2.0);
            float3 col = baseColor * (1.05 + emissive * 0.90) + float3(fresnel * 0.42 * step(0.25, alpha));
            return float4(tonemapMirrorsEdge(col), alpha);
        }

        // MODE 0: Mirror's Edge Master Architectural Surface (`arch_surface`)
        // 1. Sub-perceptual procedural micro-normal (0.012 strength so surfaces stay clean & textureless yet catch gloss)
        float3 sampleP = in.worldPos * 3.6;
        float nx = noise3D(sampleP + float3(0.15, 0, 0)) - noise3D(sampleP - float3(0.15, 0, 0));
        float ny = noise3D(sampleP + float3(0, 0.15, 0)) - noise3D(sampleP - float3(0, 0.15, 0));
        float nz = noise3D(sampleP + float3(0, 0, 0.15)) - noise3D(sampleP - float3(0, 0, 0.15));
        N = normalize(N + float3(nx, ny, nz) * 0.012);

        // 2. World-space architectural edge bevel catchlight & corner contact AO
        float3 dEdge = abs(in.worldPos - in.boxCenter) - in.boxHalfExtents;
        float3 distToEdge = abs(dEdge);
        float nearX = 1.0 - smoothstep(0.0, 0.12, distToEdge.x);
        float nearY = 1.0 - smoothstep(0.0, 0.12, distToEdge.y);
        float nearZ = 1.0 - smoothstep(0.0, 0.12, distToEdge.z);
        float creaseFactor = saturate((nearX * nearY) + (nearY * nearZ) + (nearX * nearZ));

        // 3. Mirror's Edge Signature Daylight: Gleaming Warm-White Sun + Cool Cerulean Sky-Blue Shadows!
        float3 Lsun = normalize(scene.sunDirection.xyz);
        float sunNdotL = saturate(dot(N, Lsun));
        float skyVisibility = smoothstep(-15.0, 15.0, in.worldPos.y);

        // Cool cerulean sky bounce in shadows (bright sky-blue in B1 Atrium, deeper cobalt in B3 Sump)
        float hemiUp = N.y * 0.5 + 0.5;
        float3 coolShadowB1 = mix(float3(0.58, 0.73, 0.94), float3(0.84, 0.91, 0.99), hemiUp);
        float3 coolShadowB3 = mix(float3(0.14, 0.24, 0.46), float3(0.32, 0.48, 0.76), hemiUp);
        float3 ambientSky = mix(coolShadowB3, coolShadowB1, skyVisibility);

        // 4. Multi-Bounce Saturated Radiosity GI (Beast lightmapper color-bleeding onto adjacent stark white!)
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
                float atten = pow(1.0 - dist / lRad, 1.65) * lInt;
                float wrapDiff = saturate((dot(N, L) + 0.52) / 1.52);
                giRadiosity += lCol * wrapDiff * atten * 0.62;

                float3 H = normalize(L + V);
                float specPow = mix(108.0, 16.0, roughness);
                float spec = pow(saturate(dot(N, H)), specPow) * (1.0 - roughness * 0.65);
                specularSum += lCol * spec * atten * 0.36;
            }
        }

        // Crisp sun specular + glossy sky Fresnel reflection on polished floors & lacquered color panels
        float3 Hsun = normalize(Lsun + V);
        float sunSpec = pow(saturate(dot(N, Hsun)), mix(88.0, 14.0, roughness)) * (0.20 + 0.35 * skyVisibility);
        float fresnel = pow(1.0 - saturate(dot(N, V)), 3.8);
        float3 glossySkyReflect = mix(float3(0.25, 0.55, 0.98), float3(0.95, 0.98, 1.0), skyVisibility)
                                * fresnel * (1.0 - roughness * 0.82) * 0.30;

        // Clean architectural expansion joints every 4m + crisp edge bevel catchlight
        float3 gridMod = abs(fract(in.worldPos * 0.25 + 0.5) - 0.5) / 0.25;
        float minGrid = min(min(gridMod.x, gridMod.z), gridMod.y);
        float jointLine = 1.0 - smoothstep(0.0, 0.028, minGrid);
        float ao = (1.0 - jointLine * 0.16) * (1.0 - creaseFactor * 0.14);
        float3 edgeHighlight = float3(0.16, 0.18, 0.22) * max(creaseFactor, in.bevelFlag * sunNdotL * 0.45) * (1.0 - roughness * 0.5);

        float3 directSun = float3(1.0, 0.985, 0.955) * sunNdotL * (0.36 + 0.48 * skyVisibility);
        float3 litColor = baseColor * (ambientSky * 0.68 + directSun + giRadiosity * 0.85) * ao
                        + baseColor * emissive * 0.95
                        + specularSum + sunSpec + glossySkyReflect + edgeHighlight;

        // Crisp atmospheric cobalt mist only in the deep B3 Sump abyss
        float depthFog = saturate((-in.worldPos.y - 7.5) / 13.5);
        litColor = mix(litColor, float3(0.04, 0.24, 0.68), depthFog * 0.36);

        return float4(tonemapMirrorsEdge(litColor), alpha);
    }
    """
}

