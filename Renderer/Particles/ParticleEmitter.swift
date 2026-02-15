//
//  ParticleEmitter.swift
//  Renderer
//
//  Created by laobamac on 2026/2/14.
//

import Foundation
import simd

typealias ParticleInitOp = (inout Particle, Float) -> Void
typealias ParticleEmittOp = (inout [Particle], [ParticleInitOp], UInt32, Float) -> Void
typealias ParticleGenerator = (SIMD3<Float>) -> Particle

struct ParticleBoxEmitterArgs {
    var directions: SIMD3<Float>
    var minDistance: SIMD3<Float>
    var maxDistance: SIMD3<Float>
    var emitSpeed: Float
    var origin: SIMD3<Float>
    var one_per_frame: Bool
    var sort: Bool
    var instantaneous: UInt32
    var minSpeed: Float
    var maxSpeed: Float
    
    static func makeGenerator(args: ParticleBoxEmitterArgs) -> ParticleGenerator {
        let a = args
        return { center in
            var pos = SIMD3<Float>(0, 0, 0)
            pos.x = Float.random(in: -1...1) * (a.maxDistance.x - a.minDistance.x) / 2.0 + (a.maxDistance.x + a.minDistance.x) / 2.0
            pos.y = Float.random(in: -1...1) * (a.maxDistance.y - a.minDistance.y) / 2.0 + (a.maxDistance.y + a.minDistance.y) / 2.0
            pos.z = Float.random(in: -1...1) * (a.maxDistance.z - a.minDistance.z) / 2.0 + (a.maxDistance.z + a.minDistance.z) / 2.0
            
            var p = Particle()
            pos = pos * a.directions
            ParticleModify.moveTo(p: &p, pos: pos + center)
            
            let dir = length(pos) > 0.0001 ? normalize(pos) : SIMD3<Float>(0, 1, 0)
            let speed = Float.random(in: a.minSpeed...a.maxSpeed)
            ParticleModify.changeVelocity(p: &p, v: dir * speed)
            ParticleModify.move(p: &p, acc: a.origin)
            return p
        }
    }
    
    static func makeEmittOp(args: ParticleBoxEmitterArgs) -> ParticleEmittOp {
        var timer: Float = 0.0
        let a = args
        let generator = makeGenerator(args: args)
        
        return { (particles, inis, maxcount, timepass) in
            timer += timepass
            let emitDur = 1.0 / a.emitSpeed
            var emitNum: UInt32 = 0
            if emitDur <= timer {
                emitNum = UInt32(timer / emitDur)
                timer.formTruncatingRemainder(dividingBy: emitDur)
            }
            if a.one_per_frame { emitNum = 1 }
            if a.instantaneous > 0 && particles.isEmpty { emitNum = a.instantaneous }
            
            var createdCount = 0
            while createdCount < emitNum {
                if particles.count < maxcount {
                    var p = generator(SIMD3<Float>(0,0,0))
                    for ini in inis { ini(&p, 1.0 / a.emitSpeed) }
                    particles.append(p)
                } else {
                    if let idx = particles.firstIndex(where: { !ParticleModify.lifetimeOk(p: $0) }) {
                        var p = generator(SIMD3<Float>(0,0,0))
                        for ini in inis { ini(&p, 1.0 / a.emitSpeed) }
                        particles[idx] = p
                    } else {
                        break
                    }
                }
                createdCount += 1
            }
            
            if a.sort {
                particles.sort { (p1, p2) -> Bool in
                    let l1 = ParticleModify.lifetimeOk(p: p1)
                    let l2 = ParticleModify.lifetimeOk(p: p2)
                    if l1 && !l2 { return true }
                    if l1 && l2 { return !ParticleModify.isNew(p: p1) && ParticleModify.isNew(p: p2) }
                    return false
                }
            }
        }
    }
}

struct ParticleSphereEmitterArgs {
    var directions: SIMD3<Float>
    var minDistance: Float
    var maxDistance: Float
    var emitSpeed: Float
    var origin: SIMD3<Float>
    var sign: SIMD3<Int32>
    var one_per_frame: Bool
    var sort: Bool
    var instantaneous: UInt32
    var minSpeed: Float
    var maxSpeed: Float
    
    static func makeGenerator(args: ParticleSphereEmitterArgs) -> ParticleGenerator {
        let a = args
        return { center in
            var p = Particle()
            let u = Float.random(in: 0...1)
            let r = pow(u, 1.0/3.0) * (a.maxDistance - a.minDistance) + a.minDistance
            
            let theta = Float.random(in: 0...(2 * Float.pi))
            let phi = acos(2 * Float.random(in: 0...1) - 1)
            
            var sp = SIMD3<Float>(
                r * sin(phi) * cos(theta),
                r * sin(phi) * sin(theta),
                r * cos(phi)
            )
            
            sp = sp * a.directions
            ParticleModify.applySign(p: &p, x: a.sign.x, y: a.sign.y, z: a.sign.z)
            
            ParticleModify.moveTo(p: &p, pos: sp + center)
            let dir = length(sp) > 0.0001 ? normalize(sp) : SIMD3<Float>(0, 1, 0)
            let speed = Float.random(in: a.minSpeed...a.maxSpeed)
            ParticleModify.changeVelocity(p: &p, v: dir * speed)
            ParticleModify.move(p: &p, acc: a.origin)
            return p
        }
    }
    
    static func makeEmittOp(args: ParticleSphereEmitterArgs) -> ParticleEmittOp {
        var timer: Float = 0.0
        let a = args
        let generator = makeGenerator(args: args)
        
        return { (particles, inis, maxcount, timepass) in
            timer += timepass
            let emitDur = 1.0 / a.emitSpeed
            var emitNum: UInt32 = 0
            if emitDur <= timer {
                emitNum = UInt32(timer / emitDur)
                timer.formTruncatingRemainder(dividingBy: emitDur)
            }
            if a.one_per_frame { emitNum = 1 }
            if a.instantaneous > 0 && particles.isEmpty { emitNum = a.instantaneous }
            
            var createdCount = 0
            while createdCount < emitNum {
                if particles.count < maxcount {
                    var p = generator(SIMD3<Float>(0,0,0))
                    for ini in inis { ini(&p, 1.0 / a.emitSpeed) }
                    particles.append(p)
                } else {
                    if let idx = particles.firstIndex(where: { !ParticleModify.lifetimeOk(p: $0) }) {
                        var p = generator(SIMD3<Float>(0,0,0))
                        for ini in inis { ini(&p, 1.0 / a.emitSpeed) }
                        particles[idx] = p
                    } else {
                        break
                    }
                }
                createdCount += 1
            }
            
            if a.sort {
                particles.sort { (p1, p2) -> Bool in
                    let l1 = ParticleModify.lifetimeOk(p: p1)
                    let l2 = ParticleModify.lifetimeOk(p: p2)
                    if l1 && !l2 { return true }
                    if l1 && l2 { return !ParticleModify.isNew(p: p1) && ParticleModify.isNew(p: p2) }
                    return false
                }
            }
        }
    }
}
