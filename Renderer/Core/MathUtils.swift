//
//  MathUtils.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import simd
import Foundation

struct Quaternion {
    var x: Float, y: Float, z: Float, w: Float

    static func fromEuler(_ euler: SIMD3<Float>) -> Quaternion {
        let cx = cos(euler.x * 0.5)
        let sx = sin(euler.x * 0.5)
        let cy = cos(euler.y * 0.5)
        let sy = sin(euler.y * 0.5)
        let cz = cos(euler.z * 0.5)
        let sz = sin(euler.z * 0.5)
        
        return Quaternion(
            x: sx * cy * cz - cx * sy * sz,
            y: cx * sy * cz + sx * cy * sz,
            z: cx * cy * sz - sx * sy * cz,
            w: cx * cy * cz + sx * sy * sz
        )
    }

    static func slerp(_ q1: Quaternion, _ q2: Quaternion, t: Float) -> Quaternion {
        var cosHalfTheta = q1.w * q2.w + q1.x * q2.x + q1.y * q2.y + q1.z * q2.z
        var q2m = q2

        if cosHalfTheta < 0 {
            q2m = Quaternion(x: -q2.x, y: -q2.y, z: -q2.z, w: -q2.w)
            cosHalfTheta = -cosHalfTheta
        }

        if abs(cosHalfTheta) >= 1.0 {
            return q1
        }

        let halfTheta = acos(cosHalfTheta)
        let sinHalfTheta = sqrt(1.0 - cosHalfTheta * cosHalfTheta)

        if abs(sinHalfTheta) < 0.001 {
            return Quaternion(
                x: q1.x * 0.5 + q2m.x * 0.5,
                y: q1.y * 0.5 + q2m.y * 0.5,
                z: q1.z * 0.5 + q2m.z * 0.5,
                w: q1.w * 0.5 + q2m.w * 0.5
            )
        }

        let ratioA = sin((1 - t) * halfTheta) / sinHalfTheta
        let ratioB = sin(t * halfTheta) / sinHalfTheta

        return Quaternion(
            x: q1.x * ratioA + q2m.x * ratioB,
            y: q1.y * ratioA + q2m.y * ratioB,
            z: q1.z * ratioA + q2m.z * ratioB,
            w: q1.w * ratioA + q2m.w * ratioB
        )
    }

    func toMatrix() -> matrix_float4x4 {
        let xx = x * x, yy = y * y, zz = z * z
        let xy = x * y, xz = x * z, xw = x * w
        let yz = y * z, yw = y * w, zw = z * w

        return matrix_float4x4(columns: (
            SIMD4<Float>(1 - 2 * (yy + zz), 2 * (xy + zw), 2 * (xz - yw), 0),
            SIMD4<Float>(2 * (xy - zw), 1 - 2 * (xx + zz), 2 * (yz + xw), 0),
            SIMD4<Float>(2 * (xz + yw), 2 * (yz - xw), 1 - 2 * (xx + yy), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }
}

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
    
    static func rotationMatrix3x3(angle: Float, axis: SIMD3<Float>) -> matrix_float3x3 {
        let normalizedAxis = simd_normalize(axis)
        let ct = cos(angle)
        let st = sin(angle)
        let ci = 1 - ct
        let x = normalizedAxis.x, y = normalizedAxis.y, z = normalizedAxis.z
        
        return matrix_float3x3(columns: (
            SIMD3<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st),
            SIMD3<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st),
            SIMD3<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci)
        ))
    }
    
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
        let ral = right + left
        let rsl = right - left
        let tab = top + bottom
        let tsb = top - bottom
        
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
