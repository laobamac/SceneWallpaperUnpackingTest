//
//  ParticleRenderableInitializers.swift
//  Renderer
//
//  Created by laobamac on 2026/3/17.
//

import Foundation
import simd

extension ParticleRenderable {

    func setupInitializers() {
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
}
