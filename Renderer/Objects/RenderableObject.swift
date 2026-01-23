//
//  RenderableObject.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import MetalKit
import simd

class RenderableObject {
    var id: Int = -1
    var parentId: Int?
    weak var parent: RenderableObject?
    
    var localPosition: SIMD3<Float>
    var localRotation: SIMD3<Float>
    let size: SIMD2<Float>
    let scale: SIMD3<Float>
    
    let texture: MTLTexture
    let effects: [EffectParams]
    let masks: [MTLTexture?]
    let pipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState?
    
    let vertices: [Float] = [
        -0.5, -0.5, 0, 0, 0,
         0.5, -0.5, 0, 1, 0,
        -0.5,  0.5, 0, 0, 1,
         0.5,  0.5, 0, 1, 1
    ]
    
    init(position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>, texture: MTLTexture, effects: [EffectParams], masks: [MTLTexture?], pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState? = nil) {
        self.localPosition = position
        self.localRotation = rotation
        self.size = size
        self.scale = scale
        self.texture = texture
        self.effects = effects
        self.masks = masks
        self.pipeline = pipeline
        self.depthState = depthState
    }
    
    var worldMatrix: matrix_float4x4 {
        var local = Matrix4x4.translation(x: localPosition.x, y: localPosition.y, z: localPosition.z)
        local = local * Matrix4x4.rotation(angle: localRotation.z, axis: SIMD3<Float>(0, 0, 1))
        if let p = parent { return p.worldMatrix * local }
        return local
    }
    
    func draw(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(pipeline)
        if let ds = depthState { encoder.setDepthStencilState(ds) }
        
        let geometryScale = Matrix4x4.scale(x: size.x * scale.x, y: size.y * scale.y, z: 1)
        let finalModelMatrix = worldMatrix * geometryScale
        
        var objUniforms = ObjectUniforms(modelMatrix: finalModelMatrix, alpha: 1.0, color: SIMD4<Float>(1,1,1,1))
        
        encoder.setVertexBytes(vertices, length: vertices.count * 4, index: 0)
        encoder.setVertexBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        encoder.setFragmentBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        
        var currentEffects = effects
        var count = Int32(effects.count)
        if count > 0 {
            encoder.setFragmentBytes(&currentEffects, length: MemoryLayout<EffectParams>.size * effects.count, index: 3)
        } else {
             var dummy = EffectParams(type: 0, maskIndex: 0, speed: 0, scale: 0, strength: 0, exponent: 0, direction: .zero, bounds: .zero, friction: .zero)
             encoder.setFragmentBytes(&dummy, length: MemoryLayout<EffectParams>.size, index: 3)
        }
        encoder.setFragmentBytes(&count, length: MemoryLayout<Int32>.size, index: 4)
        
        encoder.setFragmentTexture(texture, index: 0)
        for (i, mask) in masks.enumerated() {
            if i < 8 { encoder.setFragmentTexture(mask, index: 1 + i) }
        }
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    // MARK: - Static Parsing Helpers
    
    static func parseTransforms(_ obj: SceneObject) -> (SIMD3<Float>, SIMD3<Float>, SIMD2<Float>, SIMD3<Float>) {
        let originStrs = (obj.origin?.value ?? "0 0 0").components(separatedBy: " ").compactMap { Float($0) }
        let sizeStrs = (obj.size?.value ?? "100 100").components(separatedBy: " ").compactMap { Float($0) }
        let scaleStrs = (obj.scale?.value ?? "1 1 1").components(separatedBy: " ").compactMap { Float($0) }
        let angleStrs = (obj.angles?.value ?? "0 0 0").components(separatedBy: " ").compactMap { Float($0) }
        
        var pos = SIMD3<Float>(0,0,0)
        if originStrs.count >= 2 { pos.x = originStrs[0]; pos.y = originStrs[1] }
        if originStrs.count >= 3 { pos.z = originStrs[2] }
        
        var size = SIMD2<Float>(100, 100)
        if sizeStrs.count >= 2 { size.x = sizeStrs[0]; size.y = sizeStrs[1] }
        
        var scale = SIMD3<Float>(1,1,1)
        if scaleStrs.count >= 2 { scale.x = scaleStrs[0]; scale.y = scaleStrs[1] }
        
        var rotation = SIMD3<Float>(0,0,0)
        if angleStrs.count >= 3 {
            rotation.x = angleStrs[0] * .pi / 180.0
            rotation.y = angleStrs[1] * .pi / 180.0
            rotation.z = angleStrs[2] * .pi / 180.0
        }
        return (pos, rotation, size, scale)
    }
    
    static func parseEffects(_ obj: SceneObject, base: URL, textureLoader: MTKTextureLoader) -> ([EffectParams], [MTLTexture?]) {
        var effectParams: [EffectParams] = []
        var maskTextures: [MTLTexture?] = []
        
        guard let effects = obj.effects else { return ([], []) }
        
        func resolveTex(path: String) -> URL {
            let direct = base.appendingPathComponent("materials/\(path).png")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            return base.appendingPathComponent("materials/\(URL(fileURLWithPath: path).lastPathComponent).png")
        }
        
        for effect in effects {
            let fileLower = effect.file.lowercased()
            var type: Int32 = 0
            if fileLower.contains("waterwaves") { type = 2 }
            else if fileLower.contains("shake") { type = 3 }
            else if fileLower.contains("scroll") { type = 1 }
            else if fileLower.contains("foliagesway") { type = 4 }
            else if fileLower.contains("waterripple") { type = 5 } // WaterRipple
            
            if type == 0 { continue }
            
            if let pass = effect.passes?.first, let constants = pass.constantshadervalues {
                var param = EffectParams(type: type, maskIndex: -1, speed: 1, scale: 1, strength: 0.1, exponent: 1, direction: .zero, bounds: .zero, friction: .zero)
                
                // Helper to get value with prefix fallback
                func getVal(_ key: String) -> Float {
                    if let v = constants[key] {
                        switch v { case .float(let f): return f; case .string(let s): return (Float(s) ?? 0) }
                    }
                    // Fallback for ui_editor_properties_ prefix
                    if let v = constants["ui_editor_properties_" + key] {
                        switch v { case .float(let f): return f; case .string(let s): return (Float(s) ?? 0) }
                    }
                    return 0
                }
                
                func getFirstVal(_ keys: [String]) -> Float {
                    for key in keys {
                        let v = getVal(key)
                        if v != 0 { return v }
                        // Check exact match in constants just in case getVal didn't catch it (though getVal covers main + prefix)
                        if constants[key] != nil { return v }
                    }
                    return 0
                }
                
                func getVec2(_ key: String) -> SIMD2<Float> {
                    var valStr: String? = nil
                    if let v = constants[key], case .string(let s) = v { valStr = s }
                    else if let v = constants["ui_editor_properties_" + key], case .string(let s) = v { valStr = s }
                    
                    if let s = valStr {
                        let p = s.components(separatedBy: " ").compactMap{Float($0)}
                        if p.count >= 2 { return SIMD2<Float>(p[0], p[1]) }
                    }
                    return .zero
                }

                // Texture Loading Logic
                if type == 5 {
                    // WaterRipple Specific Loading
                    // Goal: maskTextures must end up as [..., Mask, Normal] so Shader (maskIndex, maskIndex+1) works.
                    // Standard: [null, Mask, Normal]
                    // This Scene: [null, Normal, Mask] (Inverted)
                    
                    var maskPath: String? = nil
                    var normPath: String? = nil
                    
                    // 1. Initial Assign (Standard Assumption)
                    if let texs = pass.textures {
                        if texs.count > 1 { maskPath = texs[1] }
                        if texs.count > 2 { normPath = texs[2] }
                    }
                    
                    // 2. Smart Detection for Inversion
                    // If Index 1 looks like a Normal and Index 2 looks like a Mask, swap them.
                    // Only swap if specific keywords are found to avoid breaking legitimate standard files.
                    if let m = maskPath, let n = normPath {
                        let mLower = m.lowercased()
                        let nLower = n.lowercased()
                        
                        let idx1IsNormal = mLower.contains("norm") && !mLower.contains("mask")
                        let idx2IsMask = nLower.contains("mask")
                        
                        if idx1IsNormal && idx2IsMask {
                            // Detected Inverted format (Scene/scene.json case)
                            let temp = maskPath
                            maskPath = normPath
                            normPath = temp
                        }
                    } else if let m = maskPath, normPath == nil {
                        // Edge case: Only Index 1 exists.
                        // If it looks like a Normal map, treat it as Normal (Case: [null, Normal])
                        if m.lowercased().contains("norm") && !m.lowercased().contains("mask") {
                            normPath = maskPath
                            maskPath = nil
                        }
                    }
                    
                    // 3. Load Textures
                    var maskTex: MTLTexture? = nil
                    var normTex: MTLTexture? = nil
                    
                    if let p = maskPath {
                        let url = resolveTex(path: p)
                        maskTex = try? textureLoader.newTexture(URL: url, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false])
                    }
                    if let p = normPath {
                        let url = resolveTex(path: p)
                        normTex = try? textureLoader.newTexture(URL: url, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false])
                    }
                    
                    // 4. Append to Global List in Correct Order [Mask, Normal]
                    if let m = maskTex, let n = normTex {
                        // Standard complete case
                        maskTextures.append(m)
                        param.maskIndex = Int32(maskTextures.count - 1)
                        maskTextures.append(n)
                    } else if let m = maskTex {
                        // Only Mask (Ripple without normal, just distortion?)
                        maskTextures.append(m)
                        param.maskIndex = Int32(maskTextures.count - 1)
                    } else if let n = normTex {
                        // Only Normal (Mask defaults to 1.0 via invalid index, Normal at index+1)
                        maskTextures.append(n)
                        // maskIndex + 1 must equal (count - 1)
                        // maskIndex = count - 2
                        param.maskIndex = Int32(maskTextures.count) - 2
                    }
                    
                } else {
                    // Generic Loading (Scroll, Shake, Foliage)
                    // Convention: textures[1] = Mask
                    if let masks = pass.textures, masks.count > 1, let maskPath = masks[1] {
                        let maskURL = resolveTex(path: maskPath)
                        if let maskTex = try? textureLoader.newTexture(URL: maskURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) {
                            maskTextures.append(maskTex)
                            param.maskIndex = Int32(maskTextures.count - 1)
                        }
                    }
                }
                
                // Parameter Parsing
                if type == 2 { // WaterWave
                    param.speed = getFirstVal(["speed", "animationspeed"])
                    param.scale = getVal("scale")
                    param.strength = getVal("strength")
                    param.exponent = getVal("exponent")
                    let dirVal = getVal("direction")
                    param.direction = SIMD2<Float>(sin(dirVal), cos(dirVal))
                } else if type == 1 { // Scroll
                    param.direction = getVec2("speed")
                } else if type == 3 { // Shake
                    param.speed = getVal("speed")
                    param.strength = getVal("strength")
                    param.bounds = getVec2("bounds")
                    param.friction = getVec2("friction")
                } else if type == 4 { // FoliageSway
                    param.speed = getVal("speeduv")
                    param.strength = getVal("strength")
                    param.scale = getVal("scale")
                    param.exponent = getVal("phase")
                    param.bounds.x = getVal("power")
                    let dirVal = getVal("scrolldirection")
                    param.direction = SIMD2<Float>(sin(dirVal), cos(dirVal))
                } else if type == 5 { // WaterRipple
                    param.speed = getFirstVal(["animationspeed", "speed", "animation_speed"])
                    param.strength = getFirstVal(["ripplestrength", "strength", "amount", "ripple_strength"])
                    param.scale = getFirstVal(["scale", "ripplescale", "ripple_scale"])
                    let dirVal = getFirstVal(["scrolldirection", "direction", "angle"])
                    param.direction = SIMD2<Float>(sin(dirVal), cos(dirVal))
                    param.friction.x = getFirstVal(["scrollspeed"])
                }
                effectParams.append(param)
            }
        }
        return (effectParams, maskTextures)
    }
}
