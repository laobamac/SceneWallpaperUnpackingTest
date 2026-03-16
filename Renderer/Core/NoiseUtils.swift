//
//  NoiseUtils.swift
//  Renderer
//
//  Created by laobamac on 2026/3/16.
//

import Foundation
import simd

public enum NoiseUtils {
    
    private static let PERLIN_PERM: [Int] = [
        151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37,
        240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177,
        33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146,
        158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25,
        63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100,
        109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206,
        59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153,
        101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246,
        97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192,
        214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114,
        67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
        151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37,
        240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177,
        33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146,
        158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25,
        63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100,
        109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206,
        59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153,
        101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246,
        97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192,
        214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114,
        67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180
    ]

    @inline(__always)
    public static func perlinGrad(hash: Int, x: Double, y: Double, z: Double) -> Double {
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

    @inline(__always)
    public static func perlinEase(t: Double) -> Double {
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
    }

    @inline(__always)
    public static func lerpDouble(t: Double, a: Double, b: Double) -> Double {
        return a + t * (b - a)
    }

    @inline(__always)
    public static func perlinNoise(x: Double, y: Double, z: Double) -> Double {
        let X = Int(floor(x)) & 255
        let Y = Int(floor(y)) & 255
        let Z = Int(floor(z)) & 255

        let fx = x - floor(x)
        let fy = y - floor(y)
        let fz = z - floor(z)

        let u = perlinEase(t: fx)
        let v = perlinEase(t: fy)
        let w = perlinEase(t: fz)

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
                a: lerpDouble(t: u, a: perlinGrad(hash: PERLIN_PERM[AA], x: fx, y: fy, z: fz), b: perlinGrad(hash: PERLIN_PERM[BA], x: fx - 1, y: fy, z: fz)),
                b: lerpDouble(t: u, a: perlinGrad(hash: PERLIN_PERM[AB], x: fx, y: fy - 1, z: fz), b: perlinGrad(hash: PERLIN_PERM[BB], x: fx - 1, y: fy - 1, z: fz))
            ),
            b: lerpDouble(
                t: v,
                a: lerpDouble(t: u, a: perlinGrad(hash: PERLIN_PERM[AA + 1], x: fx, y: fy, z: fz - 1), b: perlinGrad(hash: PERLIN_PERM[BA + 1], x: fx - 1, y: fy, z: fz - 1)),
                b: lerpDouble(t: u, a: perlinGrad(hash: PERLIN_PERM[AB + 1], x: fx, y: fy - 1, z: fz - 1), b: perlinGrad(hash: PERLIN_PERM[BB + 1], x: fx - 1, y: fy - 1, z: fz - 1))
            )
        )
    }

    @inline(__always)
    public static func perlinNoiseVec3(p: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            Float(perlinNoise(x: Double(p.x), y: Double(p.y), z: Double(p.z))),
            Float(perlinNoise(x: Double(p.x) + 89.2, y: Double(p.y) + 33.1, z: Double(p.z) + 57.3)),
            Float(perlinNoise(x: Double(p.x) + 100.3, y: Double(p.y) + 120.1, z: Double(p.z) + 142.2))
        )
    }

    @inline(__always)
    public static func curlNoise(p: SIMD3<Float>) -> SIMD3<Float> {
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
}
