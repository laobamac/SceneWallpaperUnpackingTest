//
//  ParticleSystemRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import MetalKit
import simd

class ParticleSystemRenderable: RenderableObject {
    let system: ParticleSystem
    let device: MTLDevice

    var vertexBuffers: [MTLBuffer] = []
    var indexBuffers: [MTLBuffer] = []
    var currentBufferIndex = 0
    let maxBuffers = 3

    var activeIndexCount: Int = 0

    var isRope: Bool = false
    var ropeSubdivision: Int = 4
    var ropeUVScale: Float = 1.0
    var ropeUVScrolling: Bool = false
    var ropeUVSmoothing: Bool = true
    var uniformLifetimes: Bool = false
    var trailLength: Float = 0.05
    var trailMaxLength: Float = 10.0
    var trailMinLength: Float = 0.0

    var spritesheetCols: Int = 0
    var spritesheetRows: Int = 0

    var controlPoints: [ControlPointData] = Array(
        repeating: ControlPointData(),
        count: 8
    )

    let particleFlags: Int
    let instanceOverride: ParticleInstanceOverride?

    struct SpriteVertex {
        var position: SIMD4<Float>
        var texCoordAndSize: SIMD4<Float>
        var color: SIMD4<Float>
        var velocityAndLifetime: SIMD4<Float>
        var rotation: SIMD4<Float>
    }

    struct RopeVertex {
        var positionAndSize: SIMD4<Float>
        var endPosAndLength: SIMD4<Float>
        var cp0AndTrailPos: SIMD4<Float>
        var cp1AndSizeEnd: SIMD4<Float>
        var colorEnd: SIMD4<Float>
        var uv: SIMD4<Float>
        var colorStart: SIMD4<Float>
    }

    init?(
        device: MTLDevice,
        position: SIMD3<Float>,
        rotation: SIMD3<Float>,
        size: SIMD2<Float>,
        scale: SIMD3<Float>,
        texture: MTLTexture,
        pipeline: MTLRenderPipelineState,
        depthState: MTLDepthStencilState?,
        systemDef: ParticleSystemDef,
        instanceOverride: ParticleInstanceOverride?,
        sheetCols: Int = 0,
        sheetRows: Int = 0
    ) {
        self.device = device
        self.system = ParticleSystem(def: systemDef)
        self.particleFlags = systemDef.flags ?? 0
        self.instanceOverride = instanceOverride
        self.spritesheetCols = sheetCols
        self.spritesheetRows = sheetRows

        super.init(
            position: position,
            rotation: rotation,
            size: size,
            scale: scale,
            texture: texture,
            pipeline: pipeline,
            depthState: depthState
        )

        self.system.spritesheetFrames = sheetCols * sheetRows

        if let renderers = systemDef.renderer,
            let firstRenderer = renderers.first
        {
            if firstRenderer.name == "rope" || firstRenderer.name == "ropetrail"
            {
                self.isRope = true
                self.ropeSubdivision = max(
                    0,
                    Int(firstRenderer.subdivision ?? 4)
                )
                self.ropeUVScale = firstRenderer.uvscale ?? 1.0
                self.ropeUVScrolling = firstRenderer.uvscrolling ?? false
                self.ropeUVSmoothing = firstRenderer.uvsmoothing ?? true
                self.trailLength = firstRenderer.length ?? 0.05
                self.trailMaxLength = firstRenderer.maxlength ?? 10.0
                self.trailMinLength = firstRenderer.minlength ?? 0.0
            } else if firstRenderer.name == "spritetrail" {
                self.trailLength = firstRenderer.length ?? 0.05
                self.trailMaxLength = firstRenderer.maxlength ?? 10.0
                self.trailMinLength = firstRenderer.minlength ?? 0.0
            }
        }

        for initDef in systemDef.initializer ?? [] {
            if initDef.name == "lifetimerandom" {
                let minVal = initDef.min?.getFloat() ?? 0.0
                let maxVal = initDef.max?.getFloat() ?? 1.0
                if minVal == maxVal {
                    self.uniformLifetimes = true
                }
            }
        }

        if let cps = systemDef.controlpoint {
            for cp in cps {
                if let id = cp.id, id >= 0 && id < 8 {
                    controlPoints[id].offset = cp.offset?.getVec3() ?? .zero
                    let flags = cp.flags ?? 0
                    controlPoints[id].linkMouse = (flags & 1) != 0
                    controlPoints[id].worldSpace = (flags & 2) != 0
                    if !controlPoints[id].linkMouse {
                        controlPoints[id].position = controlPoints[id].offset
                    }
                }
            }
        }

        let maxP = system.maxParticles
        var vertexBufferSize = 0
        var indexBufferSize = 0

        if isRope {
            let subDiv = max(1, ropeSubdivision)
            let maxSubSegments = max(1, maxP - 1) * subDiv
            vertexBufferSize =
                maxSubSegments * 4 * MemoryLayout<RopeVertex>.stride
            indexBufferSize = maxSubSegments * 6 * MemoryLayout<UInt32>.stride
        } else {
            vertexBufferSize = maxP * 4 * MemoryLayout<SpriteVertex>.stride
            indexBufferSize = maxP * 6 * MemoryLayout<UInt32>.stride
        }

        for _ in 0..<maxBuffers {
            guard
                let vb = device.makeBuffer(
                    length: max(16, vertexBufferSize),
                    options: .storageModeShared
                ),
                let ib = device.makeBuffer(
                    length: max(16, indexBufferSize),
                    options: .storageModeShared
                )
            else {
                return nil
            }
            vertexBuffers.append(vb)
            indexBuffers.append(ib)
        }
    }

    func update(dt: Float, screenSize: CGSize, mousePos: CGPoint?) {
        let isOrtho = (particleFlags & 4) == 0

        if let mp = mousePos {
            for i in 0..<controlPoints.count {
                if controlPoints[i].linkMouse {
                    var pos = SIMD3<Float>.zero
                    pos.x = Float(mp.x * screenSize.width)
                    pos.y = Float(mp.y * screenSize.height)
                    pos.z = 0.0
                    pos += controlPoints[i].offset
                    controlPoints[i].position = pos
                }
            }
        }

        system.update(
            dt: dt,
            controlPoints: controlPoints,
            instanceOverride: instanceOverride,
            isOrthographic: isOrtho
        )

        if system.count > 0 {
            if isRope {
                buildRopeGeometry()
            } else {
                buildSpriteGeometry()
            }
        } else {
            activeIndexCount = 0
        }
    }

    private func buildSpriteGeometry() {
        currentBufferIndex = (currentBufferIndex + 1) % maxBuffers
        let vBuffer = vertexBuffers[currentBufferIndex]
        let iBuffer = indexBuffers[currentBufferIndex]

        let vertices = vBuffer.contents().bindMemory(
            to: SpriteVertex.self,
            capacity: system.maxParticles * 4
        )
        let indices = iBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: system.maxParticles * 6
        )

        var vertexIndex: UInt32 = 0
        var indexOffset = 0

        let animMode = system.def.animationmode ?? "sequence"

        for i in 0..<system.count {
            let p = system.particles[i]
            if !p.alive || !p.position.x.isFinite || !p.position.y.isFinite
                || !p.position.z.isFinite || !p.size.isFinite || p.size <= 0.0
            {
                continue
            }

            var lifetime = p.lifetimePos
            if spritesheetCols > 0 && spritesheetRows > 0 && p.frame >= 0.0 {
                let totalFrames = Float(spritesheetCols * spritesheetRows)
                if animMode == "randomframe" {
                    lifetime = (p.frame + 0.5) / totalFrames
                } else {
                    lifetime = p.frame / totalFrames
                }
            }

            let addVertex = { (u: Float, v: Float) in
                vertices[Int(vertexIndex)] = SpriteVertex(
                    position: SIMD4<Float>(
                        p.position.x,
                        p.position.y,
                        p.position.z,
                        1.0
                    ),
                    texCoordAndSize: SIMD4<Float>(u, v, p.rotation.z, p.size),
                    color: SIMD4<Float>(
                        p.color.x,
                        p.color.y,
                        p.color.z,
                        p.alpha
                    ),
                    velocityAndLifetime: SIMD4<Float>(
                        p.velocity.x,
                        p.velocity.y,
                        p.velocity.z,
                        lifetime
                    ),
                    rotation: SIMD4<Float>(p.rotation.x, p.rotation.y, 0, 0)
                )
                vertexIndex += 1
            }

            let baseVertex = vertexIndex
            addVertex(0.0, 1.0)
            addVertex(1.0, 1.0)
            addVertex(1.0, 0.0)
            addVertex(0.0, 0.0)

            indices[indexOffset] = baseVertex + 0
            indices[indexOffset + 1] = baseVertex + 1
            indices[indexOffset + 2] = baseVertex + 2
            indices[indexOffset + 3] = baseVertex + 2
            indices[indexOffset + 4] = baseVertex + 3
            indices[indexOffset + 5] = baseVertex + 0
            indexOffset += 6
        }
        activeIndexCount = indexOffset
    }

    private func buildRopeGeometry() {
        currentBufferIndex = (currentBufferIndex + 1) % maxBuffers
        let vBuffer = vertexBuffers[currentBufferIndex]
        let iBuffer = indexBuffers[currentBufferIndex]

        let vertices = vBuffer.contents().bindMemory(
            to: RopeVertex.self,
            capacity: system.maxParticles * 4 * max(1, ropeSubdivision)
        )
        let indices = iBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: system.maxParticles * 6 * max(1, ropeSubdivision)
        )

        if system.count < 2 {
            activeIndexCount = 0
            return
        }

        let numSegments = system.count - 1
        let subdivision = max(1, ropeSubdivision)
        let totalPoints = numSegments * subdivision + 1

        var splinePositions = Array(
            repeating: SIMD3<Float>.zero,
            count: totalPoints
        )
        var splineSizes = Array(repeating: Float(0.0), count: totalPoints)
        var splineColors = Array(
            repeating: SIMD4<Float>.zero,
            count: totalPoints
        )

        let catmullRom = {
            (
                p0: SIMD3<Float>,
                p1: SIMD3<Float>,
                p2: SIMD3<Float>,
                p3: SIMD3<Float>,
                t: Float
            ) -> SIMD3<Float> in
            let t2 = t * t
            let t3 = t2 * t

            var res = p1 * 2.0
            let term1 = p2 - p0
            res += term1 * t

            var term2 = p0 * 2.0
            term2 -= p1 * 5.0
            term2 += p2 * 4.0
            term2 -= p3
            res += term2 * t2

            var term3 = p3 - p0
            term3 += p1 * 3.0
            term3 -= p2 * 3.0
            res += term3 * t3

            return res * 0.5
        }

        for i in 0..<numSegments {
            let p1 = system.particles[i]
            let p2 = system.particles[i + 1]
            let p0 = (i > 0) ? system.particles[i - 1] : p1
            let p3 = (i + 2 < system.count) ? system.particles[i + 2] : p2

            for k in 0..<subdivision {
                let t = Float(k) / Float(subdivision)
                let idx = i * subdivision + k
                splinePositions[idx] = catmullRom(
                    p0.position,
                    p1.position,
                    p2.position,
                    p3.position,
                    t
                )

                let sizeDiff = p2.size - p1.size
                splineSizes[idx] = p1.size + sizeDiff * t

                let c1 = SIMD4<Float>(
                    p1.color.x,
                    p1.color.y,
                    p1.color.z,
                    p1.alpha
                )
                let c2 = SIMD4<Float>(
                    p2.color.x,
                    p2.color.y,
                    p2.color.z,
                    p2.alpha
                )
                let cDiff = c2 - c1
                splineColors[idx] = c1 + cDiff * t
            }
        }

        let pLast = system.particles[system.count - 1]
        splinePositions[totalPoints - 1] = pLast.position
        splineSizes[totalPoints - 1] = pLast.size
        splineColors[totalPoints - 1] = SIMD4<Float>(
            pLast.color.x,
            pLast.color.y,
            pLast.color.z,
            pLast.alpha
        )

        var vertexIndex: UInt32 = 0
        var indexOffset = 0
        let totalSubSegments = totalPoints - 1
        let uvScale = ropeUVScale > 0.0 ? ropeUVScale : 1.0
        let trailLengthVal = Float(totalSubSegments) / uvScale + 1.0
        let usableLength = trailLengthVal - 1.0

        let useSmoothing =
            ropeUVSmoothing && uniformLifetimes && !ropeUVScrolling
        var cumulativeArcLength = Array(
            repeating: Float(0.0),
            count: totalPoints
        )
        var totalArcLength: Float = 0.0

        if useSmoothing {
            for i in 1..<totalPoints {
                totalArcLength += distance(
                    splinePositions[i],
                    splinePositions[i - 1]
                )
                cumulativeArcLength[i] = totalArcLength
            }
        }

        var scrollOffset: Float = 0.0
        if ropeUVScrolling && usableLength > 0.0 {
            scrollOffset =
                fmod(Float(Date().timeIntervalSince1970), 10000.0)
                * usableLength
        }

        for s in 0..<totalSubSegments {
            let posStart = splinePositions[s]
            let posEnd = splinePositions[s + 1]
            let sizeStart = splineSizes[s]
            let sizeEnd = splineSizes[s + 1]
            let colorStart = splineColors[s]
            let colorEnd = splineColors[s + 1]

            let posPrev = (s > 0) ? splinePositions[s - 1] : posStart
            let posAfter =
                (s + 2 < totalPoints) ? splinePositions[s + 2] : posEnd

            var trailPosition: Float
            if useSmoothing && totalArcLength > 0.0 {
                trailPosition =
                    cumulativeArcLength[s] / totalArcLength
                    * Float(totalSubSegments)
            } else {
                trailPosition = Float(s)
            }
            trailPosition += scrollOffset

            let addRopeVertex = { (uvX: Float, uvY: Float) in
                vertices[Int(vertexIndex)] = RopeVertex(
                    positionAndSize: SIMD4<Float>(
                        posStart.x,
                        posStart.y,
                        posStart.z,
                        sizeStart
                    ),
                    endPosAndLength: SIMD4<Float>(
                        posEnd.x,
                        posEnd.y,
                        posEnd.z,
                        trailLengthVal
                    ),
                    cp0AndTrailPos: SIMD4<Float>(
                        posPrev.x,
                        posPrev.y,
                        posPrev.z,
                        trailPosition
                    ),
                    cp1AndSizeEnd: SIMD4<Float>(
                        posAfter.x,
                        posAfter.y,
                        posAfter.z,
                        sizeEnd
                    ),
                    colorEnd: colorEnd,
                    uv: SIMD4<Float>(uvX, uvY, 0, 0),
                    colorStart: colorStart
                )
                vertexIndex += 1
            }

            let baseVertex = vertexIndex
            addRopeVertex(0.0, 0.0)
            addRopeVertex(1.0, 0.0)
            addRopeVertex(1.0, 1.0)
            addRopeVertex(0.0, 1.0)

            indices[indexOffset] = baseVertex + 0
            indices[indexOffset + 1] = baseVertex + 1
            indices[indexOffset + 2] = baseVertex + 2
            indices[indexOffset + 3] = baseVertex + 2
            indices[indexOffset + 4] = baseVertex + 3
            indices[indexOffset + 5] = baseVertex + 0
            indexOffset += 6
        }
        activeIndexCount = indexOffset
    }

    override func draw(encoder: MTLRenderCommandEncoder) {
        if activeIndexCount == 0 { return }

        encoder.setRenderPipelineState(pipeline)
        if let ds = depthState { encoder.setDepthStencilState(ds) }

        let geometryScale = Matrix4x4.scale(x: 1.0, y: 1.0, z: 1.0)
        let finalModelMatrix = worldMatrix * geometryScale

        var renderVar0 = SIMD4<Float>(
            trailLength,
            trailMaxLength,
            trailMinLength,
            0
        )
        var textureRatio: Float = 1.0
        if texture.width > 0 {
            textureRatio = Float(texture.height) / Float(texture.width)
        }
        var renderVar1 = SIMD4<Float>(0, 0, 0, textureRatio)

        if spritesheetCols > 0 && spritesheetRows > 0 {
            let frameWidth = 1.0 / Float(spritesheetCols)
            let frameHeight = 1.0 / Float(spritesheetRows)
            let totalFrames = Float(spritesheetCols * spritesheetRows)
            if texture.width > 0 {
                textureRatio =
                    (Float(texture.height) * frameHeight)
                    / (Float(texture.width) * frameWidth)
            }
            renderVar1 = SIMD4<Float>(
                frameWidth,
                frameHeight,
                totalFrames,
                textureRatio
            )
        }

        var objUniforms = ObjectUniforms(
            modelMatrix: finalModelMatrix,
            alpha: 1.0,
            color: SIMD4<Float>(1, 1, 1, 1),
            animInfo: SIMD3<Float>(0, 0, 0),
            speed: speed,
            speedSecondary: speedSecondary,
            effectScale: effectScale,
            sunScale: sunScale
        )

        encoder.setVertexBytes(
            &objUniforms,
            length: MemoryLayout<ObjectUniforms>.stride,
            index: 2
        )
        encoder.setVertexBytes(
            &renderVar0,
            length: MemoryLayout<SIMD4<Float>>.stride,
            index: 3
        )
        encoder.setVertexBytes(
            &renderVar1,
            length: MemoryLayout<SIMD4<Float>>.stride,
            index: 4
        )

        encoder.setFragmentBytes(
            &objUniforms,
            length: MemoryLayout<ObjectUniforms>.stride,
            index: 2
        )
        encoder.setFragmentBytes(
            &renderVar1,
            length: MemoryLayout<SIMD4<Float>>.stride,
            index: 4
        )
        encoder.setFragmentTexture(texture, index: 0)

        let vBuffer = vertexBuffers[currentBufferIndex]
        let iBuffer = indexBuffers[currentBufferIndex]

        encoder.setVertexBuffer(vBuffer, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: activeIndexCount,
            indexType: .uint32,
            indexBuffer: iBuffer,
            indexBufferOffset: 0
        )
    }
}
