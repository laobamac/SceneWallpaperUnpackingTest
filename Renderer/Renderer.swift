import MetalKit
import simd

// MARK: - Aligned Structs
struct EffectParams {
    var type: Int32
    var maskIndex: Int32
    var speed: Float
    var scale: Float
    var strength: Float
    var exponent: Float
    var direction: SIMD2<Float>
    var bounds: SIMD2<Float>
    var friction: SIMD2<Float>
}

struct ObjectUniforms {
    var modelMatrix: matrix_float4x4
    var alpha: Float
    var color: SIMD4<Float>
    var padding: SIMD4<Float> = .zero
}

struct GlobalUniforms {
    var projectionMatrix: matrix_float4x4
    var viewMatrix: matrix_float4x4
    var time: Float
    var padding: SIMD3<Float> = .zero
}

// 用于检测是模型还是图片的辅助结构
struct AnyModelJSON: Decodable {
    var model: String?
    var puppet: String? // Wallpaper Engine 常用字段
    var material: String?
}

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!
    var mdlPipelineState: MTLRenderPipelineState! // 新增：MDL专用管线
    var samplerState: MTLSamplerState!
    var textureLoader: MTKTextureLoader
    
    var baseFolder: URL?
    // 存储所有渲染对象 (Sprite 和 MDL)，按顺序绘制以保持层级
    var renderables: [RenderableObject] = []
    
    var startTime: Date = Date()
    var projectionSize: CGSize = CGSize(width: 1920, height: 1080)
    var viewportSize: CGSize = .zero
    var lastTime: TimeInterval = 0
    
    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)
        super.init()
        setupPipeline()
    }
    
    func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else { return }
        
        // 1. 标准 Sprite 管线
        let vertexFunc = library.makeFunction(name: "vertex_main")
        let fragmentFunc = library.makeFunction(name: "fragment_main")
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Sprite Pipeline"
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // 混合模式
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 5
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        descriptor.vertexDescriptor = vertexDescriptor
        
        try? pipelineState = device.makeRenderPipelineState(descriptor: descriptor)
        
        // 2. MDL 模型管线 (带骨骼蒙皮)
        let mdlVertFunc = library.makeFunction(name: "mdl_vertex")
        let mdlFragFunc = library.makeFunction(name: "mdl_fragment")
        
        let mdlDescriptor = MTLRenderPipelineDescriptor()
        mdlDescriptor.label = "MDL Pipeline"
        mdlDescriptor.vertexFunction = mdlVertFunc
        mdlDescriptor.fragmentFunction = mdlFragFunc
        mdlDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        mdlDescriptor.colorAttachments[0].isBlendingEnabled = true
        mdlDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        mdlDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        mdlDescriptor.depthAttachmentPixelFormat = .invalid // 2D场景通常不需要深度缓冲，靠绘制顺序
        
        // 使用 MDLModelNode 中定义的 VertexDescriptor
        mdlDescriptor.vertexDescriptor = MDLModelNode.vertexDescriptor
        
        try? mdlPipelineState = device.makeRenderPipelineState(descriptor: mdlDescriptor)
        
        // 采样器
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        samplerDesc.normalizedCoordinates = true
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }
    
    func loadScene(folder: URL) {
        let secured = folder.startAccessingSecurityScopedResource()
        defer { if secured { folder.stopAccessingSecurityScopedResource() } }
        
        self.baseFolder = folder
        renderables.removeAll()
        startTime = Date()
        lastTime = 0
        
        let projectURL = folder.appendingPathComponent("project.json")
        guard let projData = try? Data(contentsOf: projectURL),
              let projJson = try? JSONSerialization.jsonObject(with: projData, options: []) as? [String: Any],
              let sceneFile = projJson["file"] as? String else { return }
        
        let sceneURL = folder.appendingPathComponent(sceneFile)
        
        do {
            let sceneData = try Data(contentsOf: sceneURL)
            let sceneRoot = try JSONDecoder().decode(SceneRoot.self, from: sceneData)
            
            if let proj = sceneRoot.general?.orthogonalprojection {
                self.projectionSize = CGSize(width: Double(proj.width), height: Double(proj.height))
            }
            
            // 1. 创建所有对象
            var tempRenderables: [Int: RenderableObject] = [:]
            var orderedList: [RenderableObject] = []
            
            for obj in sceneRoot.objects {
                if !obj.isVisible { continue }
                
                // 检查是图片还是模型
                var createdObj: RenderableObject? = nil
                
                if let imagePath = obj.image {
                    let jsonURL = folder.appendingPathComponent(imagePath)
                    if let jsonData = try? Data(contentsOf: jsonURL),
                       let check = try? JSONDecoder().decode(AnyModelJSON.self, from: jsonData) {
                        
                        if let modelFile = check.model ?? check.puppet {
                                                    print("Loading MDL Model: \(modelFile)")
                                                    createdObj = createMDLNode(from: obj, modelPath: modelFile, jsonDef: check)
                                                } else {
                                                    createdObj = createRenderable(from: obj)
                                                }
                    }
                }
                
                if let renderable = createdObj {
                    if let id = obj.id {
                        tempRenderables[id] = renderable
                        renderable.id = id
                    }
                    renderable.parentId = obj.parent
                    orderedList.append(renderable)
                }
            }
            
            // 2. 建立父子关系
            for renderable in orderedList {
                if let pid = renderable.parentId, let parentObj = tempRenderables[pid] {
                    renderable.parent = parentObj
                }
            }
            
            self.renderables = orderedList
            
        } catch {
            print("Scene load error: \(error)")
        }
    }
    
    // 创建 MDL 模型节点
    func createMDLNode(from obj: SceneObject, modelPath: String, jsonDef: AnyModelJSON) -> RenderableObject? {
        guard let base = baseFolder, let mdlPipeline = mdlPipelineState else { return nil }
        
        let fullModelPath = base.appendingPathComponent(modelPath).path
        
        // 获取纹理
        var texture: MTLTexture?
        if let matPath = jsonDef.material {
            let matURL = base.appendingPathComponent(matPath)
            if let matData = try? Data(contentsOf: matURL),
               let matDef = try? JSONDecoder().decode(MaterialJSON.self, from: matData),
               let firstPass = matDef.passes.first,
               let texName = firstPass.textures.first {
                
                let texURL = base.appendingPathComponent("materials/\(texName).png")
                var finalTexURL = texURL
                if !FileManager.default.fileExists(atPath: texURL.path) {
                    // 尝试在 materials 根目录查找
                    finalTexURL = base.appendingPathComponent("materials").appendingPathComponent(URL(fileURLWithPath: texName).lastPathComponent + ".png")
                }
                texture = try? textureLoader.newTexture(URL: finalTexURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false])
            }
        }
        
        guard let tex = texture else { return nil }
        
        // 解析 Transform
        let (pos, rotation, size, scale) = parseTransform(obj: obj)
        
        // 创建 MDL Node
        let node = MDLModelNode(device: device,
                                mdlPath: fullModelPath,
                                texture: tex,
                                position: pos,
                                rotation: rotation,
                                size: size,
                                scale: scale,
                                pipeline: mdlPipeline)
        return node
    }
    
    // 创建普通 Sprite
    func createRenderable(from obj: SceneObject) -> RenderableObject? {
        guard let imagePath = obj.image, let base = baseFolder else { return nil }
        
        let modelURL = base.appendingPathComponent(imagePath)
        guard let modelData = try? Data(contentsOf: modelURL),
              let modelDef = try? JSONDecoder().decode(ModelJSON.self, from: modelData),
              let matPath = modelDef.material else { return nil }
        
        let matURL = base.appendingPathComponent(matPath)
        guard let matData = try? Data(contentsOf: matURL),
              let matDef = try? JSONDecoder().decode(MaterialJSON.self, from: matData),
              let firstPass = matDef.passes.first,
              let texName = firstPass.textures.first else { return nil }
        
        let texURL = base.appendingPathComponent("materials/\(texName).png")
        var finalTexURL = texURL
        if !FileManager.default.fileExists(atPath: texURL.path) {
            finalTexURL = base.appendingPathComponent("materials").appendingPathComponent(URL(fileURLWithPath: texName).lastPathComponent + ".png")
        }
        
        guard let texture = try? textureLoader.newTexture(URL: finalTexURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) else { return nil }
        
        let (pos, rotation, size, scale) = parseTransform(obj: obj)
        
        // 解析特效
        var effectParams: [EffectParams] = []
        var maskTextures: [MTLTexture?] = []
        
        if let effects = obj.effects {
            for effect in effects {
                var type: Int32 = 0
                if effect.file.contains("waterwaves") { type = 2 }
                else if effect.file.contains("shake") { type = 3 }
                else if effect.file.contains("scroll") { type = 1 }
                
                if type == 0 { continue }
                
                if let pass = effect.passes?.first, let constants = pass.constantshadervalues {
                    var param = EffectParams(type: type, maskIndex: -1, speed: 1, scale: 1, strength: 0.1, exponent: 1, direction: .zero, bounds: .zero, friction: .zero)
                    
                    if let masks = pass.textures, masks.count > 1, let maskPath = masks[1] {
                        let maskURL = base.appendingPathComponent("materials/\(maskPath).png")
                        let altMaskURL = base.appendingPathComponent("materials").appendingPathComponent(URL(fileURLWithPath: maskPath).lastPathComponent + ".png")
                        if let maskTex = try? textureLoader.newTexture(URL: maskURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) {
                            maskTextures.append(maskTex)
                            param.maskIndex = Int32(maskTextures.count - 1)
                        } else if let maskTex = try? textureLoader.newTexture(URL: altMaskURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) {
                            maskTextures.append(maskTex)
                            param.maskIndex = Int32(maskTextures.count - 1)
                        }
                    }
                    
                    func getVal(_ key: String) -> Float {
                        if let v = constants[key] {
                            switch v { case .float(let f): return f; case .string(let s): return (Float(s) ?? 0) }
                        }
                        return 0
                    }
                    func getVec2(_ key: String) -> SIMD2<Float> {
                        if let v = constants[key], case .string(let s) = v {
                            let p = s.components(separatedBy: " ").compactMap{Float($0)}
                            if p.count >= 2 { return SIMD2<Float>(p[0], p[1]) }
                        }
                        return .zero
                    }
                    
                    if type == 2 {
                        param.speed = getVal("speed"); param.scale = getVal("scale"); param.strength = getVal("strength"); param.exponent = getVal("exponent")
                        let dirVal = getVal("direction"); param.direction = SIMD2<Float>(sin(dirVal), cos(dirVal))
                    } else if type == 1 { param.direction = getVec2("speed") }
                    else if type == 3 {
                        param.speed = getVal("speed"); param.strength = getVal("strength")
                        param.bounds = getVec2("bounds"); param.friction = getVec2("friction")
                    }
                    effectParams.append(param)
                }
            }
        }
        
        return RenderableObject(position: pos, rotation: rotation, size: size, scale: scale, texture: texture, effects: effectParams, masks: maskTextures)
    }
    
    func parseTransform(obj: SceneObject) -> (SIMD3<Float>, SIMD3<Float>, SIMD2<Float>, SIMD3<Float>) {
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
    
    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let samplerState = samplerState else { return }
        
        let currentTime = Date().timeIntervalSince(startTime)
        let deltaTime = currentTime - lastTime
        lastTime = currentTime
        let timeFloat = Float(currentTime)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        
        // 投影矩阵: 0..W, 0..H (Bottom Left is 0,0)
        let proj = Matrix4x4.orthographic(left: 0, right: Float(projectionSize.width),
                                          bottom: 0, top: Float(projectionSize.height),
                                          near: -1000, far: 1000)
        var globals = GlobalUniforms(projectionMatrix: proj, viewMatrix: matrix_identity_float4x4, time: timeFloat)
        
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        // 遍历渲染对象
        for obj in renderables {
            // 更新动画状态 (骨骼等)
            obj.update(deltaTime: deltaTime)
            
            // 切换管线 (Sprite 或 MDL)
            if let mdlNode = obj as? MDLModelNode {
                encoder.setRenderPipelineState(mdlNode.pipelineState)
                // MDL 使用特殊的 Buffer 索引和逻辑
            } else {
                encoder.setRenderPipelineState(pipelineState)
                encoder.setVertexBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
                encoder.setFragmentBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
            }
            
            // 传递 Globals (注意: MDLNode 内部 draw 自己处理了矩阵，但如果需要 Globals 也可以传)
            // 这里为了简单，GlobalUniforms 的 index 1 在 Shader 中是统一的
            encoder.setVertexBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
            
            obj.draw(encoder: encoder)
        }
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - Renderable Object Base Class
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
    
    // V轴翻转以匹配 Metal 纹理坐标
    let vertices: [Float] = [
        -0.5, -0.5, 0, 0, 0,
         0.5, -0.5, 0, 1, 0,
        -0.5,  0.5, 0, 0, 1,
         0.5,  0.5, 0, 1, 1
    ]
    
    init(position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>, texture: MTLTexture, effects: [EffectParams], masks: [MTLTexture?]) {
        self.localPosition = position
        self.localRotation = rotation
        self.size = size
        self.scale = scale
        self.texture = texture
        self.effects = effects
        self.masks = masks
    }
    
    var worldMatrix: matrix_float4x4 {
        var local = Matrix4x4.translation(x: localPosition.x, y: localPosition.y, z: localPosition.z)
        local = local * Matrix4x4.rotation(angle: localRotation.z, axis: SIMD3<Float>(0, 0, 1))
        local = local * Matrix4x4.rotation(angle: localRotation.x, axis: SIMD3<Float>(1, 0, 0)) // 3D旋转支持
        local = local * Matrix4x4.rotation(angle: localRotation.y, axis: SIMD3<Float>(0, 1, 0))
        
        if let p = parent {
            return p.worldMatrix * local
        }
        return local
    }
    
    func update(deltaTime: Double) {
        // 默认无操作，子类重写
    }
    
    func draw(encoder: MTLRenderCommandEncoder) {
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

// MARK: - MDL Model Node
class MDLModelNode: RenderableObject {
    var mesh: MDLMesh
    var puppet: Puppet
    var vertexBuffer: MTLBuffer?
    var indexBuffer: MTLBuffer?
    var pipelineState: MTLRenderPipelineState
    var time: Double = 0
    
    static var vertexDescriptor: MTLVertexDescriptor = {
        let descriptor = MTLVertexDescriptor()
        // Pos(12) + Indices(16) + Weights(16) + UV(8) = 52 bytes stride
        descriptor.attributes[0].format = .float3; descriptor.attributes[0].offset = 0; descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .uint4;  descriptor.attributes[1].offset = 12; descriptor.attributes[1].bufferIndex = 0
        descriptor.attributes[2].format = .float4; descriptor.attributes[2].offset = 28; descriptor.attributes[2].bufferIndex = 0
        descriptor.attributes[3].format = .float2; descriptor.attributes[3].offset = 44; descriptor.attributes[3].bufferIndex = 0
        descriptor.layouts[0].stride = 52
        descriptor.layouts[0].stepRate = 1
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }()
    
    init?(device: MTLDevice, mdlPath: String, texture: MTLTexture, position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>, pipeline: MTLRenderPipelineState) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: mdlPath)),
              let result = MDLParser.parse(data: data) else { return nil }
        
        self.mesh = result.0
        self.puppet = result.1
        self.pipelineState = pipeline
        
        super.init(position: position, rotation: rotation, size: size, scale: scale, texture: texture, effects: [], masks: [])
        
        // 创建 Buffers
        var rawVertices = [UInt8]()
        for v in mesh.vertices {
            var v = v
            withUnsafeBytes(of: &v.position) { rawVertices.append(contentsOf: $0) }
            withUnsafeBytes(of: &v.blendIndices) { rawVertices.append(contentsOf: $0) }
            withUnsafeBytes(of: &v.blendWeights) { rawVertices.append(contentsOf: $0) }
            withUnsafeBytes(of: &v.texCoord) { rawVertices.append(contentsOf: $0) }
        }
        
        self.vertexBuffer = device.makeBuffer(bytes: rawVertices, length: rawVertices.count, options: [])
        self.indexBuffer = device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * 2, options: [])
    }
    
    override func update(deltaTime: Double) {
        time += deltaTime
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        guard let vertexBuffer = vertexBuffer, let indexBuffer = indexBuffer else { return }
        
        // 计算骨骼矩阵
        let animID = puppet.animations.first?.id ?? 0
        let bones = puppet.update(animationId: animID, time: time)
        
        // 计算 MVP
        // 注意：MDL不需要 GeometryScale (size/scale), 因为顶点已经在模型空间中定义好了。
        // 但是 SceneObject 的 scale 属性可能仍然需要应用到整个模型上。
        let modelScale = Matrix4x4.scale(x: scale.x, y: scale.y, z: scale.z)
        let finalModelMatrix = worldMatrix * modelScale
        
        // 传递数据给 Shader (UniformsMDL 结构)
        // buffer index 1: UniformsMDL { MVP, Bones[] }
        // 注意：GlobalUniforms 在 Renderer 中已经绑定到 index 1 了。
        // 这里我们需要覆盖 index 1，因为 MDL Shader 的 buffer(1) 定义包含了 MVP 和 Bones，结构不同。
        // 或者，我们在 MDL Shader 中定义 buffer(1) 为 Globals, buffer(2) 为 Model/Bones。
        // 假设我们在 Shader 中定义的是:
        // struct UniformsMDL { float4x4 mvp; float4x4 bones[128]; }; [[buffer(1)]]
        // 那么这里我们需要构建这个大结构体。
        
        // 为了方便，直接构建一个 buffer
        var bufferData = [UInt8]()
        // 1. MVP (View/Proj 来自 Global，这里我们需要合成最终的 MVP)
        // 由于 Renderer 在外部绑定了 GlobalUniforms，我们需要获取 Proj * View。
        // 这里的架构稍微有点冲突。最简单的做法是 MDL Shader 接受 MVP 矩阵。
        // 我们需要传入 globals.projection * globals.view * finalModel
        // 由于我们在 draw 内部拿不到 globals (除非传进来)，
        // 可以在 Renderer.draw 中将 globals 的 projectionMatrix 存下来传给 RenderableObject，或者...
        // 实际上 Renderer 已经在外部 setVertexBytes(globals) 到 index 1。
        // 我们的 MDL Shader 如果使用独立的 buffer layout，就直接覆盖。
        
        // 假设 MDL Shader 定义： constant UniformsMDL &uniforms [[buffer(2)]] (和 ObjectUniforms 位置一样)
        // 并且 vertex_main 接受 globals [[buffer(1)]]。
        // 如果这样，MDL Shader 只需要 ModelMatrix 和 Bones。
        // 让 MDL Shader 也引用 GlobalUniforms。
        
        // 让我们采用兼容性方案：
        // MDL Shader:
        // vertexOut mdl_vertex(..., constant GlobalUniforms &g [[buffer(1)]], constant MDLObject &obj [[buffer(2)]])
        // struct MDLObject { float4x4 model; float4x4 bones[128]; };
        
        var boneData = [simd_float4x4]()
        boneData.append(finalModelMatrix)
        boneData.append(contentsOf: bones)
        if boneData.count < 129 {
             boneData.append(contentsOf: [simd_float4x4](repeating: .identity, count: 129 - boneData.count))
        }
        
        encoder.setVertexBytes(boneData, length: boneData.count * MemoryLayout<simd_float4x4>.size, index: 2)
        
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: mesh.indices.count,
                                      indexType: .uint16,
                                      indexBuffer: indexBuffer,
                                      indexBufferOffset: 0)
    }
}

// MARK: - Matrix Helpers
struct Matrix4x4 {
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
        let ral = right + left
        let rsl = right - left
        let tab = top + bottom
        let tsb = top - bottom
        let fan = far + near
        let fsn = far - near
        return matrix_float4x4(columns: (
            SIMD4<Float>(2.0 / rsl, 0, 0, 0),
            SIMD4<Float>(0, 2.0 / tsb, 0, 0),
            SIMD4<Float>(0, 0, -2.0 / fsn, 0),
            SIMD4<Float>(-ral / rsl, -tab / tsb, -fan / fsn, 1)
        ))
    }
    
    static func translation(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(x, y, z, 1)
        return matrix
    }
    
    static func scale(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        return matrix_float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }
    
    static func rotation(angle: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
        let unitAxis = normalize(axis)
        let ct = cos(angle)
        let st = sin(angle)
        let ci = 1 - ct
        let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
        return matrix_float4x4(columns: (
            SIMD4<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
            SIMD4<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0),
            SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }
}
