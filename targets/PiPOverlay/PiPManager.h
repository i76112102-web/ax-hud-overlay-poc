//
//  PiPManager.h
//  免越狱跨 App 悬浮窗 —— 画中画 (PiP) 方案
//
//  原理：iOS 的画中画窗口由 SpringBoard/WindowServer 托管，属于系统级浮层，
//  可以显示在任意 App 之上。用 AVSampleBufferDisplayLayer 作为内容源，
//  就能把「任意自绘画面」送进 PiP 窗口，而不限于视频文件。
//
//  前提（Info.plist）：UIBackgroundModes = audio
//  前提（运行时）：
//    1) displayLayer 必须挂在**真正可见**的 view 上（不能离屏、不能 alpha≈0），
//       否则不会被合成，isPictureInPicturePossible 恒为 NO；
//    2) 必须先 enqueue 至少一帧，layer.status 进入 rendering；
//    3) AVAudioSession category = playback 且 active。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PiPManager : NSObject

@property (nonatomic, readonly) BOOL isPiPSupported;
@property (nonatomic, readonly) BOOL isPiPActive;
@property (nonatomic, readonly) BOOL isPiPPossible;

/// PiP 真正进入浮窗态后回调（用于「浮窗就绪 → 再拉起目标 App」的时序）
@property (nonatomic, copy, nullable) void (^onPiPStarted)(void);

/// 用户在 PiP 浮窗上点了播放/暂停。浮窗手势被系统接管，
/// 这是唯一能从浮窗侧传回触摸意图的通道 —— 用它做「点图标展开菜单」。
@property (nonatomic, copy, nullable) void (^onPlayPauseTapped)(BOOL playing);

/// 状态变化回调：失败原因、possible 变化、音频会话结果都从这里出来
@property (nonatomic, copy, nullable) void (^logHandler)(NSString *line);

/// 静音音频保活，默认 YES。切到目标 App 后进程靠它继续跑，才能持续推帧。
@property (nonatomic, assign) BOOL keepAliveEnabled;

/// YES = video-call 型 PiP（无播放控件、小图标，AX 风格）；NO = sampleBuffer 播放型（有播放键/进度条）。
/// 默认 YES。必须在 attachToView 之前设置。
@property (nonatomic, assign) BOOL useIconStyle;

/// 图标模式下点球回调：用于切换 HUD 菜单展开/收起
@property (nonatomic, copy, nullable) void (^onIconTapped)(void);

+ (instancetype)shared;

/// 把内容层挂到一个**可见**的 view 上（预览框）。挂载后立刻推一帧，
/// 让 layer 尽快进入 rendering —— 这是 isPictureInPicturePossible 变 YES 的前提。
- (void)attachToView:(UIView *)view;

/// 发起 PiP。YES = 已同步调用 startPictureInPicture；
/// NO = 看 logHandler 输出的原因（possible 尚未就绪时会自动排队，等 KVO 变 YES 再启动）。
- (BOOL)startPiP;
- (void)stopPiP;

/// 推送一帧画面（例如把当前 UI 渲染成 UIImage 后送进来）
- (void)pushImage:(UIImage *)image;

/// 推送一帧 CVPixelBuffer（零拷贝路径，性能更好）
- (void)pushPixelBuffer:(CVPixelBufferRef)pixelBuffer;

/// 一次性诊断快照，直接可读，用于屏内显示
- (NSString *)diagnostics;

@end

NS_ASSUME_NONNULL_END
