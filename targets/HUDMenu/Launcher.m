//
//  Launcher.m
//

#import "Launcher.h"
#import <objc/message.h>
#import <objc/runtime.h>

@implementation AXAppInfo
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@ schemes=%@>", self.name, self.bundleID, self.schemes];
}
@end

// 只用于「返回对象」的 getter。返回 BOOL / 结构体的方法不要走这里。
static id AXCall0(id obj, NSString *selName) {
    if (!obj) return nil;
    SEL s = NSSelectorFromString(selName);
    if (![obj respondsToSelector:s]) return nil;
    id (*fn)(id, SEL) = (id (*)(id, SEL))[obj methodForSelector:s];
    return fn(obj, s);
}

static NSArray<AXAppInfo *> *gCache = nil;
static NSTimeInterval gCacheAt = 0;

@implementation Launcher

+ (id)workspace {
    Class C = NSClassFromString(@"LSApplicationWorkspace");
    if (!C) return nil;
    return AXCall0((id)C, @"defaultWorkspace");
}

/// 内置 scheme 表。workspace 枚举被系统拒绝时，这是唯一可靠通道。
/// 值取自目标 App 自身 Info.plist 注册的 CFBundleURLSchemes。
+ (NSDictionary<NSString *, NSArray<NSString *> *> *)builtinSchemes {
    static NSDictionary *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @{
            // 王者荣耀 iOS（可执行 smoba）
            @"com.tencent.smoba": @[@"tencentlaunch1104466820",
                                    @"smoba1104466820",
                                    @"tencentmsdk1104466820"],
            // 和平精英（可执行 ShadowTrackerExtra）
            @"com.tencent.tmgp.pubgmhd": @[@"tencentlaunch1106467070",
                                           @"pubgmhd1106467070",
                                           @"tencent1106467070"],
        };
    });
    return d;
}

+ (NSDictionary<NSString *, NSString *> *)builtinNames {
    static NSDictionary *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @{
            @"com.tencent.smoba": @"王者荣耀",
            @"com.tencent.tmgp.pubgmhd": @"和平精英",
        };
    });
    return d;
}

#pragma mark - 枚举

+ (NSArray<AXAppInfo *> *)installedApps {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (gCache && now - gCacheAt < 3.0) return gCache;

    id ws = [self workspace];
    if (!ws) { gCache = @[]; gCacheAt = now; return gCache; }

    NSArray *raw = nil;
    for (NSString *sel in @[@"allInstalledApplications", @"allApplications"]) {
        id v = AXCall0(ws, sel);
        if ([v isKindOfClass:[NSArray class]] && [(NSArray *)v count]) { raw = v; break; }
    }
    if (!raw) { gCache = @[]; gCacheAt = now; return gCache; }

    NSMutableArray<AXAppInfo *> *out = [NSMutableArray array];
    for (id p in raw) {
        @autoreleasepool {
            NSString *type = AXCall0(p, @"applicationType");
            if ([type isKindOfClass:[NSString class]] && ![type isEqualToString:@"User"]) continue;

            NSString *bid = AXCall0(p, @"bundleIdentifier");
            if (![bid isKindOfClass:[NSString class]] || !bid.length) continue;
            if ([bid hasPrefix:@"com.apple."]) continue;
            if ([bid isEqualToString:@"local.poc.hudmenu"]) continue;

            NSString *name = nil;
            for (NSString *k in @[@"localizedName", @"itemName", @"shortVersionString"]) {
                id v = AXCall0(p, k);
                if ([v isKindOfClass:[NSString class]] && [v length]) { name = v; break; }
            }

            AXAppInfo *info = [AXAppInfo new];
            info.bundleID = bid;
            info.name = name.length ? name : bid;
            info.schemes = [self schemesOfProxy:p] ?: @[];
            [out addObject:info];
        }
    }

    [out sortUsingComparator:^NSComparisonResult(AXAppInfo *a, AXAppInfo *b) {
        return [a.name localizedStandardCompare:b.name];
    }];

    gCache = out.copy;
    gCacheAt = now;
    return gCache;
}

+ (NSArray<NSString *> *)schemesOfProxy:(id)p {
    id v = AXCall0(p, @"registeredURLSchemes");
    if (!v) {
        @try { v = [p valueForKey:@"registeredURLSchemes"]; } @catch (NSException *e) { v = nil; }
    }
    NSMutableArray<NSString *> *r = [NSMutableArray array];
    if ([v isKindOfClass:[NSDictionary class]]) {
        for (id k in [(NSDictionary *)v allKeys]) {
            if ([k isKindOfClass:[NSString class]]) [r addObject:k];
        }
    } else if ([v isKindOfClass:[NSArray class]]) {
        for (id k in (NSArray *)v) {
            if ([k isKindOfClass:[NSString class]]) [r addObject:k];
        }
    }
    return r;
}

+ (AXAppInfo *)infoForBundleID:(NSString *)bundleID {
    if (!bundleID.length) return nil;

    AXAppInfo *found = nil;
    for (AXAppInfo *i in [self installedApps]) {
        if ([i.bundleID isEqualToString:bundleID]) { found = i; break; }
    }

    NSArray<NSString *> *builtin = [self builtinSchemes][bundleID];
    NSString *builtinName = [self builtinNames][bundleID];

    if (found) {
        if (builtin.count) {
            NSMutableArray<NSString *> *m = [NSMutableArray arrayWithArray:builtin];
            for (NSString *s in found.schemes) {
                if (![m containsObject:s]) [m addObject:s];
            }
            found.schemes = m;
        }
        if (!found.name.length || [found.name isEqualToString:found.bundleID]) {
            if (builtinName.length) found.name = builtinName;
        }
        return found;
    }

    // 枚举不到也返回一条壳：scheme 来自内置表，至少还能拉起
    AXAppInfo *i = [AXAppInfo new];
    i.bundleID = bundleID;
    i.name = builtinName.length ? builtinName : bundleID;
    i.schemes = builtin ?: @[];
    return i;
}

#pragma mark - 拉起

// 依次试一组 scheme，任一成功即停
+ (void)trySchemes:(NSArray<NSString *> *)list
             index:(NSInteger)idx
        completion:(void (^)(BOOL ok, NSString *how))completion {
    if (idx >= (NSInteger)list.count) {
        if (completion) completion(NO, @"scheme 全部失败");
        return;
    }
    NSString *sc = list[idx];
    if (![sc isKindOfClass:[NSString class]] || !sc.length) {
        [self trySchemes:list index:idx + 1 completion:completion];
        return;
    }
    NSString *str = [sc containsString:@"://"] ? sc : [sc stringByAppendingString:@"://"];
    NSURL *url = [NSURL URLWithString:str];
    if (!url) {
        [self trySchemes:list index:idx + 1 completion:completion];
        return;
    }
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL ok) {
        if (ok) {
            if (completion) completion(YES, [NSString stringWithFormat:@"scheme %@", sc]);
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self trySchemes:list index:idx + 1 completion:completion];
        });
    }];
}

+ (BOOL)launchViaWorkspace:(NSString *)bundleID {
    id ws = [self workspace];
    if (!ws) return NO;
    SEL s = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (![ws respondsToSelector:s]) return NO;
    BOOL (*fn)(id, SEL, NSString *) = (BOOL (*)(id, SEL, NSString *))[ws methodForSelector:s];
    return fn(ws, s, bundleID);
}

+ (BOOL)launchBundleID:(NSString *)bundleID
               schemes:(NSArray<NSString *> *)schemes
            completion:(void (^)(BOOL, NSString *))completion {
    if (!bundleID.length) {
        if (completion) completion(NO, @"bundleID 为空");
        return NO;
    }

    NSArray<NSString *> *list = schemes;
    if (!list.count) list = [self builtinSchemes][bundleID];
    if (!list.count) list = [self infoForBundleID:bundleID].schemes;

    // 有 scheme 就走 scheme：注册过的 scheme 走 SpringBoard 打开，确定性最高，
    // 不依赖 LaunchServices 私有接口在自签包上是否被放行。
    if (list.count) {
        [self trySchemes:list index:0 completion:^(BOOL ok, NSString *how) {
            if (ok) {
                if (completion) completion(YES, how);
                return;
            }
            BOOL ls = [self launchViaWorkspace:bundleID];
            if (completion) {
                completion(ls, ls ? @"LSApplicationWorkspace"
                                  : [NSString stringWithFormat:@"scheme 与 workspace 均失败（%@）", how]);
            }
        }];
        return YES;
    }

    BOOL ls = [self launchViaWorkspace:bundleID];
    if (completion) {
        completion(ls, ls ? @"LSApplicationWorkspace"
                          : @"没有可用通道（workspace 拒绝 + 无 scheme）");
    }
    return ls;
}

+ (BOOL)openScheme:(NSString *)scheme completion:(void (^)(BOOL))completion {
    if (!scheme.length) return NO;
    NSString *str = [scheme containsString:@"://"] ? scheme : [scheme stringByAppendingString:@"://"];
    NSURL *url = [NSURL URLWithString:str];
    if (!url) return NO;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL ok) {
        if (completion) completion(ok);
    }];
    return YES;
}

@end
