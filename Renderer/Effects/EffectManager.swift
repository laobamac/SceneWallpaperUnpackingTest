//
//  EffectManager.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//

import Foundation
import MetalKit

class EffectManager {
    static let shared = EffectManager()
    var device: MTLDevice?
    var library: MTLLibrary?
    var samplerState: MTLSamplerState?

    func setup(device: MTLDevice, library: MTLLibrary) async {
        self.device = device
        self.library = library
        
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }

    func loadEffects(for obj: SceneObject, baseFolder: URL) async -> [EffectType] {
        var loaded: [EffectType] = []
        guard let device = device, let library = library, let effects = obj.effects else { return loaded }
        
        for eJSON in effects {
            guard let file = eJSON.file, let passes = eJSON.passes else { continue }
            for pass in passes {
                var effect: EffectType?
                
                if file.contains("waterwaves") { effect = WaterWavesEffect() }
                else if file.contains("scroll") { effect = ScrollEffect() }
                else if file.contains("shimmer") { effect = ShimmerEffect() }
                else if file.contains("Simple_Audio_Bars") { effect = AudioBarsEffect() }
                else if file.contains("gradient_color") { effect = GradientColorEffect() }
                else if file.contains("lens_flare_sun") { effect = LensFlareSunEffect() }
                else if file.contains("shadow") { effect = ShadowEffect() }
                
                if var fx = effect {
                    fx.id = eJSON.id ?? 0
                    if let vis = eJSON.visible {
                        if case .bool(let v) = vis { fx.isVisible = v }
                    }
                    try? await fx.load(device: device, library: library, passJSON: pass, baseFolder: baseFolder)
                    loaded.append(fx)
                }
            }
        }
        return loaded
    }
    
    func applyEffects(commandBuffer: MTLCommandBuffer, source: MTLTexture, target: MTLTexture, temp: MTLTexture, effects: [EffectType]) {
        let activeEffects = effects.filter { $0.isVisible }
        guard !activeEffects.isEmpty else { return }
        
        var currentSource = source
        if currentSource.textureType == .type2DArray {
            if let view = currentSource.makeTextureView(pixelFormat: currentSource.pixelFormat, textureType: .type2D, levels: 0..<1, slices: 0..<1) {
                currentSource = view
            }
        }
        
        var targetView = target
        if target.textureType == .type2DArray {
            if let view = target.makeTextureView(pixelFormat: target.pixelFormat, textureType: .type2D, levels: 0..<1, slices: 0..<1) {
                targetView = view
            }
        }
        
        var tempView = temp
        if temp.textureType == .type2DArray {
            if let view = temp.makeTextureView(pixelFormat: temp.pixelFormat, textureType: .type2D, levels: 0..<1, slices: 0..<1) {
                tempView = view
            }
        }
        
        var dest = (activeEffects.count % 2 == 0) ? tempView : targetView
        
        for i in 0..<activeEffects.count {
            let effect = activeEffects[i]
            effect.encode(commandBuffer: commandBuffer, sourceTexture: currentSource, destinationTexture: dest)
            currentSource = dest
            dest = (dest === targetView) ? tempView : targetView
        }
    }
}

class WaterWavesEffect: EffectType {
    var id: Int = 0
    var isVisible: Bool = true
    var effectName: String = "waterwaves"
    var pipelineState: MTLRenderPipelineState?
    var uniformBuffer: MTLBuffer?
    var uniforms = WaterWavesUniforms(g_Time: 0, g_Speed: 5, g_Scale: 200, g_Exponent: 1, g_Strength: 0.1, g_Speed2: 3, g_Scale2: 66, g_Offset2: 0, g_Exponent2: 1, padding1: 0, padding2: 0, padding3: 0)
    var maskTexture: MTLTexture?
    
    func load(device: MTLDevice, library: MTLLibrary, passJSON: EffectPassJSON, baseFolder: URL) async throws {
        if let vals = passJSON.constantshadervalues {
            if let v = vals["speed"] { uniforms.g_Speed = v.floatValue }
            if let v = vals["scale"] { uniforms.g_Scale = v.floatValue }
            if let v = vals["exponent"] { uniforms.g_Exponent = v.floatValue }
            if let v = vals["strength"] { uniforms.g_Strength = v.floatValue }
            if let v = vals["speed2"] { uniforms.g_Speed2 = v.floatValue }
            if let v = vals["scale2"] { uniforms.g_Scale2 = v.floatValue }
            if let v = vals["offset2"] { uniforms.g_Offset2 = v.floatValue }
            if let v = vals["exponent2"] { uniforms.g_Exponent2 = v.floatValue }
        }
        
        if let textures = passJSON.textures, textures.count > 1, let mask = textures[1] {
            let maskUrl = baseFolder.appendingPathComponent("materials").appendingPathComponent(mask).appendingPathExtension("png")
            maskTexture = try? await TextureManager.shared.loadTexture(url: maskUrl, options: [.origin: MTKTextureLoader.Origin.topLeft], force2D: true)
        }
        
        let constants = MTLFunctionConstantValues()
        var hasMask = maskTexture != nil
        constants.setConstantValue(&hasMask, type: .bool, index: 0)
        var dualWaves = passJSON.combos?["DUALWAVES"] == 1
        constants.setConstantValue(&dualWaves, type: .bool, index: 1)
        var timeOffset = passJSON.combos?["TIMEOFFSET"] == 1
        constants.setConstantValue(&timeOffset, type: .bool, index: 2)
        var perspective = passJSON.combos?["PERSPECTIVE"] == 1
        constants.setConstantValue(&perspective, type: .bool, index: 3)
        
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        desc.vertexFunction = library.makeFunction(name: "effect_blit_vertex")
        desc.fragmentFunction = try await library.makeFunction(name: "waterwaves_frag", constantValues: constants)
        pipelineState = try await device.makeRenderPipelineState(descriptor: desc, options: []).0
        uniformBuffer = device.makeBuffer(length: MemoryLayout<WaterWavesUniforms>.stride, options: .storageModeShared)
    }
    
    func update(dt: Float, time: Float, size: CGSize) {
        uniforms.g_Time = time
        if let buffer = uniformBuffer {
            memcpy(buffer.contents(), &uniforms, MemoryLayout<WaterWavesUniforms>.stride)
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
        if let m = maskTexture { enc.setFragmentTexture(m, index: 1) }
        if let sampler = EffectManager.shared.samplerState {
            enc.setFragmentSamplerState(sampler, index: 0)
        }
        enc.setFragmentBuffer(buffer, offset: 0, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }
}

class ScrollEffect: EffectType {
    var id: Int = 0
    var isVisible: Bool = true
    var effectName: String = "scroll"
    var pipelineState: MTLRenderPipelineState?
    var uniformBuffer: MTLBuffer?
    var uniforms = ScrollUniforms(speedx: 0, speedy: 0, repeatX: 1, repeatY: 1)
    var currentTimeX: Float = 0
    var currentTimeY: Float = 0
    
    func load(device: MTLDevice, library: MTLLibrary, passJSON: EffectPassJSON, baseFolder: URL) async throws {
        if let vals = passJSON.constantshadervalues {
            if let v = vals["speedx"] { uniforms.speedx = v.floatValue }
            if let v = vals["speedy"] { uniforms.speedy = v.floatValue }
            if let v = vals["repeat"] {
                let r = v.float2Value
                uniforms.repeatX = r.x
                uniforms.repeatY = r.y
            }
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        desc.vertexFunction = library.makeFunction(name: "effect_blit_vertex")
        desc.fragmentFunction = library.makeFunction(name: "scroll_frag")
        pipelineState = try await device.makeRenderPipelineState(descriptor: desc, options: []).0
        uniformBuffer = device.makeBuffer(length: MemoryLayout<ScrollUniforms>.stride, options: .storageModeShared)
    }
    
    func update(dt: Float, time: Float, size: CGSize) {
        currentTimeX += uniforms.speedx * dt
        currentTimeY += uniforms.speedy * dt
        var u = uniforms
        u.speedx = currentTimeX
        u.speedy = currentTimeY
        if let buffer = uniformBuffer {
            memcpy(buffer.contents(), &u, MemoryLayout<ScrollUniforms>.stride)
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

class ShimmerEffect: EffectType {
    var id: Int = 0
    var isVisible: Bool = true
    var effectName: String = "shimmer"
    var pipelineState: MTLRenderPipelineState?
    var uniformBuffer: MTLBuffer?
    var uniforms = ShimmerUniforms(color: SIMD4<Float>(1,1,1,1), g_Time: 0, speed: 0.25, brightness: 0.6, granularity: 1, direction: -1.2, offset: 0, delay: 2, padding: 0)
    
    func load(device: MTLDevice, library: MTLLibrary, passJSON: EffectPassJSON, baseFolder: URL) async throws {
        if let vals = passJSON.constantshadervalues {
            if let v = vals["ui_editor_properties_color"] {
                let c = v.float3Value
                uniforms.color = SIMD4<Float>(c.x, c.y, c.z, 1)
            }
            if let v = vals["ui_editor_properties_speed"] { uniforms.speed = v.floatValue }
            if let v = vals["ui_editor_properties_brightness"] { uniforms.brightness = v.floatValue }
            if let v = vals["ui_editor_properties_granularity"] { uniforms.granularity = v.floatValue }
            if let v = vals["ui_editor_properties_direction"] { uniforms.direction = v.floatValue }
            if let v = vals["ui_editor_properties_offset"] { uniforms.offset = v.floatValue }
            if let v = vals["ui_editor_properties_delay"] { uniforms.delay = v.floatValue }
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        desc.vertexFunction = library.makeFunction(name: "effect_blit_vertex")
        desc.fragmentFunction = library.makeFunction(name: "shimmer_frag")
        pipelineState = try await device.makeRenderPipelineState(descriptor: desc, options: []).0
        uniformBuffer = device.makeBuffer(length: MemoryLayout<ShimmerUniforms>.stride, options: .storageModeShared)
    }
    
    func update(dt: Float, time: Float, size: CGSize) {
        uniforms.g_Time = time
        if let buffer = uniformBuffer {
            memcpy(buffer.contents(), &uniforms, MemoryLayout<ShimmerUniforms>.stride)
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

class AudioBarsEffect: EffectType {
    var id: Int = 0
    var isVisible: Bool = true
    var effectName: String = "Simple_Audio_Bars"
    var pipelineState: MTLRenderPipelineState?
    var uniformBuffer: MTLBuffer?
    var uniforms = AudioBarsUniforms(color: SIMD4<Float>(1, 0.57, 0.57, 1), g_Time: 0, barSpacing: 0.75, barCount: 128, opacity: 1, lowerBound: 0, upperBound: 1, blurX: 0.5, blurY: 0.5)
    
    func load(device: MTLDevice, library: MTLLibrary, passJSON: EffectPassJSON, baseFolder: URL) async throws {
        if let vals = passJSON.constantshadervalues {
            if let v = vals["Bar Spacing"] { uniforms.barSpacing = v.floatValue }
            if let v = vals["Bar Count"] { uniforms.barCount = v.floatValue }
            if let v = vals["ui_editor_properties_opacity"] { uniforms.opacity = v.floatValue }
            if let v = vals["Lower/Upper Bar Bounds"] {
                let bounds = v.float2Value
                uniforms.lowerBound = bounds.x
                uniforms.upperBound = bounds.y
            }
            if let v = vals["Anti-alias blurring"] {
                let blur = v.float2Value
                uniforms.blurX = blur.x
                uniforms.blurY = blur.y
            }
        }
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
