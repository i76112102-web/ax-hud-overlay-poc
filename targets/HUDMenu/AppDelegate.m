//
//  AppDelegate.m
//  HUDMenu —— 复现 AX Pro Max 点「启动应用」之后的 HUD 交互层
//
//  样本时序（静态证据）：
//    didFinishLaunching
//      → 授权 / 解密 __AXPAD
//      → HUD 窗口上屏（menuWindowLevel）
//      → 目标 App 界面就绪
//      → commitMenuWindowGeometry / flushMenuWindowForDisplay
//      → 浮球 + 菜单可用
//
//  本工程把「目标 App 界面就绪」这一步省掉（免越狱无法把第三方 App 装进自己进程），
//  只复现 HUD 层本身：浮球 → 展开菜单 → 四个开关。
//

#import "AppDelegate.h"
#import "HUDMenuWindow.h"
#import "HUDMenuPanel.h"
#import "AudioKeepAlive.h"

@interface AppDelegate ()
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UILabel  *hintLabel;
@property (nonatomic, strong) HUDMenuWindow *hudWindow;
@property (nonatomic, strong) HUDMenuPanel  *panel;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.mainWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.mainWindow.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];
    self.mainWindow.rootViewController = [UIViewController new];
    [self.mainWindow makeKeyAndVisible];

    [self buildHome];

    // 后台保活：HUD 与进程常驻（对应样本的 Library/ax-hud-keepalive.wav）
    [[AudioKeepAlive shared] start];

    // 对应样本 scheduleOrientationSynchronizationAfterAppSwitch：
    // 从别的 App 切回来时，回主线程重新算一遍 HUD 几何
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onAppActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    return YES;
}

- (void)buildHome {
    UIView *root = self.mainWindow.rootViewController.view;
    CGRect b = root.bounds;
    CGFloat pad = 24, w = b.size.width - pad * 2;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(pad, 90, w, 30)];
    title.text = @"AX HUD 菜单复现";
    title.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
    title.textColor = [UIColor whiteColor];
    [root addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(pad, 128, w, 66)];
    sub.numberOfLines = 0;
    sub.text = @"点下面按钮呼出悬浮球。\n点浮球展开菜单，可拖动、可吸附边缘。";
    sub.font = [UIFont systemFontOfSize:13];
    sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    [root addSubview:sub];

    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.startButton.frame = CGRectMake(pad, 210, w, 50);
    [self.startButton setTitle:@"启动 HUD" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.startButton.backgroundColor = [UIColor colorWithHue:0.58 saturation:0.85 brightness:1.0 alpha:1.0];
    self.startButton.layer.cornerRadius = 12.0;
    [self.startButton addTarget:self
                         action:@selector(onStart)
               forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:self.startButton];

    self.hintLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 272, w, 60)];
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.font = [UIFont systemFontOfSize:12];
    self.hintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.4];
    self.hintLabel.text = @"状态：HUD 未启动";
    [root addSubview:self.hintLabel];
}

- (void)onStart {
    if (self.hudWindow) {
        self.hudWindow.hidden = NO;
        [self.panel syncGeometry];
        self.hintLabel.text = @"状态：HUD 已启动";
        return;
    }

    UIWindowScene *scene = self.mainWindow.windowScene;
    if (!scene) {
        self.hintLabel.text = @"状态：拿不到 windowScene";
        return;
    }

    self.hudWindow = [HUDMenuWindow attachToScene:scene];

    self.panel = [[HUDMenuPanel alloc] initWithFrame:self.hudWindow.bounds];
    self.panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.hudWindow addSubview:self.panel];

    __weak typeof(self) ws = self;
    self.panel.onCaptureToggle = ^(BOOL on) {
        __strong typeof(ws) s = ws;
        s.hudWindow.captureHidden = on;
        s.hintLabel.text = on
            ? @"状态：过直播已开 —— 录屏/直播/投屏时 HUD 会自动隐藏"
            : @"状态：过直播已关";
    };
    self.panel.onSecureToggle = ^(BOOL on) {
        __strong typeof(ws) s = ws;
        s.hudWindow.secureEnabled = on;
        s.hintLabel.text = on
            ? @"状态：防截屏已开 —— 截图里 HUD 区域会变黑"
            : @"状态：允许截屏";
    };
    self.panel.onThemeChange = ^(UIColor *c) {
        __strong typeof(ws) s = ws;
        s.startButton.backgroundColor = c;
    };
    self.panel.onExit = ^ {
        __strong typeof(ws) s = ws;
        s.hudWindow.hidden = YES;
        s.hintLabel.text = @"状态：HUD 已退出";
    };

    self.hintLabel.text = @"状态：HUD 已启动（点浮球展开菜单）";
}

- (void)onAppActive {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.panel && self.hudWindow && !self.hudWindow.hidden) {
            [self.panel syncGeometry];
        }
    });
}

- (void)applicationDidEnterBackground:(UIApplication *)app {
    // 后台时把 HUD 挂起，回前台由 onAppActive 恢复几何
}

@end
