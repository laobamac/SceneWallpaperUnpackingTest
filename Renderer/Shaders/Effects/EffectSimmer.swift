//
//  EffectSimmer.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//

import Foundation
import MetalKit

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
        Logger.log("[ShimmerEffect] Loaded. Color: \(uniforms.color), Speed: \(uniforms.speed), Direction: \(uniforms.direction)")
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
