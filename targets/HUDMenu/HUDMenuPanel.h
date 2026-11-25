//
//  HUDMenuPanel.h
//  悬浮图标 + 菜单面板（对应样本 `mjfuey2a` 的 128 个方法里的交互部分）
//
//  两态几何，与样本一致：
//    compact   —— 一个小浮球，可拖动，吸附屏幕边缘
//    expanded  —— 展开菜单卡片，含 4 个功能项
//
//  菜单项文案取自样本 __AXTEXT.__ustring：
//    过直播-开 / 过直播-关
//    防截屏已开启 / 允许截屏
//    主题设置 · 菜单主题 · 色相 · 饱和度 · 亮度 · 恢复默认蓝色
//    退出HUD
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HUDMenuPanel : UIView

@property (nonatomic, readonly) BOOL expanded;

/// 点「退出HUD」
@property (nonatomic, copy, nullable) void (^onExit)(void);
/// 过直播开关变化
@property (nonatomic, copy, nullable) void (^onCaptureToggle)(BOOL on);
/// 防截屏开关变化
@property (nonatomic, copy, nullable) void (^onSecureToggle)(BOOL on);
/// 主题色变化（拖动色相/饱和度/亮度时实时回调）
@property (nonatomic, copy, nullable) void (^onThemeChange)(UIColor *color);

- (instancetype)initWithFrame:(CGRect)frame;

/// 外部状态回灌（比如窗口自己检测到捕获态变化）
- (void)setCaptureOn:(BOOL)on;
- (void)setSecureOn:(BOOL)on;

/// 屏幕方向变化后重算几何（对应样本 scheduleOrientationSynchronizationAfterAppSwitch）
- (void)syncGeometry;

/// 当前主题色
@property (nonatomic, readonly) UIColor *themeColor;

@end

NS_ASSUME_NONNULL_END
