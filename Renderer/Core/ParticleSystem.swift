//
//  ParticleSystem.swift
//  Renderer
//
//  Created by laobamac on 2026/3/15.
//

import Foundation
import simd

struct Particle {
    var position: simd_float3
    var velocity: simd_float3
    var size: simd_float2
    var rotation: Float
    var angularVelocity: Float
    var color: simd_float4
    var age: Float
    var lifetime: Float
    var initialAlpha: Float
}

class ParticleSystem {
    let config: ParticleSystemConfig
    let override: InstanceOverride?
    var transform: matrix_float4x4
    var particles: [Particle] = []
    var spawnAccumulator: Float = 0.0
    var systemAge: Float = 0.0
    var maxCount: Int
    var isSequence: Bool
    var sequenceMultiplier: Float

    init(config: ParticleSystemConfig, override: InstanceOverride?, transform: matrix_float4x4) {
        self.config = config
        self.override = override
        self.transform = transform
        
        let baseMaxCount = config.maxcount ?? 100
        let multiplier = override?.count ?? 1.0
        self.maxCount = Int(Float(baseMaxCount) * multiplier)
        
        self.isSequence = config.animationmode == "sequence"
        self.sequenceMultiplier = config.sequencemultiplier ?? 1.0
        
        print("ParticleSystem: Initialized with maxCount: \(self.maxCount), isSequence: \(self.isSequence)")
    }

    func update(deltaTime: Float) -> [ParticleInstanceData] {
        systemAge += deltaTime
        
        spawnParticles(deltaTime: deltaTime)
        updateParticles(deltaTime: deltaTime)
        
        return buildInstanceData()
    }

    private func spawnParticles(deltaTime: Float) {
        guard let emitters = config.emitter else { return }
        
        for emitter in emitters {
            let baseRate = extractFloat(from: emitter.rate) ?? 0.0
            let actualRate = baseRate * (override?.count ?? 1.0)
            
            spawnAccumulator += actualRate * deltaTime
            
            var spawnCount = Int(spawnAccumulator)
            if spawnCount > 0 {
                spawnAccumulator -= Float(spawnCount)
                
                let availableSlots = maxCount - particles.count
                spawnCount = min(spawnCount, availableSlots)
                
                for _ in 0..<spawnCount {
                    var newParticle = Particle(
                        position: simd_float3(0, 0, 0),
                        velocity: simd_float3(0, 0, 0),
                        size: simd_float2(1, 1),
                        rotation: 0.0,
                        angularVelocity: 0.0,
                        color: simd_float4(1, 1, 1, 1),
                        age: 0.0,
                        lifetime: 1.0,
                        initialAlpha: 1.0
                    )
                    
                    initializeParticle(&newParticle, emitter: emitter)
                    particles.append(newParticle)
                }
            }
        }
    }

    private func initializeParticle(_ particle: inout Particle, emitter: ParticleEmitter) {
        var localPos = simd_float3(0, 0, 0)
        if let o = emitter.origin {
            localPos = parseVector3(o)
        }
        
        if emitter.name == "boxrandom" || emitter.name == "sphererandom" {
            let distMax = emitter.distancemax ?? 0.0
            let distMin = emitter.distancemin ?? 0.0
            
            if distMax > 0 {
                let r = Float.random(in: distMin...distMax)
                let theta = Float.random(in: 0...(2 * .pi))
                let phi = Float.random(in: 0 ... .pi)
                localPos.x += r * sin(phi) * cos(theta)
                localPos.y += r * sin(phi) * sin(theta)
                localPos.z += r * cos(phi)
            }
        }
        
        let worldPos = transform * simd_float4(localPos, 1.0)
        particle.position = simd_float3(worldPos.x, worldPos.y, worldPos.z)
        
        guard let initializers = config.initializer else { return }
        
        for initDef in initializers {
            switch initDef.name {
            case "lifetimerandom":
                let minVal = extractFloat(from: initDef.min) ?? 1.0
                let maxVal = extractFloat(from: initDef.max) ?? 1.0
                particle.lifetime = Float.random(in: minVal...maxVal)
                
            case "sizerandom":
                let minVal = extractFloat(from: initDef.min) ?? 1.0
                let maxVal = extractFloat(from: initDef.max) ?? 1.0
                let overrideSize = override?.size ?? 1.0
                let s = Float.random(in: minVal...maxVal) * overrideSize
                particle.size = simd_float2(s, s)
                
            case "velocityrandom":
                let minVec = extractVector3(from: initDef.min) ?? simd_float3(0,0,0)
                let maxVec = extractVector3(from: initDef.max) ?? simd_float3(0,0,0)
                particle.velocity = simd_float3(
                    Float.random(in: minVec.x...maxVec.x),
                    Float.random(in: minVec.y...maxVec.y),
                    Float.random(in: minVec.z...maxVec.z)
                )
                
            case "colorrandom":
                var cMin = simd_float3(1,1,1)
                var cMax = simd_float3(1,1,1)
                if let m1 = extractVector3(from: initDef.min) { cMin = m1 / 255.0 }
                if let m2 = extractVector3(from: initDef.max) { cMax = m2 / 255.0 } else { cMax = cMin }
                
                var finalColor = simd_float3(
                    Float.random(in: cMin.x...cMax.x),
                    Float.random(in: cMin.y...cMax.y),
                    Float.random(in: cMin.z...cMax.z)
                )
                
                if let overColorStr = override?.colorn {
                    let overColor = parseVector3(overColorStr)
                    finalColor *= overColor
                }
                
                particle.color = simd_float4(finalColor, 1.0)
                
            case "rotationrandom":
                let minVec = extractVector3(from: initDef.min) ?? simd_float3(0,0,0)
                let maxVec = extractVector3(from: initDef.max) ?? simd_float3(0,0,0)
                particle.rotation = Float.random(in: minVec.z...maxVec.z)
                
            case "angularvelocityrandom":
                let minVec = extractVector3(from: initDef.min) ?? simd_float3(0,0,0)
                let maxVec = extractVector3(from: initDef.max) ?? simd_float3(0,0,0)
                particle.angularVelocity = Float.random(in: minVec.z...maxVec.z)
                
            case "turbulentvelocityrandom":
                let sMax = initDef.speedmax ?? 0.0
                let sMin = initDef.speedmin ?? 0.0
                let scale = initDef.scale ?? 1.0
                let magnitude = Float.random(in: sMin...sMax) * scale
                particle.velocity.x += Float.random(in: -magnitude...magnitude)
                particle.velocity.y += Float.random(in: -magnitude...magnitude)
                particle.velocity.z += Float.random(in: -magnitude...magnitude)
                
            default:
                break
            }
        }
        particle.initialAlpha = particle.color.w
    }

    private func updateParticles(deltaTime: Float) {
        var aliveParticles: [Particle] = []
        
        let overrideSpeed = override?.speed ?? 1.0
        let actualDelta = deltaTime * overrideSpeed
        
        guard let operators = config.operator else {
            particles.removeAll()
            return
        }
        
        var hasMovement = false
        var hasAlphaFade = false
        var fadeIn: Float = 0.0
        var fadeOut: Float = 0.0
        var hasAngular = false
        
        for op in operators {
            if op.name == "movement" { hasMovement = true }
            if op.name == "alphafade" {
                hasAlphaFade = true
                fadeIn = op.fadeintime ?? 0.0
                fadeOut = op.fadeouttime ?? 1.0
            }
            if op.name == "angularmovement" { hasAngular = true }
        }
        
        for i in 0..<particles.count {
            var p = particles[i]
            p.age += actualDelta
            
            if p.age >= p.lifetime {
                continue
            }
            
            if hasMovement {
                p.position += p.velocity * actualDelta
            }
            
            if hasAngular {
                p.rotation += p.angularVelocity * actualDelta
            }
            
            if hasAlphaFade {
                let normalizedAge = p.age / p.lifetime
                var currentAlpha = p.initialAlpha
                
                if normalizedAge < fadeIn && fadeIn > 0 {
                    currentAlpha *= (normalizedAge / fadeIn)
                } else if normalizedAge > fadeOut && fadeOut < 1.0 {
                    currentAlpha *= (1.0 - normalizedAge) / (1.0 - fadeOut)
                }
                
                p.color.w = currentAlpha
            }
            
            aliveParticles.append(p)
        }
        
        particles = aliveParticles
    }

    private func buildInstanceData() -> [ParticleInstanceData] {
        var instanceData: [ParticleInstanceData] = []
        instanceData.reserveCapacity(particles.count)
        
        for p in particles {
            var uvOffset = simd_float4(0, 0, 1, 1)
            
            if isSequence {
                let frameProgress = (p.age * sequenceMultiplier).truncatingRemainder(dividingBy: 1.0)
                uvOffset.x = frameProgress
            }
            
            let data = ParticleInstanceData(
                position: p.position,
                size: p.size,
                rotation: p.rotation,
                color: p.color,
                uvOffset: uvOffset
            )
            instanceData.append(data)
        }
        
        return instanceData
    }

    private func extractFloat(from prop: ParticlePropertyValue?) -> Float? {
        guard let prop = prop else { return nil }
        switch prop {
        case .float(let f): return f
        case .string(let s): return Float(s)
        case .floatArray(let a): return a.first
        }
    }

    private func extractVector3(from prop: ParticlePropertyValue?) -> simd_float3? {
        guard let prop = prop else { return nil }
        switch prop {
        case .string(let s): return parseVector3(s)
        case .floatArray(let a):
            if a.count >= 3 { return simd_float3(a[0], a[1], a[2]) }
            if a.count == 2 { return simd_float3(a[0], a[1], 0) }
            if a.count == 1 { return simd_float3(a[0], a[0], a[0]) }
            return simd_float3(0,0,0)
        case .float(let f):
            return simd_float3(f, f, f)
        }
    }

    private func parseVector3(_ string: String) -> simd_float3 {
        let parts = string.split(separator: " ").compactMap { Float($0) }
        if parts.count >= 3 {
            return simd_float3(parts[0], parts[1], parts[2])
        } else if parts.count == 2 {
            return simd_float3(parts[0], parts[1], 0)
        } else if parts.count == 1 {
            return simd_float3(parts[0], parts[0], parts[0])
        }
        return simd_float3(0, 0, 0)
    }
}
