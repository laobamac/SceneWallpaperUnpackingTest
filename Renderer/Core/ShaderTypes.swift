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
    var padding: SIMD4<Float> = .zero
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
