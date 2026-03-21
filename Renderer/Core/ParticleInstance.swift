//
//  ParticleInstance.swift
//  Renderer
//
//  Created by laobamac on 2026/3/21.
//

import Foundation
import simd

struct ParticleInstance {
    var position: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var velocity: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var acceleration: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var rotation: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var angularVelocity: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var angularAcceleration: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var color: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    var alpha: Float = 1.0
    var size: Float = 20.0
    var frame: Float = 0.0
    var lifetime: Float = 1.0
    var age: Float = 0.0
    var alive: Bool = false
    
    struct InitialState {
        var color: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
        var alpha: Float = 1.0
        var size: Float = 20.0
        var lifetime: Float = 1.0
    }
    var initial: InitialState = InitialState()
    
    struct OscillateStateAlphaSize {
        var frequency: Float = 0.0
        var scale: Float = 1.0
        var phase: Float = 0.0
        var base: Float = 1.0
        var initialized: Bool = false
    }
    var oscillateAlpha: OscillateStateAlphaSize = OscillateStateAlphaSize()
    var oscillateSize: OscillateStateAlphaSize = OscillateStateAlphaSize()
    
    struct OscillateStatePosition {
        var frequency: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
        var scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
        var phase: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
        var initialized: Bool = false
    }
    var oscillatePosition: OscillateStatePosition = OscillateStatePosition()
    
    func getLifetimePos() -> Float {
        return lifetime > 0.0 ? (age / lifetime) : 1.0
    }
    
    func isAlive() -> Bool {
        return alive && age < lifetime
    }
}

struct ControlPointData {
    var position: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var offset: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var linkMouse: Bool = false
    var worldSpace: Bool = false
}
