//
//  PuppetRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import CoreGraphics
import Foundation
import MetalKit
import simd

class PuppetRenderable: RenderableObject {
    let device: MTLDevice
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int

    let uniformBuffer: MTLBuffer
    var boneMatrices: [matrix_float4x4]

    let usePixelCoords: Bool
    let skeleton: [PuppetBone]
    let animations: [PuppetAnimation]
    let animationLayers: [AnimationLayer]
    var inverseBindMatrices: [matrix_float4x4] = []

    let subMeshes: [PuppetSubMesh]?
    let maskBindings: [PuppetMaskBinding]?
    let maskTextures: [MTLTexture]

    let maskWriteState: MTLDepthStencilState?
    let maskTestState: MTLDepthStencilState?
    let puppetMaskPipeline: MTLRenderPipelineState?

    private var lastAnimCycle: Int = -1
    private var boneToTrackIndex: [Int: Int] = [:]

    init?(
        device: MTLDevice,
        vertices: [PuppetVertex],
        indices: [UInt32],
        subMeshes: [PuppetSubMesh]?,
        maskBindings: [PuppetMaskBinding]?,
        skeleton: [PuppetBone],
        animations: [PuppetAnimation],
        animationLayers: [AnimationLayer],
        position: SIMD3<Float>,
        rotation: SIMD3<Float>,
        size: SIMD2<Float>,
        scale: SIMD3<Float>,
        texture: MTLTexture,
        maskTextures: [MTLTexture],
        maskWriteState: MTLDepthStencilState?,
        maskTestState: MTLDepthStencilState?,
        puppetMaskPipeline: MTLRenderPipelineState?,
        pipeline: MTLRenderPipelineState,
        depthState: MTLDepthStencilState?,
        usePixelCoords: Bool
    ) {
        self.device = device

        Logger.log("[Puppet] === 开始初始化 PuppetRenderable ===")
        Logger.log(
            "[Puppet] 顶点数量: \(vertices.count), 索引数量: \(indices.count), 是否使用像素坐标: \(usePixelCoords)"
        )

        guard
            let vb = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<PuppetVertex>.stride,
                options: .storageModeShared
            )
        else {
            Logger.log("[Puppet] 错误: 创建顶点缓冲区失败")
            return nil
        }
        self.vertexBuffer = vb

        guard
            let ib = device.makeBuffer(
                bytes: indices,
                length: indices.count * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            )
        else {
            Logger.log("[Puppet] 错误: 创建索引缓冲区失败")
            return nil
        }
        self.indexBuffer = ib
        self.indexCount = indices.count

        self.usePixelCoords = usePixelCoords
        self.skeleton = skeleton
        self.animations = animations
        self.animationLayers = animationLayers
        self.subMeshes = subMeshes
        self.maskBindings = maskBindings
        self.maskTextures = maskTextures

        self.maskWriteState = maskWriteState
        self.maskTestState = maskTestState
        self.puppetMaskPipeline = puppetMaskPipeline

        if let sm = subMeshes {
            Logger.log("[Puppet] 发现 SubMeshes 数量: \(sm.count)")
            for (i, m) in sm.enumerated() {
                Logger.log(
                    "[Puppet] -> SubMesh[\(i)] ID: \(m.id), Start: \(m.start), Count: \(m.count)"
                )
            }
        } else {
            Logger.log("[Puppet] 未发现 SubMeshes 数据")
        }

        if let mb = maskBindings {
            Logger.log("[Puppet] 发现 Mask Bindings 数量: \(mb.count)")
            for (i, b) in mb.enumerated() {
                Logger.log(
                    "[Puppet] -> Binding[\(i)] TargetGroup: \(b.target_group), Mask: \(b.mask ?? -1)"
                )
            }
        } else {
            Logger.log("[Puppet] 未发现 Mask Bindings 数据")
        }

        Logger.log("[Puppet] 传入的 Mask Textures 数量: \(maskTextures.count)")
        Logger.log(
            "[Puppet] 传入骨骼节点数量: \(skeleton.count), 动画数量: \(animations.count)"
        )

        self.boneMatrices = Array(
            repeating: matrix_identity_float4x4,
            count: 100
        )
        guard
            let ub = device.makeBuffer(
                length: MemoryLayout<matrix_float4x4>.stride * 100,
                options: .storageModeShared
            )
        else {
            Logger.log("[Puppet] 错误: 创建骨骼 Uniform 缓冲区失败")
            return nil
        }
        self.uniformBuffer = ub

        super.init(
            position: position,
            rotation: rotation,
            size: size,
            scale: scale,
            texture: texture,
            pipeline: pipeline,
            depthState: depthState
        )

        computeInverseBindMatrices()

        if let firstAnim = animations.first {
            Logger.log(
                "[Puppet] 开始绑定动画轨道 <\(firstAnim.name)>, Tracks: \(firstAnim.tracks.count), FPS: \(firstAnim.fps), Length: \(firstAnim.length)"
            )
            for (index, track) in firstAnim.tracks.enumerated() {
                boneToTrackIndex[track.track_id] = index
            }
            Logger.log("[Puppet] 动画轨道绑定完成, 映射了 \(boneToTrackIndex.count) 个轨道")
        }

        let ptr = uniformBuffer.contents()
        ptr.copyMemory(
            from: &boneMatrices,
            byteCount: MemoryLayout<matrix_float4x4>.stride * 100
        )
        Logger.log("[Puppet] === PuppetRenderable 初始化完成 ===")
    }

    func getGlobalBindMatrix(boneIndex: Int, localMatrices: [matrix_float4x4])
        -> matrix_float4x4
    {
        if boneIndex < 0 || boneIndex >= skeleton.count {
            return matrix_identity_float4x4
        }
        let bone = skeleton[boneIndex]
        let local = localMatrices[boneIndex]
        if bone.parent >= 0 && bone.parent < skeleton.count {
            if bone.parent == boneIndex { return local }
            let parentGlobal = getGlobalBindMatrix(
                boneIndex: bone.parent,
                localMatrices: localMatrices
            )
            return parentGlobal * local
        }
        return local
    }

    func computeInverseBindMatrices() {
        Logger.log(
            "[Puppet] 开始计算 Inverse Bind Matrices (骨骼数量: \(skeleton.count))..."
        )
        inverseBindMatrices = Array(
            repeating: matrix_identity_float4x4,
            count: skeleton.count
        )
        var localMatrices = Array(
            repeating: matrix_identity_float4x4,
            count: skeleton.count
        )
        for i in 0..<skeleton.count {
            let m = skeleton[i].matrix
            localMatrices[i] = matrix_float4x4(
                columns: (
                    SIMD4<Float>(m[0], m[1], m[2], m[3]),
                    SIMD4<Float>(m[4], m[5], m[6], m[7]),
                    SIMD4<Float>(m[8], m[9], m[10], m[11]),
                    SIMD4<Float>(m[12], m[13], m[14], m[15])
                )
            )
        }
        for i in 0..<skeleton.count {
            let global = getGlobalBindMatrix(
                boneIndex: i,
                localMatrices: localMatrices
            )
            if abs(global.determinant) < 0.000001 {
                inverseBindMatrices[i] = matrix_identity_float4x4
            } else {
                inverseBindMatrices[i] = global.inverse
            }
        }
        Logger.log("[Puppet] Inverse Bind Matrices 计算完成")
    }

    func getGlobalAnimMatrix(
        boneIndex: Int,
        localMatrices: [matrix_float4x4],
        computed: inout [Bool],
        result: inout [matrix_float4x4]
    ) -> matrix_float4x4 {
        if boneIndex < 0 || boneIndex >= skeleton.count {
            return matrix_identity_float4x4
        }
        if computed[boneIndex] { return result[boneIndex] }
        let bone = skeleton[boneIndex]
        let local = localMatrices[boneIndex]
        var global = local
        if bone.parent >= 0 && bone.parent < skeleton.count
            && bone.parent != boneIndex
        {
            let parentGlobal = getGlobalAnimMatrix(
                boneIndex: bone.parent,
                localMatrices: localMatrices,
                computed: &computed,
                result: &result
            )
            global = parentGlobal * local
        }
        result[boneIndex] = global
        computed[boneIndex] = true
        return global
    }

    func updateAnimation(time: Float) {
        if animations.isEmpty { return }

        var localMatrices = Array(
            repeating: matrix_identity_float4x4,
            count: skeleton.count
        )
        for i in 0..<skeleton.count {
            let m = skeleton[i].matrix
            localMatrices[i] = matrix_float4x4(
                columns: (
                    SIMD4<Float>(m[0], m[1], m[2], m[3]),
                    SIMD4<Float>(m[4], m[5], m[6], m[7]),
                    SIMD4<Float>(m[8], m[9], m[10], m[11]),
                    SIMD4<Float>(m[12], m[13], m[14], m[15])
                )
            )
        }

        let activeLayers = animationLayers.filter { layer in
            if let v = layer.visible {
                if case .bool(let b) = v { return b }
                if case .object(let o) = v { return o.value ?? true }
            }
            return true
        }

        for layer in activeLayers {
            guard let animId = layer.animation,
                let anim = animations.first(where: { $0.id == animId })
            else { continue }

            let layerRate = layer.rate ?? 1.0
            let layerBlend = layer.blend ?? 1.0
            let fps = anim.fps > 0 ? anim.fps : 30.0
            let duration = Float(anim.length) / fps
            let t = (duration > 0) ? fmod(time * layerRate, duration) : 0

            for i in 0..<skeleton.count {
                let bone = skeleton[i]
                if let track = anim.tracks.first(where: {
                    $0.track_id == bone.id
                }), !track.frames.isEmpty {
                    let animMat: matrix_float4x4
                    if track.frames.count == 1 {
                        let k1 = track.frames[0]
                        let p = SIMD3<Float>(k1.p[0], k1.p[1], k1.p[2])
                        let r = SIMD3<Float>(k1.r[0], k1.r[1], k1.r[2])
                        let s = SIMD3<Float>(k1.s[0], k1.s[1], k1.s[2])
                        animMat =
                            Matrix4x4.translation(x: p.x, y: p.y, z: p.z)
                            * Quaternion.fromEuler(r).toMatrix()
                            * Matrix4x4.scale(x: s.x, y: s.y, z: s.z)
                    } else {
                        var idx0 = 0
                        for j in 0..<track.frames.count {
                            let fTime = track.frames[j].time ?? (Float(j) / fps)
                            if fTime <= t { idx0 = j }
                        }
                        let idx1 = (idx0 + 1) % track.frames.count
                        let k1 = track.frames[idx0]
                        let k2 = track.frames[idx1]
                        let t1 = k1.time ?? (Float(idx0) / fps)
                        var t2 = k2.time ?? (Float(idx1) / fps)
                        if idx1 == 0 { t2 = duration }
                        let fraction = (t2 > t1) ? (t - t1) / (t2 - t1) : 0
                        let p = mix(
                            SIMD3<Float>(k1.p[0], k1.p[1], k1.p[2]),
                            SIMD3<Float>(k2.p[0], k2.p[1], k2.p[2]),
                            t: fraction
                        )
                        let matR = Quaternion.slerp(
                            Quaternion.fromEuler(
                                SIMD3<Float>(k1.r[0], k1.r[1], k1.r[2])
                            ),
                            Quaternion.fromEuler(
                                SIMD3<Float>(k2.r[0], k2.r[1], k2.r[2])
                            ),
                            t: fraction
                        ).toMatrix()
                        let s = mix(
                            SIMD3<Float>(k1.s[0], k1.s[1], k1.s[2]),
                            SIMD3<Float>(k2.s[0], k2.s[1], k2.s[2]),
                            t: fraction
                        )
                        animMat =
                            Matrix4x4.translation(x: p.x, y: p.y, z: p.z) * matR
                            * Matrix4x4.scale(x: s.x, y: s.y, z: s.z)
                    }
                    let m1 = localMatrices[i]
                    let m2 = animMat
                    localMatrices[i] = matrix_float4x4(
                        columns: (
                            mix(m1.columns.0, m2.columns.0, t: layerBlend),
                            mix(m1.columns.1, m2.columns.1, t: layerBlend),
                            mix(m1.columns.2, m2.columns.2, t: layerBlend),
                            mix(m1.columns.3, m2.columns.3, t: layerBlend)
                        )
                    )
                }
            }
        }

        var globalComputed = Array(repeating: false, count: skeleton.count)
        var globalMatrices = Array(
            repeating: matrix_identity_float4x4,
            count: skeleton.count
        )
        for i in 0..<skeleton.count {
            let global = getGlobalAnimMatrix(
                boneIndex: i,
                localMatrices: localMatrices,
                computed: &globalComputed,
                result: &globalMatrices
            )
            let skinMatrix = global * inverseBindMatrices[i]
            if i < 100 { boneMatrices[i] = skinMatrix }
        }
        let ptr = uniformBuffer.contents()
        ptr.copyMemory(
            from: &boneMatrices,
            byteCount: MemoryLayout<matrix_float4x4>.stride * 100
        )
    }

    override func draw(encoder: MTLRenderCommandEncoder) {
        let geometryScale: matrix_float4x4
        if usePixelCoords {
            geometryScale = Matrix4x4.scale(x: 1.0, y: 1.0, z: 1.0)
        } else {
            geometryScale = Matrix4x4.scale(x: size.x, y: size.y, z: 1.0)
        }
        let finalModelMatrix = worldMatrix * geometryScale

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 3)

        var objUniforms = ObjectUniforms(
            modelMatrix: finalModelMatrix,
            alpha: 1.0,
            color: SIMD4<Float>(1, 1, 1, 1),
            animInfo: SIMD4<Float>(0, 0, 0, 0)
        )
        encoder.setVertexBytes(
            &objUniforms,
            length: MemoryLayout<ObjectUniforms>.size,
            index: 2
        )
        encoder.setFragmentBytes(
            &objUniforms,
            length: MemoryLayout<ObjectUniforms>.size,
            index: 2
        )

        let hasMaskLogic =
            maskBindings != nil && !maskBindings!.isEmpty
            && !maskTextures.isEmpty

        if hasMaskLogic, let maskTex = maskTextures.first,
            let maskWrite = maskWriteState, let maskTest = maskTestState,
            let maskPipe = puppetMaskPipeline
        {

            encoder.setRenderPipelineState(maskPipe)
            encoder.setDepthStencilState(maskWrite)
            encoder.setStencilReferenceValue(1)
            encoder.setFragmentTexture(maskTex, index: 0)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indexCount,
                indexType: .uint32,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )

            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)

            if let meshes = subMeshes {
                for (index, mesh) in meshes.enumerated() {
                    if maskBindings!.contains(where: {
                        $0.target_group == index
                    }) {
                        encoder.setDepthStencilState(maskTest)
                        encoder.setStencilReferenceValue(1)
                    } else {
                        if let ds = depthState {
                            encoder.setDepthStencilState(ds)
                        }
                    }

                    encoder.drawIndexedPrimitives(
                        type: .triangle,
                        indexCount: mesh.count,
                        indexType: .uint32,
                        indexBuffer: indexBuffer,
                        indexBufferOffset: mesh.start
                            * MemoryLayout<UInt32>.stride
                    )
                }
            }

        } else {
            encoder.setRenderPipelineState(pipeline)
            if let ds = depthState { encoder.setDepthStencilState(ds) }
            encoder.setFragmentTexture(texture, index: 0)

            if let meshes = subMeshes, !meshes.isEmpty {
                for mesh in meshes {
                    encoder.drawIndexedPrimitives(
                        type: .triangle,
                        indexCount: mesh.count,
                        indexType: .uint32,
                        indexBuffer: indexBuffer,
                        indexBufferOffset: mesh.start
                            * MemoryLayout<UInt32>.stride
                    )
                }
            } else {
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: indexCount,
                    indexType: .uint32,
                    indexBuffer: indexBuffer,
                    indexBufferOffset: 0
                )
            }
        }
    }

    static func parseOBJ(objContent: String, skinning: [PuppetSkinning]) -> (
        [PuppetVertex], [UInt32], Float
    ) {
        Logger.log(
            "[Puppet] 开始解析 OBJ 模型, 字符串长度: \(objContent.count), 蒙皮信息数: \(skinning.count)"
        )
        var rawPositions: [SIMD3<Float>] = []
        var rawUVs: [SIMD2<Float>] = []
        var finalVertices: [PuppetVertex] = []
        var finalIndices: [UInt32] = []
        var uniqueVertexMap: [String: UInt32] = [:]

        let skinMap = Dictionary(
            uniqueKeysWithValues: skinning.map { ($0.vertex_id, $0) }
        )
        var minPos = SIMD3<Float>(10000, 10000, 10000)
        var maxPos = SIMD3<Float>(-10000, -10000, -10000)

        let lines = objContent.components(separatedBy: .newlines)
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanLine.isEmpty || cleanLine.hasPrefix("#") { continue }
            let parts = cleanLine.components(separatedBy: .whitespaces).filter {
                !$0.isEmpty
            }

            if parts.isEmpty { continue }

            if parts[0] == "v" {
                if parts.count >= 4, let x = Float(parts[1]),
                    let y = Float(parts[2]), let z = Float(parts[3])
                {
                    let p = SIMD3<Float>(x, y, z)
                    rawPositions.append(p)
                    minPos = simd_min(minPos, p)
                    maxPos = simd_max(maxPos, p)
                }
            } else if parts[0] == "vt" {
                if parts.count >= 3, let u = Float(parts[1]),
                    let v = Float(parts[2])
                {
                    rawUVs.append(SIMD2<Float>(u, v))
                }
            } else if parts[0] == "f" {
                var faceIndices: [UInt32] = []

                for i in 1..<parts.count {
                    let component = parts[i]
                    let subParts = component.components(separatedBy: "/")
                    guard let posIdxRaw = Int(subParts[0]) else { continue }
                    let posIdx = posIdxRaw - 1

                    var uvIdx = 0
                    if subParts.count > 1, let tIdx = Int(subParts[1]) {
                        uvIdx = tIdx - 1
                    } else {
                        uvIdx = posIdx
                    }

                    let key = "\(posIdx)/\(uvIdx)"

                    if let existingIndex = uniqueVertexMap[key] {
                        faceIndices.append(existingIndex)
                    } else {
                        let newIndex = UInt32(finalVertices.count)
                        let position =
                            (posIdx >= 0 && posIdx < rawPositions.count)
                            ? rawPositions[posIdx] : SIMD3<Float>(0, 0, 0)
                        let texCoord =
                            (uvIdx >= 0 && uvIdx < rawUVs.count)
                            ? rawUVs[uvIdx] : SIMD2<Float>(0, 0)

                        var j1: UInt16 = 0
                        var j2: UInt16 = 0
                        var j3: UInt16 = 0
                        var j4: UInt16 = 0
                        var w1: Float = 0
                        var w2: Float = 0
                        var w3: Float = 0
                        var w4: Float = 0

                        if let skin = skinMap[posIdx] {
                            j1 = UInt16(min(skin.bone_indices[0], 99))
                            j2 = UInt16(min(skin.bone_indices[1], 99))
                            j3 = UInt16(min(skin.bone_indices[2], 99))
                            j4 = UInt16(min(skin.bone_indices[3], 99))
                            w1 = skin.weights[0]
                            w2 = skin.weights[1]
                            w3 = skin.weights[2]
                            w4 = skin.weights[3]
                        }

                        finalVertices.append(
                            PuppetVertex(
                                px: position.x,
                                py: position.y,
                                pz: position.z,
                                u: texCoord.x,
                                v: texCoord.y,
                                j1: j1,
                                j2: j2,
                                j3: j3,
                                j4: j4,
                                w1: w1,
                                w2: w2,
                                w3: w3,
                                w4: w4
                            )
                        )
                        uniqueVertexMap[key] = newIndex
                        faceIndices.append(newIndex)
                    }
                }

                if faceIndices.count >= 3 {
                    finalIndices.append(faceIndices[0])
                    finalIndices.append(faceIndices[1])
                    finalIndices.append(faceIndices[2])
                }
                if faceIndices.count >= 4 {
                    finalIndices.append(faceIndices[0])
                    finalIndices.append(faceIndices[2])
                    finalIndices.append(faceIndices[3])
                }
            }
        }

        Logger.log(
            "[Puppet] OBJ 解析完成: 提取顶点数 \(finalVertices.count), 面数 \(finalIndices.count / 3)"
        )
        return (finalVertices, finalIndices, maxPos.x - minPos.x)
    }
}
