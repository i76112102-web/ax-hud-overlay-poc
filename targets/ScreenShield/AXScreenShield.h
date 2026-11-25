//
//  AXScreenShield.h
//  复现 AX Pro Max 1.5.3 的免越狱防截屏：secure text entry 护盾 + 捕获态遮罩
//
//  机制（与样本 Qm7Vx2Lp9R 同构）：
//    1) 一个全屏透明 UITextField，secureTextEntry = YES，置于最高 windowLevel。
//       系统在截图 / 录屏 / 镜像时会把 secure text entry 的 layer 子树剔除并
//       替换为不透明深色，因此整屏内容在截图中变黑。
//    2) 监听 UIScreenCapturedDidChangeNotification + 前后台/场景切换，
//       进入捕获态时再叠一层 CAGradientLayer + UIVisualEffectView 遮罩，
//       覆盖录屏与 AirPlay 镜像这两种 secure 层不处理的路径。
//    3) 前后台切换后重建护盾：secure canvas 在 resign 时会被 UIKit 回收。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AXScreenShield : UIWindow

/// 默认 YES。关掉可对比截图效果。
@property (nonatomic, assign) BOOL enabled;

+ (instancetype)shieldWithWindowScene:(nullable UIWindowScene *)scene;
- (void)install;
- (void)uninstall;

/// 捕获态遮罩是否正在显示（调试用）
@property (nonatomic, readonly) BOOL maskVisible;

@end

NS_ASSUME_NONNULL_END
