//
//  AXScreenShield.m
//

#import "AXScreenShield.h"

@interface AXScreenShield ()
@property (nonatomic, strong, nullable) UITextField *shieldField;
@property (nonatomic, strong, nullable) UIView *maskView;
@property (nonatomic, strong, nullable) CAGradientLayer *maskGradient;
@property (nonatomic, strong, nullable) UIVisualEffectView *maskBlur;
@end

@implementation AXScreenShield

+ (instancetype)shieldWithWindowScene:(UIWindowScene *)scene {
    AXScreenShield *w = scene ? [[AXScreenShield alloc] initWithWindowScene:scene]
                              : [[AXScreenShield alloc] initWithFrame:[UIScreen mainScreen].bounds];
    w.enabled = YES;
    w.windowLevel = UIWindowLevelAlert + 100;   // 高于 HUD 菜单层
    w.backgroundColor = UIColor.clearColor;
    w.rootViewController = [UIViewController new];
    w.rootViewController.view.backgroundColor = UIColor.clearColor;
    w.hidden = NO;
    return w;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) { [self commonInit]; }
    return self;
}

- (instancetype)initWithWindowScene:(UIWindowScene *)windowScene {
    if (self = [super initWithWindowScene:windowScene]) { [self commonInit]; }
    return self;
}

- (void)commonInit {
    _enabled = YES;
    self.backgroundColor = UIColor.clearColor;
    [self observeNotifications];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - 通知（与样本 Bn4Ks8Yq2F 注册的 9 个一致）

- (void)observeNotifications {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    for (NSNotificationName n in @[
             UIScreenCapturedDidChangeNotification,
             UIApplicationWillResignActiveNotification,
             UIApplicationDidEnterBackgroundNotification,
             UIApplicationWillEnterForegroundNotification,
             UIApplicationDidBecomeActiveNotification,
             UISceneWillDeactivateNotification,
             UISceneDidEnterBackgroundNotification,
             UISceneWillEnterForegroundNotification,
             UISceneDidActivateNotification,
         ]) {
        [nc addObserver:self selector:@selector(onStateChange:) name:n object:nil];
    }
}

- (void)onStateChange:(NSNotification *)note {
    if (!self.enabled) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // 回前台后 secure canvas 需要重建，否则保护失效
        [self rebuildShieldIfNeeded];
        [self updateMaskForCaptureState];
    });
}

#pragma mark - 护盾

- (void)install {
    [self rebuildShieldIfNeeded];
    [self updateMaskForCaptureState];
}

- (void)uninstall {
    [self.shieldField removeFromSuperview];
    self.shieldField = nil;
    [self.maskView removeFromSuperview];
    self.maskView = nil;
}

- (void)rebuildShieldIfNeeded {
    if (!self.enabled) { [self uninstall]; return; }
    if (self.shieldField && self.shieldField.window == self) {
        self.shieldField.frame = self.bounds;
        return;
    }
    [self.shieldField removeFromSuperview];

    UITextField *f = [[UITextField alloc] initWithFrame:self.bounds];
    f.secureTextEntry = YES;            // 核心：开启 secure，系统捕获时剔除该层
    f.backgroundColor = UIColor.clearColor;
    f.textColor = UIColor.clearColor;
    f.tintColor = UIColor.clearColor;
    f.borderStyle = UITextBorderStyleNone;
    f.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    f.userInteractionEnabled = NO;      // 不拦触摸，HUD 交互照常
    f.accessibilityElementsHidden = YES;
    f.text = @" ";                      // 空内容也要让 canvas 建立起来
    [self addSubview:f];
    self.shieldField = f;

    // 成为 first responder 才会创建 _UITextLayoutCanvasView（保护的实际载体）
    [f becomeFirstResponder];
}

#pragma mark - 捕获态遮罩

- (BOOL)captureActive {
    if (@available(iOS 11.0, *)) {
        return UIScreen.mainScreen.isCaptured;   // 录屏 / AirPlay 镜像
    }
    return NO;
}

- (void)updateMaskForCaptureState {
    BOOL on = self.enabled && [self captureActive];
    if (on) { [self showMask]; } else { [self hideMask]; }
}

- (void)showMask {
    if (self.maskView) { self.maskView.frame = self.bounds; return; }

    UIView *v = [[UIView alloc] initWithFrame:self.bounds];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.userInteractionEnabled = NO;
    v.accessibilityElementsHidden = YES;
    v.accessibilityViewIsModal = YES;

    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = v.bounds;
    g.colors = @[(id)[UIColor colorWithWhite:0.10 alpha:1.0].CGColor,
                 (id)[UIColor colorWithWhite:0.02 alpha:1.0].CGColor];
    g.locations = @[@0.0, @1.0];
    g.startPoint = CGPointMake(0.5, 0.0);
    g.endPoint   = CGPointMake(0.5, 1.0);
    [v.layer addSublayer:g];

    UIVisualEffectView *blur =
        [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame = v.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [v addSubview:blur];

    [self addSubview:v];
    self.maskView = v;
    self.maskGradient = g;
    self.maskBlur = blur;
}

- (void)hideMask {
    [self.maskView removeFromSuperview];
    self.maskView = nil;
    self.maskGradient = nil;
    self.maskBlur = nil;
}

- (BOOL)maskVisible { return self.maskView != nil; }

#pragma mark - 布局与命中

- (void)layoutSubviews {
    [super layoutSubviews];
    self.shieldField.frame = self.bounds;
    self.maskView.frame = self.bounds;
    self.maskGradient.frame = self.bounds;
    self.maskBlur.frame = self.bounds;
}

/// 护盾窗口永不接收触摸
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}

@end
