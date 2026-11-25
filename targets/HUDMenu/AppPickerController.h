//
//  AppPickerController.h
//

#import <UIKit/UIKit.h>
#import "Launcher.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppPickerController : UITableViewController

/// 选中后回调（列表选中或手动输入都会走这里）
@property (nonatomic, copy, nullable) void (^onPicked)(AXAppInfo *info);

@end

NS_ASSUME_NONNULL_END
