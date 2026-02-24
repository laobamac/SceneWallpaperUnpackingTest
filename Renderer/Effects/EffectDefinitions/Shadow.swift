//
//  Shadow.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//
import Foundation
import simd

struct ShadowUniforms {
    var shadowColor: SIMD4<Float>
    var shadowOffset: SIMD4<Float>
    var alpha: Float
    var shadowDrawBorder: Float
    var padding1: Float
    var padding2: Float
}
