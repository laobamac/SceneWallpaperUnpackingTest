//
//  DebuggerSidebarView.swift
//  Renderer
//
//  Created by laobamac on 2026/3/15.
//

import SwiftUI

struct DebuggerSidebarView: View {
    @EnvironmentObject var debuggerState: DebuggerState
    @State private var localSelection: DebuggerSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("场景层级树")
                .font(.headline)
                .padding()
            
            Divider()
            
            if let context = debuggerState.sceneContext {
                List(selection: $localSelection) {
                    ForEach(context.renderables.filter { $0.parentId == nil }, id: \.id) { obj in
                        RenderableNodeView(object: obj, allObjects: context.renderables)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: localSelection) { newValue in
                    if debuggerState.selection != newValue {
                        debuggerState.selection = newValue
                    }
                }
                .onChange(of: debuggerState.selection) { newValue in
                    if localSelection != newValue {
                        localSelection = newValue
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text("暂无场景数据")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct RenderableNodeView: View {
    var object: RenderableObject
    var allObjects: [RenderableObject]
    
    @EnvironmentObject var debuggerState: DebuggerState
    @State private var isExpanded: Bool = true
    
    var body: some View {
        let children = allObjects.filter { $0.parentId == object.id }
        let isPuppet = object is PuppetRenderable
        let hasSubNodes = !children.isEmpty || isPuppet
        
        let objectLabel = HStack {
            Text("对象 [ID:\(object.id)]")
            Spacer()
            Image(systemName: debuggerState.isObjectHidden(object.id) ? "eye.slash" : "eye")
                .foregroundColor(debuggerState.isObjectHidden(object.id) ? .red : .primary)
                .onTapGesture {
                    debuggerState.toggleObjectHidden(object.id)
                }
        }
        
        if hasSubNodes {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let puppet = object as? PuppetRenderable {
                    DisclosureGroup("骨骼列表") {
                        ForEach(puppet.skeleton.indices, id: \.self) { i in
                            let bone = puppet.skeleton[i]
                            HStack {
                                Text("骨骼: \(bone.name) (ID: \(bone.id))")
                                Spacer()
                                Image(systemName: debuggerState.isBoneHidden(objectID: object.id, boneIndex: i) ? "eye.slash" : "eye")
                                    .foregroundColor(debuggerState.isBoneHidden(objectID: object.id, boneIndex: i) ? .red : .primary)
                                    .onTapGesture {
                                        debuggerState.toggleBoneHidden(objectID: object.id, boneIndex: i)
                                    }
                            }
                            .tag(DebuggerSelection.bone(object.id, i))
                        }
                    }
                    
                    if let subMeshes = puppet.subMeshes {
                        DisclosureGroup("子网格 (SubMeshes)") {
                            ForEach(subMeshes.indices, id: \.self) { i in
                                let mesh = subMeshes[i]
                                HStack {
                                    Text("网格 \(i) (ID: \(mesh.id))")
                                    Spacer()
                                    Image(systemName: debuggerState.isMeshHidden(objectID: object.id, meshIndex: i) ? "eye.slash" : "eye")
                                        .foregroundColor(debuggerState.isMeshHidden(objectID: object.id, meshIndex: i) ? .red : .primary)
                                        .onTapGesture {
                                            debuggerState.toggleMeshHidden(objectID: object.id, meshIndex: i)
                                        }
                                }
                                .tag(DebuggerSelection.submesh(object.id, i))
                            }
                        }
                    }
                }
                
                ForEach(children, id: \.id) { child in
                    RenderableNodeView(object: child, allObjects: allObjects)
                }
            } label: {
                objectLabel
                    .tag(DebuggerSelection.object(object.id))
            }
        } else {
            objectLabel
                .tag(DebuggerSelection.object(object.id))
        }
    }
}
