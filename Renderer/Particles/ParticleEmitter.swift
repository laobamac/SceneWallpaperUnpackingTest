//
//  ParticleEmitter.swift
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

import Foundation
import simd

struct ParticleBoxEmitter {
    var directions: SIMD3<Float>
    var minDistance: SIMD3<Float>
    var maxDistance: SIMD3<Float>
    var emitSpeed: Float
    var origin: SIMD3<Float>
    var onePerFrame: Bool
    var sort: Bool
    var instantaneous: Int
    var minSpeed: Float
    var maxSpeed: Float

    func makeOp() -> ParticleEmittOp {
        var timer: Double = 0.0
        return { particles, inits, maxCount, timePass in
            timer += timePass

            let genBox: () -> Particle = {
                var pos = SIMD3<Float>(0, 0, 0)
                for i in 0..<3 {
                    pos[i] = ParticleMath.lerp(
                        minDistance[i],
                        maxDistance[i],
                        ParticleMath.randomFloat()
                    )
                }
                var p = Particle()
                let finalPos = pos * directions
                p.position = finalPos
                let speed = ParticleMath.randomFloat(
                    min: minSpeed,
                    max: maxSpeed
                )
                if length(finalPos) > 0.0001 {
                    p.velocity = normalize(finalPos) * speed
                } else {
                    p.velocity = SIMD3<Float>(0, 1, 0) * speed
                }
                p.position += origin
                return p
            }

            var emitNum = 0
            let emitDur = 1.0 / Double(emitSpeed)
            if emitDur <= timer {
                emitNum = Int(timer / emitDur)
                timer -= Double(emitNum) * emitDur
            }
            if timer < 0 { timer = 0 }

            if onePerFrame { emitNum = 1 }
            if instantaneous > 0 && particles.isEmpty {
                emitNum = instantaneous
            }

            ParticleEmitterUtils.emitt(
                particles: &particles,
                num: emitNum,
                maxCount: maxCount,
                sort: sort
            ) {
                return ParticleEmitterUtils.spawn(
                    gen: genBox,
                    inits: inits,
                    duration: 1.0 / Double(emitSpeed)
                )
            }
        }
    }
}

struct ParticleSphereEmitter {
    var directions: SIMD3<Float>
    var minDistance: Float
    var maxDistance: Float
    var emitSpeed: Float
    var origin: SIMD3<Float>
    var sign: SIMD3<Int32>
    var onePerFrame: Bool
    var sort: Bool
    var instantaneous: Int
    var minSpeed: Float
    var maxSpeed: Float

    func makeOp() -> ParticleEmittOp {
        var timer: Double = 0.0
        return { particles, inits, maxCount, timePass in
            timer += timePass

            let genSphere: () -> Particle = {
                var p = Particle()
                let r = ParticleMath.lerp(
                    minDistance,
                    maxDistance,
                    pow(ParticleMath.randomFloat(), 1.0 / 3.0)
                )
                var sp = ParticleMath.genSphereSurfaceNormal() * r * directions

                if sign.x != 0 { sp.x = abs(sp.x) * Float(sign.x) }
                if sign.y != 0 { sp.y = abs(sp.y) * Float(sign.y) }
                if sign.z != 0 { sp.z = abs(sp.z) * Float(sign.z) }

                p.position = sp
                let speed = ParticleMath.randomFloat(
                    min: minSpeed,
                    max: maxSpeed
                )
                if length(sp) > 0.0001 {
                    p.velocity = normalize(sp) * speed
                } else {
                    p.velocity = SIMD3<Float>(0, 1, 0) * speed
                }
                p.position += origin
                return p
            }

            var emitNum = 0
            let emitDur = 1.0 / Double(emitSpeed)
            if emitDur <= timer {
                emitNum = Int(timer / emitDur)
                timer -= Double(emitNum) * emitDur
            }
            if timer < 0 { timer = 0 }

            if onePerFrame { emitNum = 1 }
            if instantaneous > 0 && particles.isEmpty {
                emitNum = instantaneous
            }

            ParticleEmitterUtils.emitt(
                particles: &particles,
                num: emitNum,
                maxCount: maxCount,
                sort: sort
            ) {
                return ParticleEmitterUtils.spawn(
                    gen: genSphere,
                    inits: inits,
                    duration: 1.0 / Double(emitSpeed)
                )
            }
        }
    }
}

struct ParticleEmitterUtils {
    static func emitt(
        particles: inout [Particle],
        num: Int,
        maxCount: Int,
        sort: Bool,
        spawn: () -> Particle
    ) {
        var lastParticle = 0
        var hasDead = true
        var count = 0

        for _ in 0..<num {
            if hasDead {
                let (idx, dead) = findLastParticle(
                    particles: particles,
                    last: lastParticle
                )
                lastParticle = idx
                hasDead = dead
            }

            if hasDead {
                particles[lastParticle] = spawn()
            } else {
                if particles.count == maxCount { break }
                particles.append(spawn())
            }
            count += 1
        }

        if sort {
            particles.sort { a, b in
                let la = a.lifetime > 0
                let lb = b.lifetime > 0
                return (la && !lb) || (la && lb && !a.markNew && b.markNew)
            }
        }
    }

    static func findLastParticle(particles: [Particle], last: Int) -> (
        Int, Bool
    ) {
        if last >= particles.count { return (0, false) }
        for i in last..<particles.count {
            if particles[i].lifetime <= 0 { return (i, true) }
        }
        return (0, false)
    }

    static func spawn(
        gen: () -> Particle,
        inits: [ParticleInitOp],
        duration: Double
    ) -> Particle {
        var p = gen()
        for op in inits {
            op(&p, duration)
        }
        return p
    }
}
