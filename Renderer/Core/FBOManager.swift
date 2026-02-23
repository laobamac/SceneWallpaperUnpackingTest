//
//  FBOManager.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import Metal

class FBOManager {
    static let shared = FBOManager()
    
    private var availableTextures: [String: [MTLTexture]] = [:]
    private var inUseTextures: [MTLTexture] = []
    private var namedFBOs: [String: MTLTexture] = [:]
    
    func acquire(device: MTLDevice, width: Int, height: Int, pixelFormat: MTLPixelFormat, scale: Float = 1.0) -> MTLTexture {
        let actualWidth = max(1, Int(Float(width) * scale))
        let actualHeight = max(1, Int(Float(height) * scale))
        let key = "\(actualWidth)x\(actualHeight)_\(pixelFormat.rawValue)"
        
        if var textures = availableTextures[key], !textures.isEmpty {
            let tex = textures.removeLast()
            availableTextures[key] = textures
            inUseTextures.append(tex)
            return tex
        }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: actualWidth,
            height: actualHeight,
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
    
    func registerNamedFBO(name: String, texture: MTLTexture) {
        namedFBOs[name] = texture
    }
    
    func getNamedFBO(name: String) -> MTLTexture? {
        return namedFBOs[name]
    }
    
    func release(texture: MTLTexture) {
        if let index = inUseTextures.firstIndex(where: { $0 === texture }) {
            inUseTextures.remove(at: index)
            let key = "\(texture.width)x\(texture.height)_\(texture.pixelFormat.rawValue)"
            if availableTextures[key] == nil {
                availableTextures[key] = []
            }
            availableTextures[key]?.append(texture)
        }
    }
    
    func releaseNamedFBO(name: String) {
        if let tex = namedFBOs.removeValue(forKey: name) {
            release(texture: tex)
        }
    }
    
    func clear() {
        availableTextures.removeAll()
        inUseTextures.removeAll()
        namedFBOs.removeAll()
    }
}
