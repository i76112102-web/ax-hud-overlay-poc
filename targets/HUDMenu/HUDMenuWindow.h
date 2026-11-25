//
//  HUDMenuWindow.h
//  悬浮 HUD 的承载窗口
//
//  对应样本 `mjh763hgxc`（UIWindow 子类，37 个方法）：
//    _isWindowServerHostingManaged / _isSecure / _shouldCreateContextAsSecure
//    _canBecomeKeyWindow / _isApplicationKeyWindow / _ignoresHitTest
//    configureHUDInteractionCanvas:compactAnchorView:
//    hudApplyFullScreenGeometry / hudApplyCompactGeometry
//
//  设计要点：
//   1. 层级要压过 UIAlertView，否则被系统弹窗盖住
//   2. 不能变成 key window，否则抢走宿主 App 的键盘焦点
//   3. secure 状态可控 —— 开了之后窗口内容不会被截屏/录屏采集
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HUDMenuWindow : UIWindow

/// 防截屏开关。YES 时窗口内容在截图/录屏里会变成黑色/空白。
@property (nonatomic, assign) BOOL secureEnabled;

/// 过直播开关。YES 时一旦检测到屏幕被捕获（录屏/直播/投屏），本窗口自动隐藏；
/// 捕获结束后恢复。
@property (nonatomic, assign) BOOL captureHidden;

/// 创建并挂到一个 windowScene 上，不抢 key window
+ (instancetype)attachToScene:(UIWindowScene *)scene;

/// 手动触发一次捕获态检查（系统通知之外，用户点开关时也可立即生效）
- (void)refreshCaptureState;

@end

NS_ASSUME_NONNULL_END
