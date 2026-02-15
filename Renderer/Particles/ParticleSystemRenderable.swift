//
//  ParticleSystemRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/2/14.
//

import MetalKit
import simd

class ParticleSystemRenderable: RenderableObject {
    var system: ParticleSystem?
    var instancesRenderData: [(ParticleInstance, MTLTexture?, MTLBuffer?, Int, Bool, MTLRenderPipelineState, MTLDepthStencilState?)] = []
    var ropePipeline: MTLRenderPipelineState
    var baseFolder: URL
    
    init?(device: MTLDevice, file: URL, base: URL,
          additivePipeline: MTLRenderPipelineState,
          translucentPipeline: MTLRenderPipelineState,
          additiveArrayPipeline: MTLRenderPipelineState,
          translucentArrayPipeline: MTLRenderPipelineState,
          ropePipeline: MTLRenderPipelineState,
          depthWriteDisabledState: MTLDepthStencilState,
          depthNoneState: MTLDepthStencilState,
          defaultDepthState: MTLDepthStencilState,
          overrides: [String: ScriptableValue]?) async {
        
        self.ropePipeline = ropePipeline
        self.baseFolder = base
        super.init(position: .zero, rotation: .zero, size: .one, scale: .one, texture: nil, pipeline: additivePipeline, depthState: nil)
        
        Logger.log("Loading ParticleSystem from: \(file.lastPathComponent)")
        self.system = ParticleSystem(file: file, base: base)
        
        guard let sys = self.system else {
            return nil
        }
        
        if let root = sys.root?.instance, let ov = overrides {
            applyOverrides(inst: root, overrides: ov)
        }
        
        for inst in sys.allInstances {
            var selectedPipeline = additivePipeline
            var selectedDepthState = defaultDepthState
            var isArrayTexture = false
            
            if inst.materialPath.isEmpty {
                let maxVerts = inst.maxCount * (inst.isTrail ? 20 : 6)
                let stride = inst.isTrail ? MemoryLayout<ParticleRopeVertex>.stride : MemoryLayout<ParticleVertex>.stride
                let bufferSize = maxVerts * stride
                if let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) {
                    instancesRenderData.append((inst, nil, buffer, 0, inst.isTrail, selectedPipeline, selectedDepthState))
                }
                continue
            }

            var texPath = inst.materialPath
            var texURL = TextureManager.shared.resolveTextureURL(base: base, rawPath: texPath)
            var useTranslucent = false
            
            if texPath.hasSuffix(".json") {
                do {
                    let data = try Data(contentsOf: texURL)
                    let matDef = try JSONDecoder().decode(MaterialJSON.self, from: data)
                    if let firstPass = matDef.passes.first {
                        if let firstTex = firstPass.textures.first {
                            texPath = firstTex
                            texURL = TextureManager.shared.resolveTextureURL(base: base, rawPath: texPath)
                        }
                        if let blend = firstPass.blending, blend == "translucent" {
                            useTranslucent = true
                        }
                        
                        let depthTest = firstPass.depthtest ?? "enabled"
                        let depthWrite = firstPass.depthwrite ?? "enabled"
                        
                        if depthTest == "disabled" {
                            selectedDepthState = depthNoneState
                        } else if depthWrite == "disabled" {
                            selectedDepthState = depthWriteDisabledState
                        }
                    }
                } catch {
                    Logger.log("Failed to parse material JSON: \(texPath)")
                }
            }
            
            var tex: MTLTexture? = nil
            do {
                tex = try await TextureManager.shared.loadTexture(url: texURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: true])
                if let t = tex, t.textureType == .type2DArray {
                    isArrayTexture = true
                }
            } catch {
                Logger.log("Failed to load texture for instance: \(inst.name)")
            }
            
            if isArrayTexture {
                selectedPipeline = useTranslucent ? translucentArrayPipeline : additiveArrayPipeline
            } else {
                selectedPipeline = useTranslucent ? translucentPipeline : additivePipeline
            }
            
            let maxVerts = inst.maxCount * (inst.isTrail ? 20 : 6)
            let stride = inst.isTrail ? MemoryLayout<ParticleRopeVertex>.stride : MemoryLayout<ParticleVertex>.stride
            let bufferSize = maxVerts * stride
            
            if let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) {
                instancesRenderData.append((inst, tex, buffer, 0, inst.isTrail, selectedPipeline, selectedDepthState))
            }
        }
    }
    
    private func applyOverrides(inst: ParticleInstance, overrides: [String: ScriptableValue]) {
        for (key, val) in overrides {
            switch key {
            case "rate":
                if case .float(let f) = val { inst.emitRate = f }
                else if case .string(let s) = val, let f = Float(s) { inst.emitRate = f }
            case "count":
                if case .float(let f) = val { inst.emitRate = f }
                else if case .string(let s) = val, let f = Float(s) { inst.emitRate = f }
            case "alpha":
                var alpha: Float = 1.0
                if case .float(let f) = val { alpha = f }
                else if case .string(let s) = val, let f = Float(s) { alpha = f }
                inst.initializers.append { (p, t) in
                    ParticleModify.multiplyInitAlpha(p: &p, m: alpha)
                }
            case "color", "colorn":
                var r: Float = 1, g: Float = 1, b: Float = 1
                if case .string(let s) = val {
                    let parts = s.components(separatedBy: " ").compactMap { Float($0) }
                    if parts.count >= 3 {
                        r = parts[0]; g = parts[1]; b = parts[2]
                    }
                }
                inst.initializers.append { (p, t) in
                    ParticleModify.multiplyInitColor(p: &p, r: r, g: g, b: b)
                }
            default: break
            }
        }
    }
    
    override func update(deltaTime: Float) {
        system?.update(deltaTime: deltaTime)
        updateBuffers()
    }
    
    func updateBuffers() {
        for i in 0..<instancesRenderData.count {
            let (inst, tex, buffer, _, isTrail, _, _) = instancesRenderData[i]
            guard let buf = buffer else { continue }
            
            if isTrail {
                let count = genRopeData(instance: inst, buffer: buf)
                instancesRenderData[i].3 = count
            } else {
                let count = genParticleData(instance: inst, buffer: buf, texture: tex)
                instancesRenderData[i].3 = count
            }
        }
    }
    
    func genParticleData(instance: ParticleInstance, buffer: MTLBuffer, texture: MTLTexture?) -> Int {
        let ptr = buffer.contents().bindMemory(to: ParticleVertex.self, capacity: instance.maxCount * 6)
        var idx = 0
        
        let baseRight = SIMD3<Float>(1, 0, 0)
        let baseUp = SIMD3<Float>(0, 1, 0)
        
        let arrayLen = texture?.arrayLength ?? 1
        
        for p in instance.particles {
            if idx + 6 > instance.maxCount * 6 { break }
            
            let pos = p.position
            let halfSize = p.size * 0.5
            let color = p.color
            let rot = p.rotation.z
            
            let cr = cos(rot)
            let sr = sin(rot)
            
            let rx = baseRight.x * cr - baseRight.y * sr
            let ry = baseRight.x * sr + baseRight.y * cr
            let vecRight = SIMD3<Float>(rx, ry, 0) * halfSize
            
            let ux = baseUp.x * cr - baseUp.y * sr
            let uy = baseUp.x * sr + baseUp.y * cr
            let vecUp = SIMD3<Float>(ux, uy, 0) * halfSize
            
            let v1 = pos - vecRight - vecUp
            let v2 = pos + vecRight - vecUp
            let v3 = pos + vecRight + vecUp
            let v4 = pos - vecRight + vecUp
            
            var frame: Float = 0
            if arrayLen > 1 {
                let lifeRatio = 1.0 - (p.lifetime / instance.particleLifetime)
                frame = min(Float(arrayLen - 1), max(0, floor(lifeRatio * Float(arrayLen))))
            }
            
            let bl = ParticleVertex(position: SIMD4<Float>(v1.x, v1.y, v1.z, 1), data: SIMD4<Float>(0, 1, frame, 0), color: color)
            let br = ParticleVertex(position: SIMD4<Float>(v2.x, v2.y, v2.z, 1), data: SIMD4<Float>(1, 1, frame, 0), color: color)
            let tr = ParticleVertex(position: SIMD4<Float>(v3.x, v3.y, v3.z, 1), data: SIMD4<Float>(1, 0, frame, 0), color: color)
            let tl = ParticleVertex(position: SIMD4<Float>(v4.x, v4.y, v4.z, 1), data: SIMD4<Float>(0, 0, frame, 0), color: color)
            
            ptr[idx] = bl; idx+=1
            ptr[idx] = br; idx+=1
            ptr[idx] = tr; idx+=1
            ptr[idx] = bl; idx+=1
            ptr[idx] = tr; idx+=1
            ptr[idx] = tl; idx+=1
        }
        return idx
    }
    
    func genRopeData(instance: ParticleInstance, buffer: MTLBuffer) -> Int {
        let particles = instance.particles
        if particles.count < 2 { return 0 }
        
        let ptr = buffer.contents().bindMemory(to: ParticleRopeVertex.self, capacity: instance.maxCount * 6)
        var idx = 0
        
        for i in 1..<particles.count {
            let p = particles[i]
            let prev = particles[i-1]
            
            if p.lifetime <= 0 || prev.lifetime <= 0 { continue }
            
            let size = p.size / 2.0
            let rot = p.rotation.z + Float.pi / 2.0
            let cr = cos(rot)
            let sr = sin(rot)
            
            let cx = -(size * 0.5) * sr
            let cy = (size * 0.5) * cr
            var cpVec = SIMD3<Float>(cx, cy, 0)
            
            let posVec = p.position - prev.position
            let dist = length(posVec)
            if dist > 0.0001 {
                if dot(normalize(posVec), cpVec) <= 0 {
                    cpVec = -cpVec
                }
            }
            
            let v1Pos = prev.position - cpVec
            let v2Pos = prev.position + cpVec
            let v3Pos = p.position + cpVec
            let v4Pos = p.position - cpVec
            
            let trailLen = Float(particles.count)
            let trailPos = Float(i)
            
            let v1 = ParticleRopeVertex(
                position: SIMD4<Float>(v1Pos.x, v1Pos.y, v1Pos.z, size),
                endPosition: SIMD4<Float>(p.position.x, p.position.y, p.position.z, trailLen),
                cpStart: SIMD4<Float>(v1Pos.x, v1Pos.y, v1Pos.z, trailPos - 1),
                cpEnd: SIMD4<Float>(v4Pos.x, v4Pos.y, v4Pos.z, size),
                color: prev.color
            )
            
            let v2 = ParticleRopeVertex(
                position: SIMD4<Float>(v2Pos.x, v2Pos.y, v2Pos.z, size),
                endPosition: SIMD4<Float>(p.position.x, p.position.y, p.position.z, trailLen),
                cpStart: SIMD4<Float>(v2Pos.x, v2Pos.y, v2Pos.z, trailPos - 1),
                cpEnd: SIMD4<Float>(v3Pos.x, v3Pos.y, v3Pos.z, size),
                color: prev.color
            )
            
            let v3 = ParticleRopeVertex(
                position: SIMD4<Float>(v3Pos.x, v3Pos.y, v3Pos.z, size),
                endPosition: SIMD4<Float>(p.position.x, p.position.y, p.position.z, trailLen),
                cpStart: SIMD4<Float>(v3Pos.x, v3Pos.y, v3Pos.z, trailPos),
                cpEnd: SIMD4<Float>(v2Pos.x, v2Pos.y, v2Pos.z, size),
                color: p.color
            )
            
            let v4 = ParticleRopeVertex(
                position: SIMD4<Float>(v4Pos.x, v4Pos.y, v4Pos.z, size),
                endPosition: SIMD4<Float>(p.position.x, p.position.y, p.position.z, trailLen),
                cpStart: SIMD4<Float>(v4Pos.x, v4Pos.y, v4Pos.z, trailPos),
                cpEnd: SIMD4<Float>(v1Pos.x, v1Pos.y, v1Pos.z, size),
                color: p.color
            )
            
            ptr[idx] = v1; idx += 1
            ptr[idx] = v2; idx += 1
            ptr[idx] = v3; idx += 1
            ptr[idx] = v1; idx += 1
            ptr[idx] = v3; idx += 1
            ptr[idx] = v4; idx += 1
        }
        
        return idx
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        for (_, tex, buffer, count, isTrail, pipeline, depthState) in instancesRenderData {
            guard count > 0, let buf = buffer, let t = tex else { continue }
            
            encoder.setRenderPipelineState(pipeline)
            if let ds = depthState {
                encoder.setDepthStencilState(ds)
            }
            
            if isTrail {
                encoder.setRenderPipelineState(ropePipeline)
            }
            
            encoder.setFragmentTexture(t, index: 0)
            
            var modelMat = worldMatrix
            encoder.setVertexBytes(&modelMat, length: MemoryLayout<matrix_float4x4>.size, index: 2)
            
            encoder.setVertexBuffer(buf, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
    }
}
