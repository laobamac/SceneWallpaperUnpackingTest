//
//  ShaderTypes.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import simd

// MARK: - Core Shader Structures (Aligned for Metal)

/// 特效参数 (对应 Shaders.metal: EffectParams)
struct EffectParams {
    var type: Int32         // 0: None, 1: Scroll, 2: WaterWave, 3: Shake, 4: FoliageSway, 5: WaterRipple
    var maskIndex: Int32    // -1 表示无
    var speed: Float
    var scale: Float
    var strength: Float
    var exponent: Float
    var direction: SIMD2<Float>
    var bounds: SIMD2<Float>
    var friction: SIMD2<Float>
}

/// 对象通用 Uniforms
struct ObjectUniforms {
    var modelMatrix: matrix_float4x4
    var alpha: Float
    var color: SIMD4<Float>
    var padding: SIMD4<Float> = .zero
}

/// 全局 Uniforms
struct GlobalUniforms {
    var projectionMatrix: matrix_float4x4
    var viewMatrix: matrix_float4x4
    var time: Float
    var padding: SIMD3<Float> = .zero
}

/// 骨骼动画顶点结构
struct PuppetVertex {
    var px: Float, py: Float, pz: Float
    var pad1: Float = 0
    var u: Float, v: Float
    var j1: UInt16, j2: UInt16, j3: UInt16, j4: UInt16 // 骨骼索引
    var w1: Float, w2: Float, w3: Float, w4: Float    // 骨骼权重
}
