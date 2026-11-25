//
//  AppDelegate.m — ScreenShield 演示
//  主窗口显示高对比内容；护盾开启后，截图应得到整屏深色。
//

#import "AppDelegate.h"
#import "AXScreenShield.h"

@interface AppDelegate ()
@property (nonatomic, strong) UIWindow *mainWindow;
@property (nonatomic, strong) AXScreenShield *shield;
@property (nonatomic, strong) UILabel *stateLabel;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s; break;
        }
    }
    self.mainWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                        : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.mainWindow.rootViewController = [UIViewController new];
    [self.mainWindow makeKeyAndVisible];

    UIView *root = self.mainWindow.rootViewController.view;
    root.backgroundColor = [UIColor colorWithRed:0.98 green:0.42 blue:0.18 alpha:1.0];

    UILabel *big = [[UILabel alloc] initWithFrame:CGRectInset(root.bounds, 24, 180)];
    big.numberOfLines = 0;
    big.textAlignment = NSTextAlignmentCenter;
    big.font = [UIFont monospacedDigitSystemFontOfSize:34 weight:UIFontWeightBold];
    big.textColor = UIColor.whiteColor;
    big.text = @"SCREENSHOT ME\n\n这张卡片应该\n在截图里消失";
    big.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root addSubview:big];

    UIButton *toggle = [UIButton buttonWithType:UIButtonTypeSystem];
    toggle.frame = CGRectMake(24, root.bounds.size.height - 140, root.bounds.size.width - 48, 52);
    toggle.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [toggle setTitle:@"护盾：开启（点一下切换）" forState:UIControlStateNormal];
    [toggle addTarget:self action:@selector(toggleShield:) forControlEvents:UIControlEventTouchUpInside];
    toggle.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    [root addSubview:toggle];

    self.stateLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, root.bounds.size.height - 84, root.bounds.size.width - 48, 28)];
    self.stateLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    self.stateLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.stateLabel.textColor = UIColor.whiteColor;
    [root addSubview:self.stateLabel];

    self.shield = [AXScreenShield shieldWithWindowScene:scene];
    [self.shield install];
    [self refreshState];
    return YES;
}

- (void)toggleShield:(UIButton *)sender {
    self.shield.enabled = !self.shield.enabled;
    if (self.shield.enabled) { [self.shield install]; } else { [self.shield uninstall]; }
    [self refreshState];
}

- (void)refreshState {
    self.stateLabel.text = [NSString stringWithFormat:@"shield=%@  captured=%@",
                            self.shield.enabled ? @"ON" : @"OFF",
                            UIScreen.mainScreen.isCaptured ? @"YES" : @"NO"];
}

@end
