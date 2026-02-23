//
//  RenderTargetPool.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import Metal

class RenderTargetPool {
    static let shared = RenderTargetPool()
    
    private var availableTextures: [MTLTexture] = []
    private var inUseTextures: [MTLTexture] = []
    
    func acquire(device: MTLDevice, width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture {
        for (index, texture) in availableTextures.enumerated() {
            if texture.width == width && texture.height == height && texture.pixelFormat == pixelFormat {
                let tex = availableTextures.remove(at: index)
                inUseTextures.append(tex)
                return tex
            }
        }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        
        guard let newTexture = device.makeTexture(descriptor: descriptor) else {
            fatalError()
        }
        inUseTextures.append(newTexture)
        return newTexture
    }
    
    func release(texture: MTLTexture) {
        if let index = inUseTextures.firstIndex(where: { $0 === texture }) {
            inUseTextures.remove(at: index)
            availableTextures.append(texture)
        }
    }
    
    func clear() {
        availableTextures.removeAll()
        inUseTextures.removeAll()
    }
}
