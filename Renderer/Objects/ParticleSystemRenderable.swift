//
//  ParticleSystemRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

import MetalKit
import simd

class ParticleSystemRenderable: RenderableObject {
    let device: MTLDevice
    let system: ParticleSystem
    let pipelineState: MTLRenderPipelineState
    
    var vertexBuffers: [MTLBuffer] = []
    var indexBuffers: [MTLBuffer] = []
    let bufferCount = 3
    var bufferIndex = 0
    let maxParticles = 16384
    
    var particleTexture: MTLTexture?
    var currentFrame: Float = 0
    var animationSpeed: Float = 1.0
    var isAnimated: Bool = false
    
    init(device: MTLDevice, system: ParticleSystem, pipeline: MTLRenderPipelineState) {
        self.device = device
        self.system = system
        self.pipelineState = pipeline
        
        let desc = MTLTextureDescriptor()
        desc.pixelFormat = .bgra8Unorm
        desc.width = 1
        desc.height = 1
        desc.textureType = .type2DArray
        desc.arrayLength = 1
        desc.usage = .shaderRead
        let dummyTex = device.makeTexture(descriptor: desc)!
        
        super.init(position: .zero, rotation: .zero, size: .zero, scale: .one, texture: dummyTex, pipeline: pipeline)
        
        let vertexSize = MemoryLayout<ParticleVertex>.stride * maxParticles * 4
        let indexSize = MemoryLayout<UInt16>.stride * maxParticles * 6
        
        for _ in 0..<bufferCount {
            if let vb = device.makeBuffer(length: vertexSize, options: .storageModeShared) {
                vertexBuffers.append(vb)
            } else {
                Logger.error("Failed to create particle vertex buffer")
            }
            if let ib = device.makeBuffer(length: indexSize, options: .storageModeShared) {
                indexBuffers.append(ib)
            } else {
                Logger.error("Failed to create particle index buffer")
            }
        }
        
        Logger.log("ParticleSystemRenderable initialized with \(system.subSystems.count) subsystems")
    }
    
    func update(dt: Double) {
        system.update(dt: dt)
        if isAnimated, let tex = particleTexture {
            currentFrame += Float(dt) * 30.0 * animationSpeed
            let count = Float(tex.arrayLength)
            if currentFrame >= count {
                currentFrame = fmod(currentFrame, count)
            }
        }
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        guard !vertexBuffers.isEmpty, !indexBuffers.isEmpty else { return }
        
        bufferIndex = (bufferIndex + 1) % bufferCount
        let currentVB = vertexBuffers[bufferIndex]
        let currentIB = indexBuffers[bufferIndex]
        
        let vPtr = currentVB.contents().bindMemory(to: ParticleVertex.self, capacity: maxParticles * 4)
        let iPtr = currentIB.contents().bindMemory(to: UInt16.self, capacity: maxParticles * 6)
        
        var particleCount = 0
        var vOffset = 0
        var iOffset = 0
        
        for sub in system.subSystems {
            let isTrail = sub.material.renderer == "spritetrail" || sub.material.renderer == "ropetrail"
            
            for inst in sub.instances {
                if inst.noLiveParticle { continue }
                
                if isTrail {
                    genRopeData(inst: inst, vPtr: vPtr, iPtr: iPtr, vOffset: &vOffset, iOffset: &iOffset, pCount: &particleCount)
                } else {
                    genQuadData(inst: inst, vPtr: vPtr, iPtr: iPtr, vOffset: &vOffset, iOffset: &iOffset, pCount: &particleCount)
                }
            }
        }
        
        if iOffset > 0 {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(currentVB, offset: 0, index: 0)
            
            let geometryScale = Matrix4x4.scale(x: size.x, y: size.y, z: 1)
            let finalModelMatrix = worldMatrix * geometryScale
            
            var uniforms = ParticleUniforms(
                projectionMatrix: matrix_identity_float4x4,
                viewMatrix: matrix_identity_float4x4,
                modelMatrix: finalModelMatrix,
                viewportSize: .zero,
                time: Float(system.subSystems.first?.time ?? 0)
            )
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.size, index: 1)
            
            if let tex = particleTexture {
                encoder.setFragmentTexture(tex, index: 0)
            } else {
                encoder.setFragmentTexture(self.texture, index: 0)
            }
            
            encoder.setFragmentBytes(&currentFrame, length: MemoryLayout<Float>.size, index: 2)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: iOffset, indexType: .uint16, indexBuffer: currentIB, indexBufferOffset: 0)
        }
    }
    
    private func genQuadData(inst: ParticleInstance, vPtr: UnsafeMutablePointer<ParticleVertex>, iPtr: UnsafeMutablePointer<UInt16>, vOffset: inout Int, iOffset: inout Int, pCount: inout Int) {
        for p in inst.particles {
            if p.lifetime <= 0 { continue }
            if pCount >= maxParticles { break }
            
            let pos = inst.boundedData.pos + p.position
            let size = p.size
            let rot = p.rotation.z
            let col = SIMD4<Float>(p.color.x, p.color.y, p.color.z, p.alpha)
            
            let baseIndex = UInt16(vOffset)
            
            vPtr[vOffset+0] = ParticleVertex(position: pos, texData: SIMD4<Float>(0, 0, rot, size), color: col)
            vPtr[vOffset+1] = ParticleVertex(position: pos, texData: SIMD4<Float>(1, 0, rot, size), color: col)
            vPtr[vOffset+2] = ParticleVertex(position: pos, texData: SIMD4<Float>(0, 1, rot, size), color: col)
            vPtr[vOffset+3] = ParticleVertex(position: pos, texData: SIMD4<Float>(1, 1, rot, size), color: col)
            
            iPtr[iOffset+0] = baseIndex + 0
            iPtr[iOffset+1] = baseIndex + 1
            iPtr[iOffset+2] = baseIndex + 2
            iPtr[iOffset+3] = baseIndex + 1
            iPtr[iOffset+4] = baseIndex + 3
            iPtr[iOffset+5] = baseIndex + 2
            
            vOffset += 4
            iOffset += 6
            pCount += 1
        }
    }
    
    private func genRopeData(inst: ParticleInstance, vPtr: UnsafeMutablePointer<ParticleVertex>, iPtr: UnsafeMutablePointer<UInt16>, vOffset: inout Int, iOffset: inout Int, pCount: inout Int) {
        let particles = inst.particles
        guard particles.count > 1 else { return }
        
        for i in 1..<particles.count {
            if pCount >= maxParticles { break }
            let p = particles[i]
            let prevP = particles[i-1]
            if p.lifetime <= 0 { break }
            
            let size = p.size / 2.0
            let col = SIMD4<Float>(p.color.x, p.color.y, p.color.z, p.alpha)
            
            let dir = p.position - prevP.position
            let rot = p.rotation.z + Float.pi / 2.0
            
            var cpVec = SIMD3<Float>(0, size / 2.0, 0)
            let rotMat = matrix_float3x3(rows: [
                SIMD3<Float>(cos(rot), -sin(rot), 0),
                SIMD3<Float>(sin(rot), cos(rot), 0),
                SIMD3<Float>(0, 0, 1)
            ])
            cpVec = rotMat * cpVec
            
            if dot(normalize(dir), normalize(cpVec)) < 0 {
                cpVec = -cpVec
            }
            
            let startPos = prevP.position + inst.boundedData.pos
            let endPos = p.position + inst.boundedData.pos
            
            let scp = startPos + cpVec
            let ecp = endPos - cpVec
            
            let trailLen = Float(particles.count)
            let trailPos = Float(i - 1)
            
            let baseIndex = UInt16(vOffset)
            
            vPtr[vOffset+0] = ParticleVertex(position: startPos, texData: SIMD4<Float>(0, 0, 0, size), color: col)
            vPtr[vOffset+1] = ParticleVertex(position: endPos, texData: SIMD4<Float>(0, 1, trailLen, trailPos), color: col)
            vPtr[vOffset+2] = ParticleVertex(position: scp, texData: SIMD4<Float>(1, 0, trailLen, trailPos), color: col)
            vPtr[vOffset+3] = ParticleVertex(position: ecp, texData: SIMD4<Float>(1, 1, 0, size), color: col)
            
            iPtr[iOffset+0] = baseIndex + 0
            iPtr[iOffset+1] = baseIndex + 1
            iPtr[iOffset+2] = baseIndex + 2
            iPtr[iOffset+3] = baseIndex + 1
            iPtr[iOffset+4] = baseIndex + 3
            iPtr[iOffset+5] = baseIndex + 2
            
            vOffset += 4
            iOffset += 6
            pCount += 1
        }
    }
    
    func setTexture(_ tex: MTLTexture, isArray: Bool) {
        self.particleTexture = tex
        self.isAnimated = isArray
    }
}
