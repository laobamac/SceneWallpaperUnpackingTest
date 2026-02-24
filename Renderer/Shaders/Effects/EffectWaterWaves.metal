//
//  EffectWaterWaves.metal
//  Renderer
//
//  Created by laobamac on 2026/2/24.
//

#include <metal_stdlib>
using namespace metal;

constant bool hasMask [[function_constant(0)]];
constant bool dualWaves [[function_constant(1)]];
constant bool timeOffset [[function_constant(2)]];
constant bool perspective [[function_constant(3)]];

struct EffectVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex EffectVertexOut effect_blit_vertex(uint vertexID [[vertex_id]]) {
    EffectVertexOut out;
    float2 positions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = positions[vertexID] * 0.5 + 0.5;
    out.texCoord.y = 1.0 - out.texCoord.y;
    return out;
}

struct WaterWavesUniforms {
    float g_Time;
    float g_Speed;
    float g_Scale;
    float g_Exponent;
    float g_Strength;
    float g_Speed2;
    float g_Scale2;
    float g_Offset2;
    float g_Exponent2;
    float padding1;
    float padding2;
    float padding3;
};

fragment float4 waterwaves_frag(EffectVertexOut in [[stage_in]],
                                texture2d<float> g_Texture0 [[texture(0)]],
                                texture2d<float> g_Texture1 [[texture(1)]],
                                constant WaterWavesUniforms& uniforms [[buffer(0)]],
                                sampler sampler0 [[sampler(0)]]) {
    float mask = 1.0;
    if (hasMask) {
        mask = g_Texture1.sample(sampler0, in.texCoord).r;
    }

    float2 texCoord = in.texCoord;
    float2 texCoordMotion = texCoord;
    float2 v_Direction = float2(1.0, 0.0);
    float2 v_Direction2 = float2(0.0, 1.0);

    float distance = uniforms.g_Time * uniforms.g_Speed + dot(texCoordMotion, v_Direction) * uniforms.g_Scale;
    float distance2 = 0.0;
    
    if (dualWaves) {
        distance2 = (uniforms.g_Time + uniforms.g_Offset2) * uniforms.g_Speed2 + dot(texCoordMotion, v_Direction2) * uniforms.g_Scale2;
    }

    if (timeOffset && hasMask) {
        float timeOff = g_Texture1.sample(sampler0, in.texCoord).r * 1.57079632679;
        distance += timeOff;
        if (dualWaves) {
            distance2 += timeOff;
        }
    }

    float strength = uniforms.g_Strength * uniforms.g_Strength;
    float2 offset = float2(v_Direction.y, -v_Direction.x);
    float val1 = sin(distance);
    float s1 = sign(val1);
    val1 = pow(abs(val1), uniforms.g_Exponent);

    if (dualWaves) {
        float val2 = sin(distance2);
        float s2 = sign(val2);
        val2 = pow(abs(val2), uniforms.g_Exponent2);
        texCoord += val1 * s1 * val2 * s2 * offset * strength * mask;
    } else {
        texCoord += val1 * s1 * offset * strength * mask;
    }

    return g_Texture0.sample(sampler0, texCoord);
}
