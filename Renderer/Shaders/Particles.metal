//
//  Particles.metal
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

#include <metal_stdlib>

using namespace metal;

struct ParticleVertex {
    float4 positionAndSeed;
    float4 texData;
    float4 color;
    float4 normalAndAge;
};

struct ParticleUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float4x4 modelMatrix;
    float2 viewportSize;
    float time;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
    float seed;
    float3 normal;
    float age;
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
    out.normal = normalize((uniforms.modelMatrix * float4(v.normalAndAge.xyz, 0.0)).xyz);
    out.age = v.normalAndAge.w;
    
    return out;
}

fragment float4 fragment_particle(VertexOut in [[stage_in]],
                                  texture2d_array<float> texture [[texture(0)]],
                                  sampler textureSampler [[sampler(0)]],
                                  constant float &animFrame [[buffer(2)]]) {
    uint totalFrames = texture.get_array_size();
    
    float frameRate = 30.0;
    float currentFrame = in.age * frameRate;
    
    uint slice = uint(currentFrame) % totalFrames;
    
    float4 color = texture.sample(textureSampler, in.texCoord, slice);
    
    float3 lightDir = normalize(float3(0.5, 0.5, 1.0));
    float diffuse = abs(dot(in.normal, lightDir)) * 0.7 + 0.3;
    
    return color * in.color * float4(diffuse, diffuse, diffuse, 1.0);
}
