//
//  JSEngine.swift
//  Renderer
//
//  Created by laobamac on 2026/3/11.
//

import Foundation
import JavaScriptCore

class JSEngine {
    let context: JSContext
    var isReady: Bool = false
    
    init() {
        context = JSContext()!
        setupEnvironment()
    }
    
    private func setupEnvironment() {
        context.exceptionHandler = { context, exception in
        }
        
        let createScriptProperties: @convention(block) () -> JSValue = {
            let jsObj = JSValue(newObjectIn: self.context)!
            
            let block: @convention(block) (JSValue) -> JSValue = { _ in
                return JSContext.currentThis()!
            }
            
            jsObj.setObject(block, forKeyedSubscript: "addCombo" as NSString)
            jsObj.setObject(block, forKeyedSubscript: "addCheckbox" as NSString)
            jsObj.setObject(block, forKeyedSubscript: "addText" as NSString)
            jsObj.setObject(block, forKeyedSubscript: "addSlider" as NSString)
            jsObj.setObject(block, forKeyedSubscript: "addColor" as NSString)
            
            let finishBlock: @convention(block) () -> JSValue = {
                return JSContext.currentThis()!
            }
            jsObj.setObject(finishBlock, forKeyedSubscript: "finish" as NSString)
            
            return jsObj
        }
        
        context.setObject(createScriptProperties, forKeyedSubscript: "createScriptProperties" as NSString)
    }
    
    func loadScript(script: String, properties: [String: ScriptableValue]) {
        let cleanScript = script.replacingOccurrences(of: "export var scriptProperties", with: "var scriptProperties")
                                .replacingOccurrences(of: "export let", with: "let")
                                .replacingOccurrences(of: "export function update", with: "function update")
        
        context.evaluateScript("var engine = { canvasSize: { x: 1920, y: 1080 } };")
        context.evaluateScript(cleanScript)
        
        if let scriptProps = context.objectForKeyedSubscript("scriptProperties"), !scriptProps.isUndefined {
            for (key, value) in properties {
                switch value {
                case .string(let s):
                    scriptProps.setObject(s, forKeyedSubscript: key as NSString)
                case .bool(let b):
                    scriptProps.setObject(b, forKeyedSubscript: key as NSString)
                case .float(let f):
                    scriptProps.setObject(f, forKeyedSubscript: key as NSString)
                case .int(let i):
                    scriptProps.setObject(i, forKeyedSubscript: key as NSString)
                case .object(let dict):
                    if let v = dict["value"] {
                        switch v {
                        case .string(let s): scriptProps.setObject(s, forKeyedSubscript: key as NSString)
                        case .bool(let b): scriptProps.setObject(b, forKeyedSubscript: key as NSString)
                        case .float(let f): scriptProps.setObject(f, forKeyedSubscript: key as NSString)
                        case .int(let i): scriptProps.setObject(i, forKeyedSubscript: key as NSString)
                        default: break
                        }
                    }
                default: break
                }
            }
        }
        isReady = true
    }
    
    func evaluateUpdate(value: String) -> String {
        guard isReady else { return value }
        if let updateFunc = context.objectForKeyedSubscript("update"), !updateFunc.isUndefined {
            let result = updateFunc.call(withArguments: [value])
            if let str = result?.toString(), str != "undefined" {
                return str
            }
        }
        return value
    }
}
