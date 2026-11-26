//
//  PiPManager.m
//

#import "PiPManager.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>

@interface PiPManager () <AVPictureInPictureControllerDelegate,
                          AVPictureInPictureSampleBufferPlaybackDelegate>
@property (nonatomic, strong) AVSampleBufferDisplayLayer *displayLayer;
@property (nonatomic, strong) AVPictureInPictureController *pip;
/// 必须强引用，历史上出现过 controller 不持有 contentSource 就静默失效的情况
@property (nonatomic, strong) AVPictureInPictureControllerContentSource *contentSource;
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) CMTime pushedTime;
@property (nonatomic, strong, nullable) AVAudioPlayer *keepAlivePlayer;
@property (nonatomic, assign) BOOL framePushed;
@property (nonatomic, assign) BOOL pendingStart;
@property (nonatomic, assign) BOOL observing;
@end

@implementation PiPManager

+ (instancetype)shared {
    static PiPManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [PiPManager new]; });
    return s;
}

- (instancetype)init {
    if (self = [super init]) { _keepAliveEnabled = YES; }
    return self;
}

- (void)dealloc {
    if (self.observing && self.pip) {
        [self.pip removeObserver:self forKeyPath:@"pictureInPicturePossible"];
    }
}

#pragma mark - 日志

- (void)log:(NSString *)fmt, ... {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[PiP] %@", msg);
    if (self.logHandler) {
        self.logHandler(msg);
    }
}

#pragma mark - 状态

- (BOOL)isPiPSupported {
    if (@available(iOS 15.0, *)) {
        return [AVPictureInPictureController isPictureInPictureSupported];
    }
    return NO;
}

- (BOOL)isPiPActive {
    return self.pip.isPictureInPictureActive;
}

- (BOOL)isPiPPossible {
    return self.pip.isPictureInPicturePossible;
}

- (NSString *)diagnostics {
    NSString *status = @"?";
    switch (self.displayLayer.status) {
        case AVQueuedSampleBufferRenderingStatusUnknown:   status = @"unknown"; break;
        case AVQueuedSampleBufferRenderingStatusRendering: status = @"rendering"; break;
        case AVQueuedSampleBufferRenderingStatusFailed:    status = @"FAILED"; break;
    }
    CGSize sz = self.hostView ? self.hostView.bounds.size : CGSizeZero;
    return [NSString stringWithFormat:
            @"support=%d pip=%d poss=%d act=%d\nlayer=%@ ready=%d %.0fx%.0f host=%@ err=%@",
            self.isPiPSupported,
            self.pip != nil,
            self.pip.isPictureInPicturePossible,
            self.pip.isPictureInPictureActive,
            status,
            self.displayLayer.isReadyForDisplay,
            sz.width, sz.height,
            self.hostView ? @"yes" : @"nil",
            self.displayLayer.error.localizedDescription ?: @"-"];
}

#pragma mark - 挂载

- (void)attachToView:(UIView *)view {
    if (!view) {
        [self log:@"attach: view 为 nil"];
        return;
    }
    self.hostView = view;

    if (!self.displayLayer) {
        self.displayLayer = [AVSampleBufferDisplayLayer layer];
        self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    }
    self.displayLayer.frame = view.bounds;
    if (self.displayLayer.superlayer != view.layer) {
        [self.displayLayer removeFromSuperlayer];
        [view.layer addSublayer:self.displayLayer];
    }

    [self log:@"attach %.0fx%.0f  support=%d",
         view.bounds.size.width, view.bounds.size.height, self.isPiPSupported];

    [self setupController];

    // 立刻推一帧：layer 只有拿到样本才会进 rendering，possible 才可能变 YES
    [self pushPlaceholderIfNeeded];
}

- (void)setupController {
    if (self.pip) return;
    if (!self.isPiPSupported) {
        [self log:@"❌ 本机不支持 PiP（isPictureInPictureSupported=NO）"];
        return;
    }
    if (!self.displayLayer) {
        [self log:@"❌ displayLayer 未创建"];
        return;
    }
    if (@available(iOS 15.0, *)) {
        self.contentSource =
            [[AVPictureInPictureControllerContentSource alloc]
                initWithSampleBufferDisplayLayer:self.displayLayer
                                playbackDelegate:self];
        AVPictureInPictureController *pip =
            [[AVPictureInPictureController alloc] initWithContentSource:self.contentSource];
        pip.delegate = self;
        // FIX: startPictureInPicture is invoked from the KVO callback
        // (async, outside the button's gesture stack). iOS silently rejects
        // that unless automatic inline start is enabled.
        pip.canStartPictureInPictureAutomaticallyFromInline = YES;
        self.pip = pip;

        // FIX: activate a movie-playback audio session up front so that
        // pictureInPicturePossible can turn YES as soon as the first frame is
        // rendered, instead of only after the user taps the button.
        NSError *aerr = nil;
        AVAudioSession *as = [AVAudioSession sharedInstance];
        [as setCategory:AVAudioSessionCategoryPlayback
                   mode:AVAudioSessionModeMoviePlayback
                options:0 error:&aerr];
        [as setActive:YES error:&aerr];

        [pip addObserver:self
              forKeyPath:@"pictureInPicturePossible"
                 options:NSKeyValueObservingOptionNew
                 context:NULL];
        self.observing = YES;
        [self log:@"controller 已创建，audio session 已激活，开始监听 possible"];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (![keyPath isEqualToString:@"pictureInPicturePossible"]) return;
    BOOL now = [change[NSKeyValueChangeNewKey] boolValue];
    [self log:@"possible → %d%@", now, now ? @"" : @"（需 layer 完成首帧渲染）"];

    if (now && self.pendingStart && !self.pip.isPictureInPictureActive) {
        self.pendingStart = NO;
        [self log:@"排队中的启动请求现在执行"];
        [self.pip startPictureInPicture];
    }
}

#pragma mark - 控制

- (BOOL)startPiP {
    [self setupController];

    if (!self.pip) {
        [self log:@"❌ 无法启动：controller 不存在（不支持或未 attach）"];
        return NO;
    }
    if (self.pip.isPictureInPictureActive) {
        [self log:@"已经在 PiP 中"];
        return NO;
    }

    NSError *err = nil;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    if (![s setCategory:AVAudioSessionCategoryPlayback
                   mode:AVAudioSessionModeMoviePlayback
                options:0
                  error:&err]) {
        [self log:@"⚠️ setCategory 失败: %@", err.localizedDescription];
    }
    err = nil;
    if (![s setActive:YES error:&err]) {
        [self log:@"⚠️ setActive 失败: %@", err.localizedDescription];
    }
    [self log:@"audio session: cat=%@ active=%d",
         s.category, s.isOtherAudioPlaying ? 0 : 1];

    [self startKeepAlive];

    self.playing = YES;
    [self pushPlaceholderIfNeeded];

    [self log:@"start: possible=%d ready=%d status=%@",
         self.pip.isPictureInPicturePossible,
         self.displayLayer.isReadyForDisplay,
         (self.displayLayer.status == AVQueuedSampleBufferRenderingStatusRendering) ? @"rendering" : @"not-rendering"];

    if (self.pip.isPictureInPicturePossible) {
        [self.pip startPictureInPicture];
        [self log:@"→ startPictureInPicture 已调用"];
        return YES;
    }

    self.pendingStart = YES;
    [self log:@"⏳ possible 还没就绪，已排队；一旦变 YES 立即启动"];
    return NO;
}

- (void)stopPiP {
    self.playing = NO;
    self.pendingStart = NO;
    if (self.pip.isPictureInPictureActive) {
        [self.pip stopPictureInPicture];
    }
    [self stopKeepAlive];
}

#pragma mark - 静音保活

- (void)startKeepAlive {
    if (!self.keepAliveEnabled || self.keepAlivePlayer.isPlaying) return;
    NSData *wav = [self silentWAVDataWithSeconds:2];
    if (!wav) return;
    NSError *e = nil;
    AVAudioPlayer *p = [[AVAudioPlayer alloc] initWithData:wav error:&e];
    if (e || !p) { [self log:@"keepalive 失败: %@", e.localizedDescription]; return; }
    p.numberOfLoops = -1;
    [p prepareToPlay];
    [p play];
    self.keepAlivePlayer = p;
    [self log:@"keepalive 已启动（2s 静音循环）"];
}

- (void)stopKeepAlive {
    [self.keepAlivePlayer stop];
    self.keepAlivePlayer = nil;
}

/// 内存里拼一段 WAV（16-bit mono 8kHz）。
/// 采样值取 ±1 而不是全 0：全零会被某些版本判定为「未在输出音频」而克扣后台时间。
- (NSData *)silentWAVDataWithSeconds:(NSUInteger)sec {
    const uint32_t rate = 8000;
    uint32_t frames = (uint32_t)(rate * sec);
    uint32_t dataBytes = frames * 2;
    NSMutableData *d = [NSMutableData dataWithCapacity:44 + dataBytes];

    void (^put32)(uint32_t) = ^(uint32_t v) { [d appendBytes:&v length:4]; };
    void (^put16)(uint16_t) = ^(uint16_t v) { [d appendBytes:&v length:2]; };

    [d appendBytes:"RIFF" length:4];
    put32(36 + dataBytes);
    [d appendBytes:"WAVEfmt " length:8];
    put32(16); put16(1); put16(1); put32(rate); put32(rate * 2); put16(2); put16(16);
    [d appendBytes:"data" length:4];
    put32(dataBytes);

    NSMutableData *pcm = [NSMutableData dataWithLength:dataBytes];
    int16_t *s = (int16_t *)pcm.mutableBytes;
    for (uint32_t i = 0; i < frames; i++) {
        s[i] = (i & 1) ? 1 : -1;   // ±1 LSB，人耳不可闻
    }
    [d appendData:pcm];
    return d;
}

#pragma mark - 推帧

/// 首帧占位：layer 没有样本时 possible 恒为 NO，这里先塞一帧纯色
- (void)pushPlaceholderIfNeeded {
    if (self.framePushed || !self.displayLayer) return;
    self.framePushed = YES;
    CGSize sz = CGSizeMake(480, 270);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sz format:fmt];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextSetRGBFillColor(ctx.CGContext, 0.08, 0.08, 0.09, 1);
        CGContextFillRect(ctx.CGContext, CGRectMake(0, 0, sz.width, sz.height));
    }];
    [self pushImage:img];
    [self log:@"已推送占位首帧 %.0fx%.0f", sz.width, sz.height];
    // 首帧之后补一帧，部分机型要两帧才 ready
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self pushImage:img];
    });
}

- (void)pushImage:(UIImage *)image {
    if (!image) return;
    CVPixelBufferRef pb = [self pixelBufferFromImage:image];
    if (pb) {
        [self pushPixelBuffer:pb];
        CVPixelBufferRelease(pb);
    }
}

- (void)pushPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer || !self.displayLayer) return;

    CMVideoFormatDescriptionRef fmt = NULL;
    OSStatus st = CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault, pixelBuffer, &fmt);
    if (st != noErr || !fmt) return;

    self.pushedTime = CMTimeAdd(self.pushedTime, CMTimeMake(1, 30));

    CMSampleTimingInfo timing = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = self.pushedTime,
        .decodeTimeStamp = kCMTimeInvalid,
    };

    CMSampleBufferRef sbuf = NULL;
    st = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault, pixelBuffer, fmt, &timing, &sbuf);
    CFRelease(fmt);
    if (st != noErr || !sbuf) return;

    if (self.displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        [self log:@"layer 进入 failed，flush 后重试"];
        [self.displayLayer flush];
    }
    [self.displayLayer enqueueSampleBuffer:sbuf];
    CFRelease(sbuf);
}

#pragma mark - UIImage -> CVPixelBuffer

- (CVPixelBufferRef)pixelBufferFromImage:(UIImage *)image {
    CGSize size = image.size;
    if (size.width < 1 || size.height < 1) return NULL;

    NSDictionary *attrs = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
        (id)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
    };
    CVPixelBufferRef pb = NULL;
    CVReturn r = CVPixelBufferCreate(kCFAllocatorDefault,
                                     (size_t)size.width, (size_t)size.height,
                                     kCVPixelFormatType_32BGRA,
                                     (__bridge CFDictionaryRef)attrs, &pb);
    if (r != kCVReturnSuccess || !pb) return NULL;

    CVPixelBufferLockBaseAddress(pb, 0);
    void *base = CVPixelBufferGetBaseAddress(pb);
    size_t bpr = CVPixelBufferGetBytesPerRow(pb);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(base, (size_t)size.width, (size_t)size.height,
                                             8, bpr, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (ctx) {
        UIGraphicsPushContext(ctx);
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
        UIGraphicsPopContext();
        CGContextRelease(ctx);
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
    return pb;
}

#pragma mark - AVPictureInPictureControllerDelegate

- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)c {
    [self log:@"will start"];
}

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)c {
    [self log:@"✅ PiP 已启动"];
    if (self.onPiPStarted) self.onPiPStarted();
}

- (void)pictureInPictureController:(AVPictureInPictureController *)c
        failedToStartPictureInPictureWithError:(NSError *)error {
    [self log:@"❌ PiP 启动失败: %@ (%ld)", error.localizedDescription, (long)error.code];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)c {
    [self log:@"PiP 已停止"];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)c
restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completionHandler {
    completionHandler(YES);
}

#pragma mark - 必须实现的播放代理（否则无法进入 PiP）

- (void)pictureInPictureController:(AVPictureInPictureController *)c
                       setPlaying:(BOOL)playing {
    self.playing = playing;
    // 浮窗内点播放/暂停 —— 唯一能回传到本进程的浮窗手势
    if (self.onPlayPauseTapped) self.onPlayPauseTapped(playing);
}

- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:(AVPictureInPictureController *)c {
    // 无限时长，PiP 才不会因为「播完」自动退出
    return CMTimeRangeMake(kCMTimeZero, kCMTimePositiveInfinity);
}

- (BOOL)pictureInPictureControllerIsPlaybackPaused:(AVPictureInPictureController *)c {
    return !self.playing;
}

- (void)pictureInPictureController:(AVPictureInPictureController *)c
             didTransitionToRenderSize:(CMVideoDimensions)newRenderSize {
}

- (void)pictureInPictureController:(AVPictureInPictureController *)c
                     skipByInterval:(CMTime)skipInterval
                  completionHandler:(void (^)(void))completionHandler {
    completionHandler();
}

@end
