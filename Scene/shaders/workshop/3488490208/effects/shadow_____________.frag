// [COMBO] {"material":"ui_editor_properties_blend_mode","combo":"BLENDMODE","type":"imageblending","default":0}
// [COMBO] {"material":"ui_editor_properties_mask","combo":"MASK","type":"options","default":0}

#include "common.h"
#include "common_blending.h"

uniform vec3 u_Color; // {"default":"0 0 0","label":"Color","material":"shadowColor","type":"color"}
uniform float u_shadowDrawBorder; // {"material":"shadowDrawBorder","label":"shadowDrawBorder/阴影边距","default":0.5,"range":[0,1]}

varying vec4 v_TexCoord;
varying vec2 v_ReflectedCoord;

uniform sampler2D g_Texture0; // {"hidden":true}
uniform sampler2D g_Texture1; // {"label":"ui_editor_properties_mask","mode":"opacitymask","combo":"MASK","paintdefaultcolor":"0 0 0 1"}

uniform float g_ReflectionAlpha; // {"material":"alpha","label":"ui_editor_properties_alpha","default":0.5,"range":[0.0, 1]}

void main() {
    vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
    vec4 reflected = texSample2D(g_Texture0, v_ReflectedCoord);

    #if MASK
        float mask = texSample2D(g_Texture1, v_TexCoord.zw).r;
    #else
        float mask = 1.0;
    #endif

    if (albedo.a > u_shadowDrawBorder) {
        gl_FragColor = albedo;
    } else if (reflected.a > 0.0) {
        gl_FragColor.rgb = ApplyBlending(BLENDMODE, albedo.rgb, u_Color.rgb, g_ReflectionAlpha * mask);
        gl_FragColor.a = min(1.0, albedo.a + reflected.a * g_ReflectionAlpha * mask);
    } else {
        gl_FragColor = albedo;
    }
}