//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

import Foundation
import simd

struct ParticleRoot: Codable {
    let children: [ParticleChild]?
    let controlpoint: [ParticleControlPoint]?
    let emitter: [ParticleEmitter]?
    let flags: Int?
    let initializer: [ParticleInitializer]?
    let material: String?
    let maxcount: Int?
    let `operator`: [ParticleOperator]?
    let renderer: [ParticleRenderer]?
    let starttime: Float?
    let instanceoverride: InstanceOverride?
}

struct ParticleChild: Codable {
    let id: Int?
    let name: String?
}

struct ParticleControlPoint: Codable {
    let flags: Int?
    let id: Int?
    let offset: DynamicValue?
}

struct ParticleEmitter: Codable {
    let directions: DynamicValue?
    let distancemax: DynamicValue?
    let distancemin: DynamicValue?
    let id: Int?
    let name: String?
    let rate: Float?
    let origin: DynamicValue?
    let controlPoint: Int?
    let flags: Int?
    let duration: Float?
    let delay: Float?
    let minPeriodicDuration: Float?
    let maxPeriodicDuration: Float?
    let minPeriodicDelay: Float?
    let maxPeriodicDelay: Float?
    let instantaneous: Int?
    let speedMin: Float?
    let speedMax: Float?
    let sign: [Int]?
}

struct ParticleInitializer: Codable {
    let id: Int?
    let name: String?
    let max: DynamicValue?
    let min: DynamicValue?
    let offset: DynamicValue?
    let scale: DynamicValue?
    let exponent: DynamicValue?
    let speedMin: DynamicValue?
    let speedMax: DynamicValue?
    let forward: DynamicValue?
    let timeScale: DynamicValue?
    let phaseMin: DynamicValue?
    let phaseMax: DynamicValue?
    let right: DynamicValue?
    let controlPoint: DynamicValue?
    let count: DynamicValue?
}

struct ParticleOperator: Codable {
    let id: Int?
    let name: String?
    let gravity: DynamicValue?
    let drag: DynamicValue?
    let force: DynamicValue?
    let fadeintime: DynamicValue?
    let fadeouttime: DynamicValue?
    let starttime: DynamicValue?
    let endtime: DynamicValue?
    let startvalue: DynamicValue?
    let endvalue: DynamicValue?
    let scale: DynamicValue?
    let speedmin: DynamicValue?
    let speedmax: DynamicValue?
    let phasemin: DynamicValue?
    let phasemax: DynamicValue?
    let mask: DynamicValue?
    let timescale: DynamicValue?
    let frequencymax: DynamicValue?
    let frequencymin: DynamicValue?
    let scalemin: DynamicValue?
    let scalemax: DynamicValue?
    let controlPoint: Int?
    let flags: Int?
    let axis: DynamicValue?
    let offset: DynamicValue?
    let distanceInner: DynamicValue?
    let distanceOuter: DynamicValue?
    let speedInner: DynamicValue?
    let speedOuter: DynamicValue?
    let centerForce: DynamicValue?
    let ringRadius: DynamicValue?
    let ringWidth: DynamicValue?
    let ringPullDistance: DynamicValue?
    let ringPullForce: DynamicValue?
    let audioProcessingMode: DynamicValue?
    let origin: DynamicValue?
    let threshold: DynamicValue?
}

struct ParticleRenderer: Codable {
    let id: Int?
    let name: String?
    let length: Float?
    let maxLength: Float?
    let minLength: Float?
    let subdivision: Float?
    let segments: Float?
    let uvScale: Float?
    let uvScrolling: Bool?
    let uvSmoothing: Bool?
}

struct DynamicValue: Codable {
    private var floatValues: [Float] = []
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let floatVal = try? container.decode(Float.self) {
            self.floatValues = [floatVal]
        } else if let intVal = try? container.decode(Int.self) {
            self.floatValues = [Float(intVal)]
        } else if let stringVal = try? container.decode(String.self) {
            let components = stringVal.split(separator: " ").compactMap { Float(String($0)) }
            if !components.isEmpty {
                self.floatValues = components
            } else {
                self.floatValues = [0]
            }
        } else if let arrayVal = try? container.decode([Float].self) {
            self.floatValues = arrayVal
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            if let valueObj = dictVal["value"] {
                if let floatVal = valueObj.floatValue {
                    self.floatValues = [floatVal]
                } else if let stringVal = valueObj.stringValue {
                    let components = stringVal.split(separator: " ").compactMap { Float(String($0)) }
                    if !components.isEmpty {
                        self.floatValues = components
                    } else {
                        self.floatValues = [0]
                    }
                } else {
                    self.floatValues = [0]
                }
            } else if let xObj = dictVal["x"]?.floatValue, let yObj = dictVal["y"]?.floatValue, let zObj = dictVal["z"]?.floatValue {
                self.floatValues = [xObj, yObj, zObj]
            } else {
                self.floatValues = [0]
            }
        } else {
            self.floatValues = [0]
        }
    }
    
    init(floats: [Float]) {
        self.floatValues = floats
    }
    
    func getFloat() -> Float {
        return floatValues.first ?? 0.0
    }
    
    func getVec3() -> simd_float3 {
        var result = simd_float3(0, 0, 0)
        if floatValues.count >= 1 { result.x = floatValues[0] }
        if floatValues.count >= 2 { result.y = floatValues[1] }
        if floatValues.count >= 3 { result.z = floatValues[2] }
        return result
    }
    
    func getVec4() -> simd_float4 {
        var result = simd_float4(0, 0, 0, 1)
        if floatValues.count >= 1 { result.x = floatValues[0] }
        if floatValues.count >= 2 { result.y = floatValues[1] }
        if floatValues.count >= 3 { result.z = floatValues[2] }
        if floatValues.count >= 4 { result.w = floatValues[3] }
        return result
    }
}
