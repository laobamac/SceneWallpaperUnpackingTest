//
//  EffectShimmer.metal
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

struct ShimmerUniforms {
    float4 color;
    float g_Time;
    float speed;
    float brightness;
    float granularity;
    float direction;
    float offset;
    float delay;
    float padding;
};

fragment float4 shimmer_frag(EffectVertexOut in [[stage_in]],
                             texture2d<float> sourceTex [[texture(0)]],
                             constant ShimmerUniforms& uniforms [[buffer(0)]],
                             sampler s [[sampler(0)]]) {
    float4 baseColor = sourceTex.sample(s, in.texCoord);
    if (baseColor.a == 0.0) return baseColor;

    float2 dir = float2(cos(uniforms.direction), sin(uniforms.direction));
    float pos = dot(in.texCoord, dir) * uniforms.granularity;
    float timeMod = fmod(uniforms.g_Time * uniforms.speed, uniforms.delay + 1.0);
    
    float shimmer = max(0.0, 1.0 - abs(pos - timeMod + uniforms.offset) * 5.0);
    float4 finalColor = baseColor;
    finalColor.rgb += uniforms.color.rgb * shimmer * uniforms.brightness * baseColor.a;
    
    return finalColor;
}
