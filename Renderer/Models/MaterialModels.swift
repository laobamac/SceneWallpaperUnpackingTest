//
//  MaterialModels.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation

struct MaterialConfig: Codable {
    let passes: [MaterialPassConfig]?
}

struct MaterialPassConfig: Codable {
    let shader: String?
    let blending: String?
    let cullmode: String?
    let depthtest: String?
    let depthwrite: String?
    let textures: [String]?
    let constantshadervalues: [String: ScriptableValue]?
}
