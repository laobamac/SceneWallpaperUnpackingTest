//
//  TextRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/3/7.
//

import Foundation
import MetalKit
import simd

class TextRenderable: RenderableObject {
    var textEngine: WEScriptEngine?
    var originEngine: WEScriptEngine?
    var textGenerator: TextTextureGenerator
    var baseFolder: URL
    var sceneObject: SceneObject
    
    var currentText: String = ""
    var customFontName: String?
    
    init?(device: MTLDevice, obj: SceneObject, baseFolder: URL, pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState?, canvasSize: CGSize) {
        self.textGenerator = TextTextureGenerator(device: device)
        self.baseFolder = baseFolder
        self.sceneObject = obj
        
        let (pos, rotation, size, scale) = RenderableObject.parseTransforms(obj)
        
        if let fontPath = obj.font, !fontPath.starts(with: "systemfont") {
            let fontURL = baseFolder.appendingPathComponent(fontPath)
            self.customFontName = self.textGenerator.registerFont(at: fontURL)
        }
        
        if let textScriptData = obj.text {
            if case .scriptData(let scriptData) = textScriptData, let scriptCode = scriptData.script {
                var props: [String: Any] = [:]
                if let sp = scriptData.scriptproperties {
                    for (k, v) in sp {
                        props[k] = v.rawValue
                    }
                }
                self.textEngine = WEScriptEngine(script: scriptCode, properties: props, canvasSize: canvasSize)
            } else if case .script(let scriptCode) = textScriptData {
                self.textEngine = WEScriptEngine(script: scriptCode, properties: [:], canvasSize: canvasSize)
            } else {
                self.currentText = textScriptData.value
            }
        }
        
        if let originScriptData = obj.origin {
            if case .scriptData(let scriptData) = originScriptData, let scriptCode = scriptData.script {
                var props: [String: Any] = [:]
                if let sp = scriptData.scriptproperties {
                    for (k, v) in sp {
                        props[k] = v.rawValue
                    }
                }
                self.originEngine = WEScriptEngine(script: scriptCode, properties: props, canvasSize: canvasSize)
            } else if case .script(let scriptCode) = originScriptData {
                self.originEngine = WEScriptEngine(script: scriptCode, properties: [:], canvasSize: canvasSize)
            }
        }
        
        let initialTexture = textGenerator.generateTexture(
            text: self.currentText,
            fontName: self.customFontName,
            fontSize: obj.pointsize ?? 32.0,
            bounds: CGSize(width: Double(size.x), height: Double(size.y)),
            horizontalAlign: obj.horizontalalign,
            verticalAlign: obj.verticalalign
        )
        
        let safeTexture = initialTexture ?? device.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false))!
        
        super.init(position: pos, rotation: rotation, size: size, scale: scale, alpha: obj.alpha ?? 1.0, texture: safeTexture, pipeline: pipeline, depthState: depthState)
        
        self.id = obj.id ?? -1
        self.parentId = obj.parent
    }
    
    override func update(commandBuffer: MTLCommandBuffer) {
        if let originEngine = originEngine {
            if let newPos = originEngine.evaluateUpdate(value: self.localPosition) as? SIMD3<Float> {
                self.localPosition = newPos
            }
        }
        
        var textChanged = false
        if let textEngine = textEngine {
            if let newText = textEngine.evaluateUpdate(value: self.currentText) as? String {
                if newText != self.currentText {
                    self.currentText = newText
                    textChanged = true
                }
            }
        } else if self.currentText.isEmpty && sceneObject.text != nil {
            let staticText = sceneObject.text!.value
            if staticText != self.currentText {
                self.currentText = staticText
                textChanged = true
            }
        }
        
        if textChanged {
            let (_, _, currentSize, _) = RenderableObject.parseTransforms(sceneObject)
            if let newTexture = textGenerator.generateTexture(
                text: self.currentText,
                fontName: self.customFontName,
                fontSize: sceneObject.pointsize ?? 32.0,
                bounds: CGSize(width: Double(currentSize.x), height: Double(currentSize.y)),
                horizontalAlign: sceneObject.horizontalalign,
                verticalAlign: sceneObject.verticalalign
            ) {
                self.texture = newTexture
            }
        }
        
        super.update(commandBuffer: commandBuffer)
    }
}
