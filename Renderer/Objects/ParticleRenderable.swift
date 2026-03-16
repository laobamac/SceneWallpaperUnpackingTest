//
//  ParticleRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/3/17.
//

import Foundation
import MetalKit
import simd

class ParticleRenderable: RenderableObject {
    let particleDef: ParticleDef
    var particles: [ParticleInstance] = []
    var particleCount: Int = 0
    let maxParticles: Int

    var emitters: [EmitterFunc] = []
    var initializers: [InitializerFunc] = []
    var operators: [OperatorFunc] = []
    var controlPoints: [ControlPointData] = []

    var time: TimeInterval = 0.0
    var rng = SystemRandomNumberGenerator()

    let device: MTLDevice
    var vertexBuffers: [MTLBuffer] = []
    var indexBuffers: [MTLBuffer] = []
    let inFlightSemaphore = DispatchSemaphore(value: 3)
    var currentBufferIndex = 0

    var useRopeRenderer: Bool = false
    var ropeSubdivision: Int = 0
    var ropeUVScale: Float = 1.0
    var ropeUVScrolling: Bool = false
    var ropeUVSmoothing: Bool = false
    var useTrailRenderer: Bool = false
    var trailLength: Float = 0.05
    var trailMaxLength: Float = 10.0
    var trailMinLength: Float = 0.0
    var uniformLifetimes: Bool = false

    var transformedOrigin: simd_float3 = .zero
    var lastScreenWidth: Float = 0.0
    var lastScreenHeight: Float = 0.0
    var overbright: Float = 1.0
    var activeIndexCount: Int = 0

    var spritesheetCols: Int = 0
    var spritesheetRows: Int = 0
    var spritesheetFrames: Int = 0
    var spritesheetDuration: Float = 1.0

    init?(
        device: MTLDevice,
        particleDef: ParticleDef,
        texture: MTLTexture,
        frameInfo: [TexFrameInfo]?,
        pipeline: MTLRenderPipelineState,
        depthState: MTLDepthStencilState?
    ) {
        self.device = device
        self.particleDef = particleDef

        let countMultiplier = particleDef.instanceOverride?.count?.value?.floatValue ?? 1.0
        let baseMaxCount = particleDef.maxCount ?? 1000
        self.maxParticles = max(1, Int(Float(baseMaxCount) * countMultiplier))
        self.particles = Array(repeating: ParticleInstance(), count: maxParticles)

        super.init(
            position: .zero,
            rotation: .zero,
            size: .zero,
            scale: simd_float3(1, 1, 1),
            texture: texture,
            frameInfo: frameInfo,
            pipeline: pipeline,
            depthState: depthState
        )

        if let renderers = particleDef.renderers, !renderers.isEmpty {
            let renderer = renderers[0]
            if renderer.name == "rope" || renderer.name == "ropetrail" {
                self.useRopeRenderer = true
                self.ropeSubdivision = max(0, renderer.subdivision ?? 0)
                self.ropeUVScale = renderer.uvScale ?? 1.0
                self.ropeUVScrolling = renderer.uvScrolling ?? false
                self.ropeUVSmoothing = renderer.uvSmoothing ?? false

                if renderer.name == "ropetrail" {
                    self.useTrailRenderer = true
                    self.trailLength = renderer.length ?? 0.05
                }
            } else if renderer.name == "spritetrail" {
                self.useTrailRenderer = true
                self.trailLength = renderer.length ?? 0.05
                self.trailMaxLength = renderer.maxLength ?? 10.0
                self.trailMinLength = renderer.minLength ?? 0.0
            }
        }

        setupBuffers()
        setupControlPoints()
        setupInitializers()
        setupEmitters()
        setupOperators()
    }

    private func setupBuffers() {
        var maxVertices = 0
        var maxIndices = 0

        if useRopeRenderer {
            let subdivision = max(1, ropeSubdivision)
            let maxSubSegments = max(1, maxParticles - 1) * subdivision
            maxVertices = maxSubSegments * 4
            maxIndices = maxSubSegments * 6
        } else {
            maxVertices = maxParticles * 4
            maxIndices = maxParticles * 6
        }

        let vertexStride = useRopeRenderer ? 104 : 68
        let vertexBufferSize = maxVertices * vertexStride
        let indexBufferSize = maxIndices * MemoryLayout<UInt32>.size

        for _ in 0..<3 {
            if let vBuf = device.makeBuffer(length: max(256, vertexBufferSize), options: .storageModeShared),
               let iBuf = device.makeBuffer(length: max(256, indexBufferSize), options: .storageModeShared) {
                vertexBuffers.append(vBuf)
                indexBuffers.append(iBuf)
            }
        }
    }

    private func setupControlPoints() {
        controlPoints = Array(repeating: ControlPointData(), count: 8)
        if let cps = particleDef.controlPoints {
            for cp in cps {
                if cp.id >= 0 && cp.id < 8 {
                    controlPoints[cp.id].offset = cp.offset
                    controlPoints[cp.id].linkMouse = (cp.flags & 1) != 0
                    controlPoints[cp.id].worldSpace = (cp.flags & 2) != 0

                    if !controlPoints[cp.id].linkMouse {
                        if controlPoints[cp.id].worldSpace {
                            controlPoints[cp.id].position = cp.offset - transformedOrigin
                        } else {
                            controlPoints[cp.id].position = cp.offset
                        }
                    }
                }
            }
        }
    }

    func update(dt: Float) {
        self.time += TimeInterval(dt)
        var cappedDt = dt
        if cappedDt > 0.1 { cappedDt = 0.1 }

        for i in 0..<controlPoints.count {
            if !controlPoints[i].linkMouse && controlPoints[i].worldSpace {
                controlPoints[i].position = controlPoints[i].offset - transformedOrigin
            }
        }

        for emitter in emitters {
            emitter(&particles, &particleCount, cappedDt)
        }

        for i in 0..<particleCount {
            particles[i].age += cappedDt
        }

        for op in operators {
            op(&particles, particleCount, controlPoints, Float(time), cappedDt)
        }

        for i in 0..<particleCount {
            if spritesheetFrames > 0 {
                let p = particles[i]
                let lifetimePos = p.getLifetimePos()
                let animSpeed = particleDef.sequenceMultiplier ?? 1.0

                if particleDef.animationMode == "randomframe" {
                    if p.frame < 0.0 {
                        particles[i].frame = Float.random(in: 0...Float(spritesheetFrames - 1), using: &rng)
                    }
                } else if particleDef.animationMode == "once" {
                    particles[i].frame = min(lifetimePos * Float(spritesheetFrames) * animSpeed, Float(spritesheetFrames - 1))
                } else {
                    if spritesheetDuration > 0.0 {
                        let timeInCycle = fmod(p.age * animSpeed, spritesheetDuration)
                        let cyclePos = timeInCycle / spritesheetDuration
                        particles[i].frame = fmod(cyclePos * Float(spritesheetFrames), Float(spritesheetFrames))
                    } else {
                        particles[i].frame = fmod(lifetimePos * Float(spritesheetFrames) * animSpeed, Float(spritesheetFrames))
                    }
                }
            }
        }

        var writeIdx = 0
        for readIdx in 0..<particleCount {
            if particles[readIdx].isAlive() {
                if writeIdx != readIdx {
                    particles[writeIdx] = particles[readIdx]
                }
                writeIdx += 1
            }
        }
        particleCount = writeIdx

        buildGeometry()
    }

    override func draw(encoder: MTLRenderCommandEncoder) {
        if activeIndexCount == 0 {
            inFlightSemaphore.signal()
            return
        }

        encoder.setRenderPipelineState(pipeline)
        if let depthState = depthState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setFragmentTexture(texture, index: 0)

        encoder.setVertexBuffer(vertexBuffers[currentBufferIndex], offset: 0, index: 0)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: activeIndexCount,
            indexType: .uint32,
            indexBuffer: indexBuffers[currentBufferIndex],
            indexBufferOffset: 0
        )

        inFlightSemaphore.signal()
    }
}
