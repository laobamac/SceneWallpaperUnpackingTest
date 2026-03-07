//
//  PuppetRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import MetalKit
import simd

class PuppetRenderable: RenderableObject {
    let device: MTLDevice
    let vertexBuffer: MTLBuffer

    var indexBuffer: MTLBuffer?
    var indexCount: Int = 0

    let uniformBuffer: MTLBuffer
    var boneMatrices: [matrix_float4x4]

    let usePixelCoords: Bool
    let skeleton: [PuppetBone]
    let animations: [PuppetAnimation]
    let subMeshes: [PuppetSubMesh]
    let maskedGroupIDs: Set<Int>
    
    var inverseBindMatrices: [matrix_float4x4] = []

    var maskTexture: MTLTexture?
    let uTransform: SIMD4<Float>
    let vTransform: SIMD4<Float>

    private var lastAnimCycle: Int = -1
    private var boneToTrackIndex: [Int: Int] = [:]

    init?(
        device: MTLDevice,
        vertices: [PuppetVertex],
        indices: [UInt32],
        skeleton: [PuppetBone],
        animations: [PuppetAnimation],
        subMeshes: [PuppetSubMesh],
        maskedGroupIDs: Set<Int>,
        position: SIMD3<Float>,
        rotation: SIMD3<Float>,
        size: SIMD2<Float>,
        scale: SIMD3<Float>,
        texture: MTLTexture,
        maskTexture: MTLTexture?,
        pipeline: MTLRenderPipelineState,
        depthState: MTLDepthStencilState?,
        usePixelCoords: Bool,
        uTransform: SIMD4<Float>,
        vTransform: SIMD4<Float>
    ) {
        self.device = device
        guard
            let vb = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<PuppetVertex>.stride,
                options: .storageModeShared
            )
        else {
            return nil
        }
        self.vertexBuffer = vb

        self.usePixelCoords = usePixelCoords
        self.skeleton = skeleton
        self.animations = animations
        self.subMeshes = subMeshes
        self.maskedGroupIDs = maskedGroupIDs
        self.maskTexture = maskTexture
        self.uTransform = uTransform
        self.vTransform = vTransform

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
        
        if !indices.isEmpty {
            indexBuffer = device.makeBuffer(
                bytes: indices,
                length: indices.count * 4,
                options: .storageModeShared
            )
            indexCount = indices.count
        }

        if let firstAnim = animations.first {
            for (index, track) in firstAnim.tracks.enumerated() {
                boneToTrackIndex[track.track_id] = index
            }
        }

        let ptr = uniformBuffer.contents()
        ptr.copyMemory(
            from: &boneMatrices,
            byteCount: MemoryLayout<matrix_float4x4>.stride * 100
        )
        
        print("[Puppet] 构建完成 -> 骨骼: \(skeleton.count), 动画: \(animations.count), 子网格: \(subMeshes.count), 需要遮罩的组: \(maskedGroupIDs)")
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
        let anim = animations[0]
        let fps = anim.fps > 0 ? anim.fps : 30.0
        let duration = Float(anim.length) / fps
        let t = (duration > 0) ? fmod(time, duration) : 0

        let currentCycle = (duration > 0) ? Int(time / duration) : 0
        if currentCycle > lastAnimCycle {
            lastAnimCycle = currentCycle
        }

        let frameIndex = t * fps
        var localMatrices = Array(
            repeating: matrix_identity_float4x4,
            count: skeleton.count
        )

        for i in 0..<skeleton.count {
            let bone = skeleton[i]
            var hasTrack = false

            if let trackIndex = boneToTrackIndex[bone.id] {
                let track = anim.tracks[trackIndex]
                if !track.frames.isEmpty {
                    hasTrack = true
                    let totalFrames = track.frames.count
                    let idx0 = Int(frameIndex) % totalFrames
                    let idx1 = (idx0 + 1) % totalFrames
                    let fraction = frameIndex - Float(Int(frameIndex))
                    let k1 = track.frames[idx0]
                    let k2 = track.frames[idx1]
                    let p = mix(
                        SIMD3<Float>(k1.p[0], k1.p[1], k1.p[2]),
                        SIMD3<Float>(k2.p[0], k2.p[1], k2.p[2]),
                        t: fraction
                    )
                    let r = mix(
                        SIMD3<Float>(k1.r[0], k1.r[1], k1.r[2]),
                        SIMD3<Float>(k2.r[0], k2.r[1], k2.r[2]),
                        t: fraction
                    )
                    let s = mix(
                        SIMD3<Float>(k1.s[0], k1.s[1], k1.s[2]),
                        SIMD3<Float>(k2.s[0], k2.s[1], k2.s[2]),
                        t: fraction
                    )
                    let matT = Matrix4x4.translation(x: p.x, y: p.y, z: p.z)
                    let matR = Matrix4x4.fromEuler(r)
                    let matS = Matrix4x4.scale(x: s.x, y: s.y, z: s.z)
                    localMatrices[i] = matT * matR * matS
                }
            }

            if !hasTrack {
                let m = bone.matrix
                localMatrices[i] = matrix_float4x4(
                    columns: (
                        SIMD4<Float>(m[0], m[1], m[2], m[3]),
                        SIMD4<Float>(m[4], m[5], m[6], m[7]),
                        SIMD4<Float>(m[8], m[9], m[10], m[11]),
                        SIMD4<Float>(m[12], m[13], m[14], m[15])
                    )
                )
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
        encoder.setRenderPipelineState(pipeline)
        let geometryScale: matrix_float4x4
        if usePixelCoords {
            geometryScale = Matrix4x4.scale(x: scale.x, y: scale.y, z: scale.z)
        } else {
            geometryScale = Matrix4x4.scale(
                x: size.x * scale.x,
                y: size.y * scale.y,
                z: scale.z
            )
        }
        let finalModelMatrix = worldMatrix * geometryScale
        var objUniforms = ObjectUniforms(
            modelMatrix: finalModelMatrix,
            alpha: 1.0,
            color: SIMD4<Float>(1, 1, 1, 1),
            animInfo: .zero
        )

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(
            &objUniforms,
            length: MemoryLayout<ObjectUniforms>.size,
            index: 2
        )
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 3)
        
        var uT = uTransform
        var vT = vTransform
        encoder.setVertexBytes(&uT, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)
        encoder.setVertexBytes(&vT, length: MemoryLayout<SIMD4<Float>>.stride, index: 5)
        
        encoder.setFragmentBytes(
            &objUniforms,
            length: MemoryLayout<ObjectUniforms>.size,
            index: 2
        )

        encoder.setFragmentTexture(texture, index: 0)
        if let mask = maskTexture {
            encoder.setFragmentTexture(mask, index: 1)
        } else {
            encoder.setFragmentTexture(texture, index: 1)
        }

        if let ds = depthState { encoder.setDepthStencilState(ds) }

        if let buf = indexBuffer {
            if subMeshes.isEmpty {
                var hasMask: Bool = false
                encoder.setFragmentBytes(&hasMask, length: MemoryLayout<Bool>.size, index: 3)
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: indexCount,
                    indexType: .uint32,
                    indexBuffer: buf,
                    indexBufferOffset: 0
                )
            } else {
                for subMesh in subMeshes {
                    var hasMask: Bool = maskedGroupIDs.contains(subMesh.id) && maskTexture != nil
                    encoder.setFragmentBytes(&hasMask, length: MemoryLayout<Bool>.size, index: 3)
                    encoder.drawIndexedPrimitives(
                        type: .triangle,
                        indexCount: subMesh.count,
                        indexType: .uint32,
                        indexBuffer: buf,
                        indexBufferOffset: subMesh.start * 4
                    )
                }
            }
        }
    }

    static func parseOBJ(objContent: String, skinning: [PuppetSkinning]) -> (
        [PuppetVertex], [UInt32], Float, SIMD4<Float>, SIMD4<Float>
    ) {
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

        var uTransform = SIMD4<Float>(0, 0, 0, 0)
        var vTransform = SIMD4<Float>(0, 0, 0, 0)
        var found = false

        if finalVertices.count >= 3 {
            let p0 = SIMD2<Float>(finalVertices[0].px, finalVertices[0].py)
            let u0 = finalVertices[0].u
            let v0 = finalVertices[0].v

            for i in 1..<finalVertices.count {
                let p1 = SIMD2<Float>(finalVertices[i].px, finalVertices[i].py)
                let u1 = finalVertices[i].u
                let v1 = finalVertices[i].v

                let dx1 = p1.x - p0.x
                let dy1 = p1.y - p0.y

                if dx1 * dx1 + dy1 * dy1 > 0.0001 {
                    for j in (i + 1)..<finalVertices.count {
                        let p2 = SIMD2<Float>(finalVertices[j].px, finalVertices[j].py)
                        let u2 = finalVertices[j].u
                        let v2 = finalVertices[j].v

                        let dx2 = p2.x - p0.x
                        let dy2 = p2.y - p0.y

                        let det = dx1 * dy2 - dx2 * dy1
                        if abs(det) > 0.0001 {
                            let invDet = 1.0 / det
                            
                            let du1 = u1 - u0
                            let du2 = u2 - u0
                            let A = (du1 * dy2 - du2 * dy1) * invDet
                            let B = (dx1 * du2 - dx2 * du1) * invDet
                            let C = u0 - A * p0.x - B * p0.y
                            uTransform = SIMD4<Float>(A, B, C, 0)

                            let dv1 = v1 - v0
                            let dv2 = v2 - v0
                            let D = (dv1 * dy2 - dv2 * dy1) * invDet
                            let E = (dx1 * dv2 - dx2 * dv1) * invDet
                            let F = v0 - D * p0.x - E * p0.y
                            vTransform = SIMD4<Float>(D, E, F, 0)

                            found = true
                            break
                        }
                    }
                }
                if found { break }
            }
        }

        return (
            finalVertices, finalIndices, maxPos.x - minPos.x, uTransform, vTransform
        )
    }
}
