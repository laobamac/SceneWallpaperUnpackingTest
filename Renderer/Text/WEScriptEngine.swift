//
//  WEScriptEngine.swift
//  Renderer
//
//  Created by laobamac on 2026/3/7.
//

import Foundation
import JavaScriptCore
import simd

@objc protocol WEScriptPropertiesBuilderJSExport: JSExport {
    func addCombo(_ dict: [String: Any]) -> WEScriptPropertiesBuilder
    func addCheckbox(_ dict: [String: Any]) -> WEScriptPropertiesBuilder
    func addSlider(_ dict: [String: Any]) -> WEScriptPropertiesBuilder
    func addText(_ dict: [String: Any]) -> WEScriptPropertiesBuilder
    func addColor(_ dict: [String: Any]) -> WEScriptPropertiesBuilder
    func finish() -> [String: Any]
}

class WEScriptPropertiesBuilder: NSObject, WEScriptPropertiesBuilderJSExport {
    var properties: [String: Any] = [:]
    
    func addCombo(_ dict: [String: Any]) -> WEScriptPropertiesBuilder { return self }
    func addCheckbox(_ dict: [String: Any]) -> WEScriptPropertiesBuilder { return self }
    func addSlider(_ dict: [String: Any]) -> WEScriptPropertiesBuilder { return self }
    func addText(_ dict: [String: Any]) -> WEScriptPropertiesBuilder { return self }
    func addColor(_ dict: [String: Any]) -> WEScriptPropertiesBuilder { return self }
    func finish() -> [String: Any] { return properties }
}

class WEScriptEngine {
    let context: JSContext
    var hasUpdateFunction: Bool = false
    
    init?(script: String, properties: [String: Any], canvasSize: CGSize) {
        Logger.log("[WEScriptEngine] 开始初始化 JSContext")
        guard let ctx = JSContext() else {
            Logger.log("[WEScriptEngine] JSContext 初始化失败")
            return nil
        }
        self.context = ctx
        
        let engineObj = JSValue(newObjectIn: ctx)
        let canvasObj = JSValue(newObjectIn: ctx)
        canvasObj?.setValue(canvasSize.width, forProperty: "x")
        canvasObj?.setValue(canvasSize.height, forProperty: "y")
        engineObj?.setValue(canvasObj, forProperty: "canvasSize")
        ctx.setObject(engineObj, forKeyedSubscript: "engine" as NSString)
        
        let builderBlock: @convention(block) () -> WEScriptPropertiesBuilder = {
            return WEScriptPropertiesBuilder()
        }
        ctx.setObject(unsafeBitCast(builderBlock, to: AnyObject.self), forKeyedSubscript: "createScriptProperties" as NSString)
        
        let transformedScript = script.replacingOccurrences(of: "export var ", with: "var ")
                                      .replacingOccurrences(of: "export let ", with: "let ")
                                      .replacingOccurrences(of: "export function ", with: "function ")
        
        ctx.evaluateScript(transformedScript)
        
        if let scriptProps = ctx.objectForKeyedSubscript("scriptProperties") {
            Logger.log("[WEScriptEngine] 注入 scriptProperties")
            for (key, value) in properties {
                scriptProps.setValue(value, forProperty: key)
            }
        }
        
        let updateFunc = ctx.objectForKeyedSubscript("update")
        hasUpdateFunction = updateFunc?.isUndefined == false
        Logger.log("[WEScriptEngine] 初始化完成，是否包含 update 函数: \(hasUpdateFunction)")
    }
    
    func evaluateUpdate(value: Any) -> Any? {
        guard hasUpdateFunction, let updateFunc = context.objectForKeyedSubscript("update") else { return nil }
        
        var jsArg: JSValue?
        if let v3 = value as? SIMD3<Float> {
            jsArg = JSValue(newObjectIn: context)
            jsArg?.setValue(v3.x, forProperty: "x")
            jsArg?.setValue(v3.y, forProperty: "y")
            jsArg?.setValue(v3.z, forProperty: "z")
        } else {
            jsArg = JSValue(object: value, in: context)
        }
        
        if let result = updateFunc.call(withArguments: jsArg != nil ? [jsArg!] : []) {
            if result.isString { return result.toString() }
            if result.isNumber { return result.toNumber() }
            if result.isObject {
                if let xVal = result.objectForKeyedSubscript("x"),
                   let yVal = result.objectForKeyedSubscript("y"),
                   let xNum = xVal.toNumber(),
                   let yNum = yVal.toNumber() {
                    return SIMD3<Float>(xNum.floatValue, yNum.floatValue, 0)
                }
            }
        }
        
        return nil
    }
}
