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
}

class ParticleSubSystem {
    var instance: ParticleInstance?
    var children: [ParticleSubSystem] = []
    
    func update(dt: Float) {
        instance?.update(dt: dt)
        for child in children {
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
