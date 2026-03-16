//
//  ParticleRenderableGeometry.swift
//  Renderer
//
//  Created by laobamac on 2026/3/17.
//

import Foundation
import MetalKit
import simd

extension ParticleRenderable {

    func buildGeometry() {
        if particleCount == 0 {
            activeIndexCount = 0
            return
        }

        inFlightSemaphore.wait()
        currentBufferIndex = (currentBufferIndex + 1) % 3

        if useRopeRenderer {
            buildRopeGeometry()
        } else {
            buildSpriteGeometry()
        }
    }

    private func catmullRom(
        p0: simd_float3,
        p1: simd_float3,
        p2: simd_float3,
        p3: simd_float3,
        t: Float
    ) -> simd_float3 {
        let t2 = t * t
        let t3 = t2 * t
        let term1 = 2.0 * p1
        let term2 = (-p0 + p2) * t
        let term3 = (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        let term4 = (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
        return 0.5 * (term1 + term2 + term3 + term4)
    }

    private func buildRopeGeometry() {
        let aliveCount = particleCount
        if aliveCount < 2 {
            activeIndexCount = 0
            inFlightSemaphore.signal()
            return
        }

        let numSegments = aliveCount - 1
        let subdivision = max(1, ropeSubdivision)
        let totalPoints = numSegments * subdivision + 1

        var splinePositions = [simd_float3](
            repeating: .zero,
            count: totalPoints
        )
        var splineSizes = [Float](repeating: 0.0, count: totalPoints)
        var splineColors = [simd_float4](repeating: .zero, count: totalPoints)

        for i in 0..<numSegments {
            let p1 = particles[i]
            let p2 = particles[i + 1]
            let p0 = (i > 0) ? particles[i - 1] : p1
            let p3 = (i + 2 < aliveCount) ? particles[i + 2] : p2

            for k in 0..<subdivision {
                let t = Float(k) / Float(subdivision)
                let idx = i * subdivision + k
                splinePositions[idx] = catmullRom(
                    p0: p0.position,
                    p1: p1.position,
                    p2: p2.position,
                    p3: p3.position,
                    t: t
                )
                splineSizes[idx] = RendererMath.lerp(
                    a: p1.size,
                    b: p2.size,
                    t: t
                )
                let c1 = simd_float4(p1.color, p1.alpha)
                let c2 = simd_float4(p2.color, p2.alpha)
                splineColors[idx] = mix(c1, c2, t: simd_float4(t, t, t, t))
            }
        }
        let pLast = particles[aliveCount - 1]
        splinePositions[totalPoints - 1] = pLast.position
        splineSizes[totalPoints - 1] = pLast.size
        splineColors[totalPoints - 1] = simd_float4(pLast.color, pLast.alpha)

        let totalSubSegments = totalPoints - 1
        let uvScale = ropeUVScale > 0.0 ? ropeUVScale : 1.0
        let trLength = Float(totalSubSegments) / uvScale + 1.0
        let usableLength = trLength - 1.0

        let useSmoothing =
            ropeUVSmoothing && uniformLifetimes && !ropeUVScrolling
        var cumulativeArcLength = [Float](repeating: 0.0, count: totalPoints)
        var totalArcLength: Float = 0.0

        if useSmoothing {
            for i in 1..<totalPoints {
                totalArcLength += length(
                    splinePositions[i] - splinePositions[i - 1]
                )
                cumulativeArcLength[i] = totalArcLength
            }
        }

        var scrollOffset: Float = 0.0
        if ropeUVScrolling && usableLength > 0.0 {
            scrollOffset = fmod(Float(time), 10000.0) * usableLength
        }

        let vBuffer = vertexBuffers[currentBufferIndex]
        let iBuffer = indexBuffers[currentBufferIndex]
        let vData = vBuffer.contents().bindMemory(
            to: Float.self,
            capacity: totalSubSegments * 4 * 26
        )
        let iData = iBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: totalSubSegments * 6
        )

        var vIdx = 0
        var iIdx = 0

        for s in 0..<totalSubSegments {
            let posStart = splinePositions[s]
            let posEnd = splinePositions[s + 1]
            let sizeStart = splineSizes[s]
            let sizeEnd = splineSizes[s + 1]
            let colorStart = splineColors[s]
            let colorEnd = splineColors[s + 1]
            let posPrev = (s > 0) ? splinePositions[s - 1] : posStart
            let posAfter =
                (s + 2 < totalPoints) ? splinePositions[s + 2] : posEnd

            var trailPosition: Float
            if useSmoothing && totalArcLength > 0.0 {
                trailPosition =
                    (cumulativeArcLength[s] / totalArcLength)
                    * Float(totalSubSegments)
            } else {
                trailPosition = Float(s)
            }
            trailPosition += scrollOffset

            let baseV = UInt32(vIdx / 26)

            let addVertex = { (u: Float, v: Float) in
                vData[vIdx + 0] = posStart.x
                vData[vIdx + 1] = posStart.y
                vData[vIdx + 2] = posStart.z
                vData[vIdx + 3] = sizeStart
                vData[vIdx + 4] = posEnd.x
                vData[vIdx + 5] = posEnd.y
                vData[vIdx + 6] = posEnd.z
                vData[vIdx + 7] = trLength
                vData[vIdx + 8] = posPrev.x
                vData[vIdx + 9] = posPrev.y
                vData[vIdx + 10] = posPrev.z
                vData[vIdx + 11] = trailPosition
                vData[vIdx + 12] = posAfter.x
                vData[vIdx + 13] = posAfter.y
                vData[vIdx + 14] = posAfter.z
                vData[vIdx + 15] = sizeEnd
                vData[vIdx + 16] = colorEnd.x
                vData[vIdx + 17] = colorEnd.y
                vData[vIdx + 18] = colorEnd.z
                vData[vIdx + 19] = colorEnd.w
                vData[vIdx + 20] = u
                vData[vIdx + 21] = v
                vData[vIdx + 22] = colorStart.x
                vData[vIdx + 23] = colorStart.y
                vData[vIdx + 24] = colorStart.z
                vData[vIdx + 25] = colorStart.w
                vIdx += 26
            }

            addVertex(0.0, 0.0)
            addVertex(1.0, 0.0)
            addVertex(1.0, 1.0)
            addVertex(0.0, 1.0)

            iData[iIdx + 0] = baseV + 0
            iData[iIdx + 1] = baseV + 1
            iData[iIdx + 2] = baseV + 2
            iData[iIdx + 3] = baseV + 2
            iData[iIdx + 4] = baseV + 3
            iData[iIdx + 5] = baseV + 0
            iIdx += 6
        }
        activeIndexCount = iIdx
    }

    private func buildSpriteGeometry() {
        let aliveCount = particleCount
        if aliveCount == 0 {
            activeIndexCount = 0
            inFlightSemaphore.signal()
            return
        }

        let vBuffer = vertexBuffers[currentBufferIndex]
        let iBuffer = indexBuffers[currentBufferIndex]
        let vData = vBuffer.contents().bindMemory(
            to: Float.self,
            capacity: aliveCount * 4 * 17
        )
        let iData = iBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: aliveCount * 6
        )

        var vIdx = 0
        var iIdx = 0

        for i in 0..<particleCount {
            let p = particles[i]
            if !p.alive { continue }

            var lifetimeVal = p.getLifetimePos()
            if spritesheetFrames > 0 && p.frame >= 0.0 {
                if particleDef.animationMode == "randomframe" {
                    lifetimeVal = (p.frame + 0.5) / Float(spritesheetFrames)
                } else {
                    lifetimeVal = p.frame / Float(spritesheetFrames)
                }
            }

            let baseV = UInt32(vIdx / 17)

            let addVertex = { (u: Float, v: Float) in
                vData[vIdx + 0] = p.position.x
                vData[vIdx + 1] = p.position.y
                vData[vIdx + 2] = p.position.z
                vData[vIdx + 3] = u
                vData[vIdx + 4] = v
                vData[vIdx + 5] = p.rotation.z
                vData[vIdx + 6] = p.size
                vData[vIdx + 7] = p.color.x
                vData[vIdx + 8] = p.color.y
                vData[vIdx + 9] = p.color.z
                vData[vIdx + 10] = p.alpha
                vData[vIdx + 11] = p.velocity.x
                vData[vIdx + 12] = p.velocity.y
                vData[vIdx + 13] = p.velocity.z
                vData[vIdx + 14] = lifetimeVal
                vData[vIdx + 15] = p.rotation.x
                vData[vIdx + 16] = p.rotation.y
                vIdx += 17
            }

            addVertex(0.0, 1.0)
            addVertex(1.0, 1.0)
            addVertex(1.0, 0.0)
            addVertex(0.0, 0.0)

            iData[iIdx + 0] = baseV + 0
            iData[iIdx + 1] = baseV + 1
            iData[iIdx + 2] = baseV + 2
            iData[iIdx + 3] = baseV + 2
            iData[iIdx + 4] = baseV + 3
            iData[iIdx + 5] = baseV + 0
            iIdx += 6
        }
        activeIndexCount = iIdx
    }
}
