//
//  GradientColor.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//
import Foundation
import simd

struct GradientColorUniforms {
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>
    var g_Time: Float
    var opacity: Float
    var hueSpeed: Float
    var amount: Float
    var oscillate: Float
    var padding1: Float
    var padding2: Float
    var padding3: Float
}
