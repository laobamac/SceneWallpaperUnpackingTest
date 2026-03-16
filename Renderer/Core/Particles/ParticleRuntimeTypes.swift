//
//  ParticleRuntimeTypes.swift
//  Renderer
//
//  Created by laobamac on 2026/3/17.
//

import Foundation
import MetalKit
import simd

struct ParticleInstance {
    var position: simd_float3 = .zero
    var velocity: simd_float3 = .zero
    var acceleration: simd_float3 = .zero
    var rotation: simd_float3 = .zero
    var angularVelocity: simd_float3 = .zero
    var angularAcceleration: simd_float3 = .zero
    var color: simd_float3 = simd_float3(1.0, 1.0, 1.0)
    var alpha: Float = 1.0
    var size: Float = 20.0
    var frame: Float = 0.0
    var lifetime: Float = 1.0
    var age: Float = 0.0

    struct Oscillator {
        var frequency: Float = 0.0
        var scale: Float = 1.0
        var phase: Float = 0.0
        var base: Float = 1.0
        var initialized: Bool = false
    }
    var oscillateAlpha = Oscillator()
    var oscillateSize = Oscillator()

    struct PositionOscillator {
        var frequency: simd_float3 = .zero
        var scale: simd_float3 = simd_float3(1.0, 1.0, 1.0)
        var phase: simd_float3 = .zero
        var initialized: Bool = false
    }
    var oscillatePosition = PositionOscillator()

    struct InitialState {
        var color: simd_float3 = simd_float3(1.0, 1.0, 1.0)
        var alpha: Float = 1.0
        var size: Float = 20.0
        var lifetime: Float = 1.0
    }
    var initial = InitialState()

    var alive: Bool = false

    func getLifetimePos() -> Float {
        return lifetime > 0.0 ? (age / lifetime) : 1.0
    }

    func isAlive() -> Bool {
        return alive && age < lifetime
    }
}

struct ControlPointData {
    var position: simd_float3 = .zero
    var offset: simd_float3 = .zero
    var linkMouse: Bool = false
    var worldSpace: Bool = false
}

typealias EmitterFunc = (inout [ParticleInstance], inout Int, Float) -> Void
typealias InitializerFunc = (inout ParticleInstance) -> Void
typealias OperatorFunc = (inout [ParticleInstance], Int, [ControlPointData], Float, Float) -> Void
