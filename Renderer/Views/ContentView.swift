//
//  ContentView.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import SwiftUI
import Combine

class BoneManager: ObservableObject {
    static let shared = BoneManager()
    @Published var puppets: [ObjectIdentifier: [(id: Int, name: String)]] = [:]
    @Published var puppetNames: [ObjectIdentifier: String] = [:]
    @Published var hiddenBones: [ObjectIdentifier: Set<Int>] = [:]
    
    func toggleBone(puppet: ObjectIdentifier, boneID: Int) {
        var hidden = hiddenBones[puppet] ?? Set<Int>()
        if hidden.contains(boneID) {
            hidden.remove(boneID)
        } else {
            hidden.insert(boneID)
        }
        hiddenBones[puppet] = hidden
    }
}

struct ContentView: View {
    @State private var wallpaperFolder: URL?
    @State private var isHovering = false
    @State private var showBones = false
    @ObservedObject var boneManager = BoneManager.shared

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
                                Button(showBones ? "Close Bone Settings" : "Bone Settings") {
                                    withAnimation {
                                        showBones.toggle()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .background(Material.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .padding(.trailing, 5)
                                
                                Button("Change Wallpaper") {
                                    openFolder()
                                }
                                .buttonStyle(.bordered)
                                .background(Material.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .padding(.trailing)
                            }
                            .padding(.bottom)
                        }
                    }
                }
            }
            
            if showBones && wallpaperFolder != nil {
                HStack {
                    Spacer()
                    VStack {
                        Text("Bone Settings")
                            .font(.headline)
                            .padding(.top)
                        ScrollView {
                            ForEach(Array(boneManager.puppets.keys), id: \.self) { puppetID in
                                if let bones = boneManager.puppets[puppetID], let name = boneManager.puppetNames[puppetID] {
                                    DisclosureGroup(name) {
                                        ForEach(bones, id: \.id) { bone in
                                            let isHidden = boneManager.hiddenBones[puppetID]?.contains(bone.id) ?? false
                                            Toggle(bone.name, isOn: Binding(
                                                get: { !isHidden },
                                                set: { _ in boneManager.toggleBone(puppet: puppetID, boneID: bone.id) }
                                            ))
                                            .padding(.leading, 10)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .frame(width: 250)
                    .background(Material.regular)
                    .cornerRadius(12)
                    .padding()
                    .padding(.trailing, 20)
                    .shadow(radius: 10)
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
