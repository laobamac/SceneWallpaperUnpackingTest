//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/3/21.
//

import Foundation
import simd

struct ParticleSystemDef: Codable {
    let material: String?
    let maxcount: Int?
    let flags: Int?
    let starttime: Float?
    let sequencemultiplier: Float?
    let controlpoint: [ParticleControlPointDef]?
    let emitter: [ParticleEmitterDef]?
    let initializer: [ParticleInitializerDef]?
    let operatorList: [ParticleOperatorDef]?
    let renderer: [ParticleRendererDef]?
    
    enum CodingKeys: String, CodingKey {
        case material
        case maxcount
        case flags
        case starttime
        case sequencemultiplier
        case controlpoint
        case emitter
        case initializer
        case operatorList = "operator"
        case renderer
    }
}

struct ParticleControlPointDef: Codable {
    let id: Int
    let offset: ScriptableValue?
    let flags: Int?
}

struct ParticleEmitterDef: Codable {
    let name: String
    let id: Int?
    let rate: Float?
    let instantaneous: Int?
    let delay: Float?
    let duration: Float?
    let origin: ScriptableValue?
    let directions: ScriptableValue?
    let distancemin: ScriptableValue?
    let distancemax: ScriptableValue?
    let speedmin: Float?
    let speedmax: Float?
    let controlPoint: Int?
    let flags: Int?
    let sign: ScriptableValue?
    let minPeriodicDuration: Float?
    let maxPeriodicDuration: Float?
    let minPeriodicDelay: Float?
    let maxPeriodicDelay: Float?
}

struct ParticleInitializerDef: Codable {
    let name: String
    let id: Int?
    let min: ScriptableValue?
    let max: ScriptableValue?
    let exponent: ScriptableValue?
    let offset: ScriptableValue?
    let scale: ScriptableValue?
    let speedmin: ScriptableValue?
    let speedmax: ScriptableValue?
    let forward: ScriptableValue?
    let right: ScriptableValue?
    let timescale: ScriptableValue?
    let phasemin: ScriptableValue?
    let phasemax: ScriptableValue?
    let controlPoint: ScriptableValue?
    let count: ScriptableValue?
    
    enum CodingKeys: String, CodingKey {
        case name
        case id
        case min
        case max
        case exponent
        case offset
        case scale
        case speedmin
        case speedmax
        case forward
        case right
        case timescale
        case phasemin
        case phasemax
        case controlPoint = "controlpoint"
        case count
    }
}

struct ParticleOperatorDef: Codable {
    let name: String
    let id: Int?
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
    let controlPoint: Int?
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
    let audioprocessingmode: ScriptableValue?
    let origin: ScriptableValue?
    let threshold: ScriptableValue?
    let frequencymin: ScriptableValue?
    let frequencymax: ScriptableValue?
    let scalemin: ScriptableValue?
    let scalemax: ScriptableValue?
    
    enum CodingKeys: String, CodingKey {
        case name
        case id
        case drag
        case gravity
        case force
        case fadeintime
        case fadeouttime
        case starttime
        case endtime
        case startvalue
        case endvalue
        case scale
        case speedmin
        case speedmax
        case timescale
        case mask
        case phasemin
        case phasemax
        case controlPoint = "controlpoint"
        case flags
        case axis
        case offset
        case distanceinner
        case distanceouter
        case speedinner
        case speedouter
        case centerforce
        case ringradius
        case ringwidth
        case ringpulldistance
        case ringpullforce
        case audioprocessingmode
        case origin
        case threshold
        case frequencymin
        case frequencymax
        case scalemin
        case scalemax
    }
}

struct ParticleRendererDef: Codable {
    let name: String
    let id: Int?
    let subdivision: Int?
    let uvscale: Float?
    let uvscrolling: Bool?
    let uvsmoothing: Bool?
    let length: Float?
    let segments: Int?
    let maxlength: Float?
    let minlength: Float?
    
    enum CodingKeys: String, CodingKey {
        case name
        case id
        case subdivision
        case uvscale
        case uvscrolling
        case uvsmoothing
        case length
        case segments
        case maxlength
        case minlength
    }
}
