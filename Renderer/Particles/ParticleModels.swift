//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

import simd
import Foundation

struct WPMaterial {
    var fileName: String = ""
    var renderer: String = "sprite"
}

struct Particle {
    struct InitValue {
        var color: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0)
        var alpha: Float = 1.0
        var size: Float = 20.0
        var lifetime: Float = 1.0
    }
    
    var position: SIMD3<Float> = .zero
    var color: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0)
    var alpha: Float = 1.0
    var size: Float = 20.0
    var lifetime: Float = 1.0
    
    var rotation: SIMD3<Float> = .zero
    var velocity: SIMD3<Float> = .zero
    var acceleration: SIMD3<Float> = .zero
    var angularVelocity: SIMD3<Float> = .zero
    var angularAcceleration: SIMD3<Float> = .zero
    
    var markNew: Bool = true
    var initValue: InitValue = InitValue()
}

struct ParticleControlPoint {
    var linkMouse: Bool = false
    var worldSpace: Bool = false
    var offset: SIMD3<Float> = .zero
    var id: Int = -1
}

struct ParticleInfo {
    var particles: UnsafeMutableBufferPointer<Particle>
    var controlPoints: [ParticleControlPoint]
    var time: Double
    var timePass: Double
}

typealias ParticleInitOp = (inout Particle, Double) -> Void
typealias ParticleOperatorOp = (ParticleInfo) -> Void
typealias ParticleEmittOp = (inout [Particle], [ParticleInitOp], Int, Double) -> Void

enum ParticleSpawnType: String {
    case `static`
    case eventFollow = "eventfollow"
    case eventSpawn = "eventspawn"
    case eventDeath = "eventdeath"
}

struct ParticleInstanceOverride {
    var enabled: Bool = false
    var overColor: Bool = false
    var overColorN: Bool = false
    
    var alpha: Float = 1.0
    var count: Float = 1.0
    var lifetime: Float = 1.0
    var rate: Float = 1.0
    var speed: Float = 1.0
    var size: Float = 1.0
    var color: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0)
    var colorN: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0)
}
