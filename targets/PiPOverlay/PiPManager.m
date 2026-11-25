//
//  PiPManager.m
//

#import "PiPManager.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>

@interface PiPManager () <AVPictureInPictureControllerDelegate,
                          AVPictureInPictureSampleBufferPlaybackDelegate>
@property (nonatomic, strong) AVSampleBufferDisplayLayer *displayLayer;
@property (nonatomic, strong) AVPictureInPictureController *pip;
@property (nonatomic, strong) UIWindow *hostWindow;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) CMTime pushedTime;
@property (nonatomic, strong, nullable) AVAudioPlayer *keepAlivePlayer;
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

- (BOOL)isPiPSupported {
    return [AVPictureInPictureController isPictureInPictureSupported];
}

- (BOOL)isPiPActive {
    return self.pip.isPictureInPictureActive;
}

#pragma mark - 绑定窗口

- (void)attachToWindow:(UIWindow *)window {
    self.hostWindow = window;

    if (!self.displayLayer) {
        self.displayLayer = [AVSampleBufferDisplayLayer layer];
        self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        self.displayLayer.frame = window.bounds;
    }
    CALayer *host = window.layer;
    if (self.displayLayer.superlayer != host) {
        [self.displayLayer removeFromSuperlayer];
        [host addSublayer:self.displayLayer];
    }

    if (@available(iOS 15.0, *)) {
        if (!self.pip && self.isPiPSupported) {
            AVPictureInPictureControllerContentSource *src =
                [[AVPictureInPictureControllerContentSource alloc]
                    initWithSampleBufferDisplayLayer:self.displayLayer
                                    playbackDelegate:self];

            AVPictureInPictureController *pip =
                [[AVPictureInPictureController alloc] initWithContentSource:src];
            pip.delegate = self;
            pip.canStartPictureInPictureAutomaticallyFromInline = YES;
            self.pip = pip;
        }
    }
}

#pragma mark - 控制

- (void)startPiP {
    // PiP 必须有活跃的 playback 音频会话，否则启动会失败
    NSError *err = nil;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setCategory:AVAudioSessionCategoryPlayback error:&err];
    [s setActive:YES error:&err];
    if (err) NSLog(@"[PiP] audio session: %@", err);

    [self startKeepAlive];

    self.playing = YES;
    self.pushedTime = kCMTimeZero;

    if (!self.pip) {
        NSLog(@"[PiP] not attached / unsupported");
        return;
    }
    if (self.pip.isPictureInPictureActive) return;

    if (self.pip.isPictureInPicturePossible) {
        [self.pip startPictureInPicture];
    } else {
        // 首次往往还没 possible，延时重试
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (self.pip.isPictureInPicturePossible) {
                [self.pip startPictureInPicture];
            } else {
                NSLog(@"[PiP] still not possible");
            }
        });
    }
}

- (void)stopPiP {
    self.playing = NO;
    if (self.pip.isPictureInPictureActive) {
        [self.pip stopPictureInPicture];
    }
    [self stopKeepAlive];
}

#pragma mark - 静音保活（切到目标 App 后进程继续跑）

- (void)startKeepAlive {
    if (!self.keepAliveEnabled || self.keepAlivePlayer.isPlaying) return;
    NSData *wav = [self silentWAVDataWithSeconds:2];
    if (!wav) return;
    NSError *e = nil;
    AVAudioPlayer *p = [[AVAudioPlayer alloc] initWithData:wav error:&e];
    if (e || !p) { NSLog(@"[PiP] keepalive: %@", e); return; }
    p.numberOfLoops = -1;
    // 不要把 volume 设 0：系统可能判定为「未在输出音频」而不给后台时间。
    // 静音来自采样数据本身（全零 PCM），volume 保持默认即可。
    [p prepareToPlay];
    [p play];
    self.keepAlivePlayer = p;
    NSLog(@"[PiP] keepalive started");
}

- (void)stopKeepAlive {
    [self.keepAlivePlayer stop];
    self.keepAlivePlayer = nil;
}

/// 内存里拼一段静音 WAV（16-bit mono 8kHz），不依赖资源文件
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
    [d appendData:[NSMutableData dataWithLength:dataBytes]];   // 全零 = 静音
    return d;
}

#pragma mark - 推帧

- (void)pushImage:(UIImage *)image {
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

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)c {
    NSLog(@"[PiP] started");
    if (self.onPiPStarted) self.onPiPStarted();
}
- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)c {
    NSLog(@"[PiP] stopped");
}
- (void)pictureInPictureController:(AVPictureInPictureController *)c
failedToStartPictureInPictureWithError:(NSError *)error {
    NSLog(@"[PiP] failed: %@", error);
}

#pragma mark - 必须实现的播放代理（否则无法进入 PiP）

- (void)pictureInPictureController:(AVPictureInPictureController *)c
                     setPlaying:(BOOL)playing {
    self.playing = playing;
}

- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:(AVPictureInPictureController *)c {
    // 给一个无限时长的直播区间，PiP 才不会因为"播完"自动退出
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
