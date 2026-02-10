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
    
    var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4
    var viewMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    struct ParticleSortItem {
        var particle: Particle
        var position: SIMD3<Float>
        var distance: Float
        var isTrail: Bool
        var inst: ParticleInstance?
    }
    
    init(device: MTLDevice, system: ParticleSystem, pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState?) {
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
        
        super.init(position: .zero, rotation: .zero, size: .zero, scale: .one, texture: dummyTex, pipeline: pipeline, depthState: depthState)
        
        let vertexSize = MemoryLayout<ParticleVertex>.stride * maxParticles * 4
        let indexSize = MemoryLayout<UInt16>.stride * maxParticles * 6
        
        for _ in 0..<bufferCount {
            if let vb = device.makeBuffer(length: vertexSize, options: .storageModeShared) {
                vertexBuffers.append(vb)
            }
            if let ib = device.makeBuffer(length: indexSize, options: .storageModeShared) {
                indexBuffers.append(ib)
            }
        }
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
        
        var vOffset = 0
        var iOffset = 0
        var pCount = 0
        
        var sortList: [ParticleSortItem] = []
        sortList.reserveCapacity(maxParticles)
        
        let camInv = viewMatrix.inverse
        let camPos = SIMD3<Float>(camInv.columns.3.x, camInv.columns.3.y, camInv.columns.3.z)
        
        for sub in system.subSystems {
            let isTrail = sub.material.renderer == "spritetrail" || sub.material.renderer == "ropetrail"
            
            for inst in sub.instances {
                if inst.noLiveParticle { continue }
                
                if isTrail {
                    genRopeData(inst: inst, vPtr: vPtr, iPtr: iPtr, vOffset: &vOffset, iOffset: &iOffset, pCount: &pCount)
                } else {
                    for p in inst.particles {
                        if p.lifetime <= 0 { continue }
                        let finalPos = inst.boundedData.pos + p.position
                        let dist = distance_squared(finalPos, camPos)
                        sortList.append(ParticleSortItem(particle: p, position: finalPos, distance: dist, isTrail: false, inst: nil))
                    }
                }
            }
        }
        
        sortList.sort { $0.distance > $1.distance }
        
        for item in sortList {
            if pCount >= maxParticles { break }
            genQuadData(p: item.particle, finalPos: item.position, vPtr: vPtr, iPtr: iPtr, vOffset: &vOffset, iOffset: &iOffset, pCount: &pCount)
        }
        
        if iOffset > 0 {
            encoder.setRenderPipelineState(pipelineState)
            if let ds = self.depthState {
                encoder.setDepthStencilState(ds)
            }
            
            encoder.setVertexBuffer(currentVB, offset: 0, index: 0)
            
            let finalModelMatrix = worldMatrix
            
            var uniforms = ParticleUniforms(
                projectionMatrix: self.projectionMatrix,
                viewMatrix: self.viewMatrix,
                modelMatrix: finalModelMatrix,
                viewportSize: .zero,
                time: Float(system.subSystems.first?.time ?? 0)
            )
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 1)
            
            if let tex = particleTexture {
                encoder.setFragmentTexture(tex, index: 0)
            } else {
                encoder.setFragmentTexture(self.texture, index: 0)
            }
            
            encoder.setFragmentBytes(&currentFrame, length: MemoryLayout<Float>.size, index: 2)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: iOffset, indexType: .uint16, indexBuffer: currentIB, indexBufferOffset: 0)
        }
    }
    
    private func genQuadData(p: Particle, finalPos: SIMD3<Float>, vPtr: UnsafeMutablePointer<ParticleVertex>, iPtr: UnsafeMutablePointer<UInt16>, vOffset: inout Int, iOffset: inout Int, pCount: inout Int) {
        let rot = p.rotation
        let cx = cos(rot.x), sx = sin(rot.x)
        let cy = cos(rot.y), sy = sin(rot.y)
        let cz = cos(rot.z), sz = sin(rot.z)
        
        let m00 = cy * cz
        let m01 = -cx * sz + sx * sy * cz
        let m02 = sx * sz + cx * sy * cz
        let m10 = cy * sz
        let m11 = cx * cz + sx * sy * sz
        let m12 = -sx * cz + cx * sy * sz
        let m20 = -sy
        let m21 = sx * cy
        let m22 = cx * cy
        
        let size = p.size
        let halfS = size * 0.5
        
        func rotate(_ x: Float, _ y: Float) -> SIMD3<Float> {
            return SIMD3<Float>(
                x * m00 + y * m01,
                x * m10 + y * m11,
                x * m20 + y * m21
            )
        }
        
        let o0 = rotate(-halfS, -halfS) + finalPos
        let o1 = rotate(halfS, -halfS) + finalPos
        let o2 = rotate(-halfS, halfS) + finalPos
        let o3 = rotate(halfS, halfS) + finalPos
        
        let normal = SIMD3<Float>(m02, m12, m22)
        let elapsedTime = p.initValue.lifetime - p.lifetime
        
        let col = SIMD4<Float>(p.color.x, p.color.y, p.color.z, p.alpha)
        let baseIndex = UInt16(vOffset)
        let seed = p.seed
        let normAge = SIMD4<Float>(normal.x, normal.y, normal.z, elapsedTime)
        
        vPtr[vOffset+0] = ParticleVertex(positionAndSeed: SIMD4<Float>(o0, seed), texData: SIMD4<Float>(0, 1, 0, 0), color: col, normalAndAge: normAge)
        vPtr[vOffset+1] = ParticleVertex(positionAndSeed: SIMD4<Float>(o1, seed), texData: SIMD4<Float>(1, 1, 0, 0), color: col, normalAndAge: normAge)
        vPtr[vOffset+2] = ParticleVertex(positionAndSeed: SIMD4<Float>(o2, seed), texData: SIMD4<Float>(0, 0, 0, 0), color: col, normalAndAge: normAge)
        vPtr[vOffset+3] = ParticleVertex(positionAndSeed: SIMD4<Float>(o3, seed), texData: SIMD4<Float>(1, 0, 0, 0), color: col, normalAndAge: normAge)
        
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
            let seed = p.seed
            let dummyNormal = SIMD4<Float>(0, 0, 1, 0)
            
            vPtr[vOffset+0] = ParticleVertex(positionAndSeed: SIMD4<Float>(startPos, seed), texData: SIMD4<Float>(0, 0, 0, size), color: col, normalAndAge: dummyNormal)
            vPtr[vOffset+1] = ParticleVertex(positionAndSeed: SIMD4<Float>(endPos, seed), texData: SIMD4<Float>(0, 1, trailLen, trailPos), color: col, normalAndAge: dummyNormal)
            vPtr[vOffset+2] = ParticleVertex(positionAndSeed: SIMD4<Float>(scp, seed), texData: SIMD4<Float>(1, 0, trailLen, trailPos), color: col, normalAndAge: dummyNormal)
            vPtr[vOffset+3] = ParticleVertex(positionAndSeed: SIMD4<Float>(ecp, seed), texData: SIMD4<Float>(1, 1, 0, size), color: col, normalAndAge: dummyNormal)
            
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
