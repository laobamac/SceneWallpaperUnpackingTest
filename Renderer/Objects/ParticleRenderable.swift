//
//  ParticleRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/3/17.
//

import Foundation
import MetalKit
import simd

struct ParticleInstance {
    var position: simd_float3 = .zero
    var velocity: simd_float3 = .zero
    var acceleration: simd_float3 = .zero
    var rotation: simd_float3 = .zero
    var angularVelocity: simd_float3 = .zero
    var angularAcceleration: simd_float3 = .zero
    var color: simd_float3 = simd_float3(1.0, 1.0, 1.0)
    var alpha: Float = 1.0
    var size: Float = 20.0
    var frame: Float = 0.0
    var lifetime: Float = 1.0
    var age: Float = 0.0

    struct Oscillator {
        var frequency: Float = 0.0
        var scale: Float = 1.0
        var phase: Float = 0.0
        var base: Float = 1.0
        var initialized: Bool = false
    }
    var oscillateAlpha = Oscillator()
    var oscillateSize = Oscillator()

    struct PositionOscillator {
        var frequency: simd_float3 = .zero
        var scale: simd_float3 = simd_float3(1.0, 1.0, 1.0)
        var phase: simd_float3 = .zero
        var initialized: Bool = false
    }
    var oscillatePosition = PositionOscillator()

    struct InitialState {
        var color: simd_float3 = simd_float3(1.0, 1.0, 1.0)
        var alpha: Float = 1.0
        var size: Float = 20.0
        var lifetime: Float = 1.0
    }
    var initial = InitialState()

    var alive: Bool = false

    func getLifetimePos() -> Float {
        return lifetime > 0.0 ? (age / lifetime) : 1.0
    }

    func isAlive() -> Bool {
        return alive && age < lifetime
    }
}

struct ControlPointData {
    var position: simd_float3 = .zero
    var offset: simd_float3 = .zero
    var linkMouse: Bool = false
    var worldSpace: Bool = false
}

typealias EmitterFunc = (inout [ParticleInstance], inout Int, Float) -> Void
typealias InitializerFunc = (inout ParticleInstance) -> Void
typealias OperatorFunc = (
    inout [ParticleInstance], Int, [ControlPointData], Float, Float
) -> Void

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

        let countMultiplier =
            particleDef.instanceOverride?.count?.value?.floatValue ?? 1.0
        let baseMaxCount = particleDef.maxCount ?? 1000
        self.maxParticles = max(1, Int(Float(baseMaxCount) * countMultiplier))
        self.particles = Array(
            repeating: ParticleInstance(),
            count: maxParticles
        )

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
        setupEmitters()
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
            if let vBuf = device.makeBuffer(
                length: max(256, vertexBufferSize),
                options: .storageModeShared
            ),
                let iBuf = device.makeBuffer(
                    length: max(256, indexBufferSize),
                    options: .storageModeShared
                )
            {
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
                            controlPoints[cp.id].position =
                                cp.offset - transformedOrigin
                        } else {
                            controlPoints[cp.id].position = cp.offset
                        }
                    }
                }
            }
        }
    }

    private func setupEmitters() {
        if let ems = particleDef.emitters {
            for emitter in ems {
                if emitter.name == "boxrandom" {
                    emitters.append(createBoxEmitter(emitter: emitter))
                } else if emitter.name == "sphererandom" {
                    emitters.append(createSphereEmitter(emitter: emitter))
                }
            }
        }
    }

    private func createBoxEmitter(emitter: ParticleEmitter) -> EmitterFunc {
        let rate =
            emitter.rate
            * (particleDef.instanceOverride?.rate?.value?.floatValue ?? 1.0)
        var transformedEmitterOrigin = emitter.origin
        transformedEmitterOrigin.y = -transformedEmitterOrigin.y

        var controlPointIndex = emitter.controlPoint
        if controlPointIndex == -1, let cps = particleDef.controlPoints,
            !cps.isEmpty
        {
            if (cps[0].flags & 1) != 0 {
                controlPointIndex = 0
            }
        }

        var flippedDirections = emitter.directions
        flippedDirections.y = -flippedDirections.y

        let limitOnePerFrame = (emitter.flags & 2) != 0
        let randomPeriodicEmission = (emitter.flags & 4) != 0

        var emissionTimer: Float = 0.0
        var elapsedTime: Float = 0.0
        var delayTimer: Float = emitter.delay
        var durationTimer: Float = 0.0
        var periodicTimer: Float = 0.0
        var periodicDuration: Float = 0.0
        var periodicDelay: Float = 0.0
        var emitting: Bool = false
        var instantaneousEmitted: Bool = false

        return { [weak self] particles, count, dt in
            guard let self = self else { return }
            if count >= particles.count { return }

            elapsedTime += dt

            if delayTimer > 0.0 {
                delayTimer -= dt
                return
            }

            if emitter.duration > 0.0 {
                durationTimer += dt
                if durationTimer >= emitter.duration {
                    return
                }
            }

            if randomPeriodicEmission {
                periodicTimer += dt
                if !emitting {
                    if periodicTimer >= periodicDelay {
                        emitting = true
                        periodicTimer = 0.0
                        periodicDuration = Float.random(
                            in: emitter
                                .minPeriodicDuration...emitter
                                .maxPeriodicDuration,
                            using: &self.rng
                        )
                    } else {
                        return
                    }
                } else {
                    if periodicTimer >= periodicDuration {
                        emitting = false
                        periodicTimer = 0.0
                        periodicDelay = Float.random(
                            in: emitter
                                .minPeriodicDelay...emitter.maxPeriodicDelay,
                            using: &self.rng
                        )
                        return
                    }
                }
            }

            var toEmit: Int = 0
            if emitter.instantaneous > 0 && !instantaneousEmitted {
                toEmit = emitter.instantaneous
                instantaneousEmitted = true
            }

            if emitter.rate > 0.0 {
                emissionTimer += dt * rate
                var rateEmit = Int(emissionTimer)
                emissionTimer -= Float(rateEmit)
                if limitOnePerFrame && rateEmit > 1 {
                    rateEmit = 1
                }
                toEmit += rateEmit
            }

            for _ in 0..<toEmit {
                if count >= particles.count { break }

                var spawnOrigin = transformedEmitterOrigin
                if controlPointIndex >= 0
                    && controlPointIndex < self.controlPoints.count
                {
                    spawnOrigin +=
                        self.controlPoints[controlPointIndex].position
                }

                var randomPos = simd_float3(0, 0, 0)
                let dMin = [
                    emitter.distanceMin.x, emitter.distanceMin.y,
                    emitter.distanceMin.z,
                ]
                let dMax = [
                    emitter.distanceMax.x, emitter.distanceMax.y,
                    emitter.distanceMax.z,
                ]

                for axis in 0..<3 {
                    let minDist = dMin[axis]
                    let maxDist = dMax[axis]
                    var dist = Float.random(
                        in: minDist...maxDist,
                        using: &self.rng
                    )
                    if Float.random(in: 0...1, using: &self.rng) < 0.5 {
                        dist = -dist
                    }
                    randomPos[axis] = dist
                }
                randomPos *= flippedDirections

                particles[count].position = spawnOrigin + randomPos
                particles[count].velocity = .zero
                particles[count].acceleration = .zero
                particles[count].rotation = .zero
                particles[count].angularVelocity = .zero
                particles[count].angularAcceleration = .zero

                particles[count].color =
                    simd_float3(1, 1, 1)
                    * (self.particleDef.instanceOverride?.colorn?.value?
                        .vec3Value ?? simd_float3(1, 1, 1))
                particles[count].alpha =
                    1.0
                    * (self.particleDef.instanceOverride?.alpha?.value?
                        .floatValue ?? 1.0)
                particles[count].size =
                    20.0
                    * (self.particleDef.instanceOverride?.size?.value?
                        .floatValue ?? 1.0)
                particles[count].lifetime =
                    1.0
                    * (self.particleDef.instanceOverride?.lifetime?.value?
                        .floatValue ?? 1.0)
                particles[count].age = 0.0
                particles[count].alive = true
                particles[count].frame = -1.0

                particles[count].initial.color = particles[count].color
                particles[count].initial.alpha = particles[count].alpha
                particles[count].initial.size = particles[count].size
                particles[count].initial.lifetime = particles[count].lifetime

                particles[count].oscillateAlpha = ParticleInstance.Oscillator()
                particles[count].oscillateSize = ParticleInstance.Oscillator()
                particles[count].oscillatePosition =
                    ParticleInstance.PositionOscillator()

                for initFunc in self.initializers {
                    initFunc(&particles[count])
                }

                count += 1
            }
        }
    }

    private func createSphereEmitter(emitter: ParticleEmitter) -> EmitterFunc {
        let rate =
            emitter.rate
            * (particleDef.instanceOverride?.rate?.value?.floatValue ?? 1.0)
        let lifetime =
            1.0
            * (particleDef.instanceOverride?.lifetime?.value?.floatValue ?? 1.0)
        var transformedEmitterOrigin = emitter.origin
        transformedEmitterOrigin.y = -transformedEmitterOrigin.y

        var controlPointIndex = emitter.controlPoint
        if controlPointIndex == -1, let cps = particleDef.controlPoints,
            !cps.isEmpty
        {
            if (cps[0].flags & 1) != 0 {
                controlPointIndex = 0
            }
        }

        let limitOnePerFrame = (emitter.flags & 2) != 0
        var emissionTimer: Float = 0.0
        var remaining = emitter.instantaneous

        return { [weak self] particles, count, dt in
            guard let self = self else { return }
            if count >= particles.count { return }

            emissionTimer += dt * rate
            var toEmit = Int(emissionTimer)
            emissionTimer -= Float(toEmit)

            if limitOnePerFrame && toEmit > 1 {
                toEmit = 1
            }

            if remaining > 0 {
                toEmit = remaining
                remaining = 0
            }

            for _ in 0..<toEmit {
                if count >= particles.count { break }

                var spawnOrigin = transformedEmitterOrigin
                if controlPointIndex >= 0
                    && controlPointIndex < self.controlPoints.count
                {
                    spawnOrigin +=
                        self.controlPoints[controlPointIndex].position
                }

                var randomPos = simd_float3(0, 0, 0)

                if (self.particleDef.flags ?? 0) & 4 == 0 {
                    let angle = Float.random(
                        in: 0...(2 * .pi),
                        using: &self.rng
                    )
                    let minRadius = emitter.distanceMin.x
                    let maxRadius = emitter.distanceMax.x
                    let minRadiusSq = minRadius * minRadius
                    let maxRadiusSq = maxRadius * maxRadius
                    let radiusXY = sqrt(
                        Float.random(
                            in: minRadiusSq...maxRadiusSq,
                            using: &self.rng
                        )
                    )

                    randomPos = simd_float3(
                        radiusXY * cos(angle),
                        radiusXY * sin(angle),
                        Float.random(
                            in: -maxRadius...maxRadius,
                            using: &self.rng
                        )
                    )
                    randomPos *= emitter.directions
                } else {
                    let theta = Float.random(
                        in: 0...(2 * .pi),
                        using: &self.rng
                    )
                    let cosTheta = Float.random(in: -1...1, using: &self.rng)
                    let sinTheta = sqrt(1.0 - cosTheta * cosTheta)

                    randomPos = simd_float3(
                        sinTheta * cos(theta),
                        sinTheta * sin(theta),
                        cosTheta
                    )

                    let minRadius = emitter.distanceMin.x
                    let maxRadius = emitter.distanceMax.x
                    let minRadiusCubed = minRadius * minRadius * minRadius
                    let maxRadiusCubed = maxRadius * maxRadius * maxRadius
                    let radius = cbrt(
                        Float.random(
                            in: minRadiusCubed...maxRadiusCubed,
                            using: &self.rng
                        )
                    )

                    randomPos *= radius
                    randomPos *= emitter.directions
                }

                for i in 0..<3 {
                    if emitter.sign.count > i {
                        if emitter.sign[i] == 1 {
                            randomPos[i] = abs(randomPos[i])
                        } else if emitter.sign[i] == -1 {
                            randomPos[i] = -abs(randomPos[i])
                        }
                    }
                }

                particles[count].position = spawnOrigin + randomPos

                if emitter.speedMax > 0.0 || emitter.speedMin != 0.0 {
                    let direction =
                        length(randomPos) > 0.0
                        ? normalize(randomPos) : simd_float3(0, 1, 0)
                    let speed = Float.random(
                        in: emitter.speedMin...emitter.speedMax,
                        using: &self.rng
                    )
                    particles[count].velocity = direction * speed
                } else {
                    particles[count].velocity = .zero
                }

                particles[count].acceleration = .zero
                particles[count].rotation = .zero
                particles[count].angularVelocity = .zero
                particles[count].angularAcceleration = .zero

                particles[count].color =
                    simd_float3(1, 1, 1)
                    * (self.particleDef.instanceOverride?.colorn?.value?
                        .vec3Value ?? simd_float3(1, 1, 1))
                particles[count].alpha =
                    1.0
                    * (self.particleDef.instanceOverride?.alpha?.value?
                        .floatValue ?? 1.0)
                particles[count].size =
                    20.0
                    * (self.particleDef.instanceOverride?.size?.value?
                        .floatValue ?? 1.0)
                particles[count].lifetime = lifetime
                particles[count].age = 0.0
                particles[count].alive = true
                particles[count].frame = -1.0

                particles[count].initial.color = particles[count].color
                particles[count].initial.alpha = particles[count].alpha
                particles[count].initial.size = particles[count].size
                particles[count].initial.lifetime = particles[count].lifetime

                particles[count].oscillateAlpha = ParticleInstance.Oscillator()
                particles[count].oscillateSize = ParticleInstance.Oscillator()
                particles[count].oscillatePosition =
                    ParticleInstance.PositionOscillator()

                for initFunc in self.initializers {
                    initFunc(&particles[count])
                }

                count += 1
            }
        }
    }
    private func setupInitializers() {
        if let inits = particleDef.initializers {
            for initializer in inits {
                switch initializer {
                case .colorRandom(let minVal, let maxVal):
                    initializers.append(
                        createColorRandomInitializer(
                            min: minVal.value,
                            max: maxVal.value
                        )
                    )
                case .sizeRandom(let minVal, let maxVal, let exponent):
                    initializers.append(
                        createSizeRandomInitializer(
                            min: minVal.value,
                            max: maxVal.value,
                            exponent: exponent.value
                        )
                    )
                case .alphaRandom(let minVal, let maxVal):
                    initializers.append(
                        createAlphaRandomInitializer(
                            min: minVal.value,
                            max: maxVal.value
                        )
                    )
                case .lifetimeRandom(let minVal, let maxVal):
                    let minL = minVal.value?.floatValue ?? 1.0
                    let maxL = maxVal.value?.floatValue ?? 1.0
                    self.uniformLifetimes = (minL == maxL)
                    initializers.append(
                        createLifetimeRandomInitializer(
                            min: minVal.value,
                            max: maxVal.value
                        )
                    )
                case .velocityRandom(let minVal, let maxVal):
                    initializers.append(
                        createVelocityRandomInitializer(
                            min: minVal.value,
                            max: maxVal.value
                        )
                    )
                case .rotationRandom(let minVal, let maxVal):
                    initializers.append(
                        createRotationRandomInitializer(
                            min: minVal.value,
                            max: maxVal.value
                        )
                    )
                case .angularVelocityRandom(
                    let minVal,
                    let maxVal,
                    let exponent
                ):
                    initializers.append(
                        createAngularVelocityRandomInitializer(
                            min: minVal.value,
                            max: maxVal.value,
                            exponent: exponent.value
                        )
                    )
                case .turbulentVelocityRandom(
                    let speedMin,
                    let speedMax,
                    let offset,
                    let scale,
                    let forward,
                    let timeScale,
                    let phaseMin,
                    let phaseMax,
                    let right
                ):
                    initializers.append(
                        createTurbulentVelocityRandomInitializer(
                            speedMin: speedMin.value,
                            speedMax: speedMax.value,
                            offset: offset.value,
                            scale: scale.value,
                            forward: forward.value,
                            timeScale: timeScale.value,
                            phaseMin: phaseMin.value,
                            phaseMax: phaseMax.value,
                            right: right.value
                        )
                    )
                case .mapSequenceAroundControlPoint(
                    let controlPoint,
                    let count,
                    let speedMin,
                    let speedMax
                ):
                    initializers.append(
                        createMapSequenceAroundControlPointInitializer(
                            controlPoint: controlPoint.value,
                            count: count.value,
                            speedMin: speedMin.value,
                            speedMax: speedMax.value
                        )
                    )
                case .unknown:
                    break
                }
            }
        }
    }

    private func createColorRandomInitializer(
        min: DynamicValue?,
        max: DynamicValue?
    ) -> InitializerFunc {
        let minVec = min?.vec3Value ?? simd_float3(1, 1, 1)
        let maxVec = max?.vec3Value ?? simd_float3(1, 1, 1)
        return { [weak self] p in
            guard let self = self else { return }
            let colorOverride =
                self.particleDef.instanceOverride?.colorn?.value?.vec3Value
                ?? simd_float3(1, 1, 1)
            p.color =
                simd_float3(
                    Float.random(in: minVec.x...maxVec.x, using: &self.rng),
                    Float.random(in: minVec.y...maxVec.y, using: &self.rng),
                    Float.random(in: minVec.z...maxVec.z, using: &self.rng)
                ) * colorOverride
            p.initial.color = p.color
        }
    }

    private func createSizeRandomInitializer(
        min: DynamicValue?,
        max: DynamicValue?,
        exponent: DynamicValue?
    ) -> InitializerFunc {
        let minF = min?.floatValue ?? 1.0
        let maxF = max?.floatValue ?? 1.0
        let expF = exponent?.floatValue ?? 1.0
        return { [weak self] p in
            guard let self = self else { return }
            let t = Float.random(in: 0...1, using: &self.rng)
            let adjustedT = pow(t, expF)
            let sizeOverride =
                self.particleDef.instanceOverride?.size?.value?.floatValue
                ?? 1.0
            p.size = (minF + adjustedT * (maxF - minF)) * sizeOverride / 2.0
            p.initial.size = p.size
        }
    }

    private func createAlphaRandomInitializer(
        min: DynamicValue?,
        max: DynamicValue?
    ) -> InitializerFunc {
        let minF = min?.floatValue ?? 1.0
        let maxF = max?.floatValue ?? 1.0
        return { [weak self] p in
            guard let self = self else { return }
            let alphaOverride =
                self.particleDef.instanceOverride?.alpha?.value?.floatValue
                ?? 1.0
            p.alpha =
                Float.random(in: minF...maxF, using: &self.rng) * alphaOverride
            p.initial.alpha = p.alpha
        }
    }

    private func createLifetimeRandomInitializer(
        min: DynamicValue?,
        max: DynamicValue?
    ) -> InitializerFunc {
        let minF = min?.floatValue ?? 1.0
        let maxF = max?.floatValue ?? 1.0
        return { [weak self] p in
            guard let self = self else { return }
            let lifetimeOverride =
                self.particleDef.instanceOverride?.lifetime?.value?.floatValue
                ?? 1.0
            p.lifetime =
                Float.random(in: minF...maxF, using: &self.rng)
                * lifetimeOverride
            p.initial.lifetime = p.lifetime
        }
    }

    private func createVelocityRandomInitializer(
        min: DynamicValue?,
        max: DynamicValue?
    ) -> InitializerFunc {
        let minVec = min?.vec3Value ?? simd_float3(0, 0, 0)
        let maxVec = max?.vec3Value ?? simd_float3(0, 0, 0)
        return { [weak self] p in
            guard let self = self else { return }
            let speedOverride =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            var vel =
                simd_float3(
                    Float.random(in: minVec.x...maxVec.x, using: &self.rng),
                    Float.random(in: minVec.y...maxVec.y, using: &self.rng),
                    Float.random(in: minVec.z...maxVec.z, using: &self.rng)
                ) * speedOverride
            vel.y = -vel.y
            p.velocity += vel
        }
    }

    private func createRotationRandomInitializer(
        min: DynamicValue?,
        max: DynamicValue?
    ) -> InitializerFunc {
        let minVec = min?.vec3Value ?? simd_float3(0, 0, 0)
        let maxVec = max?.vec3Value ?? simd_float3(0, 0, 0)
        return { [weak self] p in
            guard let self = self else { return }
            let speedOverride =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            p.rotation =
                simd_float3(
                    Float.random(in: minVec.x...maxVec.x, using: &self.rng),
                    Float.random(in: minVec.y...maxVec.y, using: &self.rng),
                    Float.random(in: minVec.z...maxVec.z, using: &self.rng)
                ) * speedOverride
        }
    }

    private func createAngularVelocityRandomInitializer(
        min: DynamicValue?,
        max: DynamicValue?,
        exponent: DynamicValue?
    ) -> InitializerFunc {
        let minVec = min?.vec3Value ?? simd_float3(0, 0, 0)
        let maxVec = max?.vec3Value ?? simd_float3(0, 0, 0)
        let expF = exponent?.floatValue ?? 1.0
        return { [weak self] p in
            guard let self = self else { return }
            let speedOverride =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            var result = simd_float3(0, 0, 0)
            for i in 0..<3 {
                var t = Float.random(in: 0...1, using: &self.rng)
                t = pow(t, expF)
                result[i] = minVec[i] + t * (maxVec[i] - minVec[i])
            }
            p.angularVelocity = result * speedOverride
        }
    }

    private func createTurbulentVelocityRandomInitializer(
        speedMin: DynamicValue?,
        speedMax: DynamicValue?,
        offset: DynamicValue?,
        scale: DynamicValue?,
        forward: DynamicValue?,
        timeScale: DynamicValue?,
        phaseMin: DynamicValue?,
        phaseMax: DynamicValue?,
        right: DynamicValue?
    ) -> InitializerFunc {
        var forwardVec = forward?.vec3Value ?? simd_float3(0, 1, 0)
        var rightVec = right?.vec3Value ?? simd_float3(1, 0, 0)
        forwardVec.y = -forwardVec.y
        rightVec.y = -rightVec.y

        if length(forwardVec) > 0.0001 {
            forwardVec = normalize(forwardVec)
        } else {
            forwardVec = simd_float3(0, 1, 0)
        }

        if length(rightVec) > 0.0001 {
            rightVec = normalize(rightVec)
        } else {
            rightVec = simd_float3(1, 0, 0)
        }

        let sMin = speedMin?.floatValue ?? 0.0
        let sMax = speedMax?.floatValue ?? 0.0
        let sc = scale?.floatValue ?? 1.0
        let off = offset?.floatValue ?? 0.0
        let ts = timeScale?.floatValue ?? 1.0
        let pMin = phaseMin?.floatValue ?? 0.0
        let pMax = phaseMax?.floatValue ?? 0.0
        let is2D = (self.particleDef.flags ?? 0) & 4 == 0

        return { [weak self] p in
            guard let self = self else { return }
            let speedOverride =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            let speed = Float.random(in: sMin...sMax, using: &self.rng)

            var noisePos = p.position * 0.1
            noisePos += simd_float3(
                Float(self.time) * ts,
                Float(self.time) * ts,
                Float(self.time) * ts
            )

            let phase = Float.random(in: pMin...pMax, using: &self.rng)
            let samplePos =
                noisePos + simd_float3(phase, phase * 0.7, phase * 1.3)

            var result = NoiseUtils.curlNoise(samplePos)
            let len = length(result)
            if len < 0.0001 {
                result = forwardVec
            } else {
                result = result / len
            }

            if sc < 2.0 {
                let cosAngle = dot(result, forwardVec)
                let angle = acos(simd_clamp(cosAngle, -1.0, 1.0)) / .pi
                let maxAngle = sc / 2.0

                if angle > maxAngle && maxAngle > 0.0001 {
                    var axis = cross(result, forwardVec)
                    let axisLen = length(axis)
                    if axisLen > 0.0001 {
                        axis = axis / axisLen
                        let rotAngle = (angle - maxAngle) * .pi
                        let q = simd_quatf(angle: rotAngle, axis: axis)
                        result = q.act(result)
                    }
                }
            }

            if abs(off) > 0.0001 {
                let q = simd_quatf(angle: -off, axis: rightVec)
                result = q.act(result)
            }

            if is2D {
                result.z = 0.0
                let len2d = length(result)
                if len2d > 0.0001 {
                    result /= len2d
                }
            }

            p.velocity += result * speed * speedOverride
        }
    }

    private func createMapSequenceAroundControlPointInitializer(
        controlPoint: DynamicValue?,
        count: DynamicValue?,
        speedMin: DynamicValue?,
        speedMax: DynamicValue?
    ) -> InitializerFunc {
        let cpIdx = Int(controlPoint?.floatValue ?? 0)
        let totalCount = Int(count?.floatValue ?? 1)
        let sMin = speedMin?.vec3Value ?? .zero
        let sMax = speedMax?.vec3Value ?? .zero
        var sequenceIndex = 0

        return { [weak self] p in
            guard let self = self else { return }
            let angle = (Float(sequenceIndex) / Float(totalCount)) * 2.0 * .pi
            sequenceIndex = (sequenceIndex + 1) % max(1, totalCount)

            var centerPos: simd_float3 = .zero
            if cpIdx >= 0 && cpIdx < self.controlPoints.count {
                centerPos = self.controlPoints[cpIdx].position
            }

            p.position = centerPos

            var speed = simd_float3(
                Float.random(in: sMin.x...sMax.x, using: &self.rng),
                Float.random(in: sMin.y...sMax.y, using: &self.rng),
                Float.random(in: sMin.z...sMax.z, using: &self.rng)
            )
            speed.y = -speed.y

            let rotMat = simd_float3x3(
                simd_float3(cos(angle), sin(angle), 0),
                simd_float3(-sin(angle), cos(angle), 0),
                simd_float3(0, 0, 1)
            )

            let speedOverride =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            p.velocity = (rotMat * speed) * speedOverride
        }
    }

    private func setupOperators() {
        if let ops = particleDef.operators {
            for op in ops {
                switch op {
                case .movement(let drag, let gravity):
                    operators.append(
                        createMovementOperator(
                            drag: drag.value,
                            gravity: gravity.value
                        )
                    )
                case .angularMovement(let drag, let force):
                    operators.append(
                        createAngularMovementOperator(
                            drag: drag.value,
                            force: force.value
                        )
                    )
                case .alphaFade(let fadeIn, let fadeOut):
                    operators.append(
                        createAlphaFadeOperator(
                            fadeInTime: fadeIn.value,
                            fadeOutTime: fadeOut.value
                        )
                    )
                case .sizeChange(let st, let et, let sv, let ev):
                    operators.append(
                        createSizeChangeOperator(
                            startTime: st.value,
                            endTime: et.value,
                            startValue: sv.value,
                            endValue: ev.value
                        )
                    )
                case .alphaChange(let st, let et, let sv, let ev):
                    operators.append(
                        createAlphaChangeOperator(
                            startTime: st.value,
                            endTime: et.value,
                            startValue: sv.value,
                            endValue: ev.value
                        )
                    )
                case .colorChange(let st, let et, let sv, let ev):
                    operators.append(
                        createColorChangeOperator(
                            startTime: st.value,
                            endTime: et.value,
                            startValue: sv.value,
                            endValue: ev.value
                        )
                    )
                case .turbulence(
                    let scale,
                    let speedMin,
                    let speedMax,
                    let timeScale,
                    let mask,
                    let phaseMin,
                    let phaseMax
                ):
                    operators.append(
                        createTurbulenceOperator(
                            scale: scale.value,
                            speedMin: speedMin.value,
                            speedMax: speedMax.value,
                            timeScale: timeScale.value,
                            mask: mask.value,
                            phaseMin: phaseMin.value,
                            phaseMax: phaseMax.value
                        )
                    )
                case .vortex(
                    let cp,
                    let flags,
                    let axis,
                    let offset,
                    let dInner,
                    let dOuter,
                    let sInner,
                    let sOuter,
                    let cForce,
                    let rRadius,
                    let rWidth,
                    let rpDist,
                    let rpForce,
                    let audio
                ):
                    operators.append(
                        createVortexOperator(
                            controlPoint: cp,
                            flags: flags,
                            axis: axis.value,
                            offset: offset.value,
                            distanceInner: dInner.value,
                            distanceOuter: dOuter.value,
                            speedInner: sInner.value,
                            speedOuter: sOuter.value,
                            centerForce: cForce.value,
                            ringRadius: rRadius.value,
                            ringWidth: rWidth.value,
                            ringPullDistance: rpDist.value,
                            ringPullForce: rpForce.value,
                            audioProcessingMode: audio.value
                        )
                    )
                case .controlPointAttract(
                    let cp,
                    let origin,
                    let scale,
                    let threshold
                ):
                    operators.append(
                        createControlPointAttractOperator(
                            controlPoint: cp,
                            origin: origin.value,
                            scale: scale.value,
                            threshold: threshold.value
                        )
                    )
                case .oscillateAlpha(
                    let fMin,
                    let fMax,
                    let sMin,
                    let sMax,
                    let pMin,
                    let pMax
                ):
                    operators.append(
                        createOscillateAlphaOperator(
                            frequencyMin: fMin.value,
                            frequencyMax: fMax.value,
                            scaleMin: sMin.value,
                            scaleMax: sMax.value,
                            phaseMin: pMin.value,
                            phaseMax: pMax.value
                        )
                    )
                case .oscillateSize(
                    let fMin,
                    let fMax,
                    let sMin,
                    let sMax,
                    let pMin,
                    let pMax
                ):
                    operators.append(
                        createOscillateSizeOperator(
                            frequencyMin: fMin.value,
                            frequencyMax: fMax.value,
                            scaleMin: sMin.value,
                            scaleMax: sMax.value,
                            phaseMin: pMin.value,
                            phaseMax: pMax.value
                        )
                    )
                case .oscillatePosition(
                    let fMin,
                    let fMax,
                    let sMin,
                    let sMax,
                    let pMin,
                    let pMax,
                    let mask
                ):
                    operators.append(
                        createOscillatePositionOperator(
                            frequencyMin: fMin.value,
                            frequencyMax: fMax.value,
                            scaleMin: sMin.value,
                            scaleMax: sMax.value,
                            phaseMin: pMin.value,
                            phaseMax: pMax.value,
                            mask: mask.value
                        )
                    )
                case .unknown:
                    break
                }
            }
        }
    }

    private func createMovementOperator(
        drag: DynamicValue?,
        gravity: DynamicValue?
    ) -> OperatorFunc {
        let d = drag?.floatValue ?? 0.0
        var g = gravity?.vec3Value ?? .zero
        g.y = -g.y
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let speed =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            for i in 0..<count {
                if !particles[i].alive { continue }
                particles[i].position += particles[i].velocity * dt
                particles[i].velocity += g * dt * speed
                var dragFactor = 1.0 - (d * dt)
                if dragFactor < 0.0 { dragFactor = 0.0 }
                particles[i].velocity *= dragFactor
            }
        }
    }

    private func createAngularMovementOperator(
        drag: DynamicValue?,
        force: DynamicValue?
    ) -> OperatorFunc {
        let d = drag?.floatValue ?? 0.0
        let f = force?.vec3Value ?? .zero
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let speed =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            for i in 0..<count {
                if !particles[i].alive { continue }
                particles[i].rotation +=
                    particles[i].angularVelocity * dt * speed
                particles[i].angularVelocity += f * dt * speed
                var dragFactor = 1.0 - (d * dt)
                if dragFactor < 0.0 { dragFactor = 0.0 }
                particles[i].angularVelocity *= dragFactor

                for j in 0..<3 {
                    while particles[i].rotation[j] > .pi {
                        particles[i].rotation[j] -= 2 * .pi
                    }
                    while particles[i].rotation[j] < -.pi {
                        particles[i].rotation[j] += 2 * .pi
                    }
                }
            }
        }
    }

    private func createAlphaFadeOperator(
        fadeInTime: DynamicValue?,
        fadeOutTime: DynamicValue?
    ) -> OperatorFunc {
        let fi = fadeInTime?.floatValue ?? 0.0
        let fo = fadeOutTime?.floatValue ?? 1.0
        return { particles, count, cps, time, dt in
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                if life <= fi {
                    let fade = RendererMath.lerp(
                        a: 0.0,
                        b: 1.0,
                        t: life / max(0.0001, fi)
                    )
                    particles[i].alpha = particles[i].initial.alpha * fade
                } else if life > fo {
                    let fade =
                        1.0
                        - RendererMath.lerp(
                            a: 0.0,
                            b: 1.0,
                            t: (life - fo) / max(0.0001, 1.0 - fo)
                        )
                    particles[i].alpha = particles[i].initial.alpha * fade
                } else {
                    particles[i].alpha = particles[i].initial.alpha
                }
                particles[i].oscillateAlpha.base = particles[i].alpha
            }
        }
    }

    private func createSizeChangeOperator(
        startTime: DynamicValue?,
        endTime: DynamicValue?,
        startValue: DynamicValue?,
        endValue: DynamicValue?
    ) -> OperatorFunc {
        let st = startTime?.floatValue ?? 0.0
        let et = endTime?.floatValue ?? 1.0
        let sv = startValue?.floatValue ?? 1.0
        let ev = endValue?.floatValue ?? 1.0
        return { particles, count, cps, time, dt in
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                var multiplier: Float = 1.0
                if life <= st {
                    multiplier = sv
                } else if life >= et {
                    multiplier = ev
                } else {
                    multiplier = RendererMath.lerp(
                        a: sv,
                        b: ev,
                        t: (life - st) / (et - st)
                    )
                }
                particles[i].size = particles[i].initial.size * multiplier
                particles[i].oscillateSize.base = particles[i].size
            }
        }
    }

    private func createAlphaChangeOperator(
        startTime: DynamicValue?,
        endTime: DynamicValue?,
        startValue: DynamicValue?,
        endValue: DynamicValue?
    ) -> OperatorFunc {
        let st = startTime?.floatValue ?? 0.0
        let et = endTime?.floatValue ?? 1.0
        let sv = startValue?.floatValue ?? 1.0
        let ev = endValue?.floatValue ?? 1.0
        return { particles, count, cps, time, dt in
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                var multiplier: Float = 1.0
                if life <= st {
                    multiplier = sv
                } else if life >= et {
                    multiplier = ev
                } else {
                    multiplier = RendererMath.lerp(
                        a: sv,
                        b: ev,
                        t: (life - st) / (et - st)
                    )
                }
                particles[i].alpha = particles[i].initial.alpha * multiplier
                particles[i].oscillateAlpha.base = particles[i].alpha
            }
        }
    }

    private func createColorChangeOperator(
        startTime: DynamicValue?,
        endTime: DynamicValue?,
        startValue: DynamicValue?,
        endValue: DynamicValue?
    ) -> OperatorFunc {
        let st = startTime?.floatValue ?? 0.0
        let et = endTime?.floatValue ?? 1.0
        let sv = startValue?.vec3Value ?? simd_float3(1, 1, 1)
        let ev = endValue?.vec3Value ?? simd_float3(1, 1, 1)
        return { particles, count, cps, time, dt in
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                var colorMult = simd_float3(1, 1, 1)
                if life <= st {
                    colorMult = sv
                } else if life >= et {
                    colorMult = ev
                } else {
                    let t = (life - st) / (et - st)
                    colorMult = simd_float3(
                        RendererMath.lerp(a: sv.x, b: ev.x, t: t),
                        RendererMath.lerp(a: sv.y, b: ev.y, t: t),
                        RendererMath.lerp(a: sv.z, b: ev.z, t: t)
                    )
                }
                particles[i].color = particles[i].initial.color * colorMult
            }
        }
    }

    private func createTurbulenceOperator(
        scale: DynamicValue?,
        speedMin: DynamicValue?,
        speedMax: DynamicValue?,
        timeScale: DynamicValue?,
        mask: DynamicValue?,
        phaseMin: DynamicValue?,
        phaseMax: DynamicValue?
    ) -> OperatorFunc {
        let sc = (scale?.floatValue ?? 1.0) * 2.0
        let sMin = speedMin?.floatValue ?? 0.0
        let sMax = speedMax?.floatValue ?? 0.0
        let ts = timeScale?.floatValue ?? 1.0
        let m = mask?.vec3Value ?? simd_float3(1, 1, 1)
        let pMin = phaseMin?.floatValue ?? 0.0
        let pMax = phaseMax?.floatValue ?? 0.0

        let phase = Float.random(in: pMin...pMax, using: &self.rng)
        let turbSpeed = Float.random(in: sMin...sMax, using: &self.rng)

        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let speed =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            if turbSpeed <= 0.0001 { return }

            for i in 0..<count {
                if !particles[i].alive { continue }
                var noisePos = particles[i].position
                noisePos.x += phase + ts * time
                noisePos *= sc

                var curlDir = NoiseUtils.curlNoise(noisePos)
                let len = length(curlDir)
                if len > 0.0001 {
                    curlDir = (curlDir / len) * turbSpeed
                }
                curlDir *= m
                particles[i].velocity += curlDir * dt * speed
            }
        }
    }

    private func createVortexOperator(
        controlPoint: Int,
        flags: Int,
        axis: DynamicValue?,
        offset: DynamicValue?,
        distanceInner: DynamicValue?,
        distanceOuter: DynamicValue?,
        speedInner: DynamicValue?,
        speedOuter: DynamicValue?,
        centerForce: DynamicValue?,
        ringRadius: DynamicValue?,
        ringWidth: DynamicValue?,
        ringPullDistance: DynamicValue?,
        ringPullForce: DynamicValue?,
        audioProcessingMode: DynamicValue?
    ) -> OperatorFunc {
        let infiniteAxis = (flags & 1) != 0
        let maintainDistance = (flags & 2) != 0
        let ringShape = (flags & 4) != 0
        var ax = axis?.vec3Value ?? simd_float3(0, 0, 1)
        let off = offset?.vec3Value ?? .zero
        let dIn = distanceInner?.floatValue ?? 0.0
        let dOut = distanceOuter?.floatValue ?? 0.0
        let sIn = speedInner?.floatValue ?? 0.0
        let sOut = speedOuter?.floatValue ?? 0.0
        let cForce = centerForce?.floatValue ?? 0.0
        let rRad = ringRadius?.floatValue ?? 0.0
        let rWidth = ringWidth?.floatValue ?? 0.0
        let rpDist = ringPullDistance?.floatValue ?? 0.0
        let rpForce = ringPullForce?.floatValue ?? 0.0

        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let speedOverride =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            var center: simd_float3 = off
            if controlPoint >= 0 && controlPoint < cps.count {
                center = cps[controlPoint].position + off
            }
            if length(ax) > 0.0 { ax = normalize(ax) }

            for i in 0..<count {
                if !particles[i].alive { continue }
                let toParticle = particles[i].position - center
                var radialVector = toParticle
                if infiniteAxis {
                    let axialDist = dot(toParticle, ax)
                    radialVector = toParticle - ax * axialDist
                }
                let distance = length(radialVector)
                var tangent = cross(ax, radialVector)
                if length(tangent) > 0.001 {
                    tangent = normalize(tangent)
                } else {
                    continue
                }

                var speed: Float = 0.0
                var radialForce: simd_float3 = .zero

                if ringShape {
                    let ringInner = rRad - rWidth * 0.5
                    let ringOuter = rRad + rWidth * 0.5
                    if distance < ringInner {
                        speed = 0.0
                    } else if distance <= ringOuter {
                        let t = (distance - ringInner) / max(0.0001, rWidth)
                        speed = RendererMath.lerp(a: sIn, b: sOut, t: t)
                    } else if distance <= ringOuter + rpDist {
                        let pullT = (distance - ringOuter) / max(0.0001, rpDist)
                        speed = sOut * (1.0 - pullT)
                        if distance > 0.001 {
                            radialForce =
                                -normalize(radialVector) * rpForce * pullT
                        }
                    } else {
                        speed = 0.0
                    }
                } else {
                    let disMid = dOut - dIn + 0.1
                    if disMid < 0 || distance < dIn {
                        speed = sIn
                    } else if distance > dOut {
                        speed = sOut
                    } else {
                        let t = (distance - dIn) / disMid
                        speed = RendererMath.lerp(a: sIn, b: sOut, t: t)
                    }
                }

                particles[i].velocity += tangent * speed * dt * speedOverride
                particles[i].velocity += radialForce * dt * speedOverride

                if maintainDistance && distance > 0.001 {
                    particles[i].velocity +=
                        -normalize(radialVector) * cForce * dt * speedOverride
                }
            }
        }
    }

    private func createControlPointAttractOperator(
        controlPoint: Int,
        origin: DynamicValue?,
        scale: DynamicValue?,
        threshold: DynamicValue?
    ) -> OperatorFunc {
        let org = origin?.vec3Value ?? .zero
        let sc = scale?.floatValue ?? 0.0
        let th = (threshold?.floatValue ?? 0.0) / 2.0
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let speedOverride =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            if controlPoint < 0 || controlPoint >= cps.count { return }
            let center = cps[controlPoint].position + org

            for i in 0..<count {
                if !particles[i].alive { continue }
                let toCenter = center - particles[i].position
                let distance = length(toCenter)
                if distance > 0.001 && distance < th {
                    let direction = toCenter / distance
                    particles[i].velocity += direction * sc * dt * speedOverride
                }
            }
        }
    }

    private func createOscillateAlphaOperator(
        frequencyMin: DynamicValue?,
        frequencyMax: DynamicValue?,
        scaleMin: DynamicValue?,
        scaleMax: DynamicValue?,
        phaseMin: DynamicValue?,
        phaseMax: DynamicValue?
    ) -> OperatorFunc {
        let fMin = frequencyMin?.floatValue ?? 0.0
        let fMax = frequencyMax?.floatValue ?? 0.0
        let sMin = scaleMin?.floatValue ?? 1.0
        let sMax = scaleMax?.floatValue ?? 1.0
        let pMin = phaseMin?.floatValue ?? 0.0
        let pMax = phaseMax?.floatValue ?? 0.0

        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].oscillateAlpha.initialized {
                    particles[i].oscillateAlpha.frequency = Float.random(
                        in: fMin...fMax,
                        using: &self.rng
                    )
                    particles[i].oscillateAlpha.scale = Float.random(
                        in: sMin...sMax,
                        using: &self.rng
                    )
                    particles[i].oscillateAlpha.phase = Float.random(
                        in: pMin...(pMax + 2 * .pi),
                        using: &self.rng
                    )
                    particles[i].oscillateAlpha.base = particles[i].alpha
                    particles[i].oscillateAlpha.initialized = true
                }
                let w = particles[i].oscillateAlpha.frequency
                let t = particles[i].age
                let cosVal =
                    (cos(w * t + particles[i].oscillateAlpha.phase) + 1.0) * 0.5
                let multiplier = RendererMath.lerp(a: sMin, b: sMax, t: cosVal)
                particles[i].alpha =
                    particles[i].oscillateAlpha.base * multiplier
            }
        }
    }

    private func createOscillateSizeOperator(
        frequencyMin: DynamicValue?,
        frequencyMax: DynamicValue?,
        scaleMin: DynamicValue?,
        scaleMax: DynamicValue?,
        phaseMin: DynamicValue?,
        phaseMax: DynamicValue?
    ) -> OperatorFunc {
        let fMin = frequencyMin?.floatValue ?? 0.0
        let fMax = frequencyMax?.floatValue ?? 0.0
        let sMin = scaleMin?.floatValue ?? 1.0
        let sMax = scaleMax?.floatValue ?? 1.0
        let pMin = phaseMin?.floatValue ?? 0.0
        let pMax = phaseMax?.floatValue ?? 0.0

        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].oscillateSize.initialized {
                    particles[i].oscillateSize.frequency = Float.random(
                        in: fMin...fMax,
                        using: &self.rng
                    )
                    particles[i].oscillateSize.scale = Float.random(
                        in: sMin...sMax,
                        using: &self.rng
                    )
                    particles[i].oscillateSize.phase = Float.random(
                        in: pMin...(pMax + 2 * .pi),
                        using: &self.rng
                    )
                    particles[i].oscillateSize.base = particles[i].size
                    particles[i].oscillateSize.initialized = true
                }
                let w = particles[i].oscillateSize.frequency
                let t = particles[i].age
                let cosVal =
                    (cos(w * t + particles[i].oscillateSize.phase) + 1.0) * 0.5
                let multiplier = RendererMath.lerp(a: sMin, b: sMax, t: cosVal)
                particles[i].size = particles[i].oscillateSize.base * multiplier
            }
        }
    }

    private func createOscillatePositionOperator(
        frequencyMin: DynamicValue?,
        frequencyMax: DynamicValue?,
        scaleMin: DynamicValue?,
        scaleMax: DynamicValue?,
        phaseMin: DynamicValue?,
        phaseMax: DynamicValue?,
        mask: DynamicValue?
    ) -> OperatorFunc {
        let fMin = frequencyMin?.floatValue ?? 0.0
        let fMax = frequencyMax?.floatValue ?? 0.0
        let sMin = scaleMin?.floatValue ?? 1.0
        let sMax = scaleMax?.floatValue ?? 1.0
        let pMin = phaseMin?.floatValue ?? 0.0
        let pMax = phaseMax?.floatValue ?? 0.0
        let m = mask?.vec3Value ?? simd_float3(1, 1, 1)

        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let speedOverride =
                self.particleDef.instanceOverride?.speed?.value?.floatValue
                ?? 1.0
            for i in 0..<count {
                if !particles[i].oscillatePosition.initialized {
                    particles[i].oscillatePosition.frequency = simd_float3(
                        Float.random(in: fMin...fMax, using: &self.rng),
                        Float.random(in: fMin...fMax, using: &self.rng),
                        Float.random(in: fMin...fMax, using: &self.rng)
                    )
                    particles[i].oscillatePosition.scale = simd_float3(
                        Float.random(in: sMin...sMax, using: &self.rng),
                        Float.random(in: sMin...sMax, using: &self.rng),
                        Float.random(in: sMin...sMax, using: &self.rng)
                    )
                    particles[i].oscillatePosition.phase = simd_float3(
                        Float.random(
                            in: pMin...(pMax + 2 * .pi),
                            using: &self.rng
                        ),
                        Float.random(
                            in: pMin...(pMax + 2 * .pi),
                            using: &self.rng
                        ),
                        Float.random(
                            in: pMin...(pMax + 2 * .pi),
                            using: &self.rng
                        )
                    )
                    particles[i].oscillatePosition.initialized = true
                }

                let t = particles[i].age
                var delta: simd_float3 = .zero
                for axis in 0..<3 {
                    let w =
                        2.0 * .pi
                        * particles[i].oscillatePosition.frequency[axis]
                        / (2.0 * .pi)
                    let move =
                        -particles[i].oscillatePosition.scale[axis] * w
                        * sin(
                            w * t + particles[i].oscillatePosition.phase[axis]
                        ) * dt
                    delta[axis] = move * m[axis] * speedOverride
                }
                particles[i].position += delta
            }
        }
    }

    func update(dt: Float) {
        self.time += TimeInterval(dt)
        var cappedDt = dt
        if cappedDt > 0.1 { cappedDt = 0.1 }

        for i in 0..<controlPoints.count {
            if !controlPoints[i].linkMouse && controlPoints[i].worldSpace {
                controlPoints[i].position =
                    controlPoints[i].offset - transformedOrigin
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
                        particles[i].frame = Float.random(
                            in: 0...Float(spritesheetFrames - 1),
                            using: &rng
                        )
                    }
                } else if particleDef.animationMode == "once" {
                    particles[i].frame = min(
                        lifetimePos * Float(spritesheetFrames) * animSpeed,
                        Float(spritesheetFrames - 1)
                    )
                } else {
                    if spritesheetDuration > 0.0 {
                        let timeInCycle = fmod(
                            p.age * animSpeed,
                            spritesheetDuration
                        )
                        let cyclePos = timeInCycle / spritesheetDuration
                        particles[i].frame = fmod(
                            cyclePos * Float(spritesheetFrames),
                            Float(spritesheetFrames)
                        )
                    } else {
                        particles[i].frame = fmod(
                            lifetimePos * Float(spritesheetFrames) * animSpeed,
                            Float(spritesheetFrames)
                        )
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

    private func buildGeometry() {
        if particleCount == 0 {
            activeIndexCount = 0
            return
        }

        inFlightSemaphore.wait()
        currentBufferIndex = (currentBufferIndex + 1) % 3

        if useRopeRenderer {
            buildRopeGeometry()
        } else {
            buildSpriteGeometry()
        }
    }

    private func catmullRom(
        p0: simd_float3,
        p1: simd_float3,
        p2: simd_float3,
        p3: simd_float3,
        t: Float
    ) -> simd_float3 {
        let t2 = t * t
        let t3 = t2 * t
        let term1 = 2.0 * p1
        let term2 = (-p0 + p2) * t
        let term3 = (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        let term4 = (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
        return 0.5 * (term1 + term2 + term3 + term4)
    }

    private func buildRopeGeometry() {
        let aliveCount = particleCount
        if aliveCount < 2 {
            activeIndexCount = 0
            inFlightSemaphore.signal()
            return
        }

        let numSegments = aliveCount - 1
        let subdivision = max(1, ropeSubdivision)
        let totalPoints = numSegments * subdivision + 1

        var splinePositions = [simd_float3](
            repeating: .zero,
            count: totalPoints
        )
        var splineSizes = [Float](repeating: 0.0, count: totalPoints)
        var splineColors = [simd_float4](repeating: .zero, count: totalPoints)

        for i in 0..<numSegments {
            let p1 = particles[i]
            let p2 = particles[i + 1]
            let p0 = (i > 0) ? particles[i - 1] : p1
            let p3 = (i + 2 < aliveCount) ? particles[i + 2] : p2

            for k in 0..<subdivision {
                let t = Float(k) / Float(subdivision)
                let idx = i * subdivision + k
                splinePositions[idx] = catmullRom(
                    p0: p0.position,
                    p1: p1.position,
                    p2: p2.position,
                    p3: p3.position,
                    t: t
                )
                splineSizes[idx] = RendererMath.lerp(
                    a: p1.size,
                    b: p2.size,
                    t: t
                )
                let c1 = simd_float4(p1.color, p1.alpha)
                let c2 = simd_float4(p2.color, p2.alpha)
                splineColors[idx] = mix(c1, c2, t: simd_float4(t, t, t, t))
            }
        }
        let pLast = particles[aliveCount - 1]
        splinePositions[totalPoints - 1] = pLast.position
        splineSizes[totalPoints - 1] = pLast.size
        splineColors[totalPoints - 1] = simd_float4(pLast.color, pLast.alpha)

        let totalSubSegments = totalPoints - 1
        let uvScale = ropeUVScale > 0.0 ? ropeUVScale : 1.0
        let trLength = Float(totalSubSegments) / uvScale + 1.0
        let usableLength = trLength - 1.0

        let useSmoothing =
            ropeUVSmoothing && uniformLifetimes && !ropeUVScrolling
        var cumulativeArcLength = [Float](repeating: 0.0, count: totalPoints)
        var totalArcLength: Float = 0.0

        if useSmoothing {
            for i in 1..<totalPoints {
                totalArcLength += length(
                    splinePositions[i] - splinePositions[i - 1]
                )
                cumulativeArcLength[i] = totalArcLength
            }
        }

        var scrollOffset: Float = 0.0
        if ropeUVScrolling && usableLength > 0.0 {
            scrollOffset = fmod(Float(time), 10000.0) * usableLength
        }

        let vBuffer = vertexBuffers[currentBufferIndex]
        let iBuffer = indexBuffers[currentBufferIndex]
        let vData = vBuffer.contents().bindMemory(
            to: Float.self,
            capacity: totalSubSegments * 4 * 26
        )
        let iData = iBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: totalSubSegments * 6
        )

        var vIdx = 0
        var iIdx = 0

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
                    (cumulativeArcLength[s] / totalArcLength)
                    * Float(totalSubSegments)
            } else {
                trailPosition = Float(s)
            }
            trailPosition += scrollOffset

            let baseV = UInt32(vIdx / 26)

            let addVertex = { (u: Float, v: Float) in
                vData[vIdx + 0] = posStart.x
                vData[vIdx + 1] = posStart.y
                vData[vIdx + 2] = posStart.z
                vData[vIdx + 3] = sizeStart
                vData[vIdx + 4] = posEnd.x
                vData[vIdx + 5] = posEnd.y
                vData[vIdx + 6] = posEnd.z
                vData[vIdx + 7] = trLength
                vData[vIdx + 8] = posPrev.x
                vData[vIdx + 9] = posPrev.y
                vData[vIdx + 10] = posPrev.z
                vData[vIdx + 11] = trailPosition
                vData[vIdx + 12] = posAfter.x
                vData[vIdx + 13] = posAfter.y
                vData[vIdx + 14] = posAfter.z
                vData[vIdx + 15] = sizeEnd
                vData[vIdx + 16] = colorEnd.x
                vData[vIdx + 17] = colorEnd.y
                vData[vIdx + 18] = colorEnd.z
                vData[vIdx + 19] = colorEnd.w
                vData[vIdx + 20] = u
                vData[vIdx + 21] = v
                vData[vIdx + 22] = colorStart.x
                vData[vIdx + 23] = colorStart.y
                vData[vIdx + 24] = colorStart.z
                vData[vIdx + 25] = colorStart.w
                vIdx += 26
            }

            addVertex(0.0, 0.0)
            addVertex(1.0, 0.0)
            addVertex(1.0, 1.0)
            addVertex(0.0, 1.0)

            iData[iIdx + 0] = baseV + 0
            iData[iIdx + 1] = baseV + 1
            iData[iIdx + 2] = baseV + 2
            iData[iIdx + 3] = baseV + 2
            iData[iIdx + 4] = baseV + 3
            iData[iIdx + 5] = baseV + 0
            iIdx += 6
        }
        activeIndexCount = iIdx
    }

    private func buildSpriteGeometry() {
        let aliveCount = particleCount
        if aliveCount == 0 {
            activeIndexCount = 0
            inFlightSemaphore.signal()
            return
        }

        let vBuffer = vertexBuffers[currentBufferIndex]
        let iBuffer = indexBuffers[currentBufferIndex]
        let vData = vBuffer.contents().bindMemory(
            to: Float.self,
            capacity: aliveCount * 4 * 17
        )
        let iData = iBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: aliveCount * 6
        )

        var vIdx = 0
        var iIdx = 0

        for i in 0..<particleCount {
            let p = particles[i]
            if !p.alive { continue }

            var lifetimeVal = p.getLifetimePos()
            if spritesheetFrames > 0 && p.frame >= 0.0 {
                if particleDef.animationMode == "randomframe" {
                    lifetimeVal = (p.frame + 0.5) / Float(spritesheetFrames)
                } else {
                    lifetimeVal = p.frame / Float(spritesheetFrames)
                }
            }

            let baseV = UInt32(vIdx / 17)

            let addVertex = { (u: Float, v: Float) in
                vData[vIdx + 0] = p.position.x
                vData[vIdx + 1] = p.position.y
                vData[vIdx + 2] = p.position.z
                vData[vIdx + 3] = u
                vData[vIdx + 4] = v
                vData[vIdx + 5] = p.rotation.z
                vData[vIdx + 6] = p.size
                vData[vIdx + 7] = p.color.x
                vData[vIdx + 8] = p.color.y
                vData[vIdx + 9] = p.color.z
                vData[vIdx + 10] = p.alpha
                vData[vIdx + 11] = p.velocity.x
                vData[vIdx + 12] = p.velocity.y
                vData[vIdx + 13] = p.velocity.z
                vData[vIdx + 14] = lifetimeVal
                vData[vIdx + 15] = p.rotation.x
                vData[vIdx + 16] = p.rotation.y
                vIdx += 17
            }

            addVertex(0.0, 1.0)
            addVertex(1.0, 1.0)
            addVertex(1.0, 0.0)
            addVertex(0.0, 0.0)

            iData[iIdx + 0] = baseV + 0
            iData[iIdx + 1] = baseV + 1
            iData[iIdx + 2] = baseV + 2
            iData[iIdx + 3] = baseV + 2
            iData[iIdx + 4] = baseV + 3
            iData[iIdx + 5] = baseV + 0
            iIdx += 6
        }
        activeIndexCount = iIdx
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

        encoder.setVertexBuffer(
            vertexBuffers[currentBufferIndex],
            offset: 0,
            index: 0
        )

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
