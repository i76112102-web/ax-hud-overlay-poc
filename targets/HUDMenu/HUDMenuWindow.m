//
//  HUDMenuWindow.m
//

#import "HUDMenuWindow.h"

// 私有方法声明：只为让编译器知道签名，不提供实现（不会覆盖系统）
@interface UIWindow (AXPrivateSecure)
- (BOOL)_shouldCreateContextAsSecure;
- (BOOL)_isSecure;
- (BOOL)_isWindowServerHostingManaged;
- (BOOL)_ignoresHitTest;
@end

@interface HUDMenuWindow ()
@property (nonatomic, assign) BOOL systemCaptured;
@end

@implementation HUDMenuWindow

+ (instancetype)attachToScene:(UIWindowScene *)scene {
    HUDMenuWindow *w = [[HUDMenuWindow alloc] initWithWindowScene:scene];
    // AX Pro Max 1.5.3 静态实测真值（常量 VA 0x100CD5338，字节 00 00 00 40 D1 12 63 41）
    // syslog 铁证：Window did update windowLevel(10000000.0) 后持续 visible，
    // 期间目标 App 进前台仍不被摘除。此前的 3000 是错误值，从未对齐 AX。
    w.windowLevel = 10000010.0;
    w.backgroundColor = [UIColor clearColor];
    w.rootViewController = [UIViewController new];
    w.rootViewController.view.backgroundColor = [UIColor clearColor];
    [w setHidden:NO];       // 注意：不要用 makeKeyAndVisible，会抢焦点

    [[NSNotificationCenter defaultCenter] addObserver:w
                                             selector:@selector(onCapturedChanged:)
                                                 name:UIScreenCapturedDidChangeNotification
                                               object:nil];
    [w refreshCaptureState];
    return w;
}

#pragma mark - 窗口行为

// 不抢 key：宿主 App 的输入框、键盘不受影响
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)_canBecomeKeyWindow { return NO; }
- (BOOL)_isApplicationKeyWindow { return NO; }
- (BOOL)canBecomeFocused  { return NO; }

// 命中测试要放开，否则浮球收不到点击
- (BOOL)_ignoresHitTest { return NO; }

// 不交给 WindowServer 托管：不参与系统窗口管理，切后台不会被回收重排
- (BOOL)_isWindowServerHostingManaged { return NO; }

// 关键：secure 由我们控制，系统在创建渲染上下文时查这个值
- (BOOL)_shouldCreateContextAsSecure { return self.secureEnabled; }
- (BOOL)_isSecure { return self.secureEnabled; }

#pragma mark - 开关

- (void)setSecureEnabled:(BOOL)on {
    _secureEnabled = on;
    // iOS 只在创建 context 时读 _shouldCreateContextAsSecure，
    // 运行时改完要让 layer 重新挂载才生效：把根视图挪一下即可。
    UIView *v = self.rootViewController.view;
    CALayer *superlayer = v.layer.superlayer;
    [v.layer removeFromSuperlayer];
    if (superlayer) [superlayer addSublayer:v.layer];
}

- (void)setCaptureHidden:(BOOL)on {
    _captureHidden = on;
    [self applyCaptureState];
}

- (void)refreshCaptureState {
    BOOL captured = UIScreen.mainScreen.isCaptured;
    if (captured != self.systemCaptured) {
        self.systemCaptured = captured;
        [self applyCaptureState];
    }
}

- (void)onCapturedChanged:(NSNotification *)n {
    self.systemCaptured = UIScreen.mainScreen.isCaptured;
    [self applyCaptureState];
}

- (void)applyCaptureState {
    // 过直播：捕获态直接把自己从合成树摘掉。
    // 比 secure 更彻底 —— 录屏/直播/投屏走的是不同采集通路，
    // secure 只挡像素拷贝，隐藏能挡住一切。
    BOOL shouldHide = (self.captureHidden && self.systemCaptured);
    if (self.hidden == shouldHide) return;
    self.hidden = shouldHide;

    // 恢复时把浮球重新顶到最前
    if (!shouldHide) {
        for (UIView *v in self.rootViewController.view.subviews) {
            [self.rootViewController.view bringSubviewToFront:v];
        }
    }
}

@end
