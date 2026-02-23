//
//  RenderGraph.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import Metal

class RenderGraph {
    static let shared = RenderGraph()
    
    func execute(
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice,
        effectInstance: EffectInstance,
        baseInput: MTLTexture,
        baseOutput: MTLTexture,
        uniformContext: UniformContext,
        vertexBuffer: MTLBuffer,
        texCoordBuffer: MTLBuffer,
        vertexCount: Int
    ) {
        guard let passes = effectInstance.config.passes else { return }
        
        var currentInput = baseInput
        var currentOutput = baseOutput
        
        for (index, pass) in passes.enumerated() {
            if let command = pass.command {
                if command == "copy" || command == "swap" {
                    handleCommand(
                        command: command,
                        sourceName: pass.source,
                        targetName: pass.target,
                        effectInstance: effectInstance,
                        commandBuffer: commandBuffer
                    )
                    continue
                }
            }
            
            guard let materialPath = pass.material else { continue }
            guard let materialConfig = loadMaterialConfig(path: materialPath) else { continue }
            guard let materialPass = materialConfig.passes?.first else { continue }
            guard let shaderName = materialPass.shader else { continue }
            
            let resolvedTarget = resolveOutputTexture(
                targetName: pass.target,
                effectInstance: effectInstance,
                fallback: currentOutput
            )
            
            var boundTextures: [Int: MTLTexture] = [:]
            boundTextures[0] = currentInput
            
            if let binds = pass.binds {
                for bind in binds {
                    if let tex = resolveInputTexture(name: bind.name, effectInstance: effectInstance) {
                        boundTextures[bind.index] = tex
                    }
                }
            }
            
            if let materialTextures = materialPass.textures {
                for (i, texPath) in materialTextures.enumerated() {
                    let actualIndex = i + 1
                    if boundTextures[actualIndex] == nil {
                        if let tex = TextureManager.shared.getTexture(named: texPath) {
                            boundTextures[actualIndex] = tex
                        }
                    }
                }
            }
            
            let combinedUniforms = uniformContext.collectUniforms(
                materialConstants: materialPass.constantshadervalues,
                evaluatedInstanceUniforms: effectInstance.evaluatedUniforms
            )
            
            PassExecutor.execute(
                commandBuffer: commandBuffer,
                device: device,
                shaderName: shaderName,
                materialPass: materialPass,
                combinedUniforms: combinedUniforms,
                boundTextures: boundTextures,
                outputTexture: resolvedTarget,
                vertexBuffer: vertexBuffer,
                texCoordBuffer: texCoordBuffer,
                vertexCount: vertexCount
            )
            
            if pass.target == nil {
                currentInput = currentOutput
            }
        }
    }
    
    private func handleCommand(command: String, sourceName: String?, targetName: String?, effectInstance: EffectInstance, commandBuffer: MTLCommandBuffer) {
        guard let src = sourceName, let tgt = targetName else { return }
        guard let srcTex = resolveInputTexture(name: src, effectInstance: effectInstance) else { return }
        guard let tgtTex = resolveOutputTexture(targetName: tgt, effectInstance: effectInstance, fallback: srcTex) else { return }
        
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
        blitEncoder.copy(from: srcTex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOriginMake(0, 0, 0), sourceSize: MTLSizeMake(srcTex.width, srcTex.height, 1), to: tgtTex, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOriginMake(0, 0, 0))
        blitEncoder.endEncoding()
    }
    
    private func resolveInputTexture(name: String, effectInstance: EffectInstance) -> MTLTexture? {
        if name == "previous" { return nil }
        if let tex = effectInstance.activeFBOs[name] { return tex }
        if let tex = FBOManager.shared.getNamedFBO(name: name) { return tex }
        return TextureManager.shared.getTexture(named: name)
    }
    
    private func resolveOutputTexture(targetName: String?, effectInstance: EffectInstance, fallback: MTLTexture) -> MTLTexture {
        guard let name = targetName else { return fallback }
        if let tex = effectInstance.activeFBOs[name] { return tex }
        if let tex = FBOManager.shared.getNamedFBO(name: name) { return tex }
        return fallback
    }
    
    private func loadMaterialConfig(path: String) -> MaterialConfig? {
        return nil
    }
}
