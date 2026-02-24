//
//  EffectType.swift
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//

import Foundation
import Metal
import MetalKit

protocol EffectType {
    var id: Int { get set }
    var isVisible: Bool { get set }
    var effectName: String { get }
    
    func load(device: MTLDevice, library: MTLLibrary, passJSON: EffectPassJSON, baseFolder: URL) async throws
    func update(dt: Float, time: Float, size: CGSize)
    func encode(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture, destinationTexture: MTLTexture)
}
