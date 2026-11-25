//
//  TouchInjector.m
//  私有 UITouch / UIEvent 构造与投递
//
//  对应 AX Pro Max 里的：
//    _addTouch:forDelayedDelivery:
//    _setLocationInWindow:resetPrevious:
//    _setIsFirstTouchForView:
//    _touchesEvent
//    STPendingTouchAction
//
//  用途：在「容器内虚拟运行」方案里，把 HUD 上采集到的触摸
//  转发给同进程内虚拟运行的目标 App。
//  注意：它仅在本进程内有效。想让别的进程收到触摸，
//  必须走 IOHIDEventSystemClient / BKSHIDEvent 那条路（需要更高权限）。
//

#import "TouchInjector.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

@implementation TouchInjector

+ (UITouch *)makeTouchAt:(CGPoint)pt
                  inView:(UIView *)view
                  window:(UIWindow *)window
                   phase:(UITouchPhase)phase {
    UITouch *t = [UITouch new];

    // 用 KVC 直接写私有 ivar（比调用私有方法稳定）
    @try {
        [t setValue:view forKey:@"view"];
        [t setValue:window forKey:@"window"];
        [t setValue:[NSValue valueWithCGPoint:pt] forKey:@"locationInWindow"];
        [t setValue:[NSValue valueWithCGPoint:pt] forKey:@"previousLocationInWindow"];
        [t setValue:@(phase) forKey:@"phase"];
        [t setValue:@(CACurrentMediaTime()) forKey:@"timestamp"];
        [t setValue:@(1) forKey:@"tapCount"];
        [t setValue:@(0.0) forKey:@"force"];
        [t setValue:@(0.0) forKey:@"maximumPossibleForce"];
    } @catch (NSException *e) {
        NSLog(@"[touch] kvc failed: %@", e);
        return nil;
    }
    return t;
}

+ (UIEvent *)makeEventWithTouches:(NSSet<UITouch *> *)touches {
    UIEvent *e = [UIEvent new];
    // _touches 是 NSSet（iOS 上内部存的是 NSMutableSet）
    @try {
        [e setValue:touches forKey:@"touches"];
    } @catch (NSException *ex) {
        // 退路：私有方法 _addTouch:forDelayedDelivery:
        SEL sel = NSSelectorFromString(@"_addTouch:forDelayedDelivery:");
        if ([e respondsToSelector:sel]) {
            for (UITouch *t in touches) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(e, sel, t, NO);
            }
        }
    }
    return e;
}

+ (void)tapAt:(CGPoint)pt inView:(UIView *)view window:(UIWindow *)window {
    UITouch *down = [self makeTouchAt:pt inView:view window:window phase:UITouchPhaseBegan];
    UITouch *up   = [self makeTouchAt:pt inView:view window:window phase:UITouchPhaseEnded];

    if (down) {
        UIEvent *e1 = [self makeEventWithTouches:[NSSet setWithObject:down]];
        [window sendEvent:e1];
    }
    if (up) {
        UIEvent *e2 = [self makeEventWithTouches:[NSSet setWithObject:up]];
        [window sendEvent:e2];
    }
}

+ (void)touchDownAt:(CGPoint)pt inView:(UIView *)view window:(UIWindow *)window {
    UITouch *t = [self makeTouchAt:pt inView:view window:window phase:UITouchPhaseBegan];
    if (t) [window sendEvent:[self makeEventWithTouches:[NSSet setWithObject:t]]];
}

+ (void)touchMoveAt:(CGPoint)pt inView:(UIView *)view window:(UIWindow *)window {
    UITouch *t = [self makeTouchAt:pt inView:view window:window phase:UITouchPhaseMoved];
    if (t) [window sendEvent:[self makeEventWithTouches:[NSSet setWithObject:t]]];
}

+ (void)touchUpAt:(CGPoint)pt inView:(UIView *)view window:(UIWindow *)window {
    UITouch *t = [self makeTouchAt:pt inView:view window:window phase:UITouchPhaseEnded];
    if (t) [window sendEvent:[self makeEventWithTouches:[NSSet setWithObject:t]]];
}

@end
