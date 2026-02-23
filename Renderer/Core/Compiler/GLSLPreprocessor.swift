//
//  GLSLPreprocessor.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation

class GLSLPreprocessor {
    static func preprocess(source: String, isVertex: Bool, macros: [String: String]) -> String {
        var lines = source.components(separatedBy: .newlines)
        var versionIndex = -1
        
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("#version") {
                versionIndex = index
                break
            }
        }
        
        var injectLines: [String] = []
        for (key, value) in macros {
            injectLines.append("#define \(key) \(value)")
        }
        
        if versionIndex != -1 {
            lines.insert(contentsOf: injectLines, at: versionIndex + 1)
        } else {
            lines.insert(contentsOf: injectLines, at: 0)
        }
        
        return lines.joined(separator: "\n")
    }
}
