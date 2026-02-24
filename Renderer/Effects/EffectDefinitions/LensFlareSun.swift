//
//  LensFlareSun.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//
import Foundation
import simd

struct LensFlareSunUniforms {
    var color: SIMD4<Float>
    var g_Time: Float
    var angle: Float
    var speed: Float
    var sunScale: Float
    var opacity: Float
    var scale: Float
    var rotationSpeed: Float
    var speedSecondary: Float
    var pointerSpeed: Float
    var positionOffsetX: Float
    var positionOffsetY: Float
    var padding: Float
}
