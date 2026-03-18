//
//  ParticleSystem.swift
//  Renderer
//
//  Created by laobamac on 2026/3/19.
//

import Foundation
import simd

enum ParticleSpawnType {
    case `static`
    case eventSpawn
    case eventDeath
    case eventFollow
}

typealias ParticleInitOp = (inout Particle, Double) -> Void
typealias ParticleOperatorOp = (inout ParticleInfo) -> Void
typealias ParticleEmittOp = (inout [Particle], [ParticleInitOp], UInt32, Double) -> Void

enum ParticleModify {
    static func initColor(_ p: inout Particle, _ r: Float, _ g: Float, _ b: Float) {
        p.initValue.color = SIMD3<Float>(r, g, b)
        p.color = p.initValue.color
    }
    
    static func initLifetime(_ p: inout Particle, _ life: Float) {
        p.initValue.lifetime = life
        p.lifetime = life
    }
    
    static func initSize(_ p: inout Particle, _ size: Float) {
        p.initValue.size = size
        p.size = size
    }
    
    static func initAlpha(_ p: inout Particle, _ alpha: Float) {
        p.initValue.alpha = alpha
        p.alpha = alpha
    }
    
    static func changeVelocity(_ p: inout Particle, _ x: Float, _ y: Float, _ z: Float) {
        p.velocity = SIMD3<Float>(x, y, z)
    }
    
    static func changeRotation(_ p: inout Particle, _ x: Float, _ y: Float, _ z: Float) {
        p.rotation = SIMD3<Float>(x, y, z)
    }
    
    static func changeAngularVelocity(_ p: inout Particle, _ x: Float, _ y: Float, _ z: Float) {
        p.angularVelocity = SIMD3<Float>(x, y, z)
    }
    
    static func mutiplyInitLifeTime(_ p: inout Particle, _ m: Float) {
        p.initValue.lifetime *= m
        p.lifetime = p.initValue.lifetime
    }
    
    static func mutiplyInitAlpha(_ p: inout Particle, _ m: Float) {
        p.initValue.alpha *= m
        p.alpha = p.initValue.alpha
    }
    
    static func mutiplyInitSize(_ p: inout Particle, _ m: Float) {
        p.initValue.size *= m
        p.size = p.initValue.size
    }
    
    static func mutiplyVelocity(_ p: inout Particle, _ m: Float) {
        p.velocity *= m
    }
    
    static func mutiplyInitColor(_ p: inout Particle, _ r: Float, _ g: Float, _ b: Float) {
        p.initValue.color *= SIMD3<Float>(r, g, b)
        p.color = p.initValue.color
    }
    
    static func getVelocity(_ p: Particle) -> SIMD3<Float> {
        return p.velocity
    }
    
    static func accelerate(_ p: inout Particle, _ acc: SIMD3<Double>, _ timePass: Double) {
        p.velocity += SIMD3<Float>(acc) * Float(timePass)
    }
    
    static func moveByTime(_ p: inout Particle, _ timePass: Double) {
        p.position += p.velocity * Float(timePass)
    }
    
    static func getAngular(_ p: Particle) -> SIMD3<Float> {
        return p.angularVelocity
    }
    
    static func angularAccelerate(_ p: inout Particle, _ acc: SIMD3<Double>, _ timePass: Double) {
        p.angularVelocity += SIMD3<Float>(acc) * Float(timePass)
    }
    
    static func rotateByTime(_ p: inout Particle, _ timePass: Double) {
        p.rotation += p.angularVelocity * Float(timePass)
    }
    
    static func mutiplySize(_ p: inout Particle, _ m: Float) {
        p.size *= m
    }
    
    static func mutiplySize(_ p: inout Particle, _ m: Double) {
        p.size *= Float(m)
    }
    
    static func mutiplyAlpha(_ p: inout Particle, _ m: Float) {
        p.alpha *= m
    }
    
    static func mutiplyAlpha(_ p: inout Particle, _ m: Double) {
        p.alpha *= Float(m)
    }
    
    static func mutiplyColor(_ p: inout Particle, _ r: Float, _ g: Float, _ b: Float) {
        p.color *= SIMD3<Float>(r, g, b)
    }
    
    static func mutiplyColor(_ p: inout Particle, _ r: Double, _ g: Double, _ b: Double) {
        p.color *= SIMD3<Float>(Float(r), Float(g), Float(b))
    }
    
    static func lifetimePos(_ p: Particle) -> Float {
        if p.initValue.lifetime <= 0 { return 0 }
        return 1.0 - (p.lifetime / p.initValue.lifetime)
    }
    
    static func lifetimePassed(_ p: Particle) -> Double {
        return Double(p.initValue.lifetime - p.lifetime)
    }
    
    static func getPos(_ p: Particle) -> SIMD3<Float> {
        return p.position
    }
    
    static func move(_ p: inout Particle, _ del: SIMD3<Double>) {
        p.position += SIMD3<Float>(del)
    }
    
    static func isNew(_ p: Particle) -> Bool {
        return p.mark_new
    }
    
    static func markOld(_ p: inout Particle) {
        p.mark_new = false
    }
    
    static func lifetimeOk(_ p: Particle) -> Bool {
        return p.lifetime > 0
    }
    
    static func reset(_ p: inout Particle) {
        p.color = p.initValue.color
        p.alpha = p.initValue.alpha
        p.size = p.initValue.size
    }
    
    static func changeLifetime(_ p: inout Particle, _ del: Double) {
        p.lifetime += Float(del)
    }
}

class ParticleSubSystem {
    var maxcount: UInt32
    var rate: Double
    var maxcountInstance: UInt32
    var probability: Double
    var spawnType: ParticleSpawnType
    
    var time: Double = 0
    var emitters: [ParticleEmittOp] = []
    var initializers: [ParticleInitOp] = []
    var operators: [ParticleOperatorOp] = []
    var controlpoints: [ParticleControlpoint] = []
    
    var children: [ParticleSubSystem] = []
    var instances: [ParticleInstance] = []
    
    init(maxcount: UInt32, rate: Double, maxcountInstance: UInt32, probability: Double, type: ParticleSpawnType) {
        self.maxcount = maxcount
        self.rate = rate
        self.maxcountInstance = maxcountInstance
        self.probability = probability
        self.spawnType = type
    }
    
    func queryNewInstance() -> ParticleInstance? {
        if ParticleMath.random(min: 0.0, max: 1.0) <= probability {
            for inst in instances {
                if inst.isDeath && inst.isNoLiveParticle {
                    inst.refresh()
                    return inst
                }
            }
            if instances.count < maxcountInstance {
                let newInst = ParticleInstance()
                instances.append(newInst)
                return newInst
            }
        }
        return nil
    }
    
    func emitt(frameTime: Double) {
        let particleTime = frameTime * rate
        time += particleTime
        
        if spawnType == .static {
            if instances.isEmpty {
                instances.append(ParticleInstance())
            }
        }
        
        let spawnInst = { (inst: ParticleInstance, child: ParticleSubSystem, idx: Int) in
            if let nInst = child.queryNewInstance() {
                nInst.boundedData.parent = inst
                nInst.boundedData.particle_idx = idx
            }
        }
        
        for inst in instances {
            var typeHasDeath = false
            if spawnType == .eventSpawn || spawnType == .eventFollow {
                typeHasDeath = true
            }
            
            if let parent = inst.boundedData.parent {
                let pIdx = inst.boundedData.particle_idx
                if pIdx != -1 && pIdx < parent.particlesVec.count {
                    let p = parent.particlesVec[pIdx]
                    inst.boundedData.pos = ParticleModify.getPos(p)
                    if spawnType == .eventDeath {
                        inst.boundedData.particle_idx = -1
                    }
                    if !inst.isDeath && typeHasDeath {
                        let curLifeOk = ParticleModify.lifetimeOk(p)
                        inst.isDeath = !curLifeOk && inst.boundedData.pre_lifetime_ok
                        inst.boundedData.pre_lifetime_ok = curLifeOk
                    }
                }
                if !inst.isDeath && typeHasDeath {
                    inst.isDeath = parent.isDeath
                }
            }
            
            if inst.isDeath && spawnType == .eventFollow {
                inst.particlesVec.removeAll(keepingCapacity: true)
            }
            
            if !inst.isDeath {
                for em in emitters {
                    em(&inst.particlesVec, initializers, maxcount, particleTime)
                }
            }
            
            if spawnType == .eventDeath {
                inst.isDeath = true
            }
            
            var hasLive = false
            
            inst.particlesVec.withUnsafeMutableBufferPointer { buffer in
                var info = ParticleInfo(particles: buffer, controlpoints: controlpoints, time: time, time_pass: particleTime)
                
                for i in 0..<buffer.count {
                    if ParticleModify.isNew(buffer[i]) {
                        for child in children {
                            if child.spawnType == .eventFollow || child.spawnType == .eventSpawn {
                                spawnInst(inst, child, i)
                            }
                        }
                    }
                    
                    ParticleModify.markOld(&buffer[i])
                    if !ParticleModify.lifetimeOk(buffer[i]) {
                        continue
                    }
                    
                    ParticleModify.reset(&buffer[i])
                    ParticleModify.changeLifetime(&buffer[i], -particleTime)
                    
                    if !ParticleModify.lifetimeOk(buffer[i]) {
                        for child in children {
                            if child.spawnType == .eventDeath {
                                spawnInst(inst, child, i)
                            }
                        }
                    } else {
                        hasLive = true
                    }
                }
                
                for op in operators {
                    op(&info)
                }
            }
            
            inst.isNoLiveParticle = !hasLive
        }
        
        for child in children {
            child.emitt(frameTime: frameTime)
        }
    }
}

class ParticleSystem {
    var subsystems: [ParticleSubSystem] = []
    var frameTime: Double = 0.016
    
    func emitt() {
        for el in subsystems {
            el.emitt(frameTime: frameTime)
        }
    }
}
