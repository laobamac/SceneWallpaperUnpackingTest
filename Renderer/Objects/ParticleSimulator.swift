//
//  ParticleSimulator.swift
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

import Foundation
import simd

class ParticleSimulator {
    typealias EmitterFunc = (inout [ParticleInstance], inout Int, Float) -> Void
    typealias InitializerFunc = (inout ParticleInstance) -> Void
    typealias OperatorFunc = (inout [ParticleInstance], Int, [ControlPointData], Float, Float) -> Void

    let particleDefinition: ParticleDefinition
    let instanceOverride: ParticleInstanceOverride?
    let baseObject: SceneObject

    var particles: [ParticleInstance]
    var particleCount: Int = 0
    let maxParticles: Int

    var emitters: [EmitterFunc] = []
    var initializers: [InitializerFunc] = []
    var operators: [OperatorFunc] = []
    var controlPoints: [ControlPointData]

    var time: Float = 0.0
    var transformedOrigin: SIMD3<Float> = .zero

    let defaultMaxParticles: Int = 1000

    init(definition: ParticleDefinition, override: ParticleInstanceOverride?, baseObject: SceneObject) {
        self.particleDefinition = definition
        self.instanceOverride = override
        self.baseObject = baseObject

        var countMultiplier: Float = 1.0
        if let ov = override, let c = ov.count {
            countMultiplier = c.floatValue
        }

        let baseMax = definition.maxcount ?? defaultMaxParticles
        self.maxParticles = baseMax > 0 ? Int(Float(baseMax) * countMultiplier) : defaultMaxParticles
        self.particles = Array(repeating: ParticleInstance(), count: self.maxParticles)

        self.controlPoints = Array(repeating: ControlPointData(), count: 8)
        if let cps = definition.controlpoint {
            for cp in cps {
                if let id = cp.id, id >= 0, id < 8 {
                    self.controlPoints[id].offset = cp.offset?.float3Value ?? .zero
                    let flags = cp.flags ?? 0
                    self.controlPoints[id].linkMouse = (flags & 1) != 0
                    self.controlPoints[id].worldSpace = (flags & 2) != 0

                    if !self.controlPoints[id].linkMouse {
                        if self.controlPoints[id].worldSpace {
                            self.controlPoints[id].position = self.controlPoints[id].offset - self.transformedOrigin
                        } else {
                            self.controlPoints[id].position = self.controlPoints[id].offset
                        }
                    }
                }
            }
        }

        setupEmitters()
        setupInitializers()
        setupOperators()
    }

    func update(dt: Float, currentTime: Float, screenWidth: Float, screenHeight: Float, mousePos: CGPoint?) {
        self.time = currentTime

        var origin = baseObject.origin?.float3Value ?? .zero
        origin.x -= screenWidth / 2.0
        origin.y = screenHeight / 2.0 - origin.y
        self.transformedOrigin = origin

        for i in 0..<controlPoints.count {
            if !controlPoints[i].linkMouse && controlPoints[i].worldSpace {
                controlPoints[i].position = controlPoints[i].offset - transformedOrigin
            }
        }

        if let m = mousePos {
            for i in 0..<controlPoints.count {
                if controlPoints[i].linkMouse {
                    var position = SIMD3<Float>()
                    position.x = (Float(m.x) * screenWidth) - (screenWidth / Float(2.0))
                    position.y = (screenHeight / Float(2.0)) - (Float(m.y) * screenHeight)
                    position.z = 0.0
                    position += controlPoints[i].offset
                    controlPoints[i].position = position - transformedOrigin
                }
            }
        }

        for emitter in emitters {
            emitter(&particles, &particleCount, dt)
        }

        for i in 0..<particleCount {
            particles[i].age += dt
        }

        for op in operators {
            op(&particles, particleCount, controlPoints, time, dt)
        }

        let sequenceMultiplier = particleDefinition.sequencemultiplier ?? 1.0
        let animMode = particleDefinition.animationmode ?? "sequence"
        let texFrames = 1
        let texDuration: Float = 1.0
        
        for i in 0..<particleCount {
            let p = particles[i]
            if texFrames > 0 {
                let lifetimePos = p.getLifetimePos()
                let animSpeed = sequenceMultiplier > 0.0 ? sequenceMultiplier : 1.0

                if animMode == "randomframe" {
                    if p.frame < 0.0 {
                        particles[i].frame = Float(Int.random(in: 0..<texFrames))
                    }
                } else if animMode == "once" {
                    particles[i].frame = min(lifetimePos * Float(texFrames) * animSpeed, Float(texFrames - 1))
                } else {
                    let timeInCycle = fmod(p.age * animSpeed, texDuration)
                    let cyclePos = timeInCycle / texDuration
                    particles[i].frame = fmod(cyclePos * Float(texFrames), Float(texFrames))
                }
            }
        }

        var writeIdx = 0
        for readIdx in 0..<particleCount {
            if particles[readIdx].isAlive() {
                if writeIdx != readIdx {
                    particles[writeIdx] = particles[readIdx]
                }
                writeIdx += 1
            }
        }
        particleCount = writeIdx
    }
}
