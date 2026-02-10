//
//  Particles.metal
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

#include <metal_stdlib>
#include "Puppet.h"
using namespace metal;

struct ParticleVertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float3 rotation [[attribute(2)]];
    float  size     [[attribute(3)]];
    float4 color    [[attribute(4)]];
    float  frame    [[attribute(5)]];
    float3 velocity [[attribute(6)]];
};

struct ParticleVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

float4x4 makeRotation(float3 rot) {
    float cx = cos(rot.x), sx = sin(rot.x);
    float cy = cos(rot.y), sy = sin(rot.y);
    float cz = cos(rot.z), sz = sin(rot.z);
    
    float4x4 rx = float4x4(1,0,0,0, 0,cx,-sx,0, 0,sx,cx,0, 0,0,0,1);
    float4x4 ry = float4x4(cy,0,sy,0, 0,1,0,0, -sy,0,cy,0, 0,0,0,1);
    float4x4 rz = float4x4(cz,-sz,0,0, sz,cz,0,0, 0,0,1,0, 0,0,0,1);
    return rz * ry * rx;
}

vertex ParticleVertexOut particle_vertex(ParticleVertexIn in [[stage_in]],
                                         constant GlobalUniforms &globals [[buffer(1)]],
                                         constant ObjectUniforms &object [[buffer(2)]]) {
    ParticleVertexOut out;
    
    float3 pos = in.position;
    
    if (in.size > 1.0) {
        float4x4 rotMat = makeRotation(in.rotation);
        float2 offset = in.texCoord - 0.5;
        float3 offset3 = float3(offset.x, offset.y, 0.0) * in.size * 2.0;
        pos += (rotMat * float4(offset3, 1.0)).xyz;
    }
    
    float4 worldPos = object.modelMatrix * float4(pos, 1.0);
    out.position = globals.projectionMatrix * globals.viewMatrix * worldPos;
    out.texCoord = in.texCoord;
    out.color = in.color;
    return out;
}

fragment float4 particle_fragment(ParticleVertexOut in [[stage_in]],
                                  texture2d<float> baseTexture [[texture(0)]],
                                  sampler textureSampler [[sampler(0)]]) {
    float4 texColor = baseTexture.sample(textureSampler, in.texCoord);
    return texColor * in.color;
}
