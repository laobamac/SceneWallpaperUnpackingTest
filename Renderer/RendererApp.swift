import SwiftUI

@main
struct SceneWallpaperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // 隐藏默认标题栏背景，让渲染内容填满
                .background(Color.black)
        }
        // 可以根据需要设置窗口样式
        .windowStyle(.hiddenTitleBar)
    }
}
