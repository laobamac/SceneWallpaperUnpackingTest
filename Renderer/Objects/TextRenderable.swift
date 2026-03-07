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
    var canvasSize: CGSize
    
    var currentText: String = ""
    var customFontName: String?
    var finalFontSize: Float = 32.0
    
    init?(device: MTLDevice, obj: SceneObject, baseFolder: URL, pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState?, canvasSize: CGSize) {
        Logger.log("[TextRenderable] 开始初始化文本图层 ID: \(obj.id ?? -1) 名字: \(obj.name ?? "Unknown")")
        
        self.textGenerator = TextTextureGenerator(device: device)
        self.baseFolder = baseFolder
        self.sceneObject = obj
        self.canvasSize = canvasSize
        
        let (pos, rotation, size, scale) = RenderableObject.parseTransforms(obj)
        
        let uiScale = Float(canvasSize.height) / 1080.0
        let dpiScale: Float = 96.0 / 72.0
        self.finalFontSize = (obj.pointsize ?? 32.0) * uiScale * dpiScale * 1.45
        
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
                Logger.log("[TextRenderable] 解析到复杂的文本脚本")
                self.textEngine = WEScriptEngine(script: scriptCode, properties: props, canvasSize: canvasSize)
            } else if case .script(let scriptCode) = textScriptData {
                Logger.log("[TextRenderable] 解析到简单的文本脚本")
                self.textEngine = WEScriptEngine(script: scriptCode, properties: [:], canvasSize: canvasSize)
            } else {
                self.currentText = textScriptData.value
                Logger.log("[TextRenderable] 解析到静态文本: \(self.currentText)")
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
                Logger.log("[TextRenderable] 解析到复杂的坐标脚本")
                self.originEngine = WEScriptEngine(script: scriptCode, properties: props, canvasSize: canvasSize)
            } else if case .script(let scriptCode) = originScriptData {
                Logger.log("[TextRenderable] 解析到简单的坐标脚本")
                self.originEngine = WEScriptEngine(script: scriptCode, properties: [:], canvasSize: canvasSize)
            }
        }
        
        let initialTexture = textGenerator.generateTexture(
            text: self.currentText,
            fontName: self.customFontName,
            fontSize: self.finalFontSize,
            bounds: CGSize(width: Double(size.x), height: Double(size.y)),
            horizontalAlign: obj.horizontalalign,
            verticalAlign: obj.verticalalign
        )
        
        let safeTexture: MTLTexture
        var finalSize = size
        if let t = initialTexture {
            safeTexture = t
            finalSize = SIMD2<Float>(Float(t.width), Float(t.height))
        } else {
            Logger.log("[TextRenderable] 初始纹理生成失败，使用占位纹理")
            let desc = MTLTextureDescriptor()
            desc.textureType = .type2DArray
            desc.pixelFormat = .rgba8Unorm
            desc.width = 1
            desc.height = 1
            desc.arrayLength = 1
            safeTexture = device.makeTexture(descriptor: desc)!
        }
        
        super.init(position: pos, rotation: rotation, size: finalSize, scale: scale, alpha: obj.alpha ?? 1.0, texture: safeTexture, pipeline: pipeline, depthState: depthState)
        
        self.id = obj.id ?? -1
        self.parentId = obj.parent
        Logger.log("[TextRenderable] 初始化文本图层完成")
    }
    
    override func update(commandBuffer: MTLCommandBuffer) {
        if let originEngine = originEngine {
            if let newPos = originEngine.evaluateUpdate(value: self.localPosition) as? SIMD3<Float> {
                if self.localPosition != newPos {
                    self.localPosition = newPos
                }
            }
        }
        
        var textChanged = false
        if let textEngine = textEngine {
            if let newText = textEngine.evaluateUpdate(value: self.currentText) as? String {
                if newText != self.currentText {
                    Logger.log("[TextRenderable] 动态文本内容变更: [\(self.currentText)] -> [\(newText)]")
                    self.currentText = newText
                    textChanged = true
                }
            }
        } else if self.currentText.isEmpty && sceneObject.text != nil {
            let staticText = sceneObject.text!.value
            if staticText != self.currentText {
                Logger.log("[TextRenderable] 静态文本内容更新: [\(staticText)]")
                self.currentText = staticText
                textChanged = true
            }
        }
        
        if textChanged {
            let (_, _, currentSize, _) = RenderableObject.parseTransforms(sceneObject)
            if let newTexture = textGenerator.generateTexture(
                text: self.currentText,
                fontName: self.customFontName,
                fontSize: self.finalFontSize,
                bounds: CGSize(width: Double(currentSize.x), height: Double(currentSize.y)),
                horizontalAlign: sceneObject.horizontalalign,
                verticalAlign: sceneObject.verticalalign
            ) {
                self.texture = newTexture
                self.size = SIMD2<Float>(Float(newTexture.width), Float(newTexture.height))
            }
        }
        
        super.update(commandBuffer: commandBuffer)
    }
}
