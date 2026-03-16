//
//  Particle.metal
//  Renderer
//
//  Created by laobamac on 2026/3/17.
//

#include <metal_stdlib>
using namespace metal;

struct GlobalUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float time;
    float padding;
};

struct SpriteVertexIn {
    float3 position [[attribute(0)]];
    float4 uv_rotZ_size [[attribute(1)]];
    float4 color_alpha [[attribute(2)]];
    float4 vel_lifetime [[attribute(3)]];
    float2 rotX_rotY [[attribute(4)]];
};

struct SpriteVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float frame;
};

vertex SpriteVertexOut vertex_particle_sprite(SpriteVertexIn in [[stage_in]],
                                              constant GlobalUniforms &globals [[buffer(1)]]) {
    SpriteVertexOut out;
    
    float2 uv = in.uv_rotZ_size.xy;
    float rotZ = in.uv_rotZ_size.z;
    float size = in.uv_rotZ_size.w;
    
    float2 offset = (uv - 0.5) * size;
    
    float c = cos(rotZ);
    float s = sin(rotZ);
    float2 rotatedOffset = float2(
        offset.x * c - offset.y * s,
        offset.x * s + offset.y * c
    );
    
    float3 worldPos = in.position;
    float3 right = float3(globals.viewMatrix[0][0], globals.viewMatrix[1][0], globals.viewMatrix[2][0]);
    float3 up = float3(globals.viewMatrix[0][1], globals.viewMatrix[1][1], globals.viewMatrix[2][1]);
    
    worldPos += right * rotatedOffset.x + up * rotatedOffset.y;
    
    out.position = globals.projectionMatrix * globals.viewMatrix * float4(worldPos, 1.0);
    out.uv = uv;
    out.color = in.color_alpha;
    out.frame = in.vel_lifetime.w;
    
    return out;
}

fragment float4 fragment_particle_sprite(SpriteVertexOut in [[stage_in]],
                                         texture2d<float> tex2d [[texture(0)]],
                                         sampler sampler2d [[sampler(0)]]) {
    float2 finalUV = in.uv;
    float4 texColor = tex2d.sample(sampler2d, finalUV);
    return texColor * in.color;
}

struct RopeVertexIn {
    float4 posStart_sizeStart [[attribute(0)]];
    float4 posEnd_trailLength [[attribute(1)]];
    float4 prevPos_trailPos [[attribute(2)]];
    float4 afterPos_sizeEnd [[attribute(3)]];
    float4 colorEnd [[attribute(4)]];
    float2 uvs [[attribute(5)]];
    float4 colorStart [[attribute(6)]];
};

struct RopeVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex RopeVertexOut vertex_particle_rope(RopeVertexIn in [[stage_in]],
                                          constant GlobalUniforms &globals [[buffer(1)]]) {
    RopeVertexOut out;
    
    float3 pStart = in.posStart_sizeStart.xyz;
    float sStart = in.posStart_sizeStart.w;
    
    float3 pEnd = in.posEnd_trailLength.xyz;
    float3 pPrev = in.prevPos_trailPos.xyz;
    
    float3 dir = normalize(pEnd - pPrev);
    float3 forward = float3(globals.viewMatrix[0][2], globals.viewMatrix[1][2], globals.viewMatrix[2][2]);
    float3 right = normalize(cross(dir, forward));
    
    float u = in.uvs.x;
    float v = in.uvs.y;
    
    float offset = (u - 0.5) * sStart;
    float3 worldPos = pStart + right * offset;
    
    out.position = globals.projectionMatrix * globals.viewMatrix * float4(worldPos, 1.0);
    out.uv = in.uvs;
    out.color = in.colorStart;
    
    return out;
}

fragment float4 fragment_particle_rope(RopeVertexOut in [[stage_in]],
                                       texture2d<float> tex2d [[texture(0)]],
                                       sampler sampler2d [[sampler(0)]]) {
    float4 texColor = tex2d.sample(sampler2d, in.uv);
    return texColor * in.color;
}
