//
//  EffectSimpleAudioBars.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//

import Foundation
import MetalKit

class AudioBarsEffect: EffectType {
    var id: Int = 0
    var isVisible: Bool = true
    var effectName: String = "Simple_Audio_Bars"
    var pipelineState: MTLRenderPipelineState?
    var uniformBuffer: MTLBuffer?
    var uniforms = AudioBarsUniforms(color: SIMD4<Float>(1, 0.57, 0.57, 1), g_Time: 0, barSpacing: 0.75, barCount: 128, opacity: 1, lowerBound: 0, upperBound: 1, blurX: 0.5, blurY: 0.5)
    var dummyAudioTexture: MTLTexture?
    
    func load(device: MTLDevice, library: MTLLibrary, passJSON: EffectPassJSON, baseFolder: URL) async throws {
        if let vals = passJSON.constantshadervalues {
            if let v = vals["Bar Color"] {
                var c = SIMD3<Float>(1, 1, 1)
                if case .string(let s) = v {
                    let p = s.split(separator: " ").compactMap { Float($0) }
                    if p.count >= 3 { c = SIMD3<Float>(p[0], p[1], p[2]) }
                } else if case .object(let dict) = v, let val = dict["value"] {
                    if case .string(let s) = val {
                        let p = s.split(separator: " ").compactMap { Float($0) }
                        if p.count >= 3 { c = SIMD3<Float>(p[0], p[1], p[2]) }
                    }
                }
                uniforms.color = SIMD4<Float>(c.x, c.y, c.z, 1)
            }
            if let v = vals["Bar Spacing"] { uniforms.barSpacing = v.floatValue }
            if let v = vals["Bar Count"] { uniforms.barCount = v.floatValue }
            if let v = vals["ui_editor_properties_opacity"] { uniforms.opacity = v.floatValue }
            if let v = vals["Lower/Upper Bar Bounds"] {
                var bounds = SIMD2<Float>(0, 1)
                if case .string(let s) = v {
                    let p = s.split(separator: " ").compactMap { Float($0) }
                    if p.count >= 2 { bounds = SIMD2<Float>(p[0], p[1]) }
                } else if case .object(let dict) = v, let val = dict["value"] {
                    if case .string(let s) = val {
                        let p = s.split(separator: " ").compactMap { Float($0) }
                        if p.count >= 2 { bounds = SIMD2<Float>(p[0], p[1]) }
                    }
                }
                uniforms.lowerBound = bounds.x
                uniforms.upperBound = bounds.y
            }
            if let v = vals["Anti-alias blurring"] {
                var blur = SIMD2<Float>(0.5, 0.5)
                if case .string(let s) = v {
                    let p = s.split(separator: " ").compactMap { Float($0) }
                    if p.count >= 2 { blur = SIMD2<Float>(p[0], p[1]) }
                } else if case .object(let dict) = v, let val = dict["value"] {
                    if case .string(let s) = val {
                        let p = s.split(separator: " ").compactMap { Float($0) }
                        if p.count >= 2 { blur = SIMD2<Float>(p[0], p[1]) }
                    }
                }
                uniforms.blurX = blur.x
                uniforms.blurY = blur.y
            }
        }
        Logger.log("[AudioBarsEffect] Loaded. Color: \(uniforms.color), Bounds: \(uniforms.lowerBound) - \(uniforms.upperBound), BarCount: \(uniforms.barCount)")
        
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 64, height: 1, mipmapped: false)
        dummyAudioTexture = device.makeTexture(descriptor: texDesc)
        
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        desc.vertexFunction = library.makeFunction(name: "effect_blit_vertex")
        desc.fragmentFunction = library.makeFunction(name: "audiobars_frag")
        pipelineState = try await device.makeRenderPipelineState(descriptor: desc, options: []).0
        uniformBuffer = device.makeBuffer(length: MemoryLayout<AudioBarsUniforms>.stride, options: .storageModeShared)
    }
    
    func update(dt: Float, time: Float, size: CGSize) {
        uniforms.g_Time = time
        if let buffer = uniformBuffer {
            memcpy(buffer.contents(), &uniforms, MemoryLayout<AudioBarsUniforms>.stride)
        }
        if let tex = dummyAudioTexture {
            var randomData = [UInt8](repeating: 0, count: 64)
            for i in 0..<64 { randomData[i] = UInt8.random(in: 0...255) }
            tex.replace(region: MTLRegionMake2D(0, 0, 64, 1), mipmapLevel: 0, withBytes: randomData, bytesPerRow: 64)
        }
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture, destinationTexture: MTLTexture) {
        guard let pipeline = pipelineState, let buffer = uniformBuffer else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destinationTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(sourceTexture, index: 0)
        if let dummy = dummyAudioTexture {
            enc.setFragmentTexture(dummy, index: 1)
        }
        if let sampler = EffectManager.shared.samplerState {
            enc.setFragmentSamplerState(sampler, index: 0)
        }
        enc.setFragmentBuffer(buffer, offset: 0, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }
}

class GradientColorEffect: EffectType {
    var id: Int = 0
    var isVisible: Bool = true
    var effectName: String = "gradient_color"
    var pipelineState: MTLRenderPipelineState?
    var uniformBuffer: MTLBuffer?
    var uniforms = GradientColorUniforms(color1: SIMD4<Float>(1,0,0,1), color2: SIMD4<Float>(1,0.47,0,1), g_Time: 0, opacity: 1, hueSpeed: 0, amount: 2.06, oscillate: 0, padding1: 0, padding2: 0, padding3: 0)
    
    func load(device: MTLDevice, library: MTLLibrary, passJSON: EffectPassJSON, baseFolder: URL) async throws {
        if let vals = passJSON.constantshadervalues {
            if let v = vals["Color 1"] {
                let c = v.float3Value
                uniforms.color1 = SIMD4<Float>(c.x, c.y, c.z, 1)
            }
            if let v = vals["Color 2"] {
                let c = v.float3Value
                uniforms.color2 = SIMD4<Float>(c.x, c.y, c.z, 1)
            }
            if let v = vals["Opacity"] { uniforms.opacity = v.floatValue }
            if let v = vals["Hue Speed"] { uniforms.hueSpeed = v.floatValue }
            if let v = vals["Amount"] { uniforms.amount = v.floatValue }
            if let v = vals["Oscillate"] { uniforms.oscillate = v.floatValue }
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        desc.vertexFunction = library.makeFunction(name: "effect_blit_vertex")
        desc.fragmentFunction = library.makeFunction(name: "gradient_color_frag")
        pipelineState = try await device.makeRenderPipelineState(descriptor: desc, options: []).0
        uniformBuffer = device.makeBuffer(length: MemoryLayout<GradientColorUniforms>.stride, options: .storageModeShared)
    }
    
    func update(dt: Float, time: Float, size: CGSize) {
        uniforms.g_Time = time
        if let buffer = uniformBuffer {
            memcpy(buffer.contents(), &uniforms, MemoryLayout<GradientColorUniforms>.stride)
        }
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture, destinationTexture: MTLTexture) {
        guard let pipeline = pipelineState, let buffer = uniformBuffer else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destinationTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(sourceTexture, index: 0)
        if let sampler = EffectManager.shared.samplerState {
            enc.setFragmentSamplerState(sampler, index: 0)
        }
        enc.setFragmentBuffer(buffer, offset: 0, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }
}

class LensFlareSunEffect: EffectType {
    var id: Int = 0
    var isVisible: Bool = true
    var effectName: String = "lens_flare_sun"
    var pipelineState: MTLRenderPipelineState?
    var uniformBuffer: MTLBuffer?
    var uniforms = LensFlareSunUniforms(color: SIMD4<Float>(1,1,1,1), g_Time: 0, angle: 0, speed: 0.25, sunScale: 32, opacity: 1, scale: 0.025, rotationSpeed: 1, speedSecondary: 0.125, pointerSpeed: 0, positionOffsetX: 0.1, positionOffsetY: 1.3, padding: 0)
    
    func load(device: MTLDevice, library: MTLLibrary, passJSON: EffectPassJSON, baseFolder: URL) async throws {
        if let vals = passJSON.constantshadervalues {
            if let v = vals["Color"] {
                let c = v.float3Value
                uniforms.color = SIMD4<Float>(c.x, c.y, c.z, 1)
            }
            if let v = vals["angle"] { uniforms.angle = v.floatValue }
            if let v = vals["speed"] { uniforms.speed = v.floatValue }
            if let v = vals["Sun Scale"] { uniforms.sunScale = v.floatValue }
            if let v = vals["Opacity"] { uniforms.opacity = v.floatValue }
            if let v = vals["Scale"] { uniforms.scale = v.floatValue }
            if let v = vals["rotationspeed"] { uniforms.rotationSpeed = v.floatValue }
            if let v = vals["speed secondary"] { uniforms.speedSecondary = v.floatValue }
            if let v = vals["pointerspeed"] { uniforms.pointerSpeed = v.floatValue }
            if let v = vals["Position offset"] {
                let po = v.float2Value
                uniforms.positionOffsetX = po.x
                uniforms.positionOffsetY = po.y
            }
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        desc.vertexFunction = library.makeFunction(name: "effect_blit_vertex")
        desc.fragmentFunction = library.makeFunction(name: "lens_flare_sun_frag")
        pipelineState = try await device.makeRenderPipelineState(descriptor: desc, options: []).0
        uniformBuffer = device.makeBuffer(length: MemoryLayout<LensFlareSunUniforms>.stride, options: .storageModeShared)
    }
    
    func update(dt: Float, time: Float, size: CGSize) {
        uniforms.g_Time = time
        if let buffer = uniformBuffer {
            memcpy(buffer.contents(), &uniforms, MemoryLayout<LensFlareSunUniforms>.stride)
        }
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture, destinationTexture: MTLTexture) {
        guard let pipeline = pipelineState, let buffer = uniformBuffer else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destinationTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(sourceTexture, index: 0)
        if let sampler = EffectManager.shared.samplerState {
            enc.setFragmentSamplerState(sampler, index: 0)
        }
        enc.setFragmentBuffer(buffer, offset: 0, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }
}

class ShadowEffect: EffectType {
    var id: Int = 0
    var isVisible: Bool = true
    var effectName: String = "shadow"
    var pipelineState: MTLRenderPipelineState?
    var uniformBuffer: MTLBuffer?
    var uniforms = ShadowUniforms(shadowColor: SIMD4<Float>(0,0,0,1), shadowOffset: SIMD4<Float>(2,-2,0,0), alpha: 0.15, shadowDrawBorder: 0.5, padding1: 0, padding2: 0)
    
    func load(device: MTLDevice, library: MTLLibrary, passJSON: EffectPassJSON, baseFolder: URL) async throws {
        if let vals = passJSON.constantshadervalues {
            if let v = vals["shadowColor"] {
                let c = v.float3Value
                uniforms.shadowColor = SIMD4<Float>(c.x, c.y, c.z, 1)
            }
            if let v = vals["shadowOffset"] {
                let o = v.float3Value
                uniforms.shadowOffset = SIMD4<Float>(o.x, o.y, o.z, 0)
            }
            if let v = vals["alpha"] { uniforms.alpha = v.floatValue }
            if let v = vals["shadowDrawBorder"] { uniforms.shadowDrawBorder = v.floatValue }
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        desc.vertexFunction = library.makeFunction(name: "effect_blit_vertex")
        desc.fragmentFunction = library.makeFunction(name: "shadow_frag")
        pipelineState = try await device.makeRenderPipelineState(descriptor: desc, options: []).0
        uniformBuffer = device.makeBuffer(length: MemoryLayout<ShadowUniforms>.stride, options: .storageModeShared)
    }
    
    func update(dt: Float, time: Float, size: CGSize) {
        if let buffer = uniformBuffer {
            memcpy(buffer.contents(), &uniforms, MemoryLayout<ShadowUniforms>.stride)
        }
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture, destinationTexture: MTLTexture) {
        guard let pipeline = pipelineState, let buffer = uniformBuffer else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destinationTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(sourceTexture, index: 0)
        if let sampler = EffectManager.shared.samplerState {
            enc.setFragmentSamplerState(sampler, index: 0)
        }
        enc.setFragmentBuffer(buffer, offset: 0, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }
}
