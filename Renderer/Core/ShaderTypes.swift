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
    var animInfo: SIMD4<Float>
}

struct GlobalUniforms {
    var projectionMatrix: simd_float4x4
    var viewMatrix: simd_float4x4
    var time: Float
    var padding: SIMD3<Float>
}

struct ParticleSpriteVertex {
    var position: SIMD3<Float>
    var texCoordVec4: SIMD4<Float>
    var color: SIMD4<Float>
    var texCoordVec4C1: SIMD4<Float>
    var texCoordC2: SIMD2<Float>
}

struct ParticleRopeVertex {
    var positionVec4: SIMD4<Float>
    var texCoordVec4: SIMD4<Float>
    var texCoordVec4C1: SIMD4<Float>
    var texCoordVec4C2: SIMD4<Float>
    var texCoordVec4C3: SIMD4<Float>
    var texCoordC4: SIMD2<Float>
    var color: SIMD4<Float>
}

struct ParticleUniforms {
    var modelMatrix: simd_float4x4
    var modelMatrixInverse: simd_float4x4
    var mvpMatrix: simd_float4x4
    var mvpMatrixInverse: simd_float4x4
    var viewProjectionMatrix: simd_float4x4
    var orientationUp: SIMD3<Float>
    var orientationRight: SIMD3<Float>
    var orientationForward: SIMD3<Float>
    var viewUp: SIMD3<Float>
    var viewRight: SIMD3<Float>
    var eyePosition: SIMD3<Float>
    var renderVar0: SIMD4<Float>
    var renderVar1: SIMD4<Float>
    var overbright: Float
    var padding1: Float
    var padding2: Float
    var padding3: Float
}

struct BloomConstants {
    var threshold: Float
    var strength: Float
}

struct PuppetVertex {
    var px: Float, py: Float, pz: Float
    var pad1: Float = 0
    var u: Float, v: Float
    var j1: UInt16, j2: UInt16, j3: UInt16, j4: UInt16
    var w1: Float, w2: Float, w3: Float, w4: Float
}
