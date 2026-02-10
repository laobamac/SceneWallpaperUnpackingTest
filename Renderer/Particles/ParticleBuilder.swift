//
//  ParticleBuilder.swift
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

import Foundation
import simd

class ParticleBuilder {
    static func buildSystem(from particleJSON: [String: Any], baseFolder: URL) -> ParticleSystem? {
        let sys = ParticleSystem()
        if let sub = parseParticleObject(json: particleJSON, parentJSON: nil, baseFolder: baseFolder) {
            sys.subSystems.append(sub)
            return sys
        }
        return nil
    }
    
    private static func parseParticleObject(json: [String: Any], parentJSON: [String: Any]?, baseFolder: URL) -> ParticleSubSystem? {
        guard let emittersJSON = json["emitter"] as? [[String: Any]] else {
            Logger.error("No emitters in particle object")
            return nil
        }
        
        var maxCount = 100
        if let mc = json["maxcount"] as? Int { maxCount = mc }
        
        let sub = ParticleSubSystem(system: ParticleSystem(), maxCount: maxCount, rate: 1.0, maxCountInstance: 1, probability: 1.0, spawnType: .static)
        
        if let matPath = json["material"] as? String {
            sub.material.fileName = matPath
            do {
                let matURL = baseFolder.appendingPathComponent("materials/\(matPath)")
                let finalMatURL = FileManager.default.fileExists(atPath: matURL.path) ? matURL : baseFolder.appendingPathComponent("assets/\(matPath)")
                
                if FileManager.default.fileExists(atPath: finalMatURL.path) {
                    let data = try Data(contentsOf: finalMatURL)
                    if let matJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let passes = matJSON["passes"] as? [[String: Any]], let first = passes.first, let renderer = first["shader"] as? String {
                             sub.material.renderer = renderer
                        }
                    }
                }
            } catch {
                Logger.error("Failed to parse material \(matPath)")
            }
        }
        
        if let instanceOverride = parentJSON?["instanceoverride"] as? [String: Any] {
            let over = parseInstanceOverride(json: instanceOverride)
            sub.addInitializer(ParticleModules.overrideInit(over: over))
        }
        
        for em in emittersJSON {
            if let op = parseEmitter(json: em) {
                sub.addEmitter(op)
            }
        }
        
        if let inits = json["initializer"] as? [[String: Any]] {
            for ini in inits {
                if let op = parseInitializer(json: ini) {
                    sub.addInitializer(op)
                }
            }
        }
        
        if let ops = json["operator"] as? [[String: Any]] {
            for op in ops {
                if let oper = parseOperator(json: op) {
                    sub.addOperator(oper)
                }
            }
        }
        
        if let children = json["children"] as? [[String: Any]] {
            for childJSON in children {
                if let childSub = parseChild(json: childJSON, baseFolder: baseFolder) {
                    sub.addChild(childSub)
                }
            }
        }
        
        if let cps = json["controlpoint"] as? [[String: Any]] {
            for cp in cps {
                var pcp = ParticleControlPoint()
                if let id = cp["id"] as? Int { pcp.id = id }
                if let off = cp["offset"] as? String { pcp.offset = parseVec3(off) }
                if let flags = cp["flags"] as? Int {
                    if (flags & 1) != 0 { pcp.linkMouse = true }
                    if (flags & 2) != 0 { pcp.worldSpace = true }
                }
                if pcp.id >= 0 && pcp.id < 8 {
                    sub.controlPoints[pcp.id] = pcp
                }
            }
        }
        
        return sub
    }
    
    private static func parseChild(json: [String: Any], baseFolder: URL) -> ParticleSubSystem? {
        guard let name = json["name"] as? String else { return nil }
        guard let typeStr = json["type"] as? String, let type = ParticleSpawnType(rawValue: typeStr) else { return nil }
        
        var childURL = baseFolder.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: childURL.path) {
            childURL = baseFolder.appendingPathComponent("assets/\(name)")
        }
        if !FileManager.default.fileExists(atPath: childURL.path) {
            childURL = baseFolder.appendingPathComponent("particles/\(name)")
        }
        
        do {
            let data = try Data(contentsOf: childURL)
            guard let childParticleJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            
            if let childSub = parseParticleObject(json: childParticleJSON, parentJSON: nil, baseFolder: baseFolder) {
                childSub.spawnType = type
                if let mc = json["maxcount"] as? Int { childSub.maxCountInstance = mc }
                if let prob = json["probability"] as? Float { childSub.probability = prob }
                return childSub
            }
        } catch {
            Logger.error("Failed to load child particle \(name) at \(childURL.path): \(error)")
        }
        return nil
    }
    
    private static func parseEmitter(json: [String: Any]) -> ParticleEmittOp? {
        guard let name = json["name"] as? String else { return nil }
        let rate = (json["rate"] as? Float) ?? 5.0
        let distMin = parseVec3(json["distancemin"])
        let distMax = parseVec3(json["distancemax"])
        let dirs = parseVec3(json["directions"], defaultVal: SIMD3<Float>(1,1,1))
        let origin = parseVec3(json["origin"])
        let speedMin = (json["speedmin"] as? Float) ?? 0
        let speedMax = (json["speedmax"] as? Float) ?? 0
        let instant = (json["instantaneous"] as? Int) ?? 0
        
        if name == "boxrandom" {
            let box = ParticleBoxEmitter(directions: dirs, minDistance: distMin, maxDistance: distMax, emitSpeed: rate, origin: origin, onePerFrame: false, sort: false, instantaneous: instant, minSpeed: speedMin, maxSpeed: speedMax)
            return box.makeOp()
        } else if name == "sphererandom" {
            let sphere = ParticleSphereEmitter(directions: dirs, minDistance: distMin.x, maxDistance: distMax.x, emitSpeed: rate, origin: origin, sign: SIMD3<Int32>(0,0,0), onePerFrame: false, sort: false, instantaneous: instant, minSpeed: speedMin, maxSpeed: speedMax)
            return sphere.makeOp()
        }
        return nil
    }
    
    private static func parseInitializer(json: [String: Any]) -> ParticleInitOp? {
        guard let name = json["name"] as? String else { return nil }
        
        if name == "colorrandom" {
            let min = parseVec3(json["min"])
            let max = parseVec3(json["max"], defaultVal: SIMD3<Float>(255,255,255))
            return ParticleModules.colorRandom(min: min, max: max)
        } else if name == "lifetimerandom" {
            let min = (json["min"] as? Float) ?? 0
            let max = (json["max"] as? Float) ?? 1
            return ParticleModules.lifetimeRandom(min: min, max: max)
        } else if name == "sizerandom" {
            let min = (json["min"] as? Float) ?? 0
            let max = (json["max"] as? Float) ?? 20
            return ParticleModules.sizeRandom(min: min, max: max)
        } else if name == "alpharandom" {
            let min = (json["min"] as? Float) ?? 0.05
            let max = (json["max"] as? Float) ?? 1
            return ParticleModules.alphaRandom(min: min, max: max)
        } else if name == "velocityrandom" {
            let min = parseVec3(json["min"], defaultVal: SIMD3<Float>(-32,-32,-32))
            let max = parseVec3(json["max"], defaultVal: SIMD3<Float>(32,32,32))
            return ParticleModules.velocityRandom(min: min, max: max)
        } else if name == "turbulentvelocityrandom" {
            let scale = (json["scale"] as? Float) ?? 1
            let timeScale = (json["timescale"] as? Double) ?? 1
            let offset = (json["offset"] as? Float) ?? 0
            let speedMin = (json["speedmin"] as? Float) ?? 100
            let speedMax = (json["speedmax"] as? Float) ?? 250
            let phaseMin = (json["phasemin"] as? Float) ?? 0
            let phaseMax = (json["phasemax"] as? Float) ?? 0.1
            let fwd = parseVec3(json["forward"], defaultVal: SIMD3<Float>(0,1,0))
            let right = parseVec3(json["right"], defaultVal: SIMD3<Float>(0,0,1))
            return ParticleModules.turbulentVelocityRandom(scale: scale, timeScale: timeScale, offset: offset, speedMin: speedMin, speedMax: speedMax, phaseMin: phaseMin, phaseMax: phaseMax, forward: fwd, right: right)
        }
        return nil
    }
    
    private static func parseOperator(json: [String: Any]) -> ParticleOperatorOp? {
        guard let name = json["name"] as? String else { return nil }
        
        if name == "movement" {
            let drag = (json["drag"] as? Float) ?? 0
            let grav = parseVec3(json["gravity"])
            return ParticleModules.movement(drag: drag, gravity: grav)
        } else if name == "alphafade" {
            let fi = (json["fadeintime"] as? Float) ?? 0.5
            let fo = (json["fadeouttime"] as? Float) ?? 0.5
            return ParticleModules.alphaFade(fadeIn: fi, fadeOut: fo)
        } else if name == "sizechange" {
            let st = (json["starttime"] as? Float) ?? 0
            let et = (json["endtime"] as? Float) ?? 1
            let sv = (json["startvalue"] as? Float) ?? 1
            let ev = (json["endvalue"] as? Float) ?? 0
            return ParticleModules.sizeChange(start: st, end: et, valStart: sv, valEnd: ev, overSize: 1.0)
        } else if name == "colorchange" {
            let st = (json["starttime"] as? Float) ?? 0
            let et = (json["endtime"] as? Float) ?? 1
            let sv = parseVec3(json["startvalue"])
            let ev = parseVec3(json["endvalue"])
            return ParticleModules.colorChange(start: st, end: et, valStart: sv, valEnd: ev)
        } else if name == "oscillatealpha" {
            let fmin = (json["frequencymin"] as? Float) ?? 0
            let fmax = (json["frequencymax"] as? Float) ?? 10
            let smin = (json["scalemin"] as? Float) ?? 0
            let smax = (json["scalemax"] as? Float) ?? 1
            let pmin = (json["phasemin"] as? Float) ?? 0
            let pmax = (json["phasemax"] as? Float) ?? Float.pi*2
            return ParticleModules.oscillateAlpha(freqMin: fmin, freqMax: fmax, scaleMin: smin, scaleMax: smax, phaseMin: pmin, phaseMax: pmax)
        } else if name == "turbulence" {
            let pmin = (json["phasemin"] as? Float) ?? 0
            let pmax = (json["phasemax"] as? Float) ?? 0
            let smin = (json["speedmin"] as? Float) ?? 500
            let smax = (json["speedmax"] as? Float) ?? 1000
            let ts = (json["timescale"] as? Float) ?? 20
            let sc = (json["scale"] as? Float) ?? 0.01
            let mask = parseVec3Int(json["mask"], defaultVal: SIMD3<Int32>(1,1,0))
            return ParticleModules.turbulence(phaseMin: pmin, phaseMax: pmax, speedMin: smin, speedMax: smax, timeScale: ts, scale: sc, mask: mask)
        } else if name == "vortex" {
            let cp = (json["controlpoint"] as? Int) ?? 0
            let di = (json["distanceinner"] as? Float) ?? 500
            let do_ = (json["distanceouter"] as? Float) ?? 650
            let si = (json["speedinner"] as? Float) ?? 2500
            let so = (json["speedouter"] as? Float) ?? 0
            let off = parseVec3(json["offset"])
            let ax = parseVec3(json["axis"], defaultVal: SIMD3<Float>(0,0,1))
            return ParticleModules.vortex(controlPoint: cp, distInner: di, distOuter: do_, speedInner: si, speedOuter: so, offset: off, axis: ax)
        }
        return nil
    }
    
    private static func parseInstanceOverride(json: [String: Any]) -> ParticleInstanceOverride {
        var o = ParticleInstanceOverride()
        o.enabled = true
        if let v = json["alpha"] as? Float { o.alpha = v }
        if let v = json["size"] as? Float { o.size = v }
        if let v = json["lifetime"] as? Float { o.lifetime = v }
        if let v = json["rate"] as? Float { o.rate = v }
        if let v = json["speed"] as? Float { o.speed = v }
        if let v = json["count"] as? Float { o.count = v }
        if let c = json["color"] {
            o.color = parseVec3(c)
            o.overColor = true
        } else if let c = json["colorn"] {
            o.colorN = parseVec3(c)
            o.overColorN = true
        }
        return o
    }
    
    private static func parseVec3(_ json: Any?, defaultVal: SIMD3<Float> = .zero) -> SIMD3<Float> {
        if let str = json as? String {
            let parts = str.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 { return SIMD3<Float>(parts[0], parts[1], parts[2]) }
        } else if let arr = json as? [NSNumber], arr.count >= 3 {
            return SIMD3<Float>(arr[0].floatValue, arr[1].floatValue, arr[2].floatValue)
        }
        return defaultVal
    }
    
    private static func parseVec3Int(_ json: Any?, defaultVal: SIMD3<Int32> = .zero) -> SIMD3<Int32> {
         if let str = json as? String {
            let parts = str.components(separatedBy: " ").compactMap { Int32($0) }
            if parts.count >= 3 { return SIMD3<Int32>(parts[0], parts[1], parts[2]) }
        } else if let arr = json as? [NSNumber], arr.count >= 3 {
            return SIMD3<Int32>(arr[0].int32Value, arr[1].int32Value, arr[2].int32Value)
        }
        return defaultVal
    }
}
