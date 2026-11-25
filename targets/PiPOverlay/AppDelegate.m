//
//  AppDelegate.m
//  PiPOverlay 演示 —— 「拉起目标 App 后 HUD 浮在它界面之上」
//
//  时序：
//    1. 点按钮 → 启动 PiP（系统托管浮窗，此时还压在自己界面上）
//    2. PiP 进入浮窗态（didStartPictureInPicture）→ 延迟 1.2s
//    3. openURL 拉起目标 App → 自己进后台
//    4. 后台音频保活 + PiP 由系统持有 → HUD 继续显示在目标 App 界面之上
//
//  这是免越狱下唯一能做到「切到任意 App 后仍然浮在上面」的官方路径。
//  样本走的是容器化（把目标 App 加载进自己进程），效果等价但工程量大一个量级。
//

#import "AppDelegate.h"
#import "PiPManager.h"

// 拉起哪个 App：改成目标 App 已注册的 URL Scheme
// 常见：music://（音乐）  qqmusic://  orpheus://（QQ音乐）  bilibili://  youtube://
static NSString *const kLaunchURLString = @"music://";
// 不想自动拉起就置 NO，改为手动按 Home 验证
static BOOL const kAutoLaunchAfterPiP = YES;

@interface AppDelegate ()
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIWindow *pipHost;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) NSInteger tick;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL launched;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithWhite:0.09 alpha:1.0];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(24, 120, root.view.bounds.size.width - 48, 90)];
    title.numberOfLines = 0;
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:22];
    title.text = @"拉起目标 App 后\nHUD 仍浮在它上面";
    [root.view addSubview:title];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"启动 PiP 并拉起目标 App" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.frame = CGRectMake(24, 0, root.view.bounds.size.width - 48, 54);
    btn.center = CGPointMake(root.view.bounds.size.width / 2, root.view.bounds.size.height / 2);
    btn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    btn.layer.cornerRadius = 12;
    [btn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
    [root.view addSubview:btn];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 0, root.view.bounds.size.width - 48, 60)];
    self.statusLabel.center = CGPointMake(root.view.bounds.size.width / 2,
                                          root.view.bounds.size.height / 2 + 70);
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.statusLabel.text = @"等待启动";
    [root.view addSubview:self.statusLabel];

    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];

    // PiP 宿主窗口：内容层挂在这里。
    // 注意：这个 window 必须真的在屏幕内且被合成（alpha=0 或完全离屏会导致
    // AVSampleBufferDisplayLayer 不上屏，进而 isPictureInPicturePossible 恒为 NO）。
    // 所以放在屏幕内、层级压在主窗下面、几乎全透明。
    self.pipHost = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 480, 270)];
    self.pipHost.windowLevel = UIWindowLevelNormal - 1;
    self.pipHost.alpha = 0.02;
    self.pipHost.hidden = NO;
    self.pipHost.rootViewController = [UIViewController new];
    self.pipHost.rootViewController.view.backgroundColor = UIColor.clearColor;
    [self.pipHost makeKeyAndVisible];
    [self.window makeKeyAndVisible];

    [[PiPManager shared] attachToWindow:self.pipHost];

    __weak typeof(self) weakSelf = self;
    [PiPManager shared].onPiPStarted = ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf launchTargetApp];
        });
    };
    return YES;
}

- (void)onTap {
    if ([[PiPManager shared] isPiPActive]) {
        self.statusLabel.text = @"PiP 已在运行";
        [self startFrameTimer];
        return;
    }
    self.statusLabel.text = @"正在启动 PiP…";
    [[PiPManager shared] startPiP];
    [self startFrameTimer];
}

#pragma mark - 拉起目标 App

- (void)launchTargetApp {
    if (self.launched || !kAutoLaunchAfterPiP) return;
    NSURL *url = [NSURL URLWithString:kLaunchURLString];
    if (!url) return;

    UIApplication *app = UIApplication.sharedApplication;
    if (![app canOpenURL:url]) {
        self.statusLabel.text = [NSString stringWithFormat:@"scheme 未在 Info.plist 白名单：%@", kLaunchURLString];
        NSLog(@"[PiP] canOpenURL=NO for %@", url);
        return;
    }
    self.launched = YES;
    self.statusLabel.text = [NSString stringWithFormat:@"拉起 %@", kLaunchURLString];
    [app openURL:url options:@{} completionHandler:^(BOOL ok) {
        NSLog(@"[PiP] openURL %@ -> %d", url, ok);
    }];
}

#pragma mark - 推帧

- (void)startFrameTimer {
    if (self.timer) return;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                 repeats:YES
                                                   block:^(NSTimer *t) {
        self.tick++;
        [[PiPManager shared] pushImage:[self renderHUD]];
    }];
    // 后台也要跑：加入 common mode，避免被 scroll 等打断
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

/// HUD 画面：顶部一条悬浮控制条 + 状态行。实际项目里换成你的菜单
- (UIImage *)renderHUD {
    CGSize size = CGSizeMake(480, 270);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;

        CGContextSetRGBFillColor(c, 0.06, 0.06, 0.07, 1);
        CGContextFillRect(c, CGRectMake(0, 0, size.width, size.height));

        // 顶部控制条
        CGContextSetRGBFillColor(c, 0.12, 0.12, 0.14, 1);
        CGContextFillRect(c, CGRectMake(0, 0, size.width, 64));

        // 指示点
        CGContextSetRGBFillColor(c, 0.15, 0.85, 0.55, 1);
        CGContextFillEllipseInRect(c, CGRectMake(20, 20, 24, 24));

        NSDictionary *t1 = @{
            NSFontAttributeName : [UIFont boldSystemFontOfSize:20],
            NSForegroundColorAttributeName : UIColor.whiteColor,
        };
        [@"AX HUD" drawAtPoint:CGPointMake(58, 18) withAttributes:t1];

        NSDictionary *t2 = @{
            NSFontAttributeName : [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular],
            NSForegroundColorAttributeName : [UIColor colorWithWhite:1 alpha:0.45],
        };
        [[NSString stringWithFormat:@"tick %ld", (long)self.tick]
            drawAtPoint:CGPointMake(size.width - 110, 24) withAttributes:t2];

        // 三个圆角按钮，模拟样本的 HUD 菜单项
        NSArray *items = @[@"功能", @"设置", @"关闭"];
        CGFloat w = (size.width - 4 * 20) / 3.0;
        for (NSUInteger i = 0; i < items.count; i++) {
            CGRect box = CGRectMake(20 + i * (w + 20), 100, w, 64);
            UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:14];
            CGContextSetRGBFillColor(c, 1, 1, 1, 0.10);
            CGContextAddPath(c, p.CGPath);
            CGContextFillPath(c);

            NSDictionary *ta = @{
                NSFontAttributeName : [UIFont systemFontOfSize:17 weight:UIFontWeightMedium],
                NSForegroundColorAttributeName : UIColor.whiteColor,
            };
            CGSize ts = [items[i] sizeWithAttributes:ta];
            [items[i] drawAtPoint:CGPointMake(CGRectGetMidX(box) - ts.width / 2,
                                              CGRectGetMidY(box) - ts.height / 2)
                   withAttributes:ta];
        }

        NSDictionary *t3 = @{
            NSFontAttributeName : [UIFont systemFontOfSize:13],
            NSForegroundColorAttributeName : [UIColor colorWithWhite:1 alpha:0.35],
        };
        [@"PiP 浮窗 · 覆盖在目标 App 之上"
            drawAtPoint:CGPointMake(20, size.height - 34) withAttributes:t3];
    }];
}

@end
