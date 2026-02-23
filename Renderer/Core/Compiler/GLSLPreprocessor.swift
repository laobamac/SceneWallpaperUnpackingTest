//
//  GLSLPreprocessor.swift
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

import Foundation

class GLSLPreprocessor {
    static func preprocess(source: String, isVertex: Bool) -> String {
        let commonHeader = """
        #version 330 core
        #define CAST3(x) vec3(x)
        #define CAST4(x) vec4(x)
        #define frac(x) fract(x)
        #define lerp(x, y, z) mix(x, y, z)
        #define mul(x, y) ((x) * (y))
        #define tex2D(sampler, uv) texture(sampler, uv)
        uniform float g_Time;
        uniform vec2 g_PointerPosition;
        uniform vec2 g_Resolution;
        """

        let vertexHeader = """
        layout(location = 0) in vec3 a_Position;
        layout(location = 1) in vec2 a_TexCoord;
        layout(location = 2) in vec4 a_Color;
        out vec2 v_TexCoord;
        out vec4 v_Color;
        uniform mat4 g_ModelViewProjectionMatrix;
        """

        let fragmentHeader = """
        in vec2 v_TexCoord;
        in vec4 v_Color;
        out vec4 o_FragColor;
        """

        var result = commonHeader + "\n"
        if isVertex {
            result += vertexHeader + "\n"
        } else {
            result += fragmentHeader + "\n"
        }

        result += source.replacingOccurrences(of: "gl_FragColor", with: "o_FragColor")
        return result
    }
}
