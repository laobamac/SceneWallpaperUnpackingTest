//
//  EffectSimpleAudioBars.metal
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

struct AudioBarsUniforms {
    float4 color;
    float g_Time;
    float barSpacing;
    float barCount;
    float opacity;
    float lowerBound;
    float upperBound;
    float blurX;
    float blurY;
};

fragment float4 audiobars_frag(EffectVertexOut in [[stage_in]],
                               texture2d<float> sourceTex [[texture(0)]],
                               texture2d<float> audioTex [[texture(1)]],
                               constant AudioBarsUniforms& uniforms [[buffer(0)]],
                               sampler s [[sampler(0)]]) {
    float2 uv = in.texCoord;
    float barIndex = floor(uv.x * uniforms.barCount);
    float barPos = fract(uv.x * uniforms.barCount);
    float barWidth = 1.0 - uniforms.barSpacing;
    float alpha = step(barPos, barWidth);
    
    float normalizedHeight = 1.0 - uv.y;
    float boundsMask = step(uniforms.lowerBound, normalizedHeight) * step(normalizedHeight, uniforms.upperBound);
    
    float audioSample = audioTex.sample(s, float2(uv.x, 0.5)).r;
    float heightMask = step(normalizedHeight, audioSample);
    
    float4 baseColor = sourceTex.sample(s, in.texCoord);
    float4 barColor = uniforms.color;
    barColor.a *= alpha * boundsMask * heightMask * uniforms.opacity;
    barColor.rgb *= barColor.a;
    
    return float4(baseColor.rgb * (1.0 - barColor.a) + barColor.rgb, baseColor.a * (1.0 - barColor.a) + barColor.a);
}
