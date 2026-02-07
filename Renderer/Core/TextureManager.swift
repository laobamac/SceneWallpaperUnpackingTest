//
//  TextureManager.swift
//  Renderer
//
//  Created by laobamac on 2026/2/7.
//

import MetalKit

actor TextureManager {
    static let shared = TextureManager()
    private var cache: [URL: MTLTexture] = [:]
    private var loader: MTKTextureLoader?
    
    func setup(device: MTLDevice) {
        if loader == nil {
            loader = MTKTextureLoader(device: device)
        }
    }
    
    func loadTexture(url: URL, options: [MTKTextureLoader.Option: Any]? = nil) async throws -> MTLTexture {
        if let cached = cache[url] {
            Logger.debug("Texture cache hit: \(url.lastPathComponent)")
            return cached
        }
        
        guard let loader = loader else {
            let err = NSError(domain: "TextureManager", code: 0, userInfo: nil)
            Logger.error("TextureManager not initialized")
            throw err
        }
        
        Logger.log("Loading texture: \(url.lastPathComponent)")
        do {
            let texture = try await loader.newTexture(URL: url, options: options)
            cache[url] = texture
            Logger.log("Successfully loaded texture: \(url.lastPathComponent) (\(texture.width)x\(texture.height))")
            return texture
        } catch {
            Logger.error("Failed to load texture \(url.lastPathComponent): \(error)")
            throw error
        }
    }
    
    func clear() {
        Logger.log("Clearing texture cache")
        cache.removeAll()
    }
}
