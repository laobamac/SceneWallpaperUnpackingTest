//
//  EffectModels.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation

struct EffectConfig: Codable {
    let name: String?
    let description: String?
    let group: String?
    let preview: String?
    let passes: [EffectPassConfig]?
    let dependencies: [String]?
    let fbos: [FBOConfig]?
}

struct EffectPassConfig: Codable {
    let material: String?
    let command: String?
    let source: String?
    let target: String?
    let binds: [BindConfig]?
}

struct BindConfig: Codable {
    let index: Int
    let name: String
}

struct FBOConfig: Codable {
    let name: String
    let format: String?
    let scale: Float?
    let unique: Bool?
}

struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let arrayVal = try? container.decode([Double].self) {
            value = arrayVal
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int { try container.encode(intVal) }
        else if let doubleVal = value as? Double { try container.encode(doubleVal) }
        else if let stringVal = value as? String { try container.encode(stringVal) }
        else if let boolVal = value as? Bool { try container.encode(boolVal) }
        else if let arrayVal = value as? [Double] { try container.encode(arrayVal) }
    }
}
