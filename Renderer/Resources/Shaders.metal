#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct PuppetVertexIn {
    float3 position  [[attribute(0)]];
    float2 texCoord  [[attribute(1)]];
    ushort4 joints   [[attribute(2)]];
    float4 weights   [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float2 localCoord;
};

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
    float4 padding;
};

struct PuppetUniforms {
    float4x4 bones[100];
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant GlobalUniforms &globals [[buffer(1)]],
                             constant ObjectUniforms &object [[buffer(2)]]) {
    VertexOut out;
    float4 pos = float4(in.position, 1.0);
    out.position = globals.projectionMatrix * globals.viewMatrix * object.modelMatrix * pos;
    out.texCoord = in.texCoord;
    out.localCoord = in.texCoord - 0.5;
    return out;
}

vertex VertexOut vertex_puppet(PuppetVertexIn in [[stage_in]],
                               constant GlobalUniforms &globals [[buffer(1)]],
                               constant ObjectUniforms &object [[buffer(2)]],
                               constant PuppetUniforms &puppet [[buffer(3)]])
{
    VertexOut out;
    
    float4x4 skinMatrix = float4x4(0.0);
    bool hasBones = false;
    for (int i = 0; i < 4; i++) {
        int boneIndex = int(in.joints[i]);
        float weight = in.weights[i];
        if (weight > 0.0) {
            skinMatrix += puppet.bones[boneIndex] * weight;
            hasBones = true;
        }
    }
    
    if (!hasBones) {
        skinMatrix = float4x4(1.0);
    }
    
    float4 pos = float4(in.position, 1.0);
    float4 localPos = skinMatrix * pos;
    float4 worldPos = object.modelMatrix * localPos;
    
    out.position = globals.projectionMatrix * globals.viewMatrix * worldPos;
    out.texCoord = in.texCoord;
    out.localCoord = in.texCoord - 0.5;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant GlobalUniforms &globals [[buffer(1)]],
                              constant ObjectUniforms &object [[buffer(2)]],
                              texture2d<float> baseTexture [[texture(0)]],
                              sampler textureSampler [[sampler(0)]])
{
    float4 color = baseTexture.sample(textureSampler, in.texCoord);
    color *= object.color;
    color.a *= object.alpha;
    return color;
}
