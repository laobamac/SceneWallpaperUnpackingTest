//
//  ParticleShaders.metal
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

#include <metal_stdlib>
using namespace metal;

struct ParticleUniforms {
    float4x4 modelMatrix;
    float4x4 modelMatrixInverse;
    float4x4 mvpMatrix;
    float4x4 mvpMatrixInverse;
    float4x4 viewProjectionMatrix;
    float3 orientationUp;
    float3 orientationRight;
    float3 orientationForward;
    float3 viewUp;
    float3 viewRight;
    float3 eyePosition;
    float4 renderVar0;
    float4 renderVar1;
    float overbright;
    float padding1;
    float padding2;
    float padding3;
};

struct SpriteVertexIn {
    float3 position [[attribute(0)]];
    float4 texCoordVec4 [[attribute(1)]];
    float4 color [[attribute(2)]];
    float4 texCoordVec4C1 [[attribute(3)]];
    float2 texCoordC2 [[attribute(4)]];
};

struct RopeVertexIn {
    float4 positionVec4 [[attribute(0)]];
    float4 texCoordVec4 [[attribute(1)]];
    float4 texCoordVec4C1 [[attribute(2)]];
    float4 texCoordVec4C2 [[attribute(3)]];
    float4 texCoordVec4C3 [[attribute(4)]];
    float2 texCoordC4 [[attribute(5)]];
    float4 color [[attribute(6)]];
};

struct ParticleRasterizerData {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

vertex ParticleRasterizerData spriteParticleVertex(
    uint vertexID [[vertex_id]],
    const device SpriteVertexIn* vertices [[buffer(0)]],
    constant ParticleUniforms& uniforms [[buffer(2)]])
{
    ParticleRasterizerData out;
    SpriteVertexIn vin = vertices[vertexID];

    float2 localUV = vin.texCoordVec4.xy;
    float rotZ = vin.texCoordVec4.z;
    float size = vin.texCoordVec4.w;

    float2 centeredUV = localUV - float2(0.5, 0.5);

    float c = cos(rotZ);
    float s = sin(rotZ);
    float2 rotatedUV = float2(
        centeredUV.x * c - centeredUV.y * s,
        centeredUV.x * s + centeredUV.y * c
    );

    float3 localPos = rotatedUV.x * size * uniforms.orientationRight + rotatedUV.y * size * uniforms.orientationUp;
    float3 worldPos = vin.position + localPos;

    out.position = uniforms.mvpMatrix * float4(worldPos, 1.0);
    
    float frameWidth = uniforms.renderVar1.x;
    float frameHeight = uniforms.renderVar1.y;
    float numFrames = uniforms.renderVar1.z;
    
    if (numFrames > 0.0 && frameWidth > 0.0 && frameHeight > 0.0) {
        float lifetime = vin.texCoordVec4C1.w;
        float currentFrame = min(floor(lifetime * numFrames), numFrames - 1.0);
        int cols = int(1.0 / frameWidth);
        float frameX = fmod(currentFrame, float(cols));
        float frameY = floor(currentFrame / float(cols));
        
        out.texCoord = float2(
            (localUV.x + frameX) * frameWidth,
            (localUV.y + frameY) * frameHeight
        );
    } else {
        out.texCoord = localUV;
    }

    out.color = vin.color;
    return out;
}

vertex ParticleRasterizerData ropeParticleVertex(
    uint vertexID [[vertex_id]],
    const device RopeVertexIn* vertices [[buffer(0)]],
    constant ParticleUniforms& uniforms [[buffer(2)]])
{
    ParticleRasterizerData out;
    RopeVertexIn vin = vertices[vertexID];

    float3 posStart = vin.positionVec4.xyz;
    float sizeStart = vin.positionVec4.w;
    float3 posEnd = vin.texCoordVec4.xyz;
    float3 posPrev = vin.texCoordVec4C1.xyz;
    float trailPosition = vin.texCoordVec4C1.w;
    float3 posAfter = vin.texCoordVec4C2.xyz;
    float trailLength = vin.texCoordVec4.w;
    float2 localUV = vin.texCoordC4;

    float3 tangent1 = normalize(posEnd - posPrev);
    float3 tangent2 = normalize(posAfter - posStart);
    float3 tangent = mix(tangent1, tangent2, localUV.y);
    float3 currentCenter = mix(posStart, posEnd, localUV.y);
    float currentSize = mix(sizeStart, vin.texCoordVec4C2.w, localUV.y);
    float4 currentColor = mix(vin.color, vin.texCoordVec4C3, localUV.y);

    float3 eyeDir = normalize(uniforms.eyePosition - currentCenter);
    float3 right = normalize(cross(eyeDir, tangent));

    float signX = (localUV.x - 0.5) * 2.0;
    float3 offset = right * (currentSize * signX);
    float3 worldPos = currentCenter + offset;

    out.position = uniforms.mvpMatrix * float4(worldPos, 1.0);

    float vCoord = (trailPosition + localUV.y) / max(1.0, trailLength - 1.0);
    out.texCoord = float2(localUV.x, vCoord);

    out.color = currentColor;
    return out;
}

fragment float4 particleFragment(
    ParticleRasterizerData in [[stage_in]],
    texture2d<float> tex2D [[texture(0)]],
    sampler sampler2D [[sampler(0)]],
    constant ParticleUniforms& uniforms [[buffer(2)]])
{
    float4 texColor = tex2D.sample(sampler2D, in.texCoord);
    float4 finalColor = texColor * in.color;
    finalColor.rgb *= uniforms.overbright;
    return finalColor;
}
