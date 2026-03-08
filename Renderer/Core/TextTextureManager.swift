//
//  TextTextureManager.swift
//  Renderer
//
//  Created by laobamac on 2026/3/8.
//

import AppKit
import CoreGraphics
import CoreText
import Metal

class TextTextureManager {
    static let shared = TextTextureManager()
    private var registeredFonts: [String: NSFont] = [:]
    private var device: MTLDevice?
    
    func setup(device: MTLDevice) {
        self.device = device
    }
    
    func registerFont(path: String, baseURL: URL) {
        let fontURL = baseURL.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fontURL.path) else {
            return
        }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
        if let dataProvider = CGDataProvider(url: fontURL as CFURL),
            let cgFont = CGFont(dataProvider)
        {
            if let postScriptName = cgFont.postScriptName as String? {
                if let font = NSFont(name: postScriptName, size: 12) {
                    registeredFonts[path] = font
                }
            }
        }
    }
    
    func createTexture(
        text: String,
        fontPath: String?,
        fontSize: Float,
        size: SIMD2<Float>,
        horizontalAlign: String?,
        verticalAlign: String?,
        padding: Float,
        limitWidth: Bool?
    ) -> MTLTexture? {
        guard let device = device else { return nil }
        
        let weBaseFontScale: CGFloat = 4.0
        let backingScale: CGFloat = 2.0
        let totalScale = weBaseFontScale * backingScale
        
        let adjustedFontSize = CGFloat(fontSize) * totalScale
        let scaledPadding = CGFloat(padding) * totalScale
        let baseWidth = CGFloat(size.x) * totalScale
        let baseHeight = CGFloat(size.y) * totalScale
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var font = NSFont.systemFont(ofSize: adjustedFontSize)
        
        if let fontPath = fontPath {
            if let customFont = registeredFonts[fontPath] {
                font = customFont.withSize(adjustedFontSize)
            } else if fontPath.lowercased().contains("arial") {
                if let arial = NSFont(name: "Arial", size: adjustedFontSize) {
                    font = arial
                }
            }
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = adjustedFontSize
        paragraphStyle.maximumLineHeight = adjustedFontSize
        
        switch horizontalAlign {
        case "left": paragraphStyle.alignment = .left
        case "right": paragraphStyle.alignment = .right
        case "center": paragraphStyle.alignment = .center
        default: paragraphStyle.alignment = .left
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        
        let attributedString = NSAttributedString(
            string: text,
            attributes: attributes
        )
        
        let isLimited = limitWidth ?? false
        let drawingWidth = isLimited ? max(1, baseWidth - scaledPadding * 2) : 100000.0
        let options: NSString.DrawingOptions = [
            .usesLineFragmentOrigin, .usesFontLeading,
        ]
        
        let textRect = attributedString.boundingRect(
            with: CGSize(width: drawingWidth, height: .greatestFiniteMagnitude),
            options: options
        )
        
        let finalWidth = max(baseWidth, ceil(textRect.width + scaledPadding * 2))
        let finalHeight = max(baseHeight, ceil(textRect.height + scaledPadding * 2))
        let width = max(1, Int(finalWidth))
        let height = max(1, Int(finalHeight))
        
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        let drawX: CGFloat
        if isLimited {
            drawX = scaledPadding
        } else {
            switch horizontalAlign {
            case "center": drawX = (finalWidth - textRect.width) / 2.0
            case "right": drawX = finalWidth - textRect.width - scaledPadding
            default: drawX = scaledPadding
            }
        }
        
        let drawY: CGFloat
        switch verticalAlign {
        case "top": drawY = CGFloat(height) - textRect.height - scaledPadding
        case "bottom": drawY = scaledPadding
        case "center": drawY = (CGFloat(height) - textRect.height) / 2.0
        default: drawY = CGFloat(height) - textRect.height - scaledPadding
        }
        
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        
        let targetRect = CGRect(
            x: drawX,
            y: drawY,
            width: isLimited ? (baseWidth - scaledPadding * 2) : (textRect.width + 1),
            height: textRect.height
        )
        
        attributedString.draw(with: targetRect, options: options)
        NSGraphicsContext.restoreGraphicsState()
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .rgba8Unorm
        textureDescriptor.width = width
        textureDescriptor.height = height
        textureDescriptor.textureType = .type2DArray
        textureDescriptor.arrayLength = 1
        textureDescriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor)
        else { return nil }
        
        if let data = context.data {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                slice: 0,
                withBytes: data,
                bytesPerRow: bytesPerRow,
                bytesPerImage: bytesPerRow * height
            )
        }
        
        return texture
    }
}
