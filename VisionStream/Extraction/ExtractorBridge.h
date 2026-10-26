#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Called only from OnDeviceExtractor's serial worker queue.
@interface VSExtractorBridge : NSObject
+ (nullable NSString *)resolveAddress:(NSString *)address error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
