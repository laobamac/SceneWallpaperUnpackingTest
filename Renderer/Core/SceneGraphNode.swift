//
//  SceneGraphNode.swift
//  Renderer
//
//  Created by laobamac on 2026/3/8.
//

import Foundation
import simd

class SceneGraphNode {
    let id: Int
    var parent: SceneGraphNode?
    var children: [SceneGraphNode] = []
    
    var localPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var localScale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    var localAngles: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    var globalTransform: matrix_float4x4 {
        let translation = matrix_float4x4(translation: localPosition)
        let rotationZ = matrix_float4x4(rotationZ: localAngles.z)
        let scale = matrix_float4x4(scale: localScale)
        
        let localTransform = matrix_multiply(matrix_multiply(translation, rotationZ), scale)
        
        if let parent = parent {
            return matrix_multiply(parent.globalTransform, localTransform)
        } else {
            return localTransform
        }
    }
    
    var globalPosition: SIMD3<Float> {
        let transform = globalTransform
        return SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    init(id: Int) {
        self.id = id
    }
    
    func addChild(_ node: SceneGraphNode) {
        children.append(node)
        node.parent = self
    }
}

extension matrix_float4x4 {
    init(translation t: SIMD3<Float>) {
        self.init(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        )
    }
    
    init(scale s: SIMD3<Float>) {
        self.init(
            SIMD4<Float>(s.x, 0, 0, 0),
            SIMD4<Float>(0, s.y, 0, 0),
            SIMD4<Float>(0, 0, s.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
    
    init(rotationZ angle: Float) {
        let radians = angle * .pi / 180.0
        let c = cos(radians)
        let s = sin(radians)
        self.init(
            SIMD4<Float>(c, s, 0, 0),
            SIMD4<Float>(-s, c, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}
