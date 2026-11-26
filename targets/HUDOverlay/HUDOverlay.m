//
//  HUDOverlay.m
//
//  LiveContainer global tweak: AX 风格跨 app 悬浮图标。
//
//  原理：LiveContainer 把 guest App 的 Mach-O dlopen 进 host 进程，guest 的
//  UIApplicationMain 与 HUD 在同一进程 / 同一合成树。HUD 用超高 windowLevel
//  的普通 UIWindow 盖在 guest 画面上，不依赖 PiP / SpringBoard overlay。
//
//  安装：把编译出的 HUDOverlay.dylib 放到 LiveContainer 的
//  Documents/Tweaks/（或 App Group 的 Tweaks 目录），LiveContainer 的
//  TweakLoader 会在 guest 加载时 dlopen 本 dylib，constructor 自动挂 HUD。
//
//  注意：不要用 makeKeyAndVisible，避免抢 guest 的 keyWindow/键盘焦点。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#pragma mark - 私有 API 声明（只声明，不覆盖系统）

@interface UIWindow (AXPrivate)
- (BOOL)_isWindowServerHostingManaged;
- (BOOL)_ignoresHitTest;
- (BOOL)canBecomeKeyWindow;
@end

#pragma mark - HUD 浮球视图

@interface HUDPadView : UIView
@property (nonatomic, strong) UIView *ball;
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, strong) NSArray<UIButton *> *menuItems;
@property (nonatomic, assign) BOOL menuOpen;
@property (nonatomic, assign) CGPoint draggingStart;
@end

@implementation HUDPadView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;

        CGFloat ballSize = 56.0;
        UIView *ball = [[UIView alloc] initWithFrame:CGRectMake(0, 0, ballSize, ballSize)];
        ball.layer.cornerRadius = ballSize / 2;
        ball.layer.masksToBounds = YES;
        ball.layer.shadowColor = [UIColor blackColor].CGColor;
        ball.layer.shadowOpacity = 0.35;
        ball.layer.shadowRadius = 8;
        ball.layer.shadowOffset = CGSizeMake(0, 3);
        CAGradientLayer *grad = [CAGradientLayer layer];
        grad.frame = ball.bounds;
        grad.colors = @[(id)[UIColor colorWithRed:0.15 green:0.75 blue:0.95 alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.20 green:0.35 blue:0.90 alpha:1].CGColor];
        grad.cornerRadius = ballSize / 2;
        [ball.layer insertSublayer:grad atIndex:0];
        [self addSubview:ball];
        self.ball = ball;

        UILabel *badge = [[UILabel alloc] initWithFrame:CGRectInset(ball.bounds, 4, 4)];
        badge.text = @"HUD";
        badge.textColor = [UIColor whiteColor];
        badge.font = [UIFont boldSystemFontOfSize:13];
        badge.textAlignment = NSTextAlignmentCenter;
        [ball addSubview:badge];
        self.badge = badge;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [ball addGestureRecognizer:pan];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
        tap.numberOfTapsRequired = 1;
        [ball addGestureRecognizer:tap];
    }
    return self;
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    CGPoint c = self.center;
    c.x += t.x;
    c.y += t.y;
    c.x = MAX(40, MIN(c.x, self.superview.bounds.size.width - 40));
    c.y = MAX(60, MIN(c.y, self.superview.bounds.size.height - 60));
    self.center = c;
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)onTap:(UITapGestureRecognizer *)g {
    self.menuOpen = !self.menuOpen;
    for (UIButton *b in self.menuItems) {
        b.hidden = !self.menuOpen;
    }
}

// 空白区不吞触摸：让 guest App 收到点击/滑动。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}

@end

#pragma mark - HUD 窗口

@interface HUDOverlayWindow : UIWindow
@property (nonatomic, strong) HUDPadView *pad;
@end

@implementation HUDOverlayWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // AX 静态实测值：10000010.0；同进程合成树内压过 guest 所有窗口。
        self.windowLevel = 10000010.0;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.hidden = NO;

        UIViewController *vc = [UIViewController new];
        vc.view.backgroundColor = [UIColor clearColor];
        self.rootViewController = vc;

        HUDPadView *pad = [[HUDPadView alloc] initWithFrame:CGRectMake(20, 100, 56, 56)];
        [vc.view addSubview:pad];
        self.pad = pad;

        // 菜单项
        NSArray *titles = @[@"过直播", @"防截屏", @"主题", @"退出HUD"];
        NSMutableArray *items = [NSMutableArray array];
        for (NSInteger i = 0; i < titles.count; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(0, 64 + i * 38, 120, 34);
            [b setTitle:titles[i] forState:UIControlStateNormal];
            b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            b.layer.cornerRadius = 8;
            b.hidden = YES;
            b.tag = i;
            [b addTarget:self action:@selector(menuTapped:) forControlEvents:UIControlEventTouchUpInside];
            [pad.ball.superview addSubview:b];
            [items addObject:b];
        }
        pad.menuItems = items;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onCaptured:)
                                                     name:UIScreenCapturedDidChangeNotification
                                                   object:nil];
    }
    return self;
}

// 不抢 key，避免 guest 输入框/键盘失效。
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeFocused  { return NO; }
- (BOOL)_ignoresHitTest   { return NO; }
- (BOOL)_isWindowServerHostingManaged { return NO; }

- (void)menuTapped:(UIButton *)b {
    switch (b.tag) {
        case 0: { // 过直播：捕获时摘层
            static BOOL captureHidden = NO;
            captureHidden = !captureHidden;
            objc_setAssociatedObject(self, @"captureHidden", @(captureHidden), OBJC_ASSOCIATION_RETAIN);
            [self applyCaptureState];
            break;
        }
        case 1: { // 防截屏：secure layer
            static BOOL secure = NO;
            secure = !secure;
            for (UIView *v in self.pad.subviews) {
                if (v.tag == 998) [v removeFromSuperview];
            }
            if (secure) {
                UITextField *shield = [[UITextField alloc] initWithFrame:self.pad.bounds];
                shield.tag = 998;
                shield.userInteractionEnabled = NO;
                shield.secureTextEntry = YES;
                [self.pad insertSubview:shield atIndex:0];
            }
            break;
        }
        case 2: { // 主题：切换浮球颜色
            static NSInteger theme = 0;
            theme = (theme + 1) % 3;
            UIColor *c = @[[UIColor colorWithRed:0.15 green:0.75 blue:0.95 alpha:1],
                           [UIColor colorWithRed:0.95 green:0.45 blue:0.20 alpha:1],
                           [UIColor colorWithRed:0.35 green:0.90 blue:0.45 alpha:1]][theme];
            CAGradientLayer *grad = self.pad.ball.layer.sublayers.firstObject;
            if ([grad isKindOfClass:[CAGradientLayer class]]) {
                grad.colors = @[(id)c.CGColor, (id)[UIColor colorWithWhite:0.15 alpha:1].CGColor];
            }
            break;
        }
        case 3: // 退出 HUD
            self.hidden = YES;
            break;
    }
    self.pad.menuOpen = NO;
    for (UIButton *b2 in self.pad.menuItems) b2.hidden = YES;
}

- (void)onCaptured:(NSNotification *)n {
    [self applyCaptureState];
}

- (void)applyCaptureState {
    BOOL captureHidden = [objc_getAssociatedObject(self, @"captureHidden") boolValue];
    self.hidden = (captureHidden && UIScreen.mainScreen.isCaptured);
}

@end

#pragma mark - 注入入口

static HUDOverlayWindow *gHUDWindow = nil;

static void attachHUD(void) {
    if (gHUDWindow) return;

    // guest 的 UIApplicationMain 起来后 connectedScenes 才有值。
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) return;

    HUDOverlayWindow *w = [[HUDOverlayWindow alloc] initWithFrame:scene.coordinateSpace.bounds];
    w.windowScene = scene;
    [w setHidden:NO]; // 不用 makeKeyAndVisible
    gHUDWindow = w;
    NSLog(@"[HUDOverlay] attached HUD window level=10000010 on scene=%@", scene);
}

__attribute__((constructor))
static void HUDOverlayConstructor(void) {
    // TweakLoader constructor 可能早于 UIApplication/Scene 就绪，延迟轮询。
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            attachHUD();
            // 再兜底两次，覆盖启动慢的 guest。
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ attachHUD(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ attachHUD(); });
        });
    });
    NSLog(@"[HUDOverlay] constructor loaded (AX-style floating icon, no PiP)");
}
