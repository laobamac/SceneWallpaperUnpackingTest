//
//  ShadercWrapper.mm
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

#import "ShadercWrapper.h"
#import <shaderc/shaderc.hpp>

@implementation ShadercWrapper

+ (nullable NSData *)compileGLSLToSPIRV:(NSString *)glslSource
                               isVertex:(BOOL)isVertex
                                  error:(NSError **)error {
    shaderc::Compiler compiler;
    shaderc::CompileOptions options;
    options.SetOptimizationLevel(shaderc_optimization_level_performance);

    shaderc_shader_kind kind = isVertex ? shaderc_vertex_shader : shaderc_fragment_shader;
    std::string source = [glslSource UTF8String];

    shaderc::SpvCompilationResult module = compiler.CompileGlslToSpv(
        source, kind, "shader.glsl", options);

    if (module.GetCompilationStatus() != shaderc_compilation_status_success) {
        if (error) {
            NSString *errorMessage = [NSString stringWithUTF8String:module.GetErrorMessage().c_str()];
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: errorMessage };
            *error = [NSError errorWithDomain:@"ShadercErrorDomain" code:1 userInfo:userInfo];
        }
        return nil;
    }

    std::vector<uint32_t> spirv(module.cbegin(), module.cend());
    return [NSData dataWithBytes:spirv.data() length:spirv.size() * sizeof(uint32_t)];
}

@end
