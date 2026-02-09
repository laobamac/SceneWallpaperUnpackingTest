//
//  Particles.metal
//  Renderer
//
//  Created by laobamac on 2026/2/8.
//

#include <metal_stdlib>
#include "Puppet.h"
using namespace metal;

struct ParticleInstance {
    float3 position;
    float4 color;
    float2 size;
    float rotation;
    float animationOffset;
};

struct ParticleVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
    float animationOffset;
};

vertex ParticleVertexOut vertex_particle(uint vertexID [[vertex_id]],
                                         uint instanceID [[instance_id]],
                                         constant GlobalUniforms &globals [[buffer(1)]],
                                         constant ObjectUniforms &object [[buffer(2)]],
                                         constant ParticleInstance *instances [[buffer(3)]])
{
    ParticleVertexOut out;
    ParticleInstance instance = instances[instanceID];
    
    float2 quadVertices[] = {
        float2(-0.5, -0.5),
        float2( 0.5, -0.5),
        float2(-0.5,  0.5),
        float2( 0.5,  0.5)
    };
    
    float2 rawPos = quadVertices[vertexID];
    
    float c = cos(instance.rotation);
    float s = sin(instance.rotation);
    float2 rotatedPos = float2(
        rawPos.x * c - rawPos.y * s,
        rawPos.x * s + rawPos.y * c
    );
    
    float2 scaledPos = rotatedPos * instance.size;
    
    float4 worldPos = object.modelMatrix * float4(instance.position, 1.0);
    float4 viewPos = globals.viewMatrix * worldPos;
    viewPos.xy += scaledPos;
    
    out.position = globals.projectionMatrix * viewPos;
    
    float2 uvs[] = {
        float2(0, 1),
        float2(1, 1),
        float2(0, 0),
        float2(1, 0)
    };
    out.texCoord = uvs[vertexID];
    out.color = instance.color * object.color;
    out.color.a *= object.alpha;
    out.animationOffset = instance.animationOffset;
    
    return out;
}

fragment float4 fragment_particle(ParticleVertexOut in [[stage_in]],
                                  constant GlobalUniforms &globals [[buffer(1)]],
                                  constant ObjectUniforms &object [[buffer(2)]],
                                  texture2d_array<float> textureArray [[texture(0)]],
                                  sampler textureSampler [[sampler(0)]])
{
    float numFrames = object.animInfo.x;
    float duration = object.animInfo.y;
    
    uint frameIndex = 0;
    
    if (numFrames > 1.0 && duration > 0.0) {
        float currentTime = globals.time + in.animationOffset;
        float progress = fmod(currentTime, duration) / duration;
        frameIndex = uint(progress * numFrames);
        if (frameIndex >= uint(numFrames)) {
            frameIndex = uint(numFrames) - 1;
        }
    }
    
    float4 texColor = textureArray.sample(textureSampler, in.texCoord, frameIndex);
    return texColor * in.color;
}
