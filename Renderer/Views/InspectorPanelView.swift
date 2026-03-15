//
//  InspectorPanelView.swift
//  Renderer
//
//  Created by laobamac on 2026/3/15.
//

import SwiftUI
import CoreImage
internal import simd

struct InspectorPanelView: View {
    @EnvironmentObject var debuggerState: DebuggerState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("属性与详情面板")
                .font(.headline)
                .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let selection = debuggerState.selection {
                        buildInspectorContent(for: selection)
                    } else {
                        Text("未选中任何对象")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 50)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private func buildInspectorContent(for selection: DebuggerSelection) -> some View {
        switch selection {
        case .object(let id):
            if let obj = debuggerState.sceneContext?.renderables.first(where: { $0.id == id }) {
                Text("对象 ID: \(obj.id)").font(.title3.bold())
                Text("父节点 ID: \(obj.parentId?.description ?? "无")")
                
                Divider()
                let isObjectHidden = debuggerState.isObjectHidden(id)
                Button(action: {
                    debuggerState.toggleObjectHidden(id)
                }) {
                    Text(isObjectHidden ? "显示该对象" : "隐藏该对象")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isObjectHidden ? Color.blue : Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Divider()
                Text("变换信息").font(.headline)
                Text("位置: X:\(String(format: "%.3f", obj.localPosition.x)) Y:\(String(format: "%.3f", obj.localPosition.y)) Z:\(String(format: "%.3f", obj.localPosition.z))")
                Text("旋转: X:\(String(format: "%.3f", obj.localRotation.x)) Y:\(String(format: "%.3f", obj.localRotation.y)) Z:\(String(format: "%.3f", obj.localRotation.z))")
                Text("尺寸: W:\(String(format: "%.3f", obj.size.x)) H:\(String(format: "%.3f", obj.size.y))")
                Text("缩放: X:\(String(format: "%.3f", obj.scale.x)) Y:\(String(format: "%.3f", obj.scale.y)) Z:\(String(format: "%.3f", obj.scale.z))")
                Text("透明度: \(String(format: "%.3f", obj.alpha))")
                
                Divider()
                Text("渲染状态").font(.headline)
                Text("Pipeline: \(obj.pipeline.label ?? "未知")")
                let animInfo = obj.currentAnimInfo
                Text("动画信息: [\(String(format: "%.2f", animInfo.x)), \(String(format: "%.2f", animInfo.y)), \(String(format: "%.2f", animInfo.z)), \(String(format: "%.2f", animInfo.w))]")
                
                Divider()
                Text("纹理信息").font(.headline)
                Text("路径: \(obj.textureURL?.lastPathComponent ?? "无")")
                Text("尺寸: \(obj.texture.width) x \(obj.texture.height)")
                Text("像素格式: \(String(describing: obj.texture.pixelFormat))")
                Text("数组长度: \(obj.texture.arrayLength)")
                
                Divider()
                Text("当前帧预览").font(.headline)
                TexturePreviewView(texture: obj.texture, animInfo: obj.currentAnimInfo)
            }
            
        case .bone(let objId, let boneIndex):
            if let puppet = debuggerState.sceneContext?.renderables.first(where: { $0.id == objId }) as? PuppetRenderable {
                let bone = puppet.skeleton[boneIndex]
                Text("骨骼详情").font(.title3.bold())
                Text("名称: \(bone.name)")
                Text("ID: \(bone.id)")
                Text("父骨骼索引: \(bone.parent)")
                
                Divider()
                let isBoneHidden = debuggerState.isBoneHidden(objectID: objId, boneIndex: boneIndex)
                Button(action: {
                    debuggerState.toggleBoneHidden(objectID: objId, boneIndex: boneIndex)
                }) {
                    Text(isBoneHidden ? "显示该骨骼" : "隐藏该骨骼")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isBoneHidden ? Color.blue : Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Divider()
                Text("动态变换矩阵").font(.headline)
                if boneIndex < puppet.boneMatrices.count {
                    let mat = puppet.boneMatrices[boneIndex]
                    Text(String(format: "[%.3f, %.3f, %.3f, %.3f]", mat.columns.0.x, mat.columns.0.y, mat.columns.0.z, mat.columns.0.w))
                    Text(String(format: "[%.3f, %.3f, %.3f, %.3f]", mat.columns.1.x, mat.columns.1.y, mat.columns.1.z, mat.columns.1.w))
                    Text(String(format: "[%.3f, %.3f, %.3f, %.3f]", mat.columns.2.x, mat.columns.2.y, mat.columns.2.z, mat.columns.2.w))
                    Text(String(format: "[%.3f, %.3f, %.3f, %.3f]", mat.columns.3.x, mat.columns.3.y, mat.columns.3.z, mat.columns.3.w))
                }
            }
            
        case .submesh(let objId, let meshIndex):
            if let puppet = debuggerState.sceneContext?.renderables.first(where: { $0.id == objId }) as? PuppetRenderable,
               let subMeshes = puppet.subMeshes {
                let mesh = subMeshes[meshIndex]
                Text("子网格详情").font(.title3.bold())
                Text("网格索引: \(meshIndex)")
                Text("ID: \(mesh.id)")
                
                Divider()
                let isHidden = debuggerState.isMeshHidden(objectID: objId, meshIndex: meshIndex)
                Button(action: {
                    debuggerState.toggleMeshHidden(objectID: objId, meshIndex: meshIndex)
                }) {
                    Text(isHidden ? "显示该网格" : "隐藏该网格")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isHidden ? Color.blue : Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Divider()
                Text("对象纹理图集").font(.headline)
                TexturePreviewView(texture: puppet.texture, animInfo: puppet.currentAnimInfo)
            }
            
        case .texture(let url):
            Text("贴图路径: \(url.lastPathComponent)")
        }
    }
}

struct TexturePreviewView: View {
    var texture: MTLTexture?
    var animInfo: SIMD4<Float>?
    @State private var previewImage: NSImage?

    var body: some View {
        VStack {
            if let img = previewImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .background(CheckerboardView().opacity(0.5))
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
                    .frame(maxHeight: 250)
            } else {
                Text("无法生成预览")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .onAppear { generatePreview() }
        .onChange(of: animInfo) { _ in generatePreview() }
        .onChange(of: texture?.description ?? "") { _ in generatePreview() }
    }
    
    private func generatePreview() {
        guard let tex = texture else {
            previewImage = nil
            return
        }
        
        var targetTex = tex
        if tex.textureType == .type2DArray || tex.textureType == .typeCubeArray {
            if let view = tex.makeTextureView(pixelFormat: tex.pixelFormat, textureType: .type2D, levels: 0..<1, slices: 0..<1) {
                targetTex = view
            }
        }
        
        guard let ciImage = CIImage(mtlTexture: targetTex, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else {
            previewImage = nil
            return
        }
        
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -ciImage.extent.height))
        var finalCI = flipped
        
        if let anim = animInfo, anim != SIMD4<Float>(0, 0, 1, 1) {
            let width = ciImage.extent.width
            let height = ciImage.extent.height
            let cropRect = CGRect(
                x: CGFloat(anim.x) * width,
                y: (1.0 - CGFloat(anim.y) - CGFloat(anim.w)) * height,
                width: CGFloat(anim.z) * width,
                height: CGFloat(anim.w) * height
            )
            finalCI = flipped.cropped(to: cropRect)
        }
        
        let context = CIContext()
        if let cgImage = context.createCGImage(finalCI, from: finalCI.extent) {
            previewImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } else {
            previewImage = nil
        }
    }
}

struct CheckerboardView: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let size: CGFloat = 10
                let rows = Int(proxy.size.height / size) + 1
                let cols = Int(proxy.size.width / size) + 1
                for row in 0..<rows {
                    for col in 0..<cols {
                        if (row + col) % 2 == 0 {
                            path.addRect(CGRect(x: CGFloat(col) * size, y: CGFloat(row) * size, width: size, height: size))
                        }
                    }
                }
            }
            .fill(Color.gray.opacity(0.4))
        }
    }
}
