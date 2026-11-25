//
//  AppDelegate.m  (HUDKeepAlive)
//  演示：最高层悬浮窗 + 静音音频保活 + 私有触摸投递
//

#import "AppDelegate.h"
#import "HUDWindow.h"
#import "AudioKeepAlive.h"
#import "TouchInjector.h"

@interface AppDelegate ()
@property (nonatomic, strong) UIWindow *mainWindow;
@property (nonatomic, strong) HUDWindow *hud;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.mainWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithWhite:0.09 alpha:1];
    self.mainWindow.rootViewController = root;
    [self.mainWindow makeKeyAndVisible];

    // 1. 保活
    [[AudioKeepAlive shared] start];

    // 2. 悬浮窗
    self.hud = [HUDWindow showHUD];
    __weak typeof(self) weakSelf = self;
    self.hud.onTap = ^{
        // 演示：点击浮球 → 向"虚拟 App 的视图"投递一次点击
        UIWindow *under = weakSelf.mainWindow;
        [TouchInjector tapAt:CGPointMake(160, 300)
                       inView:under.rootViewController.view
                       window:under];
        NSLog(@"[demo] injected tap");
    };

    return YES;
}

@end
