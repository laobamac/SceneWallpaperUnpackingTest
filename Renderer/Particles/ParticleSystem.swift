//
//  ParticleSystem.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import simd

class ParticleSystem {
    let def: ParticleSystemDef
    var particles: [ParticleInstance]
    var count: Int = 0
    var maxParticles: Int

    var emitters: [ParticleEmitter] = []
    var initializers: [ParticleInitializer] = []
    var operators: [ParticleOperator] = []

    var time: Float = 0.0
    var spritesheetFrames: Int = 0
    var spritesheetDuration: Float = 0.0

    init(def: ParticleSystemDef) {
        self.def = def
        self.maxParticles = def.maxcount ?? 1000
        self.particles = Array(
            repeating: ParticleInstance(),
            count: maxParticles
        )

        if let emDefs = def.emitter {
            for emDef in emDefs {
                if emDef.name == "sphererandom" {
                    emitters.append(SphereRandomEmitter(def: emDef))
                } else if emDef.name == "boxrandom" {
                    emitters.append(BoxRandomEmitter(def: emDef))
                }
            }
        }

        if let initDefs = def.initializer {
            for initDef in initDefs {
                switch initDef.name {
                case "colorrandom":
                    initializers.append(ColorRandomInitializer(def: initDef))
                case "sizerandom":
                    initializers.append(SizeRandomInitializer(def: initDef))
                case "alpharandom":
                    initializers.append(AlphaRandomInitializer(def: initDef))
                case "lifetimerandom":
                    initializers.append(LifetimeRandomInitializer(def: initDef))
                case "velocityrandom":
                    initializers.append(VelocityRandomInitializer(def: initDef))
                case "rotationrandom":
                    initializers.append(RotationRandomInitializer(def: initDef))
                case "angularvelocityrandom":
                    initializers.append(
                        AngularVelocityRandomInitializer(def: initDef)
                    )
                case "turbulentvelocityrandom":
                    initializers.append(
                        TurbulentVelocityRandomInitializer(def: initDef)
                    )
                case "mapsequencearoundcontrolpoint":
                    initializers.append(
                        MapSequenceAroundControlPointInitializer(def: initDef)
                    )
                default: break
                }
            }
        }

        if let opDefs = def.operator {
            for opDef in opDefs {
                switch opDef.name {
                case "movement": operators.append(MovementOperator(def: opDef))
                case "angularmovement":
                    operators.append(AngularMovementOperator(def: opDef))
                case "alphafade":
                    operators.append(AlphaFadeOperator(def: opDef))
                case "sizechange":
                    operators.append(SizeChangeOperator(def: opDef))
                case "alphachange":
                    operators.append(AlphaChangeOperator(def: opDef))
                case "colorchange":
                    operators.append(ColorChangeOperator(def: opDef))
                case "turbulence":
                    operators.append(TurbulenceOperator(def: opDef))
                case "vortex", "vortex_v2":
                    operators.append(VortexOperator(def: opDef))
                case "controlpointattract":
                    operators.append(ControlPointAttractOperator(def: opDef))
                case "oscillatealpha":
                    operators.append(OscillateAlphaOperator(def: opDef))
                case "oscillatesize":
                    operators.append(OscillateSizeOperator(def: opDef))
                case "oscillateposition":
                    operators.append(OscillatePositionOperator(def: opDef))
                default: break
                }
            }
        }
    }

    func update(
        dt: Float,
        controlPoints: [ControlPointData],
        instanceOverride: ParticleInstanceOverride?,
        isOrthographic: Bool,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    ) {
        time += dt

        for i in 0..<emitters.count {
            emitters[i].emit(
                particles: &particles,
                count: &count,
                dt: dt,
                controlPoints: controlPoints,
                initializers: initializers,
                instanceOverride: instanceOverride,
                isOrthographic: isOrthographic
            )
        }

        for i in 0..<count {
            particles[i].age += dt
        }

        for i in 0..<operators.count {
            operators[i].apply(
                particles: &particles,
                count: count,
                controlPoints: controlPoints,
                currentTime: time,
                dt: dt,
                instanceOverride: instanceOverride,
                globalGravity: globalGravity,
                globalWind: globalWind
            )
        }

        let animSpeed = def.sequencemultiplier ?? 1.0
        let animMode = def.animationmode ?? "sequence"

        for i in 0..<count {
            if spritesheetFrames > 0 {
                let lifetimePos = particles[i].lifetimePos
                if animMode == "randomframe" {
                    if particles[i].frame < 0.0 {
                        particles[i].frame = Float(
                            Int.random(in: 0..<spritesheetFrames)
                        )
                    }
                } else if animMode == "once" {
                    particles[i].frame = min(
                        lifetimePos * Float(spritesheetFrames) * animSpeed,
                        Float(spritesheetFrames - 1)
                    )
                } else {
                    if spritesheetDuration > 0.0 {
                        let timeInCycle = fmod(
                            particles[i].age * animSpeed,
                            spritesheetDuration
                        )
                        let cyclePos = timeInCycle / spritesheetDuration
                        particles[i].frame = fmod(
                            cyclePos * Float(spritesheetFrames),
                            Float(spritesheetFrames)
                        )
                    } else {
                        particles[i].frame = fmod(
                            lifetimePos * Float(spritesheetFrames) * animSpeed,
                            Float(spritesheetFrames)
                        )
                    }
                }
            }
        }

        var writeIdx = 0
        for readIdx in 0..<count {
            if particles[readIdx].isAlive {
                if writeIdx != readIdx {
                    particles[writeIdx] = particles[readIdx]
                }
                writeIdx += 1
            }
        }
        count = writeIdx
    }
}
