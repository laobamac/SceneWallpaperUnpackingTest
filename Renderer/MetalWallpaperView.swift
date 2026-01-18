//
//  MetalWallpaperView.swift
//  Renderer
//
//  Created by laobamac on 2026/1/18.
//

import SwiftUI
import MetalKit

struct MetalWallpaperView: NSViewRepresentable {
    // 绑定的文件夹路径，当此值变化时，触发加载
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
            mtkView.preferredFramesPerSecond = 60
            mtkView.enableSetNeedsDisplay = false // 开启自动循环渲染
            mtkView.isPaused = false
            
            // 初始化 Renderer
            let renderer = Renderer(device: device)
            context.coordinator.renderer = renderer
            mtkView.delegate = renderer
        }
        
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // 检查 URL 是否变化
        if let url = folderURL, url != context.coordinator.loadedURL {
            context.coordinator.renderer?.loadScene(folder: url)
            context.coordinator.loadedURL = url
        }
    }

    class Coordinator: NSObject {
        var parent: MetalWallpaperView
        var renderer: Renderer?
        var loadedURL: URL? // 记录当前加载的URL，防止重复加载

        init(_ parent: MetalWallpaperView) {
            self.parent = parent
        }
    }
}
