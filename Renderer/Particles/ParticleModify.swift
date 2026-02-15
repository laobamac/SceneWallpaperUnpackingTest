//
//  ParticleModify.swift
//  Renderer
//
//  Created by laobamac on 2026/2/14.
//

import simd
import Foundation

struct ParticleModify {
    
    @inline(__always) static func move(p: inout Particle, acc: SIMD3<Float>) {
        p.position += acc
    }
    
    @inline(__always) static func move(p: inout Particle, x: Float, y: Float, z: Float) {
        p.position += SIMD3<Float>(x, y, z)
    }
    
    @inline(__always) static func moveTo(p: inout Particle, pos: SIMD3<Float>) {
        p.position = pos
    }
    
    @inline(__always) static func moveTo(p: inout Particle, x: Float, y: Float, z: Float) {
        p.position = SIMD3<Float>(x, y, z)
    }
    
    @inline(__always) static func moveByTime(p: inout Particle, t: Float) {
        p.position += p.velocity * t
    }
    
    @inline(__always) static func moveMultiply(p: inout Particle, para: SIMD3<Float>) {
        p.position *= para
    }
    
    @inline(__always) static func applySign(p: inout Particle, x: Int32, y: Int32, z: Int32) {
        if x != 0 { p.position.x = abs(p.position.x) * Float(x) }
        if y != 0 { p.position.y = abs(p.position.y) * Float(y) }
        if z != 0 { p.position.z = abs(p.position.z) * Float(z) }
    }
    
    @inline(__always) static func changeLifetime(p: inout Particle, l: Float) {
        p.lifetime += l
    }
    
    @inline(__always) static func lifetimePos(p: Particle) -> Float {
        if p.lifetime < 0 { return 1.0 }
        return 1.0 - (p.lifetime / p.initValue.lifetime)
    }
    
    @inline(__always) static func lifetimePassed(p: Particle) -> Float {
        return p.initValue.lifetime - p.lifetime
    }
    
    @inline(__always) static func lifetimeOk(p: Particle) -> Bool {
        return p.lifetime > 0.0
    }
    
    @inline(__always) static func changeColor(p: inout Particle, c: SIMD3<Float>) {
        let rgb = SIMD3<Float>(p.color.x, p.color.y, p.color.z) + c
        p.color = SIMD4<Float>(rgb.x, rgb.y, rgb.z, p.color.w)
    }
    
    @inline(__always) static func changeColor(p: inout Particle, r: Float, g: Float, b: Float) {
        changeColor(p: &p, c: SIMD3<Float>(r, g, b))
    }
    
    @inline(__always) static func changeRotation(p: inout Particle, r: SIMD3<Float>) {
        p.rotation += r
    }
    
    @inline(__always) static func changeRotation(p: inout Particle, x: Float, y: Float, z: Float) {
        p.rotation += SIMD3<Float>(x, y, z)
    }
    
    @inline(__always) static func changeVelocity(p: inout Particle, v: SIMD3<Float>) {
        p.velocity += v
    }
    
    @inline(__always) static func changeVelocity(p: inout Particle, x: Float, y: Float, z: Float) {
        p.velocity += SIMD3<Float>(x, y, z)
    }
    
    @inline(__always) static func accelerate(p: inout Particle, acc: SIMD3<Float>, t: Float) {
        p.velocity += acc * t
    }
    
    @inline(__always) static func changeAngularVelocity(p: inout Particle, v: SIMD3<Float>) {
        p.angularVelocity += v
    }
    
    @inline(__always) static func angularAccelerate(p: inout Particle, acc: SIMD3<Float>, t: Float) {
        p.angularVelocity += acc * t
    }
    
    @inline(__always) static func rotate(p: inout Particle, r: SIMD3<Float>) {
        p.rotation += r
    }
    
    @inline(__always) static func rotateByTime(p: inout Particle, t: Float) {
        p.rotation += p.angularVelocity * t
    }
    
    @inline(__always) static func multiplyAlpha(p: inout Particle, a: Float) {
        p.color.w *= a
    }
    
    @inline(__always) static func multiplySize(p: inout Particle, s: Float) {
        p.size *= s
    }
    
    @inline(__always) static func multiplyColor(p: inout Particle, c: SIMD3<Float>) {
        p.color.x *= c.x
        p.color.y *= c.y
        p.color.z *= c.z
    }
    
    @inline(__always) static func multiplyVelocity(p: inout Particle, m: Float) {
        p.velocity *= m
    }
    
    @inline(__always) static func initLifetime(p: inout Particle, l: Float) {
        p.lifetime = l
        p.initValue.lifetime = l
    }
    
    @inline(__always) static func initSize(p: inout Particle, s: Float) {
        p.size = s
        p.initValue.size = s
    }
    
    @inline(__always) static func initAlpha(p: inout Particle, a: Float) {
        p.color.w = a
        p.initValue.color.w = a
    }
    
    @inline(__always) static func initColor(p: inout Particle, r: Float, g: Float, b: Float) {
        p.color.x = r
        p.color.y = g
        p.color.z = b
        p.initValue.color = p.color
    }
    
    @inline(__always) static func initVelocity(p: inout Particle, v: SIMD3<Float>) {
        p.velocity = v
    }
    
    @inline(__always) static func initVelocity(p: inout Particle, x: Float, y: Float, z: Float) {
        p.velocity = SIMD3<Float>(x, y, z)
    }
    
    @inline(__always) static func initAngularVelocity(p: inout Particle, v: SIMD3<Float>) {
        p.angularVelocity = v
    }
    
    @inline(__always) static func multiplyInitLifetime(p: inout Particle, m: Float) {
        p.lifetime *= m
        p.initValue.lifetime = p.lifetime
    }
    
    @inline(__always) static func multiplyInitAlpha(p: inout Particle, m: Float) {
        p.color.w *= m
        p.initValue.color.w = p.color.w
    }
    
    @inline(__always) static func multiplyInitSize(p: inout Particle, m: Float) {
        p.size *= m
        p.initValue.size = p.size
    }
    
    @inline(__always) static func multiplyInitColor(p: inout Particle, r: Float, g: Float, b: Float) {
        p.color.x *= r
        p.color.y *= g
        p.color.z *= b
        p.initValue.color = p.color
    }
    
    @inline(__always) static func reset(p: inout Particle) {
        p.color.w = p.initValue.color.w
        p.size = p.initValue.size
        p.color = p.initValue.color
    }
    
    @inline(__always) static func markOld(p: inout Particle) {
        p.markNew = false
    }
    
    @inline(__always) static func isNew(p: Particle) -> Bool {
        return p.markNew
    }
    
    @inline(__always) static func applyControlPointForce(p: inout Particle, center: SIMD3<Float>, amount: Float, threshold: Float, t: Float) {
        let diff = center - p.position
        let dist = length(diff)
        if dist > 0.001 {
            let dir = normalize(diff)
            var strength: Float = 0
            if dist < threshold {
                strength = 1.0 - (dist / threshold)
            }
            p.velocity += dir * amount * strength * t
        }
    }
}
