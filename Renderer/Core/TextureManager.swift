//
//  TextureManager.swift
//  Renderer
//
//  Created by laobamac on 2026/2/7.
//

import MetalKit
import ImageIO
import CoreGraphics

actor TextureManager {
    static let shared = TextureManager()
    private var cache: [URL: MTLTexture] = [:]
    private var frameInfoCache: [URL: [TexFrameInfo]] = [:]
    private var videoUpdaters: [URL: VideoTextureUpdater] = [:]
    private var device: MTLDevice?
    private var loader: MTKTextureLoader?
    private var commandQueue: MTLCommandQueue?

    func setup(device: MTLDevice) async {
        self.device = device
        self.loader = MTKTextureLoader(device: device)
        self.commandQueue = device.makeCommandQueue()
    }

    func frameInfo(for url: URL) -> [TexFrameInfo]? {
        return frameInfoCache[url]
    }

    func loadTexture(
        path: String,
        root: URL,
        options: [MTKTextureLoader.Option: Any]? = nil,
        force2D: Bool = false
    ) async throws -> MTLTexture {
        let texPath = path.hasSuffix(".tex") ? path : path + ".tex"
        let localURL = root.appendingPathComponent(texPath)
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            return try await loadTexture(url: localURL, options: options, force2D: force2D)
        }
        
        var name = path
        if name.hasSuffix(".tex") {
            name = String(name.dropLast(4))
        }
        if name.hasPrefix("materials/") {
            name = String(name.dropFirst(10))
        }

        let searchPaths = [
            "WEAssets/materials/\(name)",
            "WEAssets/\(name)"
        ]
        
        for p in searchPaths {
            if let bundleURL = Bundle.main.url(forResource: p, withExtension: "tex") {
                return try await loadTexture(url: bundleURL, options: options, force2D: force2D)
            }
        }
        
        return try await loadTexture(url: localURL, options: options, force2D: force2D)
    }

    func loadTexture(
        url: URL,
        options: [MTKTextureLoader.Option: Any]? = nil,
        force2D: Bool = false
    ) async throws -> MTLTexture {
        if let cached = cache[url] { return cached }
        guard let device = self.device, let loader = self.loader else {
            throw NSError(domain: "TextureManager", code: 0, userInfo: nil)
        }

        let texFile = try await TexParser.parse(fileURL: url)
        
        if let frames = texFile.frameInfoContainer?.frames {
            frameInfoCache[url] = frames
        }
        
        let firstMipmap = texFile.imageContainer.images.first?.mipmaps.first
        let isEmbedded = (firstMipmap?.format == .imagePNG || firstMipmap?.format == .imageJPEG || firstMipmap?.format == .imageGIF)
        let isVideo = await texFile.header.flags.contains(.isVideoTexture) || firstMipmap?.format == .videoMp4

        var texWidth = Int(texFile.header.textureWidth)
        var texHeight = Int(texFile.header.textureHeight)

        if let mip = firstMipmap {
            texWidth = Int(mip.width)
            texHeight = Int(mip.height)
        }

        if isEmbedded && !isVideo, let data = firstMipmap?.bytesData {
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                texWidth = cgImage.width
                texHeight = cgImage.height
            }
        }

        if texWidth <= 0 { texWidth = 1 }
        if texHeight <= 0 { texHeight = 1 }

        if isEmbedded && !isVideo, let data = firstMipmap?.bytesData {
            let tempTexture = try await loader.newTexture(data: data, options: options)
            
            if force2D {
                cache[url] = tempTexture
                return tempTexture
            }

            let desc = MTLTextureDescriptor()
            desc.pixelFormat = tempTexture.pixelFormat
            desc.width = tempTexture.width
            desc.height = tempTexture.height
            desc.textureType = .type2DArray
            desc.arrayLength = 1
            desc.usage = [.shaderRead]

            guard let arrayTexture = device.makeTexture(descriptor: desc),
                  let cmd = commandQueue?.makeCommandBuffer(),
                  let blit = cmd.makeBlitCommandEncoder() else {
                return tempTexture
            }

            blit.copy(from: tempTexture, sourceSlice: 0, sourceLevel: 0, to: arrayTexture, destinationSlice: 0, destinationLevel: 0, sliceCount: 1, levelCount: 1)
            blit.endEncoding()
            cmd.commit()
            await cmd.completed()
            
            cache[url] = arrayTexture
            return arrayTexture
        }

        var useSRGB = true
        if let options = options, let srgbVal = options[.SRGB] as? Bool {
            useSRGB = srgbVal
        }

        var pixelFormat: MTLPixelFormat = useSRGB ? .rgba8Unorm_srgb : .rgba8Unorm
        var bytesPerBlock = 4
        var isCompressed = false
        var needsCPUExpansion = false

        switch texFile.header.format {
        case .DXT1:
            pixelFormat = useSRGB ? .bc1_rgba_srgb : .bc1_rgba
            bytesPerBlock = 8
            isCompressed = true
        case .DXT3:
            pixelFormat = useSRGB ? .bc2_rgba_srgb : .bc2_rgba
            bytesPerBlock = 16
            isCompressed = true
        case .DXT5:
            pixelFormat = useSRGB ? .bc3_rgba_srgb : .bc3_rgba
            bytesPerBlock = 16
            isCompressed = true
        case .RG88, .R8:
            pixelFormat = useSRGB ? .rgba8Unorm_srgb : .rgba8Unorm
            bytesPerBlock = 4
            needsCPUExpansion = true
        case .RGBA8888:
            pixelFormat = useSRGB ? .rgba8Unorm_srgb : .rgba8Unorm
            bytesPerBlock = 4
        }

        if isVideo {
            pixelFormat = useSRGB ? .bgra8Unorm_srgb : .bgra8Unorm
            bytesPerBlock = 4
            isCompressed = false
            needsCPUExpansion = false
        }

        let arrayLength = await (texFile.header.flags.contains(.isGif) && !isVideo) ? max(1, texFile.imageContainer.images.count) : 1

        let desc = MTLTextureDescriptor()
        desc.pixelFormat = pixelFormat
        desc.width = texWidth
        desc.height = texHeight
        desc.textureType = force2D ? .type2D : .type2DArray
        desc.arrayLength = force2D ? 1 : arrayLength
        desc.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: desc) else {
            throw NSError(domain: "TextureManager", code: 1, userInfo: nil)
        }

        if isVideo {
            if let mipmap = firstMipmap {
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mp4")
                try? mipmap.bytesData.write(to: tempURL)
                let updater = await VideoTextureUpdater(url: tempURL, texture: texture)
                videoUpdaters[url] = updater
            }
            cache[url] = texture
            return texture
        }

        for i in 0..<arrayLength {
            if i < texFile.imageContainer.images.count {
                let image = texFile.imageContainer.images[i]
                if let mipmap = image.mipmaps.first {
                    var bytesPerRow = 0
                    var bytesPerImage = 0
                    var finalData = mipmap.bytesData

                    if needsCPUExpansion {
                        var expandedData = Data(capacity: texWidth * texHeight * 4)
                        if texFile.header.format == .RG88 {
                            for j in stride(from: 0, to: finalData.count - 1, by: 2) {
                                let r = finalData[j]
                                let g = finalData[j+1]
                                expandedData.append(contentsOf: [r, g, 0, 255])
                            }
                        } else if texFile.header.format == .R8 {
                            for j in 0..<finalData.count {
                                let r = finalData[j]
                                expandedData.append(contentsOf: [r, r, r, 255])
                            }
                        }
                        finalData = expandedData
                        bytesPerRow = texWidth * 4
                        bytesPerImage = bytesPerRow * texHeight
                    } else if isCompressed {
                        let blocksPerRow = (texWidth + 3) / 4
                        let blocksPerCol = (texHeight + 3) / 4
                        bytesPerRow = blocksPerRow * bytesPerBlock
                        bytesPerImage = bytesPerRow * blocksPerCol
                    } else {
                        bytesPerRow = texWidth * bytesPerBlock
                        bytesPerImage = bytesPerRow * texHeight
                    }
                    
                    if finalData.count < bytesPerImage {
                        finalData.append(Data(count: bytesPerImage - finalData.count))
                    }
                    
                    finalData.withUnsafeBytes { ptr in
                        if let baseAddress = ptr.baseAddress {
                            let region = MTLRegionMake2D(0, 0, texWidth, texHeight)
                            texture.replace(
                                region: region,
                                mipmapLevel: 0,
                                slice: force2D ? 0 : i,
                                withBytes: baseAddress,
                                bytesPerRow: bytesPerRow,
                                bytesPerImage: bytesPerImage
                            )
                        }
                    }
                }
            }
        }

        cache[url] = texture
        return texture
    }

    func clear() async {
        for updater in videoUpdaters.values {
            await updater.stop()
        }
        videoUpdaters.removeAll()
        cache.removeAll()
        frameInfoCache.removeAll()
    }
}
