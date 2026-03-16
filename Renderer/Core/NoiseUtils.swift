//
//  NoiseUtils.swift
//  Renderer
//
//  Created by laobamac on 2026/3/17.
//

import Foundation
import simd

class NoiseUtils {
    
    private static let grad3: [simd_float3] = [
        simd_float3(1,1,0), simd_float3(-1,1,0), simd_float3(1,-1,0), simd_float3(-1,-1,0),
        simd_float3(1,0,1), simd_float3(-1,0,1), simd_float3(1,0,-1), simd_float3(-1,0,-1),
        simd_float3(0,1,1), simd_float3(0,-1,1), simd_float3(0,1,-1), simd_float3(0,-1,-1)
    ]
    
    private static let p: [Int] = [
        151,160,137,91,90,15,
        131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
        190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
        88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
        77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
        102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
        135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
        5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
        223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
        129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
        251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
        49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
        138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
    ]
    
    private static var perm: [Int] = []
    private static var permMod12: [Int] = []
    
    static func initialize() {
        if perm.isEmpty {
            perm = [Int](repeating: 0, count: 512)
            permMod12 = [Int](repeating: 0, count: 512)
            for i in 0..<512 {
                perm[i] = p[i & 255]
                permMod12[i] = perm[i] % 12
            }
        }
    }
    
    private static func fastFloor(_ x: Float) -> Int {
        return x > 0 ? Int(x) : Int(x) - 1
    }
    
    private static func dot(_ g: simd_float3, _ x: Float, _ y: Float, _ z: Float) -> Float {
        return g.x * x + g.y * y + g.z * z
    }
    
    static func snoise(_ xin: Float, _ yin: Float, _ zin: Float) -> Float {
        initialize()
        var n0: Float = 0.0, n1: Float = 0.0, n2: Float = 0.0, n3: Float = 0.0
        let F3: Float = 1.0 / 3.0
        let s = (xin + yin + zin) * F3
        let i = fastFloor(xin + s)
        let j = fastFloor(yin + s)
        let k = fastFloor(zin + s)
        
        let G3: Float = 1.0 / 6.0
        let t = Float(i + j + k) * G3
        let X0 = Float(i) - t
        let Y0 = Float(j) - t
        let Z0 = Float(k) - t
        let x0 = xin - X0
        let y0 = yin - Y0
        let z0 = zin - Z0
        
        var i1: Int, j1: Int, k1: Int
        var i2: Int, j2: Int, k2: Int
        
        if x0 >= y0 {
            if y0 >= z0 {
                i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0
            } else if x0 >= z0 {
                i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1
            } else {
                i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1
            }
        } else {
            if y0 < z0 {
                i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1
            } else if x0 < z0 {
                i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1
            } else {
                i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0
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
        
        let ii = i & 255
        let jj = j & 255
        let kk = k & 255
        
        var t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0
        if t0 < 0 { n0 = 0.0 } else {
            t0 *= t0
            let gi0 = permMod12[ii + perm[jj + perm[kk]]]
            n0 = t0 * t0 * dot(grad3[gi0], x0, y0, z0)
        }
        
        var t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1
        if t1 < 0 { n1 = 0.0 } else {
            t1 *= t1
            let gi1 = permMod12[ii + i1 + perm[jj + j1 + perm[kk + k1]]]
            n1 = t1 * t1 * dot(grad3[gi1], x1, y1, z1)
        }
        
        var t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2
        if t2 < 0 { n2 = 0.0 } else {
            t2 *= t2
            let gi2 = permMod12[ii + i2 + perm[jj + j2 + perm[kk + k2]]]
            n2 = t2 * t2 * dot(grad3[gi2], x2, y2, z2)
        }
        
        var t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3
        if t3 < 0 { n3 = 0.0 } else {
            t3 *= t3
            let gi3 = permMod12[ii + 1 + perm[jj + 1 + perm[kk + 1]]]
            n3 = t3 * t3 * dot(grad3[gi3], x3, y3, z3)
        }
        
        return 32.0 * (n0 + n1 + n2 + n3)
    }
    
    static func snoiseVec3(_ p: simd_float3) -> simd_float3 {
        return simd_float3(
            snoise(p.x, p.y, p.z),
            snoise(p.x + 100.0, p.y + 100.0, p.z + 100.0),
            snoise(p.x + 200.0, p.y + 200.0, p.z + 200.0)
        )
    }
    
    static func curlNoise(_ p: simd_float3) -> simd_float3 {
        let e: Float = 1e-4
        let dx = simd_float3(e, 0.0, 0.0)
        let dy = simd_float3(0.0, e, 0.0)
        let dz = simd_float3(0.0, 0.0, e)
        
        let p_x0 = snoiseVec3(p - dx)
        let p_x1 = snoiseVec3(p + dx)
        let p_y0 = snoiseVec3(p - dy)
        let p_y1 = snoiseVec3(p + dy)
        let p_z0 = snoiseVec3(p - dz)
        let p_z1 = snoiseVec3(p + dz)
        
        let x = p_y1.z - p_y0.z - p_z1.y + p_z0.y
        let y = p_z1.x - p_z0.x - p_x1.z + p_x0.z
        let z = p_x1.y - p_x0.y - p_y1.x + p_y0.x
        
        let divisor = 2.0 * e
        return simd_float3(x / divisor, y / divisor, z / divisor)
    }
}
