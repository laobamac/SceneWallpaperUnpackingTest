//
//  DynamicValueEvaluator.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import simd

class DynamicValueEvaluator {
    var time: Float = 0.0
    var pointerPosition: simd_float2 = simd_float2(0, 0)
    var resolution: simd_float2 = simd_float2(1920, 1080)

    func update(deltaTime: Float) {
        time += deltaTime
    }

    func evaluateUniforms(config: [String: UniformConfig]?) -> [String: [Float]] {
        var evaluated: [String: [Float]] = [:]
        
        evaluated["g_Time"] = [time]
        evaluated["g_PointerPosition"] = [pointerPosition.x, pointerPosition.y]
        evaluated["g_Resolution"] = [resolution.x, resolution.y]

        guard let config = config else { return evaluated }

        for (key, uniform) in config {
            if let val = uniform.value?.value as? Double {
                evaluated[key] = [Float(val)]
            } else if let valArray = uniform.value?.value as? [Double] {
                evaluated[key] = valArray.map { Float($0) }
            }
        }
        
        return evaluated
    }
}
