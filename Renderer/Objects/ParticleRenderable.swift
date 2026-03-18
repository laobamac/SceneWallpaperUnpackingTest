//
//  ParticleRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/3/19.
//

import Foundation
import MetalKit
import simd

class ParticleRenderable: RenderableObject {
    var particleSystem: ParticleSystem
    var device: MTLDevice
    var texture: MTLTexture?
    var pipelineState: MTLRenderPipelineState?
    
    var instanceBuffer: MTLBuffer?
    var instanceCount: Int = 0
    var maxInstances: Int
    
    var lastUpdateTime: Double = 0
    
    init(device: MTLDevice, particleSystem: ParticleSystem, maxInstances: Int = 20000) {
        self.device = device
        self.particleSystem = particleSystem
        self.maxInstances = maxInstances
        
        let bufferSize = MemoryLayout<ParticleInstanceData>.stride * maxInstances
        self.instanceBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
    }
    
    func update(commandBuffer: MTLCommandBuffer) {
        let currentTime = Date().timeIntervalSince1970
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        particleSystem.frameTime = min(dt, 0.1)
        particleSystem.emitt()
        
        var instances: [ParticleInstanceData] = []
        
        func collectParticles(from subsystem: ParticleSubSystem) {
            for inst in subsystem.instances {
                if inst.isDeath { continue }
                for p in inst.particlesVec {
                    if ParticleModify.lifetimeOk(p) && !ParticleModify.isNew(p) {
                        let data = ParticleInstanceData(
                            position: (p.position.x, p.position.y, p.position.z),
                            size: p.size,
                            color: (p.color.x, p.color.y, p.color.z),
                            alpha: p.alpha,
                            rotation: (p.rotation.x, p.rotation.y, p.rotation.z),
                            padding: 0.0
                        )
                        instances.append(data)
                    }
                }
            }
            for child in subsystem.children {
                collectParticles(from: child)
            }
        }
        
        for sys in particleSystem.subsystems {
            collectParticles(from: sys)
        }
        
        instanceCount = min(instances.count, maxInstances)
        
        if instanceCount > 0, let buffer = instanceBuffer {
            let pointer = buffer.contents().bindMemory(to: ParticleInstanceData.self, capacity: maxInstances)
            for i in 0..<instanceCount {
                pointer[i] = instances[i]
            }
        }
    }
    
    func draw(encoder: MTLRenderCommandEncoder) {
        if instanceCount == 0 { return }
        guard let pipelineState = pipelineState, let buffer = instanceBuffer else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(buffer, offset: 0, index: 2)
        
        if let tex = texture {
            encoder.setFragmentTexture(tex, index: 0)
        }
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instanceCount)
    }
}
