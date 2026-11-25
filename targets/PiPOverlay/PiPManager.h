//
//  PiPManager.h
//  免越狱跨 App 悬浮窗 —— 画中画 (PiP) 方案
//
//  原理：iOS 的画中画窗口由 SpringBoard/WindowServer 托管，
//  属于系统级浮层，可以显示在任意 App 之上。
//  用 AVSampleBufferDisplayLayer 作为内容源，就能把「任意自绘画面」
//  送进 PiP 窗口，而不限于视频文件。
//
//  前提（Info.plist）：
//    UIBackgroundModes = audio
//  前提（运行时）：
//    AVAudioSession category = playback，且 active
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PiPManager : NSObject

@property (nonatomic, readonly) BOOL isPiPSupported;
@property (nonatomic, readonly) BOOL isPiPActive;

/// PiP 真正进入浮窗态后回调（用于「浮窗就绪 → 再拉起目标 App」的时序）
@property (nonatomic, copy, nullable) void (^onPiPStarted)(void);

/// 静音音频保活，默认 YES。切到目标 App 后进程靠它继续跑，才能持续推帧。
@property (nonatomic, assign) BOOL keepAliveEnabled;

+ (instancetype)shared;

/// 绑定一个宿主窗口（PiP 内容层会挂上去，建议隐藏或放在屏幕外）
- (void)attachToWindow:(UIWindow *)window;

/// 启动 / 停止 PiP
- (void)startPiP;
- (void)stopPiP;

/// 推送一帧画面（例如把当前 UI 渲染成 UIImage 后送进来）
- (void)pushImage:(UIImage *)image;

/// 推送一帧 CVPixelBuffer（零拷贝路径，性能更好）
- (void)pushPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
