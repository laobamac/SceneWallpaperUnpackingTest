//
//  ParticleSystem.swift
//  Renderer
//
//  Created by laobamac on 2026/2/14.
//

import Foundation
import simd

typealias ParticleOperatorOp = (inout Particle, Float) -> Void

class ParticleInstance {
    var name: String = ""
    var particles: [Particle] = []
    var initializers: [ParticleInitOp] = []
    var operators: [ParticleOperatorOp] = []
    var emitter: ParticleEmittOp?
    var generator: ParticleGenerator?
    var materialPath: String = ""
    
    var maxCount: Int = 100
    var emitRate: Float = 10.0
    var particleLifetime: Float = 1.0
    var isTrail: Bool = false
    var trailLength: Float = 0.5
    
    func update(dt: Float) {
        if let emit = emitter {
            emit(&particles, initializers, UInt32(maxCount), dt)
        }
        
        var aliveParticles: [Particle] = []
        aliveParticles.reserveCapacity(particles.count)
        
        for i in 0..<particles.count {
            var p = particles[i]
            ParticleModify.changeLifetime(p: &p, l: -dt)
            if ParticleModify.lifetimeOk(p: p) {
                ParticleModify.reset(p: &p)
                for op in operators {
                    op(&p, dt)
                }
                ParticleModify.markOld(p: &p)
                aliveParticles.append(p)
            }
        }
        particles = aliveParticles
    }
    
    func emit(at position: SIMD3<Float>, count: Int) {
        guard let gen = generator else { return }
        var spawned = 0
        while spawned < count {
            if particles.count < maxCount {
                var p = gen(position)
                for ini in initializers { ini(&p, 0) }
                particles.append(p)
            } else {
                if let idx = particles.firstIndex(where: { !ParticleModify.lifetimeOk(p: $0) }) {
                    var p = gen(position)
                    for ini in initializers { ini(&p, 0) }
                    particles[idx] = p
                } else {
                    break
                }
            }
            spawned += 1
        }
    }
}

class ParticleSubSystem {
    var instance: ParticleInstance?
    var children: [ParticleSubSystem] = []
    var type: String = ""
    var emitAccumulator: Float = 0.0
    
    func update(dt: Float) {
        instance?.update(dt: dt)
        
        for child in children {
            if child.type == "eventfollow", let parentInst = instance {
                child.emitAccumulator += dt
                let rate = child.instance?.emitRate ?? 10
                let interval = 1.0 / rate
                
                let count = Int(child.emitAccumulator / interval)
                if count > 0 {
                    child.emitAccumulator -= Float(count) * interval
                    for p in parentInst.particles {
                        child.instance?.emit(at: p.position, count: count)
                    }
                }
            }
            child.update(dt: dt)
        }
    }
    
    func getAllInstances(into result: inout [ParticleInstance]) {
        if let i = instance { result.append(i) }
        for child in children {
            child.getAllInstances(into: &result)
        }
    }
}

class ParticleSystem {
    var root: ParticleSubSystem?
    var allInstances: [ParticleInstance] = []
    
    init(file: URL, base: URL) {
        Logger.log("ParticleSystem init file: \(file.path)")
        do {
            let data = try Data(contentsOf: file)
            
            if let systemJson = try? JSONDecoder().decode(ParticleSystemJSON.self, from: data), let rootNode = systemJson.root {
                self.root = ParticleBuilder.build(root: rootNode, base: base)
                Logger.log("ParticleSystem built from 'root' property.")
            }
            else if let directNode = try? JSONDecoder().decode(ParticleChildJSON.self, from: data) {
                self.root = ParticleBuilder.build(root: directNode, base: base)
                Logger.log("ParticleSystem built from direct JSON structure.")
            } else {
                Logger.log("ParticleSystem JSON format not recognized or empty.")
            }
        } catch {
            Logger.error("Failed to load particle system JSON: \(error)")
        }
        root?.getAllInstances(into: &allInstances)
        Logger.log("ParticleSystem total instances: \(allInstances.count)")
    }
    
    func update(deltaTime: Float) {
        root?.update(dt: deltaTime)
    }
}
