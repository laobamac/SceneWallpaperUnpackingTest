//
//  TextRenderableObject.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//

import Foundation
import MetalKit
import simd
import AppKit
import JavaScriptCore

class TextRenderableObject: RenderableObject {
    var jsContext: JSContext?
    var updateFunc: JSValue?
    var lastText: String = ""
    var textFont: NSFont
    var textColor: NSColor

    init?(device: MTLDevice, position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>, pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState?, script: String, fontPath: String, pointSize: Float, colorStr: String, baseFolder: URL) {
        var c = NSColor.white
        let comps = colorStr.split(separator: " ").compactMap { Float($0) }
        if comps.count >= 3 {
            c = NSColor(red: CGFloat(comps[0]), green: CGFloat(comps[1]), blue: CGFloat(comps[2]), alpha: 1.0)
        }
        self.textColor = c

        var f = NSFont.systemFont(ofSize: CGFloat(pointSize))
        let fontURL = baseFolder.appendingPathComponent(fontPath)
        if let data = try? Data(contentsOf: fontURL),
           let provider = CGDataProvider(data: data as CFData),
           let cgFont = CGFont(provider) {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterGraphicsFont(cgFont, &error) {
                if let fontName = cgFont.postScriptName as String?, let customFont = NSFont(name: fontName, size: CGFloat(pointSize)) {
                    f = customFont
                }
            } else if let fontName = cgFont.postScriptName as String?, let customFont = NSFont(name: fontName, size: CGFloat(pointSize)) {
                f = customFont
            }
        }
        self.textFont = f

        let w = max(1, Int(size.x))
        let h = max(1, Int(size.y))
        let desc = MTLTextureDescriptor()
        desc.textureType = .type2DArray
        desc.pixelFormat = .rgba8Unorm
        desc.width = w
        desc.height = h
        desc.arrayLength = 1
        desc.usage = [.shaderRead, .renderTarget, .pixelFormatView]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        let bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, slice: 0, withBytes: bytes, bytesPerRow: w * 4, bytesPerImage: w * h * 4)

        super.init(position: position, rotation: rotation, size: size, scale: scale, texture: tex, pipeline: pipeline, depthState: depthState)

        self.jsContext = JSContext()
        let safeScript = script.replacingOccurrences(of: "export function ", with: "function ")
                               .replacingOccurrences(of: "export let ", with: "let ")
                               .replacingOccurrences(of: "export var ", with: "var ")
        self.jsContext?.evaluateScript(safeScript)
        self.updateFunc = self.jsContext?.objectForKeyedSubscript("update")
    }

    func updateTextTexture(_ text: String) {
        let w = texture.width
        let h = texture.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor,
            .paragraphStyle: pStyle
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let sSize = attrStr.size()
        let rect = CGRect(x: (CGFloat(w) - sSize.width)/2, y: (CGFloat(h) - sSize.height)/2, width: sSize.width, height: sSize.height)
        attrStr.draw(in: rect)

        NSGraphicsContext.restoreGraphicsState()

        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, slice: 0, withBytes: context.data!, bytesPerRow: w * 4, bytesPerImage: w * h * 4)
    }

    override func draw(encoder: MTLRenderCommandEncoder) {
        if let f = updateFunc, !f.isUndefined {
            if let val = f.call(withArguments: [0]) {
                let newText = val.toString() ?? ""
                if newText != lastText {
                    lastText = newText
                    updateTextTexture(newText)
                }
            }
        }
        super.draw(encoder: encoder)
    }
}
