//
//  PassExecutor.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import Metal

class PassExecutor {
    static func execute(
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice,
        effectName: String,
        passConfig: EffectPassConfig,
        evaluatedUniforms: [String: [Float]],
        inputTextures: [MTLTexture],
        outputTexture: MTLTexture,
        vertexBuffer: MTLBuffer,
        texCoordBuffer: MTLBuffer,
        vertexCount: Int
    ) {
        guard let library = EffectManager.shared.getLibrary(for: effectName),
              let reflectionMap = EffectManager.shared.getReflectionMap(for: effectName) else { return }
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = outputTexture.pixelFormat
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "main0")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "main0")
        
        if passConfig.blendmode == "add" {
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        } else if passConfig.blendmode == "translucent" || passConfig.blendmode == "normal" {
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        }
        
        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            renderEncoder.endEncoding()
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(texCoordBuffer, offset: 0, index: 1)
        
        var maxOffset = 0
        for member in reflectionMap.allMembers() {
            let end = member.offset + member.size
            if end > maxOffset { maxOffset = end }
        }
        
        if maxOffset > 0 {
            let alignedSize = (maxOffset + 15) & ~15
            if let buffer = device.makeBuffer(length: alignedSize, options: .storageModeShared) {
                let ptr = buffer.contents()
                
                for member in reflectionMap.allMembers() {
                    if let values = evaluatedUniforms[member.name] {
                        let dest = ptr.advanced(by: member.offset)
                        values.withUnsafeBufferPointer { vPtr in
                            if let baseAddress = vPtr.baseAddress {
                                dest.copyMemory(from: baseAddress, byteCount: min(member.size, values.count * MemoryLayout<Float>.size))
                            }
                        }
                    }
                }
                
                renderEncoder.setFragmentBuffer(buffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(buffer, offset: 0, index: 2)
            }
        }
        
        for (i, texture) in inputTextures.enumerated() {
            renderEncoder.setFragmentTexture(texture, index: i)
        }
        
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        renderEncoder.endEncoding()
    }
}
