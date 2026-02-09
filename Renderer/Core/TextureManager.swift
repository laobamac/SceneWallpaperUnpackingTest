//
//  TextureManager.swift
//  Renderer
//
//  Created by laobamac on 2026/2/7.
//

import MetalKit
import ImageIO

actor TextureManager {
    static let shared = TextureManager()
    private var cache: [URL: MTLTexture] = [:]
    private var loader: MTKTextureLoader?
    
    func setup(device: MTLDevice) {
        if loader == nil {
            loader = MTKTextureLoader(device: device)
            Logger.log("TextureManager initialized")
        }
    }
    
    func loadTexture(url: URL, options: [MTKTextureLoader.Option: Any]? = nil) async throws -> MTLTexture {
        if let cached = cache[url] {
            return cached
        }
        guard let loader = loader else {
            let err = NSError(domain: "TextureManager", code: 0)
            Logger.error("TextureManager not ready")
            throw err
        }
        
        do {
            Logger.debug("Loading texture: \(url.lastPathComponent)")
            let texture = try await loader.newTexture(URL: url, options: options)
            cache[url] = texture
            return texture
        } catch {
            Logger.error("Failed to load texture \(url.lastPathComponent): \(error)")
            throw error
        }
    }
    
    func clear() async {
        Logger.log("Clearing texture cache")
        cache.removeAll()
    }
}
