//
//  ParticleSimulator.swift
//  Renderer
//
//  Created by laobamac on 2026/3/21.
//

import Foundation
import simd

typealias EmitterFunc = (inout [ParticleInstance], inout Int, Float) -> Void
typealias InitializerFunc = (inout ParticleInstance) -> Void
typealias OperatorFunc = (inout [ParticleInstance], Int, [ControlPointData], Float, Float) -> Void

class ParticleSimulator {
    let def: ParticleSystemDef
    let instanceOverride: ScriptableValue?
    let baseOrigin: SIMD3<Float>
    let isOrthographic: Bool
    
    var particles: [ParticleInstance]
    var particleCount: Int = 0
    var maxParticles: Int
    
    var emitters: [EmitterFunc] = []
    var initializers: [InitializerFunc] = []
    var operators: [OperatorFunc] = []
    var controlPoints: [ControlPointData] = Array(repeating: ControlPointData(), count: 8)
    
    var time: Double = 0.0
    var transformedOrigin: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    var lastScreenWidth: Float = 0.0
    var lastScreenHeight: Float = 0.0
    var uniformLifetimes: Bool = false
    
    init(def: ParticleSystemDef, instanceOverride: ScriptableValue?, origin: SIMD3<Float>, isOrthographic: Bool) {
        self.def = def
        self.instanceOverride = instanceOverride
        self.baseOrigin = origin
        self.isOrthographic = isOrthographic
        
        var countMultiplier: Float = 1.0
        if let override = instanceOverride, case .object(let dict) = override, let countVal = dict["count"] {
            countMultiplier = countVal.floatValue
        }
        
        let adjustedMaxCount = Int(Float(def.maxcount ?? 1000) * countMultiplier)
        self.maxParticles = adjustedMaxCount > 0 ? adjustedMaxCount : 1000
        self.particles = Array(repeating: ParticleInstance(), count: self.maxParticles)
    }
    
    func setup(screenWidth: Float, screenHeight: Float) {
        self.lastScreenWidth = screenWidth
        self.lastScreenHeight = screenHeight
        var origin = baseOrigin
        origin.x -= screenWidth / 2.0
        origin.y = screenHeight / 2.0 - origin.y
        self.transformedOrigin = origin
        
        setupEmitters()
        setupInitializers()
        setupOperators()
        
        if let cps = def.controlpoint {
            for cp in cps {
                if cp.id >= 0 && cp.id < 8 {
                    let offset = cp.offset?.float3Value ?? SIMD3<Float>(0, 0, 0)
                    controlPoints[cp.id].offset = offset
                    let flags = cp.flags ?? 0
                    controlPoints[cp.id].linkMouse = (flags & 1) != 0
                    controlPoints[cp.id].worldSpace = (flags & 2) != 0
                    
                    if !controlPoints[cp.id].linkMouse {
                        if controlPoints[cp.id].worldSpace {
                            controlPoints[cp.id].position = offset - self.transformedOrigin
                        } else {
                            controlPoints[cp.id].position = offset
                        }
                    }
                }
            }
        }
        
        if let starttime = def.starttime, starttime > 0.0 {
            let step: Float = 0.1
            var t: Float = 0.0
            while t < starttime {
                self.update(dt: step, currentTime: Double(t), screenWidth: screenWidth, screenHeight: screenHeight, mousePos: nil)
                t += step
            }
        }
    }
    
    func update(dt: Float, currentTime: Double, screenWidth: Float, screenHeight: Float, mousePos: CGPoint?) {
        if screenWidth != lastScreenWidth || screenHeight != lastScreenHeight {
            var origin = baseOrigin
            origin.x -= screenWidth / 2.0
            origin.y = screenHeight / 2.0 - origin.y
            self.transformedOrigin = origin
            
            for i in 0..<controlPoints.count {
                if !controlPoints[i].linkMouse && controlPoints[i].worldSpace {
                    controlPoints[i].position = controlPoints[i].offset - self.transformedOrigin
                }
            }
            lastScreenWidth = screenWidth
            lastScreenHeight = screenHeight
        }
        
        if let mPos = mousePos {
            for i in 0..<controlPoints.count {
                if controlPoints[i].linkMouse {
                    var position = SIMD3<Float>()
                    position.x = (Float(mPos.x) * screenWidth) - (screenWidth / 2.0)
                    position.y = (screenHeight / 2.0) - (Float(mPos.y) * screenHeight)
                    position.z = 0.0
                    position += controlPoints[i].offset
                    controlPoints[i].position = position - self.transformedOrigin
                }
            }
        }
        
        self.time = currentTime
        let safeDt = min(dt, 0.1)
        
        for i in 0..<emitters.count {
            emitters[i](&particles, &particleCount, safeDt)
        }
        
        for i in 0..<particleCount {
            particles[i].age += safeDt
        }
        
        for i in 0..<operators.count {
            operators[i](&particles, particleCount, controlPoints, Float(self.time), safeDt)
        }
        
        let animSpeed = def.sequencemultiplier ?? 1.0
        for i in 0..<particleCount {
            particles[i].frame = particles[i].getLifetimePos() * animSpeed * 60.0
        }
        
        var writeIdx = 0
        for readIdx in 0..<particleCount {
            if particles[readIdx].isAlive() {
                if writeIdx != readIdx {
                    particles[writeIdx] = particles[readIdx]
                }
                writeIdx += 1
            }
        }
        particleCount = writeIdx
    }
    
    private func getOverrideValue(key: String, defaultValue: Float) -> Float {
        if let override = instanceOverride, case .object(let dict) = override, let val = dict[key] {
            return val.floatValue
        }
        return defaultValue
    }
    
    private func getOverrideVec3(key: String, defaultValue: SIMD3<Float>) -> SIMD3<Float> {
        if let override = instanceOverride, case .object(let dict) = override, let val = dict[key] {
            return val.float3Value
        }
        return defaultValue
    }
    
    private func setupEmitters() {
        guard let emitterDefs = def.emitter else { return }
        for eDef in emitterDefs {
            var funcToUse: EmitterFunc?
            if eDef.name == "boxrandom" {
                funcToUse = createBoxEmitter(eDef: eDef)
            } else if eDef.name == "sphererandom" {
                funcToUse = createSphereEmitter(eDef: eDef)
            } else {
                Logger.log("Unknown emitter type: \(eDef.name)")
                continue
            }
            if let f = funcToUse {
                emitters.append(f)
            }
        }
    }
    
    private func setupInitializers() {
        guard let initDefs = def.initializer else { return }
        for iDef in initDefs {
            var funcToUse: InitializerFunc?
            if iDef.name == "colorrandom" {
                funcToUse = createColorRandomInitializer(iDef: iDef)
            } else if iDef.name == "sizerandom" {
                funcToUse = createSizeRandomInitializer(iDef: iDef)
            } else if iDef.name == "alpharandom" {
                funcToUse = createAlphaRandomInitializer(iDef: iDef)
            } else if iDef.name == "lifetimerandom" {
                if let minVal = iDef.min?.floatValue, let maxVal = iDef.max?.floatValue {
                    self.uniformLifetimes = (minVal == maxVal)
                }
                funcToUse = createLifetimeRandomInitializer(iDef: iDef)
            } else if iDef.name == "velocityrandom" {
                funcToUse = createVelocityRandomInitializer(iDef: iDef)
            } else if iDef.name == "rotationrandom" {
                funcToUse = createRotationRandomInitializer(iDef: iDef)
            } else if iDef.name == "angularvelocityrandom" {
                funcToUse = createAngularVelocityRandomInitializer(iDef: iDef)
            } else if iDef.name == "turbulentvelocityrandom" {
                funcToUse = createTurbulentVelocityRandomInitializer(iDef: iDef)
            } else {
                Logger.log("Unknown initializer type: \(iDef.name)")
            }
            if let f = funcToUse {
                initializers.append(f)
            }
        }
    }
    
    private func setupOperators() {
        guard let opDefs = def.operatorList else { return }
        for oDef in opDefs {
            var funcToUse: OperatorFunc?
            if oDef.name == "movement" {
                funcToUse = createMovementOperator(oDef: oDef)
            } else if oDef.name == "angularmovement" {
                funcToUse = createAngularMovementOperator(oDef: oDef)
            } else if oDef.name == "alphafade" {
                funcToUse = createAlphaFadeOperator(oDef: oDef)
            } else if oDef.name == "sizechange" {
                funcToUse = createSizeChangeOperator(oDef: oDef)
            } else if oDef.name == "alphachange" {
                funcToUse = createAlphaChangeOperator(oDef: oDef)
            } else if oDef.name == "colorchange" {
                funcToUse = createColorChangeOperator(oDef: oDef)
            } else if oDef.name == "turbulence" {
                funcToUse = createTurbulenceOperator(oDef: oDef)
            } else if oDef.name == "vortex" {
                funcToUse = createVortexOperator(oDef: oDef)
            } else if oDef.name == "controlpointattract" {
                funcToUse = createControlPointAttractOperator(oDef: oDef)
            } else if oDef.name == "oscillatealpha" {
                funcToUse = createOscillateAlphaOperator(oDef: oDef)
            } else if oDef.name == "oscillatesize" {
                funcToUse = createOscillateSizeOperator(oDef: oDef)
            } else if oDef.name == "oscillateposition" {
                funcToUse = createOscillatePositionOperator(oDef: oDef)
            } else {
                Logger.log("Unknown operator type: \(oDef.name)")
            }
            if let f = funcToUse {
                operators.append(f)
            }
        }
    }
    
    private func createBoxEmitter(eDef: ParticleEmitterDef) -> EmitterFunc {
        let baseRate = eDef.rate ?? 0.0
        let rateOverride = getOverrideValue(key: "rate", defaultValue: 1.0)
        let rate = baseRate * rateOverride
        var transformedOrigin = eDef.origin?.float3Value ?? SIMD3<Float>(0, 0, 0)
        transformedOrigin.y = -transformedOrigin.y
        
        var controlPointIndex = eDef.controlPoint ?? -1
        if controlPointIndex == -1, let cps = def.controlpoint, !cps.isEmpty {
            if ((cps[0].flags ?? 0) & 1) != 0 {
                controlPointIndex = 0
            }
        }
        
        var flippedDirections = eDef.directions?.float3Value ?? SIMD3<Float>(1, 1, 1)
        flippedDirections.y = -flippedDirections.y
        let flags = eDef.flags ?? 0
        let limitOnePerFrame = (flags & 2) != 0
        let randomPeriodicEmission = (flags & 4) != 0
        
        let minDist = eDef.distancemin?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let maxDist = eDef.distancemax?.float3Value ?? SIMD3<Float>(0, 0, 0)
        
        let instantaneous = eDef.instantaneous ?? 0
        let delay = eDef.delay ?? 0.0
        let duration = eDef.duration ?? 0.0
        
        let minPeriodicDuration = eDef.minPeriodicDuration ?? 0.0
        let maxPeriodicDuration = eDef.maxPeriodicDuration ?? 0.0
        let minPeriodicDelay = eDef.minPeriodicDelay ?? 0.0
        let maxPeriodicDelay = eDef.maxPeriodicDelay ?? 0.0
        
        var emissionTimer: Float = 0.0
        var elapsedTime: Float = 0.0
        var delayTimer: Float = delay
        var durationTimer: Float = 0.0
        var periodicTimer: Float = 0.0
        var currentPeriodicDuration: Float = 0.0
        var currentPeriodicDelay: Float = 0.0
        var emitting: Bool = false
        var instantaneousEmitted: Bool = false
        
        return { [weak self] particles, count, dt in
            guard let self = self else { return }
            if count >= particles.count { return }
            
            elapsedTime += dt
            if delayTimer > 0.0 {
                delayTimer -= dt
                return
            }
            if duration > 0.0 {
                durationTimer += dt
                if durationTimer >= duration { return }
            }
            
            if randomPeriodicEmission {
                periodicTimer += dt
                if !emitting {
                    if periodicTimer >= currentPeriodicDelay {
                        emitting = true
                        periodicTimer = 0.0
                        currentPeriodicDuration = Float.random(in: minPeriodicDuration...maxPeriodicDuration)
                    } else {
                        return
                    }
                } else {
                    if periodicTimer >= currentPeriodicDuration {
                        emitting = false
                        periodicTimer = 0.0
                        currentPeriodicDelay = Float.random(in: minPeriodicDelay...maxPeriodicDelay)
                        return
                    }
                }
            }
            
            var toEmit: Int = 0
            if instantaneous > 0 && !instantaneousEmitted {
                toEmit = instantaneous
                instantaneousEmitted = true
            }
            if rate > 0.0 {
                emissionTimer += dt * rate
                var rateEmit = Int(emissionTimer)
                emissionTimer -= Float(rateEmit)
                if limitOnePerFrame && rateEmit > 1 {
                    rateEmit = 1
                }
                toEmit += rateEmit
            }
            
            for _ in 0..<toEmit {
                if count >= particles.count { break }
                var spawnOrigin = transformedOrigin
                if controlPointIndex >= 0 && controlPointIndex < self.controlPoints.count {
                    spawnOrigin += self.controlPoints[controlPointIndex].position
                }
                var randomPos = SIMD3<Float>(0, 0, 0)
                for axis in 0..<3 {
                    let dMin = minDist[axis]
                    let dMax = maxDist[axis]
                    var dist = Float.random(in: min(dMin, dMax)...max(dMin, dMax))
                    if Float.random(in: 0...1) < 0.5 { dist = -dist }
                    randomPos[axis] = dist
                }
                randomPos *= flippedDirections
                
                var p = particles[count]
                p.position = spawnOrigin + randomPos
                p.velocity = SIMD3<Float>(0, 0, 0)
                p.acceleration = SIMD3<Float>(0, 0, 0)
                p.rotation = SIMD3<Float>(0, 0, 0)
                p.angularVelocity = SIMD3<Float>(0, 0, 0)
                p.angularAcceleration = SIMD3<Float>(0, 0, 0)
                
                p.color = SIMD3<Float>(1, 1, 1) * self.getOverrideVec3(key: "colorn", defaultValue: SIMD3<Float>(1, 1, 1))
                p.alpha = 1.0 * self.getOverrideValue(key: "alpha", defaultValue: 1.0)
                p.size = 20.0 * self.getOverrideValue(key: "size", defaultValue: 1.0)
                p.lifetime = 1.0 * self.getOverrideValue(key: "lifetime", defaultValue: 1.0)
                p.age = 0.0
                p.alive = true
                p.frame = -1.0
                
                p.initial.color = p.color
                p.initial.alpha = p.alpha
                p.initial.size = p.size
                p.initial.lifetime = p.lifetime
                
                p.oscillateAlpha = ParticleInstance.OscillateStateAlphaSize()
                p.oscillateSize = ParticleInstance.OscillateStateAlphaSize()
                p.oscillatePosition = ParticleInstance.OscillateStatePosition()
                
                for initFunc in self.initializers {
                    initFunc(&p)
                }
                particles[count] = p
                count += 1
            }
        }
    }
    
    private func createSphereEmitter(eDef: ParticleEmitterDef) -> EmitterFunc {
        let baseRate = eDef.rate ?? 0.0
        let rateOverride = getOverrideValue(key: "rate", defaultValue: 1.0)
        let rate = baseRate * rateOverride
        let lifetimeOverride = getOverrideValue(key: "lifetime", defaultValue: 1.0)
        
        var transformedOrigin = eDef.origin?.float3Value ?? SIMD3<Float>(0, 0, 0)
        transformedOrigin.y = -transformedOrigin.y
        
        var controlPointIndex = eDef.controlPoint ?? -1
        if controlPointIndex == -1, let cps = def.controlpoint, !cps.isEmpty {
            if ((cps[0].flags ?? 0) & 1) != 0 {
                controlPointIndex = 0
            }
        }
        
        let flags = eDef.flags ?? 0
        let limitOnePerFrame = (flags & 2) != 0
        let is3D = ((def.flags ?? 0) & 4) != 0
        let minDist = eDef.distancemin?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let maxDist = eDef.distancemax?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let directions = eDef.directions?.float3Value ?? SIMD3<Float>(1, 1, 1)
        let sign = eDef.sign?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let speedMin = eDef.speedmin ?? 0.0
        let speedMax = eDef.speedmax ?? 0.0
        var remaining = eDef.instantaneous ?? 0
        var emissionTimer: Float = 0.0
        
        return { [weak self] particles, count, dt in
            guard let self = self else { return }
            if count >= particles.count { return }
            
            emissionTimer += dt * rate
            var toEmit = Int(emissionTimer)
            emissionTimer -= Float(toEmit)
            if limitOnePerFrame && toEmit > 1 { toEmit = 1 }
            if remaining > 0 {
                toEmit += remaining
                remaining = 0
            }
            
            for _ in 0..<toEmit {
                if count >= particles.count { break }
                var spawnOrigin = transformedOrigin
                if controlPointIndex >= 0 && controlPointIndex < self.controlPoints.count {
                    spawnOrigin += self.controlPoints[controlPointIndex].position
                }
                var randomPos = SIMD3<Float>(0, 0, 0)
                
                if !is3D {
                    let angle = Float.random(in: 0...(2.0 * .pi))
                    let rMin = minDist.x
                    let rMax = maxDist.x
                    let minSq = rMin * rMin
                    let maxSq = rMax * rMax
                    let radiusXY = sqrt(Float.random(in: min(minSq, maxSq)...max(minSq, maxSq)))
                    randomPos = SIMD3<Float>(radiusXY * cos(angle), radiusXY * sin(angle), Float.random(in: min(-rMax, rMax)...max(-rMax, rMax)))
                    randomPos *= directions
                } else {
                    let theta = Float.random(in: 0...(2.0 * .pi))
                    let cosTheta = Float.random(in: -1...1)
                    let sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta))
                    randomPos = SIMD3<Float>(sinTheta * cos(theta), sinTheta * sin(theta), cosTheta)
                    let rMin = minDist.x
                    let rMax = maxDist.x
                    let minCubed = rMin * rMin * rMin
                    let maxCubed = rMax * rMax * rMax
                    let radius = cbrt(Float.random(in: min(minCubed, maxCubed)...max(minCubed, maxCubed)))
                    randomPos *= radius
                    randomPos *= directions
                }
                
                for i in 0..<3 {
                    if sign[i] == 1.0 { randomPos[i] = abs(randomPos[i]) }
                    else if sign[i] == -1.0 { randomPos[i] = -abs(randomPos[i]) }
                }
                
                var p = particles[count]
                p.position = spawnOrigin + randomPos
                
                if speedMax > 0.0 || speedMin != 0.0 {
                    let dir = length(randomPos) > 0.0001 ? normalize(randomPos) : SIMD3<Float>(0, 1, 0)
                    let speed = Float.random(in: min(speedMin, speedMax)...max(speedMin, speedMax))
                    p.velocity = dir * speed
                } else {
                    p.velocity = SIMD3<Float>(0, 0, 0)
                }
                
                p.acceleration = SIMD3<Float>(0, 0, 0)
                p.rotation = SIMD3<Float>(0, 0, 0)
                p.angularVelocity = SIMD3<Float>(0, 0, 0)
                p.angularAcceleration = SIMD3<Float>(0, 0, 0)
                
                p.color = SIMD3<Float>(1, 1, 1) * self.getOverrideVec3(key: "colorn", defaultValue: SIMD3<Float>(1, 1, 1))
                p.alpha = 1.0 * self.getOverrideValue(key: "alpha", defaultValue: 1.0)
                p.size = 20.0 * self.getOverrideValue(key: "size", defaultValue: 1.0)
                p.lifetime = 1.0 * lifetimeOverride
                p.age = 0.0
                p.alive = true
                p.frame = -1.0
                
                p.initial.color = p.color
                p.initial.alpha = p.alpha
                p.initial.size = p.size
                p.initial.lifetime = p.lifetime
                
                p.oscillateAlpha = ParticleInstance.OscillateStateAlphaSize()
                p.oscillateSize = ParticleInstance.OscillateStateAlphaSize()
                p.oscillatePosition = ParticleInstance.OscillateStatePosition()
                
                for initFunc in self.initializers {
                    initFunc(&p)
                }
                particles[count] = p
                count += 1
            }
        }
    }
    
    private func createColorRandomInitializer(iDef: ParticleInitializerDef) -> InitializerFunc {
        let minV = iDef.min?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let maxV = iDef.max?.float3Value ?? SIMD3<Float>(1, 1, 1)
        return { [weak self] p in
            guard let self = self else { return }
            let override = self.getOverrideVec3(key: "colorn", defaultValue: SIMD3<Float>(1, 1, 1))
            let r = Float.random(in: min(minV.x, maxV.x)...max(minV.x, maxV.x))
            let g = Float.random(in: min(minV.y, maxV.y)...max(minV.y, maxV.y))
            let b = Float.random(in: min(minV.z, maxV.z)...max(minV.z, maxV.z))
            p.color = SIMD3<Float>(r, g, b) * override
            p.initial.color = p.color
        }
    }
    
    private func createSizeRandomInitializer(iDef: ParticleInitializerDef) -> InitializerFunc {
        let minV = iDef.min?.floatValue ?? 10.0
        let maxV = iDef.max?.floatValue ?? 20.0
        let expV = iDef.exponent?.floatValue ?? 1.0
        return { [weak self] p in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "size", defaultValue: 1.0)
            let t = pow(Float.random(in: 0...1), expV)
            p.size = (minV + t * (maxV - minV)) * override / 2.0
            p.initial.size = p.size
        }
    }
    
    private func createAlphaRandomInitializer(iDef: ParticleInitializerDef) -> InitializerFunc {
        let minV = iDef.min?.floatValue ?? 0.0
        let maxV = iDef.max?.floatValue ?? 1.0
        return { [weak self] p in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "alpha", defaultValue: 1.0)
            p.alpha = Float.random(in: min(minV, maxV)...max(minV, maxV)) * override
            p.initial.alpha = p.alpha
        }
    }
    
    private func createLifetimeRandomInitializer(iDef: ParticleInitializerDef) -> InitializerFunc {
        let minV = iDef.min?.floatValue ?? 1.0
        let maxV = iDef.max?.floatValue ?? 1.0
        return { [weak self] p in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "lifetime", defaultValue: 1.0)
            p.lifetime = Float.random(in: min(minV, maxV)...max(minV, maxV)) * override
            p.initial.lifetime = p.lifetime
        }
    }
    
    private func createVelocityRandomInitializer(iDef: ParticleInitializerDef) -> InitializerFunc {
        let minV = iDef.min?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let maxV = iDef.max?.float3Value ?? SIMD3<Float>(0, 0, 0)
        return { [weak self] p in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "speed", defaultValue: 1.0)
            let x = Float.random(in: min(minV.x, maxV.x)...max(minV.x, maxV.x))
            let y = Float.random(in: min(minV.y, maxV.y)...max(minV.y, maxV.y))
            let z = Float.random(in: min(minV.z, maxV.z)...max(minV.z, maxV.z))
            var vel = SIMD3<Float>(x, y, z) * override
            vel.y = -vel.y
            p.velocity += vel
        }
    }
    
    private func createRotationRandomInitializer(iDef: ParticleInitializerDef) -> InitializerFunc {
        let minV = iDef.min?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let maxV = iDef.max?.float3Value ?? SIMD3<Float>(0, 0, 0)
        return { [weak self] p in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "speed", defaultValue: 1.0)
            let x = Float.random(in: min(minV.x, maxV.x)...max(minV.x, maxV.x))
            let y = Float.random(in: min(minV.y, maxV.y)...max(minV.y, maxV.y))
            let z = Float.random(in: min(minV.z, maxV.z)...max(minV.z, maxV.z))
            p.rotation = SIMD3<Float>(x, y, z) * override
        }
    }
    
    private func createAngularVelocityRandomInitializer(iDef: ParticleInitializerDef) -> InitializerFunc {
        let minV = iDef.min?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let maxV = iDef.max?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let expV = iDef.exponent?.floatValue ?? 1.0
        return { [weak self] p in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "speed", defaultValue: 1.0)
            var result = SIMD3<Float>()
            for i in 0..<3 {
                let t = pow(Float.random(in: 0...1), expV)
                result[i] = minV[i] + t * (maxV[i] - minV[i])
            }
            p.angularVelocity = result * override
        }
    }
    
    private func mod289(_ x: SIMD4<Float>) -> SIMD4<Float> {
        return x - floor(x * (1.0 / 289.0)) * 289.0
    }
    private func permute(_ x: SIMD4<Float>) -> SIMD4<Float> {
        return mod289(((x * 34.0) + 1.0) * x)
    }
    private func taylorInvSqrt(_ r: SIMD4<Float>) -> SIMD4<Float> {
        return 1.79284291400159 - 0.85373472095314 * r
    }
    private func snoise(_ v: SIMD3<Float>) -> Float {
        let C = SIMD2<Float>(1.0 / 6.0, 1.0 / 3.0)
        let D = SIMD4<Float>(0.0, 0.5, 1.0, 2.0)
        var i = floor(v + dot(v, SIMD3<Float>(C.y, C.y, C.y)))
        let x0 = v - i + dot(i, SIMD3<Float>(C.x, C.x, C.x))
        let g = step(SIMD3<Float>(x0.y, x0.z, x0.x), SIMD3<Float>(x0.x, x0.y, x0.z))
        let l = 1.0 - g
        let i1 = min(g, SIMD3<Float>(l.z, l.x, l.y))
        let i2 = max(g, SIMD3<Float>(l.z, l.x, l.y))
        let x1 = x0 - i1 + SIMD3<Float>(C.x, C.x, C.x)
        let x2 = x0 - i2 + SIMD3<Float>(C.y, C.y, C.y)
        let x3 = x0 - 0.5
        i = mod289(SIMD4<Float>(i.x, i.y, i.z, 0.0).xyz)
        var p = permute(permute(permute(
            SIMD4<Float>(0.0, i1.z, i2.z, 1.0) + i.z)
            + SIMD4<Float>(0.0, i1.y, i2.y, 1.0) + i.y)
            + SIMD4<Float>(0.0, i1.x, i2.x, 1.0) + i.x)
        let j = p - 49.0 * floor(p * (1.0 / 49.0))
        let ns = SIMD3<Float>(0.28571428571429, -0.92857142857143, 0.14285714285714)
        let jx = SIMD4<Float>(j.x * ns.x, j.y * ns.x, j.z * ns.x, j.w * ns.x)
        let jy = SIMD4<Float>(floor(j * ns.z))
        let jz = SIMD4<Float>(floor(j * ns.w))
        let norm = taylorInvSqrt(SIMD4<Float>(dot(jx, jx), dot(jy, jy), dot(jz, jz), 0.0))
        var p0 = SIMD2<Float>(jx.x, jy.x) * norm.x
        var p1 = SIMD2<Float>(jx.y, jy.y) * norm.y
        var p2 = SIMD2<Float>(jx.z, jy.z) * norm.z
        var p3 = SIMD2<Float>(jx.w, jy.w) * norm.w
        var m = max(0.6 - SIMD4<Float>(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0)
        m = m * m
        return 42.0 * dot(m * m, SIMD4<Float>(dot(p0, SIMD2<Float>(x0.x, x0.y)), dot(p1, SIMD2<Float>(x1.x, x1.y)), dot(p2, SIMD2<Float>(x2.x, x2.y)), dot(p3, SIMD2<Float>(x3.x, x3.y))))
    }
    private func curlNoise(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let e: Float = 0.1
        let dx = SIMD3<Float>(e, 0.0, 0.0)
        let dy = SIMD3<Float>(0.0, e, 0.0)
        let dz = SIMD3<Float>(0.0, 0.0, e)
        var p_x0 = snoise(p - dx)
        var p_x1 = snoise(p + dx)
        var p_y0 = snoise(p - dy)
        var p_y1 = snoise(p + dy)
        var p_z0 = snoise(p - dz)
        var p_z1 = snoise(p + dz)
        let x = p_y1 - p_y0 - p_z1 + p_z0
        let y = p_z1 - p_z0 - p_x1 + p_x0
        let z = p_x1 - p_x0 - p_y1 + p_y0
        return SIMD3<Float>(x, y, z) / (2.0 * e)
    }
    
    private func createTurbulentVelocityRandomInitializer(iDef: ParticleInitializerDef) -> InitializerFunc {
        let speedMin = iDef.speedmin?.floatValue ?? 0.0
        let speedMax = iDef.speedmax?.floatValue ?? 0.0
        let offsetV = iDef.offset?.floatValue ?? 0.0
        let scaleV = iDef.scale?.floatValue ?? 1.0
        let timeScaleV = iDef.timescale?.floatValue ?? 1.0
        let phaseMinV = iDef.phasemin?.floatValue ?? 0.0
        let phaseMaxV = iDef.phasemax?.floatValue ?? 0.0
        var forward = iDef.forward?.float3Value ?? SIMD3<Float>(0, 1, 0)
        var right = iDef.right?.float3Value ?? SIMD3<Float>(1, 0, 0)
        forward.y = -forward.y
        right.y = -right.y
        if length(forward) > 0.0001 { forward = normalize(forward) } else { forward = SIMD3<Float>(0, 1, 0) }
        if length(right) > 0.0001 { right = normalize(right) } else { right = SIMD3<Float>(1, 0, 0) }
        
        return { [weak self] p in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "speed", defaultValue: 1.0)
            let speed = Float.random(in: min(speedMin, speedMax)...max(speedMin, speedMax))
            let phase = Float.random(in: min(phaseMinV, phaseMaxV)...max(phaseMinV, phaseMaxV))
            var noisePos = p.position * 0.1
            noisePos += SIMD3<Float>(repeating: Float(self.time) * timeScaleV)
            let samplePos = noisePos + SIMD3<Float>(phase, phase * 0.7, phase * 1.3)
            var result = self.curlNoise(samplePos)
            let len = length(result)
            if len < 0.0001 { result = forward } else { result = result / len }
            
            if scaleV < 2.0 {
                let cosAngle = dot(result, forward)
                let angle = acos(max(-1.0, min(1.0, cosAngle))) / .pi
                let maxAngle = scaleV / 2.0
                if angle > maxAngle && maxAngle > 0.0001 {
                    var axis = cross(result, forward)
                    let axisLen = length(axis)
                    if axisLen > 0.0001 {
                        axis = axis / axisLen
                        let rotAngle = (angle - maxAngle) * .pi
                        let q = simd_quatf(angle: rotAngle, axis: axis)
                        result = q.act(result)
                    }
                }
            }
            if abs(offsetV) > 0.0001 {
                let q = simd_quatf(angle: -offsetV, axis: right)
                result = q.act(result)
            }
            if !self.isOrthographic && ((self.def.flags ?? 0) & 4) == 0 {
                result.z = 0.0
                let len2d = length(result)
                if len2d > 0.0001 { result /= len2d }
            }
            p.velocity += result * speed * override
        }
    }
    
    private func createMovementOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let drag = oDef.drag?.floatValue ?? 0.0
        var gravity = oDef.gravity?.float3Value ?? SIMD3<Float>(0, 0, 0)
        gravity.y = -gravity.y
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "speed", defaultValue: 1.0)
            for i in 0..<count {
                if !particles[i].alive { continue }
                particles[i].position += particles[i].velocity * dt
                particles[i].velocity += gravity * dt * override
                var dragFactor = 1.0 - (drag * dt)
                if dragFactor < 0.0 { dragFactor = 0.0 }
                particles[i].velocity *= dragFactor
            }
        }
    }
    
    private func createAngularMovementOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let drag = oDef.drag?.floatValue ?? 0.0
        let force = oDef.force?.float3Value ?? SIMD3<Float>(0, 0, 0)
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "speed", defaultValue: 1.0)
            for i in 0..<count {
                if !particles[i].alive { continue }
                particles[i].rotation += particles[i].angularVelocity * dt * override
                particles[i].angularVelocity += force * dt * override
                var dragFactor = 1.0 - (drag * dt)
                if dragFactor < 0.0 { dragFactor = 0.0 }
                particles[i].angularVelocity *= dragFactor
                for j in 0..<3 {
                    while particles[i].rotation[j] > .pi { particles[i].rotation[j] -= (2.0 * .pi) }
                    while particles[i].rotation[j] < -.pi { particles[i].rotation[j] += (2.0 * .pi) }
                }
            }
        }
    }
    
    private func fadeValue(life: Float, startT: Float, endT: Float, startV: Float, endV: Float) -> Float {
        if life <= startT { return startV }
        if life >= endT { return endV }
        let t = (life - startT) / (endT - startT)
        return startV + t * (endV - startV)
    }
    
    private func createAlphaFadeOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let fadeIn = oDef.fadeintime?.floatValue ?? 0.0
        let fadeOut = oDef.fadeouttime?.floatValue ?? 1.0
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                if life <= fadeIn {
                    let fade = self.fadeValue(life: life, startT: 0.0, endT: fadeIn, startV: 0.0, endV: 1.0)
                    particles[i].alpha = particles[i].initial.alpha * fade
                } else if life > fadeOut {
                    let fade = 1.0 - self.fadeValue(life: life, startT: fadeOut, endT: 1.0, startV: 0.0, endV: 1.0)
                    particles[i].alpha = particles[i].initial.alpha * fade
                } else {
                    particles[i].alpha = particles[i].initial.alpha
                }
                particles[i].oscillateAlpha.base = particles[i].alpha
            }
        }
    }
    
    private func createSizeChangeOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let startT = oDef.starttime?.floatValue ?? 0.0
        let endT = oDef.endtime?.floatValue ?? 1.0
        let startV = oDef.startvalue?.floatValue ?? 1.0
        let endV = oDef.endvalue?.floatValue ?? 1.0
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                let multiplier = self.fadeValue(life: life, startT: startT, endT: endT, startV: startV, endV: endV)
                particles[i].size = particles[i].initial.size * multiplier
                particles[i].oscillateSize.base = particles[i].size
            }
        }
    }
    
    private func createAlphaChangeOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let startT = oDef.starttime?.floatValue ?? 0.0
        let endT = oDef.endtime?.floatValue ?? 1.0
        let startV = oDef.startvalue?.floatValue ?? 1.0
        let endV = oDef.endvalue?.floatValue ?? 1.0
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                let multiplier = self.fadeValue(life: life, startT: startT, endT: endT, startV: startV, endV: endV)
                particles[i].alpha = particles[i].initial.alpha * multiplier
                particles[i].oscillateAlpha.base = particles[i].alpha
            }
        }
    }
    
    private func createColorChangeOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let startT = oDef.starttime?.floatValue ?? 0.0
        let endT = oDef.endtime?.floatValue ?? 1.0
        let startV = oDef.startvalue?.float3Value ?? SIMD3<Float>(1, 1, 1)
        let endV = oDef.endvalue?.float3Value ?? SIMD3<Float>(1, 1, 1)
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            for i in 0..<count {
                if !particles[i].alive { continue }
                let life = particles[i].getLifetimePos()
                var color = SIMD3<Float>(0, 0, 0)
                color.x = self.fadeValue(life: life, startT: startT, endT: endT, startV: startV.x, endV: endV.x)
                color.y = self.fadeValue(life: life, startT: startT, endT: endT, startV: startV.y, endV: endV.y)
                color.z = self.fadeValue(life: life, startT: startT, endT: endT, startV: startV.z, endV: endV.z)
                particles[i].color = particles[i].initial.color * color
            }
        }
    }
    
    private func createTurbulenceOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let scaleV = oDef.scale?.floatValue ?? 1.0
        let timeScaleV = oDef.timescale?.floatValue ?? 1.0
        let maskV = oDef.mask?.float3Value ?? SIMD3<Float>(1, 1, 1)
        let phaseMinV = oDef.phasemin?.floatValue ?? 0.0
        let phaseMaxV = oDef.phasemax?.floatValue ?? 0.0
        let speedMin = oDef.speedmin?.floatValue ?? 0.0
        let speedMax = oDef.speedmax?.floatValue ?? 0.0
        let phase = Float.random(in: min(phaseMinV, phaseMaxV)...max(phaseMinV, phaseMaxV))
        let turbSpeed = Float.random(in: min(speedMin, speedMax)...max(speedMin, speedMax))
        let noiseScale = scaleV * 2.0
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            if turbSpeed <= 0.0001 { return }
            let override = self.getOverrideValue(key: "speed", defaultValue: 1.0)
            for i in 0..<count {
                if !particles[i].alive { continue }
                var noisePos = particles[i].position
                noisePos.x += phase + timeScaleV * time
                noisePos *= noiseScale
                var curlDir = self.curlNoise(noisePos)
                let len = length(curlDir)
                if len > 0.0001 { curlDir = (curlDir / len) * turbSpeed }
                curlDir *= maskV
                particles[i].velocity += curlDir * dt * override
            }
        }
    }
    
    private func createVortexOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let cpIdx = oDef.controlPoint ?? -1
        let flags = oDef.flags ?? 0
        var axis = oDef.axis?.float3Value ?? SIMD3<Float>(0, 0, 1)
        let offset = oDef.offset?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let distIn = oDef.distanceinner?.floatValue ?? 0.0
        let distOut = oDef.distanceouter?.floatValue ?? 100.0
        var speedIn = oDef.speedinner?.floatValue ?? 0.0
        var speedOut = oDef.speedouter?.floatValue ?? 0.0
        let centerForce = oDef.centerforce?.floatValue ?? 0.0
        let ringRadius = oDef.ringradius?.floatValue ?? 0.0
        let ringWidth = oDef.ringwidth?.floatValue ?? 0.0
        let ringPullDist = oDef.ringpulldistance?.floatValue ?? 0.0
        let ringPullForce = oDef.ringpullforce?.floatValue ?? 0.0
        let audioMode = Int(oDef.audioprocessingmode?.floatValue ?? 0.0)
        let infAxis = (flags & 1) != 0
        let maintainDist = (flags & 2) != 0
        let ringShape = (flags & 4) != 0
        
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "speed", defaultValue: 1.0)
            let audioAmp: Float = 0.0
            if audioMode > 0 && audioAmp == 0.0 { return }
            
            var localSpeedIn = speedIn
            var localSpeedOut = speedOut
            if audioMode > 0 {
                localSpeedIn *= (1.0 + audioAmp)
                localSpeedOut *= (1.0 + audioAmp)
            }
            
            var center = SIMD3<Float>(0, 0, 0)
            if cpIdx >= 0 && cpIdx < cps.count {
                center = cps[cpIdx].position + offset
            } else {
                center = offset
            }
            if length(axis) > 0.0 { axis = normalize(axis) }
            
            for i in 0..<count {
                if !particles[i].alive { continue }
                let toParticle = particles[i].position - center
                var radialVec = toParticle
                if infAxis {
                    let axialDist = dot(toParticle, axis)
                    radialVec = toParticle - axis * axialDist
                }
                let dist = length(radialVec)
                var tangent = cross(axis, radialVec)
                if length(tangent) > 0.001 {
                    tangent = normalize(tangent)
                } else {
                    continue
                }
                var speed: Float = 0.0
                var radialForce = SIMD3<Float>(0, 0, 0)
                if ringShape {
                    let ringInner = ringRadius - ringWidth * 0.5
                    let ringOuter = ringRadius + ringWidth * 0.5
                    if dist < ringInner { speed = 0.0 }
                    else if dist <= ringOuter {
                        let t = (dist - ringInner) / ringWidth
                        speed = localSpeedIn + t * (localSpeedOut - localSpeedIn)
                    } else if dist <= ringOuter + ringPullDist {
                        let pullT = (dist - ringOuter) / ringPullDist
                        speed = localSpeedOut * (1.0 - pullT)
                        if dist > 0.001 {
                            let towardRing = -normalize(radialVec)
                            radialForce = towardRing * ringPullForce * pullT
                        }
                    } else {
                        speed = 0.0
                    }
                } else {
                    let disMid = distOut - distIn + 0.1
                    if disMid < 0 || dist < distIn { speed = localSpeedIn }
                    else if dist > distOut { speed = localSpeedOut }
                    else {
                        let t = (dist - distIn) / disMid
                        speed = localSpeedIn + t * (localSpeedOut - localSpeedIn)
                    }
                }
                particles[i].velocity += tangent * speed * dt * override
                particles[i].velocity += radialForce * dt * override
                if maintainDist && dist > 0.001 {
                    let towardCenter = -normalize(radialVec)
                    particles[i].velocity += towardCenter * centerForce * dt * override
                }
            }
        }
    }
    
    private func createControlPointAttractOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let cpIdx = oDef.controlPoint ?? -1
        let origin = oDef.origin?.float3Value ?? SIMD3<Float>(0, 0, 0)
        let scale = oDef.scale?.floatValue ?? 1.0
        let threshold = (oDef.threshold?.floatValue ?? 0.0) / 2.0
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "speed", defaultValue: 1.0)
            if cpIdx < 0 || cpIdx >= cps.count { return }
            let center = cps[cpIdx].position + origin
            for i in 0..<count {
                if !particles[i].alive { continue }
                let toCenter = center - particles[i].position
                let dist = length(toCenter)
                if dist > 0.001 && dist < threshold {
                    let dir = toCenter / dist
                    particles[i].velocity += dir * scale * dt * override
                }
            }
        }
    }
    
    private func createOscillateAlphaOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let fMin = oDef.frequencymin?.floatValue ?? 0.0
        let fMax = oDef.frequencymax?.floatValue ?? 0.0
        let sMin = oDef.scalemin?.floatValue ?? 1.0
        let sMax = oDef.scalemax?.floatValue ?? 1.0
        let pMin = oDef.phasemin?.floatValue ?? 0.0
        let pMax = oDef.phasemax?.floatValue ?? 0.0
        return { [weak self] particles, count, cps, time, dt in
            guard self != nil else { return }
            for i in 0..<count {
                if !particles[i].oscillateAlpha.initialized {
                    particles[i].oscillateAlpha.frequency = Float.random(in: min(fMin, fMax)...max(fMin, fMax))
                    particles[i].oscillateAlpha.scale = Float.random(in: min(sMin, sMax)...max(sMin, sMax))
                    particles[i].oscillateAlpha.phase = Float.random(in: min(pMin, pMax)...max(pMin, pMax)) + 2.0 * .pi
                    particles[i].oscillateAlpha.base = particles[i].alpha
                    particles[i].oscillateAlpha.initialized = true
                }
                let w = particles[i].oscillateAlpha.frequency
                let t = particles[i].age
                let cosVal = (cos(w * t + particles[i].oscillateAlpha.phase) + 1.0) * 0.5
                let mul = sMin + cosVal * (sMax - sMin)
                particles[i].alpha = particles[i].oscillateAlpha.base * mul
            }
        }
    }
    
    private func createOscillateSizeOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let fMin = oDef.frequencymin?.floatValue ?? 0.0
        let fMax = oDef.frequencymax?.floatValue ?? 0.0
        let sMin = oDef.scalemin?.floatValue ?? 1.0
        let sMax = oDef.scalemax?.floatValue ?? 1.0
        let pMin = oDef.phasemin?.floatValue ?? 0.0
        let pMax = oDef.phasemax?.floatValue ?? 0.0
        return { [weak self] particles, count, cps, time, dt in
            guard self != nil else { return }
            for i in 0..<count {
                if !particles[i].oscillateSize.initialized {
                    particles[i].oscillateSize.frequency = Float.random(in: min(fMin, fMax)...max(fMin, fMax))
                    particles[i].oscillateSize.scale = Float.random(in: min(sMin, sMax)...max(sMin, sMax))
                    particles[i].oscillateSize.phase = Float.random(in: min(pMin, pMax)...max(pMin, pMax)) + 2.0 * .pi
                    particles[i].oscillateSize.base = particles[i].size
                    particles[i].oscillateSize.initialized = true
                }
                let w = particles[i].oscillateSize.frequency
                let t = particles[i].age
                let cosVal = (cos(w * t + particles[i].oscillateSize.phase) + 1.0) * 0.5
                let mul = sMin + cosVal * (sMax - sMin)
                particles[i].size = particles[i].oscillateSize.base * mul
            }
        }
    }
    
    private func createOscillatePositionOperator(oDef: ParticleOperatorDef) -> OperatorFunc {
        let fMin = oDef.frequencymin?.floatValue ?? 0.0
        let fMax = oDef.frequencymax?.floatValue ?? 0.0
        let sMin = oDef.scalemin?.floatValue ?? 1.0
        let sMax = oDef.scalemax?.floatValue ?? 1.0
        let pMin = oDef.phasemin?.floatValue ?? 0.0
        let pMax = oDef.phasemax?.floatValue ?? 0.0
        let mask = oDef.mask?.float3Value ?? SIMD3<Float>(1, 1, 1)
        return { [weak self] particles, count, cps, time, dt in
            guard let self = self else { return }
            let override = self.getOverrideValue(key: "speed", defaultValue: 1.0)
            for i in 0..<count {
                if !particles[i].oscillatePosition.initialized {
                    for axis in 0..<3 {
                        particles[i].oscillatePosition.frequency[axis] = Float.random(in: min(fMin, fMax)...max(fMin, fMax))
                        particles[i].oscillatePosition.scale[axis] = Float.random(in: min(sMin, sMax)...max(sMin, sMax))
                        particles[i].oscillatePosition.phase[axis] = Float.random(in: min(pMin, pMax)...max(pMin, pMax)) + 2.0 * .pi
                    }
                    particles[i].oscillatePosition.initialized = true
                }
                let t = particles[i].age
                var delta = SIMD3<Float>(0, 0, 0)
                for axis in 0..<3 {
                    let w = 2.0 * .pi * particles[i].oscillatePosition.frequency[axis] / (2.0 * .pi)
                    let move = -particles[i].oscillatePosition.scale[axis] * w * sin(w * t + particles[i].oscillatePosition.phase[axis]) * dt
                    delta[axis] = move * mask[axis] * override
                }
                particles[i].position += delta
            }
        }
    }
}
