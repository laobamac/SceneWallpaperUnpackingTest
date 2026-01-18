import SwiftUI

struct ContentView: View {
    @State private var wallpaperFolder: URL?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // 背景渲染层
            if let folder = wallpaperFolder {
                MetalWallpaperView(folderURL: folder)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Color.black.edgesIgnoringSafeArea(.all)
            }
            
            // UI 控制层 (当鼠标悬停时显示，或未加载时显示)
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
                    // 加载后提供一个小的浮动按钮来切换壁纸
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
        // 设置默认窗口大小
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
