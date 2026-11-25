#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HUDWindow : UIWindow

@property (nonatomic, copy) void (^onTap)(void);

/// 创建并显示一个最高层的透明悬浮窗（带一个可拖动浮球）
+ (instancetype)showHUD;

@end

NS_ASSUME_NONNULL_END
