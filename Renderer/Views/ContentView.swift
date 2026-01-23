//
//  ContentView.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import SwiftUI

struct ContentView: View {
    @State private var wallpaperFolder: URL?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            if let folder = wallpaperFolder {
                MetalWallpaperView(folderURL: folder)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Color.black.edgesIgnoringSafeArea(.all)
            }
            
            VStack {
                if wallpaperFolder == nil {
                    Text("Wallpaper Engine Metal Renderer")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding(.bottom, 20)
                    
                    Button("Open Wallpaper Folder") {
                        openFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Text("请选择包含 scene.json 和 project.json 的文件夹")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 10)
                } else {
                    if isHovering {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button("Change Wallpaper") {
                                    openFolder()
                                }
                                .buttonStyle(.bordered)
                                .background(Material.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .padding()
                            }
                        }
                    }
                }
            }
        }
        .onHover { hover in
            withAnimation {
                isHovering = hover
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Wallpaper Folder"
        panel.prompt = "Render"
        
        if panel.runModal() == .OK {
            self.wallpaperFolder = panel.url
        }
    }
}
