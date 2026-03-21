//
//  ParticleRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/3/21.
//

import MetalKit
import simd

class ParticleRenderable: RenderableObject {
    let simulator: ParticleSimulator
    var vertexBuffers: [MTLBuffer] = []
    var indexBuffers: [MTLBuffer] = []
    let inFlightCount = 3
    var currentBufferIndex = 0
    var activeIndexCount = 0
    let useRopeRenderer: Bool
    
    init?(device: MTLDevice, simulator: ParticleSimulator, texture: MTLTexture?, frameInfo: [TexFrameInfo]?, pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState?, useRopeRenderer: Bool) {
        self.simulator = simulator
        self.useRopeRenderer = useRopeRenderer
        
        super.init(position: SIMD3<Float>(0, 0, 0), rotation: SIMD3<Float>(0, 0, 0), size: SIMD2<Float>(1, 1), scale: SIMD2<Float>(1, 1), texture: texture, frameInfo: frameInfo, pipeline: pipeline, depthState: depthState)
        
        let maxP = simulator.maxParticles
        let vSize: Int
        let iSize: Int
        
        if useRopeRenderer {
            let subdivision = max(1, simulator.def.renderer?.first?.subdivision ?? 4)
            let maxSubSegments = max(1, maxP - 1) * subdivision
            vSize = maxSubSegments * 4 * 26 * MemoryLayout<Float>.stride
            iSize = maxSubSegments * 6 * MemoryLayout<UInt32>.stride
        } else {
            vSize = maxP * 4 * 17 * MemoryLayout<Float>.stride
            iSize = maxP * 6 * MemoryLayout<UInt32>.stride
        }
        
        for _ in 0..<inFlightCount {
            if let vb = device.makeBuffer(length: max(1024, vSize), options: .storageModeShared),
               let ib = device.makeBuffer(length: max(1024, iSize), options: .storageModeShared) {
                vertexBuffers.append(vb)
                indexBuffers.append(ib)
            } else {
                Logger.error("ParticleRenderable Buffer")
                return nil
            }
        }
    }
    
    override func update(commandBuffer: MTLCommandBuffer) {
        currentBufferIndex = (currentBufferIndex + 1) % inFlightCount
        
        if useRopeRenderer {
            updateRopeGeometry()
        } else {
            updateSpriteGeometry()
        }
    }
    
    private func updateSpriteGeometry() {
        let maxP = simulator.particleCount
        if maxP == 0 {
            activeIndexCount = 0
            return
        }
        
        let vBuffer = vertexBuffers[currentBufferIndex]
        let iBuffer = indexBuffers[currentBufferIndex]
        
        let vPtr = vBuffer.contents().bindMemory(to: Float.self, capacity: maxP * 4 * 17)
        let iPtr = iBuffer.contents().bindMemory(to: UInt32.self, capacity: maxP * 6)
        
        var vIdx = 0
        var iIdx = 0
        
        var numFrames = 1
        if let frames = frameInfo, frames.count > 0 {
            numFrames = frames.count
        }
        
        for i in 0..<maxP {
            let p = simulator.particles[i]
            if !p.alive { continue }
            
            if !p.position.x.isFinite || !p.position.y.isFinite || !p.position.z.isFinite || !p.size.isFinite || p.size <= 0.0 || p.size > 10000.0 {
                continue
            }
            
            var lifetime = p.getLifetimePos()
            if numFrames > 0 && p.frame >= 0.0 {
                lifetime = p.frame / Float(numFrames)
            }
            
            let addVertex = { (u: Float, v: Float, base: Int) in
                vPtr[base + 0] = p.position.x
                vPtr[base + 1] = p.position.y
                vPtr[base + 2] = p.position.z
                
                vPtr[base + 3] = u
                vPtr[base + 4] = v
                vPtr[base + 5] = p.rotation.z
                vPtr[base + 6] = p.size
                
                vPtr[base + 7] = p.color.x
                vPtr[base + 8] = p.color.y
                vPtr[base + 9] = p.color.z
                vPtr[base + 10] = p.alpha
                
                vPtr[base + 11] = p.velocity.x
                vPtr[base + 12] = p.velocity.y
                vPtr[base + 13] = p.velocity.z
                vPtr[base + 14] = lifetime
                
                vPtr[base + 15] = p.rotation.x
                vPtr[base + 16] = p.rotation.y
            }
            
            let baseV = vIdx
            addVertex(0.0, 1.0, vIdx * 17); vIdx += 1
            addVertex(1.0, 1.0, vIdx * 17); vIdx += 1
            addVertex(1.0, 0.0, vIdx * 17); vIdx += 1
            addVertex(0.0, 0.0, vIdx * 17); vIdx += 1
            
            iPtr[iIdx] = UInt32(baseV + 0); iIdx += 1
            iPtr[iIdx] = UInt32(baseV + 1); iIdx += 1
            iPtr[iIdx] = UInt32(baseV + 2); iIdx += 1
            iPtr[iIdx] = UInt32(baseV + 2); iIdx += 1
            iPtr[iIdx] = UInt32(baseV + 3); iIdx += 1
            iPtr[iIdx] = UInt32(baseV + 0); iIdx += 1
        }
        
        activeIndexCount = iIdx
    }
    
    private func updateRopeGeometry() {
        let aliveCount = simulator.particleCount
        if aliveCount < 2 {
            activeIndexCount = 0
            return
        }
        
        let rendererDef = simulator.def.renderer?.first
        let subdivision = max(1, rendererDef?.subdivision ?? 4)
        let numSegments = aliveCount - 1
        let totalPoints = numSegments * subdivision + 1
        
        var splinePositions = Array(repeating: SIMD3<Float>(), count: totalPoints)
        var splineSizes = Array(repeating: Float(), count: totalPoints)
        var splineColors = Array(repeating: SIMD4<Float>(), count: totalPoints)
        
        let catmullRom = { (p0: SIMD3<Float>, p1: SIMD3<Float>, p2: SIMD3<Float>, p3: SIMD3<Float>, t: Float) -> SIMD3<Float> in
            let t2 = t * t
            let t3 = t2 * t
            let v0 = 2.0 * p1
            let v1 = (-p0 + p2) * t
            let v2 = (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
            let v3 = (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
            return 0.5 * (v0 + v1 + v2 + v3)
        }
        
        for i in 0..<numSegments {
            let p1 = simulator.particles[i]
            let p2 = simulator.particles[i + 1]
            let p0 = (i > 0) ? simulator.particles[i - 1] : p1
            let p3 = (i + 2 < aliveCount) ? simulator.particles[i + 2] : p2
            
            for k in 0..<subdivision {
                let t = Float(k) / Float(subdivision)
                let idx = i * subdivision + k
                
                splinePositions[idx] = catmullRom(p0.position, p1.position, p2.position, p3.position, t)
                splineSizes[idx] = mix(p1.size, p2.size, t: t)
                let colorStart = SIMD4<Float>(p1.color.x, p1.color.y, p1.color.z, p1.alpha)
                let colorEnd = SIMD4<Float>(p2.color.x, p2.color.y, p2.color.z, p2.alpha)
                splineColors[idx] = mix(colorStart, colorEnd, t: t)
            }
        }
        
        let pLast = simulator.particles[aliveCount - 1]
        splinePositions[totalPoints - 1] = pLast.position
        splineSizes[totalPoints - 1] = pLast.size
        splineColors[totalPoints - 1] = SIMD4<Float>(pLast.color.x, pLast.color.y, pLast.color.z, pLast.alpha)
        
        let vBuffer = vertexBuffers[currentBufferIndex]
        let iBuffer = indexBuffers[currentBufferIndex]
        
        let vPtr = vBuffer.contents().bindMemory(to: Float.self, capacity: totalPoints * 4 * 26)
        let iPtr = iBuffer.contents().bindMemory(to: UInt32.self, capacity: totalPoints * 6)
        
        var vIdx = 0
        var iIdx = 0
        
        let totalSubSegments = totalPoints - 1
        let uvScale = rendererDef?.uvscale ?? 1.0
        let safeUvScale = uvScale > 0.0 ? uvScale : 1.0
        let trailLength = Float(totalSubSegments) / safeUvScale + 1.0
        
        let useSmoothing = (rendererDef?.uvsmoothing ?? true) && simulator.uniformLifetimes && !(rendererDef?.uvscrolling ?? false)
        var cumulativeArcLength: [Float] = []
        var totalArcLength: Float = 0.0
        
        if useSmoothing {
            cumulativeArcLength = Array(repeating: 0.0, count: totalPoints)
            for i in 1..<totalPoints {
                totalArcLength += distance(splinePositions[i], splinePositions[i - 1])
                cumulativeArcLength[i] = totalArcLength
            }
        }
        
        var scrollOffset: Float = 0.0
        if rendererDef?.uvscrolling ?? false && (trailLength - 1.0) > 0.0 {
            scrollOffset = Float(fmod(simulator.time, 10000.0)) * (trailLength - 1.0)
        }
        
        for s in 0..<totalSubSegments {
            let posStart = splinePositions[s]
            let posEnd = splinePositions[s + 1]
            let sizeStart = splineSizes[s]
            let sizeEnd = splineSizes[s + 1]
            let colorStart = splineColors[s]
            let colorEnd = splineColors[s + 1]
            let posPrev = (s > 0) ? splinePositions[s - 1] : posStart
            let posAfter = (s + 2 < totalPoints) ? splinePositions[s + 2] : posEnd
            
            var trailPosition: Float = 0.0
            if useSmoothing && totalArcLength > 0.0 {
                trailPosition = (cumulativeArcLength[s] / totalArcLength) * Float(totalSubSegments)
            } else {
                trailPosition = Float(s)
            }
            trailPosition += scrollOffset
            
            let addRopeVertex = { (uvX: Float, uvY: Float, base: Int) in
                vPtr[base + 0] = posStart.x
                vPtr[base + 1] = posStart.y
                vPtr[base + 2] = posStart.z
                vPtr[base + 3] = sizeStart
                
                vPtr[base + 4] = posEnd.x
                vPtr[base + 5] = posEnd.y
                vPtr[base + 6] = posEnd.z
                vPtr[base + 7] = trailLength
                
                vPtr[base + 8] = posPrev.x
                vPtr[base + 9] = posPrev.y
                vPtr[base + 10] = posPrev.z
                vPtr[base + 11] = trailPosition
                
                vPtr[base + 12] = posAfter.x
                vPtr[base + 13] = posAfter.y
                vPtr[base + 14] = posAfter.z
                vPtr[base + 15] = sizeEnd
                
                vPtr[base + 16] = colorEnd.x
                vPtr[base + 17] = colorEnd.y
                vPtr[base + 18] = colorEnd.z
                vPtr[base + 19] = colorEnd.w
                
                vPtr[base + 20] = uvX
                vPtr[base + 21] = uvY
                
                vPtr[base + 22] = colorStart.x
                vPtr[base + 23] = colorStart.y
                vPtr[base + 24] = colorStart.z
                vPtr[base + 25] = colorStart.w
            }
            
            let baseV = vIdx
            addRopeVertex(0.0, 0.0, vIdx * 26); vIdx += 1
            addRopeVertex(1.0, 0.0, vIdx * 26); vIdx += 1
            addRopeVertex(1.0, 1.0, vIdx * 26); vIdx += 1
            addRopeVertex(0.0, 1.0, vIdx * 26); vIdx += 1
            
            iPtr[iIdx] = UInt32(baseV + 0); iIdx += 1
            iPtr[iIdx] = UInt32(baseV + 1); iIdx += 1
            iPtr[iIdx] = UInt32(baseV + 2); iIdx += 1
            iPtr[iIdx] = UInt32(baseV + 2); iIdx += 1
            iPtr[iIdx] = UInt32(baseV + 3); iIdx += 1
            iPtr[iIdx] = UInt32(baseV + 0); iIdx += 1
        }
        
        activeIndexCount = iIdx
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        if activeIndexCount == 0 { return }
        
        var uniforms = ParticleUniforms()
        var modelMat = matrix_identity_float4x4
        modelMat = RendererMath.translate(modelMat, simulator.transformedOrigin)
        modelMat = RendererMath.scale(modelMat, SIMD3<Float>(1, 1, 1))
        
        uniforms.modelMatrix = modelMat
        uniforms.modelMatrixInverse = modelMat.inverse
        uniforms.mvpMatrix = modelMat
        uniforms.viewProjectionMatrix = matrix_identity_float4x4
        
        uniforms.orientationUp = SIMD3<Float>(0, 1, 0)
        uniforms.orientationRight = SIMD3<Float>(1, 0, 0)
        uniforms.orientationForward = SIMD3<Float>(0, 0, 1)
        uniforms.viewUp = SIMD3<Float>(0, 1, 0)
        uniforms.viewRight = SIMD3<Float>(1, 0, 0)
        uniforms.eyePosition = SIMD3<Float>(0, 0, 1000.0)
        
        var renderVar0 = SIMD4<Float>(0, 0, 0, 0)
        if let renderer = simulator.def.renderer?.first {
            renderVar0.x = renderer.length ?? 0.0
            renderVar0.y = renderer.maxlength ?? 0.0
            renderVar0.z = renderer.minlength ?? 0.0
        }
        uniforms.renderVar0 = renderVar0
        
        var renderVar1 = SIMD4<Float>(0, 0, 0, 1.0)
        if let tex = texture {
            renderVar1.w = Float(tex.height) / Float(tex.width)
            if let frames = frameInfo, frames.count > 0 {
                renderVar1.z = Float(frames.count)
                renderVar1.x = 1.0 / Float(frames.last?.row ?? 1)
                renderVar1.y = 1.0 / Float(frames.last?.col ?? 1)
            }
        }
        uniforms.renderVar1 = renderVar1
        
        uniforms.overbright = 1.0
        uniforms.refractAmount = 0.05
        uniforms.padding1 = 0
        uniforms.padding2 = 0
        
        encoder.setRenderPipelineState(pipeline)
        if let ds = depthState {
            encoder.setDepthStencilState(ds)
        }
        if let tex = texture {
            encoder.setFragmentTexture(tex, index: 0)
        }
        
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.size, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.size, index: 2)
        
        encoder.setVertexBuffer(vertexBuffers[currentBufferIndex], offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: activeIndexCount, indexType: .uint32, indexBuffer: indexBuffers[currentBufferIndex], indexBufferOffset: 0)
    }
}
