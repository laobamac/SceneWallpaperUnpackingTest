//
//  ParticleRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

import Foundation
import MetalKit
import simd

class ParticleRenderable: RenderableObject {
    let simulator: ParticleSimulator
    var vertexBuffer: MTLBuffer?
    var indexBuffer: MTLBuffer?
    let device: MTLDevice
    
    var useRopeRenderer: Bool = false
    var ropeSubdivision: Int = 1
    var ropeUVScale: Float = 1.0
    var ropeUVScrolling: Bool = false
    var ropeUVSmoothing: Bool = true
    var uniformLifetimes: Bool = false
    
    var useTrailRenderer: Bool = false
    var trailLength: Float = 0.05
    var trailMaxLength: Float = 10.0
    var trailMinLength: Float = 0.0
    var ropeSegments: Int = 4
    
    var spritesheetCols: Int = 0
    var spritesheetRows: Int = 0
    var spritesheetFrames: Int = 0
    
    var overbright: Float = 1.0
    
    var indexCount: Int = 0
    var viewportSize: CGSize = CGSize(width: 3840, height: 2160)
    
    init(device: MTLDevice,
         object: SceneObject,
         definition: ParticleDefinition,
         override: ParticleInstanceOverride?,
         texture: MTLTexture?,
         pipeline: MTLRenderPipelineState,
         depthState: MTLDepthStencilState?) {
        
        self.device = device
        self.simulator = ParticleSimulator(definition: definition, override: override, baseObject: object)
        
        let pos = object.origin?.float3Value ?? .zero
        let rot = object.angles?.float3Value ?? .zero
        let sz = object.size?.float2Value ?? .zero
        let sc = object.scale?.float3Value ?? SIMD3<Float>(1, 1, 1)
        
        super.init(position: pos, rotation: rot, size: sz, scale: sc, texture: texture, frameInfo: nil, pipeline: pipeline, depthState: depthState)
        
        if let renderers = definition.renderer, let firstRenderer = renderers.first {
            let rName = firstRenderer.name ?? "sprite"
            if rName == "rope" || rName == "ropetrail" {
                self.useRopeRenderer = true
                self.ropeSubdivision = max(1, Int(firstRenderer.subdivision ?? 4.0))
                self.ropeUVScale = firstRenderer.uvscale ?? 1.0
                self.ropeUVScrolling = firstRenderer.uvscrolling ?? false
                self.ropeUVSmoothing = firstRenderer.uvsmoothing ?? true
                
                if rName == "ropetrail" {
                    self.useTrailRenderer = true
                    self.trailLength = firstRenderer.length ?? 0.05
                    self.ropeSegments = max(2, Int(firstRenderer.segments ?? 4.0))
                }
            } else if rName == "spritetrail" {
                self.useTrailRenderer = true
                self.trailLength = firstRenderer.length ?? 0.05
                self.trailMaxLength = firstRenderer.maxlength ?? 10.0
                self.trailMinLength = firstRenderer.minlength ?? 0.0
            }
        }
        
        if let lifeInit = definition.initializer?.first(where: { $0.name == "lifetimerandom" }) {
            let minL = lifeInit.min?.floatValue ?? 0.0
            let maxL = lifeInit.max?.floatValue ?? 1.0
            self.uniformLifetimes = (minL == maxL)
        }
        
        if self.texture != nil {
            self.spritesheetCols = 1
            self.spritesheetRows = 1
            self.spritesheetFrames = 1
        }
    }
    
    override func update(commandBuffer: MTLCommandBuffer) {
        let currentTime = Float(Date().timeIntervalSinceReferenceDate)
        let dt = min(Float(0.1), Float(1.0 / 60.0))
        
        let screenWidth = Float(max(1.0, viewportSize.width))
        let screenHeight = Float(max(1.0, viewportSize.height))
        
        simulator.update(dt: dt, currentTime: currentTime, screenWidth: screenWidth, screenHeight: screenHeight, mousePos: nil)
        
        updateBuffers()
    }
    
    private func updateBuffers() {
        if simulator.particleCount == 0 {
            indexCount = 0
            return
        }
        
        if useRopeRenderer {
            buildRopeBuffers()
        } else {
            buildSpriteBuffers()
        }
    }
    
    private func buildSpriteBuffers() {
        let maxParticles = simulator.particleCount
        var vertices = [ParticleSpriteVertex]()
        var indices = [UInt32]()
        
        vertices.reserveCapacity(maxParticles * 4)
        indices.reserveCapacity(maxParticles * 6)
        
        var activeParticles = [ParticleInstance]()
        for i in 0..<maxParticles {
            if simulator.particles[i].alive {
                activeParticles.append(simulator.particles[i])
            }
        }
        
        activeParticles.sort { $0.position.z < $1.position.z }
        
        var vertexIndex: UInt32 = 0
        
        for p in activeParticles {
            var lifetime = p.getLifetimePos()
            if spritesheetFrames > 0 && p.frame >= 0.0 {
                if simulator.particleDefinition.animationmode == "randomframe" {
                    lifetime = (p.frame + Float(0.5)) / Float(spritesheetFrames)
                } else {
                    lifetime = p.frame / Float(spritesheetFrames)
                }
            }
            
            let color = SIMD4<Float>(p.color.x, p.color.y, p.color.z, p.alpha)
            let velLife = SIMD4<Float>(p.velocity.x, p.velocity.y, p.velocity.z, lifetime)
            let rotXY = SIMD2<Float>(p.rotation.x, p.rotation.y)
            let rotZSize = SIMD2<Float>(p.rotation.z, p.size)
            
            let tc0 = SIMD4<Float>(0.0, 1.0, rotZSize.x, rotZSize.y)
            let tc1 = SIMD4<Float>(1.0, 1.0, rotZSize.x, rotZSize.y)
            let tc2 = SIMD4<Float>(1.0, 0.0, rotZSize.x, rotZSize.y)
            let tc3 = SIMD4<Float>(0.0, 0.0, rotZSize.x, rotZSize.y)
            
            let v0 = ParticleSpriteVertex(position: p.position, texCoordVec4: tc0, color: color, texCoordVec4C1: velLife, texCoordC2: rotXY)
            let v1 = ParticleSpriteVertex(position: p.position, texCoordVec4: tc1, color: color, texCoordVec4C1: velLife, texCoordC2: rotXY)
            let v2 = ParticleSpriteVertex(position: p.position, texCoordVec4: tc2, color: color, texCoordVec4C1: velLife, texCoordC2: rotXY)
            let v3 = ParticleSpriteVertex(position: p.position, texCoordVec4: tc3, color: color, texCoordVec4C1: velLife, texCoordC2: rotXY)
            
            vertices.append(v0)
            vertices.append(v1)
            vertices.append(v2)
            vertices.append(v3)
            
            indices.append(vertexIndex + 0)
            indices.append(vertexIndex + 1)
            indices.append(vertexIndex + 2)
            indices.append(vertexIndex + 2)
            indices.append(vertexIndex + 3)
            indices.append(vertexIndex + 0)
            
            vertexIndex += 4
        }
        
        indexCount = indices.count
        if indexCount > 0 {
            let vSize = vertices.count * MemoryLayout<ParticleSpriteVertex>.stride
            let iSize = indices.count * MemoryLayout<UInt32>.stride
            
            if vertexBuffer == nil || vertexBuffer!.length < vSize {
                vertexBuffer = device.makeBuffer(length: vSize, options: .storageModeShared)
            }
            if indexBuffer == nil || indexBuffer!.length < iSize {
                indexBuffer = device.makeBuffer(length: iSize, options: .storageModeShared)
            }
            
            vertexBuffer?.contents().copyMemory(from: vertices, byteCount: vSize)
            indexBuffer?.contents().copyMemory(from: indices, byteCount: iSize)
        }
    }
    
    private func catmullRom(p0: SIMD3<Float>, p1: SIMD3<Float>, p2: SIMD3<Float>, p3: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        let t2 = t * t
        let t3 = t2 * t
        let a = Float(2.0) * p1
        let b = p2 - p0
        let c = Float(2.0) * p0 - Float(5.0) * p1 + Float(4.0) * p2 - p3
        let d = -p0 + Float(3.0) * p1 - Float(3.0) * p2 + p3
        return Float(0.5) * (a + (b * t) + (c * t2) + (d * t3))
    }
    
    private func buildRopeBuffers() {
        let aliveCount = simulator.particleCount
        if aliveCount < 2 {
            indexCount = 0
            return
        }
        
        var activeParticles = [ParticleInstance]()
        for i in 0..<aliveCount {
            if simulator.particles[i].alive {
                activeParticles.append(simulator.particles[i])
            }
        }
        
        activeParticles.sort { $0.position.z < $1.position.z }
        let sortedCount = activeParticles.count
        
        if sortedCount < 2 {
            indexCount = 0
            return
        }
        
        let numSegments = sortedCount - 1
        let subdivision = max(1, ropeSubdivision)
        let totalPoints = numSegments * subdivision + 1
        
        var splinePositions = [SIMD3<Float>](repeating: .zero, count: totalPoints)
        var splineSizes = [Float](repeating: 0.0, count: totalPoints)
        var splineColors = [SIMD4<Float>](repeating: .zero, count: totalPoints)
        
        for i in 0..<numSegments {
            let p1 = activeParticles[i]
            let p2 = activeParticles[i + 1]
            let p0 = (i > 0) ? activeParticles[i - 1] : p1
            let p3 = (i + 2 < sortedCount) ? activeParticles[i + 2] : p2
            
            for k in 0..<subdivision {
                let t = Float(k) / Float(subdivision)
                let idx = i * subdivision + k
                splinePositions[idx] = catmullRom(p0: p0.position, p1: p1.position, p2: p2.position, p3: p3.position, t: t)
                splineSizes[idx] = p1.size + t * (p2.size - p1.size)
                
                let c1 = SIMD4<Float>(p1.color.x, p1.color.y, p1.color.z, p1.alpha)
                let c2 = SIMD4<Float>(p2.color.x, p2.color.y, p2.color.z, p2.alpha)
                splineColors[idx] = c1 + t * (c2 - c1)
            }
        }
        
        let pLast = activeParticles[sortedCount - 1]
        splinePositions[totalPoints - 1] = pLast.position
        splineSizes[totalPoints - 1] = pLast.size
        splineColors[totalPoints - 1] = SIMD4<Float>(pLast.color.x, pLast.color.y, pLast.color.z, pLast.alpha)
        
        var vertices = [ParticleRopeVertex]()
        var indices = [UInt32]()
        let totalSubSegments = totalPoints - 1
        vertices.reserveCapacity(totalSubSegments * 4)
        indices.reserveCapacity(totalSubSegments * 6)
        
        let uvScale = ropeUVScale > 0.0 ? ropeUVScale : 1.0
        let trLength = Float(totalSubSegments) / uvScale + Float(1.0)
        let usableLength = trLength - Float(1.0)
        
        let useSmoothing = ropeUVSmoothing && uniformLifetimes && !ropeUVScrolling
        var cumulativeArcLength = [Float](repeating: 0.0, count: totalPoints)
        var totalArcLength: Float = 0.0
        
        if useSmoothing {
            for i in 1..<totalPoints {
                totalArcLength += distance(splinePositions[i], splinePositions[i - 1])
                cumulativeArcLength[i] = totalArcLength
            }
        }
        
        var scrollOffset: Float = 0.0
        if ropeUVScrolling && usableLength > 0.0 {
            scrollOffset = fmod(simulator.time, Float(10000.0)) * usableLength
        }
        
        var vertexIndex: UInt32 = 0
        
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
            
            let pv4 = SIMD4<Float>(posStart.x, posStart.y, posStart.z, sizeStart)
            let tv4 = SIMD4<Float>(posEnd.x, posEnd.y, posEnd.z, trLength)
            let tv4C1 = SIMD4<Float>(posPrev.x, posPrev.y, posPrev.z, trailPosition)
            let tv4C2 = SIMD4<Float>(posAfter.x, posAfter.y, posAfter.z, sizeEnd)
            let tv4C3 = colorEnd
            let colStart = colorStart
            
            let t0 = SIMD2<Float>(0.0, 0.0)
            let t1 = SIMD2<Float>(1.0, 0.0)
            let t2 = SIMD2<Float>(1.0, 1.0)
            let t3 = SIMD2<Float>(0.0, 1.0)
            
            let v0 = ParticleRopeVertex(positionVec4: pv4, texCoordVec4: tv4, texCoordVec4C1: tv4C1, texCoordVec4C2: tv4C2, texCoordVec4C3: tv4C3, texCoordC4: t0, color: colStart)
            let v1 = ParticleRopeVertex(positionVec4: pv4, texCoordVec4: tv4, texCoordVec4C1: tv4C1, texCoordVec4C2: tv4C2, texCoordVec4C3: tv4C3, texCoordC4: t1, color: colStart)
            let v2 = ParticleRopeVertex(positionVec4: pv4, texCoordVec4: tv4, texCoordVec4C1: tv4C1, texCoordVec4C2: tv4C2, texCoordVec4C3: tv4C3, texCoordC4: t2, color: colStart)
            let v3 = ParticleRopeVertex(positionVec4: pv4, texCoordVec4: tv4, texCoordVec4C1: tv4C1, texCoordVec4C2: tv4C2, texCoordVec4C3: tv4C3, texCoordC4: t3, color: colStart)
            
            vertices.append(v0)
            vertices.append(v1)
            vertices.append(v2)
            vertices.append(v3)
            
            indices.append(vertexIndex + 0)
            indices.append(vertexIndex + 1)
            indices.append(vertexIndex + 2)
            indices.append(vertexIndex + 2)
            indices.append(vertexIndex + 3)
            indices.append(vertexIndex + 0)
            
            vertexIndex += 4
        }
        
        indexCount = indices.count
        if indexCount > 0 {
            let vSize = vertices.count * MemoryLayout<ParticleRopeVertex>.stride
            let iSize = indices.count * MemoryLayout<UInt32>.stride
            
            if vertexBuffer == nil || vertexBuffer!.length < vSize {
                vertexBuffer = device.makeBuffer(length: vSize, options: .storageModeShared)
            }
            if indexBuffer == nil || indexBuffer!.length < iSize {
                indexBuffer = device.makeBuffer(length: iSize, options: .storageModeShared)
            }
            
            vertexBuffer?.contents().copyMemory(from: vertices, byteCount: vSize)
            indexBuffer?.contents().copyMemory(from: indices, byteCount: iSize)
        }
    }
    
    private func makeTranslationMatrix(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1.0)
        return m
    }
    
    private func makeScaleMatrix(_ s: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.0.x = s.x
        m.columns.1.y = s.y
        m.columns.2.z = s.z
        return m
    }
    
    private func makeRotationMatrix(angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        let a = normalize(axis)
        let c = cos(angle)
        let s = sin(angle)
        let mc = Float(1.0) - c
        let x = a.x, y = a.y, z = a.z
        let col0 = SIMD4<Float>(c + x*x*mc, x*y*mc + z*s, x*z*mc - y*s, 0)
        let col1 = SIMD4<Float>(x*y*mc - z*s, c + y*y*mc, y*z*mc + x*s, 0)
        let col2 = SIMD4<Float>(x*z*mc + y*s, y*z*mc - x*s, c + z*z*mc, 0)
        let col3 = SIMD4<Float>(0, 0, 0, 1)
        return simd_float4x4(col0, col1, col2, col3)
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        if indexCount == 0 { return }
        guard let vBuf = vertexBuffer, let iBuf = indexBuffer else { return }
        
        encoder.setRenderPipelineState(pipeline)
        if let ds = depthState {
            encoder.setDepthStencilState(ds)
        }
        
        if let validTex = self.texture {
            encoder.setFragmentTexture(validTex, index: 0)
        }
        
        let tMat = makeTranslationMatrix(simulator.transformedOrigin)
        let rZ = makeRotationMatrix(angle: -self.localRotation.z, axis: SIMD3<Float>(0, 0, 1))
        let rY = makeRotationMatrix(angle: self.localRotation.y, axis: SIMD3<Float>(0, 1, 0))
        let rX = makeRotationMatrix(angle: -self.localRotation.x, axis: SIMD3<Float>(1, 0, 0))
        let sMat = makeScaleMatrix(self.scale)
        
        var m = matrix_multiply(matrix_identity_float4x4, tMat)
        m = matrix_multiply(m, rZ)
        m = matrix_multiply(m, rY)
        m = matrix_multiply(m, rX)
        m = matrix_multiply(m, sMat)
        let modelMatrix = m
        
        let is3D = ((simulator.particleDefinition.flags ?? 0) & 4) != 0
        var viewProj = matrix_identity_float4x4
        let eyePos = SIMD3<Float>(0, 0, 1000)
        
        let fov = Float(50.0) * (Float.pi / Float(180.0))
        let screenWidth = Float(max(1.0, viewportSize.width))
        let screenHeight = Float(max(1.0, viewportSize.height))
        let aspect = screenWidth / screenHeight
        
        if is3D {
            let yMax = Float(0.01) * tan(fov * Float(0.5))
            let yMin = -yMax
            let xMin = yMin * aspect
            let xMax = yMax * aspect
            
            let q = Float(10000.0) / (Float(10000.0) - Float(0.01))
            
            var proj = matrix_identity_float4x4
            proj.columns.0.x = (Float(2.0) * Float(0.01)) / (xMax - xMin)
            proj.columns.1.y = (Float(2.0) * Float(0.01)) / (yMax - yMin)
            proj.columns.2.x = (xMax + xMin) / (xMax - xMin)
            proj.columns.2.y = (yMax + yMin) / (yMax - yMin)
            proj.columns.2.z = q
            proj.columns.2.w = Float(1.0)
            proj.columns.3.z = -q * Float(0.01)
            proj.columns.3.w = Float(0.0)
            
            var view = matrix_identity_float4x4
            view.columns.3 = SIMD4<Float>(0, 0, 1000, 1.0)
            
            viewProj = matrix_multiply(proj, view.inverse)
        } else {
            let camDist = (screenHeight / Float(2.0)) / tan(fov / Float(2.0))
            
            let yMax = Float(10.0) * tan(fov * Float(0.5))
            let yMin = -yMax
            let xMin = yMin * aspect
            let xMax = yMax * aspect
            
            let q = Float(10000.0) / (Float(10000.0) - Float(10.0))
            
            var proj = matrix_identity_float4x4
            proj.columns.0.x = (Float(2.0) * Float(10.0)) / (xMax - xMin)
            proj.columns.1.y = (Float(2.0) * Float(10.0)) / (yMax - yMin)
            proj.columns.2.x = (xMax + xMin) / (xMax - xMin)
            proj.columns.2.y = (yMax + yMin) / (yMax - yMin)
            proj.columns.2.z = q
            proj.columns.2.w = Float(1.0)
            proj.columns.3.z = -q * Float(10.0)
            proj.columns.3.w = Float(0.0)
            
            var view = matrix_identity_float4x4
            view.columns.3 = SIMD4<Float>(-screenWidth / Float(2.0), -screenHeight / Float(2.0), camDist, Float(1.0))
            
            viewProj = matrix_multiply(proj, view)
        }
        
        let mvp = matrix_multiply(viewProj, modelMatrix)
        
        var frameWidth: Float = 0.0
        var frameHeight: Float = 0.0
        var texRatio: Float = 1.0
        
        let texWidth = Float(self.texture?.width ?? 1)
        let texHeight = Float(self.texture?.height ?? 1)
        
        if spritesheetFrames > 0 && spritesheetCols > 0 && spritesheetRows > 0 {
            frameWidth = Float(1.0) / Float(spritesheetCols)
            frameHeight = Float(1.0) / Float(spritesheetRows)
            texRatio = (texHeight * frameHeight) / (texWidth * frameWidth)
        } else {
            texRatio = texHeight / texWidth
        }
        
        var uniforms = ParticleUniforms(
            modelMatrix: modelMatrix,
            modelMatrixInverse: modelMatrix.inverse,
            mvpMatrix: mvp,
            mvpMatrixInverse: mvp.inverse,
            viewProjectionMatrix: viewProj,
            orientationUp: SIMD3<Float>(0, 1, 0),
            orientationRight: SIMD3<Float>(1, 0, 0),
            orientationForward: SIMD3<Float>(0, 0, 1),
            viewUp: SIMD3<Float>(0, 1, 0),
            viewRight: SIMD3<Float>(1, 0, 0),
            eyePosition: eyePos,
            renderVar0: SIMD4<Float>(trailLength, trailMaxLength, trailMinLength, 0.0),
            renderVar1: SIMD4<Float>(frameWidth, frameHeight, Float(spritesheetFrames), texRatio),
            overbright: overbright,
            padding1: 0,
            padding2: 0,
            padding3: 0
        )
        
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.stride, index: 2)
        
        encoder.setVertexBuffer(vBuf, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: iBuf, indexBufferOffset: 0)
    }
}
