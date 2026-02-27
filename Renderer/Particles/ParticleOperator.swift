//
//  ParticleOperator.swift
//  Renderer
//
//  Created by laobamac on 2026/2/27.
//

import simd

class MovementOperator: ParticleOperator {
    let drag: Float
    let gravity: SIMD3<Float>

    init(def: ParticleOperatorDef) {
        self.drag = def.drag?.getFloat() ?? 0
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
        let speed = instanceOverride?.speed ?? 1
        let grav = gravity + globalGravity
        for i in 0..<count {
            if !particles[i].alive { continue }
            particles[i].position += particles[i].velocity * dt
            particles[i].velocity += grav * dt * speed
            particles[i].velocity += globalWind * dt * speed
            var dragFactor = 1 - (drag * dt)
            if dragFactor < 0 { dragFactor = 0 }
            particles[i].velocity *= dragFactor
        }
    }
}

class AngularMovementOperator: ParticleOperator {
    let drag: Float
    let force: SIMD3<Float>

    init(def: ParticleOperatorDef) {
        let degToRad = Float.pi / 180
        self.drag = def.drag?.getFloat() ?? 0
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
        let speed = instanceOverride?.speed ?? 1
        let pi = Float.pi
        let two_pi = Float.pi * 2
        for i in 0..<count {
            if !particles[i].alive { continue }
            particles[i].rotation += particles[i].angularVelocity * dt * speed
            particles[i].angularVelocity += force * dt * speed
            var dragFactor = 1 - (drag * dt)
            if dragFactor < 0 { dragFactor = 0 }
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
                    1
                    - ParticleMath.fadeValue(
                        life: life,
                        startTime: fadeOutTime,
                        endTime: 1,
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
        self.startTime = def.starttime?.getFloat() ?? 0
        self.endTime = def.endtime?.getFloat() ?? 1
        self.startValue = def.startvalue?.getFloat() ?? 1
        self.endValue = def.endvalue?.getFloat() ?? 0
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
        self.startTime = def.starttime?.getFloat() ?? 0
        self.endTime = def.endtime?.getFloat() ?? 1
        self.startValue = def.startvalue?.getFloat() ?? 1
        self.endValue = def.endvalue?.getFloat() ?? 0
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
        self.startTime = def.starttime?.getFloat() ?? 0
        self.endTime = def.endtime?.getFloat() ?? 1
        self.startValue = def.startvalue?.getVec3() ?? SIMD3<Float>(1, 1, 1)
        self.endValue = def.endvalue?.getVec3() ?? SIMD3<Float>(1, 1, 1)
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
        self.speedMin = def.speedmin?.getFloat() ?? 500
        self.speedMax = def.speedmax?.getFloat() ?? 1000
        self.timeScale = def.timescale?.getFloat() ?? 0.01
        self.mask = def.mask?.getVec3() ?? SIMD3<Float>(1, 1, 0)
        self.phaseMin = def.phasemin?.getFloat() ?? 0
        self.phaseMax = def.phasemax?.getFloat() ?? 0
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
        let noiseScale = scale * 2
        let speedOver = instanceOverride?.speed ?? 1

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
        self.distanceInner = def.distanceinner?.getFloat() ?? 500
        self.distanceOuter = def.distanceouter?.getFloat() ?? 650
        self.speedInner = def.speedinner?.getFloat() ?? 2500
        self.speedOuter = def.speedouter?.getFloat() ?? 0
        self.centerForce = def.centerforce?.getFloat() ?? 1
        self.ringRadius = def.ringradius?.getFloat() ?? 300
        self.ringWidth = def.ringwidth?.getFloat() ?? 50
        self.ringPullDistance = def.ringpulldistance?.getFloat() ?? 50
        self.ringPullForce = def.ringpullforce?.getFloat() ?? 10
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
        let speedOver = instanceOverride?.speed ?? 1

        var ax = axis
        if length(ax) > 0 {
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

            var sp: Float = 0
            var radialForce = SIMD3<Float>.zero

            if ringShape {
                let ringInner = ringRadius - ringWidth * 0.5
                let ringOuter = ringRadius + ringWidth * 0.5
                if dist < ringInner {
                    sp = 0
                } else if dist <= ringOuter {
                    let t = (dist - ringInner) / ringWidth
                    sp = ParticleMath.lerp(t: t, a: speedInner, b: speedOuter)
                } else if dist <= ringOuter + ringPullDistance {
                    let pullT = (dist - ringOuter) / ringPullDistance
                    sp = speedOuter * (1 - pullT)
                    if dist > 0.001 {
                        let towardRing = -normalize(radialVector)
                        radialForce = towardRing * ringPullForce * pullT
                    }
                }
            } else {
                let disMid = distanceOuter - distanceInner + Float(0.1)
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
        self.scale = def.scale?.getFloat() ?? 100
        self.threshold = (def.threshold?.getFloat() ?? 1000) / 2
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
        let speedOver = instanceOverride?.speed ?? 1

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
        self.freqMin = def.frequencymin?.getFloat() ?? 0
        self.freqMax = def.frequencymax?.getFloat() ?? 10
        self.scaleMin = def.scalemin?.getFloat() ?? 0
        self.scaleMax = def.scalemax?.getFloat() ?? 1
        self.phaseMin = def.phasemin?.getFloat() ?? 0
        self.phaseMax = def.phasemax?.getFloat() ?? Float.pi * 2
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
                    max: phaseMax + Float.pi * 2
                )
                particles[i].oscillateAlpha.base = particles[i].alpha
                particles[i].oscillateAlpha.initialized = true
            }
            let w = particles[i].oscillateAlpha.frequency
            let t = particles[i].age
            let cosVal =
                (cos(w * t + particles[i].oscillateAlpha.phase) + 1) * 0.5
            let mul = ParticleMath.lerp(t: Float(cosVal), a: scaleMin, b: scaleMax)
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
        self.freqMin = def.frequencymin?.getFloat() ?? 0
        self.freqMax = def.frequencymax?.getFloat() ?? 10
        self.scaleMin = def.scalemin?.getFloat() ?? 0.8
        self.scaleMax = def.scalemax?.getFloat() ?? 1.2
        self.phaseMin = def.phasemin?.getFloat() ?? 0
        self.phaseMax = def.phasemax?.getFloat() ?? Float.pi * 2
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
                    max: freqMax)
                particles[i].oscillateSize.scale = ParticleMath.randomFloat(
                    min: scaleMin,
                    max: scaleMax)
                particles[i].oscillateSize.phase = ParticleMath.randomFloat(
                    min: phaseMin,
                    max: phaseMax + Float.pi * 2)
                particles[i].oscillateSize.base = particles[i].size
                particles[i].oscillateSize.initialized = true
            }
            let w = particles[i].oscillateSize.frequency
            let t = particles[i].age
            let cosVal =
                (cos(w * t + particles[i].oscillateSize.phase) + 1) * 0.5
            let mul = ParticleMath.lerp(t: Float(cosVal), a: scaleMin, b: scaleMax)
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
        self.freqMin = def.frequencymin?.getFloat() ?? 0
        self.freqMax = def.frequencymax?.getFloat() ?? 5
        self.scaleMin = def.scalemin?.getFloat() ?? 0
        self.scaleMax = def.scalemax?.getFloat() ?? 10
        self.phaseMin = def.phasemin?.getFloat() ?? 0
        self.phaseMax = def.phasemax?.getFloat() ?? Float.pi * 2
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
        let speedOver = instanceOverride?.speed ?? 1
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
                            max: phaseMax + Float.pi * 2
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
