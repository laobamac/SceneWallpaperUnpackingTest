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
    
    static func lerp(t: Float, a: Float, b: Float) -> Float {
        return a + t * (b - a)
    }
    
    static func lerpVec3(t: Float, a: SIMD3<Float>, b: SIMD3<Float>) -> SIMD3<Float> {
        return a + (b - a) * t
    }
    
    static func fadeValue(life: Float, startTime: Float, endTime: Float, startValue: Float, endValue: Float) -> Float {
        if life <= startTime { return startValue }
        if life >= endTime { return endValue }
        let t = (life - startTime) / (endTime - startTime)
        return lerp(t: t, a: startValue, b: endValue)
    }
}

struct SimplexNoise {
    private static let grad3: [SIMD3<Float>] = [
        SIMD3<Float>(1,1,0), SIMD3<Float>(-1,1,0), SIMD3<Float>(1,-1,0), SIMD3<Float>(-1,-1,0),
        SIMD3<Float>(1,0,1), SIMD3<Float>(-1,0,1), SIMD3<Float>(1,0,-1), SIMD3<Float>(-1,0,-1),
        SIMD3<Float>(0,1,1), SIMD3<Float>(0,-1,1), SIMD3<Float>(0,1,-1), SIMD3<Float>(0,-1,-1)
    ]
    
    private static let p: [Int] = [
        151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
        190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,88,237,149,56,87,174,20,
        125,136,171,168,68,175,74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,
        105,92,41,55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,200,196,
        135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,250,124,123,5,202,38,147,118,126,255,
        82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,
        153,101,155,167,43,172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,228,
        251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,
        157,184,84,204,176,115,121,50,45,127,4,150,254,138,236,205,93,222,114,67,29,24,72,243,141,128,195,
        78,66,215,61,156,180,
        151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
        190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,88,237,149,56,87,174,20,
        125,136,171,168,68,175,74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,
        105,92,41,55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,200,196,
        135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,250,124,123,5,202,38,147,118,126,255,
        82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,
        153,101,155,167,43,172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,228,
        251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,
        157,184,84,204,176,115,121,50,45,127,4,150,254,138,236,205,93,222,114,67,29,24,72,243,141,128,195,
        78,66,215,61,156,180
    ]
    
    private static func dot(_ g: SIMD3<Float>, _ x: Float, _ y: Float, _ z: Float) -> Float {
        return g.x * x + g.y * y + g.z * z
    }
    
    static func noise3D(x: Float, y: Float, z: Float) -> Float {
        let F3: Float = 1.0 / 3.0
        let G3: Float = 1.0 / 6.0
        
        let s = (x + y + z) * F3
        let i = floor(x + s)
        let j = floor(y + s)
        let k = floor(z + s)
        
        let t = (i + j + k) * G3
        let X0 = i - t
        let Y0 = j - t
        let Z0 = k - t
        
        let x0 = x - X0
        let y0 = y - Y0
        let z0 = z - Z0
        
        var i1: Int, j1: Int, k1: Int
        var i2: Int, j2: Int, k2: Int
        
        if x0 >= y0 {
            if y0 >= z0 {
                i1 = 1; j1 = 0; k1 = 0
                i2 = 1; j2 = 1; k2 = 0
            } else if x0 >= z0 {
                i1 = 1; j1 = 0; k1 = 0
                i2 = 1; j2 = 0; k2 = 1
            } else {
                i1 = 0; j1 = 0; k1 = 1
                i2 = 1; j2 = 0; k2 = 1
            }
        } else {
            if y0 < z0 {
                i1 = 0; j1 = 0; k1 = 1
                i2 = 0; j2 = 1; k2 = 1
            } else if x0 < z0 {
                i1 = 0; j1 = 1; k1 = 0
                i2 = 0; j2 = 1; k2 = 1
            } else {
                i1 = 0; j1 = 1; k1 = 0
                i2 = 1; j2 = 1; k2 = 0
            }
        }
        
        let x1 = x0 - Float(i1) + G3
        let y1 = y0 - Float(j1) + G3
        let z1 = z0 - Float(k1) + G3
        let x2 = x0 - Float(i2) + 2.0 * G3
        let y2 = y0 - Float(j2) + 2.0 * G3
        let z2 = z0 - Float(k2) + 2.0 * G3
        let x3 = x0 - 1.0 + 3.0 * G3
        let y3 = y0 - 1.0 + 3.0 * G3
        let z3 = z0 - 1.0 + 3.0 * G3
        
        let ii = Int(i) & 255
        let jj = Int(j) & 255
        let kk = Int(k) & 255
        
        var n0: Float = 0, n1: Float = 0, n2: Float = 0, n3: Float = 0
        
        var t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0
        if t0 < 0 {
            n0 = 0.0
        } else {
            t0 *= t0
            let gi0 = p[ii + p[jj + p[kk]]] % 12
            n0 = t0 * t0 * dot(grad3[gi0], x0, y0, z0)
        }
        
        var t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1
        if t1 < 0 {
            n1 = 0.0
        } else {
            t1 *= t1
            let gi1 = p[ii + i1 + p[jj + j1 + p[kk + k1]]] % 12
            n1 = t1 * t1 * dot(grad3[gi1], x1, y1, z1)
        }
        
        var t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2
        if t2 < 0 {
            n2 = 0.0
        } else {
            t2 *= t2
            let gi2 = p[ii + i2 + p[jj + j2 + p[kk + k2]]] % 12
            n2 = t2 * t2 * dot(grad3[gi2], x2, y2, z2)
        }
        
        var t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3
        if t3 < 0 {
            n3 = 0.0
        } else {
            t3 *= t3
            let gi3 = p[ii + 1 + p[jj + 1 + p[kk + 1]]] % 12
            n3 = t3 * t3 * dot(grad3[gi3], x3, y3, z3)
        }
        
        return 32.0 * (n0 + n1 + n2 + n3)
    }
    
    static func curlNoise(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let e: Float = 0.0001
        
        let dx0 = noise3D(x: p.x - e, y: p.y, z: p.z)
        let dx1 = noise3D(x: p.x + e, y: p.y, z: p.z)
        let dy0 = noise3D(x: p.x, y: p.y - e, z: p.z)
        let dy1 = noise3D(x: p.x, y: p.y + e, z: p.z)
        let dz0 = noise3D(x: p.x, y: p.y, z: p.z - e)
        let dz1 = noise3D(x: p.x, y: p.y, z: p.z + e)
        
        let x = (dy1 - dy0) - (dz1 - dz0)
        let y = (dz1 - dz0) - (dx1 - dx0)
        let z = (dx1 - dx0) - (dy1 - dy0)
        
        let scale = 1.0 / (2.0 * e)
        return SIMD3<Float>(x, y, z) * scale
    }
}
