//
//  EventDispatcher.swift
//  Renderer
//
//  Created by laobamac on 2026/2/26.
//

import Cocoa
import simd
import JavaScriptCore

class EventDispatcher {
    var renderables: [TextRenderable] = []
    private var hoveredRenderable: TextRenderable?
    private var draggedRenderable: TextRenderable?

    func update(mouseLocation: CGPoint, in view: NSView) {
        let localPoint = convertToLocal(point: mouseLocation, in: view)
        var hitRenderable: TextRenderable? = nil
        
        for renderable in renderables.reversed() {
            if renderable.checkHit(point: localPoint) {
                hitRenderable = renderable
                break
            }
        }
        
        if hitRenderable !== hoveredRenderable {
            if let hovered = hoveredRenderable {
                hovered.isHovered = false
                if let cursorLeave = hovered.scriptObject?.objectForKeyedSubscript("cursorLeave"), !cursorLeave.isUndefined {
                    cursorLeave.call(withArguments: [[]])
                }
            }
            
            hoveredRenderable = hitRenderable
            
            if let hit = hitRenderable {
                hit.isHovered = true
                if let cursorEnter = hit.scriptObject?.objectForKeyedSubscript("cursorEnter"), !cursorEnter.isUndefined {
                    cursorEnter.call(withArguments: [[]])
                }
            }
        }
        
        if let dragged = draggedRenderable, let context = dragged.jsEngine?.context {
            let jsEvent = JSValue(newObjectIn: context)
            jsEvent?.setValue(Vec3(Double(localPoint.x), Double(localPoint.y), 0), forProperty: "worldPosition")
            if let cursorMove = dragged.scriptObject?.objectForKeyedSubscript("cursorMove"), !cursorMove.isUndefined {
                cursorMove.call(withArguments: [jsEvent as Any])
            }
        }
    }

    func mouseDown(location: CGPoint, in view: NSView) {
        let localPoint = convertToLocal(point: location, in: view)
        for renderable in renderables.reversed() {
            if renderable.checkHit(point: localPoint) {
                draggedRenderable = renderable
                renderable.isDragging = true
                if let context = renderable.jsEngine?.context {
                    let jsEvent = JSValue(newObjectIn: context)
                    jsEvent?.setValue(Vec3(Double(localPoint.x), Double(localPoint.y), 0), forProperty: "worldPosition")
                    if let cursorDown = renderable.scriptObject?.objectForKeyedSubscript("cursorDown"), !cursorDown.isUndefined {
                        cursorDown.call(withArguments: [jsEvent as Any])
                    }
                }
                break
            }
        }
    }

    func mouseUp(location: CGPoint, in view: NSView) {
        if let dragged = draggedRenderable {
            let localPoint = convertToLocal(point: location, in: view)
            if let context = dragged.jsEngine?.context {
                let jsEvent = JSValue(newObjectIn: context)
                jsEvent?.setValue(Vec3(Double(localPoint.x), Double(localPoint.y), 0), forProperty: "worldPosition")
                if let cursorUp = dragged.scriptObject?.objectForKeyedSubscript("cursorUp"), !cursorUp.isUndefined {
                    cursorUp.call(withArguments: [jsEvent as Any])
                }
            }
            dragged.isDragging = false
            draggedRenderable = nil
        }
    }

    private func convertToLocal(point: CGPoint, in view: NSView) -> simd_float2 {
        let viewWidth = Float(view.bounds.width)
        let viewHeight = Float(view.bounds.height)
        let normalizedX = Float(point.x) / viewWidth
        let normalizedY = Float(point.y) / viewHeight
        let sceneWidth: Float = 3840.0
        let sceneHeight: Float = 2160.0
        return simd_float2(normalizedX * sceneWidth, (1.0 - normalizedY) * sceneHeight)
    }
}
