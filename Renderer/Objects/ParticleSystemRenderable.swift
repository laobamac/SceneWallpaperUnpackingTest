//
//  ParticleSystemRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

import MetalKit
import simd

struct ParticleInstance {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var rotation: SIMD3<Float>
    var angularVelocity: SIMD3<Float>
    
    var color: SIMD3<Float>
    var alpha: Float
    var size: Float
    var frame: Float
    
    var lifetime: Float
    var age: Float
    var noisePos: SIMD3<Float>
    
    var initialColor: SIMD3<Float>
    var initialAlpha: Float
    var initialSize: Float
    var initialLifetime: Float
    
    var alive: Bool
}

struct ParticleVertex {
    var px, py, pz: Float
    var u, v: Float
    var rx, ry, rz: Float
    var size: Float
    var r, g, b, a: Float
    var frame: Float
    var vx, vy, vz: Float
}

class ParticleSystemRenderable: RenderableObject {
    private var particles: [ParticleInstance]
    private var emissionTimer: Float = 0
    private var maxParticles: Int
    
    private let emitters: [ParticleEmitterModel]
    private let initializers: [ParticleInitializerModel]
    private let operators: [ParticleOperatorModel]
    private let overrideData: ParticleInstanceOverrideModel?
    
    private let isTrail: Bool
    private let trailLength: Float
    private let trailSubdivision: Int
    
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private let device: MTLDevice
    
    private var spriteCols: Int = 1
    private var spriteRows: Int = 1
    private var projectionSize: CGSize = CGSize(width: 1920, height: 1080)
    
    init(device: MTLDevice, config: ParticleRoot, texture: MTLTexture, position: SIMD3<Float>, pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState?, screenSize: CGSize) {
        self.device = device
        self.maxParticles = config.maxcount ?? 1000
        self.projectionSize = screenSize
        
        let countMult = config.instanceoverride?.count?.value ?? 1.0
        let adjMax = Int(Float(self.maxParticles) * countMult)
        self.maxParticles = adjMax > 0 ? adjMax : 1000
        
        self.particles = Array(repeating: ParticleInstance(
            position: .zero, velocity: .zero, rotation: .zero, angularVelocity: .zero,
            color: .one, alpha: 1, size: 10, frame: 0, lifetime: 1, age: 0,
            noisePos: .zero, initialColor: .one, initialAlpha: 1, initialSize: 10, initialLifetime: 1, alive: false
        ), count: self.maxParticles)
        
        self.emitters = config.emitter ?? []
        self.initializers = config.initializer ?? []
        self.operators = config.operator ?? []
        self.overrideData = config.instanceoverride
        
        var isTrail = false
        var tLength: Float = 0.5
        var tSub: Int = 10
        
        if let renderers = config.renderer {
            for r in renderers {
                if r.name == "spritetrail" || r.name == "ropetrail" {
                    isTrail = true
                    tLength = r.length ?? 0.5
                    tSub = r.subdivision ?? 10
                }
            }
        }
        self.isTrail = isTrail
        self.trailLength = tLength
        self.trailSubdivision = max(1, tSub)
        
        super.init(position: position, rotation: .zero, size: SIMD2<Float>(100, 100), scale: .one, texture: texture, pipeline: pipeline, depthState: depthState)
        
        if texture.width > texture.height * 2 {
             self.spriteCols = texture.width / texture.height
        }
    }
    
    func update(dt: Float) {
        let fixedDt = min(dt, 0.1)
        
        let rateMult = overrideData?.rate?.value ?? 1.0
        
        for emitter in emitters {
            let baseRate = emitter.rate ?? 5.0
            let rate = baseRate * rateMult
            
            emissionTimer += rate * fixedDt
            let countToEmit = Int(emissionTimer)
            emissionTimer -= Float(countToEmit)
            
            if countToEmit > 0 {
                spawnParticles(count: countToEmit, config: emitter)
            }
        }
        
        for i in 0..<particles.count {
            if !particles[i].alive { continue }
            
            particles[i].age += fixedDt
            if particles[i].age >= particles[i].lifetime {
                particles[i].alive = false
                continue
            }
            
            for op in operators {
                applyOperator(op, to: &particles[i], dt: fixedDt)
            }
            
            particles[i].position += particles[i].velocity * fixedDt
            particles[i].rotation += particles[i].angularVelocity * fixedDt
        }
    }
    
    private func spawnParticles(count: Int, config: ParticleEmitterModel) {
        let screenH = Float(projectionSize.height)
        var spawned = 0
        
        let objectPos = self.localPosition
        let emitterOffset = MathHelper.parseVec3(config.origin ?? "0 0 0")
        
        let spawnBaseX = objectPos.x + emitterOffset.x
        let spawnBaseY = screenH - (objectPos.y + emitterOffset.y)
        let spawnBaseZ = objectPos.z + emitterOffset.z
        let spawnBase = SIMD3<Float>(spawnBaseX, spawnBaseY, spawnBaseZ)
        
        for i in 0..<particles.count {
            if spawned >= count { break }
            if particles[i].alive { continue }
            
            particles[i].alive = true
            particles[i].age = 0
            particles[i].noisePos = MathHelper.randomVec3(min: SIMD3<Float>(-10, -10, -10), max: SIMD3<Float>(10, 10, 10))
            
            if config.name == "sphererandom" {
                 var randDir = MathHelper.randomVec3(min: SIMD3<Float>(-1, -1, -1), max: SIMD3<Float>(1, 1, 1))
                 if simd_length(randDir) > 0.001 { randDir = simd_normalize(randDir) }
                 let distMin = MathHelper.parseVec3(config.distancemin ?? "0 0 0").x
                 let distMax = MathHelper.parseVec3(config.distancemax ?? "0 0 0").x
                 let radius = MathHelper.safeRandomFloat(min: distMin, max: distMax)
                 let offset = randDir * radius
                 
                 particles[i].position = spawnBase + SIMD3<Float>(offset.x, -offset.y, offset.z)
                 
                 let directions = MathHelper.parseVec3(config.directions ?? "1 1 1")
                 var dir = randDir
                 if simd_length(dir) > 0.001 { dir = simd_normalize(dir) }
                 let speed = MathHelper.safeRandomFloat(min: config.speedmin ?? 0, max: config.speedmax ?? 0)
                 particles[i].velocity = dir * directions * speed
                 particles[i].velocity.y = -particles[i].velocity.y
                 
            } else {
                let minBox = MathHelper.parseVec3(config.distancemin ?? "0 0 0")
                let maxBox = MathHelper.parseVec3(config.distancemax ?? "0 0 0")
                let randomOffset = MathHelper.randomVec3(min: minBox, max: maxBox)
                
                particles[i].position = spawnBase + SIMD3<Float>(randomOffset.x, -randomOffset.y, randomOffset.z)
                
                let directions = MathHelper.parseVec3(config.directions ?? "1 1 1")
                var dir = simd_normalize(randomOffset)
                if simd_length(randomOffset) < 0.001 { dir = SIMD3<Float>(0, 1, 0) }
                let speed = MathHelper.safeRandomFloat(min: config.speedmin ?? 0, max: config.speedmax ?? 0)
                particles[i].velocity = dir * directions * speed
                particles[i].velocity.y = -particles[i].velocity.y
            }
            
            particles[i].color = overrideData?.colorn?.value ?? SIMD3<Float>(1,1,1)
            particles[i].alpha = overrideData?.alpha?.value ?? 1.0
            particles[i].size = (overrideData?.size?.value ?? 1.0) * 20.0
            particles[i].lifetime = overrideData?.lifetime?.value ?? 1.0
            particles[i].velocity *= (overrideData?.speed?.value ?? 1.0)
            
            particles[i].rotation = .zero
            particles[i].angularVelocity = .zero
            
            for initOp in initializers {
                applyInitializer(initOp, to: &particles[i])
            }
            
            if let oc = overrideData?.color { particles[i].color = oc.value }
            
            particles[i].initialColor = particles[i].color
            particles[i].initialAlpha = particles[i].alpha
            particles[i].initialSize = particles[i].size
            particles[i].initialLifetime = particles[i].lifetime
            
            spawned += 1
        }
    }
    
    private func applyInitializer(_ op: ParticleInitializerModel, to p: inout ParticleInstance) {
        switch op {
        case .colorRandom(let minStr, let maxStr):
            let min = MathHelper.parseVec3(minStr)
            let max = MathHelper.parseVec3(maxStr)
            p.color = MathHelper.randomVec3(min: min, max: max) * p.color
        case .sizeRandom(let min, let max, let exp):
            let t = MathHelper.safeRandomFloat(min: 0, max: 1)
            let val = min + pow(t, exp) * (max - min)
            p.size = val * (overrideData?.size?.value ?? 1.0)
        case .alphaRandom(let min, let max):
            p.alpha = MathHelper.safeRandomFloat(min: min, max: max) * (overrideData?.alpha?.value ?? 1.0)
        case .lifetimeRandom(let min, let max):
            p.lifetime = MathHelper.safeRandomFloat(min: min, max: max) * (overrideData?.lifetime?.value ?? 1.0)
        case .velocityRandom(let minStr, let maxStr):
            let min = MathHelper.parseVec3(minStr)
            let max = MathHelper.parseVec3(maxStr)
            var rnd = MathHelper.randomVec3(min: min, max: max)
            rnd.y = -rnd.y
            p.velocity += rnd * (overrideData?.speed?.value ?? 1.0)
        case .rotationRandom(let minStr, let maxStr):
            let min = MathHelper.parseVec3(minStr)
            let max = MathHelper.parseVec3(maxStr)
            p.rotation = MathHelper.randomVec3(min: min, max: max)
        case .angularVelocityRandom(let minStr, let maxStr):
            let min = MathHelper.parseVec3(minStr)
            let max = MathHelper.parseVec3(maxStr)
            p.angularVelocity = MathHelper.randomVec3(min: min, max: max)
        case .turbulentVelocityRandom(let min, let max, let scale, let offset):
            let speed = MathHelper.safeRandomFloat(min: min, max: max)
            p.noisePos = MathHelper.randomVec3(min: .zero, max: SIMD3<Float>(10,10,10))
            let offPos = p.noisePos + SIMD3<Float>(offset, offset, offset)
            var dir = SimplexNoise.curlNoise(offPos)
            if simd_length(dir) > 0.001 { dir = simd_normalize(dir) }
            dir *= scale
            var turbVel = dir * speed * (overrideData?.speed?.value ?? 1.0)
            turbVel.y = -turbVel.y
            p.velocity += turbVel
        default: break
        }
    }
    
    private func applyOperator(_ op: ParticleOperatorModel, to p: inout ParticleInstance, dt: Float) {
        let lifePos = p.lifetime > 0 ? (p.age / p.lifetime) : 1.0
        
        switch op {
        case .movement(let drag, let gravStr):
            var g = MathHelper.parseVec3(gravStr)
            g.y = -g.y
            p.velocity += g * dt
            p.velocity *= (1.0 - drag * dt)
        case .alphaFade(let `in`, let out):
            var a = p.initialAlpha
            if lifePos <= `in` {
                a *= MathHelper.fadeValue(life: lifePos, startTime: 0, endTime: `in`, startValue: 0, endValue: 1)
            } else if lifePos >= (1.0 - out) {
                a *= (1.0 - MathHelper.fadeValue(life: lifePos, startTime: 1.0 - out, endTime: 1.0, startValue: 0, endValue: 1))
            }
            p.alpha = a
        case .rotation(let drag, let forceStr):
            let f = MathHelper.parseVec3(forceStr)
            p.angularVelocity += f * dt
            p.angularVelocity *= (1.0 - drag * dt)
        case .sizeChange(let st, let et, let sv, let ev):
             let mul = MathHelper.fadeValue(life: lifePos, startTime: st, endTime: et, startValue: sv, endValue: ev)
             p.size = p.initialSize * mul
        case .colorChange(let st, let et, let sv, let ev):
            let sVec = MathHelper.parseVec3(sv)
            let eVec = MathHelper.parseVec3(ev)
            let c = MathHelper.lerpVec3(t: (MathHelper.fadeValue(life: lifePos, startTime: st, endTime: et, startValue: 0, endValue: 1)), a: sVec, b: eVec)
            p.color = p.initialColor * c
        case .turbulence(let scale, let minS, let maxS, let timeScale):
            p.noisePos += p.velocity * 0.01
            var samplePos = p.noisePos
            samplePos.x += timeScale * p.age
            let curl = SimplexNoise.curlNoise(samplePos * scale)
            var acc = curl
            if simd_length(acc) > 0.001 { acc = simd_normalize(acc) }
            let sp = MathHelper.safeRandomFloat(min: minS, max: maxS)
            p.velocity += acc * sp * dt
        case .vortex(let axStr, let offStr, let di, let do_, let si, let so):
            let axis = simd_normalize(MathHelper.parseVec3(axStr))
            let center = MathHelper.parseVec3(offStr)
            let toPart = p.position - center
            let dist = simd_length(toPart)
            var direct = -simd_cross(axis, toPart)
            if simd_length(direct) > 0.001 { direct = simd_normalize(direct) }
            var speed: Float = 0
            if dist < di { speed = si }
            else if dist > do_ { speed = so }
            else {
                let t = (dist - di) / (do_ - di)
                speed = MathHelper.lerp(t: t, a: si, b: so)
            }
            p.velocity += direct * speed * dt
        case .attract(let oriStr, let scale, let th):
            let center = MathHelper.parseVec3(oriStr)
            let toCenter = center - p.position
            let dist = simd_length(toCenter)
            if dist > 0.001 && dist < th {
                let dir = toCenter / dist
                p.velocity += dir * scale * dt
            }
        default: break
        }
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        var vertices: [ParticleVertex] = []
        var indices: [UInt32] = []
        
        for p in particles {
            if !p.alive { continue }
            
            if isTrail {
                let segments = trailSubdivision
                let vel2 = SIMD2<Float>(p.velocity.x, p.velocity.y)
                let speed = simd_length(vel2)
                let trailLen = speed > 0.001 ? max(0, min(speed * trailLength, 50.0)) * (p.size / 20.0) : 0
                
                let perp = speed > 0.001 ? SIMD2<Float>(vel2.y, -vel2.x) / speed : SIMD2<Float>(1, 0)
                let widthDir = SIMD3<Float>(speed > 0.001 ? simd_normalize(vel2) : SIMD2<Float>(0,1), 0)
                let trailDir = SIMD3<Float>(perp, 0)
                
                let baseIndex = UInt32(vertices.count)
                
                for i in 0...segments {
                    let t = Float(i) / Float(segments)
                    let center = p.position - widthDir * (trailLen * t) + localPosition
                    let width = trailLen
                    let leftPos = center - trailDir * width
                    let rightPos = center + trailDir * width
                    
                    let col = SIMD4<Float>(p.color, p.alpha * (1.0 - t * 0.5))
                    
                    vertices.append(ParticleVertex(px: leftPos.x, py: leftPos.y, pz: leftPos.z, u: 0, v: t, rx: 0, ry: 0, rz: 0, size: 1, r: col.x, g: col.y, b: col.z, a: col.w, frame: 0, vx: 0, vy: 0, vz: 0))
                    vertices.append(ParticleVertex(px: rightPos.x, py: rightPos.y, pz: rightPos.z, u: 1, v: t, rx: 0, ry: 0, rz: 0, size: 1, r: col.x, g: col.y, b: col.z, a: col.w, frame: 0, vx: 0, vy: 0, vz: 0))
                    
                    if i > 0 {
                        let b = baseIndex + UInt32((i-1) * 2)
                        indices.append(b); indices.append(b+1); indices.append(b+3)
                        indices.append(b); indices.append(b+3); indices.append(b+2)
                    }
                }
            } else {
                let halfSize = p.size * 0.5
                let pos = p.position
                let baseIndex = UInt32(vertices.count)
                let col = SIMD4<Float>(p.color, p.alpha)
                
                vertices.append(ParticleVertex(px: pos.x, py: pos.y, pz: pos.z, u: 0, v: 1, rx: p.rotation.x, ry: p.rotation.y, rz: p.rotation.z, size: halfSize, r: col.x, g: col.y, b: col.z, a: col.w, frame: p.frame, vx: 0, vy: 0, vz: 0))
                vertices.append(ParticleVertex(px: pos.x, py: pos.y, pz: pos.z, u: 1, v: 1, rx: p.rotation.x, ry: p.rotation.y, rz: p.rotation.z, size: halfSize, r: col.x, g: col.y, b: col.z, a: col.w, frame: p.frame, vx: 0, vy: 0, vz: 0))
                vertices.append(ParticleVertex(px: pos.x, py: pos.y, pz: pos.z, u: 1, v: 0, rx: p.rotation.x, ry: p.rotation.y, rz: p.rotation.z, size: halfSize, r: col.x, g: col.y, b: col.z, a: col.w, frame: p.frame, vx: 0, vy: 0, vz: 0))
                vertices.append(ParticleVertex(px: pos.x, py: pos.y, pz: pos.z, u: 0, v: 0, rx: p.rotation.x, ry: p.rotation.y, rz: p.rotation.z, size: halfSize, r: col.x, g: col.y, b: col.z, a: col.w, frame: p.frame, vx: 0, vy: 0, vz: 0))
                
                indices.append(baseIndex); indices.append(baseIndex+1); indices.append(baseIndex+2)
                indices.append(baseIndex); indices.append(baseIndex+2); indices.append(baseIndex+3)
            }
        }
        
        if vertices.isEmpty { return }
        
        let vSize = vertices.count * MemoryLayout<ParticleVertex>.stride
        if vertexBuffer == nil || vertexBuffer!.length < vSize {
            vertexBuffer = device.makeBuffer(length: vSize * 2, options: .storageModeShared)
        }
        let iSize = indices.count * MemoryLayout<UInt32>.stride
        if indexBuffer == nil || indexBuffer!.length < iSize {
            indexBuffer = device.makeBuffer(length: iSize * 2, options: .storageModeShared)
        }
        
        guard let vb = vertexBuffer, let ib = indexBuffer else { return }
        vb.contents().copyMemory(from: vertices, byteCount: vSize)
        ib.contents().copyMemory(from: indices, byteCount: iSize)
        
        encoder.setRenderPipelineState(pipeline)
        
        let matrix = Matrix4x4.translation(x: 0, y: 0, z: 0)
        var objUniforms = ObjectUniforms(modelMatrix: matrix, alpha: 1.0, color: SIMD4<Float>(1,1,1,1), animInfo: .zero)
        
        encoder.setVertexBuffer(vb, offset: 0, index: 0)
        encoder.setVertexBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        encoder.setFragmentTexture(texture, index: 0)
        
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indices.count, indexType: .uint32, indexBuffer: ib, indexBufferOffset: 0)
    }
}
