//
//  NoiseUtils.swift
//  Renderer
//
//  Created by laobamac on 2026/2/14.
//

import Foundation
import simd

struct NoiseUtils {
    private static var p: [Int] = {
        var permutation = Array(0...255)
        permutation.shuffle()
        return permutation + permutation
    }()
    
    static func fade(_ t: Float) -> Float {
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
    
    static func lerp(_ t: Float, _ a: Float, _ b: Float) -> Float {
        return a + t * (b - a)
    }
    
    static func grad(_ hash: Int, _ x: Float, _ y: Float, _ z: Float) -> Float {
        let h = hash & 15
        let u = h < 8 ? x : y
        let v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
    }
    
    static func perlin(_ x: Float, _ y: Float, _ z: Float) -> Float {
        let X = Int(floor(x)) & 255
        let Y = Int(floor(y)) & 255
        let Z = Int(floor(z)) & 255
        
        let xf = x - floor(x)
        let yf = y - floor(y)
        let zf = z - floor(z)
        
        let u = fade(xf)
        let v = fade(yf)
        let w = fade(zf)
        
        let A = p[X] + Y
        let AA = p[A] + Z
        let AB = p[A + 1] + Z
        let B = p[X + 1] + Y
        let BA = p[B] + Z
        let BB = p[B + 1] + Z
        
        return lerp(w,
                    lerp(v,
                         lerp(u, grad(p[AA], xf, yf, zf), grad(p[BA], xf - 1, yf, zf)),
                         lerp(u, grad(p[AB], xf, yf - 1, zf), grad(p[BB], xf - 1, yf - 1, zf))),
                    lerp(v,
                         lerp(u, grad(p[AA + 1], xf, yf, zf - 1), grad(p[BA + 1], xf - 1, yf, zf - 1)),
                         lerp(u, grad(p[AB + 1], xf, yf - 1, zf - 1), grad(p[BB + 1], xf - 1, yf - 1, zf - 1))))
    }
    
    static func curlNoise(_ pos: SIMD3<Float>) -> SIMD3<Float> {
        let e: Float = 0.1
        let dx = SIMD3<Float>(e, 0, 0)
        let dy = SIMD3<Float>(0, e, 0)
        let dz = SIMD3<Float>(0, 0, e)
        
        let p_x0 = perlin(pos.x - e, pos.y, pos.z)
        let p_x1 = perlin(pos.x + e, pos.y, pos.z)
        let p_y0 = perlin(pos.x, pos.y - e, pos.z)
        let p_y1 = perlin(pos.x, pos.y + e, pos.z)
        let p_z0 = perlin(pos.x, pos.y, pos.z - e)
        let p_z1 = perlin(pos.x, pos.y, pos.z + e)
        
        let x = (p_y1 - p_y0) - (p_z1 - p_z0)
        let y = (p_z1 - p_z0) - (p_x1 - p_x0)
        let z = (p_x1 - p_x0) - (p_y1 - p_y0)
        
        return SIMD3<Float>(x, y, z) / (2.0 * e)
    }
}
