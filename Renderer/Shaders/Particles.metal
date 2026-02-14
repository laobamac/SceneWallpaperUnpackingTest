//
//  Particles.metal
//  Renderer
//
//  Created by laobamac on 2026/2/14.
//

#include <metal_stdlib>
using namespace metal;

struct GlobalUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float time;
    float3 padding;
};

struct ParticleVertex {
    float4 position [[attribute(0)]];
    float4 data [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct ParticleRopeVertex {
    float4 position [[attribute(0)]];
    float4 endPosition [[attribute(1)]];
    float4 cpStart [[attribute(2)]];
    float4 cpEnd [[attribute(3)]];
    float4 color [[attribute(4)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex VertexOut vertex_particle(
    const device ParticleVertex* vertices [[buffer(0)]],
    constant GlobalUniforms& globals [[buffer(1)]],
    constant float4x4& modelMatrix [[buffer(2)]],
    uint vid [[vertex_id]]
) {
    ParticleVertex in = vertices[vid];
    VertexOut out;
    
    float4 worldPos = modelMatrix * in.position;
    out.position = globals.projectionMatrix * globals.viewMatrix * worldPos;
    out.uv = in.data.xy;
    out.color = in.color;
    
    return out;
}

fragment float4 fragment_particle(
    VertexOut in [[stage_in]],
    texture2d<float> texture [[texture(0)]],
    sampler samplr [[sampler(0)]]
) {
    float4 texColor = texture.sample(samplr, in.uv);
    return texColor * in.color;
}

vertex VertexOut vertex_rope(
    const device ParticleRopeVertex* vertices [[buffer(0)]],
    constant GlobalUniforms& globals [[buffer(1)]],
    constant float4x4& modelMatrix [[buffer(2)]],
    uint vid [[vertex_id]]
) {
    ParticleRopeVertex in = vertices[vid];
    VertexOut out;
    
    float4 worldPos = modelMatrix * in.position;
    out.position = globals.projectionMatrix * globals.viewMatrix * worldPos;
    out.uv = float2(0.5, 0.5);
    out.color = in.color;
    
    return out;
}

fragment float4 fragment_rope(
    VertexOut in [[stage_in]],
    texture2d<float> texture [[texture(0)]],
    sampler samplr [[sampler(0)]]
) {
    return in.color;
}
