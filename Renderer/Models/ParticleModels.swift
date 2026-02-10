//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

import Foundation
import simd

struct ParticleSystemData: Codable {
    let root: ParticleRoot?
    
    enum CodingKeys: String, CodingKey {
        case root = "particle"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rootObj = try? container.decode(ParticleRoot.self, forKey: .root) {
            self.root = rootObj
        } else {
            self.root = try ParticleRoot(from: decoder)
        }
    }
}

struct ParticleRoot: Codable {
    let image: String?
    let maxcount: Int?
    let starttime: Float?
    let emitter: [ParticleEmitterModel]?
    let initializer: [ParticleInitializerModel]?
    let `operator`: [ParticleOperatorModel]?
    let renderer: [ParticleRendererModel]?
    let material: String?
    let instanceoverride: ParticleInstanceOverrideModel?
}

struct ParticleInstanceOverrideModel: Codable {
    let enabled: BoolOrScript?
    let alpha: FloatOrScript?
    let size: FloatOrScript?
    let lifetime: FloatOrScript?
    let rate: FloatOrScript?
    let speed: FloatOrScript?
    let count: FloatOrScript?
    let color: Vec3OrScript?
    let colorn: Vec3OrScript?
}

struct ParticleEmitterModel: Codable {
    let name: String?
    let rate: Float?
    let life: Float?
    let origin: String?
    let directions: String?
    let distancemin: String?
    let distancemax: String?
    let speedmin: Float?
    let speedmax: Float?
    let instantaneous: Int?
}

enum ParticleInitializerModel: Codable {
    case colorRandom(min: String, max: String)
    case sizeRandom(min: Float, max: Float, exponent: Float)
    case alphaRandom(min: Float, max: Float)
    case lifetimeRandom(min: Float, max: Float)
    case velocityRandom(min: String, max: String)
    case rotationRandom(min: String, max: String)
    case angularVelocityRandom(min: String, max: String)
    case turbulentVelocityRandom(min: Float, max: Float, scale: Float, offset: Float)
    case unknown

    enum CodingKeys: String, CodingKey {
        case name, min, max, exponent, speedmin, speedmax, scale, offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        
        switch name {
        case "colorrandom":
            let min = try? container.decode(String.self, forKey: .min)
            let max = try? container.decode(String.self, forKey: .max)
            self = .colorRandom(min: min ?? "0 0 0", max: max ?? "1 1 1")
        case "sizerandom":
            let min = try? container.decode(Float.self, forKey: .min)
            let max = try? container.decode(Float.self, forKey: .max)
            let exp = try? container.decode(Float.self, forKey: .exponent)
            self = .sizeRandom(min: min ?? 1, max: max ?? 1, exponent: exp ?? 1)
        case "alpharandom":
            let min = try? container.decode(Float.self, forKey: .min)
            let max = try? container.decode(Float.self, forKey: .max)
            self = .alphaRandom(min: min ?? 1, max: max ?? 1)
        case "lifetimerandom":
            let min = try? container.decode(Float.self, forKey: .min)
            let max = try? container.decode(Float.self, forKey: .max)
            self = .lifetimeRandom(min: min ?? 1, max: max ?? 1)
        case "velocityrandom":
            let min = try? container.decode(String.self, forKey: .min)
            let max = try? container.decode(String.self, forKey: .max)
            self = .velocityRandom(min: min ?? "-1 -1 -1", max: max ?? "1 1 1")
        case "rotationrandom":
            let min = try? container.decode(String.self, forKey: .min)
            let max = try? container.decode(String.self, forKey: .max)
            self = .rotationRandom(min: min ?? "0 0 0", max: max ?? "0 0 0")
        case "angularvelocityrandom":
            let min = try? container.decode(String.self, forKey: .min)
            let max = try? container.decode(String.self, forKey: .max)
            self = .angularVelocityRandom(min: min ?? "0 0 0", max: max ?? "0 0 0")
        case "turbulentvelocityrandom":
            let min = try? container.decode(Float.self, forKey: .speedmin)
            let max = try? container.decode(Float.self, forKey: .speedmax)
            let scale = try? container.decode(Float.self, forKey: .scale)
            let offset = try? container.decode(Float.self, forKey: .offset)
            self = .turbulentVelocityRandom(min: min ?? 0, max: max ?? 0, scale: scale ?? 1, offset: offset ?? 0)
        default:
            self = .unknown
        }
    }
    
    func encode(to encoder: Encoder) throws {}
}

enum ParticleOperatorModel: Codable {
    case movement(drag: Float, gravity: String)
    case alphaFade(in: Float, out: Float)
    case rotation(drag: Float, force: String)
    case sizeChange(start: Float, end: Float, valStart: Float, valEnd: Float)
    case colorChange(start: Float, end: Float, valStart: String, valEnd: String)
    case turbulence(scale: Float, speedMin: Float, speedMax: Float, timeScale: Float)
    case vortex(axis: String, offset: String, dInner: Float, dOuter: Float, sInner: Float, sOuter: Float)
    case attract(origin: String, scale: Float, threshold: Float)
    case unknown

    enum CodingKeys: String, CodingKey {
        case name, drag, gravity, fadeintime, fadeouttime, force, scale, speedmin, speedmax, timescale
        case starttime, endtime, startvalue, endvalue
        case axis, offset, distanceinner, distanceouter, speedinner, speedouter, origin, threshold
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        
        switch name {
        case "movement":
            let drag = try? container.decode(Float.self, forKey: .drag)
            let gravity = try? container.decode(String.self, forKey: .gravity)
            self = .movement(drag: drag ?? 0, gravity: gravity ?? "0 0 0")
        case "alphafade":
            let `in` = try? container.decode(Float.self, forKey: .fadeintime)
            let out = try? container.decode(Float.self, forKey: .fadeouttime)
            self = .alphaFade(in: `in` ?? 0, out: out ?? 0)
        case "angularmovement":
            let drag = try? container.decode(Float.self, forKey: .drag)
            let force = try? container.decode(String.self, forKey: .force)
            self = .rotation(drag: drag ?? 0, force: force ?? "0 0 0")
        case "sizechange":
            let st = try? container.decode(Float.self, forKey: .starttime)
            let et = try? container.decode(Float.self, forKey: .endtime)
            let sv = try? container.decode(Float.self, forKey: .startvalue)
            let ev = try? container.decode(Float.self, forKey: .endvalue)
            self = .sizeChange(start: st ?? 0, end: et ?? 1, valStart: sv ?? 1, valEnd: ev ?? 0)
        case "colorchange":
            let st = try? container.decode(Float.self, forKey: .starttime)
            let et = try? container.decode(Float.self, forKey: .endtime)
            let sv = try? container.decode(String.self, forKey: .startvalue)
            let ev = try? container.decode(String.self, forKey: .endvalue)
            self = .colorChange(start: st ?? 0, end: et ?? 1, valStart: sv ?? "1 1 1", valEnd: ev ?? "1 1 1")
        case "turbulence":
            let scale = try? container.decode(Float.self, forKey: .scale)
            let min = try? container.decode(Float.self, forKey: .speedmin)
            let max = try? container.decode(Float.self, forKey: .speedmax)
            let time = try? container.decode(Float.self, forKey: .timescale)
            self = .turbulence(scale: scale ?? 1, speedMin: min ?? 0, speedMax: max ?? 0, timeScale: time ?? 1)
        case "vortex":
            let ax = try? container.decode(String.self, forKey: .axis)
            let off = try? container.decode(String.self, forKey: .offset)
            let di = try? container.decode(Float.self, forKey: .distanceinner)
            let do_ = try? container.decode(Float.self, forKey: .distanceouter)
            let si = try? container.decode(Float.self, forKey: .speedinner)
            let so = try? container.decode(Float.self, forKey: .speedouter)
            self = .vortex(axis: ax ?? "0 0 1", offset: off ?? "0 0 0", dInner: di ?? 0, dOuter: do_ ?? 1000, sInner: si ?? 100, sOuter: so ?? 0)
        case "controlpointattract":
            let ori = try? container.decode(String.self, forKey: .origin)
            let sc = try? container.decode(Float.self, forKey: .scale)
            let th = try? container.decode(Float.self, forKey: .threshold)
            self = .attract(origin: ori ?? "0 0 0", scale: sc ?? 100, threshold: th ?? 1000)
        default:
            self = .unknown
        }
    }
    
    func encode(to encoder: Encoder) throws {}
}

struct ParticleRendererModel: Codable {
    let name: String
    let length: Float?
    let maxlength: Float?
    let subdivision: Int?
}

enum BoolOrScript: Codable {
    case bool(Bool)
    case script(String)
    
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let v = try? container.decode(Bool.self) {
            self = .bool(v)
            return
        }
        if let container = try? decoder.container(keyedBy: CodingKeys.self), let v = try? container.decode(String.self, forKey: .value) {
            self = .script(v)
            return
        }
        self = .bool(true)
    }
    
    var value: Bool {
        switch self {
        case .bool(let b): return b
        case .script: return true
        }
    }
    
    enum CodingKeys: String, CodingKey { case value }
    func encode(to encoder: Encoder) throws {}
}

enum FloatOrScript: Codable {
    case float(Float)
    case script(String)
    
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let v = try? container.decode(Float.self) {
            self = .float(v)
            return
        }
        if let container = try? decoder.container(keyedBy: CodingKeys.self), let v = try? container.decode(String.self, forKey: .value) {
            self = .script(v)
            return
        }
        self = .float(1.0)
    }
    
    var value: Float {
        switch self {
        case .float(let f): return f
        case .script: return 1.0
        }
    }
    
    enum CodingKeys: String, CodingKey { case value }
    func encode(to encoder: Encoder) throws {}
}

enum Vec3OrScript: Codable {
    case vec3(String)
    case script(String)
    
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let v = try? container.decode(String.self) {
            self = .vec3(v)
            return
        }
        if let container = try? decoder.container(keyedBy: CodingKeys.self), let v = try? container.decode(String.self, forKey: .value) {
            self = .script(v)
            return
        }
        self = .vec3("1 1 1")
    }
    
    var value: SIMD3<Float> {
        switch self {
        case .vec3(let s): return MathHelper.parseVec3(s)
        case .script: return SIMD3<Float>(1, 1, 1)
        }
    }
    
    enum CodingKeys: String, CodingKey { case value }
    func encode(to encoder: Encoder) throws {}
}
