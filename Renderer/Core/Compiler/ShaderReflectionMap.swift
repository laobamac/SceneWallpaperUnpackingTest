//
//  ShaderReflectionMap.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation

struct UniformMember {
    let name: String
    let offset: Int
    let size: Int
}

class ShaderReflectionMap {
    private var members: [String: UniformMember] = [:]

    init(reflectionData: [SPIRVReflectionData]) {
        for data in reflectionData {
            let member = UniformMember(name: data.name, offset: Int(data.offset), size: Int(data.size))
            members[data.name] = member
        }
    }

    func offset(for name: String) -> Int? {
        return members[name]?.offset
    }

    func size(for name: String) -> Int? {
        return members[name]?.size
    }
    
    func allMembers() -> [UniformMember] {
        return Array(members.values)
    }
}
