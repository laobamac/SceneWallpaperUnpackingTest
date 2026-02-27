//
//  TextRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/2/26.
//

import Metal
import MetalKit
import CoreText
import CoreGraphics
import Foundation
import JavaScriptCore

class TextRenderable {
    var id: Int
    var parentId: Int?
    var name: String
    var origin: simd_float3
    var scale: simd_float3
    var color: simd_float4
    var alpha: Float
    var fontName: String
    var pointSize: CGFloat
    var texture: MTLTexture?
    var jsEngine: JSEngine?
    var scriptObject: JSValue?
    var width: CGFloat
    var height: CGFloat
    var originalSize: simd_float2
    var isHovered: Bool = false
    var isDragging: Bool = false
    var originalOrigin: simd_float3
    var horizontalAlign: String
    var verticalAlign: String
    var padding: CGFloat
    var sceneHeight: CGFloat
    var scriptPropertiesMap: [String: Any]?
    
    private let device: MTLDevice
    private var isDirty: Bool = true
    private var currentText: String = ""
    
    var globalTransform: matrix_float4x4 = matrix_identity_float4x4
    var localTransform: matrix_float4x4 = matrix_identity_float4x4
    var nodeTransform: matrix_float4x4 = matrix_identity_float4x4
    
    init(device: MTLDevice, id: Int, parentId: Int?, name: String, origin: simd_float3, size: simd_float2, scale: simd_float3, color: simd_float4, alpha: Float = 1.0, fontName: String, pointSize: CGFloat, horizontalAlign: String = "center", verticalAlign: String = "center", padding: CGFloat = 0, sceneHeight: CGFloat = 1080.0, scriptProperties: [String: Any]? = nil) {
        self.device = device
        self.id = id
        self.parentId = parentId
        self.name = name
        self.origin = origin
        self.originalOrigin = origin
        self.originalSize = size
        self.width = CGFloat(size.x) + padding * 2
        self.height = CGFloat(size.y) + padding * 2
        self.scale = scale
        self.color = color
        self.alpha = alpha
        self.fontName = fontName
        self.pointSize = pointSize
        self.horizontalAlign = horizontalAlign
        self.verticalAlign = verticalAlign
        self.padding = padding
        self.sceneHeight = sceneHeight
        self.scriptPropertiesMap = scriptProperties
    }
    
    func setupScript(_ script: String, engine: JSEngine) {
        self.jsEngine = engine
        self.scriptObject = engine.evaluate(script)
        
        if let props = self.scriptPropertiesMap {
            let context = engine.context
            
            var jsProps = self.scriptObject?.objectForKeyedSubscript("scriptProperties")
            
            if jsProps == nil || jsProps!.isUndefined {
                jsProps = JSValue(newObjectIn: context)
                context.setObject(jsProps, forKeyedSubscript: "scriptProperties" as NSString)
                self.scriptObject?.setValue(jsProps, forProperty: "scriptProperties")
            }
            
            for (key, value) in props {
                if let dict = value as? [String: Any], let val = dict["value"] {
                    jsProps?.setValue(val, forProperty: key)
                } else {
                    jsProps?.setValue(value, forProperty: key)
                }
            }
        }
        
        if let initFunc = scriptObject?.objectForKeyedSubscript("init"), !initFunc.isUndefined {
            let context = engine.context
            let thisLayer = JSValue(newObjectIn: context)
            thisLayer?.setValue(Vec3(Double(origin.x), Double(origin.y), Double(origin.z)), forProperty: "origin")
            thisLayer?.setValue(Vec3(Double(originalOrigin.x), Double(originalOrigin.y), Double(originalOrigin.z)), forProperty: "originalOrigin")
            context.setObject(thisLayer, forKeyedSubscript: "thisLayer" as NSString)
            
            let initScale = Vec3(Double(scale.x), Double(scale.y), Double(scale.z))
            initFunc.call(withArguments: [initScale])
            
            if let updatedOrigin = thisLayer?.objectForKeyedSubscript("origin")?.toObjectOf(Vec3.self) as? Vec3 {
                self.origin = simd_float3(Float(updatedOrigin.x), Float(updatedOrigin.y), Float(updatedOrigin.z))
            }
        }
    }
    
    func update(time: Double) {
        guard let engine = jsEngine, let scriptObj = scriptObject else { return }
        
        let context = engine.context
        let thisLayer = context.objectForKeyedSubscript("thisLayer")
        
        if isDragging, let updatedOrigin = thisLayer?.objectForKeyedSubscript("origin")?.toObjectOf(Vec3.self) as? Vec3 {
            self.origin = simd_float3(Float(updatedOrigin.x), Float(updatedOrigin.y), Float(updatedOrigin.z))
        } else {
            thisLayer?.setValue(Vec3(Double(origin.x), Double(origin.y), Double(origin.z)), forProperty: "origin")
        }
        
        if let updateFunc = scriptObj.objectForKeyedSubscript("update"), !updateFunc.isUndefined {
            let inputScale = Vec3(Double(scale.x), Double(scale.y), Double(scale.z))
            let result = updateFunc.call(withArguments: [inputScale])
            if let newText = result?.toString(), newText != currentText, newText != "undefined", !(result?.isObject ?? false) {
                currentText = newText
                isDirty = true
            } else if let vecResult = result?.toObjectOf(Vec3.self) as? Vec3 {
                scale = simd_float3(Float(vecResult.x), Float(vecResult.y), Float(vecResult.z))
            }
        }
        
        if let applyPropsFunc = scriptObj.objectForKeyedSubscript("applyUserProperties"), !applyPropsFunc.isUndefined {
            applyPropsFunc.call(withArguments: [[]])
        }
        
        if isDirty && !currentText.isEmpty {
            generateTexture()
            isDirty = false
        }
    }
    
    private func generateTexture() {
        let weDpiScale = sceneHeight / 1080.0
        let actualPointSize = pointSize * (96.0 / 72.0) * weDpiScale
        
        let font = CTFontCreateWithName(fontName as CFString, actualPointSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w * alpha))
        ]
        
        let attributedString = NSAttributedString(string: currentText, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)
        
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let typoWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        
        let contextWidth = max(Int(ceil(width)), 1)
        let contextHeight = max(Int(ceil(height)), 1)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: contextWidth,
                                      height: contextHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: contextWidth * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        
        context.clear(CGRect(x: 0, y: 0, width: CGFloat(contextWidth), height: CGFloat(contextHeight)))
        
        var textX: CGFloat = 0
        var textY: CGFloat = 0
        
        if horizontalAlign == "left" {
            textX = padding
        } else if horizontalAlign == "right" {
            textX = CGFloat(contextWidth) - typoWidth - padding
        } else {
            textX = (CGFloat(contextWidth) - typoWidth) / 2.0
        }
        
        if verticalAlign == "top" {
            textY = CGFloat(contextHeight) - padding - ascent
        } else if verticalAlign == "bottom" {
            textY = padding + descent
        } else {
            textY = CGFloat(contextHeight) / 2.0 - (ascent - descent) / 2.0
        }
        
        context.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, context)
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2DArray
        textureDescriptor.pixelFormat = .rgba8Unorm
        textureDescriptor.width = contextWidth
        textureDescriptor.height = contextHeight
        textureDescriptor.arrayLength = 1
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let newTexture = device.makeTexture(descriptor: textureDescriptor) else { return }
        
        let region = MTLRegionMake2D(0, 0, contextWidth, contextHeight)
        if let data = context.data {
            newTexture.replace(region: region, mipmapLevel: 0, slice: 0, withBytes: data, bytesPerRow: contextWidth * 4, bytesPerImage: contextWidth * contextHeight * 4)
        }
        
        self.texture = newTexture
    }
    
    func updateTransforms(parentTransform: matrix_float4x4?) {
        let translation = matrix_float4x4(translationX: origin.x, y: origin.y, z: origin.z)
        let scaling = matrix_float4x4(scaleX: scale.x, y: scale.y, z: scale.z)
        
        var offsetX: Float = 0.0
        var offsetY: Float = 0.0
        
        if horizontalAlign == "left" {
            offsetX = Float(width) / 2.0
        } else if horizontalAlign == "right" {
            offsetX = -Float(width) / 2.0
        }
        
        if verticalAlign == "top" {
            offsetY = Float(height) / 2.0
        } else if verticalAlign == "bottom" {
            offsetY = -Float(height) / 2.0
        }
        
        let alignOffset = matrix_float4x4(translationX: offsetX, y: offsetY, z: 0)
        
        localTransform = matrix_multiply(matrix_multiply(translation, scaling), alignOffset)
        
        if let pTrans = parentTransform {
            nodeTransform = matrix_multiply(pTrans, localTransform)
        } else {
            nodeTransform = localTransform
        }
        
        globalTransform = nodeTransform
    }
    
    func checkHit(point: simd_float2) -> Bool {
        let localPoint = simd_float2(
            point.x - globalTransform.columns.3.x,
            point.y - globalTransform.columns.3.y
        )
        let halfWidth = Float(width) / 2.0 * scale.x
        let halfHeight = Float(height) / 2.0 * scale.y
        return abs(localPoint.x) <= halfWidth && abs(localPoint.y) <= halfHeight
    }
}

extension matrix_float4x4 {
    init(translationX x: Float, y: Float, z: Float) {
        self.init(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(x, y, z, 1)
        )
    }
    
    init(scaleX x: Float, y: Float, z: Float) {
        self.init(
            simd_float4(x, 0, 0, 0),
            simd_float4(0, y, 0, 0),
            simd_float4(0, 0, z, 0),
            simd_float4(0, 0, 0, 1)
        )
    }
}
