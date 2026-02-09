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
        var isNew: Bool
        var isDead: Bool
        var randomAnimOffset: Float
    }
    
    private let device: MTLDevice
    private let config: ParticleSystemConfig
    private let animatedTexture: AnimatedTexture
    private var textureArray: MTLTexture?
    private var particles: [Particle]
    private var instanceBuffer: MTLBuffer?
    private var emitAccumulator: Float = 0
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
    var childType: String = ""
    var selfRate: Float = 0
    var spawnCount: Int = 1
    
    private var isWorldSpace: Bool = false
    
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
            if let sz = o.size { self.overrideSize = sz }
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
            for e in emitters {
                self.selfRate += (e.rate ?? 0)
            }
        }
        
        if let f = config.flags, (f & 4) != 0 {
            self.isWorldSpace = true
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
    
    func addChild(_ child: ParticleSystemRenderable, type: String, count: Int = 1) {
        child.isChildSystem = true
        child.childType = type
        child.parent = self
        child.spawnCount = count
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
    
    func spawnAt(position: SIMD3<Float>, count: Int = 1) {
        let effectiveMax = Int(Float(maxCount) * overrideCount)
        if particles.count >= effectiveMax { return }
        
        guard let emitters = config.emitter, let firstEmitter = emitters.first else { return }
        
        for _ in 0..<count {
            if particles.count < effectiveMax {
                createParticle(emitter: firstEmitter, overrideOrigin: position)
            }
        }
    }
    
    private func spawnParticles(dt: Float) {
        guard let emitters = config.emitter else { return }
        let effectiveMax = Int(Float(maxCount) * overrideCount)
        
        for emitter in emitters {
            let rate = (emitter.rate ?? 0) * overrideRate
            if rate <= 0 { continue }
            
            if let delay = emitter.delay, time < delay { continue }
            if let duration = emitter.duration, duration > 0, time > ((emitter.delay ?? 0) + duration) { continue }
            
            emitAccumulator += rate * dt
            while emitAccumulator >= 1.0 {
                emitAccumulator -= 1.0
                if particles.count < effectiveMax {
                    createParticle(emitter: emitter)
                }
            }
            
            if let inst = emitter.instantaneous, inst > 0, time <= dt {
                for _ in 0..<inst {
                    if particles.count < effectiveMax {
                        createParticle(emitter: emitter)
                    }
                }
            }
        }
    }
    
    private func createParticle(emitter: ParticleEmitter, overrideOrigin: SIMD3<Float>? = nil) {
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
            isNew: true,
            isDead: false,
            randomAnimOffset: Float.random(in: 0...Float(animatedTexture.duration))
        )
        
        var spawnOrigin = MathHelper.parseVec3(emitter.origin ?? "0 0 0")
        
        if let overridePos = overrideOrigin {
            spawnOrigin = overridePos
        }
        
        var randomPos = SIMD3<Float>(0, 0, 0)
        let directions = MathHelper.parseVec3(emitter.directions ?? "1 1 1")
        
        if emitter.name == "sphererandom" || emitter.name == "sphere" {
            let distMin = Float(emitter.distancemin?.value ?? "0") ?? 0
            let distMax = Float(emitter.distancemax?.value ?? "0") ?? 0
            
            let u = Float.random(in: 0...1)
            let v = Float.random(in: 0...1)
            let theta = 2 * Float.pi * u
            let phi = acos(2 * v - 1)
            
            let x = sin(phi) * cos(theta)
            let y = sin(phi) * sin(theta)
            let z = cos(phi)
            
            let unitPos = SIMD3<Float>(x, y, z)
            
            let r = pow(Float.random(in: 0...1), 1.0/3.0)
            let dist = distMin + (distMax - distMin) * r
            
            randomPos = unitPos * dist * directions
            
        } else if emitter.name == "boxrandom" || emitter.name == "box" {
            let minVec = MathHelper.parseVec3(emitter.distancemin?.value ?? "0 0 0")
            let maxVec = MathHelper.parseVec3(emitter.distancemax?.value ?? "0 0 0")
            
            let x = MathHelper.safeRandomFloat(min: minVec.x, max: maxVec.x)
            let y = MathHelper.safeRandomFloat(min: minVec.y, max: maxVec.y)
            let z = MathHelper.safeRandomFloat(min: minVec.z, max: maxVec.z)
            
            randomPos = SIMD3<Float>(x, y, z) * directions
        }
        
        if isWorldSpace {
            let rotMat = Matrix4x4.rotation(angle: localRotation.z, axis: SIMD3<Float>(0, 0, 1))
            let rotatedPos4 = rotMat * SIMD4<Float>(randomPos.x, randomPos.y, randomPos.z, 1.0)
            let rotatedPos = SIMD3<Float>(rotatedPos4.x, rotatedPos4.y, rotatedPos4.z)
            
            let rotatedOrigin4 = rotMat * SIMD4<Float>(spawnOrigin.x, spawnOrigin.y, spawnOrigin.z, 1.0)
            let rotatedOrigin = SIMD3<Float>(rotatedOrigin4.x, rotatedOrigin4.y, rotatedOrigin4.z)
            
            p.position = self.localPosition + rotatedOrigin + rotatedPos
            p.size = p.size * SIMD2<Float>(scale.x, scale.y)
        } else {
            p.position = spawnOrigin + randomPos
        }
        
        p.color = SIMD4<Float>(overrideColor, 1.0)
        p.alpha = overrideAlpha
        p.size *= overrideSize
        p.lifetime *= overrideLifetime
        
        if let initializers = config.initializer {
            for initOp in initializers {
                applyInitializer(op: initOp, p: &p)
            }
        }
        
        if isWorldSpace {
            let rotMat = Matrix4x4.rotation(angle: localRotation.z, axis: SIMD3<Float>(0, 0, 1))
            let vel4 = rotMat * SIMD4<Float>(p.velocity.x, p.velocity.y, p.velocity.z, 0.0)
            p.velocity = SIMD3<Float>(vel4.x, vel4.y, vel4.z)
        }
        
        p.initial.color = p.color
        p.initial.alpha = p.alpha
        p.initial.size = p.size
        p.initial.lifetime = p.lifetime
        
        particles.append(p)
    }
    
    private func applyInitializer(op: ParticleInitializer, p: inout Particle) {
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
            p.size = SIMD2<Float>(val, val) * 0.5
            
        case "velocityrandom":
            let minV = MathHelper.parseVec3(op.min?.value ?? "0 0 0")
            let maxV = MathHelper.parseVec3(op.max?.value ?? "0 0 0")
            var vel = MathHelper.randomVec3(min: minV, max: maxV)
            p.velocity += vel * overrideSpeed
            
        case "colorrandom":
            let minV = MathHelper.parseVec3(op.min?.value ?? "0 0 0") / 255.0
            let maxV = MathHelper.parseVec3(op.max?.value ?? "0 0 0") / 255.0
            let col = MathHelper.randomVec3(min: minV, max: maxV)
            p.color = SIMD4<Float>(col * overrideColor, p.color.w)
            
        case "rotationrandom":
            let minV = MathHelper.parseVec3(op.min?.value ?? "0 0 0")
            let maxV = MathHelper.parseVec3(op.max?.value ?? "0 0 0")
            p.rotation = MathHelper.randomVec3(min: minV, max: maxV)
            
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
            let timeScale = Float(op.timescale?.value ?? "1") ?? 1
            
            var forward = MathHelper.parseVec3(op.forward?.value ?? "0 0 1")
            let right = MathHelper.parseVec3(op.right?.value ?? "1 0 0")
            
            forward = simd_normalize(forward)
            
            let speed = MathHelper.safeRandomFloat(min: speedMin, max: speedMax)
            let phase = MathHelper.safeRandomFloat(min: phaseMin, max: phaseMax)
            
            var noisePos = p.position * scale
            noisePos.x += phase
            
            var result = SimplexNoise.curlNoise(noisePos)
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
                let rot = Matrix4x4.rotationMatrix3x3(angle: -offset, axis: simd_normalize(right))
                result = rot * result
            }
            
            p.velocity += result * speed * overrideSpeed
            
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
            if p.age >= p.lifetime {
                p.isDead = true
            }
            
            for op in operators {
                switch op.name {
                case "movement":
                    let drag = Float(op.drag?.value ?? "0") ?? 0
                    let gravity = MathHelper.parseVec3(op.gravity?.value ?? "0 0 0")
                    
                    p.position += p.velocity * dt
                    p.velocity += gravity * dt * overrideSpeed
                    
                    if drag > 0 {
                        let dragFactor = exp(-drag * dt)
                        p.velocity *= dragFactor
                    }
                    
                case "angularmovement":
                    let drag = Float(op.drag?.value ?? "0") ?? 0
                    let force = MathHelper.parseVec3(op.force?.value ?? "0 0 0")
                    
                    p.rotation += p.angularVelocity * dt * overrideSpeed
                    p.angularVelocity += force * dt * overrideSpeed
                    
                    if drag > 0 {
                        let dragFactor = exp(-drag * dt)
                        p.angularVelocity *= dragFactor
                    }
                    
                case "alphafade":
                    let fin = Float(op.fadeintime?.value ?? "0") ?? 0
                    var fout = fin
                    if let foutStr = op.fadeouttime?.value, let f = Float(foutStr) {
                        fout = f
                    }
                    
                    let life = p.age / p.lifetime
                    
                    if life <= fin {
                        p.alpha = p.initial.alpha * MathHelper.fadeValue(life: life, startTime: 0, endTime: fin, startValue: 0, endValue: 1)
                    } else if life > fout {
                        p.alpha = p.initial.alpha * (1.0 - MathHelper.fadeValue(life: life, startTime: fout, endTime: 1, startValue: 0, endValue: 1))
                    } else {
                        p.alpha = p.initial.alpha
                    }
                    p.oscillateAlpha.base = p.alpha
                    
                case "alphachange":
                    let startVal = Float(op.startvalue?.value ?? "1") ?? 1
                    let endVal = Float(op.endvalue?.value ?? "0") ?? 0
                    let startTime = Float(op.starttime?.value ?? "0") ?? 0
                    let endTime = Float(op.endtime?.value ?? "1") ?? 1
                    
                    let life = p.age / p.lifetime
                    p.alpha = p.initial.alpha * MathHelper.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: startVal, endValue: endVal)
                    p.oscillateAlpha.base = p.alpha
                    
                case "colorchange":
                    let startVal = MathHelper.parseVec3(op.startvalue?.value ?? "255 255 255") / 255.0
                    let endVal = MathHelper.parseVec3(op.endvalue?.value ?? "255 255 255") / 255.0
                    let startTime = Float(op.starttime?.value ?? "0") ?? 0
                    let endTime = Float(op.endtime?.value ?? "1") ?? 1
                    
                    let life = p.age / p.lifetime
                    let t = (life - startTime) / (endTime - startTime)
                    let clampedT = simd_clamp(t, 0, 1)
                    
                    let mixedColor = MathHelper.lerpVec3(t: clampedT, a: startVal, b: endVal)
                    p.color = SIMD4<Float>(mixedColor * overrideColor, p.color.w)
                    
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
                        p.oscillateAlpha.phase = MathHelper.safeRandomFloat(min: pMin, max: pMax)
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
                        p.oscillateSize.phase = MathHelper.safeRandomFloat(min: pMin, max: pMax)
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
                    noisePos *= scale * 0.01
                    
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
                    
                case "vortex":
                    let cpIdx = op.controlpoint ?? 0
                    if cpIdx < 0 || cpIdx >= resolvedControlPointPositions.count { break }
                    
                    let offset = MathHelper.parseVec3(op.offset?.value ?? "0 0 0")
                    let center = resolvedControlPointPositions[cpIdx] + offset
                    let axis = simd_normalize(MathHelper.parseVec3(op.axis?.value ?? "0 0 1"))
                    
                    let distInner = Float(op.distanceInner?.value ?? "500") ?? 500
                    let distOuter = Float(op.distanceOuter?.value ?? "650") ?? 650
                    let speedInner = Float(op.speedInner?.value ?? "2500") ?? 2500
                    let speedOuter = Float(op.speedOuter?.value ?? "0") ?? 0
                    
                    let toPart = p.position - center
                    let dist = simd_length(toPart)
                    let direct = simd_cross(toPart, axis)
                    let tangent = simd_normalize(direct)
                    
                    var force: Float = 0
                    if dist < distInner {
                        force = speedInner
                    } else if dist > distOuter {
                        force = speedOuter
                    } else {
                        let t = (dist - distInner) / (distOuter - distInner)
                        force = MathHelper.lerp(t: t, a: speedInner, b: speedOuter)
                    }
                    
                    p.velocity += tangent * force * dt * overrideSpeed
                    
                case "sizechange":
                    let start = Float(op.startvalue?.value ?? "1") ?? 1
                    let end = Float(op.endvalue?.value ?? "1") ?? 1
                    let startTime = Float(op.starttime?.value ?? "0") ?? 0
                    let endTime = Float(op.endtime?.value ?? "1") ?? 1
                    
                    let life = p.age / p.lifetime
                    let multiplier = MathHelper.fadeValue(life: life, startTime: startTime, endTime: endTime, startValue: start, endValue: end)
                    p.size = p.initial.size * multiplier
                    p.oscillateSize.base = p.size.x
                    
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
                            p.oscillatePosition.phase[i] = MathHelper.safeRandomFloat(min: pMin, max: pMax)
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
                    
                default:
                    break
                }
            }
            
            if !p.isDead {
                alive.append(p)
            }
            
            for (idx, childSys) in childrenSystems.enumerated() {
                if childSys.childType == "follow" {
                    var acc = p.childEmitAccumulators[idx] ?? 0
                    let rate = childSys.selfRate > 0 ? childSys.selfRate : 30.0
                    acc += rate * dt
                    while acc >= 1.0 {
                        acc -= 1.0
                        childSys.spawnAt(position: p.position)
                    }
                    p.childEmitAccumulators[idx] = acc
                } else if childSys.childType == "spawn" && p.isNew {
                    childSys.spawnAt(position: p.position, count: childSys.spawnCount)
                } else if childSys.childType == "death" && p.isDead {
                    childSys.spawnAt(position: p.position, count: childSys.spawnCount)
                }
            }
            
            p.isNew = false
        }
        
        particles = alive
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        if particles.isEmpty || instanceBuffer == nil { return }
        
        var instances = particles.map { p -> ParticleInstance in
            return ParticleInstance(
                position: p.position,
                color: SIMD4<Float>(p.color.x, p.color.y, p.color.z, p.alpha),
                size: p.size,
                rotation: p.rotation,
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
        
        let renderMatrix: matrix_float4x4
        if isWorldSpace {
            renderMatrix = matrix_identity_float4x4
        } else {
            renderMatrix = worldMatrix
        }
        
        var objUniforms = ObjectUniforms(
            modelMatrix: renderMatrix,
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
