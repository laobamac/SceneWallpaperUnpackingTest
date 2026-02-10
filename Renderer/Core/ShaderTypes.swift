//
//  ShaderTypes.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import simd

struct ObjectUniforms {
    var modelMatrix: matrix_float4x4
    var alpha: Float
    var color: SIMD4<Float>
    var animInfo: SIMD3<Float> = .zero
}

struct GlobalUniforms {
    var projectionMatrix: matrix_float4x4
    var viewMatrix: matrix_float4x4
    var time: Float
    var padding: SIMD3<Float> = .zero
}

struct PuppetVertex {
    var px: Float, py: Float, pz: Float
    var pad1: Float = 0
    var u: Float, v: Float
    var j1: UInt16, j2: UInt16, j3: UInt16, j4: UInt16
    var w1: Float, w2: Float, w3: Float, w4: Float
}

struct ParticleVertex {
    var positionAndSeed: SIMD4<Float>
    var texData: SIMD4<Float>
    var color: SIMD4<Float>
    var normalAndAge: SIMD4<Float>
}

struct ParticleUniforms {
    var projectionMatrix: matrix_float4x4
    var viewMatrix: matrix_float4x4
    var modelMatrix: matrix_float4x4
    var viewportSize: SIMD2<Float>
    var time: Float
}
