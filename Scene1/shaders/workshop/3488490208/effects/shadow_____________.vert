#include "common.h"
#include "common_perspective.h"

uniform mat4 g_ModelViewProjectionMatrix;
uniform vec4 g_Texture1Resolution;

attribute vec3 a_Position;
attribute vec2 a_TexCoord;

varying vec4 v_TexCoord;
varying vec2 v_ReflectedCoord;

uniform vec3 u_ShadowOffset; // {"default":"2 -2 0","description":"x/y:偏移量 z:旋转角度(弧度)","label":"shadowOffset/阴影偏移","material":"shadowOffset"}

void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = a_TexCoord.xyxy;

    #if MASK
        v_TexCoord.z *= g_Texture1Resolution.z / g_Texture1Resolution.x;
        v_TexCoord.w *= g_Texture1Resolution.w / g_Texture1Resolution.y;
    #endif

    vec2 center = vec2(0.5, 0.5);
    vec2 delta = a_TexCoord - center;
    
    float sinRot = sin(u_ShadowOffset.z);
    float cosRot = cos(u_ShadowOffset.z);
    delta = vec2(
        delta.x * cosRot - delta.y * sinRot,
        delta.x * sinRot + delta.y * cosRot
    );
    
    delta += u_ShadowOffset.xy / 100.0;
    v_ReflectedCoord = center + delta;
}