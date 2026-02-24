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
                               constant AudioBarsUniforms& uniforms [[buffer(0)]],
                               sampler s [[sampler(0)]]) {
    float2 uv = in.texCoord;
    float barIndex = floor(uv.x * uniforms.barCount);
    float barPos = fract(uv.x * uniforms.barCount);
    float barWidth = 1.0 - uniforms.barSpacing;
    float alpha = step(barPos, barWidth);
    
    float normalizedHeight = uv.y;
    float boundsMask = step(uniforms.lowerBound, normalizedHeight) * step(normalizedHeight, uniforms.upperBound);
    
    float intensity = sin(uniforms.g_Time * 10.0 + barIndex) * 0.5 + 0.5;
    float heightMask = step(1.0 - normalizedHeight, intensity);
    
    float4 baseColor = sourceTex.sample(s, in.texCoord);
    float4 barColor = uniforms.color;
    barColor.a *= alpha * boundsMask * heightMask * uniforms.opacity;
    
    return mix(baseColor, barColor, barColor.a);
}
