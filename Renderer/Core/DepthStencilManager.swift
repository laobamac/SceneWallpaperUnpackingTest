//
//  DepthStencilManager.swift
//  Renderer
//
//  Created by laobamac on 2026/2/26.
//

import MetalKit

class DepthStencilManager {
    let device: MTLDevice
    
    var depthStencilState: MTLDepthStencilState?
    var depthWriteDisabledState: MTLDepthStencilState?
    var particleDepthState: MTLDepthStencilState?
    var maskWriteState: MTLDepthStencilState?
    var maskTestState: MTLDepthStencilState?
    
    init(device: MTLDevice) {
        self.device = device
        setupStates()
    }
    
    func setupStates() {
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.isDepthWriteEnabled = true
        depthDesc.depthCompareFunction = .lessEqual
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)

        let depthDisabledDesc = MTLDepthStencilDescriptor()
        depthDisabledDesc.isDepthWriteEnabled = false
        depthDisabledDesc.depthCompareFunction = .lessEqual
        depthWriteDisabledState = device.makeDepthStencilState(descriptor: depthDisabledDesc)

        let particleDepthDesc = MTLDepthStencilDescriptor()
        particleDepthDesc.isDepthWriteEnabled = false
        particleDepthDesc.depthCompareFunction = .lessEqual
        particleDepthState = device.makeDepthStencilState(descriptor: particleDepthDesc)

        let maskWriteDesc = MTLDepthStencilDescriptor()
        maskWriteDesc.isDepthWriteEnabled = false
        maskWriteDesc.depthCompareFunction = .always
        let sw = MTLStencilDescriptor()
        sw.stencilCompareFunction = .always
        sw.stencilFailureOperation = .keep
        sw.depthFailureOperation = .keep
        sw.depthStencilPassOperation = .replace
        sw.readMask = 0xFF
        sw.writeMask = 0xFF
        maskWriteDesc.frontFaceStencil = sw
        maskWriteDesc.backFaceStencil = sw
        maskWriteState = device.makeDepthStencilState(descriptor: maskWriteDesc)

        let maskTestDesc = MTLDepthStencilDescriptor()
        maskTestDesc.isDepthWriteEnabled = false
        maskTestDesc.depthCompareFunction = .always
        let st = MTLStencilDescriptor()
        st.stencilCompareFunction = .equal
        st.stencilFailureOperation = .keep
        st.depthFailureOperation = .keep
        st.depthStencilPassOperation = .keep
        st.readMask = 0xFF
        st.writeMask = 0x00
        maskTestDesc.frontFaceStencil = st
        maskTestDesc.backFaceStencil = st
        maskTestState = device.makeDepthStencilState(descriptor: maskTestDesc)
    }
}
