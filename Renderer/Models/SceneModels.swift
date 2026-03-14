//
//  SceneModels.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import Foundation
import simd

struct SceneRoot: Codable {
    let camera: SceneCamera?
    let general: SceneGeneral?
    let objects: [SceneObject]
}

struct SceneCamera: Codable {
    let center: String?
    let eye: String?
    let up: String?
}

struct SceneGeneral: Codable {
    let ambientcolor: String?
    let bloom: Bool?
    let bloomhdrfeather: Float?
    let bloomhdriterations: Int?
    let bloomhdrscatter: Float?
    let bloomhdrstrength: Float?
    let bloomhdrthreshold: Float?
    let bloomstrength: Float?
    let bloomthreshold: Float?
    let bloomtint: String?
    let clearcolor: String?
    let clearenabled: Bool?
    let farz: Float?
    let fov: Float?
    let hdr: Bool?
    let nearz: Float?
    let orthogonalprojection: OrthogonalProjection?
    let perspectiveoverridefov: Float?
}

struct OrthogonalProjection: Codable {
    let height: Int
    let width: Int
}

struct SceneObject: Codable {
    let id: Int?
    let parent: Int?
    let name: String?
    let image: String?
    let particle: String?
    let origin: SceneTransformValue?
    let angles: SceneTransformValue?
    let scale: SceneTransformValue?
    let size: SceneTransformValue?
    let visible: SceneVisibleValue?
    let colorBlendMode: Int?
    let animationlayers: [AnimationLayer]?
    let instanceoverride: InstanceOverride?
    let solid: Bool?
    let castshadow: Bool?
    let clampuvs: Bool?
    let disablepropagation: Bool?
    let copybackground: Bool?
    let parallaxDepth: String?
    let alpha: Float?
    let anchor: String?
    let backgroundbrightness: Float?
    let backgroundcolor: String?
    let blockalign: Bool?
    let color: String?
    let depthtest: String?
    let font: String?
    let horizontalalign: String?
    let limitrows: Bool?
    let limituseellipsis: Bool?
    let limitwidth: Bool?
    let maxrows: Int?
    let maxwidth: Float?
    let opaquebackground: Bool?
    let padding: Int?
    let pointsize: Float?
    let verticalalign: String?
    let maxtime: Float?
    let mintime: Float?
    let muteineditor: Bool?
    let playbackmode: String?
    let sound: [String]?
    let startsilent: Bool?
    let volume: Float?
    
    var isVisible: Bool {
        if let v = visible {
            return v.value ?? true
        }
        return true
    }
}

struct SceneTransformValue: Codable {
    let value: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict["value"]?.stringValue
        } else {
            value = nil
        }
    }
}

struct SceneVisibleValue: Codable {
    let user: String?
    let value: Bool?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
            user = nil
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            user = dict["user"]?.stringValue
            value = dict["value"]?.boolValue
        } else {
            user = nil
            value = nil
        }
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    var stringValue: String? { value as? String }
    var boolValue: Bool? { value as? Bool }
    var floatValue: Float? {
        if let f = value as? Float { return f }
        if let d = value as? Double { return Float(d) }
        if let i = value as? Int { return Float(i) }
        return nil
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else { value = "" }
    }
    
    func encode(to encoder: Encoder) throws {}
}

struct AnimationLayer: Codable {
    let id: Int?
    let name: String?
    let animation: Int?
    let additive: Bool?
    let blend: Float?
    let rate: Float?
}

struct InstanceOverride: Codable {
    let id: Int?
    let count: DynamicValue?
    let size: DynamicValue?
    let speed: DynamicValue?
    let colorn: DynamicValue?
    let alpha: DynamicValue?
    let lifetime: DynamicValue?
    let rate: DynamicValue?
    let color: DynamicValue?
}

struct ModelJSON: Codable {
    let material: String?
}

struct MaterialJSON: Codable {
    let passes: [MaterialPass]
}

struct MaterialPass: Codable {
    let textures: [String]
    let depthwrite: String?
    let combos: [String: Int]?
    let constants: [String: MaterialConstant]?
}

struct MaterialConstant: Codable {
    let value: DynamicValue?
}

struct PuppetData: Codable {
    let info: PuppetInfo
    let skeleton: [PuppetBone]
    let skinning: [PuppetSkin]
    let sub_meshes: [PuppetSubMesh]
    let mask_bindings: [PuppetMaskBinding]?
    let clipping_masks: [String]?
    let animations: [PuppetAnimation]
}

struct PuppetInfo: Codable {
    let material_file: String?
}

struct PuppetBone: Codable {
    let id: Int
    let name: String
    let parent: Int
    let position: [Float]
    let rotation: [Float]
    let scale: [Float]
}

struct PuppetSkin: Codable {
    let bone_id: Int
    let weight: Float
}

struct PuppetSubMesh: Codable {
    let id: Int
    let start_index: Int
    let index_count: Int
}

struct PuppetMaskBinding: Codable {
    let mask_id: Int
    let sub_mesh_id: Int
    let mode: Int
}

struct PuppetAnimation: Codable {
    let id: Int
    let name: String
    let duration: Float
    let keys: [PuppetAnimKey]
}

struct PuppetAnimKey: Codable {
    let bone: Int
    let time: Float
    let position: [Float]?
    let rotation: [Float]?
    let scale: [Float]?
}
