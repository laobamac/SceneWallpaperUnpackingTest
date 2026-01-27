//
//  MetalWallpaperView.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import SwiftUI
import MetalKit

struct MetalWallpaperView: NSViewRepresentable {
    var folderURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        
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
                mtkView.delegate = renderer
            } else {
                Logger.error("Failed to initialize Renderer")
            }
        } else {
            Logger.error("System does not support Metal")
        }
        
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        if let url = folderURL, url != context.coordinator.loadedURL {
            context.coordinator.renderer?.loadScene(folder: url)
            context.coordinator.loadedURL = url
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
