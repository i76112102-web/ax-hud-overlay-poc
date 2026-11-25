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
//  本工程分两段复现：
//    「启动应用」—— 用 LaunchServices 拉起本机已装的目标 App（外部等价于样本的
//                   AXZQBundleEnumerator + 容器内解包加载）
//    「HUD」     —— 浮球 + 展开菜单 + 四个开关，同进程最高 windowLevel
//
//  免越狱下 HUD 只能浮在本 App 自己的界面上；切到目标 App 后 HUD 不可见，
//  切回来即恢复（进程靠 audio 后台保活常驻）。
//

#import "AppDelegate.h"
#import "HUDMenuWindow.h"
#import "HUDMenuPanel.h"
#import "AudioKeepAlive.h"
#import "Launcher.h"
#import "AppPickerController.h"

static NSString *const kTargetBID  = @"ax.target.bundleID";
static NSString *const kTargetName = @"ax.target.name";

@interface AppDelegate ()
@property (nonatomic, strong) UIButton *targetButton;
@property (nonatomic, strong) UIButton *launchButton;
@property (nonatomic, strong) UIButton *hudButton;
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

    [self autoDetectTarget];
    return YES;
}

#pragma mark - 界面

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
    sub.text = @"「启动应用」拉起目标 App 并挂上 HUD；HUD 只在本 App 界面可见。\n点浮球展开菜单，可拖动、可吸附边缘。";
    sub.font = [UIFont systemFontOfSize:13];
    sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    [root addSubview:sub];

    // ---- 目标应用行 ----
    self.targetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.targetButton.frame = CGRectMake(pad, 200, w, 46);
    self.targetButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.targetButton.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
    self.targetButton.titleLabel.font = [UIFont systemFontOfSize:14];
    self.targetButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.targetButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.85] forState:UIControlStateNormal];
    self.targetButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07];
    self.targetButton.layer.cornerRadius = 10.0;
    [self.targetButton addTarget:self action:@selector(onPickTarget)
                forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:self.targetButton];

    // ---- 启动应用 ----
    self.launchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.launchButton.frame = CGRectMake(pad, 258, w, 50);
    [self.launchButton setTitle:@"启动应用" forState:UIControlStateNormal];
    [self.launchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.launchButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.launchButton.backgroundColor = [UIColor colorWithHue:0.58 saturation:0.85 brightness:1.0 alpha:1.0];
    self.launchButton.layer.cornerRadius = 12.0;
    [self.launchButton addTarget:self action:@selector(onLaunchTarget)
                forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:self.launchButton];

    // ---- 仅启动 HUD ----
    self.hudButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.hudButton.frame = CGRectMake(pad, 318, w, 46);
    [self.hudButton setTitle:@"仅启动 HUD" forState:UIControlStateNormal];
    [self.hudButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.85] forState:UIControlStateNormal];
    self.hudButton.titleLabel.font = [UIFont systemFontOfSize:15];
    self.hudButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    self.hudButton.layer.cornerRadius = 12.0;
    [self.hudButton addTarget:self action:@selector(onStartHUD)
             forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:self.hudButton];

    self.hintLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 378, w, 90)];
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.font = [UIFont systemFontOfSize:12];
    self.hintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.4];
    self.hintLabel.text = @"状态：空闲";
    [root addSubview:self.hintLabel];

    [self refreshTargetButton];
}

- (void)refreshTargetButton {
    NSString *bid = [[NSUserDefaults standardUserDefaults] stringForKey:kTargetBID];
    NSString *nm  = [[NSUserDefaults standardUserDefaults] stringForKey:kTargetName];
    NSString *t;
    if (bid.length) {
        t = [NSString stringWithFormat:@"目标应用：%@  (%@)", nm.length ? nm : bid, bid];
    } else {
        t = @"目标应用：未选择（点这里选择）";
    }
    [self.targetButton setTitle:t forState:UIControlStateNormal];
}

#pragma mark - 目标选择

- (void)onPickTarget {
    AppPickerController *vc = [AppPickerController new];
    __weak typeof(self) ws = self;
    vc.onPicked = ^(AXAppInfo *info) {
        __strong typeof(ws) s = ws;
        if (!s || !info.bundleID.length) return;
        [[NSUserDefaults standardUserDefaults] setObject:info.bundleID forKey:kTargetBID];
        [[NSUserDefaults standardUserDefaults] setObject:info.name forKey:kTargetName];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [s refreshTargetButton];
        s.hintLabel.text = [NSString stringWithFormat:@"已选目标：%@\n点「启动应用」拉起。", info.name];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    [self.mainWindow.rootViewController presentViewController:nav animated:YES completion:nil];
}

/// 首次启动自动挑一个已装游戏（样本针对 CFM / 王者这类目标）
- (void)autoDetectTarget {
    if ([[NSUserDefaults standardUserDefaults] stringForKey:kTargetBID].length) return;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<AXAppInfo *> *apps = [Launcher installedApps];
        AXAppInfo *hit = nil;

        NSArray<NSString *> *known = @[
            @"com.tencent.tmgp.sgame",      // 王者荣耀
            @"com.tencent.tmgp.cf",         // 穿越火线：枪战王者
            @"com.tencent.tmgp.pubgmhd",    // 和平精英
            @"com.tencent.tmgp.pubgm",
            @"com.tencent.tmgp.cod",
            @"com.tencent.ig",
        ];
        for (NSString *k in known) {
            for (AXAppInfo *a in apps) {
                if ([a.bundleID isEqualToString:k]) { hit = a; break; }
            }
            if (hit) break;
        }
        if (!hit) {
            for (AXAppInfo *a in apps) {
                if ([a.bundleID hasPrefix:@"com.tencent.tmgp."] ||
                    [a.name containsString:@"王者"] ||
                    [a.name containsString:@"和平"] ||
                    [a.name containsString:@"穿越火线"] ||
                    [a.name containsString:@"荣耀"]) { hit = a; break; }
            }
        }
        if (!hit) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSUserDefaults standardUserDefaults] setObject:hit.bundleID forKey:kTargetBID];
            [[NSUserDefaults standardUserDefaults] setObject:hit.name forKey:kTargetName];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self refreshTargetButton];
            self.hintLabel.text = [NSString stringWithFormat:@"已自动识别：%@", hit.name];
        });
    });
}

#pragma mark - 拉起

- (void)onLaunchTarget {
    NSString *bid = [[NSUserDefaults standardUserDefaults] stringForKey:kTargetBID];
    if (!bid.length) {
        [self onPickTarget];
        return;
    }

    // HUD 先就位，切回来自动还在
    [self ensureHUD];

    AXAppInfo *info = [Launcher infoForBundleID:bid];
    self.hintLabel.text = [NSString stringWithFormat:@"正在拉起 %@ …", info.name];

    __weak typeof(self) ws = self;
    [Launcher launchBundleID:bid
                     schemes:info.schemes
                  completion:^(BOOL ok, NSString *how) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) s = ws;
            if (!s) return;
            s.hintLabel.text = ok
                ? [NSString stringWithFormat:@"已拉起 %@（%@）\n切回来 HUD 仍在。", info.name, how]
                : [NSString stringWithFormat:@"拉起失败：%@\n点目标应用行换一个，或手动填 bundleID。", how];
        });
    }];
}

- (void)onStartHUD {
    [self ensureHUD];
    self.hintLabel.text = @"状态：HUD 已启动（点浮球展开菜单）";
}

#pragma mark - HUD

- (void)ensureHUD {
    if (self.hudWindow) {
        self.hudWindow.hidden = NO;
        [self.panel syncGeometry];
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
        s.launchButton.backgroundColor = c;
    };
    self.panel.onExit = ^ {
        __strong typeof(ws) s = ws;
        s.hudWindow.hidden = YES;
        s.hintLabel.text = @"状态：HUD 已退出";
    };
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
