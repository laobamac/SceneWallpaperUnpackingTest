//
//  ParticleMath.swift
//  Renderer
//
//  Created by laobamac on 2026/3/19.
//

import Foundation
import simd

enum ParticleMath {

    static func lerp<T: FloatingPoint>(_ t: T, _ a: T, _ b: T) -> T {
        return a + t * (b - a)
    }

    static func random(min: Float, max: Float) -> Float {
        if min == max { return min }
        return Float.random(in: min...max)
    }

    static func random(min: Double, max: Double) -> Double {
        if min == max { return min }
        return Double.random(in: min...max)
    }

    static func dragForce(velocity: SIMD3<Double>, drag: Float) -> SIMD3<Double>
    {
        let speed = length(velocity)
        if speed < 1e-5 {
            return SIMD3<Double>(0, 0, 0)
        }
        let dragMag = Double(drag) * speed * speed
        let dir = normalize(velocity)
        return -dir * dragMag
    }

    static func rotate(vector: SIMD3<Float>, angle: Float, axis: SIMD3<Float>)
        -> SIMD3<Float>
    {
        let normalizedAxis = normalize(axis)
        if length(normalizedAxis) < 0.99 { return vector }
        let q = simd_quatf(angle: angle, axis: normalizedAxis)
        return q.act(vector)
    }

    static func curlNoise(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let e: Double = 1e-4
        let dx = SIMD3<Double>(e, 0.0, 0.0)
        let dy = SIMD3<Double>(0.0, e, 0.0)
        let dz = SIMD3<Double>(0.0, 0.0, e)

        let x =
            (noise3D(p + dy).z - noise3D(p - dy).z)
            - (noise3D(p + dz).y - noise3D(p - dz).y)
        let y =
            (noise3D(p + dz).x - noise3D(p - dz).x)
            - (noise3D(p + dx).z - noise3D(p - dx).z)
        let z =
            (noise3D(p + dx).y - noise3D(p - dx).y)
            - (noise3D(p + dy).x - noise3D(p - dy).x)

        return SIMD3<Double>(x, y, z) / (2.0 * e)
    }

    private static func noise3D(_ p: SIMD3<Double>) -> SIMD3<Double> {
        return SIMD3<Double>(
            snoise(SIMD3<Double>(p.x, p.y, p.z)),
            snoise(SIMD3<Double>(p.x + 43.19, p.y + 13.57, p.z + 87.13)),
            snoise(SIMD3<Double>(p.x - 95.43, p.y - 68.21, p.z - 12.34))
        )
    }

    private static func snoise(_ v: SIMD3<Double>) -> Double {
        let C = SIMD2<Double>(1.0 / 6.0, 1.0 / 3.0)
        let D = SIMD4<Double>(0.0, 0.5, 1.0, 2.0)

        var i = floor(v + dot(v, SIMD3<Double>(repeating: C.y)))
        let x0 = v - i + dot(i, SIMD3<Double>(repeating: C.x))

        let g = stepFunc(SIMD3<Double>(x0.y, x0.z, x0.x), x0)
        let l = SIMD3<Double>(repeating: 1.0) - g

        let l_zxy = SIMD3<Double>(l.z, l.x, l.y)
        let i1 = min(g, l_zxy)
        let i2 = max(g, l_zxy)

        let x1 = x0 - i1 + SIMD3<Double>(repeating: C.x)
        let x2 = x0 - i2 + SIMD3<Double>(repeating: C.y)
        let x3 = x0 - SIMD3<Double>(repeating: 0.5)

        i = mod289(i)

        let p_z =
            SIMD4<Double>(repeating: i.z) + SIMD4<Double>(0.0, i1.z, i2.z, 1.0)
        let p_y =
            SIMD4<Double>(repeating: i.y) + SIMD4<Double>(0.0, i1.y, i2.y, 1.0)
        let p_x =
            SIMD4<Double>(repeating: i.x) + SIMD4<Double>(0.0, i1.x, i2.x, 1.0)

        let p = permute(permute(permute(p_z) + p_y) + p_x)

        let n_: Double = 0.142857142857
        let D_wyz = SIMD3<Double>(D.w, D.y, D.z)
        let D_xzx = SIMD3<Double>(D.x, D.z, D.x)
        let ns = n_ * D_wyz - D_xzx

        let j = p - SIMD4<Double>(repeating: 49.0) * floor(p * ns.z * ns.z)

        let x_ = floor(j * ns.z)
        let y_ = floor(j - SIMD4<Double>(repeating: 7.0) * x_)

        let x = x_ * ns.x + SIMD4<Double>(repeating: ns.y)
        let y = y_ * ns.x + SIMD4<Double>(repeating: ns.y)
        let h = SIMD4<Double>(repeating: 1.0) - abs(x) - abs(y)

        let b0 = SIMD4<Double>(x.x, x.y, y.x, y.y)
        let b1 = SIMD4<Double>(x.z, x.w, y.z, y.w)

        let s0 = floor(b0) * 2.0 + SIMD4<Double>(repeating: 1.0)
        let s1 = floor(b1) * 2.0 + SIMD4<Double>(repeating: 1.0)

        let sh = -stepFunc(h, SIMD4<Double>(repeating: 0.0))

        let a0 =
            SIMD4<Double>(b0.x, b0.z, b0.y, b0.w) + SIMD4<Double>(
                s0.x,
                s0.z,
                s0.y,
                s0.w
            ) * SIMD4<Double>(sh.x, sh.x, sh.y, sh.y)
        let a1 =
            SIMD4<Double>(b1.x, b1.z, b1.y, b1.w) + SIMD4<Double>(
                s1.x,
                s1.z,
                s1.y,
                s1.w
            ) * SIMD4<Double>(sh.z, sh.z, sh.w, sh.w)

        var p0 = SIMD3<Double>(a0.x, a0.y, h.x)
        var p1 = SIMD3<Double>(a0.z, a0.w, h.y)
        var p2 = SIMD3<Double>(a1.x, a1.y, h.z)
        var p3 = SIMD3<Double>(a1.z, a1.w, h.w)

        let norm = taylorInvSqrt(
            SIMD4<Double>(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3))
        )
        p0 *= norm.x
        p1 *= norm.y
        p2 *= norm.z
        p3 *= norm.w

        var m = max(
            SIMD4<Double>(repeating: 0.6)
                - SIMD4<Double>(
                    dot(x0, x0),
                    dot(x1, x1),
                    dot(x2, x2),
                    dot(x3, x3)
                ),
            SIMD4<Double>(repeating: 0.0)
        )
        m = m * m
        return 42.0
            * dot(
                m * m,
                SIMD4<Double>(
                    dot(p0, x0),
                    dot(p1, x1),
                    dot(p2, x2),
                    dot(p3, x3)
                )
            )
    }

    private static func mod289(_ x: SIMD3<Double>) -> SIMD3<Double> {
        return x - floor(x * (1.0 / 289.0)) * SIMD3<Double>(repeating: 289.0)
    }

    private static func mod289(_ x: SIMD4<Double>) -> SIMD4<Double> {
        return x - floor(x * (1.0 / 289.0)) * SIMD4<Double>(repeating: 289.0)
    }

    private static func permute(_ x: SIMD4<Double>) -> SIMD4<Double> {
        return mod289(((x * 34.0) + SIMD4<Double>(repeating: 1.0)) * x)
    }

    private static func taylorInvSqrt(_ r: SIMD4<Double>) -> SIMD4<Double> {
        return SIMD4<Double>(repeating: 1.79284291400159) - r * 0.85373472095314
    }

    private static func stepFunc(_ edge: SIMD3<Double>, _ x: SIMD3<Double>)
        -> SIMD3<Double>
    {
        return SIMD3<Double>(
            x.x < edge.x ? 0.0 : 1.0,
            x.y < edge.y ? 0.0 : 1.0,
            x.z < edge.z ? 0.0 : 1.0
        )
    }

    private static func stepFunc(_ edge: SIMD4<Double>, _ x: SIMD4<Double>)
        -> SIMD4<Double>
    {
        return SIMD4<Double>(
            x.x < edge.x ? 0.0 : 1.0,
            x.y < edge.y ? 0.0 : 1.0,
            x.z < edge.z ? 0.0 : 1.0,
            x.w < edge.w ? 0.0 : 1.0
        )
    }
}
