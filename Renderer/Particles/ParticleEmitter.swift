//
//  ParticleEmitter.swift
//  Renderer
//
//  Created by laobamac on 2026/2/27.
//

import simd

class BoxRandomEmitter: ParticleEmitter {
    let def: ParticleEmitterDef
    var emissionTimer: Float = 0
    var elapsedTime: Float = 0
    var delayTimer: Float
    var durationTimer: Float = 0
    var periodicTimer: Float = 0
    var periodicDuration: Float = 0
    var periodicDelay: Float = 0
    var emitting: Bool = false
    var instantaneousEmitted: Bool = false

    init(def: ParticleEmitterDef) {
        self.def = def
        self.delayTimer = def.delay ?? 0
    }

    func emit(
        particles: inout [ParticleInstance],
        count: inout Int,
        dt: Float,
        controlPoints: [ControlPointData],
        initializers: [ParticleInitializer],
        instanceOverride: ParticleInstanceOverride?,
        isOrthographic: Bool
    ) {
        let countOverride = instanceOverride?.count ?? 1
        let effectiveMaxCount = Int(Float(particles.count) * countOverride)
        if effectiveMaxCount <= 0 { return }
        if count >= effectiveMaxCount { return }

        let baseRate = def.rate ?? 10
        let rate = baseRate * countOverride

        let transformedOrigin = def.origin?.getVec3() ?? .zero

        var cpIndex = def.controlpoint ?? -1
        if cpIndex == -1 && !controlPoints.isEmpty {
            if controlPoints[0].linkMouse {
                cpIndex = 0
            }
        }

        let flippedDirections =
            def.directions?.getVec3() ?? SIMD3<Float>(1, 1, 0)

        let flags = def.flags ?? 0
        let limitOnePerFrame = (flags & 2) != 0
        let randomPeriodicEmission = (flags & 4) != 0

        elapsedTime += dt

        if delayTimer > 0 {
            delayTimer -= dt
            return
        }

        let duration = def.duration ?? 0
        if duration > 0 {
            durationTimer += dt
            if durationTimer >= duration { return }
        }

        if randomPeriodicEmission {
            periodicTimer += dt
            let minPDur = def.minperiodicduration ?? 2
            let maxPDur = def.maxperiodicduration ?? 3
            let minPDel = def.minperiodicdelay ?? 1
            let maxPDel = def.maxperiodicdelay ?? 2

            if !emitting {
                if periodicTimer >= periodicDelay {
                    emitting = true
                    periodicTimer = 0
                    periodicDuration = ParticleMath.randomFloat(
                        min: minPDur,
                        max: maxPDur
                    )
                } else {
                    return
                }
            } else {
                if periodicTimer >= periodicDuration {
                    emitting = false
                    periodicTimer = 0
                    periodicDelay = ParticleMath.randomFloat(
                        min: minPDel,
                        max: maxPDel
                    )
                    return
                }
            }
        }

        var toEmit: Int = 0
        let instantaneous = def.instantaneous ?? 0
        if instantaneous > 0 && !instantaneousEmitted {
            toEmit = Int(Float(instantaneous) * countOverride)
            instantaneousEmitted = true
        }

        if rate > 0 {
            emissionTimer += dt * rate
            var rateEmit = Int(emissionTimer)
            emissionTimer -= Float(rateEmit)
            if limitOnePerFrame && rateEmit > 1 {
                rateEmit = 1
            }
            toEmit += rateEmit
        }

        let minD = def.distancemin?.getVec3() ?? .zero
        let maxD = def.distancemax?.getVec3() ?? .zero

        for _ in 0..<toEmit {
            if count >= effectiveMaxCount { break }

            var spawnOrigin = transformedOrigin
            if cpIndex >= 0 && cpIndex < controlPoints.count {
                spawnOrigin += controlPoints[cpIndex].position
            }

            var randomPos = SIMD3<Float>.zero
            for axis in 0..<3 {
                var dist = ParticleMath.randomFloat(
                    min: minD[axis],
                    max: maxD[axis]
                )
                if ParticleMath.randomFloat(min: 0, max: 1) < 0.5 {
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

            let cOverride =
                instanceOverride?.colorn != nil
                ? ScriptableValue.string(instanceOverride!.colorn!).getVec3()
                : SIMD3<Float>(1, 1, 1)
            particles[count].color = cOverride
            particles[count].alpha = instanceOverride?.alpha ?? 1
            particles[count].size = 20 * (instanceOverride?.size ?? 1)
            particles[count].lifetime = instanceOverride?.lifetime ?? 1
            particles[count].age = 0
            particles[count].alive = true
            particles[count].frame = -1

            particles[count].initial.color = particles[count].color
            particles[count].initial.alpha = particles[count].alpha
            particles[count].initial.size = particles[count].size
            particles[count].initial.lifetime = particles[count].lifetime

            particles[count].oscillateAlpha = ParticleInstance.OscillatorState()
            particles[count].oscillateSize = ParticleInstance.OscillatorState()
            particles[count].oscillatePosition =
                ParticleInstance.PositionOscillatorState()

            for i in 0..<initializers.count {
                initializers[i].initialize(
                    particle: &particles[count],
                    instanceOverride: instanceOverride
                )
            }

            count += 1
        }
    }
}

class SphereRandomEmitter: ParticleEmitter {
    let def: ParticleEmitterDef
    var emissionTimer: Float = 0
    var remaining: Int

    init(def: ParticleEmitterDef) {
        self.def = def
        self.remaining = def.instantaneous ?? 0
    }

    func emit(
        particles: inout [ParticleInstance],
        count: inout Int,
        dt: Float,
        controlPoints: [ControlPointData],
        initializers: [ParticleInitializer],
        instanceOverride: ParticleInstanceOverride?,
        isOrthographic: Bool
    ) {
        let countOverride = instanceOverride?.count ?? 1
        let effectiveMaxCount = Int(Float(particles.count) * countOverride)
        if effectiveMaxCount <= 0 { return }
        if count >= effectiveMaxCount { return }

        let baseRate = def.rate ?? 10
        let rate = baseRate * countOverride
        let lifetimeOverride = instanceOverride?.lifetime ?? 1

        let transformedOrigin = def.origin?.getVec3() ?? .zero

        var cpIndex = def.controlpoint ?? -1
        if cpIndex == -1 && !controlPoints.isEmpty {
            if controlPoints[0].linkMouse {
                cpIndex = 0
            }
        }

        let flags = def.flags ?? 0
        let limitOnePerFrame = (flags & 2) != 0

        emissionTimer += dt * rate
        var toEmit = Int(emissionTimer)
        emissionTimer -= Float(toEmit)

        if limitOnePerFrame && toEmit > 1 {
            toEmit = 1
        }

        if remaining > 0 {
            toEmit += Int(Float(remaining) * countOverride)
            remaining = 0
        }

        let minD = def.distancemin?.getVec3() ?? .zero
        let maxD = def.distancemax?.getVec3() ?? SIMD3<Float>(256, 256, 0)
        let directions = def.directions?.getVec3() ?? SIMD3<Float>(1, 1, 0)
        let signs = def.sign?.getVec3() ?? .zero

        let speedMin = def.speedmin ?? 0
        let speedMax = def.speedmax ?? 0

        for _ in 0..<toEmit {
            if count >= effectiveMaxCount { break }

            var spawnOrigin = transformedOrigin
            if cpIndex >= 0 && cpIndex < controlPoints.count {
                spawnOrigin += controlPoints[cpIndex].position
            }

            var randomPos = SIMD3<Float>.zero

            if isOrthographic {
                let angle = ParticleMath.randomFloat(min: 0, max: Float.pi * 2)
                let minRadiusSq = minD.x * minD.x
                let maxRadiusSq = maxD.x * maxD.x
                let radiusXY = sqrt(
                    ParticleMath.randomFloat(min: minRadiusSq, max: maxRadiusSq)
                )
                randomPos = SIMD3<Float>(
                    radiusXY * cos(angle),
                    radiusXY * sin(angle),
                    ParticleMath.randomFloat(min: -maxD.x, max: maxD.x)
                )
                randomPos *= directions
            } else {
                let theta = ParticleMath.randomFloat(min: 0, max: Float.pi * 2)
                let cosTheta = ParticleMath.randomFloat(min: -1, max: 1)
                let sinTheta = sqrt(1 - cosTheta * cosTheta)
                randomPos = SIMD3<Float>(
                    sinTheta * cos(theta),
                    sinTheta * sin(theta),
                    cosTheta
                )
                let minRadiusCubed = minD.x * minD.x * minD.x
                let maxRadiusCubed = maxD.x * maxD.x * maxD.x
                let radius = cbrt(
                    ParticleMath.randomFloat(
                        min: minRadiusCubed,
                        max: maxRadiusCubed
                    )
                )
                randomPos *= radius
                randomPos *= directions
            }

            for axis in 0..<3 {
                if signs[axis] == 1 {
                    randomPos[axis] = abs(randomPos[axis])
                } else if signs[axis] == -1 {
                    randomPos[axis] = -abs(randomPos[axis])
                }
            }

            particles[count].position = spawnOrigin + randomPos

            if speedMax > 0 || speedMin != 0 {
                let direction =
                    length(randomPos) > 0
                    ? normalize(randomPos) : SIMD3<Float>(0, 1, 0)
                let speed = ParticleMath.randomFloat(
                    min: speedMin,
                    max: speedMax
                )
                particles[count].velocity = direction * speed
            } else {
                particles[count].velocity = .zero
            }

            particles[count].acceleration = .zero
            particles[count].rotation = .zero
            particles[count].angularVelocity = .zero
            particles[count].angularAcceleration = .zero

            let cOverride =
                instanceOverride?.colorn != nil
                ? ScriptableValue.string(instanceOverride!.colorn!).getVec3()
                : SIMD3<Float>(1, 1, 1)
            particles[count].color = cOverride
            particles[count].alpha = instanceOverride?.alpha ?? 1
            particles[count].size = 20 * (instanceOverride?.size ?? 1)
            particles[count].lifetime = lifetimeOverride
            particles[count].age = 0
            particles[count].alive = true
            particles[count].frame = -1

            particles[count].initial.color = particles[count].color
            particles[count].initial.alpha = particles[count].alpha
            particles[count].initial.size = particles[count].size
            particles[count].initial.lifetime = particles[count].lifetime

            particles[count].oscillateAlpha = ParticleInstance.OscillatorState()
            particles[count].oscillateSize = ParticleInstance.OscillatorState()
            particles[count].oscillatePosition =
                ParticleInstance.PositionOscillatorState()

            for i in 0..<initializers.count {
                initializers[i].initialize(
                    particle: &particles[count],
                    instanceOverride: instanceOverride
                )
            }

            count += 1
        }
    }
}
