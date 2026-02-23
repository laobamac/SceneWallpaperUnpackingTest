//
//  ShaderTranslator.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation
import Metal

enum ShaderTranslationError: Error {
    case compilationFailed(String)
    case translationFailed(String)
    case libraryCreationFailed(String)
}

class ShaderTranslator {
    static func translateAndCompile(device: MTLDevice,
                                    vertexGLSL: String,
                                    fragmentGLSL: String,
                                    macros: [String: String] = [:]) throws -> (MTLLibrary, ShaderReflectionMap) {

        let preprocessedVertex = GLSLPreprocessor.preprocess(source: vertexGLSL, isVertex: true, macros: macros)
        let preprocessedFragment = GLSLPreprocessor.preprocess(source: fragmentGLSL, isVertex: false, macros: macros)

        var vertError: NSError?
        guard let vertSpirv = ShadercWrapper.compileGLSLToSPIRV(preprocessedVertex, isVertex: true, error: &vertError) else {
            throw ShaderTranslationError.compilationFailed(vertError?.localizedDescription ?? "")
        }

        var fragError: NSError?
        guard let fragSpirv = ShadercWrapper.compileGLSLToSPIRV(preprocessedFragment, isVertex: false, error: &fragError) else {
            throw ShaderTranslationError.compilationFailed(fragError?.localizedDescription ?? "")
        }

        var vertTransError: NSError?
        guard let vertResult = SPIRVCrossWrapper.translateSPIRVToMSL(vertSpirv, isVertex: true, error: &vertTransError) else {
            throw ShaderTranslationError.translationFailed(vertTransError?.localizedDescription ?? "")
        }

        var fragTransError: NSError?
        guard let fragResult = SPIRVCrossWrapper.translateSPIRVToMSL(fragSpirv, isVertex: false, error: &fragTransError) else {
            throw ShaderTranslationError.translationFailed(fragTransError?.localizedDescription ?? "")
        }

        let combinedMSL = vertResult.mslSource + "\n" + fragResult.mslSource
        let options = MTLCompileOptions()

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: combinedMSL, options: options)
        } catch {
            throw ShaderTranslationError.libraryCreationFailed(error.localizedDescription)
        }

        let reflectionMap = ShaderReflectionMap(reflectionData: fragResult.reflectionMap)

        return (library, reflectionMap)
    }
}
