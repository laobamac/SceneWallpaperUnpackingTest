import SwiftUI

@main
struct SceneWallpaperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
