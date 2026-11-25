//
//  Launcher.h
//  免越狱拉起本机已安装的其它 App（对应样本 AXZQBundleEnumerator 的外部等价物）
//
//  两条通道，按成功率排序：
//    1. LSApplicationWorkspace -openApplicationWithBundleID:
//       LaunchServices 私有接口。非越狱设备上自签 / 企业签 App 可用，
//       App Store 上架会被审核拒，但侧载没有这个约束。
//    2. 目标 App 自己注册的 URL Scheme → UIApplication -openURL:options:
//       公开接口，只要 scheme 已注册就能起。openURL 不受
//       LSApplicationQueriesSchemes 白名单限制（白名单只限制 canOpenURL）。
//
//  拿不到 workspace 时（极少数系统版本），退回手动填 bundleID。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AXAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
/// 该 App 注册的 URL scheme（来自 LSApplicationProxy，可能为空）
@property (nonatomic, copy) NSArray<NSString *> *schemes;
@end

@interface Launcher : NSObject

/// 枚举本机用户 App（过滤掉系统 App）。workspace 不可用时返回空数组。
+ (NSArray<AXAppInfo *> *)installedApps;

/// 按 bundleID 取一条（取自 installedApps，带内部缓存）
+ (nullable AXAppInfo *)infoForBundleID:(NSString *)bundleID;

/// 拉起。返回 YES 表示已发起（不代表目标一定切到前台，见下方 completion）
+ (BOOL)launchBundleID:(NSString *)bundleID
               schemes:(nullable NSArray<NSString *> *)schemes
            completion:(nullable void (^)(BOOL ok, NSString *how))completion;

/// 只试 URL Scheme，不碰私有接口
+ (BOOL)openScheme:(NSString *)scheme completion:(nullable void (^)(BOOL ok))completion;

@end

NS_ASSUME_NONNULL_END
