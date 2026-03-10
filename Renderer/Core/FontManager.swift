//
//  FontManager.swift
//  Renderer
//
//  Created by laobamac on 2026/3/11.
//

import Foundation
import CoreText
import CoreGraphics
import AppKit

class FontManager {
    static let shared = FontManager()
    private var registeredFonts: [String: String] = [:]
    
    func registerFont(url: URL) -> String? {
        let path = url.path
        if let existing = registeredFonts[path] {
            return existing
        }
        guard let fontDataProvider = CGDataProvider(url: url as CFURL),
              let font = CGFont(fontDataProvider) else {
            return nil
        }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterGraphicsFont(font, &error) {
            if let postScriptName = font.postScriptName as String? {
                registeredFonts[path] = postScriptName
                return postScriptName
            }
        }
        return nil
    }
    
    func getFont(name: String, size: CGFloat) -> NSFont {
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    }
}
