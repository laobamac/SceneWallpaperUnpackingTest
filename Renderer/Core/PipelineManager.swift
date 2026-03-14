//
//  PipelineManager.swift
//  Renderer
//
//  Created by laobamac on 2026/3/13.
//

import Foundation
import MetalKit

class PipelineManager {
    let device: MTLDevice
    let library: MTLLibrary
    
    var pipelines: [Int: MTLRenderPipelineState] = [:]
    var puppetPipelines: [Int: MTLRenderPipelineState] = [:]
    
    var spriteParticlePipelines: [Int: MTLRenderPipelineState] = [:]
    var ropeParticlePipelines: [Int: MTLRenderPipelineState] = [:]
    
    var puppetMaskPipelineState: MTLRenderPipelineState?
    var finalPipeline: MTLRenderPipelineState?
    var extractPipeline: MTLRenderPipelineState?
    var blurPipeline: MTLRenderPipelineState?
    var upsamplePipeline: MTLRenderPipelineState?
    
    var depthStencilState: MTLDepthStencilState?
    var depthWriteDisabledState: MTLDepthStencilState?
    var maskWriteState: MTLDepthStencilState?
    var maskTestState: MTLDepthStencilState?
    
    var samplerState: MTLSamplerState?

    init(device: MTLDevice) {
        self.device = device
        guard let lib = device.makeDefaultLibrary() else {
            fatalError("Failed to load default library")
        }
        self.library = lib
    }

    func setupPipelines() async throws {
        try setupBasicPipelines()
        try setupPuppetPipelines()
        try setupParticlePipelines()
        try setupPostProcessPipelines()
        setupDepthStencilStates()
        setupSamplers()
    }

    private func makeFunction(name: String) throws -> MTLFunction {
        guard let function = library.makeFunction(name: name) else {
            throw NSError(domain: "PipelineManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Shader function '\(name)' not found in library"])
        }
        return function
    }

    private func setupBasicPipelines() throws {
        guard let vertex = try? makeFunction(name: "vertexShader"),
              let fragment = try? makeFunction(name: "fragmentShader") else { return }
              
        for blendMode in 0...2 {
            let desc = MTLRenderPipelineDescriptor()
            desc.colorAttachments[0].pixelFormat = .rgba16Float
            desc.depthAttachmentPixelFormat = .depth32Float_stencil8
            desc.stencilAttachmentPixelFormat = .depth32Float_stencil8
            desc.vertexFunction = vertex
            desc.fragmentFunction = fragment
            configureBlendMode(desc.colorAttachments[0], mode: blendMode)
            pipelines[blendMode] = try device.makeRenderPipelineState(descriptor: desc)
        }
    }

    private func setupPuppetPipelines() throws {
        let v = try makeFunction(name: "puppetVertex")
        let f = try makeFunction(name: "puppetFragment")
        
        for blendMode in 0...2 {
            let desc = MTLRenderPipelineDescriptor()
            desc.colorAttachments[0].pixelFormat = .rgba16Float
            desc.depthAttachmentPixelFormat = .depth32Float_stencil8
            desc.stencilAttachmentPixelFormat = .depth32Float_stencil8
            desc.vertexFunction = v
            desc.fragmentFunction = f
            configureBlendMode(desc.colorAttachments[0], mode: blendMode)
            puppetPipelines[blendMode] = try device.makeRenderPipelineState(descriptor: desc)
        }
        
        let maskDesc = MTLRenderPipelineDescriptor()
        maskDesc.colorAttachments[0].pixelFormat = .rgba16Float
        maskDesc.depthAttachmentPixelFormat = .depth32Float_stencil8
        maskDesc.stencilAttachmentPixelFormat = .depth32Float_stencil8
        maskDesc.vertexFunction = try makeFunction(name: "puppetMaskVertex")
        maskDesc.fragmentFunction = try makeFunction(name: "puppetMaskFragment")
        maskDesc.colorAttachments[0].isBlendingEnabled = false
        puppetMaskPipelineState = try device.makeRenderPipelineState(descriptor: maskDesc)
    }

    private func setupParticlePipelines() throws {
        let spriteVertexDescriptor = MTLVertexDescriptor()
        spriteVertexDescriptor.attributes[0].format = .float3
        spriteVertexDescriptor.attributes[0].offset = 0
        spriteVertexDescriptor.attributes[0].bufferIndex = 0
        spriteVertexDescriptor.attributes[1].format = .float4
        spriteVertexDescriptor.attributes[1].offset = 16
        spriteVertexDescriptor.attributes[1].bufferIndex = 0
        spriteVertexDescriptor.attributes[2].format = .float4
        spriteVertexDescriptor.attributes[2].offset = 32
        spriteVertexDescriptor.attributes[2].bufferIndex = 0
        spriteVertexDescriptor.attributes[3].format = .float4
        spriteVertexDescriptor.attributes[3].offset = 48
        spriteVertexDescriptor.attributes[3].bufferIndex = 0
        spriteVertexDescriptor.attributes[4].format = .float2
        spriteVertexDescriptor.attributes[4].offset = 64
        spriteVertexDescriptor.attributes[4].bufferIndex = 0
        spriteVertexDescriptor.layouts[0].stride = 80
        spriteVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        let ropeVertexDescriptor = MTLVertexDescriptor()
        ropeVertexDescriptor.attributes[0].format = .float4
        ropeVertexDescriptor.attributes[0].offset = 0
        ropeVertexDescriptor.attributes[0].bufferIndex = 0
        ropeVertexDescriptor.attributes[1].format = .float4
        ropeVertexDescriptor.attributes[1].offset = 16
        ropeVertexDescriptor.attributes[1].bufferIndex = 0
        ropeVertexDescriptor.attributes[2].format = .float4
        ropeVertexDescriptor.attributes[2].offset = 32
        ropeVertexDescriptor.attributes[2].bufferIndex = 0
        ropeVertexDescriptor.attributes[3].format = .float4
        ropeVertexDescriptor.attributes[3].offset = 48
        ropeVertexDescriptor.attributes[3].bufferIndex = 0
        ropeVertexDescriptor.attributes[4].format = .float4
        ropeVertexDescriptor.attributes[4].offset = 64
        ropeVertexDescriptor.attributes[4].bufferIndex = 0
        ropeVertexDescriptor.attributes[5].format = .float2
        ropeVertexDescriptor.attributes[5].offset = 80
        ropeVertexDescriptor.attributes[5].bufferIndex = 0
        ropeVertexDescriptor.attributes[6].format = .float4
        ropeVertexDescriptor.attributes[6].offset = 96
        ropeVertexDescriptor.attributes[6].bufferIndex = 0
        ropeVertexDescriptor.layouts[0].stride = 112
        ropeVertexDescriptor.layouts[0].stepFunction = .perVertex

        let sv = try makeFunction(name: "spriteParticleVertex")
        let rv = try makeFunction(name: "ropeParticleVertex")
        let pf = try makeFunction(name: "particleFragment")

        for blendMode in 0...2 {
            let spriteDesc = MTLRenderPipelineDescriptor()
            spriteDesc.colorAttachments[0].pixelFormat = .rgba16Float
            spriteDesc.depthAttachmentPixelFormat = .depth32Float_stencil8
            spriteDesc.stencilAttachmentPixelFormat = .depth32Float_stencil8
            spriteDesc.vertexFunction = sv
            spriteDesc.fragmentFunction = pf
            spriteDesc.vertexDescriptor = spriteVertexDescriptor
            configureBlendMode(spriteDesc.colorAttachments[0], mode: blendMode)
            spriteParticlePipelines[blendMode] = try device.makeRenderPipelineState(descriptor: spriteDesc)
            
            let ropeDesc = MTLRenderPipelineDescriptor()
            ropeDesc.colorAttachments[0].pixelFormat = .rgba16Float
            ropeDesc.depthAttachmentPixelFormat = .depth32Float_stencil8
            ropeDesc.stencilAttachmentPixelFormat = .depth32Float_stencil8
            ropeDesc.vertexFunction = rv
            ropeDesc.fragmentFunction = pf
            ropeDesc.vertexDescriptor = ropeVertexDescriptor
            configureBlendMode(ropeDesc.colorAttachments[0], mode: blendMode)
            ropeParticlePipelines[blendMode] = try device.makeRenderPipelineState(descriptor: ropeDesc)
        }
    }

    private func setupPostProcessPipelines() throws {
        let qv = try makeFunction(name: "quadVertex")
        
        let finalDesc = MTLRenderPipelineDescriptor()
        finalDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        finalDesc.vertexFunction = qv
        finalDesc.fragmentFunction = try makeFunction(name: "finalFragment")
        finalPipeline = try device.makeRenderPipelineState(descriptor: finalDesc)
        
        let extractDesc = MTLRenderPipelineDescriptor()
        extractDesc.colorAttachments[0].pixelFormat = .rgba16Float
        extractDesc.vertexFunction = qv
        extractDesc.fragmentFunction = try makeFunction(name: "extractBloomFragment")
        extractPipeline = try device.makeRenderPipelineState(descriptor: extractDesc)
        
        let blurDesc = MTLRenderPipelineDescriptor()
        blurDesc.colorAttachments[0].pixelFormat = .rgba16Float
        blurDesc.vertexFunction = qv
        blurDesc.fragmentFunction = try makeFunction(name: "gaussianBlurFragment")
        blurPipeline = try device.makeRenderPipelineState(descriptor: blurDesc)
        
        let upsampleDesc = MTLRenderPipelineDescriptor()
        upsampleDesc.colorAttachments[0].pixelFormat = .rgba16Float
        upsampleDesc.vertexFunction = qv
        upsampleDesc.fragmentFunction = try makeFunction(name: "upsampleFragment")
        
        if let upAtt = upsampleDesc.colorAttachments[0] {
            upAtt.isBlendingEnabled = true
            upAtt.sourceRGBBlendFactor = .one
            upAtt.destinationRGBBlendFactor = .one
            upAtt.rgbBlendOperation = .add
            upAtt.sourceAlphaBlendFactor = .one
            upAtt.destinationAlphaBlendFactor = .one
            upAtt.alphaBlendOperation = .add
        }
        
        upsamplePipeline = try device.makeRenderPipelineState(descriptor: upsampleDesc)
    }

    func setupDepthStencilStates() {
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)
        
        let noWriteDesc = MTLDepthStencilDescriptor()
        noWriteDesc.depthCompareFunction = .lessEqual
        noWriteDesc.isDepthWriteEnabled = false
        depthWriteDisabledState = device.makeDepthStencilState(descriptor: noWriteDesc)
        
        let maskWriteDesc = MTLDepthStencilDescriptor()
        maskWriteDesc.depthCompareFunction = .always
        maskWriteDesc.isDepthWriteEnabled = false
        let frontFace = MTLStencilDescriptor()
        frontFace.stencilCompareFunction = .always
        frontFace.stencilFailureOperation = .replace
        frontFace.depthFailureOperation = .replace
        frontFace.depthStencilPassOperation = .replace
        maskWriteDesc.frontFaceStencil = frontFace
        maskWriteDesc.backFaceStencil = frontFace
        maskWriteState = device.makeDepthStencilState(descriptor: maskWriteDesc)
        
        let maskTestDesc = MTLDepthStencilDescriptor()
        maskTestDesc.depthCompareFunction = .lessEqual
        maskTestDesc.isDepthWriteEnabled = true
        let testFace = MTLStencilDescriptor()
        testFace.stencilCompareFunction = .equal
        testFace.stencilFailureOperation = .keep
        testFace.depthFailureOperation = .keep
        testFace.depthStencilPassOperation = .keep
        maskTestDesc.frontFaceStencil = testFace
        maskTestDesc.backFaceStencil = testFace
        maskTestState = device.makeDepthStencilState(descriptor: maskTestDesc)
    }

    private func setupSamplers() {
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .linear
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }

    private func configureBlendMode(_ attachment: MTLRenderPipelineColorAttachmentDescriptor, mode: Int) {
        attachment.isBlendingEnabled = true
        if mode == 1 {
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .one
            attachment.rgbBlendOperation = .add
            attachment.sourceAlphaBlendFactor = .sourceAlpha
            attachment.destinationAlphaBlendFactor = .one
            attachment.alphaBlendOperation = .add
        } else {
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.rgbBlendOperation = .add
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            attachment.alphaBlendOperation = .add
        }
    }

    func getPipeline(isPuppet: Bool, blendMode: Int) -> MTLRenderPipelineState? {
        if isPuppet {
            return puppetPipelines[blendMode] ?? puppetPipelines[0]
        } else {
            return pipelines[blendMode] ?? pipelines[0]
        }
    }
    
    func getParticlePipeline(isRope: Bool, blendMode: Int) -> MTLRenderPipelineState? {
        if isRope {
            return ropeParticlePipelines[blendMode] ?? ropeParticlePipelines[0]
        } else {
            return spriteParticlePipelines[blendMode] ?? spriteParticlePipelines[0]
        }
    }
}
