//
//  MathUtils.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import simd
import Foundation

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
        
        // Metal standard orthographic projection (Z maps to [0, 1])
        return matrix_float4x4(columns: (
            SIMD4<Float>(2.0 / rsl, 0, 0, 0),
            SIMD4<Float>(0, 2.0 / tsb, 0, 0),
            SIMD4<Float>(0, 0, 1.0 / (far - near), 0),
            SIMD4<Float>(-ral / rsl, -tab / tsb, -near / (far - near), 1)
        ))
    }
    
    static func fromEuler(_ euler: SIMD3<Float>) -> matrix_float4x4 {
        let rotationX = rotation(angle: euler.x, axis: SIMD3<Float>(1, 0, 0))
        let rotationY = rotation(angle: euler.y, axis: SIMD3<Float>(0, 1, 0))
        let rotationZ = rotation(angle: euler.z, axis: SIMD3<Float>(0, 0, 1))
        return rotationZ * rotationY * rotationX
    }
}

struct MathHelper {
    static func safeRandomFloat(min: Float, max: Float) -> Float {
        if min == max { return min }
        if min > max { return Float.random(in: max...min) }
        return Float.random(in: min...max)
    }
    
    static func randomVec3(min: SIMD3<Float>, max: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            safeRandomFloat(min: min.x, max: max.x),
            safeRandomFloat(min: min.y, max: max.y),
            safeRandomFloat(min: min.z, max: max.z)
        )
    }
    
    static func parseVec3(_ str: String) -> SIMD3<Float> {
        let parts = str.components(separatedBy: " ").compactMap { Float($0) }
        if parts.count >= 3 { return SIMD3<Float>(parts[0], parts[1], parts[2]) }
        if parts.count == 1 { return SIMD3<Float>(parts[0], parts[0], parts[0]) }
        return SIMD3<Float>(0, 0, 0)
    }
    
    static func parseVec4(_ str: String) -> SIMD4<Float> {
        let parts = str.components(separatedBy: " ").compactMap { Float($0) }
        if parts.count >= 3 {
            let a = parts.count > 3 ? parts[3] : 255.0
            return SIMD4<Float>(parts[0], parts[1], parts[2], a)
        }
        return SIMD4<Float>(255, 255, 255, 255)
    }
}
