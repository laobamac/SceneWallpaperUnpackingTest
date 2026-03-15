//
//  DebuggerState.swift
//  Renderer
//
//  Created by laobamac on 2026/3/15.
//

import SwiftUI
import Foundation
internal import Combine

enum DebuggerSelection: Hashable {
    case object(Int)
    case bone(Int, Int)
    case submesh(Int, Int)
    case texture(URL)
}

class DebuggerState: ObservableObject {
    static let shared = DebuggerState()

    @Published var sceneContext: SceneContext?
    @Published var selection: DebuggerSelection?
    
    @Published var hiddenMeshes: Set<String> = []
    @Published var hiddenObjects: Set<Int> = []
    @Published var hiddenBones: Set<String> = []

    func toggleMeshHidden(objectID: Int, meshIndex: Int) {
        let key = "\(objectID)_\(meshIndex)"
        if hiddenMeshes.contains(key) {
            hiddenMeshes.remove(key)
        } else {
            hiddenMeshes.insert(key)
        }
    }

    func isMeshHidden(objectID: Int, meshIndex: Int) -> Bool {
        return hiddenMeshes.contains("\(objectID)_\(meshIndex)")
    }
    
    func toggleObjectHidden(_ objectID: Int) {
        if hiddenObjects.contains(objectID) {
            hiddenObjects.remove(objectID)
        } else {
            hiddenObjects.insert(objectID)
        }
    }

    func isObjectHidden(_ objectID: Int) -> Bool {
        return hiddenObjects.contains(objectID)
    }
    
    func toggleBoneHidden(objectID: Int, boneIndex: Int) {
        let key = "\(objectID)_\(boneIndex)"
        if hiddenBones.contains(key) {
            hiddenBones.remove(key)
        } else {
            hiddenBones.insert(key)
        }
    }

    func isBoneHidden(objectID: Int, boneIndex: Int) -> Bool {
        return hiddenBones.contains("\(objectID)_\(boneIndex)")
    }
}
