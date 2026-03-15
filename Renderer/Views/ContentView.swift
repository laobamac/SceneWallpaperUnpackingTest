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
    @StateObject private var debuggerState = DebuggerState.shared

    var body: some View {
        ZStack {
            if wallpaperFolder != nil {
                HSplitView {
                    DebuggerSidebarView()
                        .frame(minWidth: 200, idealWidth: 250, maxWidth: 350)
                        .environmentObject(debuggerState)

                    mainRenderView
                        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)

                    InspectorPanelView()
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                        .environmentObject(debuggerState)
                }
            } else {
                mainRenderView
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
    }

    private var mainRenderView: some View {
        ZStack {
            if let folder = wallpaperFolder {
                MetalWallpaperView(folderURL: folder)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Color.black.edgesIgnoringSafeArea(.all)
            }
            
            VStack {
                if wallpaperFolder == nil {
                    Text("Wallpaper Engine Metal 渲染器")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding(.bottom, 20)
                    
                    Button("打开壁纸文件夹") {
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
                                Button("更换壁纸") {
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
    }
    
    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "选择壁纸文件夹"
        panel.prompt = "渲染"
        
        if panel.runModal() == .OK {
            self.wallpaperFolder = panel.url
        }
    }
}
