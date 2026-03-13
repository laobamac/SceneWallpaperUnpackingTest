//
//  SceneLoader.swift
//  Renderer
//
//  Created by laobamac on 2026/3/13.
//

import Foundation
import MetalKit

struct SceneContext {
    var baseFolder: URL?
    var renderables: [RenderableObject] = []
    var projectionSize: CGSize = CGSize(width: 1920, height: 1080)
    var currentFOV: Float = 50.0
    var bloomThreshold: Float = 1.0
    var bloomStrength: Float = 2.0
    var bloomIterations: Int = 8
    var isHDREnabled: Bool = false
}

class SceneLoader {
    let device: MTLDevice
    let pipelineManager: PipelineManager

    init(device: MTLDevice, pipelineManager: PipelineManager) {
        self.device = device
        self.pipelineManager = pipelineManager
    }

    func loadScene(folder: URL) async -> SceneContext {
        var context = SceneContext()
        context.baseFolder = folder
        let secured = folder.startAccessingSecurityScopedResource()
        defer { if secured { folder.stopAccessingSecurityScopedResource() } }

        await TextureManager.shared.setup(device: device)
        await TextureManager.shared.clear()

        let projectURL = folder.appendingPathComponent("project.json")
        do {
            let projData = try Data(contentsOf: projectURL)
            guard let projJson = try JSONSerialization.jsonObject(with: projData, options: []) as? [String: Any],
                  let sceneFile = projJson["file"] as? String else { return context }

            let sceneURL = folder.appendingPathComponent(sceneFile)
            let sceneData = try Data(contentsOf: sceneURL)
            let sceneRoot = try JSONDecoder().decode(SceneRoot.self, from: sceneData)

            var rawObjects: [Int: [String: Any]] = [:]
            if let sceneDict = try JSONSerialization.jsonObject(with: sceneData) as? [String: Any],
               let objs = sceneDict["objects"] as? [[String: Any]] {
                for o in objs {
                    if let id = o["id"] as? Int {
                        rawObjects[id] = o
                    }
                }
            }

            var isBloomEnabled = false
            if let sceneDict = try? JSONSerialization.jsonObject(with: sceneData) as? [String: Any],
               let genDict = sceneDict["general"] as? [String: Any] {
                if let bloom = genDict["bloom"] as? Bool { isBloomEnabled = bloom }
                if let hdr = genDict["hdr"] as? Bool { context.isHDREnabled = hdr }
            }

            if let gen = sceneRoot.general {
                context.bloomThreshold = gen.bloomhdrthreshold ?? 1.0
                context.bloomStrength = isBloomEnabled ? (gen.bloomhdrstrength ?? 2.0) : 0.0
                context.bloomIterations = isBloomEnabled ? (gen.bloomhdriterations ?? 8) : 0
            }

            if let proj = sceneRoot.general?.orthogonalprojection {
                context.projectionSize = CGSize(width: Double(proj.width), height: Double(proj.height))
            }

            if let fov = sceneRoot.general?.fov { context.currentFOV = fov }
            if let overrideFov = sceneRoot.general?.perspectiveoverridefov, overrideFov > 0 {
                context.currentFOV = overrideFov
            }

            var tempRenderables: [Int: RenderableObject] = [:]
            var orderedList: [RenderableObject] = []

            for obj in sceneRoot.objects {
                if !obj.isVisible { continue }
                let rawObj = rawObjects[obj.id ?? -1]
                if let renderable = await createRenderable(from: obj, raw: rawObj, baseFolder: folder) {
                    if let id = obj.id {
                        tempRenderables[id] = renderable
                        renderable.id = id
                    }
                    renderable.parentId = obj.parent
                    orderedList.append(renderable)
                }
            }

            for renderable in orderedList {
                if let pid = renderable.parentId, let parentObj = tempRenderables[pid] {
                    renderable.parent = parentObj
                }
            }
            context.renderables = orderedList
        } catch {}
        return context
    }

    private func createRenderable(from obj: SceneObject, raw: [String: Any]?, baseFolder: URL) async -> RenderableObject? {
        guard let imagePath = obj.image else { return nil }
        let modelURL = baseFolder.appendingPathComponent(imagePath)
        let fileName = modelURL.deletingPathExtension().lastPathComponent
        let puppetDataURL = modelURL.deletingLastPathComponent().appendingPathComponent("\(fileName)_puppet_data.json")
        let puppetObjURL = modelURL.deletingLastPathComponent().appendingPathComponent("\(fileName)_puppet.obj")

        if FileManager.default.fileExists(atPath: puppetDataURL.path) {
            return await createPuppetRenderable(from: obj, dataURL: puppetDataURL, objURL: puppetObjURL, baseFolder: baseFolder)
        }

        do {
            let modelData = try Data(contentsOf: modelURL)
            let modelDef = try JSONDecoder().decode(ModelJSON.self, from: modelData)
            guard let matPath = modelDef.material else { return nil }
            let matURL = baseFolder.appendingPathComponent(matPath)
            let matData = try Data(contentsOf: matURL)
            let matDef = try JSONDecoder().decode(MaterialJSON.self, from: matData)
            guard let firstPass = matDef.passes.first else { return nil }

            var texture: MTLTexture!
            if let texName = firstPass.textures.first {
                let texURL = resolveTextureURL(base: baseFolder, rawPath: texName)
                texture = try await TextureManager.shared.loadTexture(url: texURL, options: [.origin: MTKTextureLoader.Origin.topLeft, .SRGB: true])
            } else {
                let (_, _, size, _) = RenderableObject.parseTransforms(obj)
                let w = max(1, Int(size.x))
                let h = max(1, Int(size.y))
                let desc = MTLTextureDescriptor()
                desc.textureType = .type2DArray
                desc.pixelFormat = .rgba16Float
                desc.width = w
                desc.height = h
                desc.arrayLength = 1
                desc.usage = [.shaderRead, .renderTarget, .pixelFormatView]
                texture = device.makeTexture(descriptor: desc)!
                let bytes = [UInt8](repeating: 0, count: w * h * 8)
                texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, slice: 0, withBytes: bytes, bytesPerRow: w * 8, bytesPerImage: w * h * 8)
            }

            let (pos, rotation, size, scale) = RenderableObject.parseTransforms(obj)
            var depthState = pipelineManager.depthStencilState
            if let dw = firstPass.depthwrite, dw == "disabled" {
                depthState = pipelineManager.depthWriteDisabledState
            }
            guard let pipeline = pipelineManager.pipelineState else { return nil }
            return RenderableObject(position: pos, rotation: rotation, size: size, scale: scale, texture: texture, pipeline: pipeline, depthState: depthState)
        } catch { return nil }
    }

    private func createPuppetRenderable(from obj: SceneObject, dataURL: URL, objURL: URL, baseFolder: URL) async -> RenderableObject? {
        do {
            let jsonData = try Data(contentsOf: dataURL)
            let puppetData = try JSONDecoder().decode(PuppetData.self, from: jsonData)
            let objContent = try String(contentsOf: objURL, encoding: .utf8)
            guard let matFile = puppetData.info.material_file else { return nil }
            let matURL = baseFolder.appendingPathComponent(matFile)
            let matData = try Data(contentsOf: matURL)
            let matDef = try JSONDecoder().decode(MaterialJSON.self, from: matData)
            guard let firstPass = matDef.passes.first, let texName = firstPass.textures.first else { return nil }
            let texURL = resolveTextureURL(base: baseFolder, rawPath: texName)
            let texture = try await TextureManager.shared.loadTexture(url: texURL, options: [.origin: MTKTextureLoader.Origin.topLeft, .SRGB: true])

            let (vertices, indices, bboxWidth) = PuppetRenderable.parseOBJ(objContent: objContent, skinning: puppetData.skeleton.isEmpty ? [] : puppetData.skinning)
            let (pos, rotation, size, scale) = RenderableObject.parseTransforms(obj)
            var depthState = pipelineManager.depthStencilState
            if let dw = firstPass.depthwrite, dw == "disabled" {
                depthState = pipelineManager.depthWriteDisabledState
            }

            var maskTextures: [MTLTexture] = []
            if let masks = puppetData.clipping_masks {
                Logger.log("[Puppet] 发现 Clipping Masks 纹理，数量: \(masks.count)")
                for (index, maskPath) in masks.enumerated() {
                    Logger.log("[Puppet] 准备加载 Mask [\(index)]: \(maskPath)")
                    let mURL = resolveTextureURL(base: baseFolder, rawPath: maskPath)
                    if let mTex = try? await TextureManager.shared.loadTexture(url: mURL, options: [.origin: MTKTextureLoader.Origin.topLeft, .SRGB: false]) {
                        maskTextures.append(mTex)
                        Logger.log("[Puppet] Mask [\(index)] 加载成功: \(mTex.width)x\(mTex.height)")
                    } else {
                        Logger.log("[Puppet] Mask [\(index)] 加载失败!")
                    }
                }
            } else {
                Logger.log("[Puppet] 当前模型没有 clipping_masks 字段")
            }

            guard let pipeline = pipelineManager.puppetPipelineState, let maskPipe = pipelineManager.puppetMaskPipelineState else { return nil }
            return PuppetRenderable(device: device, vertices: vertices, indices: indices, subMeshes: puppetData.sub_meshes, maskBindings: puppetData.mask_bindings, skeleton: puppetData.skeleton, animations: puppetData.animations, position: pos, rotation: rotation, size: size, scale: scale, texture: texture, maskTextures: maskTextures, maskWriteState: pipelineManager.maskWriteState, maskTestState: pipelineManager.maskTestState, puppetMaskPipeline: maskPipe, pipeline: pipeline, depthState: depthState, usePixelCoords: bboxWidth > 2.0)
        } catch { return nil }
    }

    private func resolveTextureURL(base: URL, rawPath: String) -> URL {
        let extensions = ["png", "webp", "tga", "mp4"]
        let fileName = URL(fileURLWithPath: rawPath).lastPathComponent
        for ext in extensions {
            let directURL = base.appendingPathComponent("materials/\(rawPath).\(ext)")
            if FileManager.default.fileExists(atPath: directURL.path) { return directURL }
            let flatURL = base.appendingPathComponent("materials/\(fileName).\(ext)")
            if FileManager.default.fileExists(atPath: flatURL.path) { return flatURL }
            let folderURL = base.appendingPathComponent(rawPath).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: folderURL.path) { return folderURL }
        }
        return base.appendingPathComponent("materials/\(fileName).png")
    }
}
