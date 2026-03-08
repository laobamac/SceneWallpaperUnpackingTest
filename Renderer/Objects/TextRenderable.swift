//
//  TextRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/3/8.
//

import Foundation
import MetalKit
import simd

class TextRenderable: RenderableObject {
    let sceneObject: SceneObject
    let textTextureManager: TextTextureManager
    var currentText: String = ""
    var scriptEngine: ScriptEngine?
    var originScriptEngine: ScriptEngine?
    
    init?(
        sceneObject: SceneObject,
        textureManager: TextTextureManager,
        canvasSize: SIMD2<Float>,
        pipeline: MTLRenderPipelineState,
        depthState: MTLDepthStencilState?,
        device: MTLDevice
    ) {
        self.sceneObject = sceneObject
        self.textTextureManager = textureManager
        let (pos, rotation, size, scale) = RenderableObject.parseTransforms(
            sceneObject
        )
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        guard let dummyTexture = device.makeTexture(descriptor: desc) else {
            return nil
        }
        super.init(
            position: pos,
            rotation: rotation,
            size: size,
            scale: scale,
            alpha: sceneObject.alpha ?? 1.0,
            texture: dummyTexture,
            pipeline: pipeline,
            depthState: depthState
        )
        if let textData = sceneObject.text {
            switch textData {
            case .string(let str):
                self.currentText = str
            case .object(let obj):
                self.currentText = obj.value ?? ""
                if let script = obj.script {
                    self.scriptEngine = ScriptEngine(
                        script: script,
                        properties: obj.scriptproperties,
                        canvasSize: canvasSize
                    )
                }
            }
        }
        if let originObj = sceneObject.origin,
            case .complex(let script, _, let props) = originObj, let s = script
        {
            self.originScriptEngine = ScriptEngine(
                script: s,
                properties: props,
                canvasSize: canvasSize
            )
        }
        updateTexture()
    }
    
    override func update(commandBuffer: MTLCommandBuffer) {
        var needsUpdate = false
        if let originEngine = originScriptEngine {
            if let newPos = originEngine.evaluateUpdate(
                value: self.localPosition
            ) as? SIMD3<Float> {
                if newPos != self.localPosition {
                    self.localPosition = newPos
                }
            }
        }
        if let textEngine = scriptEngine {
            if let updatedText = textEngine.evaluateUpdate(
                value: self.currentText
            ) as? String {
                if updatedText != self.currentText {
                    self.currentText = updatedText
                    needsUpdate = true
                }
            }
        }
        if needsUpdate {
            updateTexture()
        }
    }
    
    private func updateTexture() {
        let fontSize = sceneObject.pointsize ?? 32.0
        let padding = sceneObject.padding ?? 0.0
        let limitWidth = sceneObject.limitwidth
        
        let referenceSize: SIMD2<Float>
        if let s = sceneObject.size {
            referenceSize = s.float2Value
        } else {
            referenceSize = SIMD2<Float>(400, 400)
        }
        
        if let newTexture = textTextureManager.createTexture(
            text: currentText,
            fontPath: sceneObject.font,
            fontSize: fontSize,
            size: referenceSize,
            horizontalAlign: sceneObject.horizontalalign,
            verticalAlign: sceneObject.verticalalign,
            padding: padding,
            limitWidth: limitWidth
        ) {
            self.texture = newTexture
            let backingScale: Float = 2.0
            self.size =
                SIMD2<Float>(Float(newTexture.width), Float(newTexture.height))
                / backingScale
        }
    }
}
