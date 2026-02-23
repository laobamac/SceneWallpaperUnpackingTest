//
//  ParticleMath.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import simd

struct ParticleMath {
    static let PERLIN_PERM: [Int] = [
        151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
        140, 36, 103, 30, 69, 142, 8, 99, 37,
        240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94,
        252, 219, 203, 117, 35, 11, 32, 57, 177,
        33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165,
        71, 134, 139, 48, 27, 166, 77, 146,
        158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55,
        46, 245, 40, 244, 102, 143, 54, 65, 25,
        63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196,
        135, 130, 116, 188, 159, 86, 164, 100,
        109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147,
        118, 126, 255, 82, 85, 212, 207, 206,
        59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248,
        152, 2, 44, 154, 163, 70, 221, 153,
        101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113,
        224, 232, 178, 185, 112, 104, 218, 246,
        97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81,
        51, 145, 235, 249, 14, 239, 107, 49, 192,
        214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127,
        4, 150, 254, 138, 236, 205, 93, 222, 114,
        67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
        151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
        140, 36, 103, 30, 69, 142, 8, 99, 37,
        240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94,
        252, 219, 203, 117, 35, 11, 32, 57, 177,
        33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165,
        71, 134, 139, 48, 27, 166, 77, 146,
        158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55,
        46, 245, 40, 244, 102, 143, 54, 65, 25,
        63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196,
        135, 130, 116, 188, 159, 86, 164, 100,
        109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147,
        118, 126, 255, 82, 85, 212, 207, 206,
        59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248,
        152, 2, 44, 154, 163, 70, 221, 153,
        101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113,
        224, 232, 178, 185, 112, 104, 218, 246,
        97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81,
        51, 145, 235, 249, 14, 239, 107, 49, 192,
        214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127,
        4, 150, 254, 138, 236, 205, 93, 222, 114,
        67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
    ]

    static func perlinGrad(hash: Int, x: Double, y: Double, z: Double) -> Double
    {
        switch hash & 0xF {
        case 0x0: return x + y
        case 0x1: return -x + y
        case 0x2: return x - y
        case 0x3: return -x - y
        case 0x4: return x + z
        case 0x5: return -x + z
        case 0x6: return x - z
        case 0x7: return -x - z
        case 0x8: return y + z
        case 0x9: return -y + z
        case 0xA: return y - z
        case 0xB: return -y - z
        case 0xC: return y + x
        case 0xD: return -y + z
        case 0xE: return y - x
        case 0xF: return -y - z
        default: return 0
        }
    }

    static func perlinEase(t: Double) -> Double {
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
    }

    static func lerpDouble(t: Double, a: Double, b: Double) -> Double {
        return a + t * (b - a)
    }

    static func perlinNoise(x: Double, y: Double, z: Double) -> Double {
        let X = Int(floor(x)) & 255
        let Y = Int(floor(y)) & 255
        let Z = Int(floor(z)) & 255

        let xf = x - floor(x)
        let yf = y - floor(y)
        let zf = z - floor(z)

        let u = perlinEase(t: xf)
        let v = perlinEase(t: yf)
        let w = perlinEase(t: zf)

        let A = PERLIN_PERM[X] + Y
        let AA = PERLIN_PERM[A] + Z
        let AB = PERLIN_PERM[A + 1] + Z
        let B = PERLIN_PERM[X + 1] + Y
        let BA = PERLIN_PERM[B] + Z
        let BB = PERLIN_PERM[B + 1] + Z

        return lerpDouble(
            t: w,
            a: lerpDouble(
                t: v,
                a: lerpDouble(
                    t: u,
                    a: perlinGrad(hash: PERLIN_PERM[AA], x: xf, y: yf, z: zf),
                    b: perlinGrad(
                        hash: PERLIN_PERM[BA],
                        x: xf - 1,
                        y: yf,
                        z: zf
                    )
                ),
                b: lerpDouble(
                    t: u,
                    a: perlinGrad(
                        hash: PERLIN_PERM[AB],
                        x: xf,
                        y: yf - 1,
                        z: zf
                    ),
                    b: perlinGrad(
                        hash: PERLIN_PERM[BB],
                        x: xf - 1,
                        y: yf - 1,
                        z: zf
                    )
                )
            ),
            b: lerpDouble(
                t: v,
                a: lerpDouble(
                    t: u,
                    a: perlinGrad(
                        hash: PERLIN_PERM[AA + 1],
                        x: xf,
                        y: yf,
                        z: zf - 1
                    ),
                    b: perlinGrad(
                        hash: PERLIN_PERM[BA + 1],
                        x: xf - 1,
                        y: yf,
                        z: zf - 1
                    )
                ),
                b: lerpDouble(
                    t: u,
                    a: perlinGrad(
                        hash: PERLIN_PERM[AB + 1],
                        x: xf,
                        y: yf - 1,
                        z: zf - 1
                    ),
                    b: perlinGrad(
                        hash: PERLIN_PERM[BB + 1],
                        x: xf - 1,
                        y: yf - 1,
                        z: zf - 1
                    )
                )
            )
        )
    }

    static func perlinNoiseVec3(p: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            Float(perlinNoise(x: Double(p.x), y: Double(p.y), z: Double(p.z))),
            Float(
                perlinNoise(
                    x: Double(p.x) + 89.2,
                    y: Double(p.y) + 33.1,
                    z: Double(p.z) + 57.3
                )
            ),
            Float(
                perlinNoise(
                    x: Double(p.x) + 100.3,
                    y: Double(p.y) + 120.1,
                    z: Double(p.z) + 142.2
                )
            )
        )
    }

    static func curlNoise(p: SIMD3<Float>) -> SIMD3<Float> {
        let e: Float = 1e-4

        let dx = SIMD3<Float>(e, 0, 0)
        let dy = SIMD3<Float>(0, e, 0)
        let dz = SIMD3<Float>(0, 0, e)

        let x0 = perlinNoiseVec3(p: p - dx)
        let x1 = perlinNoiseVec3(p: p + dx)
        let y0 = perlinNoiseVec3(p: p - dy)
        let y1 = perlinNoiseVec3(p: p + dy)
        let z0 = perlinNoiseVec3(p: p - dz)
        let z1 = perlinNoiseVec3(p: p + dz)

        let x = (y1.z - y0.z) - (z1.y - z0.y)
        let y = (z1.x - z0.x) - (x1.z - x0.z)
        let z = (x1.y - x0.y) - (y1.x - y0.x)

        return SIMD3<Float>(x, y, z) / (2.0 * e)
    }

    static func randomFloat(min: Float, max: Float) -> Float {
        if max < min {
            return Float.random(in: max...min)
        }
        if max == min {
            return min
        }
        return Float.random(in: min...max)
    }

    static func randomVec3(min: SIMD3<Float>, max: SIMD3<Float>) -> SIMD3<Float>
    {
        return SIMD3<Float>(
            randomFloat(min: min.x, max: max.x),
            randomFloat(min: min.y, max: max.y),
            randomFloat(min: min.z, max: max.z)
        )
    }

    static func lerp(t: Float, a: Float, b: Float) -> Float {
        return a + t * (b - a)
    }

    static func fadeValue(
        life: Float,
        startTime: Float,
        endTime: Float,
        startValue: Float,
        endValue: Float
    ) -> Float {
        if life <= startTime { return startValue }
        if life >= endTime { return endValue }
        let t = (life - startTime) / (endTime - startTime)
        return lerp(t: t, a: startValue, b: endValue)
    }

    static func rotationMatrix3x3(angle: Float, axis: SIMD3<Float>)
        -> matrix_float3x3
    {
        let c = cos(angle)
        let s = sin(angle)
        let t = 1.0 - c
        let x = axis.x
        let y = axis.y
        let z = axis.z
        return matrix_float3x3(
            SIMD3<Float>(t * x * x + c, t * x * y + z * s, t * x * z - y * s),
            SIMD3<Float>(t * x * y - z * s, t * y * y + c, t * y * z + x * s),
            SIMD3<Float>(t * x * z + y * s, t * y * z - x * s, t * z * z + c)
        )
    }
}
