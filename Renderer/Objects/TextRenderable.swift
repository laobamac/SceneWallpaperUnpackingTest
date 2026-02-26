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
    var fontName: String
    var pointSize: CGFloat
    var texture: MTLTexture?
    var jsEngine: JSEngine?
    var scriptObject: JSValue?
    var width: CGFloat = 0
    var height: CGFloat = 0
    var isHovered: Bool = false
    var isDragging: Bool = false
    var originalOrigin: simd_float3
    
    private let device: MTLDevice
    private var isDirty: Bool = true
    private var currentText: String = ""
    
    var globalTransform: matrix_float4x4 = matrix_identity_float4x4
    var localTransform: matrix_float4x4 = matrix_identity_float4x4
    
    init(device: MTLDevice, id: Int, parentId: Int?, name: String, origin: simd_float3, scale: simd_float3, color: simd_float4, fontName: String, pointSize: CGFloat) {
        self.device = device
        self.id = id
        self.parentId = parentId
        self.name = name
        self.origin = origin
        self.originalOrigin = origin
        self.scale = scale
        self.color = color
        self.fontName = fontName
        self.pointSize = pointSize
    }
    
    func setupScript(_ script: String, engine: JSEngine) {
        self.jsEngine = engine
        self.scriptObject = engine.evaluate(script)
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
        let font = CTFontCreateWithName(fontName as CFString, pointSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w))
        ]
        
        let attributedString = NSAttributedString(string: currentText, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)
        var imageBounds = CTLineGetImageBounds(line, nil)
        
        if imageBounds.width == 0 || imageBounds.height == 0 {
            imageBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        
        width = imageBounds.width
        height = imageBounds.height
        
        let contextWidth = Int(ceil(imageBounds.width))
        let contextHeight = Int(ceil(imageBounds.height))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: contextWidth,
                                      height: contextHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: contextWidth * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        
        context.clear(CGRect(x: 0, y: 0, width: CGFloat(contextWidth), height: CGFloat(contextHeight)))
        context.textPosition = CGPoint(x: -imageBounds.origin.x, y: -imageBounds.origin.y)
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
        localTransform = matrix_multiply(translation, scaling)
        
        if let pTrans = parentTransform {
            globalTransform = matrix_multiply(pTrans, localTransform)
        } else {
            globalTransform = localTransform
        }
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
