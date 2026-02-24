//
//  EffectLensFlareSun.metal
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

struct LensFlareSunUniforms {
    float4 color;
    float g_Time;
    float angle;
    float speed;
    float sunScale;
    float opacity;
    float scale;
    float rotationSpeed;
    float speedSecondary;
    float pointerSpeed;
    float positionOffsetX;
    float positionOffsetY;
    float padding;
};

fragment float4 lens_flare_sun_frag(EffectVertexOut in [[stage_in]],
                                    texture2d<float> sourceTex [[texture(0)]],
                                    constant LensFlareSunUniforms& uniforms [[buffer(0)]],
                                    sampler s [[sampler(0)]]) {
    float2 uv = in.texCoord - float2(0.5, 0.5) - float2(uniforms.positionOffsetX, uniforms.positionOffsetY);
    float dist = length(uv);
    float glow = exp(-dist * uniforms.sunScale) * uniforms.opacity;
    
    float4 baseColor = sourceTex.sample(s, in.texCoord);
    float4 flareColor = uniforms.color * glow;
    
    return baseColor + flareColor;
}
