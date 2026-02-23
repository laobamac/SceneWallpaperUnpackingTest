//
//  Particles.metal
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

#include <metal_stdlib>
using namespace metal;

struct GlobalUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float time;
    float3 padding;
};

struct ObjectUniforms {
    float4x4 modelMatrix;
    float alpha;
    float4 color;
    float3 animInfo;
    float speed;
    float speedSecondary;
    float effectScale;
    float sunScale;
};

struct SpriteVertexIn {
    float4 position;
    float4 texCoordAndSize;
    float4 color;
    float4 velocityAndLifetime;
    float4 rotation;
};

struct RopeVertexIn {
    float4 positionAndSize;
    float4 endPosAndLength;
    float4 cp0AndTrailPos;
    float4 cp1AndSizeEnd;
    float4 colorEnd;
    float4 uv;
    float4 colorStart;
};

struct ParticleVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float lifetime;
};

vertex ParticleVertexOut particle_sprite_vertex(uint vertexID [[vertex_id]],
                                                constant SpriteVertexIn *vertices [[buffer(0)]],
                                                constant GlobalUniforms &globals [[buffer(1)]],
                                                constant ObjectUniforms &uniforms [[buffer(2)]],
                                                constant float4 &renderVar0 [[buffer(3)]],
                                                constant float4 &renderVar1 [[buffer(4)]]) {
    ParticleVertexOut out;
    SpriteVertexIn v = vertices[vertexID];
    
    float2 baseUV = v.texCoordAndSize.xy;
    float2 localPos = float2(baseUV.x - 0.5, 0.5 - baseUV.y);

    float s = sin(-v.texCoordAndSize.z);
    float c = cos(-v.texCoordAndSize.z);
    float2 rotatedPos = float2(localPos.x * c - localPos.y * s, localPos.x * s + localPos.y * c);

    float3 worldPos = v.position.xyz;
    worldPos.xy += rotatedPos * v.texCoordAndSize.w;

    float4 pos = uniforms.modelMatrix * float4(worldPos, 1.0);
    out.position = globals.projectionMatrix * globals.viewMatrix * pos;
    out.uv = baseUV;
    out.color = v.color * uniforms.color;
    out.color.a *= uniforms.alpha;
    out.lifetime = v.velocityAndLifetime.w;

    return out;
}

vertex ParticleVertexOut particle_rope_vertex(uint vertexID [[vertex_id]],
                                              constant RopeVertexIn *vertices [[buffer(0)]],
                                              constant GlobalUniforms &globals [[buffer(1)]],
                                              constant ObjectUniforms &uniforms [[buffer(2)]],
                                              constant float4 &renderVar0 [[buffer(3)]],
                                              constant float4 &renderVar1 [[buffer(4)]]) {
    ParticleVertexOut out;
    RopeVertexIn v = vertices[vertexID];

    float2 vertexUV = v.uv.xy;

    float3 dir = v.endPosAndLength.xyz - v.positionAndSize.xyz;
    if (length(dir) > 0.0001) {
        dir = normalize(dir);
    } else {
        dir = float3(1.0, 0.0, 0.0);
    }

    float3 normal = float3(-dir.y, dir.x, 0.0);
    if (length(normal) > 0.0001) {
        normal = normalize(normal);
    } else {
        normal = float3(0.0, 1.0, 0.0);
    }

    float width = (vertexUV.x > 0.5) ? v.cp1AndSizeEnd.w : v.positionAndSize.w;
    float offsetSign = (vertexUV.y > 0.5) ? 1.0 : -1.0;
    
    float3 worldPos = (vertexUV.x > 0.5) ? v.endPosAndLength.xyz : v.positionAndSize.xyz;
    worldPos += normal * (width * 0.5 * offsetSign);

    float4 pos = uniforms.modelMatrix * float4(worldPos, 1.0);
    out.position = globals.projectionMatrix * globals.viewMatrix * pos;
    
    float trailLength = v.endPosAndLength.w;
    float currentTrailPos = v.cp0AndTrailPos.w;
    if (vertexUV.x > 0.5) {
        currentTrailPos += 1.0;
    }
    
    out.uv = float2(currentTrailPos / max(trailLength, 1.0), vertexUV.y);
    out.color = (vertexUV.x > 0.5) ? v.colorEnd : v.colorStart;
    out.color *= uniforms.color;
    out.color.a *= uniforms.alpha;
    out.lifetime = 0.0;

    return out;
}

fragment float4 particle_fragment(ParticleVertexOut in [[stage_in]],
                                  texture2d_array<float> texArray [[texture(0)]],
                                  constant ObjectUniforms &uniforms [[buffer(2)]],
                                  constant float4 &renderVar1 [[buffer(4)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, mip_filter::linear, address::repeat);
    
    float4 texColor;
    if (renderVar1.z > 0.0) {
        if (texArray.get_array_size() > 1) {
            uint frames = texArray.get_array_size();
            uint currentFrame = clamp(uint(in.lifetime * float(frames)), 0u, frames - 1);
            texColor = texArray.sample(textureSampler, in.uv, currentFrame);
        } else {
            float frames = renderVar1.z;
            float frameWidth = renderVar1.x;
            float frameHeight = renderVar1.y;
            int cols = int(1.0 / frameWidth + 0.5);
            int currentFrame = clamp(int(in.lifetime * frames), 0, int(frames) - 1);
            if (cols <= 0) cols = 1;
            int col = currentFrame % cols;
            int row = currentFrame / cols;
            float2 uv = in.uv;
            uv.x = (uv.x + float(col)) * frameWidth;
            uv.y = (uv.y + float(row)) * frameHeight;
            texColor = texArray.sample(textureSampler, uv, 0);
        }
    } else {
        texColor = texArray.sample(textureSampler, in.uv, 0);
    }
    
    return texColor * in.color;
}
