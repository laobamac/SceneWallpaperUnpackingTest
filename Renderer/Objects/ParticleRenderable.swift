//
//  ParticleRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/3/15.
//

import MetalKit
import simd

class ParticleRenderable {
    let particleSystem: ParticleSystem
    var pipelineState: MTLRenderPipelineState?
    var texture: MTLTexture?
    
    var vertexBuffer: MTLBuffer?
    var indexBuffer: MTLBuffer?
    var instanceBuffer: MTLBuffer?
    
    var activeInstanceCount: Int = 0
    let maxInstances: Int
    
    init(device: MTLDevice, particleSystem: ParticleSystem) {
        self.particleSystem = particleSystem
        self.maxInstances = particleSystem.maxCount
        
        print("ParticleRenderable: Initializing with maxInstances: \(self.maxInstances)")
        
        setupBuffers(device: device)
    }
    
    private func setupBuffers(device: MTLDevice) {
        let halfSize: Float = 0.5
        let vertices: [Float] = [
            -halfSize, -halfSize, 0.0,  0.0, 1.0,
             halfSize, -halfSize, 0.0,  1.0, 1.0,
            -halfSize,  halfSize, 0.0,  0.0, 0.0,
             halfSize,  halfSize, 0.0,  1.0, 0.0
        ]
        
        let indices: [UInt16] = [
            0, 1, 2,
            1, 3, 2
        ]
        
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: .storageModeShared)
        indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared)
        
        let instanceBufferSize = maxInstances * MemoryLayout<ParticleInstanceData>.stride
        if instanceBufferSize > 0 {
            instanceBuffer = device.makeBuffer(length: instanceBufferSize, options: .storageModeShared)
        }
        
        print("ParticleRenderable: Buffers created successfully")
    }
    
    func update(deltaTime: Float) {
        let instanceDataArray = particleSystem.update(deltaTime: deltaTime)
        activeInstanceCount = min(instanceDataArray.count, maxInstances)
        
        if activeInstanceCount > 0, let buffer = instanceBuffer {
            let pointer = buffer.contents().bindMemory(to: ParticleInstanceData.self, capacity: activeInstanceCount)
            for i in 0..<activeInstanceCount {
                pointer[i] = instanceDataArray[i]
            }
        }
    }
    
    func draw(in view: MTKView, renderEncoder: MTLRenderCommandEncoder, globalUniformsBuffer: MTLBuffer) {
        guard activeInstanceCount > 0 else { return }
        guard let pipelineState = pipelineState else {
            print("ParticleRenderable: Pipeline state is missing")
            return
        }
        guard let vBuffer = vertexBuffer, let iBuffer = indexBuffer, let instBuffer = instanceBuffer else {
            print("ParticleRenderable: Required buffers are missing")
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        
        renderEncoder.setVertexBuffer(vBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(instBuffer, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(globalUniformsBuffer, offset: 0, index: 2)
        
        if let tex = texture {
            renderEncoder.setFragmentTexture(tex, index: 0)
        }
        
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: iBuffer,
            indexBufferOffset: 0,
            instanceCount: activeInstanceCount
        )
    }
}
