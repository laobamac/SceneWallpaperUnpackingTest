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
    }
    
    deinit {
        for url in registeredFonts {
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
            return getFontName(from: url)
        }
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
        let width = max(1, Int(bounds.width))
        let height = max(1, Int(bounds.height))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }
        
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        
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
        attributes[.paragraphStyle] = paragraphStyle
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = attributedString.boundingRect(with: CGSize(width: width, height: Int.max), options: [.usesLineFragmentOrigin, .usesFontLeading])
        
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
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        
        guard let texture = device.makeTexture(descriptor: descriptor),
              let data = context.data else {
            return nil
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)
        
        return texture
    }
}
