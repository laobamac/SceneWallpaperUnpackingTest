//
//  Renderer.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import Foundation
import MetalKit
import simd

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState?
    var puppetPipelineState: MTLRenderPipelineState?
    var particlePipelineState: MTLRenderPipelineState?
    var additiveParticlePipelineState: MTLRenderPipelineState?
    var extractPipeline: MTLRenderPipelineState?
    var blurPipeline: MTLRenderPipelineState?
    var upsamplePipeline: MTLRenderPipelineState?
    var finalPipeline: MTLRenderPipelineState?
    var samplerState: MTLSamplerState?
    var depthStencilState: MTLDepthStencilState?
    var depthWriteDisabledState: MTLDepthStencilState?
    var maskWriteState: MTLDepthStencilState?
    var maskTestState: MTLDepthStencilState?
    var baseFolder: URL?
    var renderables: [RenderableObject] = []
    var startTime: Date = Date()
    var lastTime: TimeInterval = 0
    var projectionSize: CGSize = CGSize(width: 1920, height: 1080)
    var currentFOV: Float = 50.0
    var hdrTexture: MTLTexture?
    var bloomTextures: [MTLTexture] = []
    var bloomTempTextures: [MTLTexture] = []
    var bloomThreshold: Float = 1.0
    var bloomStrength: Float = 2.0
    var bloomIterations: Int = 8

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        super.init()
        do { try setupPipeline() } catch { return nil }
        Task { await TextureManager.shared.setup(device: device) }
    }

    func setupPipeline() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw NSError(
                domain: "Renderer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Library error"]
            )
        }
        let hdrFormat: MTLPixelFormat = .rgba16Float
        let depthFormat: MTLPixelFormat = .depth32Float_stencil8
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Standard"
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(
            name: "fragment_main"
        )
        descriptor.colorAttachments[0].pixelFormat = hdrFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor =
            .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = depthFormat
        descriptor.stencilAttachmentPixelFormat = depthFormat
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 20
        descriptor.vertexDescriptor = vertexDescriptor
        pipelineState = try device.makeRenderPipelineState(
            descriptor: descriptor
        )
        let puppetDesc = MTLRenderPipelineDescriptor()
        puppetDesc.label = "Puppet"
        puppetDesc.vertexFunction = library.makeFunction(name: "vertex_puppet")
        puppetDesc.fragmentFunction = library.makeFunction(
            name: "fragment_main"
        )
        puppetDesc.colorAttachments[0].pixelFormat = hdrFormat
        puppetDesc.colorAttachments[0].isBlendingEnabled = true
        puppetDesc.colorAttachments[0].rgbBlendOperation = .add
        puppetDesc.colorAttachments[0].alphaBlendOperation = .add
        puppetDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        puppetDesc.colorAttachments[0].destinationRGBBlendFactor =
            .oneMinusSourceAlpha
        puppetDesc.depthAttachmentPixelFormat = depthFormat
        puppetDesc.stencilAttachmentPixelFormat = depthFormat
        let pvDesc = MTLVertexDescriptor()
        var offset = 0
        pvDesc.attributes[0].format = .float3
        pvDesc.attributes[0].offset = offset
        pvDesc.attributes[0].bufferIndex = 0
        offset += 16
        pvDesc.attributes[1].format = .float2
        pvDesc.attributes[1].offset = offset
        pvDesc.attributes[1].bufferIndex = 0
        offset += 8
        pvDesc.attributes[2].format = .ushort4
        pvDesc.attributes[2].offset = offset
        pvDesc.attributes[2].bufferIndex = 0
        offset += 8
        pvDesc.attributes[3].format = .float4
        pvDesc.attributes[3].offset = offset
        pvDesc.attributes[3].bufferIndex = 0
        offset += 16
        pvDesc.layouts[0].stride = 48
        puppetDesc.vertexDescriptor = pvDesc
        puppetPipelineState = try device.makeRenderPipelineState(
            descriptor: puppetDesc
        )
        let particleDesc = MTLRenderPipelineDescriptor()
        particleDesc.label = "Particle"
        particleDesc.vertexFunction = library.makeFunction(
            name: "vertex_particle"
        )
        particleDesc.fragmentFunction = library.makeFunction(
            name: "fragment_particle"
        )
        particleDesc.colorAttachments[0].pixelFormat = hdrFormat
        particleDesc.colorAttachments[0].isBlendingEnabled = true
        particleDesc.colorAttachments[0].rgbBlendOperation = .add
        particleDesc.colorAttachments[0].alphaBlendOperation = .add
        particleDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationRGBBlendFactor =
            .oneMinusSourceAlpha
        particleDesc.depthAttachmentPixelFormat = depthFormat
        particleDesc.stencilAttachmentPixelFormat = depthFormat
        particlePipelineState = try device.makeRenderPipelineState(
            descriptor: particleDesc
        )
        let additiveDesc = MTLRenderPipelineDescriptor()
        additiveDesc.label = "Particle Additive"
        additiveDesc.vertexFunction = library.makeFunction(
            name: "vertex_particle"
        )
        additiveDesc.fragmentFunction = library.makeFunction(
            name: "fragment_particle"
        )
        additiveDesc.colorAttachments[0].pixelFormat = hdrFormat
        additiveDesc.colorAttachments[0].isBlendingEnabled = true
        additiveDesc.colorAttachments[0].rgbBlendOperation = .add
        additiveDesc.colorAttachments[0].alphaBlendOperation = .add
        additiveDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        additiveDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        additiveDesc.depthAttachmentPixelFormat = depthFormat
        additiveDesc.stencilAttachmentPixelFormat = depthFormat
        additiveParticlePipelineState = try device.makeRenderPipelineState(
            descriptor: additiveDesc
        )
        let postDesc = MTLRenderPipelineDescriptor()
        postDesc.vertexFunction = library.makeFunction(name: "vertex_post")
        postDesc.colorAttachments[0].pixelFormat = hdrFormat
        postDesc.depthAttachmentPixelFormat = .invalid
        postDesc.stencilAttachmentPixelFormat = .invalid
        postDesc.fragmentFunction = library.makeFunction(
            name: "fragment_extract"
        )
        extractPipeline = try device.makeRenderPipelineState(
            descriptor: postDesc
        )
        postDesc.fragmentFunction = library.makeFunction(name: "fragment_blur")
        blurPipeline = try device.makeRenderPipelineState(descriptor: postDesc)
        postDesc.fragmentFunction = library.makeFunction(
            name: "fragment_upsample"
        )
        upsamplePipeline = try device.makeRenderPipelineState(
            descriptor: postDesc
        )
        postDesc.fragmentFunction = library.makeFunction(name: "fragment_final")
        postDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        postDesc.depthAttachmentPixelFormat = depthFormat
        postDesc.stencilAttachmentPixelFormat = depthFormat
        finalPipeline = try device.makeRenderPipelineState(descriptor: postDesc)
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.normalizedCoordinates = true
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
        setupDepthStencilStates()
    }

    func setupDepthStencilStates() {
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.isDepthWriteEnabled = true
        depthDesc.depthCompareFunction = .lessEqual
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)
        let depthDisabledDesc = MTLDepthStencilDescriptor()
        depthDisabledDesc.isDepthWriteEnabled = false
        depthDisabledDesc.depthCompareFunction = .lessEqual
        depthWriteDisabledState = device.makeDepthStencilState(
            descriptor: depthDisabledDesc
        )
        let maskWriteDesc = MTLDepthStencilDescriptor()
        maskWriteDesc.isDepthWriteEnabled = false
        maskWriteDesc.depthCompareFunction = .always
        let sw = MTLStencilDescriptor()
        sw.stencilCompareFunction = .always
        sw.stencilFailureOperation = .keep
        sw.depthFailureOperation = .keep
        sw.depthStencilPassOperation = .replace
        sw.readMask = 0xFF
        sw.writeMask = 0xFF
        maskWriteDesc.frontFaceStencil = sw
        maskWriteDesc.backFaceStencil = sw
        maskWriteState = device.makeDepthStencilState(descriptor: maskWriteDesc)
        let maskTestDesc = MTLDepthStencilDescriptor()
        maskTestDesc.isDepthWriteEnabled = false
        maskTestDesc.depthCompareFunction = .always
        let st = MTLStencilDescriptor()
        st.stencilCompareFunction = .equal
        st.stencilFailureOperation = .keep
        st.depthFailureOperation = .keep
        st.depthStencilPassOperation = .keep
        st.readMask = 0xFF
        st.writeMask = 0x00
        maskTestDesc.frontFaceStencil = st
        maskTestDesc.backFaceStencil = st
        maskTestState = device.makeDepthStencilState(descriptor: maskTestDesc)
    }

    func loadScene(folder: URL) async {
        let secured = folder.startAccessingSecurityScopedResource()
        defer { if secured { folder.stopAccessingSecurityScopedResource() } }
        self.baseFolder = folder
        renderables.removeAll()
        await TextureManager.shared.setup(device: device)
        await TextureManager.shared.clear()
        startTime = Date()
        lastTime = 0
        let projectURL = folder.appendingPathComponent("project.json")
        do {
            let projData = try Data(contentsOf: projectURL)
            guard
                let projJson = try JSONSerialization.jsonObject(
                    with: projData,
                    options: []
                ) as? [String: Any],
                let sceneFile = projJson["file"] as? String
            else { return }
            let sceneURL = folder.appendingPathComponent(sceneFile)
            let sceneData = try Data(contentsOf: sceneURL)
            let sceneRoot = try JSONDecoder().decode(
                SceneRoot.self,
                from: sceneData
            )
            
            var isBloomEnabled = true
            if let sceneDict = try? JSONSerialization.jsonObject(with: sceneData) as? [String: Any],
               let genDict = sceneDict["general"] as? [String: Any],
               let bloom = genDict["bloom"] as? Bool {
                isBloomEnabled = bloom
            }
            
            if let gen = sceneRoot.general {
                self.bloomThreshold = gen.bloomhdrthreshold ?? 1.0
                self.bloomStrength = isBloomEnabled ? (gen.bloomhdrstrength ?? 2.0) : 0.0
                self.bloomIterations = isBloomEnabled ? (gen.bloomhdriterations ?? 8) : 0
            }
            if let proj = sceneRoot.general?.orthogonalprojection {
                self.projectionSize = CGSize(
                    width: Double(proj.width),
                    height: Double(proj.height)
                )
            }
            if let fov = sceneRoot.general?.fov { self.currentFOV = fov }
            if let overrideFov = sceneRoot.general?.perspectiveoverridefov,
                overrideFov > 0
            {
                self.currentFOV = overrideFov
            }
            var tempRenderables: [Int: RenderableObject] = [:]
            var orderedList: [RenderableObject] = []
            for obj in sceneRoot.objects {
                if !obj.isVisible { continue }
                if let particleFile = obj.particle {
                    let directURL = folder.appendingPathComponent(particleFile)
                    let pFolderURL = folder.appendingPathComponent(
                        "particles/\(particleFile)"
                    )
                    let aFolderURL = folder.appendingPathComponent(
                        "assets/\(particleFile)"
                    )
                    var finalURL = directURL
                    if FileManager.default.fileExists(atPath: directURL.path) {
                        finalURL = directURL
                    } else if FileManager.default.fileExists(
                        atPath: pFolderURL.path
                    ) {
                        finalURL = pFolderURL
                    } else if FileManager.default.fileExists(
                        atPath: aFolderURL.path
                    ) {
                        finalURL = aFolderURL
                    }
                    if let pData = try? Data(contentsOf: finalURL),
                        let pJson = try? JSONSerialization.jsonObject(
                            with: pData
                        ) as? [String: Any],
                        let sys = ParticleBuilder.buildSystem(
                            from: pJson,
                            baseFolder: folder,
                            overrideData: obj.instanceoverride
                        )
                    {
                        if let pipeline = particlePipelineState {
                            let addPipeline =
                                additiveParticlePipelineState ?? pipeline
                            let pr = ParticleSystemRenderable(
                                device: device,
                                system: sys,
                                pipeline: pipeline,
                                additivePipeline: addPipeline,
                                depthState: depthWriteDisabledState
                            )
                            let (pos, rotation, size, scale) =
                                RenderableObject.parseTransforms(obj)
                            pr.localPosition = pos
                            pr.localRotation = rotation
                            pr.size = size
                            pr.scale = scale
                            for sub in sys.subSystems {
                                await loadParticleTextures(
                                    sub: sub,
                                    folder: folder
                                )
                            }
                            if let id = obj.id {
                                tempRenderables[id] = pr
                                pr.id = id
                            }
                            pr.parentId = obj.parent
                            orderedList.append(pr)
                        }
                        continue
                    }
                }
                if let renderable = await createRenderable(from: obj) {
                    if let id = obj.id {
                        tempRenderables[id] = renderable
                        renderable.id = id
                    }
                    renderable.parentId = obj.parent
                    orderedList.append(renderable)
                }
            }
            for renderable in orderedList {
                if let pid = renderable.parentId,
                    let parentObj = tempRenderables[pid]
                {
                    renderable.parent = parentObj
                }
            }
            self.renderables.append(contentsOf: orderedList)
        } catch {  }
    }

    func loadParticleTextures(sub: ParticleSubSystem, folder: URL) async {
        let matPath = sub.material.fileName
        var textureName: String?
        if !matPath.isEmpty {
            let potentialPaths = [
                "materials/\(matPath)", "assets/\(matPath)", matPath,
            ]
            for path in potentialPaths {
                let url = folder.appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: url.path),
                    let data = try? Data(contentsOf: url),
                    let json = try? JSONSerialization.jsonObject(with: data)
                        as? [String: Any],
                    let passes = json["passes"] as? [[String: Any]],
                    let firstPass = passes.first
                {
                    if let blend = firstPass["blending"] as? String {
                        sub.material.blending = blend
                    }
                    if let textures = firstPass["textures"] as? [String],
                        let firstTex = textures.first
                    {
                        textureName = firstTex
                    }
                    break
                }
            }
            let finalTexPath = textureName ?? matPath
            if !finalTexPath.isEmpty {
                let texURL = resolveTextureURL(
                    base: folder,
                    rawPath: finalTexPath
                )
                do {
                    let tex = try await TextureManager.shared.loadTexture(
                        url: texURL,
                        options: [
                            .origin: MTKTextureLoader.Origin.bottomLeft,
                            .SRGB: true,
                        ]
                    )
                    sub.texture = tex
                } catch {  }
            }
        }
        for child in sub.children {
            await loadParticleTextures(sub: child, folder: folder)
        }
    }

    func createRenderable(from obj: SceneObject) async -> RenderableObject? {
        guard let base = baseFolder, let imagePath = obj.image else {
            return nil
        }
        let modelURL = base.appendingPathComponent(imagePath)
        let fileName = modelURL.deletingPathExtension().lastPathComponent
        let puppetDataURL = modelURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileName)_puppet_data.json")
        let puppetObjURL = modelURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileName)_puppet.obj")
        if FileManager.default.fileExists(atPath: puppetDataURL.path) {
            return await createPuppetRenderable(
                from: obj,
                dataURL: puppetDataURL,
                objURL: puppetObjURL
            )
        }
        do {
            let modelData = try Data(contentsOf: modelURL)
            let modelDef = try JSONDecoder().decode(
                ModelJSON.self,
                from: modelData
            )
            guard let matPath = modelDef.material else { return nil }
            let matURL = base.appendingPathComponent(matPath)
            let matData = try Data(contentsOf: matURL)
            let matDef = try JSONDecoder().decode(
                MaterialJSON.self,
                from: matData
            )
            guard let firstPass = matDef.passes.first,
                let texName = firstPass.textures.first
            else { return nil }
            let texURL = resolveTextureURL(base: base, rawPath: texName)
            let texture = try await TextureManager.shared.loadTexture(
                url: texURL,
                options: [
                    .origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: true,
                ]
            )
            let (pos, rotation, size, scale) = RenderableObject.parseTransforms(
                obj
            )
            var depthState = depthStencilState
            if let dw = firstPass.depthwrite, dw == "disabled" {
                depthState = depthWriteDisabledState
            }
            guard let pipeline = pipelineState else { return nil }
            return RenderableObject(
                position: pos,
                rotation: rotation,
                size: size,
                scale: scale,
                texture: texture,
                pipeline: pipeline,
                depthState: depthState
            )
        } catch { return nil }
    }

    func createPuppetRenderable(
        from obj: SceneObject,
        dataURL: URL,
        objURL: URL
    ) async -> RenderableObject? {
        do {
            let jsonData = try Data(contentsOf: dataURL)
            let puppetData = try JSONDecoder().decode(
                PuppetData.self,
                from: jsonData
            )
            let objContent = try String(contentsOf: objURL, encoding: .utf8)
            guard let matFile = puppetData.info.material_file,
                let base = baseFolder
            else { return nil }
            let matURL = base.appendingPathComponent(matFile)
            let matData = try Data(contentsOf: matURL)
            let matDef = try JSONDecoder().decode(
                MaterialJSON.self,
                from: matData
            )
            guard let firstPass = matDef.passes.first,
                let texName = firstPass.textures.first
            else { return nil }
            let texURL = resolveTextureURL(base: base, rawPath: texName)
            let texture = try await TextureManager.shared.loadTexture(
                url: texURL,
                options: [
                    .origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: true,
                ]
            )
            let (vertices, indices, triangleBoneIndices, bboxWidth) =
                PuppetRenderable.parseOBJ(
                    objContent: objContent,
                    skinning: puppetData.skinning
                )
            let (pos, rotation, size, scale) = RenderableObject.parseTransforms(
                obj
            )
            var depthState = depthStencilState
            if let dw = firstPass.depthwrite, dw == "disabled" {
                depthState = depthWriteDisabledState
            }
            guard let pipeline = puppetPipelineState else { return nil }
            return PuppetRenderable(
                device: device,
                vertices: vertices,
                indices: indices,
                triangleBones: triangleBoneIndices,
                skeleton: puppetData.skeleton,
                animations: puppetData.animations,
                position: pos,
                rotation: rotation,
                size: size,
                scale: scale,
                texture: texture,
                pipeline: pipeline,
                depthState: depthState,
                maskWriteState: maskWriteState,
                maskTestState: maskTestState,
                usePixelCoords: bboxWidth > 2.0
            )
        } catch { return nil }
    }

    func resolveTextureURL(base: URL, rawPath: String) -> URL {
        let extensions = ["png", "webp", "tga", "mp4"]
        let fileName = URL(fileURLWithPath: rawPath).lastPathComponent
        for ext in extensions {
            let directURL = base.appendingPathComponent(
                "materials/\(rawPath).\(ext)"
            )
            if FileManager.default.fileExists(atPath: directURL.path) {
                return directURL
            }
            let flatURL = base.appendingPathComponent(
                "materials/\(fileName).\(ext)"
            )
            if FileManager.default.fileExists(atPath: flatURL.path) {
                return flatURL
            }
            let folderURL = base.appendingPathComponent(rawPath)
                .appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                return folderURL
            }
        }
        return base.appendingPathComponent("materials/\(fileName).png")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        hdrTexture = device.makeTexture(descriptor: desc)
        bloomTextures.removeAll()
        bloomTempTextures.removeAll()
        var w = Int(size.width)
        var h = Int(size.height)
        for _ in 0...bloomIterations {
            let bDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: w,
                height: h,
                mipmapped: false
            )
            bDesc.usage = [.renderTarget, .shaderRead]
            if let tex = device.makeTexture(descriptor: bDesc) {
                bloomTextures.append(tex)
            }
            if let tTex = device.makeTexture(descriptor: bDesc) {
                bloomTempTextures.append(tTex)
            }
            w = max(1, w / 2)
            h = max(1, h / 2)
        }
    }

    private func makePerspective(
        fovyRadians: Float,
        aspect: Float,
        near: Float,
        far: Float
    ) -> matrix_float4x4 {
        let ys = 1 / tanf(fovyRadians * 0.5)
        let xs = ys / aspect
        let zs = far / (near - far)
        return matrix_float4x4.init(
            columns: (
                vector_float4(xs, 0, 0, 0), vector_float4(0, ys, 0, 0),
                vector_float4(0, 0, zs, -1), vector_float4(0, 0, zs * near, 0)
            )
        )
    }

    private func makeLookAt(
        eye: SIMD3<Float>,
        center: SIMD3<Float>,
        up: SIMD3<Float>
    ) -> matrix_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        let t = SIMD3<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye))
        return matrix_float4x4.init(
            columns: (
                vector_float4(x.x, y.x, z.x, 0),
                vector_float4(x.y, y.y, z.y, 0),
                vector_float4(x.z, y.z, z.z, 0), vector_float4(t.x, t.y, t.z, 1)
            )
        )
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let hdrTex = hdrTexture,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }
        let hdrPassDesc = MTLRenderPassDescriptor()
        hdrPassDesc.colorAttachments[0].texture = hdrTex
        hdrPassDesc.colorAttachments[0].loadAction = .clear
        hdrPassDesc.colorAttachments[0].storeAction = .store
        hdrPassDesc.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1
        )
        hdrPassDesc.depthAttachment.texture = descriptor.depthAttachment.texture
        hdrPassDesc.depthAttachment.loadAction = .clear
        hdrPassDesc.depthAttachment.storeAction = .dontCare
        hdrPassDesc.depthAttachment.clearDepth = 1.0
        hdrPassDesc.stencilAttachment.texture =
            descriptor.stencilAttachment.texture
        hdrPassDesc.stencilAttachment.loadAction = .clear
        hdrPassDesc.stencilAttachment.storeAction = .dontCare
        hdrPassDesc.stencilAttachment.clearStencil = 0
        guard
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: hdrPassDesc
            )
        else { return }
        encoder.setCullMode(.none)
        let targetAspect = Double(projectionSize.width / projectionSize.height)
        let currentAspect = Double(
            view.drawableSize.width / view.drawableSize.height
        )
        var drawWidth = Double(view.drawableSize.width)
        var drawHeight = Double(view.drawableSize.height)
        var vx: Double = 0
        var vy: Double = 0
        if currentAspect > targetAspect {
            drawWidth = Double(view.drawableSize.height) * targetAspect
            vx = (Double(view.drawableSize.width) - drawWidth) / 2
        } else {
            drawHeight = Double(view.drawableSize.width) / targetAspect
            vy = (Double(view.drawableSize.height) - drawHeight) / 2
        }
        encoder.setViewport(
            MTLViewport(
                originX: vx,
                originY: vy,
                width: drawWidth,
                height: drawHeight,
                znear: 0,
                zfar: 1
            )
        )
        let fov = currentFOV * (.pi / 180.0)
        let aspect = Float(projectionSize.width / projectionSize.height)
        let camDist = (Float(projectionSize.height) / 2.0) / tan(fov / 2.0)
        let proj = makePerspective(
            fovyRadians: fov,
            aspect: aspect,
            near: 10.0,
            far: 10000.0
        )
        let viewMat = makeLookAt(
            eye: SIMD3<Float>(
                Float(projectionSize.width) / 2,
                Float(projectionSize.height) / 2,
                camDist
            ),
            center: SIMD3<Float>(
                Float(projectionSize.width) / 2,
                Float(projectionSize.height) / 2,
                0
            ),
            up: SIMD3<Float>(0, 1, 0)
        )
        let currentTime = Date().timeIntervalSince(startTime)
        let dt = currentTime - lastTime
        lastTime = currentTime
        let time = Float(currentTime)
        var globals = GlobalUniforms(
            projectionMatrix: proj,
            viewMatrix: viewMat,
            time: time
        )
        if let sampler = samplerState {
            encoder.setFragmentSamplerState(sampler, index: 0)
        }
        for obj in renderables {
            encoder.setVertexBytes(
                &globals,
                length: MemoryLayout<GlobalUniforms>.size,
                index: 1
            )
            encoder.setFragmentBytes(
                &globals,
                length: MemoryLayout<GlobalUniforms>.size,
                index: 1
            )
            if let puppet = obj as? PuppetRenderable {
                puppet.updateAnimation(time: time)
            }
            if let particle = obj as? ParticleSystemRenderable {
                particle.update(dt: dt)
                particle.projectionMatrix = proj
                particle.viewMatrix = viewMat
            }
            obj.draw(encoder: encoder)
        }
        encoder.endEncoding()
        if bloomTextures.count > 1 {
            let extractDesc = MTLRenderPassDescriptor()
            extractDesc.colorAttachments[0].texture = bloomTextures[0]
            extractDesc.colorAttachments[0].loadAction = .clear
            if let exEnc = commandBuffer.makeRenderCommandEncoder(
                descriptor: extractDesc
            ) {
                exEnc.setRenderPipelineState(extractPipeline!)
                exEnc.setFragmentTexture(hdrTex, index: 0)
                exEnc.setFragmentSamplerState(samplerState, index: 0)
                exEnc.setFragmentBytes(&bloomThreshold, length: 4, index: 0)
                exEnc.drawPrimitives(
                    type: .triangleStrip,
                    vertexStart: 0,
                    vertexCount: 4
                )
                exEnc.endEncoding()
            }
            for i in 0..<bloomTextures.count - 1 {
                let blurHDesc = MTLRenderPassDescriptor()
                blurHDesc.colorAttachments[0].texture = bloomTempTextures[i + 1]
                if let encH = commandBuffer.makeRenderCommandEncoder(
                    descriptor: blurHDesc
                ) {
                    var horiz = true
                    encH.setRenderPipelineState(blurPipeline!)
                    encH.setFragmentTexture(bloomTextures[i], index: 0)
                    encH.setFragmentSamplerState(samplerState, index: 0)
                    encH.setFragmentBytes(&horiz, length: 1, index: 0)
                    encH.drawPrimitives(
                        type: .triangleStrip,
                        vertexStart: 0,
                        vertexCount: 4
                    )
                    encH.endEncoding()
                }
                let blurVDesc = MTLRenderPassDescriptor()
                blurVDesc.colorAttachments[0].texture = bloomTextures[i + 1]
                if let encV = commandBuffer.makeRenderCommandEncoder(
                    descriptor: blurVDesc
                ) {
                    var horiz = false
                    encV.setRenderPipelineState(blurPipeline!)
                    encV.setFragmentTexture(bloomTempTextures[i + 1], index: 0)
                    encV.setFragmentSamplerState(samplerState, index: 0)
                    encV.setFragmentBytes(&horiz, length: 1, index: 0)
                    encV.drawPrimitives(
                        type: .triangleStrip,
                        vertexStart: 0,
                        vertexCount: 4
                    )
                    encV.endEncoding()
                }
            }
            for i in stride(from: bloomTextures.count - 1, to: 0, by: -1) {
                let upDesc = MTLRenderPassDescriptor()
                upDesc.colorAttachments[0].texture = bloomTempTextures[i - 1]
                if let upEnc = commandBuffer.makeRenderCommandEncoder(
                    descriptor: upDesc
                ) {
                    upEnc.setRenderPipelineState(upsamplePipeline!)
                    upEnc.setFragmentTexture(bloomTextures[i - 1], index: 0)
                    upEnc.setFragmentTexture(bloomTextures[i], index: 1)
                    upEnc.setFragmentSamplerState(samplerState, index: 0)
                    upEnc.drawPrimitives(
                        type: .triangleStrip,
                        vertexStart: 0,
                        vertexCount: 4
                    )
                    upEnc.endEncoding()
                }
                let blurFDesc = MTLRenderPassDescriptor()
                blurFDesc.colorAttachments[0].texture = bloomTextures[i - 1]
                if let fEnc = commandBuffer.makeRenderCommandEncoder(
                    descriptor: blurFDesc
                ) {
                    var horiz = true
                    fEnc.setRenderPipelineState(blurPipeline!)
                    fEnc.setFragmentTexture(bloomTempTextures[i - 1], index: 0)
                    fEnc.setFragmentSamplerState(samplerState, index: 0)
                    fEnc.setFragmentBytes(&horiz, length: 1, index: 0)
                    fEnc.drawPrimitives(
                        type: .triangleStrip,
                        vertexStart: 0,
                        vertexCount: 4
                    )
                    fEnc.endEncoding()
                }
            }
        }
        if let finalEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) {
            finalEncoder.setRenderPipelineState(finalPipeline!)
            finalEncoder.setFragmentTexture(hdrTex, index: 0)
            finalEncoder.setFragmentTexture(bloomTextures[0], index: 1)
            finalEncoder.setFragmentSamplerState(samplerState, index: 0)
            finalEncoder.setFragmentBytes(&bloomStrength, length: 4, index: 0)
            finalEncoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4
            )
            finalEncoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
