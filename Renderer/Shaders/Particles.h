//
//  Particles.h
//  Renderer
//
//  Created by laobamac on 2026/2/10.
//

#ifndef Particles_h
#define Particles_h

#include <simd/simd.h>

struct ParticleVertex {
    vector_float4 positionAndSeed;
    vector_float4 texData;
    vector_float4 color;
};

struct ParticleUniforms {
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 modelMatrix;
    vector_float2 viewportSize;
    float time;
};

#endif
