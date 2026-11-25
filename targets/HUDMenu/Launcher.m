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
    for (AXAppInfo *i in [self installedApps]) {
        if ([i.bundleID isEqualToString:bundleID]) return i;
    }
    // 枚举不到也返回一条壳，至少 scheme 为空时还能直连 workspace
    AXAppInfo *i = [AXAppInfo new];
    i.bundleID = bundleID;
    i.name = bundleID;
    i.schemes = @[];
    return i;
}

#pragma mark - 拉起

+ (BOOL)launchBundleID:(NSString *)bundleID
               schemes:(NSArray<NSString *> *)schemes
            completion:(void (^)(BOOL, NSString *))completion {
    if (!bundleID.length) {
        if (completion) completion(NO, @"bundleID 为空");
        return NO;
    }

    // --- 通道 1：LaunchServices ---
    id ws = [self workspace];
    if (ws) {
        SEL s = NSSelectorFromString(@"openApplicationWithBundleID:");
        if ([ws respondsToSelector:s]) {
            BOOL (*fn)(id, SEL, NSString *) =
                (BOOL (*)(id, SEL, NSString *))[ws methodForSelector:s];
            BOOL ok = fn(ws, s, bundleID);
            if (ok) {
                if (completion) completion(YES, @"LSApplicationWorkspace");
                return YES;
            }
        }
    }

    // --- 通道 2：URL Scheme ---
    NSArray<NSString *> *list = schemes.count ? schemes : [self infoForBundleID:bundleID].schemes;
    for (NSString *sc in list) {
        if (![sc isKindOfClass:[NSString class]] || !sc.length) continue;
        NSString *str = [sc containsString:@"://"] ? sc : [sc stringByAppendingString:@"://"];
        NSURL *url = [NSURL URLWithString:str];
        if (!url) continue;
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL ok) {
            if (completion) completion(ok, ok ? [NSString stringWithFormat:@"scheme %@", sc]
                                              : [NSString stringWithFormat:@"scheme %@ 被系统拒绝", sc]);
        }];
        return YES;
    }

    if (completion) completion(NO, @"没有可用通道（workspace 拒绝 + 无 scheme）");
    return NO;
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
