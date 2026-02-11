//
//  ParticleSystem.swift
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

import Foundation
import Metal
import simd

class ParticleInstance {
    class BoundedData {
        weak var parent: ParticleInstance?
        var particleIdx: Int = -1
        var preLifetimeOk: Bool = true
        var pos: SIMD3<Float> = .zero
    }

    var isDeath: Bool = false
    var noLiveParticle: Bool = false
    var particles: [Particle] = []
    var boundedData: BoundedData = BoundedData()

    func refresh() {
        isDeath = false
        noLiveParticle = false
        boundedData = BoundedData()
        particles.removeAll()
    }
}

class ParticleSubSystem {
    weak var system: ParticleSystem?

    var emitters: [ParticleEmittOp] = []
    var initializers: [ParticleInitOp] = []
    var operators: [ParticleOperatorOp] = []
    var controlPoints: [ParticleControlPoint] = Array(
        repeating: ParticleControlPoint(),
        count: 8
    )

    var children: [ParticleSubSystem] = []
    var instances: [ParticleInstance] = []

    var maxCount: Int
    var rate: Float
    var maxCountInstance: Int
    var probability: Float
    var spawnType: ParticleSpawnType

    var material: WPMaterial = WPMaterial()
    var texture: MTLTexture?
    var sequenceMultiplier: Float = 1.0

    var time: Double = 0

    init(
        system: ParticleSystem,
        maxCount: Int,
        rate: Float,
        maxCountInstance: Int,
        probability: Float,
        spawnType: ParticleSpawnType
    ) {
        self.system = system
        self.maxCount = maxCount
        self.rate = rate
        self.maxCountInstance = maxCountInstance
        self.probability = probability
        self.spawnType = spawnType
    }

    func addEmitter(_ op: @escaping ParticleEmittOp) { emitters.append(op) }
    func addInitializer(_ op: @escaping ParticleInitOp) {
        initializers.append(op)
    }
    func addOperator(_ op: @escaping ParticleOperatorOp) {
        operators.append(op)
    }
    func addChild(_ child: ParticleSubSystem) { children.append(child) }

    func queryNewInstance() -> ParticleInstance? {
        if ParticleMath.randomFloat() <= probability {
            for inst in instances {
                if inst.isDeath && inst.noLiveParticle {
                    inst.refresh()
                    return inst
                }
            }
            if instances.count < maxCountInstance {
                let newInst = ParticleInstance()
                instances.append(newInst)
                return newInst
            }
        }
        return nil
    }

    func emitt(frameTime: Double) {
        let particleTime = frameTime
        time += particleTime

        if spawnType == .static {
            if instances.isEmpty {
                instances.append(ParticleInstance())
            }
        }

        let globalCountMult = system?.countMultiplier ?? 1.0
        let effectiveRate = rate * globalCountMult
        let effectiveMaxCount = Int(Float(maxCount) * globalCountMult)

        for inst in instances {
            let bounded = inst.boundedData
            let typeHasDeath =
                (spawnType == .eventSpawn || spawnType == .eventFollow)

            if let parent = bounded.parent {
                if bounded.particleIdx != -1
                    && bounded.particleIdx < parent.particles.count
                {
                    let p = parent.particles[bounded.particleIdx]
                    bounded.pos = p.position

                    if spawnType == .eventDeath { bounded.particleIdx = -1 }

                    if !inst.isDeath && typeHasDeath {
                        let curLifeOk = p.lifetime > 0
                        inst.isDeath = !curLifeOk && bounded.preLifetimeOk
                        bounded.preLifetimeOk = curLifeOk
                    }
                }

                if !inst.isDeath && typeHasDeath {
                    inst.isDeath = parent.isDeath
                }
            }

            if inst.isDeath && spawnType == .eventFollow {
                inst.particles.removeAll()
            }

            if !inst.isDeath {
                for em in emitters {
                    em(
                        &inst.particles,
                        initializers,
                        effectiveMaxCount,
                        particleTime * Double(effectiveRate)
                    )
                }
            }

            if spawnType == .eventDeath { inst.isDeath = true }

            var hasLive = false

            inst.particles.withUnsafeMutableBufferPointer { buffer in
                let info = ParticleInfo(
                    particles: buffer,
                    controlPoints: controlPoints,
                    time: time,
                    timePass: particleTime
                )

                for i in 0..<buffer.count {
                    if buffer[i].markNew {
                        spawnChildren(
                            parentInst: inst,
                            idx: i,
                            typeCheck: {
                                $0 == .eventFollow || $0 == .eventSpawn
                            }
                        )
                    }

                    buffer[i].markNew = false

                    if buffer[i].lifetime <= 0 { continue }

                    buffer[i].alpha = buffer[i].initValue.alpha
                    buffer[i].size = buffer[i].initValue.size
                    buffer[i].color = buffer[i].initValue.color
                    buffer[i].lifetime -= Float(particleTime)

                    if buffer[i].lifetime <= 0 {
                        spawnChildren(
                            parentInst: inst,
                            idx: i,
                            typeCheck: { $0 == .eventDeath }
                        )
                    } else {
                        hasLive = true
                    }
                }

                for op in operators {
                    op(info)
                }
            }

            inst.noLiveParticle = !hasLive
        }

        for child in children {
            child.emitt(frameTime: frameTime)
        }
    }

    func spawnChildren(
        parentInst: ParticleInstance,
        idx: Int,
        typeCheck: (ParticleSpawnType) -> Bool
    ) {
        for child in children {
            if typeCheck(child.spawnType) {
                if let nInst = child.queryNewInstance() {
                    nInst.boundedData.parent = parentInst
                    nInst.boundedData.particleIdx = idx
                }
            }
        }
    }
}

class ParticleSystem {
    var subSystems: [ParticleSubSystem] = []
    var countMultiplier: Float = 1.0
    var speedMultiplier: Float = 1.0
    var sizeMultiplier: Float = 1.0

    func update(dt: Double) {
        let scaledDt = dt * Double(speedMultiplier)
        for sys in subSystems {
            sys.emitt(frameTime: scaledDt)
        }
    }
}
