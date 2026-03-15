//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/3/15.
//

import Foundation
import simd

enum ParticlePropertyValue: Codable {
    case float(Float)
    case string(String)
    case floatArray([Float])

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let floatVal = try? container.decode(Float.self) {
                print("ParticlePropertyValue decoded float: \(floatVal)")
                self = .float(floatVal)
                return
            }
            if let stringVal = try? container.decode(String.self) {
                print("ParticlePropertyValue decoded string: \(stringVal)")
                self = .string(stringVal)
                return
            }
        }
        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var arr: [Float] = []
            while !unkeyedContainer.isAtEnd {
                if let f = try? unkeyedContainer.decode(Float.self) {
                    arr.append(f)
                }
            }
            print("ParticlePropertyValue decoded float array: \(arr)")
            self = .floatArray(arr)
            return
        }
        print("ParticlePropertyValue failed to decode, defaulting to 0.0")
        self = .float(0.0)
    }

    func encode(to encoder: Encoder) throws {}
}

struct ParticleSystemConfig: Codable {
    let animationmode: String?
    let children: [ParticleChild]?
    let controlpoint: [ParticleControlPoint]?
    let emitter: [ParticleEmitter]?
    let flags: Int?
    let initializer: [ParticleInitializer]?
    let material: String?
    let maxcount: Int?
    let `operator`: [ParticleOperator]?
    let renderer: [ParticleRenderer]?
    let sequencemultiplier: Float?
    let starttime: Float?
}

struct ParticleChild: Codable {
    let id: Int
    let name: String
}

struct ParticleControlPoint: Codable {
    let id: Int
    let angles: String?
}

struct ParticleEmitter: Codable {
    let id: Int
    let name: String
    let rate: ParticlePropertyValue?
    let directions: String?
    let distancemax: Float?
    let distancemin: Float?
    let origin: String?
}

struct ParticleInitializer: Codable {
    let id: Int
    let name: String
    let min: ParticlePropertyValue?
    let max: ParticlePropertyValue?
    let offset: Float?
    let scale: Float?
    let speedmax: Float?
    let speedmin: Float?
}

struct ParticleOperator: Codable {
    let id: Int
    let name: String
    let fadeintime: Float?
    let fadeouttime: Float?
}

struct ParticleRenderer: Codable {
    let id: Int
    let name: String
}
