//
//  PassExecutor.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import Metal
import simd

class PassExecutor {
    static func execute(
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice,
        shaderName: String,
        materialPass: MaterialPassConfig,
        combinedUniforms: [String: Any],
        boundTextures: [Int: MTLTexture],
        outputTexture: MTLTexture,
        vertexBuffer: MTLBuffer,
        texCoordBuffer: MTLBuffer,
        vertexCount: Int
    ) {
        guard let library = EffectManager.shared.getLibrary(for: shaderName),
              let reflectionMap = EffectManager.shared.getReflectionMap(for: shaderName) else { return }
        
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
        
        applyBlendMode(descriptor: pipelineDescriptor.colorAttachments[0], blendString: materialPass.blending)
        
        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            renderEncoder.endEncoding()
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        
        applyCullMode(encoder: renderEncoder, cullString: materialPass.cullmode)
        applyDepthState(encoder: renderEncoder, device: device, depthTest: materialPass.depthtest, depthWrite: materialPass.depthwrite)
        
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
                    if let value = combinedUniforms[member.name] {
                        writeUniformToBuffer(pointer: ptr, offset: member.offset, size: member.size, value: value)
                    }
                }
                
                renderEncoder.setFragmentBuffer(buffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(buffer, offset: 0, index: 2)
            }
        }
        
        for (index, texture) in boundTextures {
            renderEncoder.setFragmentTexture(texture, index: index)
        }
        
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        renderEncoder.endEncoding()
    }
    
    private static func writeUniformToBuffer(pointer: UnsafeMutableRawPointer, offset: Int, size: Int, value: Any) {
        let dest = pointer.advanced(by: offset)
        
        if let f = value as? Float {
            dest.storeBytes(of: f, as: Float.self)
        } else if let i = value as? Int32 {
            dest.storeBytes(of: i, as: Int32.self)
        } else if let arr = value as? [Float] {
            let count = min(arr.count, size / MemoryLayout<Float>.stride)
            if count == 3 {
                var vec4 = simd_make_float4(arr[0], arr[1], arr[2], 0)
                dest.copyMemory(from: &vec4, byteCount: 16)
            } else {
                arr.withUnsafeBufferPointer { vPtr in
                    if let baseAddress = vPtr.baseAddress {
                        dest.copyMemory(from: baseAddress, byteCount: count * MemoryLayout<Float>.stride)
                    }
                }
            }
        } else if let vec2 = value as? simd_float2 {
            dest.storeBytes(of: vec2, as: simd_float2.self)
        } else if let vec3 = value as? simd_float3 {
            var vec4 = simd_make_float4(vec3.x, vec3.y, vec3.z, 0)
            dest.copyMemory(from: &vec4, byteCount: 16)
        } else if let vec4 = value as? simd_float4 {
            dest.storeBytes(of: vec4, as: simd_float4.self)
        } else if let mat3 = value as? simd_float3x3 {
            dest.storeBytes(of: mat3, as: simd_float3x3.self)
        } else if let mat4 = value as? simd_float4x4 {
            dest.storeBytes(of: mat4, as: simd_float4x4.self)
        }
    }
    
    private static func applyBlendMode(descriptor: MTLRenderPipelineColorAttachmentDescriptor, blendString: String?) {
        guard let mode = blendString?.lowercased() else {
            descriptor.isBlendingEnabled = false
            return
        }
        
        descriptor.isBlendingEnabled = true
        descriptor.sourceAlphaBlendFactor = .sourceAlpha
        descriptor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        switch mode {
        case "add", "additive":
            descriptor.sourceRGBBlendFactor = .sourceAlpha
            descriptor.destinationRGBBlendFactor = .one
        case "translucent", "normal":
            descriptor.sourceRGBBlendFactor = .sourceAlpha
            descriptor.destinationRGBBlendFactor = .oneMinusSourceAlpha
        default:
            descriptor.isBlendingEnabled = false
        }
    }
    
    private static func applyCullMode(encoder: MTLRenderCommandEncoder, cullString: String?) {
        if cullString?.lowercased() == "normal" {
            encoder.setCullMode(.back)
        } else {
            encoder.setCullMode(.none)
        }
    }
    
    private static func applyDepthState(encoder: MTLRenderCommandEncoder, device: MTLDevice, depthTest: String?, depthWrite: String?) {
        let descriptor = MTLDepthStencilDescriptor()
        
        if depthTest?.lowercased() == "enabled" {
            descriptor.depthCompareFunction = .less
        } else {
            descriptor.depthCompareFunction = .always
        }
        
        if depthWrite?.lowercased() == "enabled" {
            descriptor.isDepthWriteEnabled = true
        } else {
            descriptor.isDepthWriteEnabled = false
        }
        
        if let state = device.makeDepthStencilState(descriptor: descriptor) {
            encoder.setDepthStencilState(state)
        }
    }
}
