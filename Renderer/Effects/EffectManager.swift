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
                    Logger.log("[EffectManager] Loading effect: \(fx.effectName) for object ID: \(obj.id ?? -1)")
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
