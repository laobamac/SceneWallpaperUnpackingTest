//
//  TextTextureManager.swift
//  Renderer
//
//  Created by laobamac on 2026/3/8.
//

import Metal
import AppKit
import CoreText
import CoreGraphics

class TextTextureManager {
    static let shared = TextTextureManager()
    private var registeredFonts: [String: NSFont] = [:]
    private var device: MTLDevice?

    func setup(device: MTLDevice) {
        self.device = device
    }

    func registerFont(path: String, baseURL: URL) {
        let fontURL = baseURL.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fontURL.path) else { return }
        
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
        
        if let dataProvider = CGDataProvider(url: fontURL as CFURL),
           let cgFont = CGFont(dataProvider) {
            if let postScriptName = cgFont.postScriptName as String? {
                if let font = NSFont(name: postScriptName, size: 12) {
                    registeredFonts[path] = font
                }
            }
        }
    }

    func createTexture(text: String, fontPath: String?, fontSize: Float, size: SIMD2<Float>, horizontalAlign: String?, verticalAlign: String?, padding: Float) -> MTLTexture? {
        guard let device = device else { return nil }
        
        let weFontScale: CGFloat = 2.8
        let backingScale: CGFloat = 2.0
        
        let width = max(1, Int(CGFloat(size.x) * backingScale))
        let height = max(1, Int(CGFloat(size.y) * backingScale))
        
        let adjustedFontSize = CGFloat(fontSize) * weFontScale * backingScale
        let scaledPadding = CGFloat(padding) * backingScale

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
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
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.lineHeightMultiple = 1.0
        paragraphStyle.maximumLineHeight = adjustedFontSize
        paragraphStyle.minimumLineHeight = adjustedFontSize
        
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
            .baselineOffset: 0
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let drawingWidth = max(1, CGFloat(width) - scaledPadding * 2)
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let textRect = attributedString.boundingRect(with: CGSize(width: drawingWidth, height: .greatestFiniteMagnitude), options: options)

        let drawX = scaledPadding
        var drawY: CGFloat = 0

        switch verticalAlign {
        case "top":
            drawY = CGFloat(height) - textRect.height - scaledPadding
        case "bottom":
            drawY = scaledPadding
        case "center":
            drawY = (CGFloat(height) - textRect.height) / 2.0
        default:
            drawY = CGFloat(height) - textRect.height - scaledPadding
        }

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        
        let targetRect = CGRect(x: drawX, y: drawY, width: drawingWidth, height: textRect.height)
        attributedString.draw(with: targetRect, options: options)
        
        NSGraphicsContext.restoreGraphicsState()

        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .rgba8Unorm
        textureDescriptor.width = width
        textureDescriptor.height = height
        textureDescriptor.textureType = .type2DArray
        textureDescriptor.arrayLength = 1
        textureDescriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return nil }

        if let data = context.data {
            texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                            mipmapLevel: 0,
                            slice: 0,
                            withBytes: data,
                            bytesPerRow: bytesPerRow,
                            bytesPerImage: bytesPerRow * height)
        }

        return texture
    }
}
