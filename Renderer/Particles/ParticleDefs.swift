//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import simd

struct ParticleInstance {
    var position: SIMD3<Float> = .zero
    var velocity: SIMD3<Float> = .zero
    var acceleration: SIMD3<Float> = .zero
    var rotation: SIMD3<Float> = .zero
    var angularVelocity: SIMD3<Float> = .zero
    var angularAcceleration: SIMD3<Float> = .zero

    var color: SIMD3<Float> = .one
    var alpha: Float = 1.0
    var size: Float = 20.0
    var frame: Float = -1.0

    var lifetime: Float = 1.0
    var age: Float = 0.0

    struct OscillatorState {
        var frequency: Float = 0.0
        var scale: Float = 1.0
        var phase: Float = 0.0
        var base: Float = 1.0
        var initialized: Bool = false
    }

    struct PositionOscillatorState {
        var frequency: SIMD3<Float> = .zero
        var scale: SIMD3<Float> = .one
        var phase: SIMD3<Float> = .zero
        var initialized: Bool = false
    }

    var oscillateAlpha = OscillatorState()
    var oscillateSize = OscillatorState()
    var oscillatePosition = PositionOscillatorState()

    struct InitialState {
        var color: SIMD3<Float> = .one
        var alpha: Float = 1.0
        var size: Float = 20.0
        var lifetime: Float = 1.0
    }

    var initial = InitialState()
    var alive: Bool = false

    var lifetimePos: Float {
        return lifetime > 0.0 ? (age / lifetime) : 1.0
    }

    var isAlive: Bool {
        return alive && age < lifetime
    }
}

struct ControlPointData {
    var position: SIMD3<Float> = .zero
    var offset: SIMD3<Float> = .zero
    var linkMouse: Bool = false
    var worldSpace: Bool = false
}

protocol ParticleEmitter {
    func emit(
        particles: inout [ParticleInstance],
        count: inout Int,
        dt: Float,
        controlPoints: [ControlPointData],
        initializers: [ParticleInitializer],
        instanceOverride: ParticleInstanceOverride?,
        isOrthographic: Bool
    )
}

protocol ParticleInitializer {
    func initialize(
        particle: inout ParticleInstance,
        instanceOverride: ParticleInstanceOverride?
    )
}

protocol ParticleOperator {
    func apply(
        particles: inout [ParticleInstance],
        count: Int,
        controlPoints: [ControlPointData],
        currentTime: Float,
        dt: Float,
        instanceOverride: ParticleInstanceOverride?,
        globalGravity: SIMD3<Float>,
        globalWind: SIMD3<Float>
    )
}
