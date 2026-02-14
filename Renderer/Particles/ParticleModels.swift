//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/2/14.
//

import Foundation
import simd

struct SingleRandom {
    var min: Float = 0.0
    var max: Float = 0.0
    var exponent: Float = 1.0
    
    static func from(json: ParticleModuleJSON) -> SingleRandom {
        var r = SingleRandom()
        if let minVal = json.min {
            if case .float(let f) = minVal { r.min = f }
            else if case .string(let s) = minVal, let f = Float(s) { r.min = f }
        }
        if let maxVal = json.max {
            if case .float(let f) = maxVal { r.max = f }
            else if case .string(let s) = maxVal, let f = Float(s) { r.max = f }
        }
        return r
    }
}

struct VecRandom {
    var min: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var max: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var exponent: Float = 1.0
    
    static func from(json: ParticleModuleJSON) -> VecRandom {
        var r = VecRandom()
        if let minVal = json.min {
            let parts = minVal.value.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 { r.min = SIMD3<Float>(parts[0], parts[1], parts[2]) }
        }
        if let maxVal = json.max {
            let parts = maxVal.value.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 { r.max = SIMD3<Float>(parts[0], parts[1], parts[2]) }
        }
        return r
    }
}

struct TurbulentRandom {
    var scale: Float = 1.0
    var timescale: Float = 1.0
    var offset: Float = 0.0
    var speedmin: Float = 100.0
    var speedmax: Float = 250.0
    var phasemin: Float = 0.0
    var phasemax: Float = 0.1
    var forward: SIMD3<Float> = SIMD3<Float>(0.0, 1.0, 0.0)
    var right: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 1.0)
    var up: SIMD3<Float> = SIMD3<Float>(1.0, 0.0, 0.0)
    
    static func from(json: ParticleModuleJSON) -> TurbulentRandom {
        var r = TurbulentRandom()
        if let v = json.scale { r.scale = v }
        if let v = json.timescale { r.timescale = v }
        if let v = json.offset, let f = Float(v.value) { r.offset = f }
        if let v = json.speedmin { r.speedmin = v }
        if let v = json.speedmax { r.speedmax = v }
        if let v = json.phasemin { r.phasemin = v }
        if let v = json.phasemax { r.phasemax = v }
        return r
    }
}

struct ValueChange {
    var starttime: Float = 0.0
    var endtime: Float = 1.0
    var startvalue: Float = 1.0
    var endvalue: Float = 0.0
    
    static func from(json: ParticleModuleJSON) -> ValueChange {
        var v = ValueChange()
        if let val = json.starttime { v.starttime = val }
        if let val = json.endtime { v.endtime = val }
        if let val = json.startvalue, let f = Float(val.value) { v.startvalue = f }
        if let val = json.endvalue, let f = Float(val.value) { v.endvalue = f }
        return v
    }
}

struct VecChange {
    var starttime: Float = 0.0
    var endtime: Float = 1.0
    var startvalue: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var endvalue: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    static func from(json: ParticleModuleJSON) -> VecChange {
        var v = VecChange()
        if let val = json.starttime { v.starttime = val }
        if let val = json.endtime { v.endtime = val }
        if let val = json.startvalue {
            let parts = val.value.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 { v.startvalue = SIMD3<Float>(parts[0], parts[1], parts[2]) }
        }
        if let val = json.endvalue {
            let parts = val.value.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 { v.endvalue = SIMD3<Float>(parts[0], parts[1], parts[2]) }
        }
        return v
    }
}

class FrequencyValue {
    struct StorageRandom {
        var reset: Bool = true
        var frequency: Float = 0.0
        var scale: Float = 1.0
        var phase: Float = 0.0
    }
    
    var mask: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 0.0)
    var frequencymin: Float = 0.0
    var frequencymax: Float = 10.0
    var scalemin: Float = 0.0
    var scalemax: Float = 1.0
    var phasemin: Float = 0.0
    var phasemax: Float = Float.pi * 2.0
    
    var storage: [StorageRandom] = []
    
    static func from(json: ParticleModuleJSON, name: String) -> FrequencyValue {
        let v = FrequencyValue()
        if name == "oscillatesize" {
            v.scalemin = 0.8
            v.scalemax = 1.2
        } else if name == "oscillateposition" {
            v.frequencymax = 5.0
        }
        if let val = json.frequency {
            v.frequencymin = val
            v.frequencymax = val
        }
        if let val = json.scale {
            v.scalemin = val
            v.scalemax = val
        }
        if let val = json.phasemin { v.phasemin = val }
        if let val = json.phasemax { v.phasemax = val }
        if let val = json.mask {
            let parts = val.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 { v.mask = SIMD3<Float>(parts[0], parts[1], parts[2]) }
        }
        return v
    }
    
    func checkAndResize(size: Int) {
        if storage.count < size {
            storage.append(contentsOf: Array(repeating: StorageRandom(), count: max(size, storage.count * 2) - storage.count))
        }
    }
    
    func genFrequency(particle: Particle, index: Int) {
        if index >= storage.count { return }
        if particle.lifetime <= 0 { storage[index].reset = true }
        if storage[index].reset {
            storage[index].frequency = Float.random(in: frequencymin...frequencymax)
            storage[index].scale = Float.random(in: scalemin...scalemax)
            storage[index].phase = Float.random(in: phasemin...(phasemax + Float.pi * 2))
            storage[index].reset = false
        }
    }
    
    func getScale(index: Int, time: Float) -> Float {
        if index >= storage.count { return 1.0 }
        let st = storage[index]
        let w = st.frequency
        let t = (cos(w * time + st.phase) + 1.0) * 0.5
        return st.scale * (scalemin + (scalemax - scalemin) * t)
    }
    
    func getMove(index: Int, time: Float, timePass: Float) -> Float {
        if index >= storage.count { return 0.0 }
        let st = storage[index]
        let w = st.frequency
        return -1.0 * st.scale * w * sin(w * time + st.phase) * timePass
    }
}

struct Turbulence {
    var phasemin: Float = 0.0
    var phasemax: Float = 0.0
    var speedmin: Float = 500.0
    var speedmax: Float = 1000.0
    var timescale: Float = 20.0
    var scale: Float = 0.01
    var mask: SIMD3<Int32> = SIMD3<Int32>(1, 1, 0)
    
    static func from(json: ParticleModuleJSON) -> Turbulence {
        var v = Turbulence()
        if let val = json.phasemin { v.phasemin = val }
        if let val = json.phasemax { v.phasemax = val }
        if let val = json.speedmin { v.speedmin = val }
        if let val = json.speedmax { v.speedmax = val }
        if let val = json.timescale { v.timescale = val }
        if let val = json.scale { v.scale = val }
        if let val = json.mask {
            let parts = val.components(separatedBy: " ").compactMap { Int32($0) }
            if parts.count >= 3 { v.mask = SIMD3<Int32>(parts[0], parts[1], parts[2]) }
        }
        return v
    }
}

struct Vortex {
    var controlpoint: Int = 0
    var distanceinner: Float = 500.0
    var distanceouter: Float = 650.0
    var speedinner: Float = 2500.0
    var speedouter: Float = 0.0
    var offset: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var axis: SIMD3<Float> = SIMD3<Float>(0, 0, 1)
    
    static func from(json: ParticleModuleJSON) -> Vortex {
        var v = Vortex()
        if let val = json.controlpoint { v.controlpoint = val % 8 }
        if let val = json.distanceinner { v.distanceinner = val }
        if let val = json.distanceouter { v.distanceouter = val }
        if let val = json.speedinner { v.speedinner = val }
        if let val = json.speedouter { v.speedouter = val }
        if let val = json.offset {
            let parts = val.value.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 { v.offset = SIMD3<Float>(parts[0], parts[1], parts[2]) }
        }
        if let val = json.axis {
            let parts = val.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 { v.axis = SIMD3<Float>(parts[0], parts[1], parts[2]) }
        }
        return v
    }
}

struct ControlPointForce {
    var controlpoint: Int = 0
    var scale: Float = 512.0
    var threshold: Float = 512.0
    var origin: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    static func from(json: ParticleModuleJSON) -> ControlPointForce {
        var v = ControlPointForce()
        if let val = json.controlpoint { v.controlpoint = val % 8 }
        if let val = json.scale { v.scale = val }
        if let val = json.threshold { v.threshold = val }
        if let val = json.offset {
            let parts = val.value.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 { v.origin = SIMD3<Float>(parts[0], parts[1], parts[2]) }
        }
        return v
    }
}
