//
//  EffectGradientColor.metal
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//

#include <metal_stdlib>
using namespace metal;

struct EffectVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct GradientColorUniforms {
    float4 color1;
    float4 color2;
    float g_Time;
    float opacity;
    float hueSpeed;
    float amount;
    float oscillate;
    float padding1;
    float padding2;
    float padding3;
};

fragment float4 gradient_color_frag(EffectVertexOut in [[stage_in]],
                                    texture2d<float> sourceTex [[texture(0)]],
                                    constant GradientColorUniforms& uniforms [[buffer(0)]],
                                    sampler s [[sampler(0)]]) {
    float4 baseColor = sourceTex.sample(s, in.texCoord);
    if (baseColor.a == 0.0) return baseColor;

    float mixFactor = in.texCoord.y * uniforms.amount;
    
    if (uniforms.oscillate > 0.0) {
        mixFactor += sin(uniforms.g_Time * uniforms.hueSpeed) * 0.5 + 0.5;
    } else {
        mixFactor += uniforms.g_Time * uniforms.hueSpeed;
    }
    
    mixFactor = fract(mixFactor);
    float4 gradColor = mix(uniforms.color1, uniforms.color2, mixFactor);
    
    float4 finalColor = baseColor;
    finalColor.rgb = mix(baseColor.rgb, gradColor.rgb, uniforms.opacity * baseColor.a);
    
    return finalColor;
}
