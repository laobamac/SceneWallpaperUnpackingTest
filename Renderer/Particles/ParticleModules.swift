//
//  ParticleModules.swift
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

import simd
import Foundation

class ParticleModules {
    
    static func colorRandom(min: SIMD3<Float>, max: SIMD3<Float>) -> ParticleInitOp {
        return { p, _ in
            let r = ParticleMath.randomFloat(min: min.x, max: max.x) / 255.0
            let g = ParticleMath.randomFloat(min: min.y, max: max.y) / 255.0
            let b = ParticleMath.randomFloat(min: min.z, max: max.z) / 255.0
            p.color = SIMD3<Float>(r, g, b)
            p.initValue.color = p.color
        }
    }
    
    static func lifetimeRandom(min: Float, max: Float) -> ParticleInitOp {
        return { p, _ in
            let l = ParticleMath.randomFloat(min: min, max: max)
            p.lifetime = l
            p.initValue.lifetime = l
        }
    }
    
    static func sizeRandom(min: Float, max: Float) -> ParticleInitOp {
        return { p, _ in
            let s = ParticleMath.randomFloat(min: min, max: max)
            p.size = s
            p.initValue.size = s
        }
    }
    
    static func alphaRandom(min: Float, max: Float) -> ParticleInitOp {
        return { p, _ in
            let a = ParticleMath.randomFloat(min: min, max: max)
            p.alpha = a
            p.initValue.alpha = a
        }
    }
    
    static func velocityRandom(min: SIMD3<Float>, max: SIMD3<Float>) -> ParticleInitOp {
        return { p, _ in
            let vx = ParticleMath.randomFloat(min: min.x, max: max.x)
            let vy = ParticleMath.randomFloat(min: min.y, max: max.y)
            let vz = ParticleMath.randomFloat(min: min.z, max: max.z)
            p.velocity += SIMD3<Float>(vx, vy, vz)
        }
    }
    
    static func rotationRandom(min: SIMD3<Float>, max: SIMD3<Float>) -> ParticleInitOp {
        return { p, _ in
            let rx = ParticleMath.randomFloat(min: min.x, max: max.x)
            let ry = ParticleMath.randomFloat(min: min.y, max: max.y)
            let rz = ParticleMath.randomFloat(min: min.z, max: max.z)
            p.rotation += SIMD3<Float>(rx, ry, rz)
        }
    }
    
    static func angularVelocityRandom(min: SIMD3<Float>, max: SIMD3<Float>) -> ParticleInitOp {
        return { p, _ in
            let ax = ParticleMath.randomFloat(min: min.x, max: max.x)
            let ay = ParticleMath.randomFloat(min: min.y, max: max.y)
            let az = ParticleMath.randomFloat(min: min.z, max: max.z)
            p.angularVelocity += SIMD3<Float>(ax, ay, az)
        }
    }
    
    static func turbulentVelocityRandom(scale: Float, timeScale: Double, offset: Float, speedMin: Float, speedMax: Float, phaseMin: Float, phaseMax: Float, forward: SIMD3<Float>, right: SIMD3<Float>) -> ParticleInitOp {
        var pos = SIMD3<Double>(0,0,0)
        return { p, _ in
            let speed = ParticleMath.randomFloat(min: speedMin, max: speedMax)
            var duration = 10.0
            pos.x += Double(speed)
            
            var result = SIMD3<Float>(0,0,0)
            while duration > 0.01 {
                result = normalize(ParticleMath.curlNoise(pos: pos))
                pos += SIMD3<Double>(Double(result.x), Double(result.y), Double(result.z)) * 0.005 / timeScale
                duration -= 0.01
            }
            
            let c = dot(result, forward) / (length(result) * length(forward))
            let a = acos(c) / Float.pi
            let s = scale / 2.0
            
            if a > s {
                let axis = normalize(cross(result, forward))
                let q = simd_quatf(angle: (a - a * s) * Float.pi, axis: axis)
                result = q.act(result)
            }
            
            let offsetQ = simd_quatf(angle: offset, axis: right)
            result = offsetQ.act(result) * speed
            p.velocity += result
        }
    }
    
    static func overrideInit(over: ParticleInstanceOverride) -> ParticleInitOp {
        return { p, _ in
            p.lifetime *= over.lifetime
            p.initValue.lifetime = p.lifetime
            
            p.alpha *= over.alpha
            p.initValue.alpha = p.alpha
            
            p.size *= over.size
            p.initValue.size = p.size
            
            p.velocity *= over.speed
            
            if over.overColor {
                p.color = over.color / 255.0
                p.initValue.color = p.color
            } else if over.overColorN {
                p.color *= over.colorN
                p.initValue.color = p.color
            }
        }
    }
    
    static func movement(drag: Float, gravity: SIMD3<Float>) -> ParticleOperatorOp {
        return { info in
            let buffer = info.particles
            for i in 0..<buffer.count {
                var velocity = buffer[i].velocity
                let dragForce = -velocity * drag
                let acc = dragForce + gravity
                buffer[i].velocity += acc * Float(info.timePass)
                buffer[i].position += buffer[i].velocity * Float(info.timePass)
            }
        }
    }
    
    static func angularMovement(drag: Float, force: SIMD3<Float>) -> ParticleOperatorOp {
        return { info in
            let buffer = info.particles
            for i in 0..<buffer.count {
                let angular = buffer[i].angularVelocity
                let dragForce = -angular * drag
                let acc = dragForce + force
                buffer[i].angularVelocity += acc * Float(info.timePass)
                buffer[i].rotation += buffer[i].angularVelocity * Float(info.timePass)
            }
        }
    }
    
    static func sizeChange(start: Float, end: Float, valStart: Float, valEnd: Float, overSize: Float) -> ParticleOperatorOp {
        return { info in
            let buffer = info.particles
            for i in 0..<buffer.count {
                let life = buffer[i].initValue.lifetime > 0 ? (1.0 - buffer[i].lifetime / buffer[i].initValue.lifetime) : 1.0
                let val = ParticleModules.fadeValueChange(life: life, start: start, end: end, valStart: valStart, valEnd: valEnd)
                buffer[i].size = buffer[i].initValue.size * val * overSize
            }
        }
    }
    
    static func alphaFade(fadeIn: Float, fadeOut: Float) -> ParticleOperatorOp {
        return { info in
            let buffer = info.particles
            for i in 0..<buffer.count {
                let life = buffer[i].initValue.lifetime > 0 ? (1.0 - buffer[i].lifetime / buffer[i].initValue.lifetime) : 1.0
                if life <= fadeIn {
                    buffer[i].alpha = buffer[i].initValue.alpha * ParticleModules.fadeValueChange(life: life, start: 0, end: fadeIn, valStart: 0, valEnd: 1)
                } else if life > fadeOut {
                    buffer[i].alpha = buffer[i].initValue.alpha * (1.0 - ParticleModules.fadeValueChange(life: life, start: fadeOut, end: 1, valStart: 0, valEnd: 1))
                }
            }
        }
    }
    
    static func alphaChange(start: Float, end: Float, valStart: Float, valEnd: Float) -> ParticleOperatorOp {
        return { info in
            let buffer = info.particles
            for i in 0..<buffer.count {
                let life = buffer[i].initValue.lifetime > 0 ? (1.0 - buffer[i].lifetime / buffer[i].initValue.lifetime) : 1.0
                let val = ParticleModules.fadeValueChange(life: life, start: start, end: end, valStart: valStart, valEnd: valEnd)
                buffer[i].alpha = buffer[i].initValue.alpha * val
            }
        }
    }
    
    static func colorChange(start: Float, end: Float, valStart: SIMD3<Float>, valEnd: SIMD3<Float>) -> ParticleOperatorOp {
        return { info in
            let buffer = info.particles
            for i in 0..<buffer.count {
                let life = buffer[i].initValue.lifetime > 0 ? (1.0 - buffer[i].lifetime / buffer[i].initValue.lifetime) : 1.0
                var col = SIMD3<Float>(0,0,0)
                col.x = ParticleModules.fadeValueChange(life: life, start: start, end: end, valStart: valStart.x, valEnd: valEnd.x)
                col.y = ParticleModules.fadeValueChange(life: life, start: start, end: end, valStart: valStart.y, valEnd: valEnd.y)
                col.z = ParticleModules.fadeValueChange(life: life, start: start, end: end, valStart: valStart.z, valEnd: valEnd.z)
                buffer[i].color = buffer[i].initValue.color * col
            }
        }
    }
    
    static func oscillateAlpha(freqMin: Float, freqMax: Float, scaleMin: Float, scaleMax: Float, phaseMin: Float, phaseMax: Float) -> ParticleOperatorOp {
        var storage: [OscillateStorage] = []
        return { info in
            if storage.count < info.particles.count {
                storage = Array(repeating: OscillateStorage(), count: info.particles.count * 2)
            }
            let buffer = info.particles
            for i in 0..<buffer.count {
                if buffer[i].lifetime <= 0 || buffer[i].markNew { storage[i].reset = true }
                if storage[i].reset {
                    storage[i].freq = ParticleMath.randomFloat(min: freqMin, max: freqMax)
                    storage[i].scale = ParticleMath.randomFloat(min: scaleMin, max: scaleMax)
                    storage[i].phase = ParticleMath.randomFloat(min: phaseMin, max: phaseMax)
                    storage[i].reset = false
                }
                
                let time = buffer[i].initValue.lifetime - buffer[i].lifetime
                let f = storage[i].freq / (2.0 * Float.pi)
                let w = 2.0 * Float.pi * f
                let scale = ParticleMath.lerp(scaleMin, scaleMax, (cos(w * time + storage[i].phase) + 1.0) * 0.5)
                buffer[i].alpha = buffer[i].initValue.alpha * scale
            }
        }
    }
    
    static func oscillateSize(freqMin: Float, freqMax: Float, scaleMin: Float, scaleMax: Float, phaseMin: Float, phaseMax: Float) -> ParticleOperatorOp {
        var storage: [OscillateStorage] = []
        return { info in
            if storage.count < info.particles.count {
                storage = Array(repeating: OscillateStorage(), count: info.particles.count * 2)
            }
            let buffer = info.particles
            for i in 0..<buffer.count {
                if buffer[i].lifetime <= 0 || buffer[i].markNew { storage[i].reset = true }
                if storage[i].reset {
                    storage[i].freq = ParticleMath.randomFloat(min: freqMin, max: freqMax)
                    storage[i].scale = ParticleMath.randomFloat(min: scaleMin, max: scaleMax)
                    storage[i].phase = ParticleMath.randomFloat(min: phaseMin, max: phaseMax)
                    storage[i].reset = false
                }
                
                let time = buffer[i].initValue.lifetime - buffer[i].lifetime
                let f = storage[i].freq / (2.0 * Float.pi)
                let w = 2.0 * Float.pi * f
                let scale = ParticleMath.lerp(scaleMin, scaleMax, (cos(w * time + storage[i].phase) + 1.0) * 0.5)
                buffer[i].size = buffer[i].initValue.size * scale
            }
        }
    }
    
    static func oscillatePosition(freqMin: Float, freqMax: Float, scaleMin: Float, scaleMax: Float, phaseMin: Float, phaseMax: Float, mask: SIMD3<Float>) -> ParticleOperatorOp {
        var storageX: [OscillateStorage] = []
        var storageY: [OscillateStorage] = []
        var storageZ: [OscillateStorage] = []
        
        return { info in
            let count = info.particles.count
            if storageX.count < count {
                storageX = Array(repeating: OscillateStorage(), count: count * 2)
                storageY = Array(repeating: OscillateStorage(), count: count * 2)
                storageZ = Array(repeating: OscillateStorage(), count: count * 2)
            }
            let buffer = info.particles
            
            for i in 0..<count {
                let p = buffer[i]
                let reset = p.lifetime <= 0 || p.markNew
                
                let updateStorage = { (st: inout OscillateStorage) in
                    if reset { st.reset = true }
                    if st.reset {
                        st.freq = ParticleMath.randomFloat(min: freqMin, max: freqMax)
                        st.scale = ParticleMath.randomFloat(min: scaleMin, max: scaleMax)
                        st.phase = ParticleMath.randomFloat(min: phaseMin, max: phaseMax)
                        st.reset = false
                    }
                }
                updateStorage(&storageX[i])
                updateStorage(&storageY[i])
                updateStorage(&storageZ[i])
                
                let time = p.initValue.lifetime - p.lifetime
                var delta = SIMD3<Float>(0,0,0)
                
                let calcMove = { (st: OscillateStorage) -> Float in
                    let f = st.freq / (2.0 * Float.pi)
                    let w = 2.0 * Float.pi * f
                    return -1.0 * st.scale * w * sin(w * time + st.phase) * Float(info.timePass)
                }
                
                if mask.x > 0.01 { delta.x = calcMove(storageX[i]) }
                if mask.y > 0.01 { delta.y = calcMove(storageY[i]) }
                if mask.z > 0.01 { delta.z = calcMove(storageZ[i]) }
                
                buffer[i].position += delta
            }
        }
    }
    
    static func turbulence(phaseMin: Float, phaseMax: Float, speedMin: Float, speedMax: Float, timeScale: Float, scale: Float, mask: SIMD3<Int32>) -> ParticleOperatorOp {
        return { info in
            let phase = ParticleMath.randomFloat(min: phaseMin, max: phaseMax)
            let speed = ParticleMath.randomFloat(min: speedMin, max: speedMax)
            let buffer = info.particles
            
            for i in 0..<buffer.count {
                var pos = SIMD3<Double>(Double(buffer[i].position.x), Double(buffer[i].position.y), Double(buffer[i].position.z))
                pos.x += Double(phase + timeScale * Float(info.time))
                var result = ParticleMath.curlNoise(pos: pos * Double(scale) * 2.0)
                result = normalize(result) * speed
                if mask.x == 0 { result.x = 0 }
                if mask.y == 0 { result.y = 0 }
                if mask.z == 0 { result.z = 0 }
                
                buffer[i].velocity += result * Float(info.timePass)
            }
        }
    }
    
    static func vortex(controlPoint: Int, distInner: Float, distOuter: Float, speedInner: Float, speedOuter: Float, offset: SIMD3<Float>, axis: SIMD3<Float>) -> ParticleOperatorOp {
        return { info in
            let cpOffset = info.controlPoints.indices.contains(controlPoint) ? info.controlPoints[controlPoint].offset : SIMD3<Float>(0,0,0)
            let finalOffset = cpOffset + offset
            let distMid = distOuter - distInner + 0.1
            let buffer = info.particles
            
            for i in 0..<buffer.count {
                let pos = buffer[i].position
                let diff = pos - finalOffset
                let direct = -normalize(cross(axis, pos))
                let dist = length(diff)
                
                if distMid < 0 || dist < distInner {
                    buffer[i].velocity += direct * speedInner * Float(info.timePass)
                } else if dist > distOuter {
                    buffer[i].velocity += direct * speedOuter * Float(info.timePass)
                } else {
                    let t = (dist - distInner) / distMid
                    let s = ParticleMath.lerp(speedInner, speedOuter, t)
                    buffer[i].velocity += direct * s * Float(info.timePass)
                }
            }
        }
    }
    
    private static func fadeValueChange(life: Float, start: Float, end: Float, valStart: Float, valEnd: Float) -> Float {
        if life <= start { return valStart }
        if life > end { return valEnd }
        let t = (life - start) / (end - start)
        return ParticleMath.lerp(valStart, valEnd, t)
    }
    
    struct OscillateStorage {
        var reset: Bool = true
        var freq: Float = 0
        var scale: Float = 1
        var phase: Float = 0
    }
}
