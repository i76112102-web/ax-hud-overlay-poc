//
//  AppDelegate.m
//  PiPOverlay —— 免越狱跨 App 悬浮（PiP 路径）
//
//  能力边界（必读）：
//    iOS 上「在别的 App 界面之上放一个可点击的原生悬浮窗」没有官方 API。
//    PiP 是唯一被允许跨 App 的浮层，但它是一个视频窗：
//      - 能显示任意自绘画面、能拖动缩放        ✅
//      - 内容里的按钮不能点（手势被系统接管）  ❌
//    浮窗上唯一的触摸回传通道是「播放/暂停」按钮 → setPlaying: 回调。
//    本实现就利用它做「点浮窗 → 切换成 HUD 菜单」。
//
//  关于样本 AX Pro Max：它没有走 openURL，二进制里没有任何 sgame/tencentgame
//  字符串，走的是 AXZQBundleEnumerator + 解包 + 二次 UIApplicationMain，
//  也就是把目标 App 装进**自己进程**里跑。同进程的 window 当然能点，
//  这是它「点图标展开菜单」成立的原因，代价是要自己实现一个容器宿主。
//

#import "AppDelegate.h"
#import "PiPManager.h"
#import <math.h>

/// 依次尝试的目标 scheme（第一个 canOpenURL 通过的胜出）
static NSArray<NSString *> *kTargetSchemes(void) {
    return @[ @"sgame://", @"tencentgame://", @"qqmusic://", @"music://" ];
}

typedef NS_ENUM(NSInteger, HUDMode) {
    HUDModeIcon = 0,   // 悬浮球
    HUDModeMenu = 1,   // 展开菜单
};

@interface AppDelegate ()
@property (nonatomic, strong) UIWindow *mainWindow;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *preview;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;
@property (nonatomic, assign) NSInteger tick;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
@property (nonatomic, assign) HUDMode mode;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.logLines = [NSMutableArray array];
    self.mode = HUDModeIcon;

    CGSize scr = [UIScreen mainScreen].bounds.size;
    CGFloat pad = 18;
    CGFloat w = scr.width - pad * 2;

    self.mainWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(pad, 54, w, 46)];
    title.numberOfLines = 0;
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    title.text = @"PiP 悬浮 · 拉起游戏后仍浮在上面";
    [root.view addSubview:title];

    // 预览框：必须真在屏、真被合成，否则 isPictureInPicturePossible 恒为 NO。
    // 不要设 masksToBounds —— 裁剪 group 会让 AVSampleBufferDisplayLayer 不上屏。
    CGFloat pvW = w, pvH = floor(w * 9.0 / 16.0);
    self.preview = [[UIView alloc] initWithFrame:CGRectMake(pad, CGRectGetMaxY(title.frame) + 8, pvW, pvH)];
    self.preview.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.preview.layer.borderWidth = 1;
    self.preview.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    [root.view addSubview:self.preview];

    UILabel *pvTag = [[UILabel alloc] initWithFrame:CGRectMake(pad + 8, self.preview.frame.origin.y + 6, 280, 15)];
    pvTag.text = @"PiP 内容源 · 实时预览";
    pvTag.font = [UIFont systemFontOfSize:10];
    pvTag.textColor = [UIColor colorWithWhite:1 alpha:0.5];
    [root.view addSubview:pvTag];

    CGFloat btnH = 46;
    CGFloat y = CGRectGetMaxY(self.preview.frame) + 12;

    UIButton *b1 = [self button:@"① 启动 PiP 浮窗" tag:1 y:y width:w pad:pad h:btnH];
    [root.view addSubview:b1];
    y = CGRectGetMaxY(b1.frame) + 8;
    UIButton *b2 = [self button:@"② 拉起目标 App" tag:2 y:y width:w pad:pad h:btnH];
    [root.view addSubview:b2];
    y = CGRectGetMaxY(b2.frame) + 8;
    UIButton *b3 = [self button:@"③ 切换 图标 / 菜单" tag:3 y:y width:w pad:pad h:btnH];
    [root.view addSubview:b3];

    y = CGRectGetMaxY(b3.frame) + 10;
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w, 34)];
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.75];
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.statusLabel.text = @"初始化中…";
    [root.view addSubview:self.statusLabel];

    CGFloat logY = CGRectGetMaxY(self.statusLabel.frame) + 6;
    CGFloat logH = MAX(90, scr.height - logY - 20);
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(pad, logY, w, logH)];
    self.logView.editable = NO;
    self.logView.backgroundColor = [UIColor colorWithWhite:0.11 alpha:1.0];
    self.logView.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    self.logView.font = [UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightRegular];
    self.logView.textContainerInset = UIEdgeInsetsMake(6, 6, 6, 6);
    self.logView.layer.cornerRadius = 6;
    [root.view addSubview:self.logView];

    self.mainWindow.rootViewController = root;
    [self.mainWindow makeKeyAndVisible];

    __weak typeof(self) ws = self;
    [PiPManager shared].logHandler = ^(NSString *line) { [ws appendLog:line]; };
    [PiPManager shared].onPiPStarted = ^{
        [ws appendLog:@"浮窗已就绪 → 现在点 ② 拉起目标 App"];
    };
    [PiPManager shared].onPlayPauseTapped = ^(BOOL playing) {
        // 浮窗上点了播放/暂停：当作「展开/收起菜单」
        [ws appendLog:[NSString stringWithFormat:@"浮窗控件事件 playing=%d → 切换画面", playing]];
        [ws toggleMode];
    };

    [[PiPManager shared] attachToView:self.preview];
    [self startFrameTimer];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [ws refreshStatus]; });
    return YES;
}

- (UIButton *)button:(NSString *)title tag:(NSInteger)tag y:(CGFloat)y
               width:(CGFloat)w pad:(CGFloat)pad h:(CGFloat)h {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.frame = CGRectMake(pad, y, w, h);
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    b.layer.cornerRadius = 9;
    b.tag = tag;
    [b addTarget:self action:@selector(onButton:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)appendLog:(NSString *)line {
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"HH:mm:ss";
    NSString *s = [NSString stringWithFormat:@"%@  %@", [f stringFromDate:[NSDate date]], line];
    [self.logLines addObject:s];
    if (self.logLines.count > 300) [self.logLines removeObjectAtIndex:0];
    self.logView.text = [self.logLines componentsJoinedByString:@"\n"];
    if (self.logView.text.length) {
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length - 1, 1)];
    }
}

- (void)refreshStatus {
    self.statusLabel.text = [[PiPManager shared] diagnostics];
}

#pragma mark - 交互

- (void)onButton:(UIButton *)sender {
    [self keepBackgroundAlive];

    switch (sender.tag) {
        case 1: {
            self.statusLabel.text = @"正在启动 PiP…";
            BOOL sent = [[PiPManager shared] startPiP];
            self.statusLabel.text = sent ? @"PiP 启动指令已发出"
                                         : @"未发出，原因见下方日志";
            break;
        }
        case 2:
            [self launchTargetApp];
            break;
        case 3:
            [self toggleMode];
            break;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self refreshStatus]; });
}

- (void)toggleMode {
    self.mode = (self.mode == HUDModeIcon) ? HUDModeMenu : HUDModeIcon;
    [self appendLog:(self.mode == HUDModeIcon) ? @"画面 → 悬浮图标" : @"画面 → HUD 菜单"];
    [[PiPManager shared] pushImage:[self renderCurrentMode]];
}

- (void)launchTargetApp {
    for (NSString *s in kTargetSchemes()) {
        NSURL *url = [NSURL URLWithString:s];
        if (!url) continue;
        if (![UIApplication.sharedApplication canOpenURL:url]) {
            [self appendLog:[NSString stringWithFormat:@"canOpenURL=NO  %@", s]];
            continue;
        }
        [self appendLog:[NSString stringWithFormat:@"openURL %@", s]];
        self.statusLabel.text = [NSString stringWithFormat:@"拉起 %@", s];
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL ok) {
            NSLog(@"[PiP] openURL %@ -> %d", s, ok);
        }];
        return;
    }
    [self appendLog:@"❌ 所有候选 scheme 都不在白名单 / 未安装"];
    self.statusLabel.text = @"没有可拉起的 App";
}

- (void)keepBackgroundAlive {
    if (self.bgTask > 0) return;
    __weak typeof(self) ws = self;
    self.bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        typeof(self) s = ws;
        if (s.bgTask > 0) {
            [[UIApplication sharedApplication] endBackgroundTask:s.bgTask];
            s.bgTask = 0;
        }
    }];
}

#pragma mark - 推帧

- (void)startFrameTimer {
    if (self.timer) return;
    self.timer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *t) {
        self.tick++;
        [[PiPManager shared] pushImage:[self renderCurrentMode]];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (UIImage *)renderCurrentMode {
    return (self.mode == HUDModeIcon) ? [self renderIcon] : [self renderMenu];
}

/// 悬浮球：深色圆底 + 呼吸绿点 + 标记。PiP 缩到最小后视觉上就是个悬浮图标。
- (UIImage *)renderIcon {
    CGSize size = CGSizeMake(480, 270);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGContextSetRGBFillColor(c, 0.05, 0.05, 0.06, 1);
        CGContextFillRect(c, CGRectMake(0, 0, size.width, size.height));

        // 外圈光晕
        CGContextSetRGBFillColor(c, 0.15, 0.85, 0.55, 0.10);
        CGContextFillEllipseInRect(c, CGRectMake(240 - 86, 135 - 86, 172, 172));
        CGContextSetRGBFillColor(c, 0.15, 0.85, 0.55, 0.18);
        CGContextFillEllipseInRect(c, CGRectMake(240 - 64, 135 - 64, 128, 128));

        // 内圆
        CGContextSetRGBFillColor(c, 0.11, 0.11, 0.13, 1);
        CGContextFillEllipseInRect(c, CGRectMake(240 - 52, 135 - 52, 104, 104));

        NSDictionary *ta = @{
            NSFontAttributeName : [UIFont boldSystemFontOfSize:34],
            NSForegroundColorAttributeName : UIColor.whiteColor,
        };
        CGSize ts = [@"AX" sizeWithAttributes:ta];
        [@"AX" drawAtPoint:CGPointMake(240 - ts.width / 2, 135 - ts.height / 2) withAttributes:ta];

        // 右上角呼吸点
        CGFloat phase = (self.tick % 20) / 20.0;
        CGFloat alpha = 0.35 + 0.55 * fabs(sin(phase * M_PI));
        CGContextSetRGBFillColor(c, 0.15, 0.85, 0.55, alpha);
        CGContextFillEllipseInRect(c, CGRectMake(240 + 42, 135 - 58, 18, 18));

        NSDictionary *t3 = @{
            NSFontAttributeName : [UIFont systemFontOfSize:11],
            NSForegroundColorAttributeName : [UIColor colorWithWhite:1 alpha:0.3],
        };
        [@"点浮窗播放键切换菜单"
            drawAtPoint:CGPointMake(180, 232) withAttributes:t3];
    }];
}

/// HUD 菜单：三个功能项
- (UIImage *)renderMenu {
    CGSize size = CGSizeMake(480, 270);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGContextSetRGBFillColor(c, 0.06, 0.06, 0.07, 1);
        CGContextFillRect(c, CGRectMake(0, 0, size.width, size.height));

        CGContextSetRGBFillColor(c, 0.12, 0.12, 0.14, 1);
        CGContextFillRect(c, CGRectMake(0, 0, size.width, 56));

        CGContextSetRGBFillColor(c, 0.15, 0.85, 0.55, 1);
        CGContextFillEllipseInRect(c, CGRectMake(20, 18, 20, 20));

        NSDictionary *t1 = @{
            NSFontAttributeName : [UIFont boldSystemFontOfSize:18],
            NSForegroundColorAttributeName : UIColor.whiteColor,
        };
        [@"AX HUD" drawAtPoint:CGPointMake(52, 16) withAttributes:t1];

        NSDictionary *t2 = @{
            NSFontAttributeName : [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular],
            NSForegroundColorAttributeName : [UIColor colorWithWhite:1 alpha:0.45],
        };
        [[NSString stringWithFormat:@"tick %ld", (long)self.tick]
            drawAtPoint:CGPointMake(size.width - 96, 22) withAttributes:t2];

        NSArray *items = @[@"功能", @"设置", @"关闭"];
        CGFloat w = (size.width - 4 * 20) / 3.0;
        for (NSUInteger i = 0; i < items.count; i++) {
            CGRect box = CGRectMake(20 + i * (w + 20), 96, w, 66);
            UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:12];
            CGContextSetRGBFillColor(c, 1, 1, 1, 0.10);
            CGContextAddPath(c, p.CGPath);
            CGContextFillPath(c);

            NSDictionary *ta = @{
                NSFontAttributeName : [UIFont systemFontOfSize:16 weight:UIFontWeightMedium],
                NSForegroundColorAttributeName : UIColor.whiteColor,
            };
            CGSize ts = [items[i] sizeWithAttributes:ta];
            [items[i] drawAtPoint:CGPointMake(CGRectGetMidX(box) - ts.width / 2,
                                              CGRectGetMidY(box) - ts.height / 2)
                   withAttributes:ta];
        }

        NSDictionary *t3 = @{
            NSFontAttributeName : [UIFont systemFontOfSize:12],
            NSForegroundColorAttributeName : [UIColor colorWithWhite:1 alpha:0.35],
        };
        [@"再点浮窗播放键收回图标"
            drawAtPoint:CGPointMake(20, size.height - 28) withAttributes:t3];
    }];
}

@end
