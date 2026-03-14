//
//  ParticleInstance.swift
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

import Foundation
import simd

struct ParticleInstance {
    var position: SIMD3<Float> = .zero
    var velocity: SIMD3<Float> = .zero
    var acceleration: SIMD3<Float> = .zero

    var rotation: SIMD3<Float> = .zero
    var angularVelocity: SIMD3<Float> = .zero
    var angularAcceleration: SIMD3<Float> = .zero

    var color: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0)
    var alpha: Float = 1.0
    var size: Float = 20.0
    var frame: Float = 0.0

    var lifetime: Float = 1.0
    var age: Float = 0.0

    struct OscillatorAlpha {
        var frequency: Float = 0.0
        var scale: Float = 1.0
        var phase: Float = 0.0
        var base: Float = 1.0
        var initialized: Bool = false
    }
    var oscillateAlpha = OscillatorAlpha()

    struct OscillatorSize {
        var frequency: Float = 0.0
        var scale: Float = 1.0
        var phase: Float = 0.0
        var base: Float = 1.0
        var initialized: Bool = false
    }
    var oscillateSize = OscillatorSize()

    struct OscillatorPosition {
        var frequency: SIMD3<Float> = .zero
        var scale: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0)
        var phase: SIMD3<Float> = .zero
        var initialized: Bool = false
    }
    var oscillatePosition = OscillatorPosition()

    struct InitialValues {
        var color: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0)
        var alpha: Float = 1.0
        var size: Float = 20.0
        var lifetime: Float = 1.0
    }
    var initial = InitialValues()

    var alive: Bool = false

    func getLifetimePos() -> Float {
        return lifetime > 0.0 ? (age / lifetime) : 1.0
    }

    func isAlive() -> Bool {
        return alive && age < lifetime
    }
}

struct ControlPointData {
    var position: SIMD3<Float> = .zero
    var offset: SIMD3<Float> = .zero
    var linkMouse: Bool = false
    var worldSpace: Bool = false
}
