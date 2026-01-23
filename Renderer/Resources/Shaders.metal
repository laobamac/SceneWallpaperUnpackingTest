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

struct EffectParams {
    int type;
    int maskIndex;
    float speed;
    float scale;
    float strength;
    float exponent;
    float2 direction;
    float2 bounds;
    float2 friction;
};

enum EffectType {
    EffectTypeNone = 0,
    EffectTypeScroll = 1,
    EffectTypeWaterWave = 2,
    EffectTypeShake = 3,
    EffectTypeFoliageSway = 4,
    EffectTypeWaterRipple = 5
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
    
    // Skinning
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
                              constant EffectParams *effects [[buffer(3)]],
                              constant int &effectCount [[buffer(4)]],
                              texture2d<float> baseTexture [[texture(0)]],
                              array<texture2d<float>, 8> maskTextures [[texture(1)]],
                              sampler textureSampler [[sampler(0)]]) {
    
    float2 uv = in.texCoord;
    float2 originalUV = uv;
    
    for (int i = 0; i < effectCount; i++) {
        EffectParams e = effects[i];
        if (e.type == EffectTypeScroll) {
            float2 scrollOffset = float2(e.direction.x, e.direction.y) * globals.time * 0.1;
            uv = uv - scrollOffset;
            uv = uv - floor(uv);
        } else if (e.type == EffectTypeWaterWave) {
            float mask = 1.0;
            if (e.maskIndex >= 0 && e.maskIndex < 8) {
                mask = maskTextures[e.maskIndex].sample(textureSampler, originalUV).r;
            }
            float2 dir = e.direction;
            float distance = globals.time * e.speed + dot(uv, dir) * e.scale;
            float val = pow(abs(sin(distance)), e.exponent) * sign(sin(distance));
            uv += val * float2(dir.y, -dir.x) * e.strength * mask * 0.5;
        } else if (e.type == EffectTypeShake) {
            float mask = 1.0;
            if (e.maskIndex >= 0 && e.maskIndex < 8) {
                mask = maskTextures[e.maskIndex].sample(textureSampler, originalUV).r;
            }
            float2 noise = float2(sin(globals.time * e.speed), cos(globals.time * e.speed * 0.8));
            uv += noise * e.strength * mask * 0.02;
        } else if (e.type == EffectTypeFoliageSway) {
            // FoliageSway
            float mask = 1.0;
            if (e.maskIndex >= 0 && e.maskIndex < 8) {
                mask = maskTextures[e.maskIndex].sample(textureSampler, originalUV).r;
            }
            float t = globals.time * e.speed;
            float spatial = (originalUV.x + originalUV.y) / max(e.scale, 0.001);
            float val = sin(t + spatial + e.exponent);
            
            uv += e.direction * val * e.strength * mask * 0.005;
        } else if (e.type == EffectTypeWaterRipple) {
            // WaterRipple Logic
            float mask = 1.0;
            if (e.maskIndex >= 0 && e.maskIndex < 8) {
                mask = maskTextures[e.maskIndex].sample(textureSampler, originalUV).r;
            }
            
            float3 normal = float3(0.5, 0.5, 1.0);
            int normalIdx = e.maskIndex + 1;
            
            if (normalIdx >= 0 && normalIdx < 8) {
                float activeSpeed = e.speed + e.friction.x;
                float2 scroll = e.direction * globals.time * activeSpeed;
                float2 normalUV = originalUV * e.scale + scroll;
                normal = maskTextures[normalIdx].sample(textureSampler, normalUV).rgb;
            }
            
            float2 offset = (normal.xy * 2.0 - 1.0) * e.strength * mask * 0.1;
            uv += offset;
        }
    }
    
    float4 color = baseTexture.sample(textureSampler, uv);
    color *= object.color;
    
    color.a *= object.alpha;
    
    if (color.a < 0.01) discard_fragment();
    
    return color;
}
