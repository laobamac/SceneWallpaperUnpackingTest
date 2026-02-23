//
//  ParticleModules.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import simd

extension ScriptableValue {
    func getFloat() -> Float {
        switch self {
        case .float(let f): return f
        case .int(let i): return Float(i)
        case .string(let s): return Float(s) ?? 0.0
        case .script(let v): return Float(v) ?? 0.0
        case .floatArray(let a): return a.first ?? 0.0
        }
    }

    func getVec3() -> SIMD3<Float> {
        switch self {
        case .string(let s), .script(let s):
            let parts = s.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 {
                return SIMD3<Float>(parts[0], parts[1], parts[2])
            } else if parts.count == 1 {
                return SIMD3<Float>(parts[0], parts[0], parts[0])
            }
            return .zero
        case .floatArray(let a):
            if a.count >= 3 { return SIMD3<Float>(a[0], a[1], a[2]) }
            return .zero
        case .float(let f):
            return SIMD3<Float>(f, f, f)
        case .int(let i):
            let f = Float(i)
            return SIMD3<Float>(f, f, f)
        }
    }
}

class BoxRandomEmitter: ParticleEmitter {
    let def: ParticleEmitterDef
    var emissionTimer: Float = 0.0
    var elapsedTime: Float = 0.0
    var delayTimer: Float
    var durationTimer: Float = 0.0
    var periodicTimer: Float = 0.0
    var periodicDuration: Float = 0.0
    var periodicDelay: Float = 0.0
    var emitting: Bool = false
    var instantaneousEmitted: Bool = false

    init(def: ParticleEmitterDef) {
        self.def = def
        self.delayTimer = def.delay ?? 0.0
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
        let countOverride = instanceOverride?.count ?? 1.0
        let effectiveMaxCount = Int(Float(particles.count) * countOverride)
        if effectiveMaxCount <= 0 { return }
        if count >= effectiveMaxCount { return }

        let baseRate = def.rate ?? 10.0
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

        if delayTimer > 0.0 {
            delayTimer -= dt
            return
        }

        let duration = def.duration ?? 0.0
        if duration > 0.0 {
            durationTimer += dt
            if durationTimer >= duration { return }
        }

        if randomPeriodicEmission {
            periodicTimer += dt
            let minPDur = def.minperiodicduration ?? 2.0
            let maxPDur = def.maxperiodicduration ?? 3.0
            let minPDel = def.minperiodicdelay ?? 1.0
            let maxPDel = def.maxperiodicdelay ?? 2.0

            if !emitting {
                if periodicTimer >= periodicDelay {
                    emitting = true
                    periodicTimer = 0.0
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
                    periodicTimer = 0.0
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

        if rate > 0.0 {
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
                : .one
            particles[count].color = cOverride
            particles[count].alpha = instanceOverride?.alpha ?? 1.0
            particles[count].size = 20.0 * (instanceOverride?.size ?? 1.0)
            particles[count].lifetime = instanceOverride?.lifetime ?? 1.0
            particles[count].age = 0.0
            particles[count].alive = true
            particles[count].frame = -1.0

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
    var emissionTimer: Float = 0.0
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
        let countOverride = instanceOverride?.count ?? 1.0
        let effectiveMaxCount = Int(Float(particles.count) * countOverride)
        if effectiveMaxCount <= 0 { return }
        if count >= effectiveMaxCount { return }

        let baseRate = def.rate ?? 10.0
        let rate = baseRate * countOverride
        let lifetimeOverride = instanceOverride?.lifetime ?? 1.0

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

        let speedMin = def.speedmin ?? 0.0
        let speedMax = def.speedmax ?? 0.0

        for _ in 0..<toEmit {
            if count >= effectiveMaxCount { break }

            var spawnOrigin = transformedOrigin
            if cpIndex >= 0 && cpIndex < controlPoints.count {
                spawnOrigin += controlPoints[cpIndex].position
            }

            var randomPos = SIMD3<Float>.zero

            if isOrthographic {
                let angle = ParticleMath.randomFloat(min: 0, max: .pi * 2)
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
                let theta = ParticleMath.randomFloat(min: 0, max: .pi * 2)
                let cosTheta = ParticleMath.randomFloat(min: -1, max: 1)
                let sinTheta = sqrt(1.0 - cosTheta * cosTheta)
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

            if speedMax > 0.0 || speedMin != 0.0 {
                let direction =
                    length(randomPos) > 0.0
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
                : .one
            particles[count].color = cOverride
            particles[count].alpha = instanceOverride?.alpha ?? 1.0
            particles[count].size = 20.0 * (instanceOverride?.size ?? 1.0)
            particles[count].lifetime = lifetimeOverride
            particles[count].age = 0.0
            particles[count].alive = true
            particles[count].frame = -1.0

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

class ColorRandomInitializer: ParticleInitializer {
    let minVal: SIMD3<Float>
    let maxVal: SIMD3<Float>
    init(def: ParticleInitializerDef) {
        var mn = def.min?.getVec3() ?? .zero
        var mx = def.max?.getVec3() ?? SIMD3<Float>(255, 255, 255)
        if mn.x > 1.0 || mn.y > 1.0 || mn.z > 1.0 { mn /= 255.0 }
        if mx.x > 1.0 || mx.y > 1.0 || mx.z > 1.0 { mx /= 255.0 }
        self.minVal = mn
        self.maxVal = mx
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let overrideColor =
            instanceOverride?.colorn != nil
            ? ScriptableValue.string(instanceOverride!.colorn!).getVec3() : .one
        particle.color =
            ParticleMath.randomVec3(min: minVal, max: maxVal) * overrideColor
        particle.initial.color = particle.color
    }
}

class SizeRandomInitializer: ParticleInitializer {
    let minVal: Float
    let maxVal: Float
    let exponent: Float
    init(def: ParticleInitializerDef) {
        self.minVal = def.min?.getFloat() ?? 0.0
        self.maxVal = def.max?.getFloat() ?? 20.0
        self.exponent = def.exponent?.getFloat() ?? 1.0
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let t = ParticleMath.randomFloat(min: 0.0, max: 1.0)
        let adjustedT = pow(t, exponent)
        let overrideSize = instanceOverride?.size ?? 1.0
        particle.size =
            (minVal + adjustedT * (maxVal - minVal)) * overrideSize / 2.0
        particle.initial.size = particle.size
    }
}

class AlphaRandomInitializer: ParticleInitializer {
    let minVal: Float
    let maxVal: Float
    init(def: ParticleInitializerDef) {
        self.minVal = def.min?.getFloat() ?? 0.05
        self.maxVal = def.max?.getFloat() ?? 1.0
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let overrideAlpha = instanceOverride?.alpha ?? 1.0
        particle.alpha =
            ParticleMath.randomFloat(min: minVal, max: maxVal) * overrideAlpha
        particle.initial.alpha = particle.alpha
    }
}

class LifetimeRandomInitializer: ParticleInitializer {
    let minVal: Float
    let maxVal: Float
    init(def: ParticleInitializerDef) {
        self.minVal = def.min?.getFloat() ?? 0.0
        self.maxVal = def.max?.getFloat() ?? 1.0
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let overrideLife = instanceOverride?.lifetime ?? 1.0
        particle.lifetime =
            ParticleMath.randomFloat(min: minVal, max: maxVal) * overrideLife
        particle.initial.lifetime = particle.lifetime
    }
}

class VelocityRandomInitializer: ParticleInitializer {
    let minVal: SIMD3<Float>
    let maxVal: SIMD3<Float>
    init(def: ParticleInitializerDef) {
        self.minVal = def.min?.getVec3() ?? SIMD3<Float>(-32, -32, -32)
        self.maxVal = def.max?.getVec3() ?? SIMD3<Float>(32, 32, 32)
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let overrideSpeed = instanceOverride?.speed ?? 1.0
        let vel =
            ParticleMath.randomVec3(min: minVal, max: maxVal) * overrideSpeed
        particle.velocity += vel
    }
}

class RotationRandomInitializer: ParticleInitializer {
    let minVal: SIMD3<Float>
    let maxVal: SIMD3<Float>
    init(def: ParticleInitializerDef) {
        let degToRad = Float.pi / 180.0
        self.minVal = (def.min?.getVec3() ?? .zero) * degToRad
        self.maxVal =
            (def.max?.getVec3() ?? SIMD3<Float>(0, 0, 360.0)) * degToRad
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let overrideSpeed = instanceOverride?.speed ?? 1.0
        particle.rotation =
            ParticleMath.randomVec3(min: minVal, max: maxVal) * overrideSpeed
    }
}

class AngularVelocityRandomInitializer: ParticleInitializer {
    let minVal: SIMD3<Float>
    let maxVal: SIMD3<Float>
    let exponent: Float
    init(def: ParticleInitializerDef) {
        let degToRad = Float.pi / 180.0
        self.minVal = (def.min?.getVec3() ?? SIMD3<Float>(0, 0, -5)) * degToRad
        self.maxVal = (def.max?.getVec3() ?? SIMD3<Float>(0, 0, 5)) * degToRad
        self.exponent = def.exponent?.getFloat() ?? 1.0
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        var result = SIMD3<Float>.zero
        for i in 0..<3 {
            var t = ParticleMath.randomFloat(min: 0, max: 1)
            t = pow(t, exponent)
            result[i] = minVal[i] + t * (maxVal[i] - minVal[i])
        }
        let overrideSpeed = instanceOverride?.speed ?? 1.0
        particle.angularVelocity = result * overrideSpeed
    }
}

class TurbulentVelocityRandomInitializer: ParticleInitializer {
    let speedMin: Float
    let speedMax: Float
    let scale: Float
    let offset: Float
    let forward: SIMD3<Float>
    let timeScale: Float
    let phaseMin: Float
    let phaseMax: Float
    let right: SIMD3<Float>

    init(def: ParticleInitializerDef) {
        self.speedMin = def.speedmin?.getFloat() ?? 100.0
        self.speedMax = def.speedmax?.getFloat() ?? 250.0
        self.scale = def.scale?.getFloat() ?? 1.0
        self.offset = (def.offset?.getFloat() ?? 0.0) * (Float.pi / 180.0)
        self.forward = def.forward?.getVec3() ?? SIMD3<Float>(0, 1, 0)
        self.timeScale = def.timescale?.getFloat() ?? 1.0
        self.phaseMin = def.phasemin?.getFloat() ?? 0.0
        self.phaseMax = def.phasemax?.getFloat() ?? 0.1
        self.right = def.right?.getVec3() ?? SIMD3<Float>(0, 0, 1)
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        var fwd = forward
        var rgt = right

        if length(fwd) > 0.0001 {
            fwd = normalize(fwd)
        } else {
            fwd = SIMD3<Float>(0, 1, 0)
        }
        if length(rgt) > 0.0001 {
            rgt = normalize(rgt)
        } else {
            rgt = SIMD3<Float>(1, 0, 0)
        }

        let speed = ParticleMath.randomFloat(min: speedMin, max: speedMax)
        var noisePos = particle.position * 0.1
        noisePos += SIMD3<Float>(
            repeating: Float(
                Date().timeIntervalSince1970.truncatingRemainder(
                    dividingBy: 1000.0
                )
            ) * timeScale
        )
        let phase = ParticleMath.randomFloat(min: phaseMin, max: phaseMax)
        let samplePos = noisePos + SIMD3<Float>(phase, phase * 0.7, phase * 1.3)

        var result = ParticleMath.curlNoise(p: samplePos)
        let len = length(result)
        if len < 0.0001 { result = fwd } else { result = result / len }

        if scale < 2.0 {
            let cosAngle = dot(result, fwd)
            let angle = acos(simd_clamp(cosAngle, -1.0, 1.0)) / Float.pi
            let maxAngle = scale / 2.0
            if angle > maxAngle && maxAngle > 0.0001 {
                var axis = cross(result, fwd)
                let axisLen = length(axis)
                if axisLen > 0.0001 {
                    axis = axis / axisLen
                    let rotAngle = (angle - maxAngle) * Float.pi
                    let rot = ParticleMath.rotationMatrix3x3(
                        angle: rotAngle,
                        axis: axis
                    )
                    let rotResult =
                        rot * SIMD3<Float>(result.x, result.y, result.z)
                    result = SIMD3<Float>(rotResult.x, rotResult.y, rotResult.z)
                }
            }
        }

        if abs(offset) > 0.0001 {
            let rot = ParticleMath.rotationMatrix3x3(angle: -offset, axis: rgt)
            let rotResult = rot * SIMD3<Float>(result.x, result.y, result.z)
            result = SIMD3<Float>(rotResult.x, rotResult.y, rotResult.z)
        }

        result.z = 0.0
        let len2d = length(result)
        if len2d > 0.0001 { result /= len2d }

        let overrideSpeed = instanceOverride?.speed ?? 1.0
        let finalVel = result * speed * overrideSpeed
        particle.velocity += finalVel
    }
}

class MapSequenceAroundControlPointInitializer: ParticleInitializer {
    let controlPoint: Int
    let count: Int
    let speedMin: SIMD3<Float>
    let speedMax: SIMD3<Float>
    var sequenceIndex = 0

    init(def: ParticleInitializerDef) {
        self.controlPoint = Int(def.controlpoint?.getFloat() ?? 0)
        self.count = Int(def.count?.getFloat() ?? 1)
        self.speedMin = def.speedmin?.getVec3() ?? .zero
        self.speedMax = def.speedmax?.getVec3() ?? SIMD3<Float>(100, 100, 100)
    }

    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let overrideSpeed = instanceOverride?.speed ?? 1.0
        let angle = (Float(sequenceIndex) / Float(count)) * Float.pi * 2.0
        sequenceIndex = (sequenceIndex + 1) % count

        let speed = ParticleMath.randomVec3(min: speedMin, max: speedMax)

        let rotMat = matrix_float3x3(
            SIMD3<Float>(cos(angle), sin(angle), 0),
            SIMD3<Float>(-sin(angle), cos(angle), 0),
            SIMD3<Float>(0, 0, 1)
        )
        let rotatedSpeed = rotMat * SIMD3<Float>(speed.x, speed.y, speed.z)
        particle.velocity =
            SIMD3<Float>(rotatedSpeed.x, rotatedSpeed.y, rotatedSpeed.z)
            * overrideSpeed
    }
}

class MovementOperator: ParticleOperator {
    let drag: Float
    let gravity: SIMD3<Float>

    init(def: ParticleOperatorDef) {
        self.drag = def.drag?.getFloat() ?? 0.0
        self.gravity = def.gravity?.getVec3() ?? .zero
    }

    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        let speed = instanceOverride?.speed ?? 1.0
        let grav = gravity + globalGravity
        for i in 0..<count {
            if !particles[i].alive { continue }
            particles[i].position += particles[i].velocity * dt
            particles[i].velocity += grav * dt * speed
            particles[i].velocity += globalWind * dt * speed
            var dragFactor = 1.0 - (drag * dt)
            if dragFactor < 0.0 { dragFactor = 0.0 }
            particles[i].velocity *= dragFactor
        }
    }
}

class AngularMovementOperator: ParticleOperator {
    let drag: Float
    let force: SIMD3<Float>

    init(def: ParticleOperatorDef) {
        let degToRad = Float.pi / 180.0
        self.drag = def.drag?.getFloat() ?? 0.0
        self.force = (def.force?.getVec3() ?? .zero) * degToRad
    }

    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        let speed = instanceOverride?.speed ?? 1.0
        let pi = Float.pi
        let two_pi = Float.pi * 2.0
        for i in 0..<count {
            if !particles[i].alive { continue }
            particles[i].rotation += particles[i].angularVelocity * dt * speed
            particles[i].angularVelocity += force * dt * speed
            var dragFactor = 1.0 - (drag * dt)
            if dragFactor < 0.0 { dragFactor = 0.0 }
            particles[i].angularVelocity *= dragFactor
            for j in 0..<3 {
                while particles[i].rotation[j] > pi {
                    particles[i].rotation[j] -= two_pi
                }
                while particles[i].rotation[j] < -pi {
                    particles[i].rotation[j] += two_pi
                }
            }
        }
    }
}

class AlphaFadeOperator: ParticleOperator {
    let fadeInTime: Float
    let fadeOutTime: Float
    init(def: ParticleOperatorDef) {
        self.fadeInTime = def.fadeintime?.getFloat() ?? 0.5
        self.fadeOutTime = def.fadeouttime?.getFloat() ?? 0.5
    }
    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        for i in 0..<count {
            if !particles[i].alive { continue }
            let life = particles[i].lifetimePos
            if life <= fadeInTime {
                let fade = ParticleMath.fadeValue(
                    life: life,
                    startTime: 0,
                    endTime: fadeInTime,
                    startValue: 0,
                    endValue: 1
                )
                particles[i].alpha = particles[i].initial.alpha * fade
            } else if life > fadeOutTime {
                let fade =
                    1.0
                    - ParticleMath.fadeValue(
                        life: life,
                        startTime: fadeOutTime,
                        endTime: 1.0,
                        startValue: 0,
                        endValue: 1
                    )
                particles[i].alpha = particles[i].initial.alpha * fade
            } else {
                particles[i].alpha = particles[i].initial.alpha
            }
            particles[i].oscillateAlpha.base = particles[i].alpha
        }
    }
}

class SizeChangeOperator: ParticleOperator {
    let startTime: Float
    let endTime: Float
    let startValue: Float
    let endValue: Float
    init(def: ParticleOperatorDef) {
        self.startTime = def.starttime?.getFloat() ?? 0.0
        self.endTime = def.endtime?.getFloat() ?? 1.0
        self.startValue = def.startvalue?.getFloat() ?? 1.0
        self.endValue = def.endvalue?.getFloat() ?? 0.0
    }
    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        for i in 0..<count {
            if !particles[i].alive { continue }
            let life = particles[i].lifetimePos
            let multiplier = ParticleMath.fadeValue(
                life: life,
                startTime: startTime,
                endTime: endTime,
                startValue: startValue,
                endValue: endValue
            )
            particles[i].size = particles[i].initial.size * multiplier
            particles[i].oscillateSize.base = particles[i].size
        }
    }
}

class AlphaChangeOperator: ParticleOperator {
    let startTime: Float
    let endTime: Float
    let startValue: Float
    let endValue: Float
    init(def: ParticleOperatorDef) {
        self.startTime = def.starttime?.getFloat() ?? 0.0
        self.endTime = def.endtime?.getFloat() ?? 1.0
        self.startValue = def.startvalue?.getFloat() ?? 1.0
        self.endValue = def.endvalue?.getFloat() ?? 0.0
    }
    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        for i in 0..<count {
            if !particles[i].alive { continue }
            let life = particles[i].lifetimePos
            let multiplier = ParticleMath.fadeValue(
                life: life,
                startTime: startTime,
                endTime: endTime,
                startValue: startValue,
                endValue: endValue
            )
            particles[i].alpha = particles[i].initial.alpha * multiplier
            particles[i].oscillateAlpha.base = particles[i].alpha
        }
    }
}

class ColorChangeOperator: ParticleOperator {
    let startTime: Float
    let endTime: Float
    let startValue: SIMD3<Float>
    let endValue: SIMD3<Float>
    init(def: ParticleOperatorDef) {
        self.startTime = def.starttime?.getFloat() ?? 0.0
        self.endTime = def.endtime?.getFloat() ?? 1.0
        self.startValue = def.startvalue?.getVec3() ?? .one
        self.endValue = def.endvalue?.getVec3() ?? .one
    }
    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        for i in 0..<count {
            if !particles[i].alive { continue }
            let life = particles[i].lifetimePos
            var col = SIMD3<Float>.zero
            col.x = ParticleMath.fadeValue(
                life: life,
                startTime: startTime,
                endTime: endTime,
                startValue: startValue.x,
                endValue: endValue.x
            )
            col.y = ParticleMath.fadeValue(
                life: life,
                startTime: startTime,
                endTime: endTime,
                startValue: startValue.y,
                endValue: endValue.y
            )
            col.z = ParticleMath.fadeValue(
                life: life,
                startTime: startTime,
                endTime: endTime,
                startValue: startValue.z,
                endValue: endValue.z
            )
            particles[i].color = particles[i].initial.color * col
        }
    }
}

class TurbulenceOperator: ParticleOperator {
    let scale: Float
    let speedMin: Float
    let speedMax: Float
    let timeScale: Float
    let mask: SIMD3<Float>
    let phaseMin: Float
    let phaseMax: Float

    init(def: ParticleOperatorDef) {
        self.scale = def.scale?.getFloat() ?? 0.005
        self.speedMin = def.speedmin?.getFloat() ?? 500.0
        self.speedMax = def.speedmax?.getFloat() ?? 1000.0
        self.timeScale = def.timescale?.getFloat() ?? 0.01
        self.mask = def.mask?.getVec3() ?? SIMD3<Float>(1, 1, 0)
        self.phaseMin = def.phasemin?.getFloat() ?? 0.0
        self.phaseMax = def.phasemax?.getFloat() ?? 0.0
    }

    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        let phase = ParticleMath.randomFloat(min: phaseMin, max: phaseMax)
        let turbSpeed = ParticleMath.randomFloat(min: speedMin, max: speedMax)
        let noiseScale = scale * 2.0
        let speedOver = instanceOverride?.speed ?? 1.0

        if turbSpeed <= 0.0001 { return }

        for i in 0..<count {
            if !particles[i].alive { continue }
            var noisePos = particles[i].position
            noisePos.x += phase + timeScale * currentTime
            noisePos *= noiseScale

            var curlDir = ParticleMath.curlNoise(p: noisePos)
            let len = length(curlDir)
            if len > 0.0001 {
                curlDir = (curlDir / len) * turbSpeed
            }
            curlDir *= mask
            particles[i].velocity += curlDir * dt * speedOver
        }
    }
}

class VortexOperator: ParticleOperator {
    let controlPoint: Int
    let flags: Int
    let axis: SIMD3<Float>
    let offset: SIMD3<Float>
    let distanceInner: Float
    let distanceOuter: Float
    let speedInner: Float
    let speedOuter: Float
    let centerForce: Float
    let ringRadius: Float
    let ringWidth: Float
    let ringPullDistance: Float
    let ringPullForce: Float

    init(def: ParticleOperatorDef) {
        self.controlPoint = def.controlpoint ?? 0
        self.flags = def.flags ?? 0
        self.axis = def.axis?.getVec3() ?? SIMD3<Float>(0, 0, 1)
        self.offset = def.offset?.getVec3() ?? .zero
        self.distanceInner = def.distanceinner?.getFloat() ?? 500.0
        self.distanceOuter = def.distanceouter?.getFloat() ?? 650.0
        self.speedInner = def.speedinner?.getFloat() ?? 2500.0
        self.speedOuter = def.speedouter?.getFloat() ?? 0.0
        self.centerForce = def.centerforce?.getFloat() ?? 1.0
        self.ringRadius = def.ringradius?.getFloat() ?? 300.0
        self.ringWidth = def.ringwidth?.getFloat() ?? 50.0
        self.ringPullDistance = def.ringpulldistance?.getFloat() ?? 50.0
        self.ringPullForce = def.ringpullforce?.getFloat() ?? 10.0
    }

    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        let infiniteAxis = (flags & 1) != 0
        let maintainDistance = (flags & 2) != 0
        let ringShape = (flags & 4) != 0
        let speedOver = instanceOverride?.speed ?? 1.0

        var ax = axis
        if length(ax) > 0.0 {
            ax = normalize(ax)
        } else {
            ax = SIMD3<Float>(0, 0, 1)
        }

        var center = offset
        if controlPoint >= 0 && controlPoint < controlPoints.count {
            center = controlPoints[controlPoint].position + offset
        }

        for i in 0..<count {
            if !particles[i].alive { continue }
            let toParticle = particles[i].position - center
            var radialVector = toParticle

            if infiniteAxis {
                let axialDistance = dot(toParticle, ax)
                radialVector = toParticle - ax * axialDistance
            }

            let dist = length(radialVector)
            var tangent = cross(ax, radialVector)
            if length(tangent) > 0.001 {
                tangent = normalize(tangent)
            } else {
                continue
            }

            var sp: Float = 0.0
            var radialForce = SIMD3<Float>.zero

            if ringShape {
                let ringInner = ringRadius - ringWidth * 0.5
                let ringOuter = ringRadius + ringWidth * 0.5
                if dist < ringInner {
                    sp = 0.0
                } else if dist <= ringOuter {
                    let t = (dist - ringInner) / ringWidth
                    sp = ParticleMath.lerp(t: t, a: speedInner, b: speedOuter)
                } else if dist <= ringOuter + ringPullDistance {
                    let pullT = (dist - ringOuter) / ringPullDistance
                    sp = speedOuter * (1.0 - pullT)
                    if dist > 0.001 {
                        let towardRing = -normalize(radialVector)
                        radialForce = towardRing * ringPullForce * pullT
                    }
                }
            } else {
                let disMid = distanceOuter - distanceInner + 0.1
                if disMid < 0 || dist < distanceInner {
                    sp = speedInner
                } else if dist > distanceOuter {
                    sp = speedOuter
                } else {
                    let t = (dist - distanceInner) / disMid
                    sp = ParticleMath.lerp(t: t, a: speedInner, b: speedOuter)
                }
            }

            particles[i].velocity += tangent * sp * dt * speedOver
            particles[i].velocity += radialForce * dt * speedOver

            if maintainDistance && dist > 0.001 {
                let towardCenter = -normalize(radialVector)
                particles[i].velocity +=
                    towardCenter * centerForce * dt * speedOver
            }
        }
    }
}

class ControlPointAttractOperator: ParticleOperator {
    let controlPoint: Int
    let origin: SIMD3<Float>
    let scale: Float
    let threshold: Float

    init(def: ParticleOperatorDef) {
        self.controlPoint = def.controlpoint ?? 0
        self.origin = def.origin?.getVec3() ?? .zero
        self.scale = def.scale?.getFloat() ?? 100.0
        self.threshold = (def.threshold?.getFloat() ?? 1000.0) / 2.0
    }

    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        if controlPoint < 0 || controlPoint >= controlPoints.count { return }
        let center = controlPoints[controlPoint].position + origin
        let speedOver = instanceOverride?.speed ?? 1.0

        for i in 0..<count {
            if !particles[i].alive { continue }
            let toCenter = center - particles[i].position
            let dist = length(toCenter)
            if dist > 0.001 && dist < threshold {
                let dir = toCenter / dist
                particles[i].velocity += dir * scale * dt * speedOver
            }
        }
    }
}

class OscillateAlphaOperator: ParticleOperator {
    let freqMin: Float
    let freqMax: Float
    let scaleMin: Float
    let scaleMax: Float
    let phaseMin: Float
    let phaseMax: Float

    init(def: ParticleOperatorDef) {
        self.freqMin = def.frequencymin?.getFloat() ?? 0.0
        self.freqMax = def.frequencymax?.getFloat() ?? 10.0
        self.scaleMin = def.scalemin?.getFloat() ?? 0.0
        self.scaleMax = def.scalemax?.getFloat() ?? 1.0
        self.phaseMin = def.phasemin?.getFloat() ?? 0.0
        self.phaseMax = def.phasemax?.getFloat() ?? Float.pi * 2.0
    }

    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        for i in 0..<count {
            if !particles[i].oscillateAlpha.initialized {
                particles[i].oscillateAlpha.frequency =
                    ParticleMath.randomFloat(min: freqMin, max: freqMax)
                particles[i].oscillateAlpha.scale = ParticleMath.randomFloat(
                    min: scaleMin,
                    max: scaleMax
                )
                particles[i].oscillateAlpha.phase = ParticleMath.randomFloat(
                    min: phaseMin,
                    max: phaseMax + Float.pi * 2.0
                )
                particles[i].oscillateAlpha.base = particles[i].alpha
                particles[i].oscillateAlpha.initialized = true
            }
            let w = particles[i].oscillateAlpha.frequency
            let t = particles[i].age
            let cosVal =
                (cos(w * t + particles[i].oscillateAlpha.phase) + 1.0) * 0.5
            let mul = ParticleMath.lerp(t: cosVal, a: scaleMin, b: scaleMax)
            particles[i].alpha = particles[i].oscillateAlpha.base * mul
        }
    }
}

class OscillateSizeOperator: ParticleOperator {
    let freqMin: Float
    let freqMax: Float
    let scaleMin: Float
    let scaleMax: Float
    let phaseMin: Float
    let phaseMax: Float

    init(def: ParticleOperatorDef) {
        self.freqMin = def.frequencymin?.getFloat() ?? 0.0
        self.freqMax = def.frequencymax?.getFloat() ?? 10.0
        self.scaleMin = def.scalemin?.getFloat() ?? 0.8
        self.scaleMax = def.scalemax?.getFloat() ?? 1.2
        self.phaseMin = def.phasemin?.getFloat() ?? 0.0
        self.phaseMax = def.phasemax?.getFloat() ?? Float.pi * 2.0
    }

    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        for i in 0..<count {
            if !particles[i].oscillateSize.initialized {
                particles[i].oscillateSize.frequency = ParticleMath.randomFloat(
                    min: freqMin,
                    max: freqMax
                )
                particles[i].oscillateSize.scale = ParticleMath.randomFloat(
                    min: scaleMin,
                    max: scaleMax
                )
                particles[i].oscillateSize.phase = ParticleMath.randomFloat(
                    min: phaseMin,
                    max: phaseMax + Float.pi * 2.0
                )
                particles[i].oscillateSize.base = particles[i].size
                particles[i].oscillateSize.initialized = true
            }
            let w = particles[i].oscillateSize.frequency
            let t = particles[i].age
            let cosVal =
                (cos(w * t + particles[i].oscillateSize.phase) + 1.0) * 0.5
            let mul = ParticleMath.lerp(t: cosVal, a: scaleMin, b: scaleMax)
            particles[i].size = particles[i].oscillateSize.base * mul
        }
    }
}

class OscillatePositionOperator: ParticleOperator {
    let freqMin: Float
    let freqMax: Float
    let scaleMin: Float
    let scaleMax: Float
    let phaseMin: Float
    let phaseMax: Float
    let mask: SIMD3<Float>

    init(def: ParticleOperatorDef) {
        self.freqMin = def.frequencymin?.getFloat() ?? 0.0
        self.freqMax = def.frequencymax?.getFloat() ?? 5.0
        self.scaleMin = def.scalemin?.getFloat() ?? 0.0
        self.scaleMax = def.scalemax?.getFloat() ?? 10.0
        self.phaseMin = def.phasemin?.getFloat() ?? 0.0
        self.phaseMax = def.phasemax?.getFloat() ?? Float.pi * 2.0
        self.mask = def.mask?.getVec3() ?? SIMD3<Float>(1, 1, 0)
    }

    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        let speedOver = instanceOverride?.speed ?? 1.0
        for i in 0..<count {
            if !particles[i].oscillatePosition.initialized {
                for axis in 0..<3 {
                    particles[i].oscillatePosition.frequency[axis] =
                        ParticleMath.randomFloat(min: freqMin, max: freqMax)
                    particles[i].oscillatePosition.scale[axis] =
                        ParticleMath.randomFloat(min: scaleMin, max: scaleMax)
                    particles[i].oscillatePosition.phase[axis] =
                        ParticleMath.randomFloat(
                            min: phaseMin,
                            max: phaseMax + Float.pi * 2.0
                        )
                }
                particles[i].oscillatePosition.initialized = true
            }
            let t = particles[i].age
            var delta = SIMD3<Float>.zero
            for axis in 0..<3 {
                let w = particles[i].oscillatePosition.frequency[axis]
                let move =
                    -particles[i].oscillatePosition.scale[axis] * w
                    * sin(w * t + particles[i].oscillatePosition.phase[axis])
                    * dt
                delta[axis] = move * mask[axis] * speedOver
            }
            particles[i].position += delta
        }
    }
}
