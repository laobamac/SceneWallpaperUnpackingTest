//
//  TextRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/3/11.
//

import MetalKit
import CoreGraphics
import AppKit

class TextRenderable: RenderableObject {
    var device: MTLDevice
    var jsEngine: JSEngine?
    var currentTextString: String = ""
    var fontName: String = ""
    var baseFontSize: CGFloat = 32.0
    var alignment: NSTextAlignment = .left
    var verticalAlign: String = "top"
    var padding: CGFloat = 0.0
    var textColor: NSColor = .white
    var projectionSize: CGSize
    var baseSize: SIMD2<Float>
    
    private var lastScaleFactor: CGFloat = 0
    private var isStaticText: Bool = false
    
    init?(device: MTLDevice, sceneObject: SceneObject, baseFolder: URL?, position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>, pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState?, projectionSize: CGSize) {
        self.device = device
        self.projectionSize = projectionSize
        self.baseSize = size
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        guard let placeholder = device.makeTexture(descriptor: desc) else { return nil }
        
        super.init(position: position, rotation: rotation, size: size, scale: scale, texture: placeholder, pipeline: pipeline, depthState: depthState)
        
        self.padding = CGFloat(sceneObject.padding ?? 0)
        
        let resolutionScale = max(1.0, CGFloat(projectionSize.height) / 1080.0)
        let userDpiMultiplier: CGFloat = 2.0
        let pointToPixelRatio: CGFloat = 96.0 / 72.0
        self.baseFontSize = CGFloat(sceneObject.pointsize ?? 32) * resolutionScale * userDpiMultiplier * pointToPixelRatio
        
        if let hAlign = sceneObject.horizontalalign {
            switch hAlign {
            case "center": self.alignment = .center
            case "right": self.alignment = .right
            default: self.alignment = .left
            }
        }
        self.verticalAlign = sceneObject.verticalalign ?? "top"
        
        if let c = sceneObject.color {
            let colorVec = c.float3Value
            self.textColor = NSColor(red: CGFloat(colorVec.x), green: CGFloat(colorVec.y), blue: CGFloat(colorVec.z), alpha: 1.0)
        }
        
        if let fontString = sceneObject.font {
            if let base = baseFolder, fontString.hasSuffix(".otf") || fontString.hasSuffix(".ttf") {
                let fontURL = base.appendingPathComponent(fontString)
                if let registeredName = FontManager.shared.registerFont(url: fontURL) {
                    self.fontName = registeredName
                } else {
                    self.fontName = NSFont.systemFont(ofSize: self.baseFontSize).fontName
                }
            } else {
                self.fontName = fontString
            }
        } else {
            self.fontName = NSFont.systemFont(ofSize: self.baseFontSize).fontName
        }
        
        if let textProp = sceneObject.text {
            switch textProp {
            case .string(let s):
                self.currentTextString = s
                self.isStaticText = true
            case .script(let val, let script, let props):
                self.currentTextString = val
                self.jsEngine = JSEngine()
                self.jsEngine?.loadScript(script: script, properties: props)
                self.isStaticText = false
            default:
                self.currentTextString = ""
            }
        }
        
        updateTexture()
    }
    
    override func update(commandBuffer: MTLCommandBuffer) {
        var needsUpdate = false
        
        if !isStaticText, let engine = jsEngine {
            let newText = engine.evaluateUpdate(value: currentTextString)
            if newText != currentTextString {
                currentTextString = newText
                needsUpdate = true
            }
        }
        
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let globalScale = calculateGlobalScale()
        let effectiveScale = screenScale * CGFloat(globalScale)
        
        if abs(effectiveScale - lastScaleFactor) > 0.1 {
            lastScaleFactor = effectiveScale
            needsUpdate = true
        }
        
        if needsUpdate {
            updateTexture()
        }
    }
    
    private func calculateGlobalScale() -> Float {
        var s = scale.x
        var currentParent = parent
        while let p = currentParent {
            s *= p.scale.x
            currentParent = p.parent
        }
        return s
    }
    
    private func updateTexture() {
        guard !currentTextString.isEmpty else { return }
        
        let boxWidth = max(1, Int(CGFloat(baseSize.x) * lastScaleFactor))
        let boxHeight = max(1, Int(CGFloat(baseSize.y) * lastScaleFactor))
        
        let scaledFontSize = baseFontSize * lastScaleFactor
        let scaledPadding = padding * lastScaleFactor
        
        let nsFont = FontManager.shared.getFont(name: fontName, size: scaledFontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: currentTextString, attributes: attributes)
        let textSize = attributedString.size()
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        
        guard let context = CGContext(data: nil, width: boxWidth, height: boxHeight, bitsPerComponent: 8, bytesPerRow: boxWidth * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return
        }
        
        context.clear(CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight))
        
        context.translateBy(x: 0, y: CGFloat(boxHeight))
        context.scaleBy(x: 1.0, y: -1.0)
        
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        
        var xOffset: CGFloat = scaledPadding
        if alignment == .center {
            xOffset = (CGFloat(boxWidth) - textSize.width) / 2.0
        } else if alignment == .right {
            xOffset = CGFloat(boxWidth) - textSize.width - scaledPadding
        }
        
        var yOffset: CGFloat = scaledPadding
        if verticalAlign == "center" {
            yOffset = (CGFloat(boxHeight) - textSize.height) / 2.0
        } else if verticalAlign == "bottom" {
            yOffset = CGFloat(boxHeight) - textSize.height - scaledPadding
        }
        
        attributedString.draw(at: CGPoint(x: xOffset, y: yOffset))
        
        NSGraphicsContext.restoreGraphicsState()
        
        if let data = context.data {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: boxWidth, height: boxHeight, mipmapped: false)
            desc.textureType = .type2DArray
            desc.arrayLength = 1
            desc.usage = [.shaderRead]
            if let newTexture = device.makeTexture(descriptor: desc) {
                newTexture.replace(region: MTLRegionMake2D(0, 0, boxWidth, boxHeight), mipmapLevel: 0, slice: 0, withBytes: data, bytesPerRow: boxWidth * 4, bytesPerImage: boxWidth * boxHeight * 4)
                self.texture = newTexture
            }
        }
    }
}
