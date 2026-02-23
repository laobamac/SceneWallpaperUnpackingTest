//
//  ShadercWrapper.h
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ShadercWrapper : NSObject

+ (nullable NSData *)compileGLSLToSPIRV:(NSString *)glslSource
                               isVertex:(BOOL)isVertex
                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
