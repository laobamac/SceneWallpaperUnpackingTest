//
//  Particle.swift
//  Renderer
//
//  Created by laobamac on 2026/3/19.
//

import Foundation
import simd

struct ParticleInitValue {
    var color: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0)
    var alpha: Float = 1.0
    var size: Float = 20.0
    var lifetime: Float = 1.0
}

struct Particle {
    var position: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var color: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0)
    var alpha: Float = 1.0
    var size: Float = 20.0
    var lifetime: Float = 1.0
    
    var rotation: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var velocity: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var acceleration: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var angularVelocity: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var angularAcceleration: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    
    var mark_new: Bool = true
    var initValue: ParticleInitValue = ParticleInitValue()
}

struct ParticleControlpoint {
    var offset: SIMD3<Double> = SIMD3<Double>(0.0, 0.0, 0.0)
}

struct ParticleInfo {
    var particles: UnsafeMutableBufferPointer<Particle>
    var controlpoints: [ParticleControlpoint]
    var time: Double
    var time_pass: Double
}

class ParticleInstance {
    struct BoundedData {
        weak var parent: ParticleInstance?
        var particle_idx: Int = -1
        var pos: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
        var pre_lifetime_ok: Bool = true
    }
    
    private var m_is_death: Bool = false
    private var m_no_live_particle: Bool = false
    
    var particlesVec: [Particle] = []
    var boundedData: BoundedData = BoundedData()
    
    func refresh() {
        m_is_death = false
        m_no_live_particle = false
        boundedData = BoundedData()
        particlesVec.removeAll(keepingCapacity: true)
    }
    
    var isDeath: Bool {
        get { return m_is_death }
        set { m_is_death = newValue }
    }
    
    var isNoLiveParticle: Bool {
        get { return m_no_live_particle }
        set { m_no_live_particle = newValue }
    }
}
