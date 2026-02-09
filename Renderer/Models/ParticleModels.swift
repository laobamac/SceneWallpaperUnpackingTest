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
    let flags: Int?
    
    enum CodingKeys: String, CodingKey {
        case children, controlpoint, emitter, initializer, material, maxcount, renderer, starttime, flags
        case operatorList = "operator"
    }
}

struct ParticleChild: Codable {
    let id: Int?
    let name: String
    let type: String?
    let maxcount: Int?
    let probability: Float?
    let count: Int?
}

struct ParticleControlPoint: Codable {
    let id: Int
    let offset: String?
    let flags: Int?
}

struct ParticleEmitter: Codable {
    let id: Int
    let name: String
    let rate: Float?
    let origin: String?
    let directions: String?
    let distancemin: ScriptableValue?
    let distancemax: ScriptableValue?
    let delay: Float?
    let duration: Float?
    let instantaneous: Int?
    let flags: Int?
    let controlpoint: Int?
    let sign: String?
    let speedmin: Float?
    let speedmax: Float?
}

struct ParticleInitializer: Codable {
    let id: Int
    let name: String
    let min: ScriptableValue?
    let max: ScriptableValue?
    let exponent: ScriptableValue?
    let offset: ScriptableValue?
    let scale: ScriptableValue?
    let speedmin: ScriptableValue?
    let speedmax: ScriptableValue?
    let forward: ScriptableValue?
    let right: ScriptableValue?
    let up: ScriptableValue?
    let phasemin: ScriptableValue?
    let phasemax: ScriptableValue?
    let timescale: ScriptableValue?
}

struct ParticleOperator: Codable {
    let id: Int
    let name: String
    let gravity: ScriptableValue?
    let drag: ScriptableValue?
    let fadeintime: ScriptableValue?
    let fadeouttime: ScriptableValue?
    let frequencymax: ScriptableValue?
    let frequencymin: ScriptableValue?
    let scalemax: ScriptableValue?
    let scalemin: ScriptableValue?
    let phasemin: ScriptableValue?
    let phasemax: ScriptableValue?
    let mask: ScriptableValue?
    let speedmax: ScriptableValue?
    let speedmin: ScriptableValue?
    let scale: ScriptableValue?
    let timescale: ScriptableValue?
    let threshold: ScriptableValue?
    let controlpoint: Int?
    let force: ScriptableValue?
    let startvalue: ScriptableValue?
    let endvalue: ScriptableValue?
    let starttime: ScriptableValue?
    let endtime: ScriptableValue?
    let origin: ScriptableValue?
    let axis: ScriptableValue?
    let speedInner: ScriptableValue?
    let speedOuter: ScriptableValue?
    let distanceInner: ScriptableValue?
    let distanceOuter: ScriptableValue?
    let ringRadius: ScriptableValue?
    let ringWidth: ScriptableValue?
    let centerForce: ScriptableValue?
    let ringPullDistance: ScriptableValue?
    let ringPullForce: ScriptableValue?
    let offset: ScriptableValue?
    
    enum CodingKeys: String, CodingKey {
        case id, name, gravity, drag, fadeintime, fadeouttime
        case frequencymax, frequencymin, scalemax, scalemin, phasemin, phasemax
        case mask, speedmax, speedmin, scale, timescale, threshold, controlpoint, force
        case startvalue, endvalue, starttime, endtime, origin, axis, offset
        case speedInner = "speedinner"
        case speedOuter = "speedouter"
        case distanceInner = "distanceinner"
        case distanceOuter = "distanceouter"
        case ringRadius, ringWidth, centerForce, ringPullDistance, ringPullForce
    }
}

struct ParticleRenderer: Codable {
    let id: Int
    let name: String
    let subdivision: Int?
}
