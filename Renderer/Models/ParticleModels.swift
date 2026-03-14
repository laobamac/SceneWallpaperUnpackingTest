//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

import Foundation
import simd

struct ParticleInstanceOverride: Codable {
    let enabled: BoolOrObject?
    let alpha: ScriptableValue?
    let size: ScriptableValue?
    let lifetime: ScriptableValue?
    let rate: ScriptableValue?
    let speed: ScriptableValue?
    let count: ScriptableValue?
    let color: ScriptableValue?
    let colorn: ScriptableValue?
}

struct ParticleDefinition: Codable {
    let material: String?
    let animationmode: String?
    let sequencemultiplier: Swift.Float?
    let maxcount: Int?
    let starttime: Swift.Float?
    let flags: Int?
    let emitter: [ParticleEmitter]?
    let initializer: [ParticleInitializer]?
    let `operator`: [ParticleOperator]?
    let renderer: [ParticleRenderer]?
    let controlpoint: [ParticleControlPoint]?
    let children: [ParticleChild]?
}

struct ParticleEmitter: Codable {
    let id: Int?
    let name: String?
    let directions: ScriptableValue?
    let distancemin: ScriptableValue?
    let distancemax: ScriptableValue?
    let origin: ScriptableValue?
    let sign: ScriptableValue?
    let instantaneous: Int?
    let speedmin: Swift.Float?
    let speedmax: Swift.Float?
    let rate: Swift.Float?
    let controlpoint: Int?
    let flags: Int?
    let cone: Swift.Float?
    let delay: Swift.Float?
    let duration: Swift.Float?
    let audioprocessingbounds: ScriptableValue?
    let audioprocessingexponent: Swift.Float?
    let audioprocessingfrequencystart: Int?
    let audioprocessingfrequencyend: Int?
    let audioprocessingmode: Int?
    let minperiodicdelay: Swift.Float?
    let maxperiodicdelay: Swift.Float?
    let minperiodicduration: Swift.Float?
    let maxperiodicduration: Swift.Float?
}

struct ParticleInitializer: Codable {
    let id: Int?
    let name: String?
    let min: ScriptableValue?
    let max: ScriptableValue?
    let exponent: ScriptableValue?
    let speedmin: ScriptableValue?
    let speedmax: ScriptableValue?
    let scale: ScriptableValue?
    let offset: ScriptableValue?
    let forward: ScriptableValue?
    let timescale: ScriptableValue?
    let phasemin: ScriptableValue?
    let phasemax: ScriptableValue?
    let right: ScriptableValue?
    let controlpoint: ScriptableValue?
    let count: ScriptableValue?
}

struct ParticleOperator: Codable {
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

struct ParticleRenderer: Codable {
    let id: Int?
    let name: String?
    let length: Swift.Float?
    let maxlength: Swift.Float?
    let minlength: Swift.Float?
    let subdivision: Swift.Float?
    let segments: Swift.Float?
    let uvscale: Swift.Float?
    let uvscrolling: Bool?
    let uvsmoothing: Bool?
    let fadealpha: Bool?
    let fadesize: Bool?
}

struct ParticleControlPoint: Codable {
    let id: Int?
    let flags: Int?
    let offset: ScriptableValue?
    let locktopointer: Bool?
}

struct ParticleChild: Codable {
    let id: Int?
    let type: String?
    let name: String?
    let maxcount: Int?
    let controlpointstartindex: Int?
    let probability: Swift.Float?
    let angles: ScriptableValue?
    let origin: ScriptableValue?
    let scale: ScriptableValue?
    let particle: String?
}
