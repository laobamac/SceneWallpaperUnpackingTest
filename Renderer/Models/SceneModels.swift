//
//  SceneModels.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import Foundation
import simd

struct SceneRoot: Codable {
    let general: GeneralSettings?
    let objects: [SceneObject]
}

struct GeneralSettings: Codable {
    let orthogonalprojection: ProjectionSize?
    let fov: Float?
    let perspectiveoverridefov: Float?
    let bloomhdrthreshold: Float?
    let bloomhdrstrength: Float?
    let bloomhdriterations: Int?
}

struct ProjectionSize: Codable {
    let width: Float
    let height: Float
}

struct SceneObject: Codable {
    let id: Int?
    let name: String?
    let image: String?
    let particle: String?
    let type: String?
    let origin: ScriptableValue?
    let size: ScriptableValue?
    let scale: ScriptableValue?
    let angles: ScriptableValue?
    let parent: Int?
    let visible: BoolOrObject?
    let effects: [EffectJSON]?
    let instanceoverride: ParticleInstanceOverride?
    let text: TextProperty?
    let font: String?
    let pointsize: Float?
    let color: String?

    var isVisible: Bool {
        if let v = visible {
            if case .bool(let b) = v { return b }
            return true
        }
        return true
    }
}

enum TextProperty: Codable {
    case string(String)
    case object(TextObject)

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        if let o = try? TextObject(from: decoder) {
            self = .object(o)
            return
        }
        self = .string("")
    }
    
    func encode(to encoder: Encoder) throws {}
    
    var script: String {
        if case .object(let o) = self { return o.script ?? "" }
        return ""
    }
    
    var value: String {
        if case .string(let s) = self { return s }
        if case .object(let o) = self { return o.value ?? "" }
        return ""
    }
}

struct TextObject: Codable {
    let script: String?
    let value: String?
}

struct EffectJSON: Codable {
    let id: Int?
    let file: String?
    let visible: BoolOrObject?
    let passes: [EffectPassJSON]?
}

struct EffectPassJSON: Codable {
    let constantshadervalues: [String: ScriptableValue]?
    let combos: [String: Int]?
    let textures: [String?]?
}

struct DynamicKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    var intValue: Int?
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

enum ScriptableValue: Codable {
    case string(String)
    case script(value: String)
    case float(Float)
    case int(Int)
    case bool(Bool)
    case floatArray([Float])
    case object([String: ScriptableValue])

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let b = try? container.decode(Bool.self) {
                self = .bool(b)
                return
            }
            if let i = try? container.decode(Int.self) {
                self = .int(i)
                return
            }
            if let f = try? container.decode(Float.self) {
                self = .float(f)
                return
            }
            if let s = try? container.decode(String.self) {
                self = .string(s)
                return
            }
        }
        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var arr: [Float] = []
            while !unkeyedContainer.isAtEnd {
                if let f = try? unkeyedContainer.decode(Float.self) {
                    arr.append(f)
                } else {
                    _ = try? unkeyedContainer.decode(DummyCodable.self)
                }
            }
            self = .floatArray(arr)
            return
        }
        if let container = try? decoder.container(keyedBy: DynamicKey.self) {
            if container.allKeys.count == 1, let scriptKey = DynamicKey(stringValue: "value"), let val = try? container.decode(String.self, forKey: scriptKey) {
                self = .script(value: val)
                return
            }
            var dict: [String: ScriptableValue] = [:]
            for key in container.allKeys {
                if let val = try? container.decode(ScriptableValue.self, forKey: key) {
                    dict[key.stringValue] = val
                }
            }
            self = .object(dict)
            return
        }
        self = .string("0")
    }

    var value: String {
        switch self {
        case .string(let s): return s
        case .script(let v): return v
        case .float(let f): return "\(f)"
        case .int(let i): return "\(i)"
        case .bool(let b): return "\(b)"
        case .floatArray(let a): return a.map { "\($0)" }.joined(separator: " ")
        case .object(_): return ""
        }
    }
    
    var floatValue: Float {
        switch self {
        case .float(let f): return f
        case .int(let i): return Float(i)
        case .string(let s): return Float(s) ?? 0.0
        default: return 0.0
        }
    }
    
    var float2Value: SIMD2<Float> {
        switch self {
        case .string(let s):
            let parts = s.split(separator: " ").compactMap { Float($0) }
            if parts.count >= 2 { return SIMD2<Float>(parts[0], parts[1]) }
            return SIMD2<Float>(0, 0)
        default: return SIMD2<Float>(0, 0)
        }
    }

    var float3Value: SIMD3<Float> {
        switch self {
        case .string(let s):
            let parts = s.split(separator: " ").compactMap { Float($0) }
            if parts.count >= 3 { return SIMD3<Float>(parts[0], parts[1], parts[2]) }
            if parts.count == 1 { return SIMD3<Float>(parts[0], parts[0], parts[0]) }
            return SIMD3<Float>(0, 0, 0)
        case .object(let dict):
            if let val = dict["value"] {
                return val.float3Value
            }
            return SIMD3<Float>(0, 0, 0)
        default: return SIMD3<Float>(0, 0, 0)
        }
    }
    
    func encode(to encoder: Encoder) throws {}
}

private struct DummyCodable: Codable {}

enum BoolOrObject: Codable {
    case bool(Bool)
    case object(VisibilityObject)

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
            let b = try? container.decode(Bool.self)
        {
            self = .bool(b)
            return
        }
        if let o = try? VisibilityObject(from: decoder) {
            self = .object(o)
            return
        }
        self = .bool(true)
    }
    func encode(to encoder: Encoder) throws {}
}

struct VisibilityObject: Codable {
    let value: Bool?
}

struct ModelJSON: Codable {
    let material: String?
}

struct MaterialJSON: Codable {
    let passes: [MaterialPass]
}

struct MaterialPass: Codable {
    let textures: [String]
    let shader: String?
    let blending: String?
    let cullmode: String?
    let depthtest: String?
    let depthwrite: String?
}

struct PuppetData: Codable {
    let info: PuppetInfo
    let skinning: [PuppetSkinning]
    let skeleton: [PuppetBone]
    let animations: [PuppetAnimation]
}

struct PuppetInfo: Codable {
    let version: Int?
    let material_file: String?
}

struct PuppetSkinning: Codable {
    let vertex_id: Int
    let bone_indices: [UInt32]
    let weights: [Float]
}

struct PuppetBone: Codable {
    let id: Int
    let name: String
    let parent: Int
    let matrix: [Float]
    let render_tag: String?
}

struct PuppetAnimation: Codable {
    let id: Int
    let name: String
    let mode: String
    let fps: Float
    let length: Int
    let track_count: Int
    let tracks: [PuppetTrack]
}

struct PuppetTrack: Codable {
    let track_id: Int
    let frames: [PuppetKeyframe]
}

struct PuppetKeyframe: Codable {
    let p: [Float]
    let r: [Float]
    let s: [Float]
}

struct ParticleSystemDef: Codable {
    let animationmode: String?
    let children: [ParticleChild]?
    let controlpoint: [ParticleControlPoint]?
    let emitter: [ParticleEmitterDef]?
    let flags: Int?
    let initializer: [ParticleInitializerDef]?
    let material: String?
    let maxcount: Int?
    let `operator`: [ParticleOperatorDef]?
    let renderer: [ParticleRendererDef]?
    let sequencemultiplier: Float?
    let starttime: Float?
}

struct ParticleChild: Codable {
    let id: Int?
    let maxcount: Int?
    let name: String?
    let type: String?
    let controlpointstartindex: Int?
    let probability: Float?
    let angles: ScriptableValue?
    let origin: ScriptableValue?
    let scale: ScriptableValue?
    let particleFile: String?
}

struct ParticleControlPoint: Codable {
    let flags: Int?
    let id: Int?
    let offset: ScriptableValue?
    let locktopointer: Bool?
}

struct ParticleEmitterDef: Codable {
    let directions: ScriptableValue?
    let distancemax: ScriptableValue?
    let distancemin: ScriptableValue?
    let id: Int?
    let name: String?
    let origin: ScriptableValue?
    let rate: Float?
    let sign: ScriptableValue?
    let instantaneous: Int?
    let speedmin: Float?
    let speedmax: Float?
    let controlpoint: Int?
    let flags: Int?
    let cone: Float?
    let delay: Float?
    let duration: Float?
    let audioprocessingbounds: ScriptableValue?
    let audioprocessingexponent: Int?
    let audioprocessingfrequencystart: Int?
    let audioprocessingfrequencyend: Int?
    let audioprocessingmode: Int?
    let minperiodicdelay: Float?
    let maxperiodicdelay: Float?
    let minperiodicduration: Float?
    let maxperiodicduration: Float?
}

struct ParticleInitializerDef: Codable {
    let id: Int?
    let name: String?
    let max: ScriptableValue?
    let min: ScriptableValue?
    let exponent: ScriptableValue?
    let offset: ScriptableValue?
    let scale: ScriptableValue?
    let speedmax: ScriptableValue?
    let speedmin: ScriptableValue?
    let forward: ScriptableValue?
    let right: ScriptableValue?
    let timescale: ScriptableValue?
    let phasemin: ScriptableValue?
    let phasemax: ScriptableValue?
    let controlpoint: ScriptableValue?
    let count: ScriptableValue?
}

struct ParticleOperatorDef: Codable {
    let id: Int?
    let name: String?
    let drag: ScriptableValue?
    let gravity: ScriptableValue?
    let force: ScriptableValue?
    let fadeintime: ScriptableValue?
    let fadeouttime: ScriptableValue?
    let starttime: ScriptableValue?
    let endtime: ScriptableValue?
    let startvalue: ScriptableValue?
    let endvalue: ScriptableValue?
    let scale: ScriptableValue?
    let speedmin: ScriptableValue?
    let speedmax: ScriptableValue?
    let timescale: ScriptableValue?
    let mask: ScriptableValue?
    let phasemin: ScriptableValue?
    let phasemax: ScriptableValue?
    let controlpoint: Int?
    let flags: Int?
    let axis: ScriptableValue?
    let offset: ScriptableValue?
    let distanceinner: ScriptableValue?
    let distanceouter: ScriptableValue?
    let speedinner: ScriptableValue?
    let speedouter: ScriptableValue?
    let centerforce: ScriptableValue?
    let ringradius: ScriptableValue?
    let ringwidth: ScriptableValue?
    let ringpulldistance: ScriptableValue?
    let ringpullforce: ScriptableValue?
    let origin: ScriptableValue?
    let threshold: ScriptableValue?
    let frequencymin: ScriptableValue?
    let frequencymax: ScriptableValue?
    let scalemin: ScriptableValue?
    let scalemax: ScriptableValue?
}

struct ParticleRendererDef: Codable {
    let id: Int?
    let name: String?
    let length: Float?
    let maxlength: Float?
    let minlength: Float?
    let subdivision: Float?
    let segments: Float?
    let uvscale: Float?
    let uvscrolling: Bool?
    let uvsmoothing: Bool?
    let fadealpha: Bool?
    let fadesize: Bool?
}

struct ParticleInstanceOverride: Codable {
    let alpha: Float?
    let count: Float?
    let id: Int?
    let rate: Float?
    let speed: Float?
    let color: String?
    let colorn: String?
    let size: Float?
    let lifetime: Float?
}
