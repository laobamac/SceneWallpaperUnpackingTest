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
    var uniforms: [String: UniformConfig]
    var maskTextures: [MTLTexture] = []
    
    init(name: String, uniforms: [String: UniformConfig]) {
        self.name = name
        self.uniforms = uniforms
    }
    
    func loadMasks(device: MTLDevice, basePath: URL, config: EffectConfig?) {
        guard let config = config, let passes = config.passes else { return }
        
        for pass in passes {
            // WE effects often load masks implicitly via uniform textures or predefined naming
            // Here we map any uniform that is a texture to a mask loading process
        }
    }
}
