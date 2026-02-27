//
//  ParticleModules.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import simd

extension ScriptableValue {
    func getFloat() -> Float {
        switch self {
        case .float(let f): return f
        case .int(let i): return Float(i)
        case .string(let s): return Float(s) ?? 0
        case .script(let v): return Float(v) ?? 0
        case .floatArray(let a): return a.first ?? 0
        case .bool(let b): return b ? 1 : 0
        case .object(_): return 0
        }
    }

    func getVec3() -> SIMD3<Float> {
        switch self {
        case .string(let s), .script(let s):
            let parts = s.components(separatedBy: " ").compactMap { Float($0) }
            if parts.count >= 3 {
                return SIMD3<Float>(parts[0], parts[1], parts[2])
            } else if parts.count == 1 {
                return SIMD3<Float>(parts[0], parts[0], parts[0])
            }
            return .zero
        case .floatArray(let a):
            if a.count >= 3 { return SIMD3<Float>(a[0], a[1], a[2]) }
            return .zero
        case .float(let f):
            return SIMD3<Float>(f, f, f)
        case .int(let i):
            let f = Float(i)
            return SIMD3<Float>(f, f, f)
        case .bool(let b):
            let f: Float = b ? 1 : 0
            return SIMD3<Float>(f, f, f)
        case .object(_):
            return .zero
        }
    }
}
