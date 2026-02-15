//
//  ParticleBuilder.swift
//  Renderer
//
//  Created by laobamac on 2026/2/14.
//

import Foundation
import simd

class ParticleBuilder {
    
    static func build(root: ParticleChildJSON, base: URL) -> ParticleSubSystem? {
        let sys = ParticleSubSystem()
        sys.instance = buildInstance(json: root, base: base)
        
        if let children = root.children {
            for child in children {
                if let sub = build(root: child, base: base) {
                    sys.children.append(sub)
                }
            }
        }
        return sys
    }
    
    static func buildInstance(json: ParticleChildJSON, base: URL) -> ParticleInstance {
        let inst = ParticleInstance()
        inst.maxCount = json.maxcount ?? 100
        inst.name = json.name ?? "particle"
        
        if let mat = json.material {
            inst.materialPath = mat
        } else if let tex = json.texture {
            inst.materialPath = tex
        }
        
        if let rate = json.rate {
            inst.emitRate = rate
        } else if let count = json.count {
            inst.emitRate = Float(count)
        }
        
        inst.particleLifetime = json.lifetime ?? 1.0
        
        if let inits = json.initializers {
            for mod in inits {
                if let op = genParticleInitOp(json: mod) {
                    inst.initializers.append(op)
                }
            }
        }
        
        if let ops = json.operators {
            for mod in ops {
                if let op = genParticleOperatorOp(json: mod) {
                    inst.operators.append(op)
                }
            }
        }
        
        if let renderers = json.renderers {
            for mod in renderers {
                if mod.name == "trail" {
                    inst.isTrail = true
                    inst.trailLength = mod.time ?? 0.5
                }
            }
        }
        
        if let emitters = json.emitters {
            for mod in emitters {
                if let em = genEmitterOp(json: mod, inst: inst) {
                    inst.emitter = em
                }
            }
        } else {
             var args = ParticleBoxEmitterArgs(
                 directions: SIMD3<Float>(1,1,1),
                 minDistance: SIMD3<Float>(0,0,0),
                 maxDistance: SIMD3<Float>(0,0,0),
                 emitSpeed: inst.emitRate,
                 origin: SIMD3<Float>(0,0,0),
                 one_per_frame: false,
                 sort: false,
                 instantaneous: 0,
                 minSpeed: 0,
                 maxSpeed: 0
             )
             inst.emitter = ParticleBoxEmitterArgs.makeEmittOp(args: args)
        }
        
        return inst
    }
    
    static func genEmitterOp(json: ParticleModuleJSON, inst: ParticleInstance) -> ParticleEmittOp? {
        guard let name = json.name else { return nil }
        
        if name == "sphere" || name == "sphererandom" {
            var args = ParticleSphereEmitterArgs(
                directions: SIMD3<Float>(1,1,1),
                minDistance: json.distanceinner ?? 0,
                maxDistance: json.distanceouter ?? (json.distancemax?.floatValue ?? 0),
                emitSpeed: inst.emitRate,
                origin: SIMD3<Float>(0,0,0),
                sign: SIMD3<Int32>(1,1,1),
                one_per_frame: false,
                sort: false,
                instantaneous: 0,
                minSpeed: json.speedinner ?? (json.speedmin ?? 0),
                maxSpeed: json.speedouter ?? (json.speedmax ?? 0)
            )
            if let origin = json.origin {
                let parts = origin.components(separatedBy: " ").compactMap { Float($0) }
                if parts.count >= 3 { args.origin = SIMD3<Float>(parts[0], parts[1], parts[2]) }
            }
            if let dir = json.directions {
                let parts = dir.components(separatedBy: " ").compactMap { Float($0) }
                if parts.count >= 3 { args.directions = SIMD3<Float>(parts[0], parts[1], parts[2]) }
            }
            return ParticleSphereEmitterArgs.makeEmittOp(args: args)
            
        } else if name == "box" || name == "boxrandom" {
            var args = ParticleBoxEmitterArgs(
                directions: SIMD3<Float>(1,1,1),
                minDistance: SIMD3<Float>(0,0,0),
                maxDistance: SIMD3<Float>(0,0,0),
                emitSpeed: inst.emitRate,
                origin: SIMD3<Float>(0,0,0),
                one_per_frame: false,
                sort: false,
                instantaneous: 0,
                minSpeed: json.speedmin ?? 0,
                maxSpeed: json.speedmax ?? 0
            )
            if let x = json.x, case .float(let f) = x { args.maxDistance.x = f; args.minDistance.x = -f }
            if let y = json.y, case .float(let f) = y { args.maxDistance.y = f; args.minDistance.y = -f }
            if let z = json.z, case .float(let f) = z { args.maxDistance.z = f; args.minDistance.z = -f }
            
            if let origin = json.origin {
                let parts = origin.components(separatedBy: " ").compactMap { Float($0) }
                if parts.count >= 3 { args.origin = SIMD3<Float>(parts[0], parts[1], parts[2]) }
            }
            if let dir = json.directions {
                let parts = dir.components(separatedBy: " ").compactMap { Float($0) }
                if parts.count >= 3 { args.directions = SIMD3<Float>(parts[0], parts[1], parts[2]) }
            }
            return ParticleBoxEmitterArgs.makeEmittOp(args: args)
        }
        
        return nil
    }
    
    static func genParticleInitOp(json: ParticleModuleJSON) -> ParticleInitOp? {
        guard let name = json.name else { return nil }
        
        switch name {
        case "lifetimerandom":
            let r = SingleRandom.from(json: json)
            return { (p, t) in
                let val = Float.random(in: r.min...r.max)
                ParticleModify.initLifetime(p: &p, l: val)
            }
        case "rotationspeedrandom", "angularvelocityrandom":
             let r = SingleRandom.from(json: json)
             return { (p, t) in
                 let val = Float.random(in: r.min...r.max)
                 ParticleModify.initAngularVelocity(p: &p, v: SIMD3<Float>(0, 0, val))
             }
        case "rotationrandom":
            let r = VecRandom.from(json: json)
             return { (p, t) in
                 let x = Float.random(in: r.min.x...r.max.x)
                 let y = Float.random(in: r.min.y...r.max.y)
                 let z = Float.random(in: r.min.z...r.max.z)
                 ParticleModify.changeRotation(p: &p, x: x, y: y, z: z)
             }
        case "sizerandom":
             let r = SingleRandom.from(json: json)
             return { (p, t) in
                 let val = Float.random(in: r.min...r.max)
                 ParticleModify.initSize(p: &p, s: val)
             }
        case "alpharandom":
            let r = SingleRandom.from(json: json)
            return { (p, t) in
                let val = Float.random(in: r.min...r.max)
                ParticleModify.initAlpha(p: &p, a: val)
            }
        case "alphafade":
            let v = ValueChange.from(json: json)
            return { (p, t) in
                ParticleModify.initAlpha(p: &p, a: v.startvalue)
            }
        case "colorrandom":
            let r = VecRandom.from(json: json)
            return { (p, t) in
                let rv = SIMD3<Float>(
                    Float.random(in: r.min.x...r.max.x),
                    Float.random(in: r.min.y...r.max.y),
                    Float.random(in: r.min.z...r.max.z)
                )
                ParticleModify.initColor(p: &p, r: rv.x, g: rv.y, b: rv.z)
            }
        case "velocityrandom":
            let r = VecRandom.from(json: json)
            return { (p, t) in
                let rv = SIMD3<Float>(
                    Float.random(in: r.min.x...r.max.x),
                    Float.random(in: r.min.y...r.max.y),
                    Float.random(in: r.min.z...r.max.z)
                )
                ParticleModify.changeVelocity(p: &p, v: rv)
            }
        case "turbulentvelocityrandom":
            let scale = json.scale ?? 1.0
            let minS = json.speedmin ?? 0.0
            let maxS = json.speedmax ?? 100.0
            return { (p, t) in
                let randomDir = normalize(SIMD3<Float>(
                    Float.random(in: -1...1),
                    Float.random(in: -1...1),
                    Float.random(in: -1...1)
                ))
                let speed = Float.random(in: minS...maxS)
                ParticleModify.changeVelocity(p: &p, v: randomDir * speed * scale)
            }
        case "velocity":
             let r = VecRandom.from(json: json)
             return { (p, t) in
                 ParticleModify.changeVelocity(p: &p, v: r.min)
             }
        default:
            return nil
        }
    }
    
    static func genParticleOperatorOp(json: ParticleModuleJSON) -> ParticleOperatorOp? {
        guard let name = json.name else { return nil }
        
        switch name {
        case "movement":
            let drag = json.drag ?? 0.0
            var gravity = SIMD3<Float>(0,0,0)
            if let gStr = json.gravity {
                let parts = gStr.components(separatedBy: " ").compactMap { Float($0) }
                if parts.count >= 3 { gravity = SIMD3<Float>(parts[0], parts[1], parts[2]) }
            }
            return { (p, t) in
                ParticleModify.moveByTime(p: &p, t: t)
                ParticleModify.accelerate(p: &p, acc: gravity, t: t)
                if drag > 0 {
                    ParticleModify.multiplyVelocity(p: &p, m: 1.0 - (drag * t))
                }
            }
        case "alphafade":
            let v = ValueChange.from(json: json)
            return { (p, t) in
                let pos = ParticleModify.lifetimePos(p: p)
                if pos >= v.starttime && pos <= v.endtime {
                    let range = v.endtime - v.starttime
                    let localT = (pos - v.starttime) / (range > 0 ? range : 1.0)
                    let alpha = v.startvalue * (1.0 - localT) + v.endvalue * localT
                    ParticleModify.initAlpha(p: &p, a: alpha)
                }
            }
        case "oscillatealpha", "oscillatesize", "oscillateposition":
            let f = FrequencyValue.from(json: json, name: name)
            return { (p, t) in
                if ParticleModify.isNew(p: p) { return }
                let idx = abs(p.position.hashValue) % 128
                f.checkAndResize(size: 128)
                f.genFrequency(particle: p, index: idx)
                let lifetime = ParticleModify.lifetimePassed(p: p)
                
                if name == "oscillatealpha" {
                    let scale = f.getScale(index: idx, time: lifetime)
                    ParticleModify.multiplyAlpha(p: &p, a: scale)
                } else if name == "oscillatesize" {
                    let scale = f.getScale(index: idx, time: lifetime)
                    ParticleModify.multiplySize(p: &p, s: scale)
                } else if name == "oscillateposition" {
                    let move = f.getMove(index: idx, time: lifetime, timePass: t)
                    ParticleModify.move(p: &p, acc: f.mask * move)
                }
            }
        case "rotator":
             var speed: Float = 0
             if let s = json.speed, case .float(let f) = s { speed = f }
             let axisStr = json.axis ?? ""
             var axis = SIMD3<Float>(0,0,1)
             if !axisStr.isEmpty {
                 let parts = axisStr.components(separatedBy: " ").compactMap { Float($0) }
                 if parts.count >= 3 { axis = SIMD3<Float>(parts[0], parts[1], parts[2]) }
             }
             return { (p, t) in
                 ParticleModify.rotate(p: &p, r: axis * speed * t)
                 ParticleModify.rotateByTime(p: &p, t: t)
             }
        case "angularmovement":
            return { (p, t) in
                ParticleModify.rotateByTime(p: &p, t: t)
            }
        case "turbulence":
            let turb = TurbulentRandom.from(json: json)
            return { (p, t) in
                let life = ParticleModify.lifetimePassed(p: p)
                let pos = p.position * turb.scale - SIMD3<Float>(0, 0, life * turb.timescale)
                let vec = NoiseUtils.curlNoise(pos + SIMD3<Float>(turb.offset, 0, 0))
                var force = SIMD3<Float>(0,0,0)
                force += turb.forward * vec.x
                force += turb.right * vec.y
                force += turb.up * vec.z
                
                var strength: Float = 0
                if life < turb.phasemin { strength = 0 }
                else if life > turb.phasemax { strength = 1 }
                else { strength = (life - turb.phasemin) / (turb.phasemax - turb.phasemin) }
                
                let targetSpeed = turb.speedmin + (turb.speedmax - turb.speedmin) * strength
                ParticleModify.accelerate(p: &p, acc: force * targetSpeed, t: t)
            }
        case "vortex":
            let vor = Vortex.from(json: json)
            return { (p, t) in
                 let diff = p.position - vor.offset
                 let axis = normalize(vor.axis)
                 let proj = dot(diff, axis)
                 let center = vor.offset + axis * proj
                 let radVec = p.position - center
                 let dist = length(radVec)
                 
                 var force = SIMD3<Float>(0,0,0)
                 if dist > 0.001 {
                     let tan = normalize(cross(axis, radVec))
                     var speed = vor.speedinner
                     if dist > vor.distanceinner && dist < vor.distanceouter {
                         let f = (dist - vor.distanceinner) / (vor.distanceouter - vor.distanceinner)
                         speed = vor.speedinner * (1.0 - f) + vor.speedouter * f
                     } else if dist >= vor.distanceouter {
                         speed = vor.speedouter
                     }
                     force = tan * speed
                 }
                 ParticleModify.accelerate(p: &p, acc: force, t: t)
            }
        case "controlpointattract":
            let cp = ControlPointForce.from(json: json)
            return { (p, t) in
                ParticleModify.applyControlPointForce(p: &p, center: cp.origin, amount: cp.scale, threshold: cp.threshold, t: t)
            }
        case "color":
             let vc = VecChange.from(json: json)
             return { (p, t) in
                 let pos = ParticleModify.lifetimePos(p: p)
                 if pos >= vc.starttime && pos <= vc.endtime {
                      let range = vc.endtime - vc.starttime
                      let localT = (pos - vc.starttime) / (range > 0 ? range : 1.0)
                      let c = vc.startvalue * (1.0 - localT) + vc.endvalue * localT
                      ParticleModify.initColor(p: &p, r: c.x, g: c.y, b: c.z)
                 }
             }
        default:
            return nil
        }
    }
}

extension ParticleModuleJSON {
    var time: Float? {
        if let t = fadeintime { return t }
        return nil
    }
}

extension ScriptableValue {
    var floatValue: Float? {
        switch self {
        case .float(let f): return f
        case .string(let s): return Float(s)
        default: return nil
        }
    }
}
