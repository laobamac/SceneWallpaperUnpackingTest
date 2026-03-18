//
//  Particle.metal
//  Renderer
//
//  Created by laobamac on 2026/3/19.
//

#include <metal_stdlib>
using namespace metal;

struct GlobalUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float time;
    float padding;
};

struct ParticleInstanceData {
    packed_float3 position;
    float size;
    packed_float3 color;
    float alpha;
    packed_float3 rotation;
    float padding;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex VertexOut particle_vertex(uint vertexID [[vertex_id]],
                                 uint instanceID [[instance_id]],
                                 constant GlobalUniforms &globals [[buffer(1)]],
                                 device const ParticleInstanceData *instances [[buffer(2)]]) {
    VertexOut out;
    ParticleInstanceData inst = instances[instanceID];
    
    float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    
    float2 offsets[4] = {
        float2(-0.5, -0.5),
        float2( 0.5, -0.5),
        float2(-0.5,  0.5),
        float2( 0.5,  0.5)
    };
    
    float2 uv = uvs[vertexID];
    float2 offset = offsets[vertexID] * inst.size;
    
    float c = cos(inst.rotation[2]);
    float s = sin(inst.rotation[2]);
    float2 rotatedOffset = float2(
        offset.x * c - offset.y * s,
        offset.x * s + offset.y * c
    );
    
    float3 worldPos = inst.position;
    float4 viewPos = globals.viewMatrix * float4(worldPos, 1.0);
    viewPos.xy += rotatedOffset;
    
    out.position = globals.projectionMatrix * viewPos;
    out.uv = uv;
    out.color = float4(inst.color, inst.alpha);
    
    return out;
}

fragment float4 particle_fragment(VertexOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  sampler texSampler [[sampler(0)]]) {
    float4 texColor = tex.sample(texSampler, in.uv);
    return texColor * in.color;
}
