//
//  ScriptEngine.swift
//  Renderer
//
//  Created by laobamac on 2026/3/8.
//

import Foundation
import JavaScriptCore
import simd

class ScriptEngine {
    let context: JSContext
    var scriptProperties: [String: Any] = [:]

    init?(script: String, properties: [String: ScriptableValue]?, canvasSize: SIMD2<Float>) {
        guard let ctx = JSContext() else { return nil }
        self.context = ctx

        let engineObj = JSValue(newObjectIn: ctx)
        let canvasSizeObj = JSValue(newObjectIn: ctx)
        canvasSizeObj?.setValue(canvasSize.x, forProperty: "x")
        canvasSizeObj?.setValue(canvasSize.y, forProperty: "y")
        engineObj?.setValue(canvasSizeObj, forProperty: "canvasSize")
        ctx.setObject(engineObj, forKeyedSubscript: "engine" as NSString)

        let createScriptProperties: @convention(block) () -> JSValue = {
            let propsObj = JSValue(newObjectIn: JSContext.current())
            
            let addCombo: @convention(block) (JSValue) -> JSValue = { _ in return propsObj! }
            let addCheckbox: @convention(block) (JSValue) -> JSValue = { _ in return propsObj! }
            let addText: @convention(block) (JSValue) -> JSValue = { _ in return propsObj! }
            let addSlider: @convention(block) (JSValue) -> JSValue = { _ in return propsObj! }
            let finish: @convention(block) () -> JSValue = { return propsObj! }
            
            propsObj?.setValue(addCombo, forProperty: "addCombo")
            propsObj?.setValue(addCheckbox, forProperty: "addCheckbox")
            propsObj?.setValue(addText, forProperty: "addText")
            propsObj?.setValue(addSlider, forProperty: "addSlider")
            propsObj?.setValue(finish, forProperty: "finish")
            
            return propsObj!
        }
        ctx.setObject(createScriptProperties, forKeyedSubscript: "createScriptProperties" as NSString)

        if let props = properties {
            for (key, val) in props {
                switch val {
                case .string(let s): scriptProperties[key] = s
                case .bool(let b): scriptProperties[key] = b
                case .int(let i): scriptProperties[key] = i
                case .float(let f): scriptProperties[key] = f
                case .object(let dict):
                    if let v = dict["value"] {
                        switch v {
                        case .string(let s): scriptProperties[key] = s
                        case .bool(let b): scriptProperties[key] = b
                        case .int(let i): scriptProperties[key] = i
                        case .float(let f): scriptProperties[key] = f
                        default: break
                        }
                    }
                case .complex(_, let v, let p):
                    if let validV = v {
                        scriptProperties[key] = validV
                    } else if let validP = p?["value"] {
                        switch validP {
                        case .string(let s): scriptProperties[key] = s
                        case .bool(let b): scriptProperties[key] = b
                        case .int(let i): scriptProperties[key] = i
                        case .float(let f): scriptProperties[key] = f
                        default: break
                        }
                    }
                default: break
                }
            }
        }

        let transformedScript = script.replacingOccurrences(of: "export var ", with: "var ")
                                      .replacingOccurrences(of: "export let ", with: "let ")
                                      .replacingOccurrences(of: "export function ", with: "function ")
                                      .replacingOccurrences(of: "'use strict';", with: "")
        
        ctx.evaluateScript(transformedScript)

        if let jsProps = ctx.objectForKeyedSubscript("scriptProperties") {
            for (key, val) in scriptProperties {
                jsProps.setValue(val, forProperty: key)
            }
        }
    }

    func evaluateUpdate(value: Any) -> Any? {
        guard let updateFunc = context.objectForKeyedSubscript("update"), !updateFunc.isUndefined else {
            return nil
        }
        
        let valObj: Any
        if let vec3 = value as? SIMD3<Float> {
            let jsVec = JSValue(newObjectIn: context)
            jsVec?.setValue(vec3.x, forProperty: "x")
            jsVec?.setValue(vec3.y, forProperty: "y")
            jsVec?.setValue(vec3.z, forProperty: "z")
            valObj = jsVec as Any
        } else {
            valObj = value
        }
        
        let result = updateFunc.call(withArguments: [valObj])
        
        if result?.isString ?? false {
            return result?.toString()
        } else if result?.isObject ?? false {
            let x = Float(result?.objectForKeyedSubscript("x")?.toDouble() ?? 0)
            let y = Float(result?.objectForKeyedSubscript("y")?.toDouble() ?? 0)
            let z = Float(result?.objectForKeyedSubscript("z")?.toDouble() ?? 0)
            return SIMD3<Float>(x, y, z)
        }
        return nil
    }
}
