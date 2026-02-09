//
//  TextureManager.swift
//  Renderer
//
//  Created by laobamac on 2026/2/7.
//

import MetalKit
import ImageIO

struct AnimatedTexture {
    let textures: [MTLTexture]
    let delays: [Double]
    let duration: Double
}

actor TextureManager {
    static let shared = TextureManager()
    private var cache: [URL: MTLTexture] = [:]
    private var animatedCache: [URL: AnimatedTexture] = [:]
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
    
    func loadAnimatedTexture(url: URL, device: MTLDevice) async throws -> AnimatedTexture {
        if let cached = animatedCache[url] {
            return cached
        }
        
        Logger.debug("Loading animated texture: \(url.lastPathComponent)")
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            Logger.error("Failed to create image source for \(url.lastPathComponent)")
            throw NSError(domain: "TextureManager", code: 1)
        }
        
        let count = CGImageSourceGetCount(source)
        var textures: [MTLTexture] = []
        var delays: [Double] = []
        var totalDuration: Double = 0
        
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [.SRGB: false, .origin: MTKTextureLoader.Origin.bottomLeft]
        
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            do {
                let texture = try await loader.newTexture(cgImage: cgImage, options: options)
                textures.append(texture)
                
                var delay = 0.1
                if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any] {
                    if let gifProps = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                        if let d = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, d > 0 { delay = d }
                        else if let d = gifProps[kCGImagePropertyGIFDelayTime as String] as? Double, d > 0 { delay = d }
                    } else if let webpProps = props[kCGImagePropertyWebPDictionary as String] as? [String: Any] {
                        if let d = webpProps[kCGImagePropertyWebPUnclampedDelayTime as String] as? Double, d > 0 { delay = d }
                        else if let d = webpProps[kCGImagePropertyWebPDelayTime as String] as? Double, d > 0 { delay = d }
                    }
                }
                delays.append(delay)
                totalDuration += delay
            } catch {
                Logger.error("Failed to load frame \(i) of \(url.lastPathComponent)")
            }
        }
        
        if textures.isEmpty {
             Logger.error("No frames loaded for \(url.lastPathComponent)")
             throw NSError(domain: "TextureManager", code: 2)
        }
        
        Logger.log("Loaded \(textures.count) frames for \(url.lastPathComponent), duration: \(totalDuration)s")
        
        let result = AnimatedTexture(textures: textures, delays: delays, duration: totalDuration)
        animatedCache[url] = result
        return result
    }
    
    func clear() async {
        Logger.log("Clearing texture cache")
        cache.removeAll()
        animatedCache.removeAll()
    }
}
