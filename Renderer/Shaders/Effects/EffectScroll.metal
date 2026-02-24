//
//  EffectScroll.metal
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

struct ScrollUniforms {
    float speedx;
    float speedy;
    float repeatX;
    float repeatY;
};

fragment float4 scroll_frag(EffectVertexOut in [[stage_in]],
                            texture2d<float> sourceTex [[texture(0)]],
                            constant ScrollUniforms& uniforms [[buffer(0)]],
                            sampler s [[sampler(0)]]) {
    float2 uv = in.texCoord;
    uv.x = fmod(uv.x * uniforms.repeatX + uniforms.speedx, 1.0);
    uv.y = fmod(uv.y * uniforms.repeatY + uniforms.speedy, 1.0);
    if (uv.x < 0.0) uv.x += 1.0;
    if (uv.y < 0.0) uv.y += 1.0;
    return sourceTex.sample(s, uv);
}
