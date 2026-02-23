//
//  EffectInstance.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import Metal

class EffectInstance {
    let name: String
    let config: EffectConfig
    var activeFBOs: [String: MTLTexture] = [:]
    var evaluatedUniforms: [String: [Float]] = [:]
    var instanceTime: Float = 0.0
    
    init(name: String, config: EffectConfig) {
        self.name = name
        self.config = config
    }
    
    func allocateUniqueFBOs(device: MTLDevice, baseWidth: Int, baseHeight: Int, defaultFormat: MTLPixelFormat) {
        guard let fbos = config.fbos else { return }
        for fbo in fbos {
            if fbo.unique == true {
                let scale = fbo.scale ?? 1.0
                let formatStr = fbo.format ?? "rgba8888"
                let format = parseFormat(formatStr, defaultFormat: defaultFormat)
                let tex = FBOManager.shared.acquire(device: device, width: baseWidth, height: baseHeight, pixelFormat: format, scale: scale)
                activeFBOs[fbo.name] = tex
            }
        }
    }
    
    func releaseUniqueFBOs() {
        for (_, tex) in activeFBOs {
            FBOManager.shared.release(texture: tex)
        }
        activeFBOs.removeAll()
    }
    
    func updateTime(deltaTime: Float) {
        instanceTime += deltaTime
    }
    
    private func parseFormat(_ formatString: String, defaultFormat: MTLPixelFormat) -> MTLPixelFormat {
        switch formatString.lowercased() {
        case "rgba8888": return .bgra8Unorm
        case "rgba16f": return .rgba16Float
        case "rgba32f": return .rgba32Float
        case "r8": return .r8Unorm
        case "rg88": return .rg8Unorm
        default: return defaultFormat
        }
    }
}
