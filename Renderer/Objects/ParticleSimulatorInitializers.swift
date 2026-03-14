//
//  ParticleSimulatorInitializers.swift
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

import Foundation
import simd

extension ParticleSimulator {
    func setupInitializers() {
        guard let inits = particleDefinition.initializer else { return }
        for i in inits {
            let name = i.name ?? ""
            if name == "colorrandom" {
                initializers.append(createColorRandomInitializer(i))
            } else if name == "sizerandom" {
                initializers.append(createSizeRandomInitializer(i))
            } else if name == "alpharandom" {
                initializers.append(createAlphaRandomInitializer(i))
            } else if name == "lifetimerandom" {
                initializers.append(createLifetimeRandomInitializer(i))
            } else if name == "velocityrandom" {
                initializers.append(createVelocityRandomInitializer(i))
            } else if name == "rotationrandom" {
                initializers.append(createRotationRandomInitializer(i))
            } else if name == "angularvelocityrandom" {
                initializers.append(createAngularVelocityRandomInitializer(i))
            } else if name == "turbulentvelocityrandom" {
                initializers.append(createTurbulentVelocityRandomInitializer(i))
            } else if name == "mapsequencearoundcontrolpoint" {
                initializers.append(createMapSequenceAroundControlPointInitializer(i))
            }
        }
    }

    private func createColorRandomInitializer(_ initData: ParticleInitializer) -> InitializerFunc {
        let minV = initData.min?.float3Value ?? SIMD3<Float>(0,0,0)
        let maxV = initData.max?.float3Value ?? SIMD3<Float>(255,255,255)
        let overrideV = instanceOverride?.colorn?.float3Value ?? SIMD3<Float>(1,1,1)
        
        var adjMin = minV
        var adjMax = maxV
        if adjMin.x > 1.0 || adjMin.y > 1.0 || adjMin.z > 1.0 { adjMin /= 255.0 }
        if adjMax.x > 1.0 || adjMax.y > 1.0 || adjMax.z > 1.0 { adjMax /= 255.0 }

        return { (p: inout ParticleInstance) in
            let r = Float.random(in: min(adjMin.x, adjMax.x)...max(adjMin.x, adjMax.x))
            let g = Float.random(in: min(adjMin.y, adjMax.y)...max(adjMin.y, adjMax.y))
            let b = Float.random(in: min(adjMin.z, adjMax.z)...max(adjMin.z, adjMax.z))
            p.color = SIMD3<Float>(r, g, b) * overrideV
            p.initial.color = p.color
        }
    }

    private func createSizeRandomInitializer(_ initData: ParticleInitializer) -> InitializerFunc {
        let minV = initData.min?.floatValue ?? 0.0
        let maxV = initData.max?.floatValue ?? 20.0
        let expV = initData.exponent?.floatValue ?? 1.0
        let overrideV = instanceOverride?.size?.floatValue ?? 1.0

        return { (p: inout ParticleInstance) in
            let t = Float.random(in: 0.0...1.0)
            let adjustedT = pow(t, expV)
            p.size = (minV + adjustedT * (maxV - minV)) * overrideV / 2.0
            p.initial.size = p.size
        }
    }

    private func createAlphaRandomInitializer(_ initData: ParticleInitializer) -> InitializerFunc {
        let minV = initData.min?.floatValue ?? 0.05
        let maxV = initData.max?.floatValue ?? 1.0
        let overrideV = instanceOverride?.alpha?.floatValue ?? 1.0

        return { (p: inout ParticleInstance) in
            p.alpha = Float.random(in: min(minV, maxV)...max(minV, maxV)) * overrideV
            p.initial.alpha = p.alpha
        }
    }

    private func createLifetimeRandomInitializer(_ initData: ParticleInitializer) -> InitializerFunc {
        let minV = initData.min?.floatValue ?? 0.0
        let maxV = initData.max?.floatValue ?? 1.0
        let overrideV = instanceOverride?.lifetime?.floatValue ?? 1.0

        return { (p: inout ParticleInstance) in
            p.lifetime = Float.random(in: min(minV, maxV)...max(minV, maxV)) * overrideV
            p.initial.lifetime = p.lifetime
        }
    }

    private func createVelocityRandomInitializer(_ initData: ParticleInitializer) -> InitializerFunc {
        let minV = initData.min?.float3Value ?? SIMD3<Float>(-32,-32,-32)
        let maxV = initData.max?.float3Value ?? SIMD3<Float>(32,32,32)
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        return { (p: inout ParticleInstance) in
            var vel = SIMD3<Float>(
                Float.random(in: min(minV.x, maxV.x)...max(minV.x, maxV.x)),
                Float.random(in: min(minV.y, maxV.y)...max(minV.y, maxV.y)),
                Float.random(in: min(minV.z, maxV.z)...max(minV.z, maxV.z))
            ) * overrideV
            vel.y = -vel.y
            p.velocity += vel
        }
    }

    private func createRotationRandomInitializer(_ initData: ParticleInitializer) -> InitializerFunc {
        let minV = initData.min?.float3Value ?? .zero
        let maxV = initData.max?.float3Value ?? SIMD3<Float>(0, 0, 2.0 * .pi)
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        return { (p: inout ParticleInstance) in
            p.rotation = SIMD3<Float>(
                Float.random(in: min(minV.x, maxV.x)...max(minV.x, maxV.x)),
                Float.random(in: min(minV.y, maxV.y)...max(minV.y, maxV.y)),
                Float.random(in: min(minV.z, maxV.z)...max(minV.z, maxV.z))
            ) * overrideV
        }
    }

    private func createAngularVelocityRandomInitializer(_ initData: ParticleInitializer) -> InitializerFunc {
        let minV = initData.min?.float3Value ?? SIMD3<Float>(0, 0, -5.0)
        let maxV = initData.max?.float3Value ?? SIMD3<Float>(0, 0, 5.0)
        let expV = initData.exponent?.floatValue ?? 1.0
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        return { (p: inout ParticleInstance) in
            var result = SIMD3<Float>()
            for i in 0..<3 {
                let t = pow(Float.random(in: 0.0...1.0), expV)
                result[i] = minV[i] + t * (maxV[i] - minV[i])
            }
            p.angularVelocity = result * overrideV
        }
    }

    private func createTurbulentVelocityRandomInitializer(_ initData: ParticleInitializer) -> InitializerFunc {
        let speedMin = initData.speedmin?.floatValue ?? 100.0
        let speedMax = initData.speedmax?.floatValue ?? 250.0
        let offset = initData.offset?.floatValue ?? 0.0
        let scale = initData.scale?.floatValue ?? 1.0
        var forward = initData.forward?.float3Value ?? SIMD3<Float>(0.0, 1.0, 0.0)
        let timeScale = initData.timescale?.floatValue ?? 1.0
        let phaseMin = initData.phasemin?.floatValue ?? 0.0
        let phaseMax = initData.phasemax?.floatValue ?? 0.1
        var right = initData.right?.float3Value ?? SIMD3<Float>(0.0, 0.0, 1.0)
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        forward.y = -forward.y
        right.y = -right.y

        if length(forward) > 0.0001 { forward = normalize(forward) }
        else { forward = SIMD3<Float>(0.0, 1.0, 0.0) }
        if length(right) > 0.0001 { right = normalize(right) }
        else { right = SIMD3<Float>(1.0, 0.0, 0.0) }

        let is2D = ((particleDefinition.flags ?? 0) & 4) == 0

        return { [weak self] (p: inout ParticleInstance) in
            guard let self = self else { return }
            let speed = Float.random(in: min(speedMin, speedMax)...max(speedMin, speedMax))
            var noisePos = p.position * 0.1
            noisePos += SIMD3<Float>(repeating: self.time * timeScale)

            let phase = Float.random(in: min(phaseMin, phaseMax)...max(phaseMin, phaseMax))
            let samplePos = noisePos + SIMD3<Float>(phase, phase * 0.7, phase * 1.3)

            var result = NoiseUtils.curlNoise(samplePos)
            let len = length(result)
            if len < 0.0001 { result = forward }
            else { result /= len }

            if scale < 2.0 {
                let cosAngle = dot(result, forward)
                let angle = acos(min(max(cosAngle, -1.0), 1.0)) / .pi
                let maxAngle = scale / 2.0

                if angle > maxAngle && maxAngle > 0.0001 {
                    var axis = cross(result, forward)
                    let axisLen = length(axis)
                    if axisLen > 0.0001 {
                        axis /= axisLen
                        let rotAngle = (angle - maxAngle) * .pi
                        let q = simd_quatf(angle: rotAngle, axis: axis)
                        result = q.act(result)
                    }
                }
            }

            if abs(offset) > 0.0001 {
                let q = simd_quatf(angle: -offset, axis: right)
                result = q.act(result)
            }

            if is2D {
                result.z = 0.0
                let len2d = length(result)
                if len2d > 0.0001 { result /= len2d }
            }

            p.velocity += result * speed * overrideV
        }
    }

    private func createMapSequenceAroundControlPointInitializer(_ initData: ParticleInitializer) -> InitializerFunc {
        let controlPoint = Int(initData.controlpoint?.floatValue ?? 0.0)
        let count = Int(initData.count?.floatValue ?? 1.0)
        let speedMin = initData.speedmin?.float3Value ?? .zero
        let speedMax = initData.speedmax?.float3Value ?? SIMD3<Float>(100, 100, 100)
        let overrideV = instanceOverride?.speed?.floatValue ?? 1.0

        var sequenceIndex = 0

        return { [weak self] (p: inout ParticleInstance) in
            guard let self = self else { return }
            let angle = (Float(sequenceIndex) / Float(count)) * 2.0 * .pi
            sequenceIndex = (sequenceIndex + 1) % count

            var centerPos = SIMD3<Float>()
            if controlPoint >= 0 && controlPoint < self.controlPoints.count {
                centerPos = self.controlPoints[controlPoint].position
            }
            p.position = centerPos

            var speed = SIMD3<Float>(
                Float.random(in: min(speedMin.x, speedMax.x)...max(speedMin.x, speedMax.x)),
                Float.random(in: min(speedMin.y, speedMax.y)...max(speedMin.y, speedMax.y)),
                Float.random(in: min(speedMin.z, speedMax.z)...max(speedMin.z, speedMax.z))
            )
            speed.y = -speed.y

            let c = cos(angle)
            let s = sin(angle)
            let rotatedSpeedX = c * speed.x - s * speed.y
            let rotatedSpeedY = s * speed.x + c * speed.y
            let rotatedSpeedZ = speed.z

            p.velocity = SIMD3<Float>(rotatedSpeedX, rotatedSpeedY, rotatedSpeedZ) * overrideV
        }
    }
}
