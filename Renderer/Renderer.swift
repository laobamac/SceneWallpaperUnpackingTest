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

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!
    var samplerState: MTLSamplerState!
    var textureLoader: MTKTextureLoader
    
    var baseFolder: URL?
    // 存储所有渲染对象，按ID索引以便查找父节点
    var renderables: [RenderableObject] = []
    
    var startTime: Date = Date()
    var projectionSize: CGSize = CGSize(width: 1920, height: 1080)
    var viewportSize: CGSize = .zero
    
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
        let vertexFunc = library.makeFunction(name: "vertex_main")
        let fragmentFunc = library.makeFunction(name: "fragment_main")
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Uber Pipeline"
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
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
                if let renderable = createRenderable(from: obj) {
                    // 如果有ID，记录下来
                    if let id = obj.id {
                        tempRenderables[id] = renderable
                        renderable.id = id
                    }
                    renderable.parentId = obj.parent
                    orderedList.append(renderable)
                }
            }
            
            // 2. 建立父子关系 (Hierarchy Linking)
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
        
        // 使用 bottomLeft 加载纹理，这是 Metal 的标准
        guard let texture = try? textureLoader.newTexture(URL: finalTexURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) else { return nil }
        
        // 解析 Transform
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
            // JSON 通常是 deg，我们需要 rad
            rotation.x = angleStrs[0] * .pi / 180.0
            rotation.y = angleStrs[1] * .pi / 180.0
            rotation.z = angleStrs[2] * .pi / 180.0
        }
        
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
    
    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let samplerState = samplerState else { return }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        
        encoder.setRenderPipelineState(pipelineState)
        
        let time = Float(Date().timeIntervalSince(startTime))
        
        // 投影矩阵: 0..W, 0..H (Bottom Left is 0,0)
        let proj = Matrix4x4.orthographic(left: 0, right: Float(projectionSize.width),
                                          bottom: 0, top: Float(projectionSize.height),
                                          near: -1000, far: 1000)
        var globals = GlobalUniforms(projectionMatrix: proj, viewMatrix: matrix_identity_float4x4, time: time)
        
        encoder.setVertexBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
        encoder.setFragmentBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        for obj in renderables {
            obj.draw(encoder: encoder)
        }
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - Renderable Object with Hierarchy
class RenderableObject {
    var id: Int = -1
    var parentId: Int?
    weak var parent: RenderableObject?
    
    let localPosition: SIMD3<Float>
    let localRotation: SIMD3<Float>
    let size: SIMD2<Float>
    let scale: SIMD3<Float>
    
    let texture: MTLTexture
    let effects: [EffectParams]
    let masks: [MTLTexture?]
    
    // 修复后的顶点：V轴翻转 (0->0, 1->1) 以匹配 Metal 纹理坐标原点
    let vertices: [Float] = [
        -0.5, -0.5, 0, 0, 0, // Bottom-Left: UV(0, 0) -> Texture Bottom-Left
         0.5, -0.5, 0, 1, 0, // Bottom-Right: UV(1, 0)
        -0.5,  0.5, 0, 0, 1, // Top-Left: UV(0, 1) -> Texture Top-Left
         0.5,  0.5, 0, 1, 1  // Top-Right: UV(1, 1)
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
    
    // 递归计算 World Matrix
    var worldMatrix: matrix_float4x4 {
        // Local: Translation * Rotation * Scale (for size)
        // 注意：WE 中 scale 属性通常是附加缩放，size 属性是基本大小
        // 我们在 draw 里面构建 geometry scale，这里处理 Transform hierarchy
        
        // 1. 本地变换
        var local = Matrix4x4.translation(x: localPosition.x, y: localPosition.y, z: localPosition.z)
        local = local * Matrix4x4.rotation(angle: localRotation.z, axis: SIMD3<Float>(0, 0, 1)) // 主要处理2D Z轴旋转
        
        // 2. 如果有父节点，乘上父节点的 World Matrix
        if let p = parent {
            return p.worldMatrix * local
        }
        return local
    }
    
    func draw(encoder: MTLRenderCommandEncoder) {
        // 最终 Model Matrix = Parent... * Local * GeometryScale
        // GeometryScale 将 1x1 的单位 Quad 放大到物体尺寸
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
