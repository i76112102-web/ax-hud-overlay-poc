//
//  AppPickerController.m
//

#import "AppPickerController.h"

@interface AppPickerController ()
@property (nonatomic, strong) NSArray<AXAppInfo *> *apps;
@end

@implementation AppPickerController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"选择目标应用";
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.08];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(onCancel)];

    // 枚举放到后台，避免 workspace 首次调用卡主线程
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<AXAppInfo *> *list = [Launcher installedApps];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.apps = list;
            [self.tableView reloadData];
        });
    });
}

- (void)onCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    return self.apps.count ? self.apps.count : 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"其它";
    return self.apps.count
        ? [NSString stringWithFormat:@"已安装 %lu 个", (unsigned long)self.apps.count]
        : @"已安装 App";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (section != 1) return nil;
    if (self.apps.count) return @"列表来自 LaunchServices。找不到目标时用上面的手动输入。";
    return @"枚举不到已安装 App：workspace 被系统拒绝。请手动输入目标的 bundleID。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"cell";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    }
    c.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
    c.textLabel.textColor = [UIColor whiteColor];
    c.detailTextLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.4];
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.accessoryType = UITableViewCellAccessoryNone;

    if (ip.section == 0) {
        c.textLabel.text = @"手动输入 bundleID…";
        c.detailTextLabel.text = @"workspace 枚举不到时用这条";
    } else if (self.apps.count == 0) {
        c.textLabel.text = @"（空）";
        c.detailTextLabel.text = nil;
    } else {
        AXAppInfo *a = self.apps[ip.row];
        c.textLabel.text = a.name;
        c.detailTextLabel.text = a.bundleID;
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == 0) {
        [self askManual];
        return;
    }
    if (self.apps.count == 0) return;

    AXAppInfo *a = self.apps[ip.row];
    if (self.onPicked) self.onPicked(a);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)askManual {
    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:@"目标 bundleID"
                                            message:@"例如 com.tencent.tmgp.sgame"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"com.example.game";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        NSString *bid = ac.textFields.firstObject.text;
        bid = [bid stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!bid.length) return;
        AXAppInfo *a = [Launcher infoForBundleID:bid];
        if (s.onPicked) s.onPicked(a);
        [s dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
