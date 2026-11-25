//
//  HUDWindow.m
//  同进程最高层悬浮窗（对应 AX Pro Max 的 AXHUD* 组件）
//
//  说明：
//   - 这是「容器内虚拟运行」方案里的 HUD 层。目标 App 被加载进本进程后，
//     这个 window 盖在它上面即可实现"悬浮"。
//   - 单独的 App 用它，只能覆盖自己；跨 App 请用 PiPOverlay。
//

#import "HUDWindow.h"

static const CGFloat kHUDLevel = 10000000;   // 远高于 UIWindowLevelAlert

@interface HUDWindow ()
@property (nonatomic, strong) UIView *ball;
@property (nonatomic, assign) CGPoint panStart;
@end

@implementation HUDWindow

+ (instancetype)showHUD {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; }
    }
    HUDWindow *w = scene
        ? [[HUDWindow alloc] initWithWindowScene:scene]
        : [[HUDWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    w.windowLevel = kHUDLevel;
    w.backgroundColor = UIColor.clearColor;
    w.rootViewController = [UIViewController new];
    w.rootViewController.view.backgroundColor = UIColor.clearColor;
    w.hidden = NO;
    [w makeKeyAndVisible];

    [w installBall];
    return w;
}

- (void)installBall {
    CGFloat d = 56;
    self.ball = [[UIView alloc] initWithFrame:CGRectMake(24, 160, d, d)];
    self.ball.backgroundColor = [UIColor colorWithRed:0.13 green:0.85 blue:0.55 alpha:0.9];
    self.ball.layer.cornerRadius = d / 2;
    self.ball.layer.shadowColor = UIColor.blackColor.CGColor;
    self.ball.layer.shadowOpacity = 0.35;
    self.ball.layer.shadowRadius = 8;

    UILabel *l = [[UILabel alloc] initWithFrame:self.ball.bounds];
    l.text = @"AX";
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont boldSystemFontOfSize:15];
    [self.ball addSubview:l];

    [self.rootViewController.view addSubview:self.ball];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [self.ball addGestureRecognizer:pan];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapBall)];
    [self.ball addGestureRecognizer:tap];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint p = [g translationInView:self];
    if (g.state == UIGestureRecognizerStateBegan) {
        self.panStart = self.ball.center;
    }
    self.ball.center = CGPointMake(self.panStart.x + p.x, self.panStart.y + p.y);
}

- (void)onTapBall {
    NSLog(@"[HUD] tap");
    if (self.onTap) self.onTap();
}

// 命中测试：空白区域返回 nil，让触摸穿透到下层（关键，否则会挡住虚拟 App）
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self.rootViewController.view) return nil;
    return v;
}

- (BOOL)_canBecomeKeyWindow { return NO; }

@end
