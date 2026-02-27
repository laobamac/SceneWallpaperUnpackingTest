//
//  ParticleInitializer.swift
//  Renderer
//
//  Created by laobamac on 2026/2/27.
//

import simd
import Foundation

class ColorRandomInitializer: ParticleInitializer {
    let minVal: SIMD3<Float>
    let maxVal: SIMD3<Float>
    init(def: ParticleInitializerDef) {
        var mn = def.min?.getVec3() ?? .zero
        var mx = def.max?.getVec3() ?? SIMD3<Float>(255, 255, 255)
        if mn.x > 1 || mn.y > 1 || mn.z > 1 { mn /= 255 }
        if mx.x > 1 || mx.y > 1 || mx.z > 1 { mx /= 255 }
        self.minVal = mn
        self.maxVal = mx
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let overrideColor =
            instanceOverride?.colorn != nil
            ? ScriptableValue.string(instanceOverride!.colorn!).getVec3() : SIMD3<Float>(1, 1, 1)
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
        self.minVal = def.min?.getFloat() ?? 0
        self.maxVal = def.max?.getFloat() ?? 20
        self.exponent = def.exponent?.getFloat() ?? 1
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let t = ParticleMath.randomFloat(min: 0, max: 1)
        let adjustedT = pow(t, exponent)
        let overrideSize = instanceOverride?.size ?? 1
        particle.size =
            (minVal + adjustedT * (maxVal - minVal)) * overrideSize / 2
        particle.initial.size = particle.size
    }
}

class AlphaRandomInitializer: ParticleInitializer {
    let minVal: Float
    let maxVal: Float
    init(def: ParticleInitializerDef) {
        self.minVal = def.min?.getFloat() ?? 0.05
        self.maxVal = def.max?.getFloat() ?? 1
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let overrideAlpha = instanceOverride?.alpha ?? 1
        particle.alpha =
            ParticleMath.randomFloat(min: minVal, max: maxVal) * overrideAlpha
        particle.initial.alpha = particle.alpha
    }
}

class LifetimeRandomInitializer: ParticleInitializer {
    let minVal: Float
    let maxVal: Float
    init(def: ParticleInitializerDef) {
        self.minVal = def.min?.getFloat() ?? 0
        self.maxVal = def.max?.getFloat() ?? 1
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let overrideLife = instanceOverride?.lifetime ?? 1
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
        let overrideSpeed = instanceOverride?.speed ?? 1
        let vel =
            ParticleMath.randomVec3(min: minVal, max: maxVal) * overrideSpeed
        particle.velocity += vel
    }
}

class RotationRandomInitializer: ParticleInitializer {
    let minVal: SIMD3<Float>
    let maxVal: SIMD3<Float>
    init(def: ParticleInitializerDef) {
        let degToRad = Float.pi / 180
        self.minVal = (def.min?.getVec3() ?? .zero) * degToRad
        self.maxVal =
            (def.max?.getVec3() ?? SIMD3<Float>(0, 0, 360)) * degToRad
    }
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    ) {
        let overrideSpeed = instanceOverride?.speed ?? 1
        particle.rotation =
            ParticleMath.randomVec3(min: minVal, max: maxVal) * overrideSpeed
    }
}

class AngularVelocityRandomInitializer: ParticleInitializer {
    let minVal: SIMD3<Float>
    let maxVal: SIMD3<Float>
    let exponent: Float
    init(def: ParticleInitializerDef) {
        let degToRad = Float.pi / 180
        self.minVal = (def.min?.getVec3() ?? SIMD3<Float>(0, 0, -5)) * degToRad
        self.maxVal = (def.max?.getVec3() ?? SIMD3<Float>(0, 0, 5)) * degToRad
        self.exponent = def.exponent?.getFloat() ?? 1
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
        let overrideSpeed = instanceOverride?.speed ?? 1
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
        self.speedMin = def.speedmin?.getFloat() ?? 100
        self.speedMax = def.speedmax?.getFloat() ?? 250
        self.scale = def.scale?.getFloat() ?? 1
        self.offset = (def.offset?.getFloat() ?? 0) * (Float.pi / 180)
        self.forward = def.forward?.getVec3() ?? SIMD3<Float>(0, 1, 0)
        self.timeScale = def.timescale?.getFloat() ?? 1
        self.phaseMin = def.phasemin?.getFloat() ?? 0
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
                    dividingBy: 1000
                )
            ) * timeScale
        )
        let phase = ParticleMath.randomFloat(min: phaseMin, max: phaseMax)
        let samplePos = noisePos + SIMD3<Float>(phase, phase * 0.7, phase * 1.3)

        var result = ParticleMath.curlNoise(p: samplePos)
        let len = length(result)
        if len < 0.0001 { result = fwd } else { result = result / len }

        if scale < 2 {
            let cosAngle = dot(result, fwd)
            let angle = acos(simd_clamp(cosAngle, -1, 1)) / Float.pi
            let maxAngle = scale / 2
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

        result.z = 0
        let len2d = length(result)
        if len2d > 0.0001 { result /= len2d }

        let overrideSpeed = instanceOverride?.speed ?? 1
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
        let overrideSpeed = instanceOverride?.speed ?? 1
        let angle = (Float(sequenceIndex) / Float(count)) * Float.pi * 2
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
