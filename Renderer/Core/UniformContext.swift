//
//  UniformContext.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import simd

class UniformContext {
    static let shared = UniformContext()
    
    var time: Float = 0.0
    var daytime: Float = 0.0
    var pointerPosition: simd_float2 = simd_make_float2(0, 0)
    var pointerPositionLast: simd_float2 = simd_make_float2(0, 0)
    var texelSize: simd_float2 = simd_make_float2(0, 0)
    var texelSizeHalf: simd_float2 = simd_make_float2(0, 0)
    var brightness: Float = 1.0
    var alpha: Float = 1.0
    var userAlpha: Float = 1.0
    
    var audioSpectrum16Left: [Float] = Array(repeating: 0.0, count: 16)
    var audioSpectrum16Right: [Float] = Array(repeating: 0.0, count: 16)
    var audioSpectrum32Left: [Float] = Array(repeating: 0.0, count: 32)
    var audioSpectrum32Right: [Float] = Array(repeating: 0.0, count: 32)
    var audioSpectrum64Left: [Float] = Array(repeating: 0.0, count: 64)
    var audioSpectrum64Right: [Float] = Array(repeating: 0.0, count: 64)
    
    var modelMatrix: simd_float4x4 = matrix_identity_float4x4
    var viewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4
    var modelViewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4
    var modelViewProjectionMatrixInverse: simd_float4x4 = matrix_identity_float4x4
    var effectTextureProjectionMatrix: simd_float4x4 = matrix_identity_float4x4
    var effectTextureProjectionMatrixInverse: simd_float4x4 = matrix_identity_float4x4
    var normalModelMatrix: simd_float3x3 = matrix_identity_float3x3

    var lightAmbientColor: simd_float3 = simd_make_float3(1, 1, 1)
    var lightSkylightColor: simd_float3 = simd_make_float3(1, 1, 1)

    func update(deltaTime: Float, width: Float, height: Float, mouseX: Float, mouseY: Float) {
        time += deltaTime
        
        pointerPositionLast = pointerPosition
        pointerPosition = simd_make_float2(mouseX, mouseY)
        
        let invW = width > 0 ? 1.0 / width : 0.0
        let invH = height > 0 ? 1.0 / height : 0.0
        texelSize = simd_make_float2(invW, invH)
        texelSizeHalf = simd_make_float2(invW * 0.5, invH * 0.5)
    }
    
    func collectUniforms(materialConstants: [String: ScriptableValue]?, evaluatedInstanceUniforms: [String: [Float]]?) -> [String: Any] {
        var map: [String: Any] = [:]
        
        map["g_Time"] = time
        map["g_Daytime"] = daytime
        map["g_PointerPosition"] = pointerPosition
        map["g_PointerPositionLast"] = pointerPositionLast
        map["g_TexelSize"] = texelSize
        map["g_TexelSizeHalf"] = texelSizeHalf
        map["g_Brightness"] = brightness
        map["g_Alpha"] = alpha
        map["g_UserAlpha"] = userAlpha
        
        map["g_AudioSpectrum16Left"] = audioSpectrum16Left
        map["g_AudioSpectrum16Right"] = audioSpectrum16Right
        map["g_AudioSpectrum32Left"] = audioSpectrum32Left
        map["g_AudioSpectrum32Right"] = audioSpectrum32Right
        map["g_AudioSpectrum64Left"] = audioSpectrum64Left
        map["g_AudioSpectrum64Right"] = audioSpectrum64Right
        
        map["g_ModelMatrix"] = modelMatrix
        map["g_ViewProjectionMatrix"] = viewProjectionMatrix
        map["g_ModelViewProjectionMatrix"] = modelViewProjectionMatrix
        map["g_ModelViewProjectionMatrixInverse"] = modelViewProjectionMatrixInverse
        map["g_EffectTextureProjectionMatrix"] = effectTextureProjectionMatrix
        map["g_EffectTextureProjectionMatrixInverse"] = effectTextureProjectionMatrixInverse
        map["g_NormalModelMatrix"] = normalModelMatrix
        
        map["g_LightAmbientColor"] = lightAmbientColor
        map["g_LightSkylightColor"] = lightSkylightColor
        
        if let constants = materialConstants {
            for (key, val) in constants {
                switch val {
                case .float(let f): map[key] = f
                case .int(let i): map[key] = Int32(i)
                case .floatArray(let arr): map[key] = arr
                default: break
                }
            }
        }
        
        if let evaluated = evaluatedInstanceUniforms {
            for (key, arr) in evaluated {
                map[key] = arr
            }
        }
        
        return map
    }
}
