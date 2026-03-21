//
//  Particles.metal
//  Renderer
//
//  Created by laobamac on 2026/3/21.
//

#include <metal_stdlib>
using namespace metal;

struct GlobalUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float time;
    float3 padding;
};

struct ParticleUniforms {
    float4x4 modelMatrix;
    float4x4 modelMatrixInverse;
    float4x4 mvpMatrix;
    float4x4 viewProjectionMatrix;
    float3 orientationUp;
    float3 orientationRight;
    float3 orientationForward;
    float3 viewUp;
    float3 viewRight;
    float3 eyePosition;
    float4 renderVar0;
    float4 renderVar1;
    float refractAmount;
    float overbright;
    float padding1;
    float padding2;
};

struct ParticleSpriteVertexIn {
    float3 position [[attribute(0)]];
    float4 texCoordVec4 [[attribute(1)]];
    float4 color [[attribute(2)]];
    float4 texCoordVec4C1 [[attribute(3)]];
    float2 texCoordC2 [[attribute(4)]];
};

struct ParticleVertexOut {
    float4 position [[position]];
    float2 texCoords;
    float4 color;
};

vertex ParticleVertexOut particleSpriteVertexShader(
    uint vertexID [[vertex_id]],
    constant float *vData [[buffer(0)]],
    constant GlobalUniforms &globals [[buffer(1)]],
    constant ParticleUniforms &particles [[buffer(2)]])
{
    ParticleVertexOut out;
    uint base = vertexID * 17;
    
    float3 pos = float3(vData[base+0], vData[base+1], vData[base+2]);
    float4 texCoordVec4 = float4(vData[base+3], vData[base+4], vData[base+5], vData[base+6]);
    float4 color = float4(vData[base+7], vData[base+8], vData[base+9], vData[base+10]);
    float4 texCoordVec4C1 = float4(vData[base+11], vData[base+12], vData[base+13], vData[base+14]);
    float2 texCoordC2 = float2(vData[base+15], vData[base+16]);
    
    float size = texCoordVec4.w;
    float2 uv = texCoordVec4.xy;
    float rotZ = texCoordVec4.z;
    
    float2 offset = (uv - 0.5) * size;
    float c = cos(rotZ);
    float s = sin(rotZ);
    float2x2 rotMat = float2x2(c, -s, s, c);
    offset = rotMat * offset;
    
    float3 worldPos = pos + particles.orientationRight * offset.x + particles.orientationUp * offset.y;
    worldPos = (particles.modelMatrix * float4(worldPos, 1.0)).xyz;
    
    out.position = globals.projectionMatrix * globals.viewMatrix * float4(worldPos, 1.0);
    
    float numFrames = particles.renderVar1.z;
    if (numFrames > 0.0) {
        float lifetime = texCoordVec4C1.w;
        float frameVal = lifetime * numFrames;
        float currentFrame = floor(frameVal);
        float cols = 1.0 / max(0.001, particles.renderVar1.x);
        float rows = 1.0 / max(0.001, particles.renderVar1.y);
        
        float2 frameSize = float2(1.0 / cols, 1.0 / rows);
        float frameX = fmod(currentFrame, cols);
        float frameY = floor(currentFrame / cols);
        
        uv = float2(frameX * frameSize.x + uv.x * frameSize.x, frameY * frameSize.y + uv.y * frameSize.y);
    }
    
    out.texCoords = uv;
    out.color = color;
    
    return out;
}

vertex ParticleVertexOut particleRopeVertexShader(
    uint vertexID [[vertex_id]],
    constant float *vData [[buffer(0)]],
    constant GlobalUniforms &globals [[buffer(1)]],
    constant ParticleUniforms &particles [[buffer(2)]])
{
    ParticleVertexOut out;
    uint base = vertexID * 26;
    
    float3 startPos = float3(vData[base+0], vData[base+1], vData[base+2]);
    float sizeStart = vData[base+3];
    float3 endPos = float3(vData[base+4], vData[base+5], vData[base+6]);
    float trailLength = vData[base+7];
    float3 prevPos = float3(vData[base+8], vData[base+9], vData[base+10]);
    float trailPos = vData[base+11];
    float3 nextPos = float3(vData[base+12], vData[base+13], vData[base+14]);
    float sizeEnd = vData[base+15];
    float4 colorEnd = float4(vData[base+16], vData[base+17], vData[base+18], vData[base+19]);
    float2 uv = float2(vData[base+20], vData[base+21]);
    float4 colorStart = float4(vData[base+22], vData[base+23], vData[base+24], vData[base+25]);
    
    float3 dir = normalize(endPos - startPos + float3(0.0001));
    float3 right = cross(particles.orientationForward, dir);
    if (length(right) > 0.0001) {
        right = normalize(right);
    } else {
        right = particles.orientationRight;
    }
    
    float offsetMag = (uv.x - 0.5) * sizeStart;
    float3 worldPos = startPos + right * offsetMag;
    worldPos = (particles.modelMatrix * float4(worldPos, 1.0)).xyz;
    
    out.position = globals.projectionMatrix * globals.viewMatrix * float4(worldPos, 1.0);
    out.texCoords = float2(uv.x, trailPos / max(1.0, trailLength - 1.0));
    out.color = colorStart;
    
    return out;
}

fragment float4 particleFragmentShader(
    ParticleVertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    sampler texSampler [[sampler(0)]],
    constant ParticleUniforms &particles [[buffer(2)]])
{
    float4 texColor = tex.sample(texSampler, in.texCoords);
    return texColor * in.color * particles.overbright;
}
