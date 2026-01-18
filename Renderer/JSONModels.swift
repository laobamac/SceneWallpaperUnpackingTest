import Foundation
import simd

// MARK: - Scene JSON Structures
struct SceneRoot: Codable {
    let general: GeneralSettings?
    let objects: [SceneObject]
}

struct GeneralSettings: Codable {
    let orthogonalprojection: ProjectionSize?
}

struct ProjectionSize: Codable {
    let width: Float
    let height: Float
}

struct SceneObject: Codable {
    let id: Int?
    let name: String?
    let image: String?
    
    // 核心属性
    let origin: ScriptableValue?
    let size: ScriptableValue?
    let scale: ScriptableValue?
    let angles: ScriptableValue? // 新增：旋转角度
    let parent: Int?             // 新增：父节点 ID
    
    let effects: [ObjectEffect]?
    let visible: BoolOrObject?
    
    var isVisible: Bool {
        if let v = visible {
            if case .bool(let b) = v { return b }
            return true
        }
        return true
    }
}

// 兼容 String 或 {"value": String} 的包装器
enum ScriptableValue: Codable {
    case string(String)
    case script(value: String)
    
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let str = try? container.decode(String.self) {
            self = .string(str)
            return
        }
        
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let val = try? container.decode(String.self, forKey: .value) {
            self = .script(value: val)
            return
        }
        
        // 容错处理
        if let container = try? decoder.singleValueContainer(),
           let num = try? container.decode(Float.self) {
            self = .string("\(num)")
            return
        }

        self = .string("0 0 0")
    }
    
    var value: String {
        switch self {
        case .string(let s): return s
        case .script(let v): return v
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case value
    }
    
    func encode(to encoder: Encoder) throws {}
}

enum BoolOrObject: Codable {
    case bool(Bool)
    case object(VisibilityObject)
    
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let o = try? VisibilityObject(from: decoder) {
            self = .object(o)
            return
        }
        self = .bool(true)
    }
    
    func encode(to encoder: Encoder) throws {}
}

struct VisibilityObject: Codable {
    let value: Bool?
}

struct ObjectEffect: Codable {
    let file: String
    let id: Int?
    let passes: [EffectPass]?
}

struct EffectPass: Codable {
    let constantshadervalues: [String: ShaderValue]?
    let textures: [String?]?
}

enum ShaderValue: Codable {
    case float(Float)
    case string(String)
    
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let f = try? container.decode(Float.self) {
                self = .float(f)
                return
            }
            if let s = try? container.decode(String.self) {
                self = .string(s)
                return
            }
        }
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let f = try? container.decode(Float.self, forKey: .value) {
                self = .float(f)
                return
            }
            if let s = try? container.decode(String.self, forKey: .value) {
                self = .string(s)
                return
            }
        }
        self = .float(0)
    }
    
    enum CodingKeys: String, CodingKey {
        case value
    }
    
    func encode(to encoder: Encoder) throws {}
}

struct ModelJSON: Codable {
    let material: String?
}

struct MaterialJSON: Codable {
    let passes: [MaterialPass]
}

struct MaterialPass: Codable {
    let textures: [String]
    let shader: String
}
