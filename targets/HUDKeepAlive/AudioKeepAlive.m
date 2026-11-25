//
//  AudioKeepAlive.m
//  静音音频后台保活（对应 AX Pro Max 的 Library/ax-hud-keepalive.wav）
//
//  原理：
//   Info.plist 声明 UIBackgroundModes=audio + AVAudioSessionCategoryPlayback，
//   只要音频一直在播，App 就不会被系统挂起（suspend），HUD 与注入线程就能常驻。
//   比 beginBackgroundTask（只有 ~30 秒）可靠得多。
//
//  这里在内存里现场生成一段 1 秒静音 WAV，不依赖任何资源文件。
//

#import "AudioKeepAlive.h"
#import <AVFoundation/AVFoundation.h>

@interface AudioKeepAlive ()
@property (nonatomic, strong) AVAudioPlayer *player;
@end

@implementation AudioKeepAlive

+ (instancetype)shared {
    static AudioKeepAlive *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [AudioKeepAlive new]; });
    return s;
}

#pragma mark - 生成 1 秒静音 WAV（PCM 16bit 单声道 44.1k）

static NSData *SilentWavData(void) {
    const uint32_t sampleRate = 44100;
    const uint16_t channels   = 1;
    const uint16_t bits       = 16;
    const uint32_t frames     = sampleRate;         // 1 秒
    const uint32_t dataSize   = frames * channels * (bits / 8);

    NSMutableData *d = [NSMutableData data];
    void (^w32)(uint32_t) = ^(uint32_t v){ [d appendBytes:&v length:4]; };
    void (^w16)(uint16_t) = ^(uint16_t v){ [d appendBytes:&v length:2]; };

    [d appendBytes:"RIFF" length:4];
    w32(36 + dataSize);
    [d appendBytes:"WAVEfmt " length:8];
    w32(16);
    w16(1);                       // PCM
    w16(channels);
    w32(sampleRate);
    w32(sampleRate * channels * bits / 8);   // byte rate
    w16(channels * bits / 8);                // block align
    w16(bits);
    [d appendBytes:"data" length:4];
    w32(dataSize);
    [d appendBytes:[NSMutableData dataWithLength:dataSize] length:dataSize];  // 全 0 = 静音
    return d;
}

#pragma mark - 控制

- (void)start {
    NSError *err = nil;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setCategory:AVAudioSessionCategoryPlayback
              mode:AVAudioSessionModeDefault
           options:0
             error:&err];
    [s setActive:YES error:&err];
    if (err) NSLog(@"[keepalive] session: %@", err);

    // 后台也要能继续播
    self.player = [[AVAudioPlayer alloc] initWithData:SilentWavData() error:&err];
    if (err) { NSLog(@"[keepalive] player: %@", err); return; }
    self.player.numberOfLoops = -1;     // 无限循环
    self.player.volume = 0.0;           // 静音（但播放器仍在消费音频管线）
    [self.player prepareToPlay];
    [self.player play];

    // 中断恢复：来电等打断后自动续上
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];
}

- (void)onInterruption:(NSNotification *)n {
    NSNumber *type = n.userInfo[AVAudioSessionInterruptionTypeKey];
    if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded) {
        [self.player play];
    }
}

- (void)stop {
    [self.player stop];
    self.player = nil;
}

- (BOOL)isRunning {
    return self.player.isPlaying;
}

@end
