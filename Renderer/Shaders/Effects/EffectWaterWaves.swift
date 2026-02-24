//
//  EffectWaterWaves.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//

import Foundation
import MetalKit

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
