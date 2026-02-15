//
//  SceneModels.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import Foundation

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
    let type: String?
    let origin: ScriptableValue?
    let size: ScriptableValue?
    let scale: ScriptableValue?
    let angles: ScriptableValue?
    let parent: Int?
    let visible: BoolOrObject?
    let effects: [EffectJSON]?
    let particle: String?
    let instanceoverride: [String: ScriptableValue]?

    var isVisible: Bool {
        if let v = visible {
            if case .bool(let b) = v { return b }
            return true
        }
        return true
    }
}

struct EffectJSON: Codable {
    let file: String?
    let passes: [EffectPassJSON]?
}

struct EffectPassJSON: Codable {
    let constantshadervalues: [String: ScriptableValue]?
}

enum ScriptableValue: Codable {
    case string(String)
    case script(value: String)
    case float(Float)

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let str = try? container.decode(String.self) {
                self = .string(str)
                return
            }
            if let num = try? container.decode(Float.self) {
                self = .float(num)
                return
            }
        }
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
            let val = try? container.decode(String.self, forKey: .value)
        {
            self = .script(value: val)
            return
        }
        self = .string("0 0 0")
    }

    var value: String {
        switch self {
        case .string(let s): return s
        case .script(let v): return v
        case .float(let f): return "\(f)"
        }
    }
    enum CodingKeys: String, CodingKey { case value }
    func encode(to encoder: Encoder) throws {}
}

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

struct ParticleSystemJSON: Codable {
    let children: [ParticleChildJSON]?
    let root: ParticleChildJSON?
}

struct ParticleChildJSON: Codable {
    let name: String?
    let type: String?
    let material: String?
    let maxcount: Int?
    let rate: Float?
    let count: Int?
    let lifetime: Float?
    let position: String?
    let origin: String?
    let rotation: String?
    let size: String?
    let color: String?
    let alpha: String?
    let texture: String?
    let children: [ParticleChildJSON]?
    let emitters: [ParticleModuleJSON]?
    let initializers: [ParticleModuleJSON]?
    let operators: [ParticleModuleJSON]?
    let renderers: [ParticleModuleJSON]?
}

struct ParticleModuleJSON: Codable {
    let name: String?
    let min: ScriptableValue?
    let max: ScriptableValue?
    let x: ScriptableValue?
    let y: ScriptableValue?
    let z: ScriptableValue?
    let r: ScriptableValue?
    let g: ScriptableValue?
    let b: ScriptableValue?
    let a: ScriptableValue?
    let strength: Float?
    let frequency: Float?
    let scale: Float?
    let offset: ScriptableValue?
    let speed: ScriptableValue?
    let drag: Float?
    let gravity: String?
    let force: String?
    let direction: String?
    let random: Bool?
    let fadeintime: Float?
    let fadeouttime: Float?
    let starttime: Float?
    let endtime: Float?
    let startvalue: ScriptableValue?
    let endvalue: ScriptableValue?
    let distancemin: ScriptableValue?
    let distancemax: ScriptableValue?
    let rate: Float?
    let origin: String?
    let directions: String?
    let speedmin: Float?
    let speedmax: Float?
    let phasemin: Float?
    let phasemax: Float?
    let timescale: Float?
    let distanceinner: Float?
    let distanceouter: Float?
    let speedinner: Float?
    let speedouter: Float?
    let axis: String?
    let controlpoint: Int?
    let threshold: Float?
    let mask: String?
}
