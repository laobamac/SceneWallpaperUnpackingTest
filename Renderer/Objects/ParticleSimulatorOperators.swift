//
//  ParticleSimulatorOperators.swift
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

import Foundation
import simd

extension ParticleSimulator {
    func setupOperators() {
        guard let ops = particleDefinition.`operator` else { return }
        for o in ops {
            let name = o.name ?? ""
            if name == "movement" {
                operators.append(createMovementOperator(o))
            } else if name == "angularmovement" {
                operators.append(createAngularMovementOperator(o))
            } else if name == "alphafade" {
                operators.append(createAlphaFadeOperator(o))
            } else if name == "sizechange" {
                operators.append(createSizeChangeOperator(o))
            } else if name == "alphachange" {
                operators.append(createAlphaChangeOperator(o))
            } else if name == "colorchange" {
                operators.append(createColorChangeOperator(o))
            } else if name == "turbulence" {
                operators.append(createTurbulenceOperator(o))
            } else if name == "vortex" || name == "vortex_v2" {
                operators.append(createVortexOperator(o))
            } else if name == "controlpointattract" {
                operators.append(createControlPointAttractOperator(o))
            } else if name == "oscillatealpha" {
                operators.append(createOscillateAlphaOperator(o))
            } else if name == "oscillatesize" {
                operators.append(createOscillateSizeOperator(o))
            } else if name == "oscillateposition" {
                operators.append(createOscillatePositionOperator(o))
            }
        }
    }

    private func lerp(t: Float, a: Float, b: Float) -> Float {
        return a + t * (b - a)
    }

    private func fadeValue(life: Float, startTime: Float, endTime: Float, startValue: Float, endValue: Float) -> Float {
        if life <= startTime {
            return startValue
        } else if life >= endTime {
            return endValue
        } else {
            let t = (life - startTime) / (endTime - startTime)
            return lerp(t: t, a: startValue, b: endValue)
        }
    }

    private func createMovementOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let drag = opData.drag?.floatValue ?? 0.0
        var gravity = opData.gravity?.float3Value ?? .zero
        gravity.y = -gravity.y
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        return { (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            for i in 0..<count {
                if !particles[i].alive { continue }
                particles[i].position += particles[i].velocity * dt
                particles[i].velocity += gravity * dt * overrideV
                var dragFactor = 1.0 - (drag * dt)
                if dragFactor < 0.0 { dragFactor = 0.0 }
                particles[i].velocity *= dragFactor
            }
        }
    }

    private func createAngularMovementOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let drag = opData.drag?.floatValue ?? 0.0
        let force = opData.force?.float3Value ?? .zero
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        return { (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            for i in 0..<count {
                if !particles[i].alive { continue }
                particles[i].rotation += particles[i].angularVelocity * dt * overrideV
                particles[i].angularVelocity += force * dt * overrideV
                var dragFactor = 1.0 - (drag * dt)
                if dragFactor < 0.0 { dragFactor = 0.0 }
                particles[i].angularVelocity *= dragFactor

                let pi = Float.pi
                let twoPi = 2.0 * Float.pi
                for j in 0..<3 {
                    while particles[i].rotation[j] > pi { particles[i].rotation[j] -= twoPi }
                    while particles[i].rotation[j] < -pi { particles[i].rotation[j] += twoPi }
                }
            }
        }
    }

    private func createAlphaFadeOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let fadeInTime = opData.fadeintime?.floatValue ?? 0.5
        let fadeOutTime = opData.fadeouttime?.floatValue ?? 0.5

        return { [weak self] (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                if life <= fadeInTime {
                    let fade = self.fadeValue(life: life, startTime: 0.0, endTime: fadeInTime, startValue: 0.0, endValue: 1.0)
                    particles[i].alpha = particles[i].initial.alpha * fade
                } else if life > fadeOutTime {
                    let fade = 1.0 - self.fadeValue(life: life, startTime: fadeOutTime, endTime: 1.0, startValue: 0.0, endValue: 1.0)
                    particles[i].alpha = particles[i].initial.alpha * fade
                } else {
                    particles[i].alpha = particles[i].initial.alpha
                }
                particles[i].oscillateAlpha.base = particles[i].alpha
            }
        }
    }

    private func createSizeChangeOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let startTime = opData.starttime?.floatValue ?? 0.0
        let endTime = opData.endtime?.floatValue ?? 1.0
        let startValue = opData.startvalue?.floatValue ?? 1.0
        let endValue = opData.endvalue?.floatValue ?? 0.0

        return { [weak self] (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                let multiplier = self.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: startValue, endValue: endValue)
                particles[i].size = particles[i].initial.size * multiplier
                particles[i].oscillateSize.base = particles[i].size
            }
        }
    }

    private func createAlphaChangeOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let startTime = opData.starttime?.floatValue ?? 0.0
        let endTime = opData.endtime?.floatValue ?? 1.0
        let startValue = opData.startvalue?.floatValue ?? 1.0
        let endValue = opData.endvalue?.floatValue ?? 0.0

        return { [weak self] (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                let multiplier = self.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: startValue, endValue: endValue)
                particles[i].alpha = particles[i].initial.alpha * multiplier
                particles[i].oscillateAlpha.base = particles[i].alpha
            }
        }
    }

    private func createColorChangeOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let startTime = opData.starttime?.floatValue ?? 0.0
        let endTime = opData.endtime?.floatValue ?? 1.0
        let startValue = opData.startvalue?.float3Value ?? SIMD3<Float>(1.0, 1.0, 1.0)
        let endValue = opData.endvalue?.float3Value ?? SIMD3<Float>(1.0, 1.0, 1.0)

        return { [weak self] (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                var color = SIMD3<Float>()
                color.x = self.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: startValue.x, endValue: endValue.x)
                color.y = self.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: startValue.y, endValue: endValue.y)
                color.z = self.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: startValue.z, endValue: endValue.z)
                particles[i].color = particles[i].initial.color * color
            }
        }
    }

    private func createTurbulenceOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let scale = opData.scale?.floatValue ?? 0.005
        let speedMin = opData.speedmin?.floatValue ?? 500.0
        let speedMax = opData.speedmax?.floatValue ?? 1000.0
        let timeScale = opData.timescale?.floatValue ?? 0.01
        let mask = opData.mask?.float3Value ?? SIMD3<Float>(1.0, 1.0, 0.0)
        let phaseMin = opData.phasemin?.floatValue ?? 0.0
        let phaseMax = opData.phasemax?.floatValue ?? 0.0
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        let phase = Float.random(in: min(phaseMin, phaseMax)...max(phaseMin, phaseMax))
        let turbSpeed = Float.random(in: min(speedMin, speedMax)...max(speedMin, speedMax))
        let noiseScale = scale * 2.0

        return { (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            if turbSpeed <= 0.0001 { return }
            for i in 0..<count {
                if !particles[i].alive { continue }
                var noisePos = particles[i].position
                noisePos.x += phase + timeScale * time
                noisePos *= noiseScale
                var curlDir = NoiseUtils.curlNoise(noisePos)
                let len = length(curlDir)
                if len > 0.0001 {
                    curlDir = (curlDir / len) * turbSpeed
                }
                curlDir *= mask
                particles[i].velocity += curlDir * dt * overrideV
            }
        }
    }

    private func createVortexOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let controlPoint = opData.controlpoint ?? 0
        let flags = opData.flags ?? 0
        var axis = opData.axis?.float3Value ?? SIMD3<Float>(0.0, 0.0, 1.0)
        let offset = opData.offset?.float3Value ?? .zero
        let distanceInner = opData.distanceinner?.floatValue ?? 500.0
        let distanceOuter = opData.distanceouter?.floatValue ?? 650.0
        let speedInner = opData.speedinner?.floatValue ?? 2500.0
        let speedOuter = opData.speedouter?.floatValue ?? 0.0
        let centerForce = opData.centerforce?.floatValue ?? 1.0
        let ringRadius = opData.ringradius?.floatValue ?? 300.0
        let ringWidth = opData.ringwidth?.floatValue ?? 50.0
        let ringPullDistance = opData.ringpulldistance?.floatValue ?? 50.0
        let ringPullForce = opData.ringpullforce?.floatValue ?? 10.0
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        let infiniteAxis = (flags & 1) != 0
        let maintainDistance = (flags & 2) != 0
        let ringShape = (flags & 4) != 0

        if length(axis) > 0.0 { axis = normalize(axis) }
        else { axis = SIMD3<Float>(0.0, 0.0, 1.0) }

        return { (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            var center = SIMD3<Float>(0.0, 0.0, 0.0)
            if controlPoint >= 0 && controlPoint < controlPoints.count {
                center = controlPoints[controlPoint].position + offset
            } else {
                center = offset
            }

            for i in 0..<count {
                if !particles[i].alive { continue }
                let toParticle = particles[i].position - center
                var radialVector = toParticle
                if infiniteAxis {
                    let axialDistance = dot(toParticle, axis)
                    radialVector = toParticle - axis * axialDistance
                }
                let dist = length(radialVector)
                var tangent = cross(axis, radialVector)
                if length(tangent) > 0.001 {
                    tangent = normalize(tangent)
                } else {
                    continue
                }

                var speed: Float = 0.0
                var radialForce = SIMD3<Float>(0.0, 0.0, 0.0)

                if ringShape {
                    let ringInner = ringRadius - ringWidth * 0.5
                    let ringOuter = ringRadius + ringWidth * 0.5
                    if dist < ringInner {
                        speed = 0.0
                    } else if dist <= ringOuter {
                        let t = (dist - ringInner) / ringWidth
                        speed = speedInner + t * (speedOuter - speedInner)
                    } else if dist <= ringOuter + ringPullDistance {
                        let pullT = (dist - ringOuter) / ringPullDistance
                        speed = speedOuter * (1.0 - pullT)
                        if dist > 0.001 {
                            let towardRing = -normalize(radialVector)
                            radialForce = towardRing * ringPullForce * pullT
                        }
                    } else {
                        speed = 0.0
                    }
                } else {
                    let disMid = distanceOuter - distanceInner + 0.1
                    if disMid < 0 || dist < distanceInner {
                        speed = speedInner
                    } else if dist > distanceOuter {
                        speed = speedOuter
                    } else {
                        let t = (dist - distanceInner) / disMid
                        speed = speedInner + t * (speedOuter - speedInner)
                    }
                }

                particles[i].velocity += tangent * speed * dt * overrideV
                particles[i].velocity += radialForce * dt * overrideV

                if maintainDistance && dist > 0.001 {
                    let towardCenter = -normalize(radialVector)
                    particles[i].velocity += towardCenter * centerForce * dt * overrideV
                }
            }
        }
    }

    private func createControlPointAttractOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let controlPoint = opData.controlpoint ?? 0
        let origin = opData.origin?.float3Value ?? .zero
        let scale = opData.scale?.floatValue ?? 100.0
        let threshold = (opData.threshold?.floatValue ?? 1000.0) / 2.0
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        return { (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            if controlPoint < 0 || controlPoint >= controlPoints.count { return }
            let center = controlPoints[controlPoint].position + origin

            for i in 0..<count {
                if !particles[i].alive { continue }
                let toCenter = center - particles[i].position
                let dist = length(toCenter)
                if dist > 0.001 && dist < threshold {
                    let direction = toCenter / dist
                    let forceVec = direction * scale * dt
                    particles[i].velocity += forceVec * overrideV
                }
            }
        }
    }

    private func createOscillateAlphaOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let freqMin = opData.frequencymin?.floatValue ?? 0.0
        let freqMax = opData.frequencymax?.floatValue ?? 10.0
        let scaleMin = opData.scalemin?.floatValue ?? 0.0
        let scaleMax = opData.scalemax?.floatValue ?? 1.0
        let phaseMin = opData.phasemin?.floatValue ?? 0.0
        let phaseMax = opData.phasemax?.floatValue ?? (2.0 * Float.pi)

        return { [weak self] (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].oscillateAlpha.initialized {
                    particles[i].oscillateAlpha.frequency = Float.random(in: min(freqMin, freqMax)...max(freqMin, freqMax))
                    particles[i].oscillateAlpha.scale = Float.random(in: min(scaleMin, scaleMax)...max(scaleMin, scaleMax))
                    let p2 = phaseMax + 2.0 * Float.pi
                    particles[i].oscillateAlpha.phase = Float.random(in: min(phaseMin, p2)...max(phaseMin, p2))
                    particles[i].oscillateAlpha.base = particles[i].alpha
                    particles[i].oscillateAlpha.initialized = true
                }
                let w = particles[i].oscillateAlpha.frequency
                let t = particles[i].age
                let cosVal = (cos(w * t + particles[i].oscillateAlpha.phase) + 1.0) * 0.5
                let multiplier = self.lerp(t: cosVal, a: scaleMin, b: scaleMax)
                particles[i].alpha = particles[i].oscillateAlpha.base * multiplier
            }
        }
    }

    private func createOscillateSizeOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let freqMin = opData.frequencymin?.floatValue ?? 0.0
        let freqMax = opData.frequencymax?.floatValue ?? 10.0
        let scaleMin = opData.scalemin?.floatValue ?? 0.8
        let scaleMax = opData.scalemax?.floatValue ?? 1.2
        let phaseMin = opData.phasemin?.floatValue ?? 0.0
        let phaseMax = opData.phasemax?.floatValue ?? (2.0 * Float.pi)

        return { [weak self] (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].oscillateSize.initialized {
                    particles[i].oscillateSize.frequency = Float.random(in: min(freqMin, freqMax)...max(freqMin, freqMax))
                    particles[i].oscillateSize.scale = Float.random(in: min(scaleMin, scaleMax)...max(scaleMin, scaleMax))
                    let p2 = phaseMax + 2.0 * Float.pi
                    particles[i].oscillateSize.phase = Float.random(in: min(phaseMin, p2)...max(phaseMin, p2))
                    particles[i].oscillateSize.base = particles[i].size
                    particles[i].oscillateSize.initialized = true
                }
                let w = particles[i].oscillateSize.frequency
                let t = particles[i].age
                let cosVal = (cos(w * t + particles[i].oscillateSize.phase) + 1.0) * 0.5
                let multiplier = self.lerp(t: cosVal, a: scaleMin, b: scaleMax)
                particles[i].size = particles[i].oscillateSize.base * multiplier
            }
        }
    }

    private func createOscillatePositionOperator(_ opData: ParticleOperator) -> OperatorFunc {
        let freqMin = opData.frequencymin?.floatValue ?? 0.0
        let freqMax = opData.frequencymax?.floatValue ?? 5.0
        let scaleMin = opData.scalemin?.floatValue ?? 0.0
        let scaleMax = opData.scalemax?.floatValue ?? 10.0
        let phaseMin = opData.phasemin?.floatValue ?? 0.0
        let phaseMax = opData.phasemax?.floatValue ?? (2.0 * Float.pi)
        let mask = opData.mask?.float3Value ?? SIMD3<Float>(1.0, 1.0, 0.0)
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        return { (particles: inout [ParticleInstance], count: Int, controlPoints: [ControlPointData], time: Float, dt: Float) in
            for i in 0..<count {
                if !particles[i].oscillatePosition.initialized {
                    for axis in 0..<3 {
                        particles[i].oscillatePosition.frequency[axis] = Float.random(in: min(freqMin, freqMax)...max(freqMin, freqMax))
                        particles[i].oscillatePosition.scale[axis] = Float.random(in: min(scaleMin, scaleMax)...max(scaleMin, scaleMax))
                        let p2 = phaseMax + 2.0 * Float.pi
                        particles[i].oscillatePosition.phase[axis] = Float.random(in: min(phaseMin, p2)...max(phaseMin, p2))
                    }
                    particles[i].oscillatePosition.initialized = true
                }
                let t = particles[i].age
                var delta = SIMD3<Float>(0.0, 0.0, 0.0)
                for axis in 0..<3 {
                    let w = 2.0 * Float.pi * particles[i].oscillatePosition.frequency[axis] / (2.0 * Float.pi)
                    let move = -particles[i].oscillatePosition.scale[axis] * w * sin(w * t + particles[i].oscillatePosition.phase[axis]) * dt
                    delta[axis] = move * mask[axis] * overrideV
                }
                particles[i].position += delta
            }
        }
    }
}
