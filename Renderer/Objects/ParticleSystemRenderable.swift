//
//  ParticleSystemRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/2/8.
//

import MetalKit
import simd

class ParticleSystemRenderable: RenderableObject {
    private struct OscillatorState {
        var frequency: Float = 0
        var scale: Float = 1
        var phase: Float = 0
        var base: Float = 1
        var initialized: Bool = false
    }
    
    private struct VectorOscillatorState {
        var frequency: SIMD3<Float> = .zero
        var scale: SIMD3<Float> = .one
        var phase: SIMD3<Float> = .zero
        var initialized: Bool = false
    }
    
    private struct InitialState {
        var color: SIMD4<Float> = .one
        var alpha: Float = 1
        var size: SIMD2<Float> = .one
        var lifetime: Float = 1
    }
    
    private struct Particle {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var acceleration: SIMD3<Float>
        var rotation: SIMD3<Float>
        var angularVelocity: SIMD3<Float>
        var angularAcceleration: SIMD3<Float>
        var color: SIMD4<Float>
        var alpha: Float
        var size: SIMD2<Float>
        var frame: Float
        var age: Float
        var lifetime: Float
        var initial: InitialState
        var oscillateAlpha: OscillatorState
        var oscillateSize: OscillatorState
        var oscillatePosition: VectorOscillatorState
        var childEmitAccumulators: [Int: Float]
        var alive: Bool
        var randomAnimOffset: Float
    }
    
    private struct EmitterState {
        var emissionTimer: Float = 0
        var periodicTimer: Float = 0
        var periodicDelay: Float = 0
        var periodicDuration: Float = 0
        var emitting: Bool = false
        var instantaneousEmitted: Bool = false
    }
    
    private let device: MTLDevice
    private let config: ParticleSystemConfig
    private let animatedTexture: AnimatedTexture
    private var textureArray: MTLTexture?
    private var particles: [Particle]
    private var instanceBuffer: MTLBuffer?
    private let maxCount: Int
    private var time: Float = 0
    
    private var overrideRate: Float = 1.0
    private var overrideCount: Float = 1.0
    private var overrideColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    private var overrideAlpha: Float = 1.0
    private var overrideSpeed: Float = 1.0
    private var overrideSize: Float = 1.0
    private var overrideLifetime: Float = 1.0
    
    private var controlPoints: [ParticleControlPoint] = []
    private var resolvedControlPointPositions: [SIMD3<Float>] = []
    
    var childrenSystems: [ParticleSystemRenderable] = []
    var isChildSystem: Bool = false
    var selfRate: Float = 0
    
    private var emitterStates: [Int: EmitterState] = [:]
    private var initializerSequenceIndices: [Int: Int] = [:]
    
    init?(device: MTLDevice, config: ParticleSystemConfig, texture: AnimatedTexture, position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>, pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState?, overrides: InstanceOverride?) {
        self.device = device
        self.config = config
        self.animatedTexture = texture
        self.maxCount = config.maxcount ?? 1000
        self.particles = []
        
        super.init(position: position, rotation: rotation, size: size, scale: scale, texture: texture.textures[0], pipeline: pipeline, depthState: depthState)
        
        self.textureArray = createTextureArray(from: texture.textures, device: device)
        
        if let o = overrides {
            if let r = o.rate { self.overrideRate = r }
            if let c = o.count { self.overrideCount = c }
            if let colStr = o.colorn { self.overrideColor = MathHelper.parseVec3(colStr) }
            if let a = o.alpha { self.overrideAlpha = a }
            if let s = o.speed { self.overrideSpeed = s }
        }
        
        if let cps = config.controlpoint {
            self.controlPoints = cps
        } else {
            for i in 0..<8 {
                self.controlPoints.append(ParticleControlPoint(id: i, offset: "0 0 0", flags: 0))
            }
        }
        self.resolvedControlPointPositions = Array(repeating: .zero, count: 8)
        
        if let emitters = config.emitter {
            for (index, e) in emitters.enumerated() {
                self.selfRate += (e.rate ?? 0)
                var state = EmitterState()
                state.periodicDelay = e.delay ?? 0
                self.emitterStates[index] = state
            }
        }
        
        let capacity = Int(Float(maxCount) * overrideCount) + 1
        if capacity > 0 {
            self.particles.reserveCapacity(capacity)
            self.instanceBuffer = device.makeBuffer(length: capacity * MemoryLayout<ParticleInstance>.stride, options: .storageModeShared)
        }
        
        if let st = config.starttime, st > 0, !isChildSystem {
            let step: Float = 0.016666
            var t: Float = 0
            while t < st {
                update(dt: step, totalTime: t)
                t += step
            }
        }
    }
    
    private func createTextureArray(from textures: [MTLTexture], device: MTLDevice) -> MTLTexture? {
        guard let first = textures.first else { return nil }
        
        let desc = MTLTextureDescriptor()
        desc.textureType = .type2DArray
        desc.pixelFormat = first.pixelFormat
        desc.width = first.width
        desc.height = first.height
        desc.arrayLength = textures.count
        desc.usage = .shaderRead
        
        guard let arrayTexture = device.makeTexture(descriptor: desc) else { return nil }
        
        let bytesPerPixel = 4
        let bytesPerRow = first.width * bytesPerPixel
        let region = MTLRegionMake2D(0, 0, first.width, first.height)
        var data = [UInt8](repeating: 0, count: first.height * bytesPerRow)
        
        for (i, tex) in textures.enumerated() {
            tex.getBytes(&data, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
            arrayTexture.replace(region: region, mipmapLevel: 0, slice: i, withBytes: data, bytesPerRow: bytesPerRow, bytesPerImage: 0)
        }
        
        return arrayTexture
    }
    
    func addChild(_ child: ParticleSystemRenderable) {
        child.isChildSystem = true
        child.parent = self
        self.childrenSystems.append(child)
    }
    
    func update(dt: Float, totalTime: Float) {
        self.time = totalTime
        
        for (i, cp) in controlPoints.enumerated() {
            if i < 8 {
                let offset = MathHelper.parseVec3(cp.offset ?? "0 0 0")
                var pos = offset
                if (cp.flags ?? 0) & 2 != 0 {
                    pos = offset - self.localPosition
                }
                resolvedControlPointPositions[i] = pos
            }
        }
        
        if !isChildSystem {
            spawnParticles(dt: dt)
        }
        
        updateParticles(dt: dt, time: totalTime)
        
        for child in childrenSystems {
            child.update(dt: dt, totalTime: totalTime)
        }
    }
    
    func spawnAt(position: SIMD3<Float>) {
        let effectiveMax = Int(Float(maxCount) * overrideCount)
        if particles.count >= effectiveMax { return }
        
        guard let emitters = config.emitter, let firstEmitter = emitters.first else { return }
        createParticle(emitter: firstEmitter, emitterIndex: 0, overrideOrigin: position)
    }
    
    private func spawnParticles(dt: Float) {
        guard let emitters = config.emitter else { return }
        let effectiveMax = Int(Float(maxCount) * overrideCount)
        
        for (index, emitter) in emitters.enumerated() {
            var state = emitterStates[index] ?? EmitterState()
            
            let rate = (emitter.rate ?? 0) * overrideRate
            let limitOnePerFrame = ((emitter.flags ?? 0) & 2) != 0
            let randomPeriodic = ((emitter.flags ?? 0) & 4) != 0
            
            if let delay = emitter.delay, time < delay { continue }
            if let duration = emitter.duration, duration > 0, time > ((emitter.delay ?? 0) + duration) { continue }
            
            if randomPeriodic {
                state.periodicTimer += dt
                if !state.emitting {
                    if state.periodicTimer >= state.periodicDelay {
                        state.emitting = true
                        state.periodicTimer = 0
                        state.periodicDuration = MathHelper.safeRandomFloat(min: emitter.minPeriodicDuration ?? 0, max: emitter.maxPeriodicDuration ?? 0)
                    } else {
                        emitterStates[index] = state
                        continue
                    }
                } else {
                    if state.periodicTimer >= state.periodicDuration {
                        state.emitting = false
                        state.periodicTimer = 0
                        state.periodicDelay = MathHelper.safeRandomFloat(min: emitter.minPeriodicDelay ?? 0, max: emitter.maxPeriodicDelay ?? 0)
                        emitterStates[index] = state
                        continue
                    }
                }
            }
            
            var toEmit: Int = 0
            
            if let inst = emitter.instantaneous, inst > 0, !state.instantaneousEmitted {
                toEmit += inst
                state.instantaneousEmitted = true
            }
            
            if rate > 0 && !limitOnePerFrame {
                state.emissionTimer += rate * dt
                toEmit += Int(state.emissionTimer)
                state.emissionTimer -= Float(Int(state.emissionTimer))
            }
            
            if limitOnePerFrame && rate > 0 {
                toEmit += 1
            }
            
            for _ in 0..<toEmit {
                if particles.count < effectiveMax {
                    createParticle(emitter: emitter, emitterIndex: index)
                } else {
                    break
                }
            }
            
            emitterStates[index] = state
        }
    }
    
    private func createParticle(emitter: ParticleEmitter, emitterIndex: Int, overrideOrigin: SIMD3<Float>? = nil) {
        var p = Particle(
            position: .zero,
            velocity: .zero,
            acceleration: .zero,
            rotation: .zero,
            angularVelocity: .zero,
            angularAcceleration: .zero,
            color: .one,
            alpha: 1.0,
            size: SIMD2<Float>(20, 20),
            frame: 0,
            age: 0,
            lifetime: 1,
            initial: InitialState(),
            oscillateAlpha: OscillatorState(),
            oscillateSize: OscillatorState(),
            oscillatePosition: VectorOscillatorState(),
            childEmitAccumulators: [:],
            alive: true,
            randomAnimOffset: Float.random(in: 0...Float(animatedTexture.duration))
        )
        
        var originVec = MathHelper.parseVec3(emitter.origin ?? "0 0 0")
        originVec.y = -originVec.y
        
        var spawnOrigin = originVec
        
        var cpIndex = emitter.controlpoint ?? -1
        if let overridePos = overrideOrigin {
            spawnOrigin = overridePos
        } else {
            if cpIndex == -1 && !controlPoints.isEmpty {
                let cp0 = controlPoints[0]
                if (cp0.flags ?? 0) & 1 != 0 {
                    cpIndex = 0
                }
            }
            if cpIndex >= 0 && cpIndex < resolvedControlPointPositions.count {
                spawnOrigin += resolvedControlPointPositions[cpIndex]
            }
        }
        
        var randomPos = SIMD3<Float>(0, 0, 0)
        var directions = MathHelper.parseVec3(emitter.directions ?? "1 1 1")
        directions.y = -directions.y
        
        if emitter.name == "sphererandom" {
            let is3D = ((config.flags ?? 0) & 4) != 0
            
            let distMin = Float(emitter.distancemin?.value ?? "0") ?? 0
            let distMax = Float(emitter.distancemax?.value ?? "0") ?? 0
            
            if !is3D {
                let angle = Float.random(in: 0...(2 * .pi))
                let minRadiusSq = distMin * distMin
                let maxRadiusSq = distMax * distMax
                let radiusXY = sqrt(MathHelper.safeRandomFloat(min: minRadiusSq, max: maxRadiusSq))
                
                let z = MathHelper.safeRandomFloat(min: -distMax, max: distMax)
                
                randomPos = SIMD3<Float>(
                    radiusXY * cos(angle),
                    radiusXY * sin(angle),
                    z
                )
            } else {
                let u = Float.random(in: 0...1)
                let v = Float.random(in: 0...1)
                let theta = 2 * Float.pi * u
                let phi = acos(2 * v - 1)
                
                let minR3 = distMin * distMin * distMin
                let maxR3 = distMax * distMax * distMax
                let r = pow(MathHelper.safeRandomFloat(min: minR3, max: maxR3), 1.0/3.0)
                
                let x = sin(phi) * cos(theta)
                let y = sin(phi) * sin(theta)
                let z = cos(phi)
                
                randomPos = SIMD3<Float>(x, y, z) * r
            }
            randomPos *= directions
            
        } else if emitter.name == "boxrandom" {
            let minVec = MathHelper.parseVec3(emitter.distancemin?.value ?? "0 0 0")
            let maxVec = MathHelper.parseVec3(emitter.distancemax?.value ?? "0 0 0")
            
            let x = MathHelper.safeRandomFloat(min: minVec.x, max: maxVec.x) * (Float.random(in: 0...1) > 0.5 ? 1 : -1)
            let y = MathHelper.safeRandomFloat(min: minVec.y, max: maxVec.y) * (Float.random(in: 0...1) > 0.5 ? 1 : -1)
            let z = MathHelper.safeRandomFloat(min: minVec.z, max: maxVec.z) * (Float.random(in: 0...1) > 0.5 ? 1 : -1)
            
            randomPos = SIMD3<Float>(x, y, z) * directions
        }
        
        if let signStr = emitter.sign {
            let signs = MathHelper.parseVec3(signStr)
            for i in 0..<3 {
                if signs[i] > 0.5 { randomPos[i] = abs(randomPos[i]) }
                else if signs[i] < -0.5 { randomPos[i] = -abs(randomPos[i]) }
            }
        }
        
        p.position = spawnOrigin + randomPos
        
        p.color = SIMD4<Float>(overrideColor, 1.0)
        p.alpha = overrideAlpha
        p.size *= overrideSize
        p.lifetime *= overrideLifetime
        
        if let initializers = config.initializer {
            for (idx, initOp) in initializers.enumerated() {
                applyInitializer(op: initOp, idx: idx, p: &p)
            }
        }
        
        p.initial.color = p.color
        p.initial.alpha = p.alpha
        p.initial.size = p.size
        p.initial.lifetime = p.lifetime
        
        particles.append(p)
    }
    
    private func applyInitializer(op: ParticleInitializer, idx: Int, p: inout Particle) {
        switch op.name {
        case "lifetimerandom":
            let minV = Float(op.min?.value ?? "0") ?? 0
            let maxV = Float(op.max?.value ?? "0") ?? 0
            let exp = Float(op.exponent?.value ?? "1") ?? 1
            let t = pow(Float.random(in: 0...1), exp)
            p.lifetime = minV + t * (maxV - minV)
            
        case "sizerandom":
            let minV = Float(op.min?.value ?? "0") ?? 0
            let maxV = Float(op.max?.value ?? "0") ?? 0
            let exp = Float(op.exponent?.value ?? "1") ?? 1
            let t = pow(Float.random(in: 0...1), exp)
            let val = minV + t * (maxV - minV)
            p.size = SIMD2<Float>(val, val) * 0.5 * overrideSize
            
        case "velocityrandom":
            let minV = MathHelper.parseVec3(op.min?.value ?? "0 0 0")
            let maxV = MathHelper.parseVec3(op.max?.value ?? "0 0 0")
            var vel = MathHelper.randomVec3(min: minV, max: maxV)
            vel.y = -vel.y
            p.velocity += vel * overrideSpeed
            
        case "colorrandom":
            let minV = MathHelper.parseVec3(op.min?.value ?? "0 0 0") / 255.0
            let maxV = MathHelper.parseVec3(op.max?.value ?? "0 0 0") / 255.0
            let col = MathHelper.randomVec3(min: minV, max: maxV)
            p.color = SIMD4<Float>(col * overrideColor, p.color.w)
            
        case "rotationrandom":
            let minV = MathHelper.parseVec3(op.min?.value ?? "0 0 0")
            let maxV = MathHelper.parseVec3(op.max?.value ?? "0 0 0")
            p.rotation = MathHelper.randomVec3(min: minV, max: maxV) * overrideSpeed
            
        case "angularvelocityrandom":
            let minV = MathHelper.parseVec3(op.min?.value ?? "0 0 0")
            let maxV = MathHelper.parseVec3(op.max?.value ?? "0 0 0")
            let exp = Float(op.exponent?.value ?? "1") ?? 1
            let t = pow(Float.random(in: 0...1), exp)
            let val = minV + (maxV - minV) * t
            p.angularVelocity = val * overrideSpeed
            
        case "alpharandom":
            let minV = Float(op.min?.value ?? "0") ?? 0
            let maxV = Float(op.max?.value ?? "0") ?? 0
            p.alpha = MathHelper.safeRandomFloat(min: minV, max: maxV) * overrideAlpha
            
        case "turbulentvelocityrandom":
            let speedMin = Float(op.speedmin?.value ?? "0") ?? 0
            let speedMax = Float(op.speedmax?.value ?? "0") ?? 0
            let offset = Float(op.offset?.value ?? "0") ?? 0
            let scale = Float(op.scale?.value ?? "1") ?? 1
            let phaseMin = Float(op.phasemin?.value ?? "0") ?? 0
            let phaseMax = Float(op.phasemax?.value ?? "0") ?? 0
            var forward = MathHelper.parseVec3(op.forward?.value ?? "0 0 1")
            var right = MathHelper.parseVec3(op.right?.value ?? "1 0 0")
            
            forward.y = -forward.y
            right.y = -right.y
            
            if simd_length(forward) > 0.0001 { forward = simd_normalize(forward) }
            if simd_length(right) > 0.0001 { right = simd_normalize(right) }
            
            let speed = MathHelper.safeRandomFloat(min: speedMin, max: speedMax)
            let phase = MathHelper.safeRandomFloat(min: phaseMin, max: phaseMax)
            
            let noisePos = MathHelper.randomVec3(min: SIMD3<Float>(repeating: 0), max: SIMD3<Float>(repeating: 10))
            let samplePos = noisePos + SIMD3<Float>(phase, phase * 0.7, phase * 1.3)
            
            var result = SimplexNoise.curlNoise(samplePos)
            let len = simd_length(result)
            if len < 0.0001 {
                result = forward
            } else {
                result = result / len
            }
            
            if scale < 2.0 {
                let cosAngle = simd_dot(result, forward)
                let angle = acos(simd_clamp(cosAngle, -1.0, 1.0)) / Float.pi
                let maxAngle = scale / 2.0
                
                if angle > maxAngle && maxAngle > 0.0001 {
                    var axis = simd_cross(result, forward)
                    let axisLen = simd_length(axis)
                    if axisLen > 0.0001 {
                        axis = axis / axisLen
                        let rotAngle = (angle - maxAngle) * Float.pi
                        let rot = Matrix4x4.rotationMatrix3x3(angle: rotAngle, axis: axis)
                        result = rot * result
                    }
                }
            }
            
            if abs(offset) > 0.0001 {
                let rot = Matrix4x4.rotationMatrix3x3(angle: -offset, axis: right)
                result = rot * result
            }
            
            p.velocity += result * speed * overrideSpeed
            
        case "mapsequencearoundcontrolpoint":
            let cpIdx = Int(Float(op.controlpoint?.value ?? "0") ?? 0)
            let count = Int(Float(op.count?.value ?? "1") ?? 1)
            let sMin = MathHelper.parseVec3(op.speedmin?.value ?? "0 0 0")
            let sMax = MathHelper.parseVec3(op.speedmax?.value ?? "0 0 0")
            
            var seqIdx = initializerSequenceIndices[idx] ?? 0
            let angle = (Float(seqIdx) / Float(count)) * 2 * Float.pi
            initializerSequenceIndices[idx] = (seqIdx + 1) % count
            
            var centerPos = SIMD3<Float>(0,0,0)
            if cpIdx >= 0 && cpIdx < resolvedControlPointPositions.count {
                centerPos = resolvedControlPointPositions[cpIdx]
            }
            
            p.position = centerPos
            
            var speed = MathHelper.randomVec3(min: sMin, max: sMax)
            speed.y = -speed.y
            
            let c = cos(angle)
            let s = sin(angle)
            let rotMat = matrix_float3x3(
                SIMD3<Float>(c, -s, 0),
                SIMD3<Float>(s, c, 0),
                SIMD3<Float>(0, 0, 1)
            )
            
            p.velocity = (rotMat * speed) * overrideSpeed
            
        default:
            break
        }
    }
    
    private func updateParticles(dt: Float, time: Float) {
        var alive: [Particle] = []
        alive.reserveCapacity(particles.count)
        
        let operators = config.operatorList ?? []
        
        for var p in particles {
            p.age += dt
            if p.age >= p.lifetime { continue }
            
            for op in operators {
                switch op.name {
                case "movement":
                    let drag = Float(op.drag?.value ?? "0") ?? 0
                    var gravity = MathHelper.parseVec3(op.gravity?.value ?? "0 0 0")
                    gravity.y = -gravity.y
                    
                    p.position += p.velocity * dt
                    p.velocity += gravity * dt * overrideSpeed
                    
                    var dragFactor = 1.0 - (drag * dt)
                    if dragFactor < 0 { dragFactor = 0 }
                    p.velocity *= dragFactor
                    
                case "angularmovement":
                    let drag = Float(op.drag?.value ?? "0") ?? 0
                    let force = MathHelper.parseVec3(op.force?.value ?? "0 0 0")
                    
                    p.rotation += p.angularVelocity * dt * overrideSpeed
                    p.angularVelocity += force * dt * overrideSpeed
                    
                    var dragFactor = 1.0 - (drag * dt)
                    if dragFactor < 0 { dragFactor = 0 }
                    p.angularVelocity *= dragFactor
                    
                case "alphafade":
                    let fin = Float(op.fadeintime?.value ?? "0") ?? 0
                    let fout = Float(op.fadeouttime?.value ?? "0") ?? 0
                    let life = p.age / p.lifetime
                    
                    if life <= fin {
                        p.alpha = p.initial.alpha * MathHelper.fadeValue(life: life, startTime: 0, endTime: fin, startValue: 0, endValue: 1)
                    } else if life > fout {
                        p.alpha = p.initial.alpha * (1.0 - MathHelper.fadeValue(life: life, startTime: fout, endTime: 1, startValue: 0, endValue: 1))
                    } else {
                        p.alpha = p.initial.alpha
                    }
                    p.oscillateAlpha.base = p.alpha
                    
                case "oscillatealpha":
                    let fMin = Float(op.frequencymin?.value ?? "0") ?? 0
                    let fMax = Float(op.frequencymax?.value ?? "0") ?? 0
                    let sMin = Float(op.scalemin?.value ?? "0") ?? 0
                    let sMax = Float(op.scalemax?.value ?? "1") ?? 1
                    let pMin = Float(op.phasemin?.value ?? "0") ?? 0
                    let pMax = Float(op.phasemax?.value ?? "0") ?? 0
                    
                    if !p.oscillateAlpha.initialized {
                        p.oscillateAlpha.frequency = MathHelper.safeRandomFloat(min: fMin, max: fMax)
                        p.oscillateAlpha.scale = MathHelper.safeRandomFloat(min: sMin, max: sMax)
                        p.oscillateAlpha.phase = MathHelper.safeRandomFloat(min: pMin, max: pMax) + 2.0 * Float.pi
                        p.oscillateAlpha.base = p.alpha
                        p.oscillateAlpha.initialized = true
                    }
                    
                    let w = p.oscillateAlpha.frequency
                    let t = p.age
                    let cosVal = (cos(w * t + p.oscillateAlpha.phase) + 1.0) * 0.5
                    let multiplier = MathHelper.lerp(t: cosVal, a: sMin, b: sMax)
                    p.alpha = p.oscillateAlpha.base * multiplier
                    
                case "oscillatesize":
                    let fMin = Float(op.frequencymin?.value ?? "0") ?? 0
                    let fMax = Float(op.frequencymax?.value ?? "0") ?? 0
                    let sMin = Float(op.scalemin?.value ?? "0") ?? 0
                    let sMax = Float(op.scalemax?.value ?? "1") ?? 1
                    let pMin = Float(op.phasemin?.value ?? "0") ?? 0
                    let pMax = Float(op.phasemax?.value ?? "0") ?? 0
                    
                    if !p.oscillateSize.initialized {
                        p.oscillateSize.frequency = MathHelper.safeRandomFloat(min: fMin, max: fMax)
                        p.oscillateSize.scale = MathHelper.safeRandomFloat(min: sMin, max: sMax)
                        p.oscillateSize.phase = MathHelper.safeRandomFloat(min: pMin, max: pMax) + 2.0 * Float.pi
                        p.oscillateSize.base = p.size.x
                        p.oscillateSize.initialized = true
                    }
                    
                    let w = p.oscillateSize.frequency
                    let t = p.age
                    let cosVal = (cos(w * t + p.oscillateSize.phase) + 1.0) * 0.5
                    let multiplier = MathHelper.lerp(t: cosVal, a: sMin, b: sMax)
                    p.size = p.initial.size * multiplier
                    
                case "turbulence":
                    let scale = Float(op.scale?.value ?? "1") ?? 1
                    let speedMin = Float(op.speedmin?.value ?? "0") ?? 0
                    let speedMax = Float(op.speedmax?.value ?? "0") ?? 0
                    let timeScale = Float(op.timescale?.value ?? "1") ?? 1
                    let mask = MathHelper.parseVec3(op.mask?.value ?? "1 1 1")
                    let pMin = Float(op.phasemin?.value ?? "0") ?? 0
                    let pMax = Float(op.phasemax?.value ?? "0") ?? 0
                    
                    let turbSpeed = (speedMin + speedMax) * 0.5
                    if turbSpeed <= 0.0001 { break }
                    
                    let phase = (pMin + pMax) * 0.5
                    var noisePos = p.position
                    noisePos.x += phase + timeScale * time
                    noisePos *= scale * 2.0
                    
                    var curlDir = SimplexNoise.curlNoise(noisePos)
                    let len = simd_length(curlDir)
                    if len > 0.0001 {
                        curlDir = (curlDir / len) * turbSpeed
                    }
                    curlDir *= mask
                    p.velocity += curlDir * dt * overrideSpeed
                    
                case "controlpointattract":
                    let cpIdx = op.controlpoint ?? 0
                    let origin = MathHelper.parseVec3(op.origin?.value ?? "0 0 0")
                    let scale = Float(op.scale?.value ?? "0") ?? 0
                    let threshold = (Float(op.threshold?.value ?? "0") ?? 0) / 2.0
                    
                    if cpIdx < 0 || cpIdx >= resolvedControlPointPositions.count { break }
                    let center = resolvedControlPointPositions[cpIdx] + origin
                    
                    let toCenter = center - p.position
                    let dist = simd_length(toCenter)
                    
                    if dist > 0.001 && dist < threshold {
                        let direction = toCenter / dist
                        let force = direction * scale * dt
                        p.velocity += force * overrideSpeed
                    }
                    
                case "sizechange":
                    let start = Float(op.startvalue?.value ?? "1") ?? 1
                    let end = Float(op.endvalue?.value ?? "1") ?? 1
                    let startTime = Float(op.starttime?.value ?? "0") ?? 0
                    let endTime = Float(op.endtime?.value ?? "1") ?? 1
                    
                    let life = p.age / p.lifetime
                    let multiplier = MathHelper.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: start, endValue: end)
                    p.size = p.initial.size * multiplier
                    p.oscillateSize.base = p.size.x
                    
                case "alphachange":
                    let start = Float(op.startvalue?.value ?? "1") ?? 1
                    let end = Float(op.endvalue?.value ?? "1") ?? 1
                    let startTime = Float(op.starttime?.value ?? "0") ?? 0
                    let endTime = Float(op.endtime?.value ?? "1") ?? 1
                    
                    let life = p.age / p.lifetime
                    let multiplier = MathHelper.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: start, endValue: end)
                    p.alpha = p.initial.alpha * multiplier
                    p.oscillateAlpha.base = p.alpha
                    
                case "colorchange":
                    let start = MathHelper.parseVec3(op.startvalue?.value ?? "1 1 1")
                    let end = MathHelper.parseVec3(op.endvalue?.value ?? "1 1 1")
                    let startTime = Float(op.starttime?.value ?? "0") ?? 0
                    let endTime = Float(op.endtime?.value ?? "1") ?? 1
                    
                    let life = p.age / p.lifetime
                    let r = MathHelper.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: start.x, endValue: end.x)
                    let g = MathHelper.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: start.y, endValue: end.y)
                    let b = MathHelper.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: start.z, endValue: end.z)
                    
                    p.color = SIMD4<Float>(p.initial.color.x * r, p.initial.color.y * g, p.initial.color.z * b, p.color.w)
                    
                case "oscillateposition":
                    let fMin = Float(op.frequencymin?.value ?? "0") ?? 0
                    let fMax = Float(op.frequencymax?.value ?? "0") ?? 0
                    let sMin = Float(op.scalemin?.value ?? "0") ?? 0
                    let sMax = Float(op.scalemax?.value ?? "0") ?? 0
                    let pMin = Float(op.phasemin?.value ?? "0") ?? 0
                    let pMax = Float(op.phasemax?.value ?? "0") ?? 0
                    let mask = MathHelper.parseVec3(op.mask?.value ?? "1 1 1")
                    
                    if !p.oscillatePosition.initialized {
                        for i in 0..<3 {
                            p.oscillatePosition.frequency[i] = MathHelper.safeRandomFloat(min: fMin, max: fMax)
                            p.oscillatePosition.scale[i] = MathHelper.safeRandomFloat(min: sMin, max: sMax)
                            p.oscillatePosition.phase[i] = MathHelper.safeRandomFloat(min: pMin, max: pMax) + 2.0 * Float.pi
                        }
                        p.oscillatePosition.initialized = true
                    }
                    
                    let t = p.age
                    var delta = SIMD3<Float>(0, 0, 0)
                    for i in 0..<3 {
                        let w = p.oscillatePosition.frequency[i]
                        let move = -p.oscillatePosition.scale[i] * w * sin(w * t + p.oscillatePosition.phase[i]) * dt
                        delta[i] = move * mask[i] * overrideSpeed
                    }
                    p.position += delta
                    
                case "vortex":
                    let cpIdx = op.controlpoint ?? 0
                    let axisVal = MathHelper.parseVec3(op.axis?.value ?? "0 0 1")
                    let offsetVal = MathHelper.parseVec3(op.offset?.value ?? "0 0 0")
                    let distInner = Float(op.distanceInner?.value ?? "0") ?? 0
                    let distOuter = Float(op.distanceOuter?.value ?? "0") ?? 0
                    let speedInner = Float(op.speedInner?.value ?? "0") ?? 0
                    let speedOuter = Float(op.speedOuter?.value ?? "0") ?? 0
                    let centerForce = Float(op.centerForce?.value ?? "0") ?? 0
                    let ringRadius = Float(op.ringRadius?.value ?? "0") ?? 0
                    let ringWidth = Float(op.ringWidth?.value ?? "0") ?? 0
                    let ringPullDist = Float(op.ringPullDistance?.value ?? "0") ?? 0
                    let ringPullForce = Float(op.ringPullForce?.value ?? "0") ?? 0
                    let flags = op.flags ?? 0
                    
                    let infiniteAxis = (flags & 1) != 0
                    let maintainDist = (flags & 2) != 0
                    let ringShape = (flags & 4) != 0
                    
                    var center = offsetVal
                    if cpIdx >= 0 && cpIdx < resolvedControlPointPositions.count {
                        center = resolvedControlPointPositions[cpIdx] + offsetVal
                    }
                    
                    var axis = axisVal
                    if simd_length(axis) > 0 { axis = simd_normalize(axis) } else { axis = SIMD3<Float>(0,0,1) }
                    
                    let toParticle = p.position - center
                    var radialVector = toParticle
                    
                    if infiniteAxis {
                        let axialDist = simd_dot(toParticle, axis)
                        radialVector = toParticle - axis * axialDist
                    }
                    
                    let distance = simd_length(radialVector)
                    var tangent = simd_cross(axis, radialVector)
                    if simd_length(tangent) > 0.001 { tangent = simd_normalize(tangent) } else { continue }
                    
                    var speed: Float = 0
                    var radialForce = SIMD3<Float>(0,0,0)
                    
                    if ringShape {
                        let ringInner = ringRadius - ringWidth * 0.5
                        let ringOuter = ringRadius + ringWidth * 0.5
                        
                        if distance < ringInner {
                            speed = 0
                        } else if distance <= ringOuter {
                            let t = (distance - ringInner) / ringWidth
                            speed = MathHelper.lerp(t: t, a: speedInner, b: speedOuter)
                        } else if distance <= ringOuter + ringPullDist {
                            let pullT = (distance - ringOuter) / ringPullDist
                            speed = speedOuter * (1.0 - pullT)
                            if distance > 0.001 {
                                let towardRing = -simd_normalize(radialVector)
                                radialForce = towardRing * ringPullForce * pullT
                            }
                        }
                    } else {
                        let disMid = distOuter - distInner + 0.1
                        if disMid < 0 || distance < distInner {
                            speed = speedInner
                        } else if distance > distOuter {
                            speed = speedOuter
                        } else {
                            let t = (distance - distInner) / disMid
                            speed = MathHelper.lerp(t: t, a: speedInner, b: speedOuter)
                        }
                    }
                    
                    p.velocity += tangent * speed * dt * overrideSpeed
                    p.velocity += radialForce * dt * overrideSpeed
                    
                    if maintainDist && distance > 0.001 {
                        let towardCenter = -simd_normalize(radialVector)
                        p.velocity += towardCenter * centerForce * dt * overrideSpeed
                    }
                    
                default:
                    break
                }
            }
            alive.append(p)
        }
        
        particles = alive
        
        if let children = config.children {
            for (idx, _) in children.enumerated() {
                if idx < childrenSystems.count {
                    let childSys = childrenSystems[idx]
                    var rate = childSys.selfRate > 0 ? childSys.selfRate : 30.0
                    if rate > 40.0 { rate = 40.0 }
                    
                    for i in 0..<particles.count {
                        var acc = particles[i].childEmitAccumulators[idx] ?? 0
                        acc += rate * dt
                        
                        let spawnPos = particles[i].position
                        
                        while acc >= 1.0 {
                            acc -= 1.0
                            childSys.spawnAt(position: spawnPos)
                        }
                        particles[i].childEmitAccumulators[idx] = acc
                    }
                }
            }
        }
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        if particles.isEmpty || instanceBuffer == nil { return }
        
        var instances = particles.map { p -> ParticleInstance in
            return ParticleInstance(
                position: p.position,
                color: SIMD4<Float>(p.color.x, p.color.y, p.color.z, p.alpha),
                size: p.size,
                rotation: p.rotation.z,
                animationOffset: p.randomAnimOffset
            )
        }
        
        let count = instances.count
        instanceBuffer?.contents().copyMemory(from: &instances, byteCount: count * MemoryLayout<ParticleInstance>.stride)
        
        encoder.setRenderPipelineState(pipeline)
        
        if let texArray = self.textureArray {
            encoder.setFragmentTexture(texArray, index: 0)
        } else if let first = animatedTexture.textures.first {
            encoder.setFragmentTexture(first, index: 0)
        }
        
        if let ds = depthState {
            encoder.setDepthStencilState(ds)
        }
        
        var objUniforms = ObjectUniforms(
            modelMatrix: worldMatrix,
            alpha: 1.0,
            color: SIMD4<Float>(1,1,1,1),
            animInfo: SIMD3<Float>(Float(animatedTexture.textures.count), Float(animatedTexture.duration), 0)
        )
        encoder.setVertexBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 3)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        
        for child in childrenSystems {
            child.draw(encoder: encoder)
        }
    }
}
