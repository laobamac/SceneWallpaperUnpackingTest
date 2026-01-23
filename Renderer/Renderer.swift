import MetalKit
import simd

// MARK: - 核心数据结构 (Aligned for Metal)

/// 特效参数 (与 Shaders.metal 中的 struct EffectParams 对应)
struct EffectParams {
    var type: Int32         // 0: None, 1: Scroll, 2: WaterWave, 3: Shake
    var maskIndex: Int32    // 遮罩纹理索引 (-1 表示无)
    var speed: Float
    var scale: Float
    var strength: Float
    var exponent: Float
    var direction: SIMD2<Float>
    var bounds: SIMD2<Float>
    var friction: SIMD2<Float>
}

/// 对象通用参数
struct ObjectUniforms {
    var modelMatrix: matrix_float4x4
    var alpha: Float
    var color: SIMD4<Float>
    var padding: SIMD4<Float> = .zero
}

/// 全局参数
struct GlobalUniforms {
    var projectionMatrix: matrix_float4x4
    var viewMatrix: matrix_float4x4
    var time: Float
    var padding: SIMD3<Float> = .zero
}

/// 骨骼动画顶点结构
struct PuppetVertex {
    var px: Float, py: Float, pz: Float
    var pad1: Float = 0
    var u: Float, v: Float
    var j1: UInt16, j2: UInt16, j3: UInt16, j4: UInt16 // 骨骼索引
    var w1: Float, w2: Float, w3: Float, w4: Float    // 骨骼权重
}

// MARK: - 渲染器核心类

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!
    var puppetPipelineState: MTLRenderPipelineState!
    var samplerState: MTLSamplerState!
    
    // 深度和模板状态 (用于处理遮罩/裁剪逻辑)
    var depthStencilState: MTLDepthStencilState!      // 普通绘制 (无模板)
    var maskWriteState: MTLDepthStencilState!         // 写入遮罩 (Stencil = 1)
    var maskTestState: MTLDepthStencilState!          // 裁剪测试 (仅绘制 Stencil == 1 区域)
    
    var textureLoader: MTKTextureLoader
    var baseFolder: URL?
    var renderables: [RenderableObject] = []
    
    var startTime: Date = Date()
    var projectionSize: CGSize = CGSize(width: 1920, height: 1080)
    
    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)
        super.init()
        setupPipeline()
    }
    
    // 配置 Metal 渲染管线
    func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else { return }
        
        // 1. 标准静态物体管线
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Standard Pipeline"
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // 开启混合 (Alpha Blending)
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        // 必须设置深度/模板格式，即使静态物体不用
        descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3; vertexDescriptor.attributes[0].offset = 0; vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2; vertexDescriptor.attributes[1].offset = 12; vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 20
        descriptor.vertexDescriptor = vertexDescriptor
        
        try? pipelineState = device.makeRenderPipelineState(descriptor: descriptor)
        
        // 2. 骨骼动画 (Puppet) 管线
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
        // Position, UV, Joints(4), Weights(4)
        pvDesc.attributes[0].format = .float3; pvDesc.attributes[0].offset = 0; pvDesc.attributes[0].bufferIndex = 0
        pvDesc.attributes[1].format = .float2; pvDesc.attributes[1].offset = 16; pvDesc.attributes[1].bufferIndex = 0
        pvDesc.attributes[2].format = .ushort4; pvDesc.attributes[2].offset = 24; pvDesc.attributes[2].bufferIndex = 0
        pvDesc.attributes[3].format = .float4; pvDesc.attributes[3].offset = 32; pvDesc.attributes[3].bufferIndex = 0
        pvDesc.layouts[0].stride = 48
        puppetDesc.vertexDescriptor = pvDesc
        
        try? puppetPipelineState = device.makeRenderPipelineState(descriptor: puppetDesc)
        
        // 采样器
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear; samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge; samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.normalizedCoordinates = true
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
        
        setupDepthStencilStates()
    }
    
    func setupDepthStencilStates() {
        // A. 普通状态：不写入深度，不测试模板
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.isDepthWriteEnabled = false
        depthDesc.depthCompareFunction = .always
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)
        
        // B. 遮罩写入状态：Stencil = 1
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
        
        // C. 遮罩测试状态：Stencil == 1 时才绘制
        let maskTestDesc = MTLDepthStencilDescriptor()
        maskTestDesc.isDepthWriteEnabled = false
        maskTestDesc.depthCompareFunction = .always
        let st = MTLStencilDescriptor()
        st.stencilCompareFunction = .equal
        st.stencilFailureOperation = .keep
        st.depthFailureOperation = .keep
        st.depthStencilPassOperation = .keep
        st.readMask = 0xFF; st.writeMask = 0x00 // 只读
        maskTestDesc.frontFaceStencil = st; maskTestDesc.backFaceStencil = st
        maskTestState = device.makeDepthStencilState(descriptor: maskTestDesc)
    }
    
    // MARK: - 场景加载逻辑
    
    func loadScene(folder: URL) {
        print("=== 正在加载场景: \(folder.lastPathComponent) ===")
        let secured = folder.startAccessingSecurityScopedResource()
        defer { if secured { folder.stopAccessingSecurityScopedResource() } }
        
        self.baseFolder = folder
        renderables.removeAll()
        startTime = Date()
        
        // 1. 读取 project.json 确定场景文件
        let projectURL = folder.appendingPathComponent("project.json")
        guard let projData = try? Data(contentsOf: projectURL),
              let projJson = try? JSONSerialization.jsonObject(with: projData, options: []) as? [String: Any],
              let sceneFile = projJson["file"] as? String else {
            print("错误: 无法读取 project.json 或 file 字段")
            return
        }
        
        // 2. 读取 scene.json
        let sceneURL = folder.appendingPathComponent(sceneFile)
        do {
            let sceneData = try Data(contentsOf: sceneURL)
            let sceneRoot = try JSONDecoder().decode(SceneRoot.self, from: sceneData)
            
            if let proj = sceneRoot.general?.orthogonalprojection {
                self.projectionSize = CGSize(width: Double(proj.width), height: Double(proj.height))
            }
            
            // 3. 构建渲染树
            // 这里我们简化处理，将对象展平成列表，但保留父子变换关系
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
            
            // 4. 链接父子关系
            for renderable in orderedList {
                if let pid = renderable.parentId, let parentObj = tempRenderables[pid] {
                    renderable.parent = parentObj
                }
            }
            
            self.renderables = orderedList
            print("场景加载完成，对象数量: \(renderables.count)")
            
        } catch {
            print("场景 JSON 解析失败: \(error)")
        }
    }
    
    // 工厂方法：根据对象类型创建 Renderable
    func createRenderable(from obj: SceneObject) -> RenderableObject? {
        guard let imagePath = obj.image, let base = baseFolder else { return nil }
        let modelURL = base.appendingPathComponent(imagePath)
        let fileName = modelURL.deletingPathExtension().lastPathComponent
        
        // 检查是否存在 Puppet 数据 (_puppet_data.json)
        let puppetDataURL = modelURL.deletingLastPathComponent().appendingPathComponent("\(fileName)_puppet_data.json")
        let puppetObjURL = modelURL.deletingLastPathComponent().appendingPathComponent("\(fileName)_puppet.obj")
        
        if FileManager.default.fileExists(atPath: puppetDataURL.path) {
            // 创建骨骼动画对象
            return createPuppetRenderable(from: obj, dataURL: puppetDataURL, objURL: puppetObjURL)
        }
        
        // 创建静态图片对象
        guard let modelData = try? Data(contentsOf: modelURL),
              let modelDef = try? JSONDecoder().decode(ModelJSON.self, from: modelData),
              let matPath = modelDef.material else { return nil }
        
        let matURL = base.appendingPathComponent(matPath)
        guard let matData = try? Data(contentsOf: matURL),
              let matDef = try? JSONDecoder().decode(MaterialJSON.self, from: matData),
              let firstPass = matDef.passes.first,
              let texName = firstPass.textures.first else { return nil }
        
        let texURL = resolveTextureURL(base: base, rawPath: texName)
        guard let texture = try? textureLoader.newTexture(URL: texURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) else { return nil }
        
        let (pos, rotation, size, scale) = parseTransforms(obj)
        let (effects, masks) = parseEffects(obj, base: base)
        
        return RenderableObject(position: pos, rotation: rotation, size: size, scale: scale, texture: texture, effects: effects, masks: masks, pipeline: pipelineState, depthState: depthStencilState)
    }
    
    // 创建骨骼对象
    func createPuppetRenderable(from obj: SceneObject, dataURL: URL, objURL: URL) -> RenderableObject? {
        guard let jsonData = try? Data(contentsOf: dataURL),
              let puppetData = try? JSONDecoder().decode(PuppetData.self, from: jsonData),
              let objContent = try? String(contentsOf: objURL, encoding: .utf8) else { return nil }
        
        guard let matFile = puppetData.info.material_file, let base = baseFolder else { return nil }
        let matURL = base.appendingPathComponent(matFile)
        guard let matData = try? Data(contentsOf: matURL),
              let matDef = try? JSONDecoder().decode(MaterialJSON.self, from: matData),
              let firstPass = matDef.passes.first,
              let texName = firstPass.textures.first else { return nil }
        
        let texURL = resolveTextureURL(base: base, rawPath: texName)
        guard let texture = try? textureLoader.newTexture(URL: texURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) else { return nil }

        // 解析 OBJ 生成顶点数据
        let (vertices, indices, triangleBoneIndices, bboxWidth) = parseOBJ(objContent: objContent, skinning: puppetData.skinning)
        
        let usePixelCoords = bboxWidth > 2.0 // 判断是否使用像素坐标系
        
        let (pos, rotation, size, scale) = parseTransforms(obj)
        let (effects, masks) = parseEffects(obj, base: base)
        
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
            effects: effects,
            masks: masks,
            pipeline: puppetPipelineState,
            depthState: depthStencilState,
            maskWriteState: maskWriteState,
            maskTestState: maskTestState,
            usePixelCoords: usePixelCoords
        )
    }
    
    // MARK: - 辅助解析函数
    
    func resolveTextureURL(base: URL, rawPath: String) -> URL {
        // 尝试直接路径
        let directURL = base.appendingPathComponent("materials/\(rawPath).png")
        if FileManager.default.fileExists(atPath: directURL.path) { return directURL }
        // 尝试仅文件名
        let fileName = URL(fileURLWithPath: rawPath).lastPathComponent
        return base.appendingPathComponent("materials/\(fileName).png")
    }
    
    func parseOBJ(objContent: String, skinning: [PuppetSkinning]) -> ([PuppetVertex], [UInt32], [Int], Float) {
        var rawPositions: [SIMD3<Float>] = []
        var rawUVs: [SIMD2<Float>] = []
        var finalVertices: [PuppetVertex] = []
        var finalIndices: [UInt32] = []
        var triangleBoneIndices: [Int] = []
        var uniqueVertexMap: [String: UInt32] = [:]
        
        let skinMap = Dictionary(uniqueKeysWithValues: skinning.map { ($0.vertex_id, $0) })
        var minPos = SIMD3<Float>(10000, 10000, 10000)
        var maxPos = SIMD3<Float>(-10000, -10000, -10000)
        
        let lines = objContent.components(separatedBy: .newlines)
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanLine.isEmpty || cleanLine.hasPrefix("#") { continue }
            let parts = cleanLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            if parts[0] == "v" {
                if parts.count >= 4, let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                    let p = SIMD3<Float>(x, y, z)
                    rawPositions.append(p)
                    minPos = simd_min(minPos, p)
                    maxPos = simd_max(maxPos, p)
                }
            } else if parts[0] == "vt" {
                if parts.count >= 3, let u = Float(parts[1]), let v = Float(parts[2]) {
                    rawUVs.append(SIMD2<Float>(u, 1.0 - v))
                }
            } else if parts[0] == "f" {
                var faceIndices: [UInt32] = []
                var dominantBone = -1
                
                for i in 1..<parts.count {
                    let component = parts[i]
                    let subParts = component.components(separatedBy: "/")
                    guard let posIdxRaw = Int(subParts[0]) else { continue }
                    let posIdx = posIdxRaw - 1
                    
                    var uvIdx = 0
                    if subParts.count > 1, let tIdx = Int(subParts[1]) { uvIdx = tIdx - 1 } else { uvIdx = posIdx }
                    
                    let key = "\(posIdx)/\(uvIdx)"
                    
                    if let existingIndex = uniqueVertexMap[key] {
                        faceIndices.append(existingIndex)
                        if dominantBone == -1 {
                             let v = finalVertices[Int(existingIndex)]
                             if v.w1 > 0.5 { dominantBone = Int(v.j1) }
                        }
                    } else {
                        let newIndex = UInt32(finalVertices.count)
                        let position = (posIdx >= 0 && posIdx < rawPositions.count) ? rawPositions[posIdx] : SIMD3<Float>(0,0,0)
                        let texCoord = (uvIdx >= 0 && uvIdx < rawUVs.count) ? rawUVs[uvIdx] : SIMD2<Float>(0,0)
                        
                        var j1: UInt16 = 0, j2: UInt16 = 0, j3: UInt16 = 0, j4: UInt16 = 0
                        var w1: Float = 0, w2: Float = 0, w3: Float = 0, w4: Float = 0
                        
                        if let skin = skinMap[posIdx] {
                            j1 = UInt16(min(skin.bone_indices[0], 99))
                            j2 = UInt16(min(skin.bone_indices[1], 99))
                            j3 = UInt16(min(skin.bone_indices[2], 99))
                            j4 = UInt16(min(skin.bone_indices[3], 99))
                            w1 = skin.weights[0]; w2 = skin.weights[1]; w3 = skin.weights[2]; w4 = skin.weights[3]
                            if dominantBone == -1 && w1 > 0.5 { dominantBone = Int(j1) }
                        }
                        
                        finalVertices.append(PuppetVertex(px: position.x, py: position.y, pz: position.z, u: texCoord.x, v: texCoord.y, j1: j1, j2: j2, j3: j3, j4: j4, w1: w1, w2: w2, w3: w3, w4: w4))
                        uniqueVertexMap[key] = newIndex
                        faceIndices.append(newIndex)
                    }
                }
                
                // 三角形生成 (Triangulation)
                if faceIndices.count >= 3 {
                    finalIndices.append(faceIndices[0]); finalIndices.append(faceIndices[1]); finalIndices.append(faceIndices[2])
                    triangleBoneIndices.append(dominantBone)
                }
                if faceIndices.count >= 4 {
                    finalIndices.append(faceIndices[0]); finalIndices.append(faceIndices[2]); finalIndices.append(faceIndices[3])
                    triangleBoneIndices.append(dominantBone)
                }
            }
        }
        return (finalVertices, finalIndices, triangleBoneIndices, maxPos.x - minPos.x)
    }

    func parseTransforms(_ obj: SceneObject) -> (SIMD3<Float>, SIMD3<Float>, SIMD2<Float>, SIMD3<Float>) {
        let originStrs = (obj.origin?.value ?? "0 0 0").components(separatedBy: " ").compactMap { Float($0) }
        let sizeStrs = (obj.size?.value ?? "100 100").components(separatedBy: " ").compactMap { Float($0) }
        let scaleStrs = (obj.scale?.value ?? "1 1 1").components(separatedBy: " ").compactMap { Float($0) }
        let angleStrs = (obj.angles?.value ?? "0 0 0").components(separatedBy: " ").compactMap { Float($0) }
        
        var pos = SIMD3<Float>(0,0,0)
        if originStrs.count >= 2 { pos.x = originStrs[0]; pos.y = originStrs[1] }
        if originStrs.count >= 3 { pos.z = originStrs[2] }
        
        var size = SIMD2<Float>(100, 100)
        if sizeStrs.count >= 2 { size.x = sizeStrs[0]; size.y = sizeStrs[1] }
        
        var scale = SIMD3<Float>(1,1,1)
        if scaleStrs.count >= 2 { scale.x = scaleStrs[0]; scale.y = scaleStrs[1] }
        
        var rotation = SIMD3<Float>(0,0,0)
        if angleStrs.count >= 3 {
            rotation.x = angleStrs[0] * .pi / 180.0
            rotation.y = angleStrs[1] * .pi / 180.0
            rotation.z = angleStrs[2] * .pi / 180.0
        }
        return (pos, rotation, size, scale)
    }
    
    func parseEffects(_ obj: SceneObject, base: URL) -> ([EffectParams], [MTLTexture?]) {
        var effectParams: [EffectParams] = []
        var maskTextures: [MTLTexture?] = []
        
        guard let effects = obj.effects else { return ([], []) }
        
        for effect in effects {
            var type: Int32 = 0
            if effect.file.contains("waterwaves") { type = 2 }
            else if effect.file.contains("shake") { type = 3 }
            else if effect.file.contains("scroll") { type = 1 }
            // 可以在此添加更多特效类型的判断，例如:
            // else if effect.file.contains("blur") { type = 4 }
            
            if type == 0 { continue }
            
            if let pass = effect.passes?.first, let constants = pass.constantshadervalues {
                var param = EffectParams(type: type, maskIndex: -1, speed: 1, scale: 1, strength: 0.1, exponent: 1, direction: .zero, bounds: .zero, friction: .zero)
                
                // 加载遮罩纹理
                if let masks = pass.textures, masks.count > 1, let maskPath = masks[1] {
                    let maskURL = resolveTextureURL(base: base, rawPath: maskPath)
                    if let maskTex = try? textureLoader.newTexture(URL: maskURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) {
                        maskTextures.append(maskTex)
                        param.maskIndex = Int32(maskTextures.count - 1)
                    }
                }
                
                // 辅助函数：从 ShaderValue 获取 Float
                func getVal(_ key: String) -> Float {
                    if let v = constants[key] {
                        switch v { case .float(let f): return f; case .string(let s): return (Float(s) ?? 0) }
                    }
                    return 0
                }
                // 辅助函数：从 ShaderValue 获取 Vec2
                func getVec2(_ key: String) -> SIMD2<Float> {
                    if let v = constants[key], case .string(let s) = v {
                        let p = s.components(separatedBy: " ").compactMap{Float($0)}
                        if p.count >= 2 { return SIMD2<Float>(p[0], p[1]) }
                    }
                    return .zero
                }
                
                // 参数映射
                if type == 2 { // WaterWaves
                    param.speed = getVal("speed")
                    param.scale = getVal("scale")
                    param.strength = getVal("strength")
                    param.exponent = getVal("exponent")
                    let dirVal = getVal("direction")
                    param.direction = SIMD2<Float>(sin(dirVal), cos(dirVal))
                } else if type == 1 { // Scroll
                    param.direction = getVec2("speed")
                } else if type == 3 { // Shake
                    param.speed = getVal("speed")
                    param.strength = getVal("strength")
                    param.bounds = getVec2("bounds")
                    param.friction = getVec2("friction")
                }
                
                effectParams.append(param)
            }
        }
        return (effectParams, maskTextures)
    }
    
    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // 更新视口，这里使用等比缩放
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let descriptor = view.currentRenderPassDescriptor else { return }
        
        // 每一帧清空颜色和深度模板
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        descriptor.depthAttachment.clearDepth = 1.0
        descriptor.stencilAttachment.clearStencil = 0
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        
        encoder.setCullMode(.none)
        
        // 构建正交投影矩阵
        let proj = Matrix4x4.orthographic(left: 0, right: Float(projectionSize.width), bottom: 0, top: Float(projectionSize.height), near: -5000, far: 5000)
        let time = Float(Date().timeIntervalSince(startTime))
        var globals = GlobalUniforms(projectionMatrix: proj, viewMatrix: matrix_identity_float4x4, time: time)
        
        encoder.setVertexBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
        encoder.setFragmentBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        // 遍历绘制列表
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

// MARK: - Renderable Objects (Standard)
class RenderableObject {
    var id: Int = -1
    var parentId: Int?
    weak var parent: RenderableObject?
    
    var localPosition: SIMD3<Float>
    var localRotation: SIMD3<Float>
    let size: SIMD2<Float>
    let scale: SIMD3<Float>
    
    let texture: MTLTexture
    let effects: [EffectParams]
    let masks: [MTLTexture?]
    let pipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState?
    
    let vertices: [Float] = [
        -0.5, -0.5, 0, 0, 0,
         0.5, -0.5, 0, 1, 0,
        -0.5,  0.5, 0, 0, 1,
         0.5,  0.5, 0, 1, 1
    ]
    
    init(position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>, texture: MTLTexture, effects: [EffectParams], masks: [MTLTexture?], pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState? = nil) {
        self.localPosition = position
        self.localRotation = rotation
        self.size = size
        self.scale = scale
        self.texture = texture
        self.effects = effects
        self.masks = masks
        self.pipeline = pipeline
        self.depthState = depthState
    }
    
    var worldMatrix: matrix_float4x4 {
        var local = Matrix4x4.translation(x: localPosition.x, y: localPosition.y, z: localPosition.z)
        local = local * Matrix4x4.rotation(angle: localRotation.z, axis: SIMD3<Float>(0, 0, 1))
        if let p = parent { return p.worldMatrix * local }
        return local
    }
    
    func draw(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(pipeline)
        if let ds = depthState { encoder.setDepthStencilState(ds) }
        
        let geometryScale = Matrix4x4.scale(x: size.x * scale.x, y: size.y * scale.y, z: 1)
        let finalModelMatrix = worldMatrix * geometryScale
        
        var objUniforms = ObjectUniforms(modelMatrix: finalModelMatrix, alpha: 1.0, color: SIMD4<Float>(1,1,1,1))
        
        encoder.setVertexBytes(vertices, length: vertices.count * 4, index: 0)
        encoder.setVertexBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        encoder.setFragmentBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        
        var currentEffects = effects
        var count = Int32(effects.count)
        if count > 0 {
            encoder.setFragmentBytes(&currentEffects, length: MemoryLayout<EffectParams>.size * effects.count, index: 3)
        } else {
             var dummy = EffectParams(type: 0, maskIndex: 0, speed: 0, scale: 0, strength: 0, exponent: 0, direction: .zero, bounds: .zero, friction: .zero)
             encoder.setFragmentBytes(&dummy, length: MemoryLayout<EffectParams>.size, index: 3)
        }
        encoder.setFragmentBytes(&count, length: MemoryLayout<Int32>.size, index: 4)
        
        encoder.setFragmentTexture(texture, index: 0)
        for (i, mask) in masks.enumerated() {
            if i < 8 { encoder.setFragmentTexture(mask, index: 1 + i) }
        }
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

// MARK: - Puppet Renderable (Animation Logic)
class PuppetRenderable: RenderableObject {
    let device: MTLDevice
    let vertexBuffer: MTLBuffer
    
    // 分层索引缓冲区
    var maskIndexBuffer: MTLBuffer?    // 遮罩层 (如眼白)
    var clippedIndexBuffer: MTLBuffer? // 被裁切层 (如瞳孔)
    var overlayIndexBuffer: MTLBuffer? // 覆盖层 (如睫毛)
    var standardIndexBuffer: MTLBuffer? // 普通绘制层 (当没有特殊标记时)
    
    var maskIndexCount: Int = 0
    var clippedIndexCount: Int = 0
    var overlayIndexCount: Int = 0
    var standardIndexCount: Int = 0

    let uniformBuffer: MTLBuffer
    var boneMatrices: [matrix_float4x4] // 骨骼矩阵数组
    
    let usePixelCoords: Bool
    let skeleton: [PuppetBone]
    let animations: [PuppetAnimation]
    var inverseBindMatrices: [matrix_float4x4] = []
    
    // 渲染状态
    let maskWriteState: MTLDepthStencilState?
    let maskTestState: MTLDepthStencilState?
    
    init(device: MTLDevice, vertices: [PuppetVertex], indices: [UInt32], triangleBones: [Int],
         skeleton: [PuppetBone], animations: [PuppetAnimation],
         position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>,
         texture: MTLTexture, effects: [EffectParams], masks: [MTLTexture?], pipeline: MTLRenderPipelineState,
         depthState: MTLDepthStencilState?, maskWriteState: MTLDepthStencilState?, maskTestState: MTLDepthStencilState?, usePixelCoords: Bool) {
        
        self.device = device
        self.vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<PuppetVertex>.stride, options: .storageModeShared)!
        
        self.usePixelCoords = usePixelCoords
        self.skeleton = skeleton
        self.animations = animations
        self.maskWriteState = maskWriteState
        self.maskTestState = maskTestState
        
        // 初始化骨骼数组 (100个单位矩阵)
        self.boneMatrices = Array(repeating: matrix_identity_float4x4, count: 100)
        self.uniformBuffer = device.makeBuffer(length: MemoryLayout<matrix_float4x4>.stride * 100, options: .storageModeShared)!
        
        super.init(position: position, rotation: rotation, size: size, scale: scale, texture: texture, effects: effects, masks: masks, pipeline: pipeline, depthState: depthState)
        
        computeInverseBindMatrices()
        
        // --- 核心逻辑: 通用数据驱动的渲染层分类 ---
        
        // 1. 自动检测遮罩层 (Blinking Animation)
        var maskBoneIDs = Set<Int>()
        for anim in animations {
            for track in anim.tracks {
                // 如果某个骨骼在动画中 Y轴缩放压扁到 < 0.2，视为“眨眼”动作的眼白/眼皮
                let minScaleY = track.frames.map { $0.s[1] }.min() ?? 1.0
                if minScaleY < 0.2 { maskBoneIDs.insert(track.track_id) }
            }
        }
        
        // 2. 读取 JSON 中的 render_tag
        var jsonClippedIDs = Set<Int>()
        var jsonMaskIDs = Set<Int>()
        
        for bone in skeleton {
            if let tag = bone.render_tag {
                if tag == "clipped" { jsonClippedIDs.insert(bone.id) }
                else if tag == "mask" { jsonMaskIDs.insert(bone.id) }
            }
        }
        
        // 合并遮罩 ID
        maskBoneIDs.formUnion(jsonMaskIDs)
        
        // 3. 构建索引列表
        var maskIndices: [UInt32] = []
        var clippedIndices: [UInt32] = []
        var overlayIndices: [UInt32] = []
        var standardIndices: [UInt32] = []
        
        let hasClippingLogic = !maskBoneIDs.isEmpty || !jsonClippedIDs.isEmpty
        
        for i in stride(from: 0, to: indices.count, by: 3) {
            // 获取该三角形所属的主导骨骼ID
            let boneIdx = (i/3 < triangleBones.count) ? triangleBones[i/3] : -1
            
            if maskBoneIDs.contains(boneIdx) {
                // 属于遮罩层 (眼白)
                maskIndices.append(indices[i]); maskIndices.append(indices[i+1]); maskIndices.append(indices[i+2])
            } else if jsonClippedIDs.contains(boneIdx) {
                // 属于裁剪层 (瞳孔) - 仅在 JSON 中明确指定时生效
                clippedIndices.append(indices[i]); clippedIndices.append(indices[i+1]); clippedIndices.append(indices[i+2])
            } else if hasClippingLogic {
                // 如果存在遮罩逻辑，其他所有东西都放入覆盖层 (Overlay)，防止被错误裁剪
                overlayIndices.append(indices[i]); overlayIndices.append(indices[i+1]); overlayIndices.append(indices[i+2])
            } else {
                // 没有任何特殊逻辑，走普通绘制
                standardIndices.append(indices[i]); standardIndices.append(indices[i+1]); standardIndices.append(indices[i+2])
            }
        }
        
        // 4. 创建 GPU 缓冲区
        if !maskIndices.isEmpty { maskIndexBuffer = device.makeBuffer(bytes: maskIndices, length: maskIndices.count * 4, options: .storageModeShared); maskIndexCount = maskIndices.count }
        if !clippedIndices.isEmpty { clippedIndexBuffer = device.makeBuffer(bytes: clippedIndices, length: clippedIndices.count * 4, options: .storageModeShared); clippedIndexCount = clippedIndices.count }
        if !overlayIndices.isEmpty { overlayIndexBuffer = device.makeBuffer(bytes: overlayIndices, length: overlayIndices.count * 4, options: .storageModeShared); overlayIndexCount = overlayIndices.count }
        if !standardIndices.isEmpty { standardIndexBuffer = device.makeBuffer(bytes: standardIndices, length: standardIndices.count * 4, options: .storageModeShared); standardIndexCount = standardIndices.count }
        
        // 上传初始骨骼数据
        let ptr = uniformBuffer.contents()
        ptr.copyMemory(from: &boneMatrices, byteCount: MemoryLayout<matrix_float4x4>.stride * 100)
    }
    
    // 计算全局绑定矩阵
    func getGlobalBindMatrix(boneIndex: Int, localMatrices: [matrix_float4x4]) -> matrix_float4x4 {
        if boneIndex < 0 || boneIndex >= skeleton.count { return matrix_identity_float4x4 }
        let bone = skeleton[boneIndex]
        let local = localMatrices[boneIndex]
        if bone.parent >= 0 && bone.parent < skeleton.count {
            if bone.parent == boneIndex { return local }
            let parentGlobal = getGlobalBindMatrix(boneIndex: bone.parent, localMatrices: localMatrices)
            return parentGlobal * local
        }
        return local
    }
    
    // 计算逆绑定矩阵
    func computeInverseBindMatrices() {
        inverseBindMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        var localMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        for i in 0..<skeleton.count {
            let m = skeleton[i].matrix
            localMatrices[i] = matrix_float4x4(columns: ( SIMD4<Float>(m[0], m[1], m[2], m[3]), SIMD4<Float>(m[4], m[5], m[6], m[7]), SIMD4<Float>(m[8], m[9], m[10], m[11]), SIMD4<Float>(m[12], m[13], m[14], m[15]) ))
        }
        for i in 0..<skeleton.count {
            let global = getGlobalBindMatrix(boneIndex: i, localMatrices: localMatrices)
            if abs(global.determinant) < 0.000001 { inverseBindMatrices[i] = matrix_identity_float4x4 } else { inverseBindMatrices[i] = global.inverse }
        }
    }
    
    // 递归计算动画矩阵
    func getGlobalAnimMatrix(boneIndex: Int, localMatrices: [matrix_float4x4], computed: inout [Bool], result: inout [matrix_float4x4]) -> matrix_float4x4 {
        if boneIndex < 0 || boneIndex >= skeleton.count { return matrix_identity_float4x4 }
        if computed[boneIndex] { return result[boneIndex] }
        let bone = skeleton[boneIndex]
        let local = localMatrices[boneIndex]
        var global = local
        if bone.parent >= 0 && bone.parent < skeleton.count && bone.parent != boneIndex {
            let parentGlobal = getGlobalAnimMatrix(boneIndex: bone.parent, localMatrices: localMatrices, computed: &computed, result: &result)
            global = parentGlobal * local
        }
        result[boneIndex] = global
        computed[boneIndex] = true
        return global
    }
    
    // 更新动画帧
    func updateAnimation(time: Float) {
        if animations.isEmpty { return }
        let anim = animations[0]
        let fps = anim.fps > 0 ? anim.fps : 30.0
        let duration = Float(anim.length) / fps
        let t = (duration > 0) ? fmod(time, duration) : 0
        let frameIndex = t * fps
        var localMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        
        for i in 0..<skeleton.count {
            let bone = skeleton[i]
            if let track = anim.tracks.first(where: { $0.track_id == bone.id }), !track.frames.isEmpty {
                let totalFrames = track.frames.count
                let idx0 = Int(frameIndex) % totalFrames
                let idx1 = (idx0 + 1) % totalFrames
                let fraction = frameIndex - Float(Int(frameIndex))
                let k1 = track.frames[idx0]
                let k2 = track.frames[idx1]
                let p = mix(SIMD3<Float>(k1.p[0], k1.p[1], k1.p[2]), SIMD3<Float>(k2.p[0], k2.p[1], k2.p[2]), t: fraction)
                let r = mix(SIMD3<Float>(k1.r[0], k1.r[1], k1.r[2]), SIMD3<Float>(k2.r[0], k2.r[1], k2.r[2]), t: fraction)
                let s = mix(SIMD3<Float>(k1.s[0], k1.s[1], k1.s[2]), SIMD3<Float>(k2.s[0], k2.s[1], k2.s[2]), t: fraction)
                let matT = Matrix4x4.translation(x: p.x, y: p.y, z: p.z)
                let matR = Matrix4x4.fromEuler(r)
                let matS = Matrix4x4.scale(x: s.x, y: s.y, z: s.z)
                localMatrices[i] = matT * matR * matS
            } else {
                let m = bone.matrix
                localMatrices[i] = matrix_float4x4(columns: ( SIMD4<Float>(m[0], m[1], m[2], m[3]), SIMD4<Float>(m[4], m[5], m[6], m[7]), SIMD4<Float>(m[8], m[9], m[10], m[11]), SIMD4<Float>(m[12], m[13], m[14], m[15]) ))
            }
        }
        
        var globalComputed = Array(repeating: false, count: skeleton.count)
        var globalMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        for i in 0..<skeleton.count {
            let global = getGlobalAnimMatrix(boneIndex: i, localMatrices: localMatrices, computed: &globalComputed, result: &globalMatrices)
            let skinMatrix = global * inverseBindMatrices[i]
            if i < 100 { boneMatrices[i] = skinMatrix }
        }
        let ptr = uniformBuffer.contents()
        ptr.copyMemory(from: &boneMatrices, byteCount: MemoryLayout<matrix_float4x4>.stride * 100)
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(pipeline)
        let geometryScale: matrix_float4x4
        if usePixelCoords { geometryScale = Matrix4x4.scale(x: scale.x, y: scale.y, z: scale.z) } else { geometryScale = Matrix4x4.scale(x: size.x * scale.x, y: size.y * scale.y, z: scale.z) }
        let finalModelMatrix = worldMatrix * geometryScale
        var objUniforms = ObjectUniforms(modelMatrix: finalModelMatrix, alpha: 1.0, color: SIMD4<Float>(1,1,1,1))
        
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 3)
        encoder.setFragmentBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        
        var count: Int32 = 0
        encoder.setFragmentBytes(&count, length: MemoryLayout<Int32>.size, index: 4)
        encoder.setFragmentTexture(texture, index: 0)
        
        if standardIndexCount > 0, let buf = standardIndexBuffer {
             if let ds = depthState { encoder.setDepthStencilState(ds) }
             encoder.drawIndexedPrimitives(type: .triangle, indexCount: standardIndexCount, indexType: .uint32, indexBuffer: buf, indexBufferOffset: 0)
        } else {
             // Pass 1: Mask (Write Stencil 1)
             if maskIndexCount > 0, let buf = maskIndexBuffer, let ws = maskWriteState {
                 encoder.setDepthStencilState(ws)
                 encoder.setStencilReferenceValue(1)
                 encoder.drawIndexedPrimitives(type: .triangle, indexCount: maskIndexCount, indexType: .uint32, indexBuffer: buf, indexBufferOffset: 0)
             }
             // Pass 2: Clipped Pupils (Read Stencil 1)
             if clippedIndexCount > 0, let buf = clippedIndexBuffer, let ts = maskTestState {
                 encoder.setDepthStencilState(ts)
                 encoder.setStencilReferenceValue(1)
                 encoder.drawIndexedPrimitives(type: .triangle, indexCount: clippedIndexCount, indexType: .uint32, indexBuffer: buf, indexBufferOffset: 0)
             }
             // Pass 3: Overlay (Everything else - Eyelashes/Face) -> No Stencil
             if overlayIndexCount > 0, let buf = overlayIndexBuffer, let ds = depthState {
                 encoder.setDepthStencilState(ds)
                 encoder.drawIndexedPrimitives(type: .triangle, indexCount: overlayIndexCount, indexType: .uint32, indexBuffer: buf, indexBufferOffset: 0)
             }
        }
    }
}

// MARK: - Matrix Helpers
struct Matrix4x4 {
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
        let ral = right + left; let rsl = right - left; let tab = top + bottom; let tsb = top - bottom; let fan = far + near; let fsn = far - near
        return matrix_float4x4(columns: ( SIMD4<Float>(2.0 / rsl, 0, 0, 0), SIMD4<Float>(0, 2.0 / tsb, 0, 0), SIMD4<Float>(0, 0, -2.0 / fsn, 0), SIMD4<Float>(-ral / rsl, -tab / tsb, -fan / fsn, 1) ))
    }
    static func translation(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4; matrix.columns.3 = SIMD4<Float>(x, y, z, 1); return matrix
    }
    static func scale(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        return matrix_float4x4(columns: ( SIMD4<Float>(x, 0, 0, 0), SIMD4<Float>(0, y, 0, 0), SIMD4<Float>(0, 0, z, 0), SIMD4<Float>(0, 0, 0, 1) ))
    }
    static func rotation(angle: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
        let unitAxis = normalize(axis); let ct = cos(angle); let st = sin(angle); let ci = 1 - ct
        let x = unitAxis.x; let y = unitAxis.y; let z = unitAxis.z
        return matrix_float4x4(columns: ( SIMD4<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0), SIMD4<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0), SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0), SIMD4<Float>(0, 0, 0, 1) ))
    }
    static func fromEuler(_ e: SIMD3<Float>) -> matrix_float4x4 {
        let mx = rotation(angle: e.x, axis: SIMD3<Float>(1, 0, 0)); let my = rotation(angle: e.y, axis: SIMD3<Float>(0, 1, 0)); let mz = rotation(angle: e.z, axis: SIMD3<Float>(0, 0, 1))
        return mz * my * mx
    }
}
