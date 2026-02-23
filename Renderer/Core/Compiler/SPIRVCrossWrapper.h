//
//  SPIRVCrossWrapper.h
//  Renderer
//
//  Created by laobamac on 2026/2/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPIRVReflectionData : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) NSUInteger offset;
@property (nonatomic, assign) NSUInteger size;
@end

@interface SPIRVTranslationResult : NSObject
@property (nonatomic, strong) NSString *mslSource;
@property (nonatomic, strong) NSArray<SPIRVReflectionData *> *reflectionMap;
@end

@interface SPIRVCrossWrapper : NSObject

+ (nullable SPIRVTranslationResult *)translateSPIRVToMSL:(NSData *)spirvData
                                                isVertex:(BOOL)isVertex
                                                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
