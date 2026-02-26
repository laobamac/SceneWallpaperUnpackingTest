//
//  MetalWallpaperView.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import SwiftUI
import MetalKit
import AppKit

class InteractiveMTKView: MTKView {
    weak var renderer: Renderer?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
    }
    
    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        renderer?.updateMousePosition(loc, in: self)
    }
    
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        renderer?.mouseDown(at: loc, in: self)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        renderer?.updateMousePosition(loc, in: self)
    }
    
    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        renderer?.mouseUp(at: loc, in: self)
    }
}

struct MetalWallpaperView: NSViewRepresentable {
    var folderURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> InteractiveMTKView {
        let mtkView = InteractiveMTKView()
        
        if let device = MTLCreateSystemDefaultDevice() {
            mtkView.device = device
            mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            mtkView.colorPixelFormat = .bgra8Unorm
            mtkView.depthStencilPixelFormat = .depth32Float_stencil8
            mtkView.preferredFramesPerSecond = 60
            mtkView.enableSetNeedsDisplay = false
            mtkView.isPaused = false
            
            if let renderer = Renderer(device: device) {
                context.coordinator.renderer = renderer
                mtkView.renderer = renderer
                mtkView.delegate = renderer
            }
        }
        
        return mtkView
    }

    func updateNSView(_ nsView: InteractiveMTKView, context: Context) {
        if let url = folderURL, url != context.coordinator.loadedURL {
            context.coordinator.loadedURL = url
            Task {
                await context.coordinator.renderer?.loadScene(folder: url)
            }
        }
    }

    class Coordinator: NSObject {
        var parent: MetalWallpaperView
        var renderer: Renderer?
        var loadedURL: URL?

        init(_ parent: MetalWallpaperView) {
            self.parent = parent
        }
    }
}
