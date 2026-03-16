//
//  ParticleRenderableEmitters.swift
//  Renderer
//
//  Created by laobamac on 2026/3/17.
//

import Foundation
import simd

extension ParticleRenderable {

    func setupEmitters() {
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
        let rate = emitter.rate * (particleDef.instanceOverride?.rate?.value?.floatValue ?? 1.0)
        var transformedEmitterOrigin = emitter.origin
        transformedEmitterOrigin.y = -transformedEmitterOrigin.y

        var controlPointIndex = emitter.controlPoint
        if controlPointIndex == -1, let cps = particleDef.controlPoints, !cps.isEmpty {
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
                        periodicDuration = Float.random(in: emitter.minPeriodicDuration...emitter.maxPeriodicDuration, using: &self.rng)
                    } else {
                        return
                    }
                } else {
                    if periodicTimer >= periodicDuration {
                        emitting = false
                        periodicTimer = 0.0
                        periodicDelay = Float.random(in: emitter.minPeriodicDelay...emitter.maxPeriodicDelay, using: &self.rng)
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
                if controlPointIndex >= 0 && controlPointIndex < self.controlPoints.count {
                    spawnOrigin += self.controlPoints[controlPointIndex].position
                }

                var randomPos = simd_float3(0, 0, 0)
                let dMin = [emitter.distanceMin.x, emitter.distanceMin.y, emitter.distanceMin.z]
                let dMax = [emitter.distanceMax.x, emitter.distanceMax.y, emitter.distanceMax.z]

                for axis in 0..<3 {
                    let minDist = dMin[axis]
                    let maxDist = dMax[axis]
                    var dist = Float.random(in: minDist...maxDist, using: &self.rng)
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

                particles[count].color = simd_float3(1, 1, 1) * (self.particleDef.instanceOverride?.colorn?.value?.vec3Value ?? simd_float3(1, 1, 1))
                particles[count].alpha = 1.0 * (self.particleDef.instanceOverride?.alpha?.value?.floatValue ?? 1.0)
                particles[count].size = 20.0 * (self.particleDef.instanceOverride?.size?.value?.floatValue ?? 1.0)
                particles[count].lifetime = 1.0 * (self.particleDef.instanceOverride?.lifetime?.value?.floatValue ?? 1.0)
                particles[count].age = 0.0
                particles[count].alive = true
                particles[count].frame = -1.0

                particles[count].initial.color = particles[count].color
                particles[count].initial.alpha = particles[count].alpha
                particles[count].initial.size = particles[count].size
                particles[count].initial.lifetime = particles[count].lifetime

                particles[count].oscillateAlpha = ParticleInstance.Oscillator()
                particles[count].oscillateSize = ParticleInstance.Oscillator()
                particles[count].oscillatePosition = ParticleInstance.PositionOscillator()

                for initFunc in self.initializers {
                    initFunc(&particles[count])
                }

                count += 1
            }
        }
    }

    private func createSphereEmitter(emitter: ParticleEmitter) -> EmitterFunc {
        let rate = emitter.rate * (particleDef.instanceOverride?.rate?.value?.floatValue ?? 1.0)
        let lifetime = 1.0 * (particleDef.instanceOverride?.lifetime?.value?.floatValue ?? 1.0)
        var transformedEmitterOrigin = emitter.origin
        transformedEmitterOrigin.y = -transformedEmitterOrigin.y

        var controlPointIndex = emitter.controlPoint
        if controlPointIndex == -1, let cps = particleDef.controlPoints, !cps.isEmpty {
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
                if controlPointIndex >= 0 && controlPointIndex < self.controlPoints.count {
                    spawnOrigin += self.controlPoints[controlPointIndex].position
                }

                var randomPos = simd_float3(0, 0, 0)

                if (self.particleDef.flags ?? 0) & 4 == 0 {
                    let angle = Float.random(in: 0...(2 * .pi), using: &self.rng)
                    let minRadius = emitter.distanceMin.x
                    let maxRadius = emitter.distanceMax.x
                    let minRadiusSq = minRadius * minRadius
                    let maxRadiusSq = maxRadius * maxRadius
                    let radiusXY = sqrt(Float.random(in: minRadiusSq...maxRadiusSq, using: &self.rng))

                    randomPos = simd_float3(
                        radiusXY * cos(angle),
                        radiusXY * sin(angle),
                        Float.random(in: -maxRadius...maxRadius, using: &self.rng)
                    )
                    randomPos *= emitter.directions
                } else {
                    let theta = Float.random(in: 0...(2 * .pi), using: &self.rng)
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
                    let radius = cbrt(Float.random(in: minRadiusCubed...maxRadiusCubed, using: &self.rng))

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
                    let direction = length(randomPos) > 0.0 ? normalize(randomPos) : simd_float3(0, 1, 0)
                    let speed = Float.random(in: emitter.speedMin...emitter.speedMax, using: &self.rng)
                    particles[count].velocity = direction * speed
                } else {
                    particles[count].velocity = .zero
                }

                particles[count].acceleration = .zero
                particles[count].rotation = .zero
                particles[count].angularVelocity = .zero
                particles[count].angularAcceleration = .zero

                particles[count].color = simd_float3(1, 1, 1) * (self.particleDef.instanceOverride?.colorn?.value?.vec3Value ?? simd_float3(1, 1, 1))
                particles[count].alpha = 1.0 * (self.particleDef.instanceOverride?.alpha?.value?.floatValue ?? 1.0)
                particles[count].size = 20.0 * (self.particleDef.instanceOverride?.size?.value?.floatValue ?? 1.0)
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
                particles[count].oscillatePosition = ParticleInstance.PositionOscillator()

                for initFunc in self.initializers {
                    initFunc(&particles[count])
                }

                count += 1
            }
        }
    }
}
