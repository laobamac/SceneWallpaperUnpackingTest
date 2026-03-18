//
//  ParticleParser.swift
//  Renderer
//
//  Created by laobamac on 2026/3/19.
//

import Foundation
import simd

struct WPParticleParser {
    
    struct SingleRandom {
        var min: Float = 0.0
        var max: Float = 0.0
        var exponent: Float = 1.0
        
        static func readFromJson(_ j: [String: Any]) -> SingleRandom {
            var r = SingleRandom()
            if let v = j["min"] as? NSNumber { r.min = v.floatValue }
            if let v = j["max"] as? NSNumber { r.max = v.floatValue }
            return r
        }
    }
    
    struct VecRandom {
        var min: [Float] = [0.0, 0.0, 0.0]
        var max: [Float] = [0.0, 0.0, 0.0]
        var exponent: Float = 1.0
        
        static func readFromJson(_ j: [String: Any], defaultMin: [Float]? = nil, defaultMax: [Float]? = nil) -> VecRandom {
            var r = VecRandom()
            if let dm = defaultMin { r.min = dm }
            if let dx = defaultMax { r.max = dx }
            if let arr = j["min"] as? [NSNumber], arr.count >= 3 {
                r.min = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue]
            }
            if let arr = j["max"] as? [NSNumber], arr.count >= 3 {
                r.max = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue]
            }
            return r
        }
    }
    
    struct TurbulentRandom {
        var scale: Float = 1.0
        var timescale: Double = 1.0
        var offset: Float = 0.0
        var speedmin: Float = 100.0
        var speedmax: Float = 250.0
        var phasemin: Float = 0.0
        var phasemax: Float = 0.1
        var forward: [Float] = [0.0, 1.0, 0.0]
        var right: [Float] = [0.0, 0.0, 1.0]
        var up: [Float] = [1.0, 0.0, 0.0]
        
        static func readFromJson(_ j: [String: Any]) -> TurbulentRandom {
            var r = TurbulentRandom()
            if let v = j["scale"] as? NSNumber { r.scale = v.floatValue }
            if let v = j["timescale"] as? NSNumber { r.timescale = v.doubleValue }
            if let v = j["offset"] as? NSNumber { r.offset = v.floatValue }
            if let v = j["speedmin"] as? NSNumber { r.speedmin = v.floatValue }
            if let v = j["speedmax"] as? NSNumber { r.speedmax = v.floatValue }
            if let v = j["phasemin"] as? NSNumber { r.phasemin = v.floatValue }
            if let v = j["phasemax"] as? NSNumber { r.phasemax = v.floatValue }
            if let arr = j["forward"] as? [NSNumber], arr.count >= 3 { r.forward = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            if let arr = j["right"] as? [NSNumber], arr.count >= 3 { r.right = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            if let arr = j["up"] as? [NSNumber], arr.count >= 3 { r.up = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            return r
        }
    }
    
    struct ValueChange {
        var starttime: Float = 0.0
        var endtime: Float = 1.0
        var startvalue: Float = 1.0
        var endvalue: Float = 0.0
        
        static func readFromJson(_ j: [String: Any]) -> ValueChange {
            var v = ValueChange()
            if let val = j["starttime"] as? NSNumber { v.starttime = val.floatValue }
            if let val = j["endtime"] as? NSNumber { v.endtime = val.floatValue }
            if let val = j["startvalue"] as? NSNumber { v.startvalue = val.floatValue }
            if let val = j["endvalue"] as? NSNumber { v.endvalue = val.floatValue }
            return v
        }
    }
    
    struct VecChange {
        var starttime: Float = 0.0
        var endtime: Float = 1.0
        var startvalue: [Float] = [0.0, 0.0, 0.0]
        var endvalue: [Float] = [0.0, 0.0, 0.0]
        
        static func readFromJson(_ j: [String: Any]) -> VecChange {
            var v = VecChange()
            if let val = j["starttime"] as? NSNumber { v.starttime = val.floatValue }
            if let val = j["endtime"] as? NSNumber { v.endtime = val.floatValue }
            if let arr = j["startvalue"] as? [NSNumber], arr.count >= 3 { v.startvalue = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            if let arr = j["endvalue"] as? [NSNumber], arr.count >= 3 { v.endvalue = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            return v
        }
    }
    
    class FrequencyValue {
        var mask: [Float] = [1.0, 1.0, 0.0]
        var frequencymin: Float = 0.0
        var frequencymax: Float = 10.0
        var scalemin: Float = 0.0
        var scalemax: Float = 1.0
        var phasemin: Float = 0.0
        var phasemax: Float = Float.pi * 2.0
        
        struct StorageRandom {
            var reset: Bool = true
            var frequency: Float = 0.0
            var scale: Float = 1.0
            var phase: Float = 0.0
        }
        
        var storage: [StorageRandom] = []
        
        static func readFromJson(_ j: [String: Any], name: String) -> FrequencyValue {
            let v = FrequencyValue()
            if name == "oscillatesize" {
                v.scalemin = 0.8
                v.scalemax = 1.2
            } else if name == "oscillateposition" {
                v.frequencymax = 5.0
            }
            if let val = j["frequencymin"] as? NSNumber { v.frequencymin = val.floatValue }
            if let val = j["frequencymax"] as? NSNumber { v.frequencymax = val.floatValue }
            if v.frequencymax == 0.0 { v.frequencymax = v.frequencymin }
            if let val = j["scalemin"] as? NSNumber { v.scalemin = val.floatValue }
            if let val = j["scalemax"] as? NSNumber { v.scalemax = val.floatValue }
            if let val = j["phasemin"] as? NSNumber { v.phasemin = val.floatValue }
            if let val = j["phasemax"] as? NSNumber { v.phasemax = val.floatValue }
            if let arr = j["mask"] as? [NSNumber], arr.count >= 3 { v.mask = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            return v
        }
        
        func checkAndResize(_ s: Int) {
            if storage.count < s {
                storage.append(contentsOf: Array(repeating: StorageRandom(), count: (2 * s) - storage.count + 1))
            }
        }
        
        func genFrequency(_ p: Particle, _ index: Int) {
            if !ParticleModify.lifetimeOk(p) { storage[index].reset = true }
            if storage[index].reset {
                storage[index].frequency = ParticleMath.random(min: frequencymin, max: frequencymax)
                storage[index].scale = ParticleMath.random(min: scalemin, max: scalemax)
                storage[index].phase = Float(ParticleMath.random(min: Double(phasemin), max: Double(phasemax) + 2.0 * Double.pi))
                storage[index].reset = false
            }
        }
        
        func getScale(_ index: Int, _ time: Double) -> Double {
            let st = storage[index]
            let f = Double(st.frequency) / (2.0 * Double.pi)
            let w = 2.0 * Double.pi * f
            let cosVal = cos(w * time + Double(st.phase))
            return Double(ParticleMath.lerp(Float((cosVal + 1.0) * 0.5), scalemin, scalemax))
        }
        
        func getMove(_ index: Int, _ time: Double, _ timePass: Double) -> Double {
            let st = storage[index]
            let f = Double(st.frequency) / (2.0 * Double.pi)
            let w = 2.0 * Double.pi * f
            return -1.0 * Double(st.scale) * w * sin(w * time + Double(st.phase)) * timePass
        }
        
        func copy() -> FrequencyValue {
            let c = FrequencyValue()
            c.mask = self.mask
            c.frequencymin = self.frequencymin
            c.frequencymax = self.frequencymax
            c.scalemin = self.scalemin
            c.scalemax = self.scalemax
            c.phasemin = self.phasemin
            c.phasemax = self.phasemax
            return c
        }
    }
    
    struct Turbulence {
        var phasemin: Float = 0
        var phasemax: Float = 0
        var speedmin: Float = 500.0
        var speedmax: Float = 1000.0
        var timescale: Float = 20.0
        var scale: Float = 0.01
        var mask: [Int32] = [1, 1, 0]
        
        static func readFromJson(_ j: [String: Any]) -> Turbulence {
            var v = Turbulence()
            if let val = j["phasemin"] as? NSNumber { v.phasemin = val.floatValue }
            if let val = j["phasemax"] as? NSNumber { v.phasemax = val.floatValue }
            if let val = j["speedmin"] as? NSNumber { v.speedmin = val.floatValue }
            if let val = j["speedmax"] as? NSNumber { v.speedmax = val.floatValue }
            if let val = j["timescale"] as? NSNumber { v.timescale = val.floatValue }
            if let val = j["scale"] as? NSNumber { v.scale = val.floatValue }
            if let arr = j["mask"] as? [NSNumber], arr.count >= 3 { v.mask = [arr[0].int32Value, arr[1].int32Value, arr[2].int32Value] }
            return v
        }
    }
    
    struct Vortex {
        var controlpoint: Int32 = 0
        var distanceinner: Float = 500.0
        var distanceouter: Float = 650.0
        var speedinner: Float = 2500.0
        var speedouter: Float = 0
        var flags: Int32 = 0
        var offset: [Float] = [0.0, 0.0, 0.0]
        var axis: [Float] = [0.0, 0.0, 1.0]
        
        static func readFromJson(_ j: [String: Any]) -> Vortex {
            var v = Vortex()
            if let val = j["controlpoint"] as? NSNumber { v.controlpoint = val.int32Value }
            if v.controlpoint >= 8 { Logger.error("wrong contropoint index \(v.controlpoint)") }
            v.controlpoint %= 8
            if let val = j["distanceinner"] as? NSNumber { v.distanceinner = val.floatValue }
            if let val = j["distanceouter"] as? NSNumber { v.distanceouter = val.floatValue }
            if let val = j["speedinner"] as? NSNumber { v.speedinner = val.floatValue }
            if let val = j["speedouter"] as? NSNumber { v.speedouter = val.floatValue }
            if let val = j["flags"] as? NSNumber { v.flags = val.int32Value }
            if let arr = j["offset"] as? [NSNumber], arr.count >= 3 { v.offset = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            if let arr = j["axis"] as? [NSNumber], arr.count >= 3 { v.axis = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            return v
        }
    }
    
    struct ControlPointForce {
        var controlpoint: Int32 = 0
        var scale: Float = 512.0
        var threshold: Float = 512.0
        var origin: [Float] = [0.0, 0.0, 0.0]
        
        static func readFromJson(_ j: [String: Any]) -> ControlPointForce {
            var v = ControlPointForce()
            if let val = j["controlpoint"] as? NSNumber { v.controlpoint = val.int32Value }
            if v.controlpoint >= 8 { Logger.error("wrong contropoint index \(v.controlpoint)") }
            v.controlpoint %= 8
            if let val = j["scale"] as? NSNumber { v.scale = val.floatValue }
            if let val = j["threadhold"] as? NSNumber { v.threshold = val.floatValue }
            if let arr = j["offset"] as? [NSNumber], arr.count >= 3 { v.origin = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            return v
        }
    }
    
    static func fadeValueChange(_ life: Float, _ start: Float, _ end: Float, _ startValue: Float, _ endValue: Float) -> Double {
        if life <= start { return Double(startValue) }
        else if life > end { return Double(endValue) }
        else {
            let pass = (life - start) / (end - start)
            return Double(ParticleMath.lerp(pass, startValue, endValue))
        }
    }
    
    static func genParticleInitOp(_ wpj: [String: Any]) -> ParticleInitOp {
        guard let name = wpj["name"] as? String else { return { _,_ in } }
        
        if name == "colorrandom" {
            let r = VecRandom.readFromJson(wpj, defaultMin: [0,0,0], defaultMax: [255,255,255])
            return { p, _ in
                let rr = ParticleMath.random(min: r.min[0], max: r.max[0]) / 255.0
                let gg = ParticleMath.random(min: r.min[1], max: r.max[1]) / 255.0
                let bb = ParticleMath.random(min: r.min[2], max: r.max[2]) / 255.0
                ParticleModify.initColor(&p, rr, gg, bb)
            }
        } else if name == "lifetimerandom" {
            var r = SingleRandom()
            r.min = 0.0; r.max = 1.0
            r = SingleRandom.readFromJson(wpj)
            return { p, _ in ParticleModify.initLifetime(&p, ParticleMath.random(min: r.min, max: r.max)) }
        } else if name == "sizerandom" {
            var r = SingleRandom()
            r.min = 0.0; r.max = 20.0
            r = SingleRandom.readFromJson(wpj)
            return { p, _ in ParticleModify.initSize(&p, ParticleMath.random(min: r.min, max: r.max)) }
        } else if name == "alpharandom" {
            var r = SingleRandom()
            r.min = 0.05; r.max = 1.0
            r = SingleRandom.readFromJson(wpj)
            return { p, _ in ParticleModify.initAlpha(&p, ParticleMath.random(min: r.min, max: r.max)) }
        } else if name == "velocityrandom" {
            let r = VecRandom.readFromJson(wpj, defaultMin: [-32,-32,0], defaultMax: [32,32,0])
            return { p, _ in
                let vx = ParticleMath.random(min: r.min[0], max: r.max[0])
                let vy = ParticleMath.random(min: r.min[1], max: r.max[1])
                let vz = ParticleMath.random(min: r.min[2], max: r.max[2])
                ParticleModify.changeVelocity(&p, vx, vy, vz)
            }
        } else if name == "rotationrandom" {
            let r = VecRandom.readFromJson(wpj, defaultMax: [0, 0, Float.pi * 2])
            return { p, _ in
                let rx = ParticleMath.random(min: r.min[0], max: r.max[0])
                let ry = ParticleMath.random(min: r.min[1], max: r.max[1])
                let rz = ParticleMath.random(min: r.min[2], max: r.max[2])
                ParticleModify.changeRotation(&p, rx, ry, rz)
            }
        } else if name == "angularvelocityrandom" {
            let r = VecRandom.readFromJson(wpj, defaultMin: [0, 0, -5], defaultMax: [0, 0, 5])
            return { p, _ in
                let ax = ParticleMath.random(min: r.min[0], max: r.max[0])
                let ay = ParticleMath.random(min: r.min[1], max: r.max[1])
                let az = ParticleMath.random(min: r.min[2], max: r.max[2])
                ParticleModify.changeAngularVelocity(&p, ax, ay, az)
            }
        } else if name == "turbulentvelocityrandom" {
            let r = TurbulentRandom.readFromJson(wpj)
            let forward = SIMD3<Float>(r.forward[0], r.forward[1], r.forward[2])
            let right = SIMD3<Float>(r.right[0], r.right[1], r.right[2])
            
            class TurbulentState {
                var pos: SIMD3<Float>
                init(pos: SIMD3<Float>) { self.pos = pos }
            }
            
            let state = TurbulentState(pos: SIMD3<Float>(
                ParticleMath.random(min: 0.0, max: 10.0),
                ParticleMath.random(min: 0.0, max: 10.0),
                ParticleMath.random(min: 0.0, max: 10.0)
            ))
            
            return { p, duration in
                var dur = duration
                let speed = ParticleMath.random(min: r.speedmin, max: r.speedmax)
                if dur > 10.0 {
                    state.pos.x += speed
                    dur = 0.0
                }
                var result = SIMD3<Float>(0,0,0)
                repeat {
                    let dPos = SIMD3<Double>(Double(state.pos.x), Double(state.pos.y), Double(state.pos.z))
                    let curl = ParticleMath.curlNoise(dPos)
                    result = normalize(SIMD3<Float>(Float(curl.x), Float(curl.y), Float(curl.z)))
                    state.pos += result * (0.005 / Float(r.timescale))
                    dur -= 0.01
                } while dur > 0.01
                
                let c = dot(result, forward) / (length(result) * length(forward))
                let a = acos(c) / Float.pi
                let scale = r.scale / 2.0
                if a > scale {
                    let axis = normalize(cross(result, forward))
                    result = ParticleMath.rotate(vector: result, angle: (a - a * scale) * Float.pi, axis: axis)
                }
                result = ParticleMath.rotate(vector: result, angle: r.offset, axis: right)
                result *= speed
                ParticleModify.changeVelocity(&p, result.x, result.y, result.z)
            }
        }
        return { _,_ in }
    }
    
    static func genOverrideInitOp(lifetime: Float, alpha: Float, size: Float, speed: Float, overColor: Bool, color: [Float], overColorn: Bool, colorn: [Float]) -> ParticleInitOp {
        return { p, _ in
            ParticleModify.mutiplyInitLifeTime(&p, lifetime)
            ParticleModify.mutiplyInitAlpha(&p, alpha)
            ParticleModify.mutiplyInitSize(&p, size)
            ParticleModify.mutiplyVelocity(&p, speed)
            if overColor && color.count >= 3 {
                ParticleModify.initColor(&p, color[0] / 255.0, color[1] / 255.0, color[2] / 255.0)
            } else if overColorn && colorn.count >= 3 {
                ParticleModify.mutiplyInitColor(&p, colorn[0], colorn[1], colorn[2])
            }
        }
    }
    
    static func genParticleOperatorOp(_ wpj: [String: Any], speedOver: Float, sizeOver: Float) -> ParticleOperatorOp {
        guard let name = wpj["name"] as? String else { return { _ in } }
        
        if name == "movement" {
            var drag: Float = 0.0
            var gravity: [Float] = [0, 0, 0]
            if let v = wpj["drag"] as? NSNumber { drag = v.floatValue }
            if let arr = wpj["gravity"] as? [NSNumber], arr.count >= 3 { gravity = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            let vecG = SIMD3<Double>(Double(gravity[0]), Double(gravity[1]), Double(gravity[2]))
            
            return { info in
                for i in 0..<info.particles.count {
                    let pVel = info.particles[i].velocity
                    let vel = SIMD3<Double>(Double(pVel.x), Double(pVel.y), Double(pVel.z))
                    let acc = ParticleMath.dragForce(velocity: vel, drag: drag) + vecG
                    let finalAcc = SIMD3<Double>(acc.x * Double(speedOver), acc.y * Double(speedOver), acc.z * Double(speedOver))
                    ParticleModify.accelerate(&info.particles[i], finalAcc, info.time_pass)
                    ParticleModify.moveByTime(&info.particles[i], info.time_pass)
                }
            }
        } else if name == "angularmovement" {
            var drag: Float = 0.0
            var force: [Float] = [0, 0, 0]
            if let v = wpj["drag"] as? NSNumber { drag = v.floatValue }
            if let arr = wpj["force"] as? [NSNumber], arr.count >= 3 { force = [arr[0].floatValue, arr[1].floatValue, arr[2].floatValue] }
            let vecF = SIMD3<Double>(Double(force[0]), Double(force[1]), Double(force[2]))
            
            return { info in
                for i in 0..<info.particles.count {
                    let pAng = info.particles[i].angularVelocity
                    let ang = SIMD3<Double>(Double(pAng.x), Double(pAng.y), Double(pAng.z))
                    let acc = ParticleMath.dragForce(velocity: ang, drag: drag) + vecF
                    ParticleModify.angularAccelerate(&info.particles[i], acc, info.time_pass)
                    ParticleModify.rotateByTime(&info.particles[i], info.time_pass)
                }
            }
        } else if name == "sizechange" {
            let vc = ValueChange.readFromJson(wpj)
            return { info in
                for i in 0..<info.particles.count {
                    let pass = fadeValueChange(ParticleModify.lifetimePos(info.particles[i]), vc.starttime, vc.endtime, vc.startvalue, vc.endvalue)
                    ParticleModify.mutiplySize(&info.particles[i], sizeOver * Float(pass))
                }
            }
        } else if name == "alphafade" {
            var fadeintime: Float = 0.5
            var fadeouttime: Float = 0.5
            if let v = wpj["fadeintime"] as? NSNumber { fadeintime = v.floatValue }
            if let v = wpj["fadeouttime"] as? NSNumber { fadeouttime = v.floatValue }
            return { info in
                for i in 0..<info.particles.count {
                    let life = ParticleModify.lifetimePos(info.particles[i])
                    if life <= fadeintime {
                        ParticleModify.mutiplyAlpha(&info.particles[i], Float(fadeValueChange(life, 0, fadeintime, 0, 1.0)))
                    } else if life > fadeouttime {
                        ParticleModify.mutiplyAlpha(&info.particles[i], 1.0 - Float(fadeValueChange(life, fadeouttime, 1.0, 0, 1.0)))
                    }
                }
            }
        } else if name == "alphachange" {
            let vc = ValueChange.readFromJson(wpj)
            return { info in
                for i in 0..<info.particles.count {
                    ParticleModify.mutiplyAlpha(&info.particles[i], Float(fadeValueChange(ParticleModify.lifetimePos(info.particles[i]), vc.starttime, vc.endtime, vc.startvalue, vc.endvalue)))
                }
            }
        } else if name == "colorchange" {
            let vc = VecChange.readFromJson(wpj)
            return { info in
                for i in 0..<info.particles.count {
                    let life = ParticleModify.lifetimePos(info.particles[i])
                    let r = fadeValueChange(life, vc.starttime, vc.endtime, vc.startvalue[0], vc.endvalue[0])
                    let g = fadeValueChange(life, vc.starttime, vc.endtime, vc.startvalue[1], vc.endvalue[1])
                    let b = fadeValueChange(life, vc.starttime, vc.endtime, vc.startvalue[2], vc.endvalue[2])
                    ParticleModify.mutiplyColor(&info.particles[i], r, g, b)
                }
            }
        } else if name == "oscillatealpha" {
            let fv = FrequencyValue.readFromJson(wpj, name: name)
            return { info in
                fv.checkAndResize(info.particles.count)
                for i in 0..<info.particles.count {
                    fv.genFrequency(info.particles[i], i)
                    ParticleModify.mutiplyAlpha(&info.particles[i], fv.getScale(i, ParticleModify.lifetimePassed(info.particles[i])))
                }
            }
        } else if name == "oscillatesize" {
            let fv = FrequencyValue.readFromJson(wpj, name: name)
            return { info in
                fv.checkAndResize(info.particles.count)
                for i in 0..<info.particles.count {
                    fv.genFrequency(info.particles[i], i)
                    ParticleModify.mutiplySize(&info.particles[i], fv.getScale(i, ParticleModify.lifetimePassed(info.particles[i])))
                }
            }
        } else if name == "oscillateposition" {
            let fvx = FrequencyValue.readFromJson(wpj, name: name)
            let fvArray = [fvx, fvx.copy(), fvx.copy()]
            return { info in
                for f in fvArray { f.checkAndResize(info.particles.count) }
                for i in 0..<info.particles.count {
                    var del = SIMD3<Double>(0,0,0)
                    let time = ParticleModify.lifetimePassed(info.particles[i])
                    for d in 0..<3 {
                        if fvArray[0].mask[d] < 0.01 { continue }
                        fvArray[d].genFrequency(info.particles[i], i)
                        let move = fvArray[d].getMove(i, time, info.time_pass)
                        if d == 0 { del.x = move } else if d == 1 { del.y = move } else { del.z = move }
                    }
                    ParticleModify.move(&info.particles[i], del)
                }
            }
        } else if name == "turbulence" {
            let tur = Turbulence.readFromJson(wpj)
            let phase = ParticleMath.random(min: Double(tur.phasemin), max: Double(tur.phasemax))
            let speed = ParticleMath.random(min: Double(tur.speedmin), max: Double(tur.speedmax))
            return { info in
                for i in 0..<info.particles.count {
                    let pPos = info.particles[i].position
                    var pos = SIMD3<Double>(Double(pPos.x), Double(pPos.y), Double(pPos.z))
                    pos.x += phase + Double(tur.timescale) * info.time
                    let curl = ParticleMath.curlNoise(pos * Double(tur.scale) * 2.0)
                    let normCurl = normalize(curl)
                    var result = speed * normCurl
                    if tur.mask[0] == 0 { result.x = 0 }
                    if tur.mask[1] == 0 { result.y = 0 }
                    if tur.mask[2] == 0 { result.z = 0 }
                    ParticleModify.accelerate(&info.particles[i], result, info.time_pass)
                }
            }
        } else if name == "vortex" {
            let v = Vortex.readFromJson(wpj)
            return { info in
                let idx = Int(v.controlpoint)
                let cOffset = (idx < info.controlpoints.count) ? info.controlpoints[idx].offset : SIMD3<Double>(0,0,0)
                let offset = cOffset + SIMD3<Double>(Double(v.offset[0]), Double(v.offset[1]), Double(v.offset[2]))
                let axis = SIMD3<Double>(Double(v.axis[0]), Double(v.axis[1]), Double(v.axis[2]))
                let dis_mid = Double(v.distanceouter - v.distanceinner) + 0.1
                
                for i in 0..<info.particles.count {
                    let pPos = info.particles[i].position
                    let pos = SIMD3<Double>(Double(pPos.x), Double(pPos.y), Double(pPos.z))
                    let direct = -normalize(cross(axis, pos))
                    let distance = length(pos - offset)
                    
                    if dis_mid < 0 || distance < Double(v.distanceinner) {
                        ParticleModify.accelerate(&info.particles[i], direct * Double(v.speedinner), info.time_pass)
                    }
                    if distance > Double(v.distanceouter) {
                        ParticleModify.accelerate(&info.particles[i], direct * Double(v.speedouter), info.time_pass)
                    } else if distance > Double(v.distanceinner) {
                        let t = (distance - Double(v.distanceinner)) / dis_mid
                        ParticleModify.accelerate(&info.particles[i], direct * Double(ParticleMath.lerp(Float(t), v.speedinner, v.speedouter)), info.time_pass)
                    }
                }
            }
        }
        return { _ in }
    }
}
