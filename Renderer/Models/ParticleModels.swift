//
//  ParticleModels.swift
//  Renderer
//
//  Created by laobamac on 2026/3/16.
//

import Foundation
import simd

struct DynamicValue: Codable {
    var floatValue: Float = 0.0
    var vec3Value: simd_float3 = simd_float3(0, 0, 0)
    var vec4Value: simd_float4 = simd_float4(0, 0, 0, 0)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let floatVal = try? container.decode(Float.self) {
            self.floatValue = floatVal
            self.vec3Value = simd_float3(floatVal, floatVal, floatVal)
            self.vec4Value = simd_float4(floatVal, floatVal, floatVal, floatVal)
        } else if let stringVal = try? container.decode(String.self) {
            let components = stringVal.split(separator: " ").compactMap { Float($0) }
            if components.count == 1 {
                self.floatValue = components[0]
                self.vec3Value = simd_float3(components[0], components[0], components[0])
                self.vec4Value = simd_float4(components[0], components[0], components[0], components[0])
            } else if components.count == 3 {
                self.floatValue = components[0]
                self.vec3Value = simd_float3(components[0], components[1], components[2])
                self.vec4Value = simd_float4(components[0], components[1], components[2], 1.0)
            } else if components.count >= 4 {
                self.floatValue = components[0]
                self.vec3Value = simd_float3(components[0], components[1], components[2])
                self.vec4Value = simd_float4(components[0], components[1], components[2], components[3])
            }
        }
    }
}

struct DynamicValueWrapper: Codable {
    var value: DynamicValue?
}

struct ParticleControlPoint: Codable {
    var id: Int
    var offset: simd_float3
    var flags: Int
}

struct ParticleRendererConfig: Codable {
    var name: String
    var subdivision: Int?
    var uvScale: Float?
    var uvScrolling: Bool?
    var uvSmoothing: Bool?
    var length: Float?
    var segments: Int?
    var maxLength: Float?
    var minLength: Float?
}

struct ParticleEmitter: Codable {
    var name: String
    var rate: Float
    var origin: simd_float3
    var controlPoint: Int
    var directions: simd_float3
    var flags: Int
    var delay: Float
    var duration: Float
    var minPeriodicDuration: Float
    var maxPeriodicDuration: Float
    var minPeriodicDelay: Float
    var maxPeriodicDelay: Float
    var instantaneous: Int
    var distanceMin: simd_float3
    var distanceMax: simd_float3
    var speedMin: Float
    var speedMax: Float
    var sign: [Int]
    
    enum CodingKeys: String, CodingKey {
        case name, rate, origin, controlPoint, directions, flags, delay, duration
        case minPeriodicDuration = "minperiodicduration"
        case maxPeriodicDuration = "maxperiodicduration"
        case minPeriodicDelay = "minperiodicdelay"
        case maxPeriodicDelay = "maxperiodicdelay"
        case instantaneous
        case distanceMin = "distancemin"
        case distanceMax = "distancemax"
        case speedMin = "speedmin"
        case speedMax = "speedmax"
        case sign
    }
}

enum ParticleInitializer {
    case colorRandom(min: DynamicValueWrapper, max: DynamicValueWrapper)
    case sizeRandom(min: DynamicValueWrapper, max: DynamicValueWrapper, exponent: DynamicValueWrapper)
    case alphaRandom(min: DynamicValueWrapper, max: DynamicValueWrapper)
    case lifetimeRandom(min: DynamicValueWrapper, max: DynamicValueWrapper)
    case velocityRandom(min: DynamicValueWrapper, max: DynamicValueWrapper)
    case rotationRandom(min: DynamicValueWrapper, max: DynamicValueWrapper)
    case angularVelocityRandom(min: DynamicValueWrapper, max: DynamicValueWrapper, exponent: DynamicValueWrapper)
    case turbulentVelocityRandom(speedMin: DynamicValueWrapper, speedMax: DynamicValueWrapper, offset: DynamicValueWrapper, scale: DynamicValueWrapper, forward: DynamicValueWrapper, timeScale: DynamicValueWrapper, phaseMin: DynamicValueWrapper, phaseMax: DynamicValueWrapper, right: DynamicValueWrapper)
    case mapSequenceAroundControlPoint(controlPoint: DynamicValueWrapper, count: DynamicValueWrapper, speedMin: DynamicValueWrapper, speedMax: DynamicValueWrapper)
    case unknown
}

extension ParticleInitializer: Codable {
    enum CodingKeys: String, CodingKey {
        case name, min, max, exponent, speedMin = "speedmin", speedMax = "speedmax", offset, scale, forward, timeScale = "timescale", phaseMin = "phasemin", phaseMax = "phasemax", right, controlPoint = "controlpoint", count
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        switch name {
        case "colorrandom":
            self = .colorRandom(min: try container.decode(DynamicValueWrapper.self, forKey: .min), max: try container.decode(DynamicValueWrapper.self, forKey: .max))
        case "sizerandom":
            self = .sizeRandom(min: try container.decode(DynamicValueWrapper.self, forKey: .min), max: try container.decode(DynamicValueWrapper.self, forKey: .max), exponent: try container.decode(DynamicValueWrapper.self, forKey: .exponent))
        case "alpharandom":
            self = .alphaRandom(min: try container.decode(DynamicValueWrapper.self, forKey: .min), max: try container.decode(DynamicValueWrapper.self, forKey: .max))
        case "lifetimerandom":
            self = .lifetimeRandom(min: try container.decode(DynamicValueWrapper.self, forKey: .min), max: try container.decode(DynamicValueWrapper.self, forKey: .max))
        case "velocityrandom":
            self = .velocityRandom(min: try container.decode(DynamicValueWrapper.self, forKey: .min), max: try container.decode(DynamicValueWrapper.self, forKey: .max))
        case "rotationrandom":
            self = .rotationRandom(min: try container.decode(DynamicValueWrapper.self, forKey: .min), max: try container.decode(DynamicValueWrapper.self, forKey: .max))
        case "angularvelocityrandom":
            self = .angularVelocityRandom(min: try container.decode(DynamicValueWrapper.self, forKey: .min), max: try container.decode(DynamicValueWrapper.self, forKey: .max), exponent: try container.decode(DynamicValueWrapper.self, forKey: .exponent))
        case "turbulentvelocityrandom":
            self = .turbulentVelocityRandom(speedMin: try container.decode(DynamicValueWrapper.self, forKey: .speedMin), speedMax: try container.decode(DynamicValueWrapper.self, forKey: .speedMax), offset: try container.decode(DynamicValueWrapper.self, forKey: .offset), scale: try container.decode(DynamicValueWrapper.self, forKey: .scale), forward: try container.decode(DynamicValueWrapper.self, forKey: .forward), timeScale: try container.decode(DynamicValueWrapper.self, forKey: .timeScale), phaseMin: try container.decode(DynamicValueWrapper.self, forKey: .phaseMin), phaseMax: try container.decode(DynamicValueWrapper.self, forKey: .phaseMax), right: try container.decode(DynamicValueWrapper.self, forKey: .right))
        case "mapsequencearoundcontrolpoint":
            self = .mapSequenceAroundControlPoint(controlPoint: try container.decode(DynamicValueWrapper.self, forKey: .controlPoint), count: try container.decode(DynamicValueWrapper.self, forKey: .count), speedMin: try container.decode(DynamicValueWrapper.self, forKey: .speedMin), speedMax: try container.decode(DynamicValueWrapper.self, forKey: .speedMax))
        default:
            self = .unknown
        }
    }
    
    func encode(to encoder: Encoder) throws {}
}

enum ParticleOperator {
    case movement(drag: DynamicValueWrapper, gravity: DynamicValueWrapper)
    case angularMovement(drag: DynamicValueWrapper, force: DynamicValueWrapper)
    case alphaFade(fadeInTime: DynamicValueWrapper, fadeOutTime: DynamicValueWrapper)
    case sizeChange(startTime: DynamicValueWrapper, endTime: DynamicValueWrapper, startValue: DynamicValueWrapper, endValue: DynamicValueWrapper)
    case alphaChange(startTime: DynamicValueWrapper, endTime: DynamicValueWrapper, startValue: DynamicValueWrapper, endValue: DynamicValueWrapper)
    case colorChange(startTime: DynamicValueWrapper, endTime: DynamicValueWrapper, startValue: DynamicValueWrapper, endValue: DynamicValueWrapper)
    case turbulence(scale: DynamicValueWrapper, speedMin: DynamicValueWrapper, speedMax: DynamicValueWrapper, timeScale: DynamicValueWrapper, mask: DynamicValueWrapper, phaseMin: DynamicValueWrapper, phaseMax: DynamicValueWrapper)
    case vortex(controlPoint: Int, flags: Int, axis: DynamicValueWrapper, offset: DynamicValueWrapper, distanceInner: DynamicValueWrapper, distanceOuter: DynamicValueWrapper, speedInner: DynamicValueWrapper, speedOuter: DynamicValueWrapper, centerForce: DynamicValueWrapper, ringRadius: DynamicValueWrapper, ringWidth: DynamicValueWrapper, ringPullDistance: DynamicValueWrapper, ringPullForce: DynamicValueWrapper, audioProcessingMode: DynamicValueWrapper)
    case controlPointAttract(controlPoint: Int, origin: DynamicValueWrapper, scale: DynamicValueWrapper, threshold: DynamicValueWrapper)
    case oscillateAlpha(frequencyMin: DynamicValueWrapper, frequencyMax: DynamicValueWrapper, scaleMin: DynamicValueWrapper, scaleMax: DynamicValueWrapper, phaseMin: DynamicValueWrapper, phaseMax: DynamicValueWrapper)
    case oscillateSize(frequencyMin: DynamicValueWrapper, frequencyMax: DynamicValueWrapper, scaleMin: DynamicValueWrapper, scaleMax: DynamicValueWrapper, phaseMin: DynamicValueWrapper, phaseMax: DynamicValueWrapper)
    case oscillatePosition(frequencyMin: DynamicValueWrapper, frequencyMax: DynamicValueWrapper, scaleMin: DynamicValueWrapper, scaleMax: DynamicValueWrapper, phaseMin: DynamicValueWrapper, phaseMax: DynamicValueWrapper, mask: DynamicValueWrapper)
    case unknown
}

extension ParticleOperator: Codable {
    enum CodingKeys: String, CodingKey {
        case name, drag, gravity, force, fadeInTime = "fadeintime", fadeOutTime = "fadeouttime", startTime = "starttime", endTime = "endtime", startValue = "startvalue", endValue = "endvalue", scale, speedMin = "speedmin", speedMax = "speedmax", timeScale = "timescale", mask, phaseMin = "phasemin", phaseMax = "phasemax", controlPoint = "controlpoint", flags, axis, offset, distanceInner = "distanceinner", distanceOuter = "distanceouter", speedInner = "speedinner", speedOuter = "speedouter", centerForce = "centerforce", ringRadius = "ringradius", ringWidth = "ringwidth", ringPullDistance = "ringpulldistance", ringPullForce = "ringpullforce", audioProcessingMode = "audioprocessingmode", origin, threshold, frequencyMin = "frequencymin", frequencyMax = "frequencymax", scaleMin = "scalemin", scaleMax = "scalemax"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        switch name {
        case "movement":
            self = .movement(drag: try container.decode(DynamicValueWrapper.self, forKey: .drag), gravity: try container.decode(DynamicValueWrapper.self, forKey: .gravity))
        case "angularmovement":
            self = .angularMovement(drag: try container.decode(DynamicValueWrapper.self, forKey: .drag), force: try container.decode(DynamicValueWrapper.self, forKey: .force))
        case "alphafade":
            self = .alphaFade(fadeInTime: try container.decode(DynamicValueWrapper.self, forKey: .fadeInTime), fadeOutTime: try container.decode(DynamicValueWrapper.self, forKey: .fadeOutTime))
        case "sizechange":
            self = .sizeChange(startTime: try container.decode(DynamicValueWrapper.self, forKey: .startTime), endTime: try container.decode(DynamicValueWrapper.self, forKey: .endTime), startValue: try container.decode(DynamicValueWrapper.self, forKey: .startValue), endValue: try container.decode(DynamicValueWrapper.self, forKey: .endValue))
        case "alphachange":
            self = .alphaChange(startTime: try container.decode(DynamicValueWrapper.self, forKey: .startTime), endTime: try container.decode(DynamicValueWrapper.self, forKey: .endTime), startValue: try container.decode(DynamicValueWrapper.self, forKey: .startValue), endValue: try container.decode(DynamicValueWrapper.self, forKey: .endValue))
        case "colorchange":
            self = .colorChange(startTime: try container.decode(DynamicValueWrapper.self, forKey: .startTime), endTime: try container.decode(DynamicValueWrapper.self, forKey: .endTime), startValue: try container.decode(DynamicValueWrapper.self, forKey: .startValue), endValue: try container.decode(DynamicValueWrapper.self, forKey: .endValue))
        case "turbulence":
            self = .turbulence(scale: try container.decode(DynamicValueWrapper.self, forKey: .scale), speedMin: try container.decode(DynamicValueWrapper.self, forKey: .speedMin), speedMax: try container.decode(DynamicValueWrapper.self, forKey: .speedMax), timeScale: try container.decode(DynamicValueWrapper.self, forKey: .timeScale), mask: try container.decode(DynamicValueWrapper.self, forKey: .mask), phaseMin: try container.decode(DynamicValueWrapper.self, forKey: .phaseMin), phaseMax: try container.decode(DynamicValueWrapper.self, forKey: .phaseMax))
        case "vortex":
            self = .vortex(controlPoint: try container.decode(Int.self, forKey: .controlPoint), flags: try container.decode(Int.self, forKey: .flags), axis: try container.decode(DynamicValueWrapper.self, forKey: .axis), offset: try container.decode(DynamicValueWrapper.self, forKey: .offset), distanceInner: try container.decode(DynamicValueWrapper.self, forKey: .distanceInner), distanceOuter: try container.decode(DynamicValueWrapper.self, forKey: .distanceOuter), speedInner: try container.decode(DynamicValueWrapper.self, forKey: .speedInner), speedOuter: try container.decode(DynamicValueWrapper.self, forKey: .speedOuter), centerForce: try container.decode(DynamicValueWrapper.self, forKey: .centerForce), ringRadius: try container.decode(DynamicValueWrapper.self, forKey: .ringRadius), ringWidth: try container.decode(DynamicValueWrapper.self, forKey: .ringWidth), ringPullDistance: try container.decode(DynamicValueWrapper.self, forKey: .ringPullDistance), ringPullForce: try container.decode(DynamicValueWrapper.self, forKey: .ringPullForce), audioProcessingMode: try container.decode(DynamicValueWrapper.self, forKey: .audioProcessingMode))
        case "controlpointattract":
            self = .controlPointAttract(controlPoint: try container.decode(Int.self, forKey: .controlPoint), origin: try container.decode(DynamicValueWrapper.self, forKey: .origin), scale: try container.decode(DynamicValueWrapper.self, forKey: .scale), threshold: try container.decode(DynamicValueWrapper.self, forKey: .threshold))
        case "oscillatealpha":
            self = .oscillateAlpha(frequencyMin: try container.decode(DynamicValueWrapper.self, forKey: .frequencyMin), frequencyMax: try container.decode(DynamicValueWrapper.self, forKey: .frequencyMax), scaleMin: try container.decode(DynamicValueWrapper.self, forKey: .scaleMin), scaleMax: try container.decode(DynamicValueWrapper.self, forKey: .scaleMax), phaseMin: try container.decode(DynamicValueWrapper.self, forKey: .phaseMin), phaseMax: try container.decode(DynamicValueWrapper.self, forKey: .phaseMax))
        case "oscillatesize":
            self = .oscillateSize(frequencyMin: try container.decode(DynamicValueWrapper.self, forKey: .frequencyMin), frequencyMax: try container.decode(DynamicValueWrapper.self, forKey: .frequencyMax), scaleMin: try container.decode(DynamicValueWrapper.self, forKey: .scaleMin), scaleMax: try container.decode(DynamicValueWrapper.self, forKey: .scaleMax), phaseMin: try container.decode(DynamicValueWrapper.self, forKey: .phaseMin), phaseMax: try container.decode(DynamicValueWrapper.self, forKey: .phaseMax))
        case "oscillateposition":
            self = .oscillatePosition(frequencyMin: try container.decode(DynamicValueWrapper.self, forKey: .frequencyMin), frequencyMax: try container.decode(DynamicValueWrapper.self, forKey: .frequencyMax), scaleMin: try container.decode(DynamicValueWrapper.self, forKey: .scaleMin), scaleMax: try container.decode(DynamicValueWrapper.self, forKey: .scaleMax), phaseMin: try container.decode(DynamicValueWrapper.self, forKey: .phaseMin), phaseMax: try container.decode(DynamicValueWrapper.self, forKey: .phaseMax), mask: try container.decode(DynamicValueWrapper.self, forKey: .mask))
        default:
            self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {}
}

struct ParticleInstanceOverride: Codable {
    var count: DynamicValueWrapper?
    var alpha: DynamicValueWrapper?
    var color: DynamicValueWrapper?
    var colorn: DynamicValueWrapper?
    var size: DynamicValueWrapper?
    var lifetime: DynamicValueWrapper?
    var rate: DynamicValueWrapper?
    var speed: DynamicValueWrapper?
}

struct ParticleMaterialDef: Codable {
    var material: String
}

struct ParticleDef: Codable {
    var name: String?
    var maxCount: Int?
    var origin: DynamicValueWrapper?
    var sequenceMultiplier: Float?
    var animationMode: String?
    var flags: Int?
    var renderers: [ParticleRendererConfig]?
    var controlPoints: [ParticleControlPoint]?
    var emitters: [ParticleEmitter]?
    var initializers: [ParticleInitializer]?
    var operators: [ParticleOperator]?
    var instanceOverride: ParticleInstanceOverride?
    var material: ParticleMaterialDef?
}
