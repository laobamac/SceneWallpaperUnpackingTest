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

    float3 linearBase = pow(baseColor.rgb, float3(2.2));

    float mixFactor = in.texCoord.x * uniforms.amount;
    
    if (uniforms.oscillate > 0.0) {
        mixFactor += sin(uniforms.g_Time * uniforms.hueSpeed) * 0.5 + 0.5;
    } else {
        mixFactor += uniforms.g_Time * uniforms.hueSpeed;
    }
    
    mixFactor = abs(fract(mixFactor * 0.5) * 2.0 - 1.0);
    
    float3 linearC1 = pow(uniforms.color1.rgb, float3(2.2));
    float3 linearC2 = pow(uniforms.color2.rgb, float3(2.2));
    
    float3 gradColor = mix(linearC1, linearC2, mixFactor);
    
    float3 premultipliedGrad = gradColor * baseColor.a;
    float3 finalLinear = mix(linearBase, premultipliedGrad, uniforms.opacity);
    
    float4 finalColor = float4(pow(finalLinear, float3(1.0 / 2.2)), baseColor.a);
    
    return finalColor;
}
