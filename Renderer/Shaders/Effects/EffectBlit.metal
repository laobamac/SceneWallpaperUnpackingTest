//
//  EffectBlit.metal
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

fragment float4 effect_blit_fragment(EffectVertexOut in [[stage_in]],
                                     texture2d<float> sourceTex [[texture(0)]],
                                     sampler s [[sampler(0)]]) {
    return sourceTex.sample(s, in.texCoord);
}
