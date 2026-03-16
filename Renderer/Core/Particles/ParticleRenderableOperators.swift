//
//  ParticleRenderableOperators.swift
//  Renderer
//
//  Created by laobamac on 2026/3/17.
//

import Foundation
import simd

extension ParticleRenderable {

    func setupOperators() {
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
}
