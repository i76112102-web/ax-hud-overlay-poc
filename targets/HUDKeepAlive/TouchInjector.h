#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchInjector : NSObject

+ (void)tapAt:(CGPoint)pt inView:(UIView *)view window:(UIWindow *)window;
+ (void)touchDownAt:(CGPoint)pt inView:(UIView *)view window:(UIWindow *)window;
+ (void)touchMoveAt:(CGPoint)pt inView:(UIView *)view window:(UIWindow *)window;
+ (void)touchUpAt:(CGPoint)pt inView:(UIView *)view window:(UIWindow *)window;

@end

NS_ASSUME_NONNULL_END
