//
//  SPIRVCrossWrapper.mm
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

#import "SPIRVCrossWrapper.h"
#import <spirv_cross/spirv_msl.hpp>

@implementation SPIRVReflectionData
@end

@implementation SPIRVTranslationResult
@end

@implementation SPIRVCrossWrapper

+ (nullable SPIRVTranslationResult *)translateSPIRVToMSL:(NSData *)spirvData
                                                isVertex:(BOOL)isVertex
                                                   error:(NSError **)error {
    try {
        const uint32_t* ptr = (const uint32_t*)spirvData.bytes;
        size_t wordCount = spirvData.length / sizeof(uint32_t);
        std::vector<uint32_t> spirv(ptr, ptr + wordCount);

        spirv_cross::CompilerMSL compiler(spirv);

        spirv_cross::CompilerMSL::Options options;
        options.set_msl_version(2, 1);
        if (isVertex) {
            options.flip_vert_y = true;
        }
        compiler.set_msl_options(options);

        std::string msl = compiler.compile();

        SPIRVTranslationResult *result = [[SPIRVTranslationResult alloc] init];
        result.mslSource = [NSString stringWithUTF8String:msl.c_str()];

        NSMutableArray<SPIRVReflectionData *> *reflectionMap = [NSMutableArray array];
        spirv_cross::ShaderResources resources = compiler.get_shader_resources();

        for (auto &resource : resources.uniform_buffers) {
            const spirv_cross::SPIRType &type = compiler.get_type(resource.base_type_id);
            unsigned memberCount = type.member_types.size();
            for (unsigned i = 0; i < memberCount; i++) {
                std::string memberName = compiler.get_member_name(type.self, i);
                size_t memberOffset = compiler.type_struct_member_offset(type, i);
                size_t memberSize = compiler.get_declared_struct_member_size(type, i);

                SPIRVReflectionData *data = [[SPIRVReflectionData alloc] init];
                data.name = [NSString stringWithUTF8String:memberName.c_str()];
                data.offset = memberOffset;
                data.size = memberSize;
                [reflectionMap addObject:data];
            }
        }
        result.reflectionMap = reflectionMap;
        return result;
    } catch (const std::exception& e) {
        if (error) {
            NSString *errorMessage = [NSString stringWithUTF8String:e.what()];
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: errorMessage };
            *error = [NSError errorWithDomain:@"SPIRVCrossErrorDomain" code:2 userInfo:userInfo];
        }
        return nil;
    }
}

@end
