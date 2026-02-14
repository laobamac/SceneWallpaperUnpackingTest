//
//  Particles.swift
//  Renderer
//
//  Created by laobamac on 2026/2/14.
//

import simd

struct Particle {
    struct InitValue {
        var color: SIMD4<Float> = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
        var size: Float = 20.0
        var lifetime: Float = 1.0
    }
    
    var position: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var color: SIMD4<Float> = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
    var size: Float = 20.0
    var lifetime: Float = 1.0
    
    var rotation: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var velocity: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var acceleration: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var angularVelocity: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var angularAcceleration: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    
    var markNew: Bool = true
    var initValue: InitValue = InitValue()
}
