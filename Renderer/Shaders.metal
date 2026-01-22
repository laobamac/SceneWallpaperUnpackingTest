#include <metal_stdlib>
using namespace metal;

// -------------------------------------------------------------------------
// 结构体定义
// -------------------------------------------------------------------------

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
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
    EffectTypeShake = 3
};

// -------------------------------------------------------------------------
// 顶点着色器
// -------------------------------------------------------------------------

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

// -------------------------------------------------------------------------
// 片元着色器
// -------------------------------------------------------------------------

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
    
    // ----------------------------------------------------
    // 特效处理
    // ----------------------------------------------------
    for (int i = 0; i < effectCount; i++) {
        EffectParams e = effects[i];
        
        // --- SCROLL (滚动) ---
        if (e.type == EffectTypeScroll) {
            float2 scrollOffset = float2(e.direction.x, e.direction.y) * globals.time * 0.1; // 降低速度系数
            uv = uv - scrollOffset; // 减去偏移以模拟纹理移动
            uv = uv - floor(uv);    // 保持在 0-1
        }
        
        // --- WATERWAVE (水波纹) ---
        else if (e.type == EffectTypeWaterWave) {
            float mask = 1.0;
            if (e.maskIndex >= 0 && e.maskIndex < 8) {
                mask = maskTextures[e.maskIndex].sample(textureSampler, originalUV).r;
            }
            
            float2 dir = e.direction;
            float2 texCoordMotion = uv;
            
            float distance = globals.time * e.speed + dot(texCoordMotion, dir) * e.scale;
            float val = sin(distance);
            float s = sign(val);
            val = pow(abs(val), e.exponent);
            
            float2 offsetDir = float2(dir.y, -dir.x);
            float strength = e.strength * e.strength * 0.5; // 降低强度
            
            uv += val * s * offsetDir * strength * mask;
        }
        
        // --- SHAKE (修复抽搐问题) ---
        else if (e.type == EffectTypeShake) {
            float mask = 1.0;
            if (e.maskIndex >= 0 && e.maskIndex < 8) {
                mask = maskTextures[e.maskIndex].sample(textureSampler, originalUV).r;
            }
            
            // 修复：使用平滑的 sin 函数代替 fract，消除回弹抽搐
            float time = globals.time * e.speed;
            
            // 生成平滑的随机感运动
            float2 noise = float2(
                sin(time),
                cos(time * 0.8)
            );
            
            // 应用摩擦力和边界 (简化版)
            noise *= e.strength * mask;
            
            // 对 UV 进行偏移
            uv += noise * 0.02; // 限制最大幅度
        }
    }
    
    float4 color = baseTexture.sample(textureSampler, uv);
    color *= object.color;
    color.a *= object.alpha;
    
    if (color.a < 0.01) discard_fragment();
    
    return color;
}
