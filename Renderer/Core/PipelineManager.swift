//
//  PipelineManager.swift
//  Renderer
//
//  Created by laobamac on 2026/2/26.
//

import MetalKit

class PipelineManager {
    let device: MTLDevice
    let library: MTLLibrary
    
    var pipelineState: MTLRenderPipelineState?
    var puppetPipelineState: MTLRenderPipelineState?
    var translucentSpritePipeline: MTLRenderPipelineState?
    var additiveSpritePipeline: MTLRenderPipelineState?
    var translucentRopePipeline: MTLRenderPipelineState?
    var additiveRopePipeline: MTLRenderPipelineState?
    var extractPipeline: MTLRenderPipelineState?
    var blurPipeline: MTLRenderPipelineState?
    var upsamplePipeline: MTLRenderPipelineState?
    var finalPipeline: MTLRenderPipelineState?
    var samplerState: MTLSamplerState?
    
    init(device: MTLDevice, library: MTLLibrary) {
        self.device = device
        self.library = library
    }
    
    func setupPipelines(hdrFormat: MTLPixelFormat, depthFormat: MTLPixelFormat) async throws {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Standard"
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.colorAttachments[0].pixelFormat = hdrFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = depthFormat
        descriptor.stencilAttachmentPixelFormat = depthFormat
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 20
        descriptor.vertexDescriptor = vertexDescriptor
        pipelineState = try await device.makeRenderPipelineState(descriptor: descriptor, options: []).0

        let puppetDesc = MTLRenderPipelineDescriptor()
        puppetDesc.label = "Puppet"
        puppetDesc.vertexFunction = library.makeFunction(name: "vertex_puppet")
        puppetDesc.fragmentFunction = library.makeFunction(name: "fragment_main")
        puppetDesc.colorAttachments[0].pixelFormat = hdrFormat
        puppetDesc.colorAttachments[0].isBlendingEnabled = true
        puppetDesc.colorAttachments[0].rgbBlendOperation = .add
        puppetDesc.colorAttachments[0].alphaBlendOperation = .add
        puppetDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        puppetDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        puppetDesc.depthAttachmentPixelFormat = depthFormat
        puppetDesc.stencilAttachmentPixelFormat = depthFormat
        let pvDesc = MTLVertexDescriptor()
        var offset = 0
        pvDesc.attributes[0].format = .float3
        pvDesc.attributes[0].offset = offset
        pvDesc.attributes[0].bufferIndex = 0
        offset += 16
        pvDesc.attributes[1].format = .float2
        pvDesc.attributes[1].offset = offset
        pvDesc.attributes[1].bufferIndex = 0
        offset += 8
        pvDesc.attributes[2].format = .ushort4
        pvDesc.attributes[2].offset = offset
        pvDesc.attributes[2].bufferIndex = 0
        offset += 8
        pvDesc.attributes[3].format = .float4
        pvDesc.attributes[3].offset = offset
        pvDesc.attributes[3].bufferIndex = 0
        offset += 16
        pvDesc.layouts[0].stride = 48
        puppetDesc.vertexDescriptor = pvDesc
        puppetPipelineState = try await device.makeRenderPipelineState(descriptor: puppetDesc, options: []).0

        let particleDesc = MTLRenderPipelineDescriptor()
        particleDesc.label = "TranslucentSprite"
        particleDesc.vertexFunction = library.makeFunction(name: "particle_sprite_vertex")
        particleDesc.fragmentFunction = library.makeFunction(name: "particle_fragment")
        particleDesc.colorAttachments[0].pixelFormat = hdrFormat
        particleDesc.colorAttachments[0].isBlendingEnabled = true
        particleDesc.colorAttachments[0].rgbBlendOperation = .add
        particleDesc.colorAttachments[0].alphaBlendOperation = .add
        particleDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        particleDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        particleDesc.depthAttachmentPixelFormat = depthFormat
        particleDesc.stencilAttachmentPixelFormat = depthFormat
        translucentSpritePipeline = try await device.makeRenderPipelineState(descriptor: particleDesc, options: []).0

        particleDesc.label = "AdditiveSprite"
        particleDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        particleDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        additiveSpritePipeline = try await device.makeRenderPipelineState(descriptor: particleDesc, options: []).0

        particleDesc.label = "TranslucentRope"
        particleDesc.vertexFunction = library.makeFunction(name: "particle_rope_vertex")
        particleDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        particleDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        translucentRopePipeline = try await device.makeRenderPipelineState(descriptor: particleDesc, options: []).0

        particleDesc.label = "AdditiveRope"
        particleDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        particleDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        additiveRopePipeline = try await device.makeRenderPipelineState(descriptor: particleDesc, options: []).0

        let postDesc = MTLRenderPipelineDescriptor()
        postDesc.vertexFunction = library.makeFunction(name: "vertex_post")
        postDesc.colorAttachments[0].pixelFormat = hdrFormat
        postDesc.depthAttachmentPixelFormat = .invalid
        postDesc.stencilAttachmentPixelFormat = .invalid
        postDesc.fragmentFunction = library.makeFunction(name: "fragment_extract")
        extractPipeline = try await device.makeRenderPipelineState(descriptor: postDesc, options: []).0
        postDesc.fragmentFunction = library.makeFunction(name: "fragment_blur")
        blurPipeline = try await device.makeRenderPipelineState(descriptor: postDesc, options: []).0
        postDesc.fragmentFunction = library.makeFunction(name: "fragment_upsample")
        upsamplePipeline = try await device.makeRenderPipelineState(descriptor: postDesc, options: []).0
        postDesc.fragmentFunction = library.makeFunction(name: "fragment_final")
        postDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        postDesc.depthAttachmentPixelFormat = depthFormat
        postDesc.stencilAttachmentPixelFormat = depthFormat
        finalPipeline = try await device.makeRenderPipelineState(descriptor: postDesc, options: []).0

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.normalizedCoordinates = true
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }
}
