//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/3/16.
//

import Foundation
import simd

struct ParticleSystemConfig: Codable {
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
    let id: Int?
    let name: String?
}

struct ParticleControlPoint: Codable {
    let id: Int?
    let angles: ScriptableValue?
}

struct ParticleEmitter: Codable {
    let id: Int?
    let name: String?
    let directions: ScriptableValue?
    let distancemax: Float?
    let distancemin: Float?
    let origin: ScriptableValue?
    let rate: Float?
}

struct ParticleInitializer: Codable {
    let id: Int?
    let name: String?
    let min: ScriptableValue?
    let max: ScriptableValue?
    let offset: Float?
    let scale: Float?
    let speedmax: Float?
    let speedmin: Float?
}

struct ParticleOperator: Codable {
    let id: Int?
    let name: String?
    let fadeintime: Float?
    let fadeouttime: Float?
}

struct ParticleRenderer: Codable {
    let id: Int?
    let name: String?
}
