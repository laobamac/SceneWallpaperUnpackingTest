//
//  EffectScroll.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//

import Foundation
import MetalKit

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
