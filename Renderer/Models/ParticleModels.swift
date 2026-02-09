//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/2/8.
//

import Foundation

struct ParticleSystemConfig: Codable {
    let children: [ParticleChild]?
    let controlpoint: [ParticleControlPoint]?
    let emitter: [ParticleEmitter]?
    let initializer: [ParticleInitializer]?
    let material: String?
    let maxcount: Int?
    let operatorList: [ParticleOperator]?
    let renderer: [ParticleRenderer]?
    let starttime: Float?
    
    enum CodingKeys: String, CodingKey {
        case children, controlpoint, emitter, initializer, material, maxcount, renderer, starttime
        case operatorList = "operator"
    }
}

struct ParticleChild: Codable {
    let id: Int?
    let name: String
    let type: String?
    let maxcount: Int?
}

struct ParticleControlPoint: Codable {
    let id: Int
    let offset: String?
}

struct ParticleEmitter: Codable {
    let id: Int
    let name: String
    let rate: Float?
    let origin: String?
    let directions: String?
    let distancemin: Float?
    let distancemax: Float?
}

struct ParticleInitializer: Codable {
    let id: Int
    let name: String
    let min: ScriptableValue?
    let max: ScriptableValue?
    let exponent: Float?
    let offset: Float?
    let scale: Float?
    let speedmin: Float?
    let speedmax: Float?
}

struct ParticleOperator: Codable {
    let id: Int
    let name: String
    let gravity: String?
    let drag: Float?
    let fadeintime: Float?
    let fadeouttime: Float?
    let frequencymax: Float?
    let frequencymin: Float?
    let scalemax: Float?
    let scalemin: Float?
    let mask: String?
    let speedmax: Float?
    let speedmin: Float?
    let scale: Float?
    let threshold: Float?
    let controlpoint: Int?
    let force: String?
    let startvalue: Float?
    let endvalue: Float?
}

struct ParticleRenderer: Codable {
    let id: Int
    let name: String
}
