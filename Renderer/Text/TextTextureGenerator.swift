//
//  TextTextureGenerator.swift
//  Renderer
//
//  Created by laobamac on 2026/3/7.
//

import Foundation
import MetalKit
import CoreText
import AppKit

class TextTextureGenerator {
    let device: MTLDevice
    private var registeredFonts: Set<URL> = []
    
    init(device: MTLDevice) {
        self.device = device
        Logger.log("[TextTextureGenerator] 初始化")
    }
    
    deinit {
        for url in registeredFonts {
            Logger.log("[TextTextureGenerator] 注销字体: \(url.lastPathComponent)")
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    
    func registerFont(at url: URL) -> String? {
        if registeredFonts.contains(url) {
            return getFontName(from: url)
        }
        
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            registeredFonts.insert(url)
            let name = getFontName(from: url)
            Logger.log("[TextTextureGenerator] 成功注册字体: \(url.lastPathComponent), 字体名称: \(name ?? "Unknown")")
            return name
        }
        Logger.log("[TextTextureGenerator] 注册字体失败: \(url.lastPathComponent)")
        return nil
    }
    
    private func getFontName(from url: URL) -> String? {
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(dataProvider),
              let postScriptName = cgFont.postScriptName else {
            return nil
        }
        return postScriptName as String
    }
    
    func generateTexture(text: String, fontName: String?, fontSize: Float, bounds: CGSize, horizontalAlign: String?, verticalAlign: String?) -> MTLTexture? {
        Logger.log("[TextTextureGenerator] 准备生成纹理 - 文本: [\(text)] 字体: [\(fontName ?? "System")] 大小: \(fontSize) 边界: \(bounds.width)x\(bounds.height)")
        
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white
        ]
        
        if let name = fontName, let nsFont = NSFont(name: name, size: CGFloat(fontSize)) {
            attributes[.font] = nsFont
        } else {
            attributes[.font] = NSFont.systemFont(ofSize: CGFloat(fontSize))
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        switch horizontalAlign {
        case "left": paragraphStyle.alignment = .left
        case "right": paragraphStyle.alignment = .right
        default: paragraphStyle.alignment = .center
        }
        
        let tightLineHeight = CGFloat(fontSize) * 0.95
        paragraphStyle.minimumLineHeight = tightLineHeight
        paragraphStyle.maximumLineHeight = tightLineHeight
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        attributes[.paragraphStyle] = paragraphStyle
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let constraintSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let textRect = attributedString.boundingRect(with: constraintSize, options: [.usesLineFragmentOrigin, .usesFontLeading])
        
        let width = max(1, Int(ceil(max(bounds.width, textRect.width))))
        let height = max(1, Int(ceil(max(bounds.height, textRect.height))))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            Logger.log("[TextTextureGenerator] 创建 CGContext 失败")
            return nil
        }
        
        context.clear(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        
        var drawY: CGFloat = 0
        switch verticalAlign {
        case "top":
            drawY = 0
        case "bottom":
            drawY = CGFloat(height) - textRect.height
        default:
            drawY = (CGFloat(height) - textRect.height) / 2.0
        }
        
        let drawRect = CGRect(x: 0, y: drawY, width: CGFloat(width), height: textRect.height)
        attributedString.draw(in: drawRect)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = width
        descriptor.height = height
        descriptor.arrayLength = 1
        descriptor.usage = [.shaderRead, .renderTarget]
        
        guard let texture = device.makeTexture(descriptor: descriptor),
              let data = context.data else {
            Logger.log("[TextTextureGenerator] 创建 MTLTexture 失败或获取像素数据失败")
            return nil
        }
        
        let bytesPerRow = width * 4
        let rawPtr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var flippedData = [UInt8](repeating: 0, count: width * height * 4)
        
        flippedData.withUnsafeMutableBytes { dstPtr in
            guard let dstBase = dstPtr.baseAddress else { return }
            for y in 0..<height {
                let srcRow = rawPtr.advanced(by: y * bytesPerRow)
                let dstRow = dstBase.advanced(by: (height - 1 - y) * bytesPerRow)
                memcpy(dstRow, srcRow, bytesPerRow)
            }
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        let bytesPerImage = width * height * 4
        texture.replace(region: region, mipmapLevel: 0, slice: 0, withBytes: flippedData, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
        
        Logger.log("[TextTextureGenerator] 纹理生成完成: \(width)x\(height)")
        return texture
    }
}
