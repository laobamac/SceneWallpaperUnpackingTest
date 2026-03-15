//
//  Particle.metal
//  Renderer
//
//  Created by laobamac on 2026/3/15.
//

#include <metal_stdlib>
using namespace metal;

struct GlobalUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float time;
    float3 padding;
};

struct ParticleInstanceData {
    float3 position;
    float2 size;
    float rotation;
    float4 color;
    float4 uvOffset;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

vertex VertexOut particle_vertex(uint vertexID [[vertex_id]],
                                 uint instanceID [[instance_id]],
                                 constant float* vertexData [[buffer(0)]],
                                 constant ParticleInstanceData* instanceData [[buffer(1)]],
                                 constant GlobalUniforms& globals [[buffer(2)]]) {
    
    VertexOut out;
    
    uint baseIndex = vertexID * 5;
    float3 localPos = float3(vertexData[baseIndex], vertexData[baseIndex+1], vertexData[baseIndex+2]);
    float2 baseUV = float2(vertexData[baseIndex+3], vertexData[baseIndex+4]);
    
    ParticleInstanceData inst = instanceData[instanceID];
    
    float c = cos(inst.rotation);
    float s = sin(inst.rotation);
    float2x2 rotMatrix = float2x2(c, -s, s, c);
    
    float2 scaledRotatedPos = rotMatrix * (localPos.xy * inst.size);
    float3 worldPos = float3(scaledRotatedPos.x + inst.position.x,
                             scaledRotatedPos.y + inst.position.y,
                             inst.position.z);
    
    out.position = globals.projectionMatrix * globals.viewMatrix * float4(worldPos, 1.0);
    
    float sequenceOffset = inst.uvOffset.x;
    float u = baseUV.x;
    float v = baseUV.y;
    
    if (inst.uvOffset.z > 0.0) {
        u = u + sequenceOffset;
    }
    
    out.texCoord = float2(u, v);
    out.color = inst.color;
    
    return out;
}

fragment float4 particle_fragment(VertexOut in [[stage_in]],
                                  texture2d<float> colorTexture [[texture(0)]]) {
    
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    if (is_null_texture(colorTexture)) {
        return in.color;
    }
    
    float4 texColor = colorTexture.sample(textureSampler, in.texCoord);
    return texColor * in.color;
}
