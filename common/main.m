//
//  main.m  —— 三个 target 共用
//
//  纯 clang 构建，不依赖 .xcodeproj / xcodegen。
//  AppDelegate 类名统一，入口直接取。
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
