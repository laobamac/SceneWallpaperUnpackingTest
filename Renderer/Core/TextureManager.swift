//
//  TextureManager.swift
//  Renderer
//
//  Created by laobamac on 2026/2/7.
//

import ImageIO
import MetalKit

actor TextureManager {
    static let shared = TextureManager()
    private var cache: [URL: MTLTexture] = [:]
    private var loader: MTKTextureLoader?

    func setup(device: MTLDevice) async {
        if loader == nil {
            loader = MTKTextureLoader(device: device)
            await Logger.log("TextureManager initialized")
        }
    }

    func loadTexture(url: URL, options: [MTKTextureLoader.Option: Any]? = nil, force2D: Bool = false)
        async throws -> MTLTexture
    {
        if let cached = cache[url] { return cached }
        guard let loader = loader else {
            let err = NSError(domain: "TextureManager", code: 0)
            await Logger.error("TextureManager not ready")
            throw err
        }

        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        if let src = source, CGImageSourceGetCount(src) > 1 {
            return try await loadWebPTextureArray(
                url: url,
                device: loader.device
            )
        }

        await Logger.log(
            "加载截图纹理: \(url.lastPathComponent) 从 \(url.path)"
        )
        do {
            let tempTexture = try await loader.newTexture(
                URL: url,
                options: options
            )
            
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

            guard let arrayTexture = loader.device.makeTexture(descriptor: desc)
            else {
                throw NSError(domain: "TextureManager", code: 5)
            }

            if let cmd = loader.device.makeCommandQueue()?.makeCommandBuffer(),
                let blit = cmd.makeBlitCommandEncoder()
            {
                blit.copy(
                    from: tempTexture,
                    sourceSlice: 0,
                    sourceLevel: 0,
                    to: arrayTexture,
                    destinationSlice: 0,
                    destinationLevel: 0,
                    sliceCount: 1,
                    levelCount: 1
                )
                blit.endEncoding()
                cmd.commit()
                await cmd.completed()
            }

            await Logger.log(
                "成功加载静态纹理: \(url.lastPathComponent)"
            )
            cache[url] = arrayTexture
            return arrayTexture
        } catch {
            await Logger.error(
                "加载纹理失败 \(url.lastPathComponent): \(error)"
            )
            throw error
        }
    }

    func loadWebPTextureArray(url: URL, device: MTLDevice) async throws
        -> MTLTexture
    {
        if let cached = cache[url] { return cached }
        await Logger.log(
            "加载WebP动态图集: \(url.lastPathComponent) 从 \(url.path)"
        )

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw NSError(domain: "TextureManager", code: 1)
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            throw NSError(domain: "TextureManager", code: 2)
        }

        guard let firstImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw NSError(domain: "TextureManager", code: 3)
        }

        let width = firstImage.width
        let height = firstImage.height

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .bgra8Unorm_srgb
        descriptor.width = width
        descriptor.height = height
        descriptor.textureType = .type2DArray
        descriptor.arrayLength = count
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "TextureManager", code: 4)
        }

        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )

        for i in 0..<count {
            if let image = CGImageSourceCreateImageAtIndex(source, i, nil) {
                context?.clear(CGRect(x: 0, y: 0, width: width, height: height))
                context?.draw(
                    image,
                    in: CGRect(x: 0, y: 0, width: width, height: height)
                )

                if let data = context?.data {
                    let bytesPerRow = context!.bytesPerRow
                    texture.replace(
                        region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        slice: i,
                        withBytes: data,
                        bytesPerRow: bytesPerRow,
                        bytesPerImage: bytesPerRow * height
                    )
                }
            }
        }

        await Logger.log(
            "成功加载WebP动态图集: \(url.lastPathComponent) (\(count) 帧)"
        )
        cache[url] = texture
        return texture
    }

    func clear() async {
        await Logger.log("清空纹理缓存")
        cache.removeAll()
    }
}
