//
//  ParticleSimulatorEmitters.swift
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

import Foundation
import simd

extension ParticleSimulator {
    func setupEmitters() {
        guard let ems = particleDefinition.emitter else { return }
        for e in ems {
            let name = e.name ?? ""
            if name == "boxrandom" {
                emitters.append(createBoxEmitter(e))
            } else if name == "sphererandom" {
                emitters.append(createSphereEmitter(e))
            }
        }
    }

    func createBoxEmitter(_ emitter: ParticleEmitter) -> EmitterFunc {
        let rateBase = emitter.rate ?? 10.0
        let rateOverride = instanceOverride?.rate?.floatValue ?? 1.0
        let rate = rateBase * rateOverride

        var transformedEmitterOrigin = emitter.origin?.float3Value ?? .zero
        transformedEmitterOrigin.y = -transformedEmitterOrigin.y

        var controlPointIndex = emitter.controlpoint ?? -1
        if controlPointIndex == -1 && !controlPoints.isEmpty {
            if controlPoints[0].linkMouse {
                controlPointIndex = 0
            }
        }

        var flippedDirections = emitter.directions?.float3Value ?? SIMD3<Float>(1.0, 1.0, 0.0)
        flippedDirections.y = -flippedDirections.y

        let flags = emitter.flags ?? 0
        let limitOnePerFrame = (flags & 2) != 0
        let randomPeriodicEmission = (flags & 4) != 0

        var emissionTimer: Float = 0.0
        var delayTimer: Float = emitter.delay ?? 0.0
        let duration: Float = emitter.duration ?? 0.0
        var durationTimer: Float = 0.0
        var periodicTimer: Float = 0.0
        var periodicDuration: Float = 0.0
        var periodicDelay: Float = 0.0
        var emitting: Bool = false
        var instantaneousEmitted: Bool = false

        let dMin = emitter.distancemin?.float3Value ?? .zero
        let dMax = emitter.distancemax?.float3Value ?? SIMD3<Float>(256.0, 256.0, 0.0)
        let inst = emitter.instantaneous ?? 0

        let colornOverride = instanceOverride?.colorn?.float3Value ?? .one
        let alphaOverride = instanceOverride?.alpha?.floatValue ?? 1.0
        let sizeOverride = instanceOverride?.size?.floatValue ?? 1.0
        let lifetimeOverride = instanceOverride?.lifetime?.floatValue ?? 1.0

        let minPDur = emitter.minperiodicduration ?? 2.0
        let maxPDur = emitter.maxperiodicduration ?? 3.0
        let minPDel = emitter.minperiodicdelay ?? 1.0
        let maxPDel = emitter.maxperiodicdelay ?? 2.0

        return { [weak self] (particles: inout [ParticleInstance], count: inout Int, dt: Float) in
            guard let self = self else { return }
            if count >= particles.count { return }

            if delayTimer > 0.0 {
                delayTimer -= dt
                return
            }

            if duration > 0.0 {
                durationTimer += dt
                if durationTimer >= duration { return }
            }

            if randomPeriodicEmission {
                periodicTimer += dt
                if !emitting {
                    if periodicTimer >= periodicDelay {
                        emitting = true
                        periodicTimer = 0.0
                        periodicDuration = Float.random(in: min(minPDur, maxPDur)...max(minPDur, maxPDur))
                    } else {
                        return
                    }
                } else {
                    if periodicTimer >= periodicDuration {
                        emitting = false
                        periodicTimer = 0.0
                        periodicDelay = Float.random(in: min(minPDel, maxPDel)...max(minPDel, maxPDel))
                        return
                    }
                }
            }

            var toEmit: Int = 0
            if inst > 0 && !instantaneousEmitted {
                toEmit = inst
                instantaneousEmitted = true
            }

            if rateBase > 0.0 {
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
                if controlPointIndex >= 0 && controlPointIndex < self.controlPoints.count {
                    spawnOrigin += self.controlPoints[controlPointIndex].position
                }

                var randomPos = SIMD3<Float>()
                for axis in 0..<3 {
                    let v1 = dMin[axis]
                    let v2 = dMax[axis]
                    var dist = Float.random(in: min(v1, v2)...max(v1, v2))
                    if Bool.random() { dist = -dist }
                    randomPos[axis] = dist
                }
                randomPos *= flippedDirections

                particles[count].position = spawnOrigin + randomPos
                particles[count].velocity = .zero
                particles[count].acceleration = .zero
                particles[count].rotation = .zero
                particles[count].angularVelocity = .zero
                particles[count].angularAcceleration = .zero

                particles[count].color = colornOverride
                particles[count].alpha = alphaOverride
                particles[count].size = 20.0 * sizeOverride
                particles[count].lifetime = lifetimeOverride
                particles[count].age = 0.0
                particles[count].alive = true
                particles[count].frame = -1.0

                particles[count].initial.color = particles[count].color
                particles[count].initial.alpha = particles[count].alpha
                particles[count].initial.size = particles[count].size
                particles[count].initial.lifetime = particles[count].lifetime

                particles[count].oscillateAlpha = ParticleInstance.OscillatorAlpha()
                particles[count].oscillateSize = ParticleInstance.OscillatorSize()
                particles[count].oscillatePosition = ParticleInstance.OscillatorPosition()

                for initFunc in self.initializers {
                    initFunc(&particles[count])
                }

                count += 1
            }
        }
    }

    func createSphereEmitter(_ emitter: ParticleEmitter) -> EmitterFunc {
        let rateBase = emitter.rate ?? 10.0
        let rateOverride = instanceOverride?.rate?.floatValue ?? 1.0
        let rate = rateBase * rateOverride
        let lifetimeOverride = instanceOverride?.lifetime?.floatValue ?? 1.0

        var transformedEmitterOrigin = emitter.origin?.float3Value ?? .zero
        transformedEmitterOrigin.y = -transformedEmitterOrigin.y

        var controlPointIndex = emitter.controlpoint ?? -1
        if controlPointIndex == -1 && !controlPoints.isEmpty {
            if controlPoints[0].linkMouse {
                controlPointIndex = 0
            }
        }

        let flags = emitter.flags ?? 0
        let limitOnePerFrame = (flags & 2) != 0
        let is3D = ((particleDefinition.flags ?? 0) & 4) != 0

        var emissionTimer: Float = 0.0
        var remaining: Int = emitter.instantaneous ?? 0

        let dMin = emitter.distancemin?.float3Value ?? .zero
        let dMax = emitter.distancemax?.float3Value ?? SIMD3<Float>(256.0, 256.0, 0.0)
        let sgn = emitter.sign?.float3Value ?? .zero
        let directions = emitter.directions?.float3Value ?? SIMD3<Float>(1.0, 1.0, 0.0)
        let sMin = emitter.speedmin ?? 0.0
        let sMax = emitter.speedmax ?? 0.0

        let colornOverride = instanceOverride?.colorn?.float3Value ?? .one
        let alphaOverride = instanceOverride?.alpha?.floatValue ?? 1.0
        let sizeOverride = instanceOverride?.size?.floatValue ?? 1.0

        return { [weak self] (particles: inout [ParticleInstance], count: inout Int, dt: Float) in
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
                if controlPointIndex >= 0 && controlPointIndex < self.controlPoints.count {
                    spawnOrigin += self.controlPoints[controlPointIndex].position
                }

                var randomPos = SIMD3<Float>()
                if !is3D {
                    let angle = Float.random(in: 0...(2.0 * .pi))
                    let minRadius = dMin.x
                    let maxRadius = dMax.x
                    let minRadiusSq = minRadius * minRadius
                    let maxRadiusSq = maxRadius * maxRadius
                    let radiusXY = sqrt(Float.random(in: min(minRadiusSq, maxRadiusSq)...max(minRadiusSq, maxRadiusSq)))

                    randomPos = SIMD3<Float>(
                        radiusXY * cos(angle),
                        radiusXY * sin(angle),
                        Float.random(in: min(-dMax.z, dMax.z)...max(-dMax.z, dMax.z))
                    )
                    randomPos *= directions
                } else {
                    let theta = Float.random(in: 0...(2.0 * .pi))
                    let cosTheta = Float.random(in: -1.0...1.0)
                    let sinTheta = sqrt(1.0 - cosTheta * cosTheta)
                    randomPos = SIMD3<Float>(sinTheta * cos(theta), sinTheta * sin(theta), cosTheta)

                    let minRadius = dMin.x
                    let maxRadius = dMax.x
                    let minRadiusCubed = minRadius * minRadius * minRadius
                    let maxRadiusCubed = maxRadius * maxRadius * maxRadius
                    let radius = pow(Float.random(in: min(minRadiusCubed, maxRadiusCubed)...max(minRadiusCubed, maxRadiusCubed)), 1.0/3.0)

                    randomPos *= radius
                    randomPos *= directions
                }

                for i in 0..<3 {
                    if sgn[i] == 1.0 {
                        randomPos[i] = abs(randomPos[i])
                    } else if sgn[i] == -1.0 {
                        randomPos[i] = -abs(randomPos[i])
                    }
                }

                particles[count].position = spawnOrigin + randomPos

                if sMax > 0.0 || sMin != 0.0 {
                    let len = length(randomPos)
                    let direction = len > 0.0 ? (randomPos / len) : SIMD3<Float>(0.0, 1.0, 0.0)
                    let speed = Float.random(in: min(sMin, sMax)...max(sMin, sMax))
                    particles[count].velocity = direction * speed
                } else {
                    particles[count].velocity = .zero
                }

                particles[count].acceleration = .zero
                particles[count].rotation = .zero
                particles[count].angularVelocity = .zero
                particles[count].angularAcceleration = .zero

                particles[count].color = colornOverride
                particles[count].alpha = alphaOverride
                particles[count].size = 20.0 * sizeOverride
                particles[count].lifetime = lifetimeOverride
                particles[count].age = 0.0
                particles[count].alive = true
                particles[count].frame = -1.0

                particles[count].initial.color = particles[count].color
                particles[count].initial.alpha = particles[count].alpha
                particles[count].initial.size = particles[count].size
                particles[count].initial.lifetime = particles[count].lifetime

                particles[count].oscillateAlpha = ParticleInstance.OscillatorAlpha()
                particles[count].oscillateSize = ParticleInstance.OscillatorSize()
                particles[count].oscillatePosition = ParticleInstance.OscillatorPosition()

                for initFunc in self.initializers {
                    initFunc(&particles[count])
                }

                count += 1
            }
        }
    }
}
