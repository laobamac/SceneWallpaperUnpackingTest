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
    float seed;
};

vertex VertexOut vertex_particle(uint vertexID [[vertex_id]],
                                 constant ParticleVertex *vertices [[buffer(0)]],
                                 constant ParticleUniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    ParticleVertex v = vertices[vertexID];
    
    float4 worldPos = uniforms.modelMatrix * float4(v.positionAndSeed.xyz, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    
    out.texCoord = v.texData.xy;
    out.color = v.color;
    out.seed = v.positionAndSeed.w;
    
    return out;
}

fragment float4 fragment_particle(VertexOut in [[stage_in]],
                                  texture2d_array<float> texture [[texture(0)]],
                                  sampler textureSampler [[sampler(0)]],
                                  constant float &animFrame [[buffer(2)]]) {
    uint totalFrames = texture.get_array_size();
    
    float randomOffset = fract(in.seed * 123.456) * float(totalFrames);
    float currentFrame = animFrame + randomOffset;
    
    uint slice = uint(currentFrame) % totalFrames;
    
    float4 color = texture.sample(textureSampler, in.texCoord, slice);
    return color * in.color;
}
