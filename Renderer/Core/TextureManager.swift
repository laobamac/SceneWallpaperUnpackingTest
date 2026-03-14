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
        await Logger.log("TextureManager initialized")
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
            await Logger.error("TextureManager 尚未初始化")
            throw NSError(domain: "TextureManager", code: 0, userInfo: nil)
        }

        await Logger.log("加载纹理: \(url.lastPathComponent) 从 \(url.path)")

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

        let formatName = String(describing: texFile.header.format)
        let isGif = await texFile.header.flags.contains(.isGif)
        let typeString = isVideo ? "视频纹理" : (isGif ? "动画图集" : "静态贴图")
        let embedStr = isVideo ? "MP4 视频流" : (isEmbedded ? "内嵌 \(firstMipmap?.format ?? .invalid)" : "原生 \(formatName)")
        await Logger.log("  => 详情: [\(typeString)] 渲染尺寸:\(texWidth)x\(texHeight), 格式:\(embedStr), 容器V\(texFile.imageContainer.version.rawValue)")

        if isEmbedded && !isVideo, let data = firstMipmap?.bytesData {
            await Logger.debug("  => 处理内嵌格式图像数据，大小: \(data.count) 字节")
            let tempTexture = try await loader.newTexture(data: data, options: options)
            
            if force2D {
                cache[url] = tempTexture
                await Logger.log("  => 成功加载强制 2D 纹理: \(url.lastPathComponent)")
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
                await Logger.error("  => 生成纹理数组失败，返回降级 2D 纹理")
                return tempTexture
            }

            blit.copy(from: tempTexture, sourceSlice: 0, sourceLevel: 0, to: arrayTexture, destinationSlice: 0, destinationLevel: 0, sliceCount: 1, levelCount: 1)
            blit.endEncoding()
            cmd.commit()
            await cmd.completed()
            
            await Logger.log("  => 成功加载并转换内嵌纹理为数组: \(url.lastPathComponent)")
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

        let arrayLength = (isGif && !isVideo) ? max(1, texFile.imageContainer.images.count) : 1
        await Logger.debug("  => 分配纹理描述符: Format=\(pixelFormat), isCompressed=\(isCompressed), needsCPUExpansion=\(needsCPUExpansion), ArrayLength=\(arrayLength)")

        let desc = MTLTextureDescriptor()
        desc.pixelFormat = pixelFormat
        desc.width = texWidth
        desc.height = texHeight
        desc.textureType = force2D ? .type2D : .type2DArray
        desc.arrayLength = force2D ? 1 : arrayLength
        desc.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: desc) else {
            await Logger.log("  => 生成纹理对象失败: \(url.lastPathComponent)")
            throw NSError(domain: "TextureManager", code: 1, userInfo: nil)
        }

        if isVideo {
            if let mipmap = firstMipmap {
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mp4")
                try? mipmap.bytesData.write(to: tempURL)
                let updater = await VideoTextureUpdater(url: tempURL, texture: texture)
                videoUpdaters[url] = updater
                await Logger.log("  => 开始后台解码视频: \(url.lastPathComponent), 写入临时路径: \(tempURL.path)")
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
                        await Logger.debug("  => 正在 CPU 端扩展单/双通道数据")
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
                        await Logger.debug("  => 数据长度不足(\(finalData.count) < \(bytesPerImage)), 进行补齐")
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

        await Logger.log("  => 成功加载纹理: \(url.lastPathComponent)")
        cache[url] = texture
        return texture
    }

    func clear() async {
        await Logger.log("清空纹理缓存")
        for updater in videoUpdaters.values {
            await updater.stop()
        }
        videoUpdaters.removeAll()
        cache.removeAll()
        frameInfoCache.removeAll()
    }
}
