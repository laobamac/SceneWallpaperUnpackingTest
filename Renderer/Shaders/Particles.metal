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
    float3 rotation;
    float animationOffset;
};

struct ParticleVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
    float animationOffset;
};

float3x3 makeRotationMatrix(float3 r) {
    float cx = cos(r.x);
    float sx = sin(r.x);
    float cy = cos(r.y);
    float sy = sin(r.y);
    float cz = cos(r.z);
    float sz = sin(r.z);

    float3x3 rotX = float3x3(
        float3(1, 0, 0),
        float3(0, cx, sx),
        float3(0, -sx, cx)
    );

    float3x3 rotY = float3x3(
        float3(cy, 0, -sy),
        float3(0, 1, 0),
        float3(sy, 0, cy)
    );

    float3x3 rotZ = float3x3(
        float3(cz, sz, 0),
        float3(-sz, cz, 0),
        float3(0, 0, 1)
    );

    return rotZ * rotY * rotX;
}

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
    
    float2 rawPos2D = quadVertices[vertexID];
    float3 rawPos = float3(rawPos2D.x * instance.size.x, rawPos2D.y * instance.size.y, 0.0);
    
    float3x3 rotMat = makeRotationMatrix(instance.rotation);
    float3 localPos = rotMat * rawPos;
    
    float4 worldPos = object.modelMatrix * float4(instance.position + localPos, 1.0);
    float4 viewPos = globals.viewMatrix * worldPos;
    
    out.position = globals.projectionMatrix * viewPos;
    
    float2 uvs[] = {
        float2(0, 0),
        float2(1, 0),
        float2(0, 1),
        float2(1, 1)
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
