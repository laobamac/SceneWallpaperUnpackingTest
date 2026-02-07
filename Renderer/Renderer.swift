//
//  Renderer.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import MetalKit
import simd

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState?
    var puppetPipelineState: MTLRenderPipelineState?
    var samplerState: MTLSamplerState?
    
    var depthStencilState: MTLDepthStencilState?
    var maskWriteState: MTLDepthStencilState?
    var maskTestState: MTLDepthStencilState?
    
    var textureLoader: MTKTextureLoader
    var baseFolder: URL?
    var renderables: [RenderableObject] = []
    
    var startTime: Date = Date()
    var projectionSize: CGSize = CGSize(width: 1920, height: 1080)
    
    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            Logger.error("Failed to create command queue")
            return nil
        }
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)
        super.init()
        
        do {
            try setupPipeline()
            Logger.log("Renderer initialized successfully")
        } catch {
            Logger.error("Pipeline setup failed: \(error)")
            return nil
        }
    }
    
    func setupPipeline() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw NSError(domain: "Renderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create default library"])
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Standard Pipeline"
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = 20
        descriptor.vertexDescriptor = vertexDescriptor
        
        pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        
        let puppetDesc = MTLRenderPipelineDescriptor()
        puppetDesc.label = "Puppet Pipeline"
        puppetDesc.vertexFunction = library.makeFunction(name: "vertex_puppet")
        puppetDesc.fragmentFunction = library.makeFunction(name: "fragment_main")
        puppetDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        puppetDesc.colorAttachments[0].isBlendingEnabled = true
        puppetDesc.colorAttachments[0].rgbBlendOperation = .add
        puppetDesc.colorAttachments[0].alphaBlendOperation = .add
        puppetDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        puppetDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        puppetDesc.depthAttachmentPixelFormat = .depth32Float_stencil8
        puppetDesc.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        let pvDesc = MTLVertexDescriptor()
        var offset = 0
        
        pvDesc.attributes[0].format = .float3; pvDesc.attributes[0].offset = offset; pvDesc.attributes[0].bufferIndex = 0
        offset += 16
        
        pvDesc.attributes[1].format = .float2; pvDesc.attributes[1].offset = offset; pvDesc.attributes[1].bufferIndex = 0
        offset += 8
        
        pvDesc.attributes[2].format = .ushort4; pvDesc.attributes[2].offset = offset; pvDesc.attributes[2].bufferIndex = 0
        offset += 8
        
        pvDesc.attributes[3].format = .float4; pvDesc.attributes[3].offset = offset; pvDesc.attributes[3].bufferIndex = 0
        offset += 16
        
        pvDesc.layouts[0].stride = 48
        puppetDesc.vertexDescriptor = pvDesc
        
        puppetPipelineState = try device.makeRenderPipelineState(descriptor: puppetDesc)
        
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear; samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge; samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.normalizedCoordinates = true
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
        
        setupDepthStencilStates()
    }
    
    func setupDepthStencilStates() {
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.isDepthWriteEnabled = false
        depthDesc.depthCompareFunction = .always
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)
        
        let maskWriteDesc = MTLDepthStencilDescriptor()
        maskWriteDesc.isDepthWriteEnabled = false
        maskWriteDesc.depthCompareFunction = .always
        let sw = MTLStencilDescriptor()
        sw.stencilCompareFunction = .always
        sw.stencilFailureOperation = .keep
        sw.depthFailureOperation = .keep
        sw.depthStencilPassOperation = .replace
        sw.readMask = 0xFF; sw.writeMask = 0xFF
        maskWriteDesc.frontFaceStencil = sw; maskWriteDesc.backFaceStencil = sw
        maskWriteState = device.makeDepthStencilState(descriptor: maskWriteDesc)
        
        let maskTestDesc = MTLDepthStencilDescriptor()
        maskTestDesc.isDepthWriteEnabled = false
        maskTestDesc.depthCompareFunction = .always
        let st = MTLStencilDescriptor()
        st.stencilCompareFunction = .equal
        st.stencilFailureOperation = .keep
        st.depthFailureOperation = .keep
        st.depthStencilPassOperation = .keep
        st.readMask = 0xFF; st.writeMask = 0x00
        maskTestDesc.frontFaceStencil = st; maskTestDesc.backFaceStencil = st
        maskTestState = device.makeDepthStencilState(descriptor: maskTestDesc)
    }
    
    func loadScene(folder: URL) {
        Logger.log("=== Loading Scene: \(folder.lastPathComponent) ===")
        let secured = folder.startAccessingSecurityScopedResource()
        defer { if secured { folder.stopAccessingSecurityScopedResource() } }
        
        self.baseFolder = folder
        renderables.removeAll()
        startTime = Date()
        
        let projectURL = folder.appendingPathComponent("project.json")
        do {
            let projData = try Data(contentsOf: projectURL)
            guard let projJson = try JSONSerialization.jsonObject(with: projData, options: []) as? [String: Any],
                  let sceneFile = projJson["file"] as? String else {
                Logger.error("Invalid project.json format")
                return
            }
            
            let sceneURL = folder.appendingPathComponent(sceneFile)
            let sceneData = try Data(contentsOf: sceneURL)
            let sceneRoot = try JSONDecoder().decode(SceneRoot.self, from: sceneData)
            
            if let proj = sceneRoot.general?.orthogonalprojection {
                self.projectionSize = CGSize(width: Double(proj.width), height: Double(proj.height))
            }
            
            var tempRenderables: [Int: RenderableObject] = [:]
            var orderedList: [RenderableObject] = []
            
            for obj in sceneRoot.objects {
                if !obj.isVisible { continue }
                if let renderable = createRenderable(from: obj) {
                    if let id = obj.id {
                        tempRenderables[id] = renderable
                        renderable.id = id
                    }
                    renderable.parentId = obj.parent
                    orderedList.append(renderable)
                }
            }
            
            for renderable in orderedList {
                if let pid = renderable.parentId, let parentObj = tempRenderables[pid] {
                    renderable.parent = parentObj
                }
            }
            
            self.renderables = orderedList
            Logger.log("Scene loaded successfully. Objects count: \(renderables.count)")
            
        } catch {
            Logger.error("Failed to load scene: \(error)")
        }
    }
    
    func createRenderable(from obj: SceneObject) -> RenderableObject? {
        guard let imagePath = obj.image, let base = baseFolder else { return nil }
        let modelURL = base.appendingPathComponent(imagePath)
        let fileName = modelURL.deletingPathExtension().lastPathComponent
        
        let puppetDataURL = modelURL.deletingLastPathComponent().appendingPathComponent("\(fileName)_puppet_data.json")
        let puppetObjURL = modelURL.deletingLastPathComponent().appendingPathComponent("\(fileName)_puppet.obj")
        
        if FileManager.default.fileExists(atPath: puppetDataURL.path) {
            return createPuppetRenderable(from: obj, dataURL: puppetDataURL, objURL: puppetObjURL)
        }
        
        do {
            let modelData = try Data(contentsOf: modelURL)
            let modelDef = try JSONDecoder().decode(ModelJSON.self, from: modelData)
            guard let matPath = modelDef.material else { return nil }
            
            let matURL = base.appendingPathComponent(matPath)
            let matData = try Data(contentsOf: matURL)
            let matDef = try JSONDecoder().decode(MaterialJSON.self, from: matData)
            guard let firstPass = matDef.passes.first, let texName = firstPass.textures.first else { return nil }
            
            let texURL = resolveTextureURL(base: base, rawPath: texName)
            let texture = try textureLoader.newTexture(URL: texURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false])
            
            let (pos, rotation, size, scale) = RenderableObject.parseTransforms(obj)
            
            guard let pipeline = pipelineState else { return nil }
            return RenderableObject(position: pos, rotation: rotation, size: size, scale: scale, texture: texture, pipeline: pipeline, depthState: depthStencilState)
        } catch {
            Logger.error("Error creating static renderable: \(error)")
            return nil
        }
    }
    
    func createPuppetRenderable(from obj: SceneObject, dataURL: URL, objURL: URL) -> RenderableObject? {
        do {
            let jsonData = try Data(contentsOf: dataURL)
            let puppetData = try JSONDecoder().decode(PuppetData.self, from: jsonData)
            let objContent = try String(contentsOf: objURL, encoding: .utf8)
            
            guard let matFile = puppetData.info.material_file, let base = baseFolder else { return nil }
            let matURL = base.appendingPathComponent(matFile)
            let matData = try Data(contentsOf: matURL)
            let matDef = try JSONDecoder().decode(MaterialJSON.self, from: matData)
            
            guard let firstPass = matDef.passes.first, let texName = firstPass.textures.first else { return nil }
            
            let texURL = resolveTextureURL(base: base, rawPath: texName)
            let texture = try textureLoader.newTexture(URL: texURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false])

            let (vertices, indices, triangleBoneIndices, bboxWidth) = PuppetRenderable.parseOBJ(objContent: objContent, skinning: puppetData.skinning)
            let usePixelCoords = bboxWidth > 2.0
            
            let (pos, rotation, size, scale) = RenderableObject.parseTransforms(obj)
            
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
                depthState: depthStencilState,
                maskWriteState: maskWriteState,
                maskTestState: maskTestState,
                usePixelCoords: usePixelCoords
            )
        } catch {
            Logger.error("Error creating puppet renderable: \(error)")
            return nil
        }
    }
    
    func resolveTextureURL(base: URL, rawPath: String) -> URL {
        let extensions = ["png", "jpg", "jpeg", "tga", "bmp"]
        let fileName = URL(fileURLWithPath: rawPath).lastPathComponent
            
        for ext in extensions {
            let directURL = base.appendingPathComponent("materials/\(rawPath).\(ext)")
            if FileManager.default.fileExists(atPath: directURL.path) {
                return directURL
            }
                
            let flatURL = base.appendingPathComponent("materials/\(fileName).\(ext)")
            if FileManager.default.fileExists(atPath: flatURL.path) {
                return flatURL
            }
        }
        
        return base.appendingPathComponent("materials/\(fileName).png")
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        descriptor.depthAttachment.clearDepth = 1.0
        descriptor.stencilAttachment.clearStencil = 0
        
        encoder.setCullMode(.none)
        
        let proj = Matrix4x4.orthographic(left: 0, right: Float(projectionSize.width), bottom: 0, top: Float(projectionSize.height), near: -5000, far: 5000)
        let time = Float(Date().timeIntervalSince(startTime))
        var globals = GlobalUniforms(projectionMatrix: proj, viewMatrix: matrix_identity_float4x4, time: time)
        
        encoder.setVertexBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
        encoder.setFragmentBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
        
        if let sampler = samplerState {
            encoder.setFragmentSamplerState(sampler, index: 0)
        }
        
        for obj in renderables {
            if let puppet = obj as? PuppetRenderable {
                puppet.updateAnimation(time: time)
            }
            obj.draw(encoder: encoder)
        }
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
