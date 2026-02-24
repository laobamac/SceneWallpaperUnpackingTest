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

class TextRenderableObject: RenderableObject {
    var textFont: NSFont
    var textColor: NSColor
    var textString: String = ""
    var horizontalAlignment: NSTextAlignment = .center
    var verticalAlignment: String = "center"
    var isBaked: Bool = false

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

        let sceneURL = baseFolder.appendingPathComponent("scene.json")
        if let data = try? Data(contentsOf: sceneURL),
           let root = try? JSONDecoder().decode(SceneRoot.self, from: data) {
            for obj in root.objects {
                if let textProp = obj.text {
                    let s = textProp.script
                    let v = textProp.value
                    if (!script.isEmpty && s == script) || (!script.isEmpty && v == script) {
                        self.textString = v.isEmpty ? script : v
                        if let ha = obj.horizontalalign {
                            if ha == "left" { self.horizontalAlignment = .left }
                            else if ha == "right" { self.horizontalAlignment = .right }
                        }
                        if let va = obj.verticalalign {
                            self.verticalAlignment = va
                        }
                        break
                    }
                }
            }
        }
        
        if self.textString.isEmpty {
            self.textString = script
        }

        let w = max(1, Int(size.x))
        let h = max(1, Int(size.y))
        
        let desc = MTLTextureDescriptor()
        desc.textureType = .type2DArray
        desc.pixelFormat = .bgra8Unorm
        desc.width = w
        desc.height = h
        desc.arrayLength = 1
        desc.usage = [.shaderRead, .renderTarget, .pixelFormatView]
        
        guard let tex = device.makeTexture(descriptor: desc) else {
            return nil
        }

        super.init(position: position, rotation: rotation, size: size, scale: scale, texture: tex, pipeline: pipeline, depthState: depthState)
    }

    func bakeTexture() {
        let w = texture.width
        let h = texture.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return
        }

        context.clear(CGRect(x: 0, y: 0, width: w, height: h))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = horizontalAlignment
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor,
            .paragraphStyle: pStyle
        ]
        let attrStr = NSAttributedString(string: textString, attributes: attrs)
        let sSize = attrStr.size()
        
        var yPos: CGFloat = 0
        if verticalAlignment == "bottom" {
            yPos = CGFloat(h) - sSize.height
        } else if verticalAlignment == "top" {
            yPos = 0
        } else {
            yPos = (CGFloat(h) - sSize.height) / 2
        }
        
        let rect = CGRect(x: 0, y: yPos, width: CGFloat(w), height: sSize.height)
        attrStr.draw(in: rect)

        NSGraphicsContext.restoreGraphicsState()

        if let data = context.data {
            texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, slice: 0, withBytes: data, bytesPerRow: w * 4, bytesPerImage: w * h * 4)
        }
    }

    override func draw(encoder: MTLRenderCommandEncoder) {
        if !isBaked {
            bakeTexture()
            isBaked = true
        }
        super.draw(encoder: encoder)
    }
}
