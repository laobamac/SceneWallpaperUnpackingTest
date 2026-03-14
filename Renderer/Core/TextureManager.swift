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

        if isEmbedded, let data = firstMipmap?.bytesData {
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                texWidth = cgImage.width
                texHeight = cgImage.height
            }
        }

        if texWidth <= 0 { texWidth = 1 }
        if texHeight <= 0 { texHeight = 1 }

        let isGif = await texFile.header.flags.contains(.isGif)
        let arrayLength = (isGif && !isVideo) ? max(1, texFile.imageContainer.images.count) : 1
        let finalArrayLength = force2D ? 1 : arrayLength
        let isArray = finalArrayLength > 1

        if isEmbedded && !isVideo, let data = firstMipmap?.bytesData {
            let tempTexture = try await loader.newTexture(data: data, options: options)
            
            if !isArray {
                cache[url] = tempTexture
                return tempTexture
            }

            let desc = MTLTextureDescriptor()
            desc.pixelFormat = tempTexture.pixelFormat
            desc.width = tempTexture.width
            desc.height = tempTexture.height
            desc.textureType = .type2DArray
            desc.arrayLength = finalArrayLength
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

        if isVideo {
            pixelFormat = useSRGB ? .bgra8Unorm_srgb : .bgra8Unorm
            bytesPerBlock = 4
            isCompressed = false
            needsCPUExpansion = false
        } else {
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
        }

        let desc = MTLTextureDescriptor()
        desc.pixelFormat = pixelFormat
        desc.width = texWidth
        desc.height = texHeight
        desc.textureType = isArray ? .type2DArray : .type2D
        desc.arrayLength = finalArrayLength
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

        for i in 0..<finalArrayLength {
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
                                expandedData.append(contentsOf: [g, g, g, r])
                            }
                        } else if texFile.header.format == .R8 {
                            for j in 0..<finalData.count {
                                let r = finalData[j]
                                expandedData.append(contentsOf: [r, r, r, r])
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
                                slice: isArray ? i : 0,
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
