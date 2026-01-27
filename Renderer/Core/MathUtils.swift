//
//  MathUtils.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import simd

struct Matrix4x4 {
    static func translation(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(x, y, z, 1)
        return matrix
    }
    
    static func scale(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.0.x = x
        matrix.columns.1.y = y
        matrix.columns.2.z = z
        return matrix
    }
    
    static func rotation(angle: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
        let normalizedAxis = simd_normalize(axis)
        let ct = cos(angle)
        let st = sin(angle)
        let ci = 1 - ct
        let x = normalizedAxis.x, y = normalizedAxis.y, z = normalizedAxis.z
        
        return matrix_float4x4(columns: (
            SIMD4<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
            SIMD4<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0),
            SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }
    
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
        let ral = right + left
        let rsl = right - left
        let tab = top + bottom
        let tsb = top - bottom
        let fan = far + near
        let fsn = far - near
        
        return matrix_float4x4(columns: (
            SIMD4<Float>(2.0 / rsl, 0, 0, 0),
            SIMD4<Float>(0, 2.0 / tsb, 0, 0),
            SIMD4<Float>(0, 0, -2.0 / fsn, 0),
            SIMD4<Float>(-ral / rsl, -tab / tsb, -fan / fsn, 1)
        ))
    }
    
    static func fromEuler(_ euler: SIMD3<Float>) -> matrix_float4x4 {
        let rotationX = rotation(angle: euler.x, axis: SIMD3<Float>(1, 0, 0))
        let rotationY = rotation(angle: euler.y, axis: SIMD3<Float>(0, 1, 0))
        let rotationZ = rotation(angle: euler.z, axis: SIMD3<Float>(0, 0, 1))
        return rotationZ * rotationY * rotationX
    }
}
