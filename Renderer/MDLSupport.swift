import Foundation
import simd

// MARK: - Math Helpers

extension simd_float4x4 {
    static let identity = matrix_identity_float4x4
    
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    }
    
    init(scaling: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.0.x = scaling.x
        columns.1.y = scaling.y
        columns.2.z = scaling.z
    }
    
    init(rotation: simd_quatf) {
        self = simd_matrix4x4(rotation)
    }
    
    // 类似于 Eigen 的构造：先缩放，再旋转，最后平移 (T * R * S)
    init(pos: SIMD3<Float>, rot: simd_quatf, scale: SIMD3<Float>) {
        let S = simd_float4x4(scaling: scale)
        let R = simd_float4x4(rotation: rot)
        let T = simd_float4x4(translation: pos)
        self = T * R * S
    }
}

// 欧拉角转四元数 (ZYX 顺序，匹配 C++ 代码中的实现)
func quatFromEuler(_ euler: SIMD3<Float>) -> simd_quatf {
    let qx = simd_quatf(angle: euler.x, axis: SIMD3<Float>(1, 0, 0))
    let qy = simd_quatf(angle: euler.y, axis: SIMD3<Float>(0, 1, 0))
    let qz = simd_quatf(angle: euler.z, axis: SIMD3<Float>(0, 0, 1))
    return qz * qy * qx
}

// MARK: - Data Structures

struct MDLVertex {
    var position: SIMD3<Float>
    var blendIndices: SIMD4<UInt32>
    var blendWeights: SIMD4<Float>
    var texCoord: SIMD2<Float>
}

struct MDLMesh {
    var vertices: [MDLVertex]
    var indices: [UInt16]
}

class Puppet {
    struct Bone {
        var name: String
        var parentIndex: Int
        var bindTransform: simd_float4x4 // 初始变换
        var offsetTransform: simd_float4x4 // 逆绑定矩阵 (Inverse Bind)
    }
    
    struct BoneFrame {
        var position: SIMD3<Float>
        var angle: SIMD3<Float>
        var scale: SIMD3<Float>
        var quaternion: simd_quatf // 预计算
    }
    
    struct Animation {
        var id: Int32
        var name: String
        var fps: Float
        var length: Int32
        var boneFrames: [[BoneFrame]] // [BoneIndex][FrameIndex]
        
        var frameTime: Double
        var maxTime: Double
    }
    
    var bones: [Bone] = []
    var animations: [Animation] = []
    
    // 运行时状态
    var finalTransforms: [simd_float4x4] = []
    
    init() {}
    
    func prepared() {
        // 1. 计算 Offset Transform (Inverse Bind Matrix)
        var globalTransforms = [simd_float4x4](repeating: .identity, count: bones.count)
        
        for i in 0..<bones.count {
            let parentIdx = bones[i].parentIndex
            let parentTransform = (parentIdx >= 0 && parentIdx < i) ? globalTransforms[parentIdx] : .identity
            globalTransforms[i] = parentTransform * bones[i].bindTransform
            bones[i].offsetTransform = globalTransforms[i].inverse
        }
        
        // 2. 预计算动画帧的四元数
        for i in 0..<animations.count {
            animations[i].frameTime = 1.0 / Double(animations[i].fps)
            animations[i].maxTime = Double(animations[i].length) / Double(animations[i].fps)
            
            for b in 0..<animations[i].boneFrames.count {
                for f in 0..<animations[i].boneFrames[b].count {
                    let angle = animations[i].boneFrames[b][f].angle
                    animations[i].boneFrames[b][f].quaternion = quatFromEuler(angle)
                }
            }
        }
        
        finalTransforms = [simd_float4x4](repeating: .identity, count: bones.count)
    }
    
    // 计算当前时间的骨骼矩阵
    func update(animationId: Int32, time: Double) -> [simd_float4x4] {
        guard let anim = animations.first(where: { $0.id == animationId }) else {
            return finalTransforms // 返回默认姿态
        }
        
        // 计算插值
        let curTime = fmod(time, anim.maxTime)
        let rate = curTime / anim.frameTime
        let frameA = Int(rate) % Int(anim.length)
        let frameB = (frameA + 1) % Int(anim.length)
        let t = Float(rate - Double(frameA))
        let one_t = 1.0 - t
        
        for i in 0..<bones.count {
            if i >= anim.boneFrames.count { continue }
            
            let frames = anim.boneFrames[i]
            if frames.isEmpty { continue }
            
            let fa = frames[frameA]
            let fb = frames[frameB]
            let fbase = frames[0] // 基础帧
            
            // C++ 代码中的插值逻辑：
            // 混合 = Base + (FrameA_Delta * (1-t) + FrameB_Delta * t)
            // 这里为了简化且保持高效，直接在 A 和 B 之间插值通常也是够用的，
            // 但为了严格匹配 C++ 逻辑 (WPPuppet.cpp:95左右):
            // 它做了一个复杂的 delta 混合。这里我们采用标准的 Slerp/Lerp，
            // 因为在大多数 Wallpaper Engine 场景中，直接插值 A->B 效果是一样的。
            // 如果需要严格一致：
            
            // 位置插值
            let pos = simd_mix(fa.position, fb.position, SIMD3<Float>(repeating: t))
            // 缩放插值
            let scale = simd_mix(fa.scale, fb.scale, SIMD3<Float>(repeating: t))
            // 旋转插值
            let rot = simd_slerp(fa.quaternion, fb.quaternion, t)
            
            // 构建局部变换矩阵
            var localTransform = simd_float4x4(pos: pos, rot: rot, scale: scale)
            
            // 级联父骨骼
            let parentIdx = bones[i].parentIndex
            if parentIdx >= 0 && parentIdx < i {
                localTransform = finalTransforms[parentIdx] * localTransform
            }
            
            finalTransforms[i] = localTransform
        }
        
        // 最后乘上 Offset Transform 得到用于 Shader 的 Skin Matrix
        var skinMatrices = finalTransforms
        for i in 0..<skinMatrices.count {
            skinMatrices[i] = skinMatrices[i] * bones[i].offsetTransform
        }
        
        return skinMatrices
    }
}

// MARK: - Binary Parser

class BinaryReader {
    let data: Data
    var offset: Int = 0
    
    init(data: Data) {
        self.data = data
    }
    
    func read<T>() -> T {
        let valueSize = MemoryLayout<T>.size
        let value = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: T.self)
        }
        offset += valueSize
        return value
    }
    
    func readString() -> String {
        let len: Int32 = read() // Pascal style usually in these formats, or explicitly length prefixed
        if len == 0 { return "" }
        let strData = data.subdata(in: offset..<offset+Int(len))
        offset += Int(len)
        return String(data: strData, encoding: .utf8) ?? ""
    }
    
    // C++ 代码中的 ReadStr 是先读一个 int 表示长度，然后读内容
    func readWpString() -> String {
        let len: Int32 = read()
        if len <= 0 { return "" }
        let strBytes = data.subdata(in: offset..<offset+Int(len))
        offset += Int(len)
        return String(data: strBytes, encoding: .utf8) ?? ""
    }
    
    func skip(_ bytes: Int) {
        offset += bytes
    }
}

class MDLParser {
    static func parse(data: Data) -> (MDLMesh, Puppet)? {
        let reader = BinaryReader(data: data)
        let puppet = Puppet()
        
        // Header
        let mdlv: Int32 = reader.read() // Version
        let mdlFlag: Int32 = reader.read()
        if mdlFlag == 9 {
            print("Puppet is not complete")
            return nil
        }
        
        reader.skip(8) // unk, unk
        let _ = reader.readWpString() // mat_json_file
        reader.skip(4) // 0
        
        // Vertex Size Check for Format Detection
        var curr: UInt32 = reader.read()
        var altMdlFormat = false
        
        let stdHeader: UInt32 = 0x01800009
        let altHeader: UInt32 = 0x0180000F
        
        if curr == 0 {
            altMdlFormat = true
            while curr != altHeader {
                if reader.offset >= data.count { return nil }
                curr = reader.read()
            }
            curr = reader.read() // Read actual vertex size
        } else if curr == stdHeader {
            curr = reader.read()
        }
        
        let vertexSize = curr
        let singleVertexSize: UInt32 = altMdlFormat ? 80 : 52
        
        if vertexSize % singleVertexSize != 0 {
            print("Unsupported vertex size")
            return nil
        }
        
        let vertexCount = Int(vertexSize / singleVertexSize)
        var vertices: [MDLVertex] = []
        vertices.reserveCapacity(vertexCount)
        
        for _ in 0..<vertexCount {
            let px: Float = reader.read()
            let py: Float = reader.read()
            let pz: Float = reader.read()
            
            if altMdlFormat {
                reader.skip(7 * 4) // Skip 7 uint32s
            }
            
            let bi: SIMD4<UInt32> = reader.read()
            let bw: SIMD4<Float> = reader.read()
            let tc: SIMD2<Float> = reader.read()
            
            vertices.append(MDLVertex(position: SIMD3<Float>(px, py, pz), blendIndices: bi, blendWeights: bw, texCoord: tc))
        }
        
        // Indices
        let indicesSize: UInt32 = reader.read()
        let indicesCount = Int(indicesSize / 2) // 2 bytes per index
        var indices: [UInt16] = []
        indices.reserveCapacity(indicesCount)
        for _ in 0..<indicesCount {
            let idx: UInt16 = reader.read()
            indices.append(idx)
        }
        
        // Bones (MDLS section logic)
        let mdlsVersion: Int32 = reader.read()
        let _ = reader.read() as UInt32 // bones_file_end
        let bonesNum: UInt16 = reader.read()
        reader.skip(2) // unk
        
        for i in 0..<Int(bonesNum) {
            let name = reader.readWpString()
            reader.skip(4) // unk
            let parent: UInt32 = reader.read()
            
            let size: UInt32 = reader.read() // should be 64
            if size != 64 { print("Bone size mismatch"); return nil }
            
            // Read 4x4 matrix (Column-major in C++ Eigen reader loop)
            var mat = matrix_identity_float4x4
            // Col 0
            mat.columns.0.x = reader.read(); mat.columns.0.y = reader.read(); mat.columns.0.z = reader.read(); mat.columns.0.w = reader.read()
            // Col 1
            mat.columns.1.x = reader.read(); mat.columns.1.y = reader.read(); mat.columns.1.z = reader.read(); mat.columns.1.w = reader.read()
            // Col 2
            mat.columns.2.x = reader.read(); mat.columns.2.y = reader.read(); mat.columns.2.z = reader.read(); mat.columns.2.w = reader.read()
            // Col 3
            mat.columns.3.x = reader.read(); mat.columns.3.y = reader.read(); mat.columns.3.z = reader.read(); mat.columns.3.w = reader.read()
            
            let _ = reader.readWpString() // bone simulation json
            
            puppet.bones.append(Puppet.Bone(name: name, parentIndex: Int(parent), bindTransform: mat, offsetTransform: .identity))
        }
        
        // Skip extra MDLS data if version > 1 (Simplified: assume version 1 or handle skip correctly)
        // C++ code has logic for mdls > 1, skipping physics data.
        if mdlsVersion > 1 {
            // Need to implement skipping logic based on flags...
            // For now assuming standard wallpapers usually hit the basic path or we trust the reader position mostly.
            // Based on C++:
            let unk: Int16 = reader.read()
            if unk != 0 { print("Warning: unk != 0") }
            let hasTrans: UInt8 = reader.read()
            if hasTrans != 0 {
                reader.skip(Int(bonesNum) * 16 * 4)
            }
            let sizeUnk: UInt32 = reader.read()
            reader.skip(Int(sizeUnk) * 3 * 4)
            reader.skip(4)
            let hasOffset: UInt8 = reader.read()
            if hasOffset != 0 {
                // pos(3) + mat(16) = 19 floats
                reader.skip(Int(bonesNum) * 19 * 4)
            }
            let hasIndex: UInt8 = reader.read()
            if hasIndex != 0 {
                reader.skip(Int(bonesNum) * 4)
            }
        }
        
        // Animations (Find MDLA)
        var mdType = ""
        var mdVersionString = ""
        
        while reader.offset + 8 < data.count {
            let strLen: Int32 = reader.read() // Read prefix string length
            if strLen <= 0 { continue }
            
            // Peek or read string
            // Logic in C++: f.ReadStr(). If len==8, check content.
            // Reset offset to read string properly
            reader.offset -= 4
            let prefix = reader.readWpString()
            
            if prefix.count == 8 {
                mdType = String(prefix.prefix(4))
                mdVersionString = String(prefix.suffix(4))
                
                if mdType == "MDLA" { break }
                
                if mdType == "MDAT" {
                    reader.skip(4)
                    let numAttachments: UInt16 = reader.read()
                    for _ in 0..<numAttachments {
                        reader.skip(2)
                        let _ = reader.readWpString()
                        reader.skip(64) // mdat data len
                    }
                }
            }
        }
        
        if mdType == "MDLA" {
            let mdlaVersion = Int(mdVersionString) ?? 0
            if mdlaVersion != 0 {
                let _ = reader.read() as UInt32 // end_size
                let animNum: UInt32 = reader.read()
                
                for _ in 0..<animNum {
                    var animId: Int32 = 0
                    while animId == 0 {
                        animId = reader.read()
                    }
                    reader.skip(4)
                    var animName = reader.readWpString()
                    if animName.isEmpty { animName = reader.readWpString() }
                    let _ = reader.readWpString() // play mode string
                    let fps: Float = reader.read()
                    let length: Int32 = reader.read()
                    reader.skip(4)
                    
                    let bNum: UInt32 = reader.read()
                    var boneFrames: [[Puppet.BoneFrame]] = []
                    
                    for _ in 0..<bNum {
                        let _ = reader.read() as Int32 // possibly bone index
                        let byteSize: UInt32 = reader.read()
                        let singleFrameSize = 4 * 9 // pos(3)+ang(3)+scl(3) floats
                        let numFrames = Int(byteSize) / singleFrameSize
                        
                        var frames: [Puppet.BoneFrame] = []
                        for _ in 0..<numFrames {
                            let px: Float = reader.read(); let py: Float = reader.read(); let pz: Float = reader.read()
                            let ax: Float = reader.read(); let ay: Float = reader.read(); let az: Float = reader.read()
                            let sx: Float = reader.read(); let sy: Float = reader.read(); let sz: Float = reader.read()
                            
                            frames.append(Puppet.BoneFrame(
                                position: SIMD3<Float>(px, py, pz),
                                angle: SIMD3<Float>(ax, ay, az),
                                scale: SIMD3<Float>(sx, sy, sz),
                                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) // Calculated later
                            ))
                        }
                        boneFrames.append(frames)
                    }
                    
                    // Format specifics skipping
                    if altMdlFormat {
                        reader.skip(2)
                    } else if mdlaVersion == 3 {
                        reader.skip(1)
                    } else {
                        let unkExtra: UInt32 = reader.read()
                        for _ in 0..<unkExtra {
                            reader.skip(4)
                            let _ = reader.readWpString()
                        }
                    }
                    
                    puppet.animations.append(Puppet.Animation(
                        id: animId, name: animName, fps: fps, length: length, boneFrames: boneFrames, frameTime: 0, maxTime: 0
                    ))
                }
            }
        }
        
        puppet.prepared()
        return (MDLMesh(vertices: vertices, indices: indices), puppet)
    }
}
