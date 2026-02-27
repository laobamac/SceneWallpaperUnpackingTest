//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/2/27.
//

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
