#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioKeepAlive : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
- (BOOL)isRunning;
@end

NS_ASSUME_NONNULL_END
