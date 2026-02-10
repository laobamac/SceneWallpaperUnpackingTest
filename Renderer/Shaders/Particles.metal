//
//  Particles.metal
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

#include <metal_stdlib>
#include "Particles.h"

using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

vertex VertexOut vertex_particle(uint vertexID [[vertex_id]],
                                 constant ParticleVertex *vertices [[buffer(0)]],
                                 constant ParticleUniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    ParticleVertex v = vertices[vertexID];
    
    float3 center = v.position;
    float2 corner = v.texData.xy;
    float rotation = v.texData.z;
    float size = v.texData.w;
    
    float c = cos(rotation);
    float s = sin(rotation);
    float2x2 rotMat = float2x2(c, -s, s, c);
    
    float2 offset = (corner - 0.5) * size;
    offset = rotMat * offset;
    
    float4 worldPos = uniforms.modelMatrix * float4(center, 1.0);
    float4 viewPos = uniforms.viewMatrix * worldPos;
    viewPos.xy += offset;
    
    out.position = uniforms.projectionMatrix * viewPos;
    out.texCoord = float2(corner.x, 1.0 - corner.y);
    out.color = v.color;
    
    return out;
}

fragment float4 fragment_particle(VertexOut in [[stage_in]],
                                  texture2d_array<float> texture [[texture(0)]],
                                  sampler textureSampler [[sampler(0)]],
                                  constant float &animFrame [[buffer(2)]]) {
    uint slice = uint(animFrame);
    if (slice >= texture.get_array_size()) {
        slice = 0;
    }
    float4 color = texture.sample(textureSampler, in.texCoord, slice);
    return color * in.color;
}
