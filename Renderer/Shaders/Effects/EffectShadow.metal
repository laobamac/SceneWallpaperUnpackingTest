//
//  EffectShadow.metal
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

struct ShadowUniforms {
    float4 shadowColor;
    float4 shadowOffset;
    float alpha;
    float shadowDrawBorder;
    float padding1;
    float padding2;
};

fragment float4 shadow_frag(EffectVertexOut in [[stage_in]],
                            texture2d<float> sourceTex [[texture(0)]],
                            constant ShadowUniforms& uniforms [[buffer(0)]],
                            sampler s [[sampler(0)]]) {
    float4 baseColor = sourceTex.sample(s, in.texCoord);
    
    float2 offsetUV = in.texCoord - uniforms.shadowOffset.xy * 0.001;
    float shadowAlpha = sourceTex.sample(s, offsetUV).a;
    
    if (baseColor.a > 0.0) {
        return baseColor;
    }
    
    float4 outColor = uniforms.shadowColor;
    outColor.a = shadowAlpha * uniforms.alpha;
    
    return outColor;
}
