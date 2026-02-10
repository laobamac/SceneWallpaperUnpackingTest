//
//  ParticleMath.swift
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

import simd
import Foundation

struct ParticleMath {
    static func randomFloat() -> Float {
        return Float.random(in: 0.0...1.0)
    }
    
    static func randomFloat(min: Float, max: Float) -> Float {
        if min == max { return min }
        if min > max { return Float.random(in: max...min) }
        return Float.random(in: min...max)
    }
    
    static func lerp(_ v0: Float, _ v1: Float, _ t: Float) -> Float {
        return v0 + t * (v1 - v0)
    }
    
    static func lerp(_ v0: Double, _ v1: Double, _ t: Double) -> Double {
        return v0 + t * (v1 - v0)
    }
    
    static func genSphereSurfaceNormal() -> SIMD3<Float> {
        let u = Float.random(in: 0...1)
        let v = Float.random(in: 0...1)
        let theta = 2 * Float.pi * u
        let phi = acos(2 * v - 1)
        let x = sin(phi) * cos(theta)
        let y = sin(phi) * sin(theta)
        let z = cos(phi)
        return SIMD3<Float>(x, y, z)
    }
    
    private static let grad3: [SIMD3<Float>] = [
        SIMD3(1,1,0), SIMD3(-1,1,0), SIMD3(1,-1,0), SIMD3(-1,-1,0),
        SIMD3(1,0,1), SIMD3(-1,0,1), SIMD3(1,0,-1), SIMD3(-1,0,-1),
        SIMD3(0,1,1), SIMD3(0,-1,1), SIMD3(0,1,-1), SIMD3(0,-1,-1)
    ]
    
    private static let p: [Int] = {
        var p = Array(0...255)
        p.shuffle()
        return p + p
    }()
    
    private static func fastFloor(_ x: Float) -> Int {
        return x > 0 ? Int(x) : Int(x) - 1
    }
    
    private static func dot(_ g: SIMD3<Float>, _ x: Float, _ y: Float, _ z: Float) -> Float {
        return g.x * x + g.y * y + g.z * z
    }
    
    static func simplexNoise(x: Float, y: Float, z: Float) -> Float {
        let F3: Float = 1.0/3.0
        let G3: Float = 1.0/6.0
        let s = (x+y+z) * F3
        let i = fastFloor(x+s)
        let j = fastFloor(y+s)
        let k = fastFloor(z+s)
        let t = Float(i+j+k) * G3
        let X0 = Float(i) - t
        let Y0 = Float(j) - t
        let Z0 = Float(k) - t
        let x0 = x - X0
        let y0 = y - Y0
        let z0 = z - Z0
        
        var i1, j1, k1, i2, j2, k2: Int
        if x0 >= y0 {
            if y0 >= z0 { i1=1; j1=0; k1=0; i2=1; j2=1; k2=0 }
            else if x0 >= z0 { i1=1; j1=0; k1=0; i2=1; j2=0; k2=1 }
            else { i1=0; j1=0; k1=1; i2=1; j2=0; k2=1 }
        } else {
            if y0 < z0 { i1=0; j1=0; k1=1; i2=0; j2=1; k2=1 }
            else if x0 < z0 { i1=0; j1=1; k1=0; i2=0; j2=1; k2=1 }
            else { i1=0; j1=1; k1=0; i2=1; j2=1; k2=0 }
        }
        
        let x1 = x0 - Float(i1) + G3
        let y1 = y0 - Float(j1) + G3
        let z1 = z0 - Float(k1) + G3
        let x2 = x0 - Float(i2) + 2.0*G3
        let y2 = y0 - Float(j2) + 2.0*G3
        let z2 = z0 - Float(k2) + 2.0*G3
        let x3 = x0 - 1.0 + 3.0*G3
        let y3 = y0 - 1.0 + 3.0*G3
        let z3 = z0 - 1.0 + 3.0*G3
        
        let ii = i & 255
        let jj = j & 255
        let kk = k & 255
        
        var n0: Float = 0, n1: Float = 0, n2: Float = 0, n3: Float = 0
        
        var t0 = 0.6 - x0*x0 - y0*y0 - z0*z0
        if t0 < 0 { n0 = 0.0 }
        else {
            t0 *= t0
            n0 = t0 * t0 * dot(grad3[p[ii+p[jj+p[kk]]] % 12], x0, y0, z0)
        }
        
        var t1 = 0.6 - x1*x1 - y1*y1 - z1*z1
        if t1 < 0 { n1 = 0.0 }
        else {
            t1 *= t1
            n1 = t1 * t1 * dot(grad3[p[ii+i1+p[jj+j1+p[kk+k1]]] % 12], x1, y1, z1)
        }
        
        var t2 = 0.6 - x2*x2 - y2*y2 - z2*z2
        if t2 < 0 { n2 = 0.0 }
        else {
            t2 *= t2
            n2 = t2 * t2 * dot(grad3[p[ii+i2+p[jj+j2+p[kk+k2]]] % 12], x2, y2, z2)
        }
        
        var t3 = 0.6 - x3*x3 - y3*y3 - z3*z3
        if t3 < 0 { n3 = 0.0 }
        else {
            t3 *= t3
            n3 = t3 * t3 * dot(grad3[p[ii+1+p[jj+1+p[kk+1]]] % 12], x3, y3, z3)
        }
        
        return 32.0 * (n0 + n1 + n2 + n3)
    }
    
    static func curlNoise(pos: SIMD3<Double>) -> SIMD3<Float> {
        let p = SIMD3<Float>(Float(pos.x), Float(pos.y), Float(pos.z))
        let e: Float = 0.1
        let dx = SIMD3<Float>(e, 0, 0)
        let dy = SIMD3<Float>(0, e, 0)
        let dz = SIMD3<Float>(0, 0, e)
        
        let n1 = simplexNoise(x: p.x, y: p.y + e, z: p.z)
        let n2 = simplexNoise(x: p.x, y: p.y - e, z: p.z)
        let n3 = simplexNoise(x: p.x, y: p.y, z: p.z + e)
        let n4 = simplexNoise(x: p.x, y: p.y, z: p.z - e)
        let n5 = simplexNoise(x: p.x + e, y: p.y, z: p.z)
        let n6 = simplexNoise(x: p.x - e, y: p.y, z: p.z)
        
        let x = n1 - n2 - (n3 - n4)
        let y = n3 - n4 - (n5 - n6)
        let z = n5 - n6 - (n1 - n2)
        
        return SIMD3<Float>(x, y, z) / (2 * e)
    }
}
