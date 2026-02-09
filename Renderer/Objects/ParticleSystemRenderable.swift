//
//  ParticleSystemRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/2/8.
//

import MetalKit
import simd

class ParticleSystemRenderable: RenderableObject {
    private struct Particle {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var color: SIMD4<Float>
        var size: SIMD2<Float>
        var rotation: Float
        var angularVelocity: Float
        var age: Float
        var lifetime: Float
        var initialSize: SIMD2<Float>
        var initialColor: SIMD4<Float>
        var seed: SIMD3<Float>
        var childEmitAccumulators: [Int: Float]
    }
    
    private let device: MTLDevice
    private let config: ParticleSystemConfig
    private let animatedTexture: AnimatedTexture
    private var particles: [Particle]
    private var instanceBuffer: MTLBuffer?
    private var emitAccumulator: Float = 0
    private let maxCount: Int
    
    private var overrideRate: Float = 1.0
    private var overrideCount: Float = 1.0
    private var overrideColor: SIMD3<Float>?
    private var overrideAlpha: Float = 1.0
    
    private var controlPoints: [SIMD3<Float>] = []
    
    private var systemPosition: SIMD3<Float>
    private var systemRotation: SIMD3<Float>
    private var systemScale: SIMD3<Float>
    
    var childrenSystems: [ParticleSystemRenderable] = []
    var isChildSystem: Bool = false
    var selfRate: Float = 0
    
    init?(device: MTLDevice, config: ParticleSystemConfig, texture: AnimatedTexture, position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>, pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState?, overrides: InstanceOverride?) {
        self.device = device
        self.config = config
        self.animatedTexture = texture
        self.maxCount = config.maxcount ?? 100
        self.particles = []
        self.particles.reserveCapacity(self.maxCount)
        
        self.systemPosition = position
        self.systemRotation = rotation
        self.systemScale = scale
        
        super.init(position: position, rotation: rotation, size: size, scale: scale, texture: texture.textures[0], pipeline: pipeline, depthState: depthState)
        
        if let o = overrides {
            if let r = o.rate { self.overrideRate = r }
            if let c = o.count { self.overrideCount = c }
            if let colStr = o.colorn {
                self.overrideColor = MathHelper.parseVec3(colStr)
            }
            if let a = o.alpha { self.overrideAlpha = a }
        }
        
        if let cps = config.controlpoint {
            for cp in cps {
                let offset = MathHelper.parseVec3(cp.offset ?? "0 0 0")
                self.controlPoints.append(offset)
            }
        } else {
            for _ in 0..<8 { self.controlPoints.append(SIMD3<Float>(0,0,0)) }
        }
        
        if let emitters = config.emitter {
            for e in emitters {
                self.selfRate += (e.rate ?? 0)
            }
        }
        
        let capacity = Int(Float(maxCount) * overrideCount) + 1
        if capacity > 0 {
            self.instanceBuffer = device.makeBuffer(length: capacity * MemoryLayout<ParticleInstance>.stride, options: .storageModeShared)
        }
        
        if let st = config.starttime, st > 0, !isChildSystem {
            let step: Float = 0.016666
            var t: Float = 0
            while t < st {
                update(dt: step, time: t)
                t += step
            }
        }
    }
    
    func addChild(_ child: ParticleSystemRenderable) {
        child.isChildSystem = true
        self.childrenSystems.append(child)
    }
    
    func update(dt: Float, time: Float) {
        if !isChildSystem {
            spawnParticles(dt: dt)
        }
        
        updateParticles(dt: dt, time: time)
        
        for child in childrenSystems {
            child.update(dt: dt, time: time)
        }
    }
    
    func spawnAt(position: SIMD3<Float>, velocity: SIMD3<Float> = SIMD3<Float>(0,0,0)) {
        guard let emitters = config.emitter, let firstEmitter = emitters.first else { return }
        createParticle(emitter: firstEmitter, overrideOrigin: position)
    }
    
    private func spawnParticles(dt: Float) {
        guard let emitters = config.emitter else { return }
        let effectiveMax = Int(Float(maxCount) * overrideCount)
        
        for emitter in emitters {
            let rate = (emitter.rate ?? 0) * overrideRate
            if rate <= 0 { continue }
            
            emitAccumulator += rate * dt
            while emitAccumulator >= 1.0 {
                emitAccumulator -= 1.0
                if particles.count < effectiveMax {
                    createParticle(emitter: emitter)
                }
            }
        }
    }
    
    private func createParticle(emitter: ParticleEmitter, overrideOrigin: SIMD3<Float>? = nil) {
        let limit = Int(Float(maxCount) * overrideCount)
        if particles.count >= limit { return }
        
        var p = Particle(
            position: SIMD3<Float>(0,0,0),
            velocity: SIMD3<Float>(0,0,0),
            color: SIMD4<Float>(1,1,1,1),
            size: SIMD2<Float>(0,0),
            rotation: 0,
            angularVelocity: 0,
            age: 0,
            lifetime: 1,
            initialSize: SIMD2<Float>(0,0),
            initialColor: SIMD4<Float>(1,1,1,1),
            seed: SIMD3<Float>(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1)),
            childEmitAccumulators: [:]
        )
        
        let originOffset = MathHelper.parseVec3(emitter.origin ?? "0 0 0")
        var randomOffset = SIMD3<Float>(0,0,0)
        
        if emitter.name == "sphererandom" {
            let distMin = emitter.distancemin ?? 0
            let distMax = emitter.distancemax ?? 0
            let dist = MathHelper.safeRandomFloat(min: distMin, max: distMax)
            
            let u = Float.random(in: -1...1)
            let theta = Float.random(in: 0...(2 * .pi))
            let x = sqrt(1 - u * u) * cos(theta)
            let y = sqrt(1 - u * u) * sin(theta)
            let z = u
            let dir = SIMD3<Float>(x, y, z)
            
            randomOffset = originOffset + dir * dist
        } else {
            randomOffset = originOffset
        }
        
        if let pos = overrideOrigin {
            p.position = pos + randomOffset * 0.05
        } else {
            p.position = randomOffset
        }
        
        if let initializers = config.initializer {
            for initOp in initializers {
                applyInitializer(op: initOp, p: &p)
            }
        }
        
        if let oc = overrideColor {
            p.color = SIMD4<Float>(p.color.x * oc.x, p.color.y * oc.y, p.color.z * oc.z, p.color.w)
        }
        
        if isChildSystem {
            p.color.w *= 0.3
            p.size *= 0.15
        } else {
            p.size *= 0.7
        }
        
        p.color.w *= overrideAlpha
        
        let scaleFactor = (systemScale.x + systemScale.y) * 0.5
        p.size *= scaleFactor
        
        p.initialSize = p.size
        p.initialColor = p.color
        
        particles.append(p)
    }
    
    private func applyInitializer(op: ParticleInitializer, p: inout Particle) {
        switch op.name {
        case "lifetimerandom":
            let minV = Float(op.min?.value ?? "0") ?? 0
            let maxV = Float(op.max?.value ?? "0") ?? 0
            var val = MathHelper.safeRandomFloat(min: minV, max: maxV)
            if let exp = op.exponent { val = pow(val, exp) }
            p.lifetime = val
        case "sizerandom":
            let minV = Float(op.min?.value ?? "0") ?? 0
            let maxV = Float(op.max?.value ?? "0") ?? 0
            var val = MathHelper.safeRandomFloat(min: minV, max: maxV)
            if let exp = op.exponent { val = pow(val, exp) }
            p.size = SIMD2<Float>(val, val)
        case "velocityrandom":
            let minV = MathHelper.parseVec3(op.min?.value ?? "0 0 0")
            let maxV = MathHelper.parseVec3(op.max?.value ?? "0 0 0")
            p.velocity = MathHelper.randomVec3(min: minV, max: maxV)
        case "colorrandom":
            let minV = MathHelper.parseVec4(op.min?.value ?? "0 0 0 0")
            let maxV = MathHelper.parseVec4(op.max?.value ?? "0 0 0 0")
            let r = MathHelper.safeRandomFloat(min: minV.x, max: maxV.x) / 255.0
            let g = MathHelper.safeRandomFloat(min: minV.y, max: maxV.y) / 255.0
            let b = MathHelper.safeRandomFloat(min: minV.z, max: maxV.z) / 255.0
            let a = MathHelper.safeRandomFloat(min: minV.w, max: maxV.w) / 255.0
            p.color = SIMD4<Float>(r, g, b, a)
        case "rotationrandom":
            let minV = MathHelper.parseVec3(op.min?.value ?? "0 0 0").z
            let maxV = MathHelper.parseVec3(op.max?.value ?? "0 0 0").z
            p.rotation = MathHelper.safeRandomFloat(min: minV, max: maxV) * .pi / 180.0
        case "alpharandom":
            let minV = Float(op.min?.value ?? "0") ?? 0
            let maxV = Float(op.max?.value ?? "0") ?? 0
            p.color.w = MathHelper.safeRandomFloat(min: minV, max: maxV)
        case "angularvelocityrandom":
            let minV = MathHelper.parseVec3(op.min?.value ?? "0 0 0").z
            let maxV = MathHelper.parseVec3(op.max?.value ?? "0 0 0").z
            p.angularVelocity = MathHelper.safeRandomFloat(min: minV, max: maxV)
        case "turbulentvelocityrandom":
             let scale = op.scale ?? 1.0
             let speedMin = op.speedmin ?? 0
             let speedMax = op.speedmax ?? 0
             let offset = op.offset ?? 0
             let speed = MathHelper.safeRandomFloat(min: speedMin, max: speedMax)
             let time = Float(0)
             let noise = simd_float3(
                 sin(p.position.x * scale + time * speed + offset),
                 cos(p.position.y * scale + time * speed + offset),
                 sin(p.position.z * scale + time * speed + offset)
             )
             p.velocity += noise
        default:
            break
        }
    }
    
    private func rotatePoint(_ point: SIMD3<Float>, angles: SIMD3<Float>) -> SIMD3<Float> {
        var p = point
        let radX = angles.x * .pi / 180.0
        let radY = angles.y * .pi / 180.0
        let radZ = angles.z * .pi / 180.0
        
        if angles.x != 0 {
            let cx = cos(radX), sx = sin(radX)
            let y = p.y * cx - p.z * sx
            let z = p.y * sx + p.z * cx
            p.y = y; p.z = z
        }
        if angles.y != 0 {
            let cy = cos(radY), sy = sin(radY)
            let x = p.x * cy + p.z * sy
            let z = -p.x * sy + p.z * cy
            p.x = x; p.z = z
        }
        if angles.z != 0 {
            let cz = cos(radZ), sz = sin(radZ)
            let x = p.x * cz - p.y * sz
            let y = p.x * sz + p.y * cz
            p.x = x; p.y = y
        }
        return p
    }
    
    private func updateParticles(dt: Float, time: Float) {
        var alive: [Particle] = []
        alive.reserveCapacity(particles.count)
        
        let operators = config.operatorList ?? []
        
        var followChildren: [(index: Int, rate: Float, system: ParticleSystemRenderable)] = []
        if let childrenConfigs = config.children {
            for (idx, childConfig) in childrenConfigs.enumerated() {
                if childConfig.type == "eventfollow" && idx < childrenSystems.count {
                    let childSys = childrenSystems[idx]
                    var rate = childSys.selfRate > 0 ? childSys.selfRate : 30.0
                    if rate > 40.0 { rate = 40.0 }
                    followChildren.append((idx, rate, childSys))
                }
            }
        }
        
        let myWorldPos = self.systemPosition
        let myRotation = self.systemRotation
        let myScale = self.systemScale
        
        for var p in particles {
            p.age += dt
            if p.age >= p.lifetime { continue }
            
            for childInfo in followChildren {
                var acc = p.childEmitAccumulators[childInfo.index] ?? 0
                acc += childInfo.rate * dt
                
                let localPos = p.position
                let rotatedPos = rotatePoint(localPos, angles: myRotation)
                let scaledPos = rotatedPos * myScale
                let worldPos = myWorldPos + scaledPos
                
                while acc >= 1.0 {
                    acc -= 1.0
                    childInfo.system.spawnAt(position: worldPos)
                }
                p.childEmitAccumulators[childInfo.index] = acc
            }
            
            for op in operators {
                switch op.name {
                case "movement":
                    let g = MathHelper.parseVec3(op.gravity ?? "0 0 0")
                    let drag = op.drag ?? 0
                    p.velocity += g * dt
                    if drag > 0 {
                        p.velocity *= (1.0 - drag * dt)
                    }
                    p.position += p.velocity * dt
                    
                case "alphafade":
                    let fin = op.fadeintime ?? 0
                    let fout = op.fadeouttime ?? 0
                    var alpha = p.initialColor.w
                    
                    let effectiveFin = fin < 0.001 ? 0.2 : fin
                    if p.age < effectiveFin {
                        alpha *= (p.age / effectiveFin)
                    }
                    
                    let timeRemaining = p.lifetime - p.age
                    let effectiveFout = fout < 0.001 ? 0.2 : fout
                    if timeRemaining < effectiveFout {
                        alpha *= (timeRemaining / effectiveFout)
                    }
                    p.color.w = alpha
                    
                case "oscillatealpha":
                    let fMin = op.frequencymin ?? 1
                    let fMax = op.frequencymax ?? 1
                    let sMin = op.scalemin ?? 0
                    let freq = fMin + (fMax - fMin) * p.seed.x
                    let val = sin(p.age * freq) * 0.5 + 0.5
                    let scale = sMin + (1.0 - sMin) * val
                    p.color.w *= scale
                    
                case "oscillateposition":
                    let fMin = op.frequencymin ?? 1
                    let fMax = op.frequencymax ?? 1
                    let sMin = op.scalemin ?? 0
                    let sMax = op.scalemax ?? 0
                    let freq = fMin + (fMax - fMin) * p.seed.y
                    let amp = sMin + (sMax - sMin) * p.seed.z
                    let velChange = cos(p.age * freq) * amp * 2.0
                    p.velocity.x += velChange * dt
                    p.velocity.y += velChange * dt * 0.5
                    
                case "oscillatesize":
                    let fMin = op.frequencymin ?? 1
                    let fMax = op.frequencymax ?? 1
                    let sMin = op.scalemin ?? 1
                    let sMax = op.scalemax ?? 1
                    let freq = fMin + (fMax - fMin) * p.seed.x
                    let amp = sMin + (sMax - sMin) * p.seed.y
                    let val = sin(p.age * freq) * 0.5 + 0.5
                    let scale = sMin + (sMax - sMin) * val
                    p.size = p.initialSize * scale
                    
                case "turbulence":
                    let mask = MathHelper.parseVec3(op.mask ?? "1 1 1")
                    let scale = op.scale ?? 1
                    let sMin = op.speedmin ?? 0
                    let sMax = op.speedmax ?? 0
                    let speed = MathHelper.safeRandomFloat(min: sMin, max: sMax)
                    let t = time * speed * 0.01
                    let nx = sin(p.position.x * scale + t) * cos(p.position.y * scale * 0.8)
                    let ny = cos(p.position.x * scale * 1.2 + t) * sin(p.position.z * scale)
                    let nz = sin(p.position.x * scale * 0.5 + t)
                    let noise = SIMD3<Float>(nx, ny, nz)
                    p.position += noise * mask * dt * 10.0
                    
                case "controlpointattract":
                    let cpIdx = op.controlpoint ?? 0
                    if cpIdx >= 0 && cpIdx < controlPoints.count {
                        let target = controlPoints[cpIdx]
                        let delta = target - p.position
                        let distSq = dot(delta, delta)
                        let dist = sqrt(distSq)
                        let threshold = op.threshold ?? 100
                        
                        if dist < threshold && dist > 0.001 {
                            let dir = delta / dist
                            let scale = op.scale ?? 0
                            let factor = pow(1.0 - (dist / threshold), 2.0)
                            let force = scale * factor
                            p.velocity += dir * force * dt
                        }
                    }
                    
                case "angularmovement":
                    let force = MathHelper.parseVec3(op.force ?? "0 0 0")
                    p.angularVelocity += force.z * dt
                    p.rotation += p.angularVelocity * dt
                    
                case "sizechange":
                    let start = op.startvalue ?? 1
                    let end = op.endvalue ?? 1
                    let nAge = p.age / p.lifetime
                    let s = start + (end - start) * nAge
                    p.size = p.initialSize * s
                    
                default:
                    break
                }
            }
            alive.append(p)
        }
        particles = alive
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        if particles.isEmpty || instanceBuffer == nil { return }
        
        var instances = particles.map { p -> ParticleInstance in
            return ParticleInstance(
                position: p.position,
                color: p.color,
                size: p.size,
                rotation: p.rotation,
                padding: 0
            )
        }
        
        let count = instances.count
        instanceBuffer?.contents().copyMemory(from: &instances, byteCount: count * MemoryLayout<ParticleInstance>.stride)
        
        encoder.setRenderPipelineState(pipeline)
        
        var texIndex = 0
        if animatedTexture.textures.count > 1 {
            let totalDuration = animatedTexture.duration
            if totalDuration > 0 {
                let t = fmod(Date().timeIntervalSince1970, totalDuration)
                var accum: Double = 0
                for (i, delay) in animatedTexture.delays.enumerated() {
                    accum += delay
                    if t <= accum {
                        texIndex = i
                        break
                    }
                }
            }
        }
        
        encoder.setFragmentTexture(animatedTexture.textures[texIndex], index: 0)
        
        if let ds = depthState {
            encoder.setDepthStencilState(ds)
        }
        
        var objUniforms = ObjectUniforms(modelMatrix: worldMatrix, alpha: 1.0, color: SIMD4<Float>(1,1,1,1), padding: .zero)
        encoder.setVertexBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 3)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        
        for child in childrenSystems {
            child.draw(encoder: encoder)
        }
    }
}
