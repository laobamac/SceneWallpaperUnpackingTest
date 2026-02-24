//
//  AudioBars.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//
import Foundation
import simd

struct AudioBarsUniforms {
    var color: SIMD4<Float>
    var g_Time: Float
    var barSpacing: Float
    var barCount: Float
    var opacity: Float
    var lowerBound: Float
    var upperBound: Float
    var blurX: Float
    var blurY: Float
}
