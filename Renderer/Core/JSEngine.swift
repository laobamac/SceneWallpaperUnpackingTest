//
//  JSEngine.swift
//  Renderer
//
//  Created by laobamac on 2026/2/26.
//

import Foundation
import JavaScriptCore
import simd

@objc protocol Vec3Export: JSExport {
    var x: Double { get set }
    var y: Double { get set }
    var z: Double { get set }
    init(_ x: Double, _ y: Double, _ z: Double)
    func multiply(_ scalar: Double) -> Vec3
    func add(_ other: Vec3) -> Vec3
    func subtract(_ other: Vec3) -> Vec3
}

@objc class Vec3: NSObject, Vec3Export {
    dynamic var x: Double
    dynamic var y: Double
    dynamic var z: Double

    required init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    func multiply(_ scalar: Double) -> Vec3 {
        return Vec3(x * scalar, y * scalar, z * scalar)
    }

    func add(_ other: Vec3) -> Vec3 {
        return Vec3(x + other.x, y + other.y, z + other.z)
    }

    func subtract(_ other: Vec3) -> Vec3 {
        return Vec3(x - other.x, y - other.y, z - other.z)
    }
}

@objc protocol WEMathExport: JSExport {
    func mix(_ x: Double, _ y: Double, _ a: Double) -> Double
}

@objc class WEMath: NSObject, WEMathExport {
    func mix(_ x: Double, _ y: Double, _ a: Double) -> Double {
        return x * (1.0 - a) + y * a
    }
}

@objc protocol LocalStorageExport: JSExport {
    func get(_ key: String) -> JSValue?
    func set(_ key: String, _ value: JSValue)
    func remove(_ key: String)
}

@objc class LocalStorage: NSObject, LocalStorageExport {
    private var storage: [String: Any] = [:]

    func get(_ key: String) -> JSValue? {
        guard let value = storage[key] else { return nil }
        return JSValue(object: value, in: JSContext.current())
    }

    func set(_ key: String, _ value: JSValue) {
        storage[key] = value.toObject()
    }

    func remove(_ key: String) {
        storage.removeValue(forKey: key)
    }
}

class JSEngine {
    let context: JSContext
    let sharedObject: JSValue
    let localStorage: LocalStorage

    init() {
        context = JSContext()
        localStorage = LocalStorage()
        
        context.setObject(Vec3.self, forKeyedSubscript: "Vec3" as NSString)
        
        let weMath = WEMath()
        context.setObject(weMath, forKeyedSubscript: "WEMath" as NSString)
        
        context.setObject(localStorage, forKeyedSubscript: "localStorage" as NSString)
        
        sharedObject = JSValue(newObjectIn: context)
        context.setObject(sharedObject, forKeyedSubscript: "shared" as NSString)
        
        let createScriptPropertiesJS = """
        function() {
            var props = {};
            return {
                addCheckbox: function(dict) { if(dict && dict.name && dict.value !== undefined) props[dict.name] = dict.value; return this; },
                addSlider: function(dict) { if(dict && dict.name && dict.value !== undefined) props[dict.name] = dict.value; return this; },
                addText: function(dict) { if(dict && dict.name && dict.value !== undefined) props[dict.name] = dict.value; return this; },
                finish: function() { return props; }
            };
        }
        """
        context.evaluateScript("var createScriptProperties = " + createScriptPropertiesJS)
        
        context.exceptionHandler = { _, _ in }
    }
    
    func evaluate(_ script: String) -> JSValue? {
        var processedScript = script.replacingOccurrences(of: "export let", with: "let")
        processedScript = processedScript.replacingOccurrences(of: "export var", with: "var")
        processedScript = processedScript.replacingOccurrences(of: "export function", with: "function")
        processedScript = processedScript.replacingOccurrences(of: "import * as WEMath from 'WEMath';", with: "")
        
        let wrappedScript = """
        (function() {
            \(processedScript)
            return {
                init: typeof init !== 'undefined' ? init : undefined,
                update: typeof update !== 'undefined' ? update : undefined,
                cursorEnter: typeof cursorEnter !== 'undefined' ? cursorEnter : undefined,
                cursorLeave: typeof cursorLeave !== 'undefined' ? cursorLeave : undefined,
                cursorDown: typeof cursorDown !== 'undefined' ? cursorDown : undefined,
                cursorUp: typeof cursorUp !== 'undefined' ? cursorUp : undefined,
                cursorMove: typeof cursorMove !== 'undefined' ? cursorMove : undefined,
                applyUserProperties: typeof applyUserProperties !== 'undefined' ? applyUserProperties : undefined,
                scriptProperties: typeof scriptProperties !== 'undefined' ? scriptProperties : undefined
            };
        })();
        """
        return context.evaluateScript(wrappedScript)
    }
}
