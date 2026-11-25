//
//  HUDMenuPanel.m
//

#import "HUDMenuPanel.h"
#import <math.h>

static const CGFloat kFabSize  = 56.0;
static const CGFloat kCardW    = 272.0;
static const CGFloat kRowH     = 54.0;
static const CGFloat kGap      = 8.0;
static const CGFloat kEdge     = 12.0;
static const CGFloat kThemeH   = 186.0;

#pragma mark - 单行菜单项

@interface HUDMenuRow : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, copy) void (^onTap)(void);
- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle;
- (void)setSubtitle:(NSString *)s;
- (void)setHighlightedLook:(BOOL)on;
@end

@implementation HUDMenuRow

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07];
    self.layer.cornerRadius = 10.0;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.06].CGColor;

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = title;
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    _titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    [self addSubview:_titleLabel];

    _subLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _subLabel.text = subtitle;
    _subLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _subLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.45];
    _subLabel.textAlignment = NSTextAlignmentRight;
    _subLabel.adjustsFontSizeToFitWidth = YES;
    _subLabel.minimumScaleFactor = 0.7;
    [self addSubview:_subLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(handleTap)];
    [self addGestureRecognizer:tap];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    self.titleLabel.frame = CGRectMake(14, 0, w * 0.46, h);
    self.subLabel.frame   = CGRectMake(w * 0.46, 0, w * 0.54 - 14, h);
}

- (void)setSubtitle:(NSString *)s {
    self.subLabel.text = s;
    [self setNeedsLayout];
}

- (void)setHighlightedLook:(BOOL)on {
    self.subLabel.textColor = on
        ? [UIColor colorWithRed:0.42 green:0.86 blue:0.62 alpha:1.0]
        : [UIColor colorWithWhite:1.0 alpha:0.45];
}

- (void)handleTap {
    self.alpha = 0.55;
    [UIView animateWithDuration:0.15 animations:^{ self.alpha = 1.0; }];
    if (self.onTap) self.onTap();
}

@end

#pragma mark - HUD 面板

@interface HUDMenuPanel () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIView  *fab;
@property (nonatomic, strong) UILabel *fabLabel;
@property (nonatomic, strong) UIView  *card;
@property (nonatomic, strong) NSMutableArray<HUDMenuRow *> *rows;
@property (nonatomic, strong) HUDMenuRow *themeRow;
@property (nonatomic, strong) UIView *themeBox;
@property (nonatomic, strong) UISlider *hueSlider;
@property (nonatomic, strong) UISlider *satSlider;
@property (nonatomic, strong) UISlider *briSlider;

@property (nonatomic, assign) CGFloat hue;
@property (nonatomic, assign) CGFloat sat;
@property (nonatomic, assign) CGFloat bri;

@property (nonatomic, assign) CGPoint fabCenter;
@property (nonatomic, assign) CGPoint dragStart;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) BOOL themeExpanded;
@property (nonatomic, assign) BOOL captureOn;
@property (nonatomic, assign) BOOL secureOn;

@end

@implementation HUDMenuPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.hue = 0.58; self.sat = 0.85; self.bri = 1.0;
    [self buildFab];
    [self buildCard];
    [self syncGeometry];
    return self;
}

#pragma mark - 构建

- (UIColor *)themeColor {
    return [UIColor colorWithHue:self.hue saturation:self.sat brightness:self.bri alpha:1.0];
}

- (void)buildFab {
    CGFloat s = kFabSize;
    self.fab = [[UIView alloc] initWithFrame:CGRectMake(0, 0, s, s)];
    self.fab.backgroundColor = self.themeColor;
    self.fab.layer.cornerRadius = s * 0.5;
    self.fab.layer.shadowColor = [UIColor blackColor].CGColor;
    self.fab.layer.shadowOpacity = 0.35;
    self.fab.layer.shadowRadius = 8;
    self.fab.layer.shadowOffset = CGSizeMake(0, 3);
    self.fab.userInteractionEnabled = YES;

    self.fabLabel = [[UILabel alloc] initWithFrame:self.fab.bounds];
    self.fabLabel.text = @"AX";
    self.fabLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.fabLabel.textColor = [UIColor whiteColor];
    self.fabLabel.textAlignment = NSTextAlignmentCenter;
    self.fabLabel.userInteractionEnabled = NO;
    [self.fab addSubview:self.fabLabel];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(onPan:)];
    pan.delegate = self;
    [self.fab addGestureRecognizer:pan];

    [self addSubview:self.fab];
}

- (void)buildCard {
    self.card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kCardW, 100)];
    self.card.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:0.96];
    self.card.layer.cornerRadius = 14.0;
    self.card.layer.borderWidth = 1.0;
    self.card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    self.card.hidden = YES;
    self.card.alpha = 0.0;
    [self addSubview:self.card];

    self.rows = [NSMutableArray array];

    HUDMenuRow *r1 = [[HUDMenuRow alloc] initWithTitle:@"过直播" subtitle:@"关"];
    __weak typeof(self) ws = self;
    r1.onTap = ^{
        __strong typeof(ws) s = ws;
        if (!s) return;
        s.captureOn = !s.captureOn;
        [s updateCaptureRow];
        if (s.onCaptureToggle) s.onCaptureToggle(s.captureOn);
    };

    HUDMenuRow *r2 = [[HUDMenuRow alloc] initWithTitle:@"防截屏" subtitle:@"允许截屏"];
    r2.onTap = ^{
        __strong typeof(ws) s = ws;
        if (!s) return;
        s.secureOn = !s.secureOn;
        [s updateSecureRow];
        if (s.onSecureToggle) s.onSecureToggle(s.secureOn);
    };

    self.themeRow = [[HUDMenuRow alloc] initWithTitle:@"主题设置" subtitle:@"菜单主题"];
    self.themeRow.onTap = ^{
        __strong typeof(ws) s = ws;
        if (!s) return;
        s.themeExpanded = !s.themeExpanded;
        s.themeBox.hidden = !s.themeExpanded;
        [s.themeRow setSubtitle:s.themeExpanded ? @"点击收起" : @"菜单主题"];
        [s layoutCardAnimated:YES];
    };

    HUDMenuRow *r4 = [[HUDMenuRow alloc] initWithTitle:@"退出HUD" subtitle:@"关闭悬浮"];
    r4.onTap = ^{
        __strong typeof(ws) s = ws;
        if (s.onExit) s.onExit();
    };

    [self.rows addObject:r1];
    [self.rows addObject:r2];
    [self.rows addObject:self.themeRow];
    [self.rows addObject:r4];

    for (HUDMenuRow *r in self.rows) {
        [self.card addSubview:r];
    }

    [self buildThemeBox];
}

- (void)buildThemeBox {
    self.themeBox = [[UIView alloc] initWithFrame:CGRectZero];
    self.themeBox.hidden = YES;
    [self.card addSubview:self.themeBox];

    NSArray<NSString *> *names = @[@"色相", @"饱和度", @"亮度"];
    NSMutableArray<UISlider *> *sliders = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectZero];
        lb.text = names[i];
        lb.font = [UIFont systemFontOfSize:12];
        lb.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
        lb.tag = 100 + i;
        [self.themeBox addSubview:lb];

        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectZero];
        sl.minimumValue = 0.0;
        sl.maximumValue = 1.0;
        sl.tag = 200 + i;
        [sl addTarget:self action:@selector(onSlider:) forControlEvents:UIControlEventValueChanged];
        [self.themeBox addSubview:sl];
        [sliders addObject:sl];
    }
    self.hueSlider = sliders[0];
    self.satSlider = sliders[1];
    self.briSlider = sliders[2];
    self.hueSlider.value = self.hue;
    self.satSlider.value = self.sat;
    self.briSlider.value = self.bri;

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"恢复默认蓝色" forState:UIControlStateNormal];
    [reset setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.8] forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:13];
    reset.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    reset.layer.cornerRadius = 8.0;
    reset.tag = 300;
    [reset addTarget:self action:@selector(onReset) forControlEvents:UIControlEventTouchUpInside];
    [self.themeBox addSubview:reset];
}

#pragma mark - 布局

- (CGFloat)cardHeight {
    CGFloat h = 4 * kRowH + 3 * kGap + 2 * kGap;
    if (self.themeExpanded) h += kThemeH;
    return h;
}

- (void)syncGeometry {
    CGRect b = self.bounds;
    CGFloat s = kFabSize;
    if (self.fabCenter.x <= 0 && self.fabCenter.y <= 0) {
        self.fabCenter = CGPointMake(CGRectGetMaxX(b) - kEdge - s * 0.5,
                                     CGRectGetMinY(b) + 120 + s * 0.5);
    }
    self.fabCenter = [self clampPoint:self.fabCenter];
    self.fab.center = self.fabCenter;
    [self layoutCardAnimated:NO];
}

- (CGPoint)clampPoint:(CGPoint)p {
    CGRect b = self.bounds;
    CGFloat s = kFabSize;
    CGFloat half = s * 0.5;
    CGFloat minX = half + kEdge;
    CGFloat maxX = CGRectGetMaxX(b) - half - kEdge;
    CGFloat minY = half + kEdge + (b.size.height > b.size.width ? 44 : 0);
    CGFloat maxY = CGRectGetMaxY(b) - half - kEdge;
    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;
    return CGPointMake(MIN(MAX(p.x, minX), maxX), MIN(MAX(p.y, minY), maxY));
}

- (void)layoutCardAnimated:(BOOL)animated {
    CGFloat cardH = [self cardHeight];
    CGFloat x;
    if (self.fabCenter.x - kFabSize * 0.5 - kGap - kCardW >= kEdge) {
        x = self.fabCenter.x - kFabSize * 0.5 - kGap - kCardW;   // 放左侧
    } else {
        x = self.fabCenter.x + kFabSize * 0.5 + kGap;            // 放右侧
    }
    CGRect b = self.bounds;
    x = MIN(MAX(x, kEdge), CGRectGetMaxX(b) - kCardW - kEdge);
    if (x < kEdge) x = kEdge;

    CGFloat y = self.fabCenter.y - cardH * 0.5;
    CGFloat minY = kEdge + (b.size.height > b.size.width ? 44 : 0);
    y = MIN(MAX(y, minY), CGRectGetMaxY(b) - cardH - kEdge);
    if (y < minY) y = minY;

    CGRect target = CGRectMake(x, y, kCardW, cardH);

    void (^layoutContent)(void) = ^{
        self.card.frame = target;
        CGFloat cy = kGap;
        for (HUDMenuRow *r in self.rows) {
            r.frame = CGRectMake(kGap, cy, kCardW - kGap * 2, kRowH);
            cy += kRowH + kGap;
        }
        self.themeBox.frame = CGRectMake(kGap, cy, kCardW - kGap * 2, kThemeH);
        [self layoutThemeBox];
    };

    if (animated) {
        [UIView animateWithDuration:0.22
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:layoutContent
                         completion:nil];
    } else {
        layoutContent();
    }
}

- (void)layoutThemeBox {
    CGFloat w = self.themeBox.bounds.size.width;
    CGFloat y = 4.0;
    for (int i = 0; i < 3; i++) {
        UILabel *lb = [self.themeBox viewWithTag:100 + i];
        UISlider *sl = [self.themeBox viewWithTag:200 + i];
        lb.frame = CGRectMake(0, y, 52, 26);
        sl.frame = CGRectMake(54, y, w - 54, 26);
        y += 34.0;
    }
    UIButton *reset = [self.themeBox viewWithTag:300];
    reset.frame = CGRectMake(0, y + 6, w, 34);
}

#pragma mark - 交互

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    // 空白区域穿透，不挡住宿主界面
    return (v == self) ? nil : v;
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    if (g.state == UIGestureRecognizerStateBegan) {
        self.dragStart = p;
        self.dragging = NO;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGFloat dx = fabs(p.x - self.dragStart.x);
        CGFloat dy = fabs(p.y - self.dragStart.y);
        if (dx > 6 || dy > 6) self.dragging = YES;
        if (self.dragging) {
            self.fabCenter = [self clampPoint:p];
            self.fab.center = self.fabCenter;
            [self layoutCardAnimated:NO];
        }
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled) {
        if (!self.dragging) {
            [self toggleExpand];
        } else {
            [self snapToEdge];
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

- (void)snapToEdge {
    CGRect b = self.bounds;
    CGFloat half = kFabSize * 0.5;
    CGFloat leftX = kEdge + half;
    CGFloat rightX = CGRectGetMaxX(b) - kEdge - half;
    CGFloat targetX = (self.fabCenter.x < CGRectGetMidX(b)) ? leftX : rightX;

    [UIView animateWithDuration:0.2
                          delay:0
         usingSpringWithDamping:0.78
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.fabCenter = CGPointMake(targetX, self.fabCenter.y);
        self.fab.center = self.fabCenter;
        [self layoutCardAnimated:NO];
    } completion:nil];
}

- (void)toggleExpand {
    self.expanded = !self.expanded;
    if (!self.expanded) {
        self.themeExpanded = NO;
        self.themeBox.hidden = YES;
        [self.themeRow setSubtitle:@"菜单主题"];
        [UIView animateWithDuration:0.18 animations:^{
            self.card.alpha = 0.0;
            self.card.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } completion:^(BOOL f) {
            self.card.hidden = YES;
            self.fabLabel.text = @"AX";
        }];
    } else {
        [self layoutCardAnimated:NO];
        self.card.hidden = NO;
        self.card.transform = CGAffineTransformMakeScale(0.9, 0.9);
        [UIView animateWithDuration:0.2
                              delay:0
             usingSpringWithDamping:0.82
              initialSpringVelocity:0.5
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.card.alpha = 1.0;
            self.card.transform = CGAffineTransformIdentity;
        } completion:nil];
        self.fabLabel.text = @"×";
    }
}

#pragma mark - 状态

- (void)setCaptureOn:(BOOL)on {
    _captureOn = on;
    [self updateCaptureRow];
}

- (void)updateCaptureRow {
    HUDMenuRow *r = self.rows.count > 0 ? self.rows[0] : nil;
    if (!r) return;
    [r setSubtitle:self.captureOn ? @"过直播-开" : @"过直播-关"];
    [r setHighlightedLook:self.captureOn];
}

- (void)setSecureOn:(BOOL)on {
    _secureOn = on;
    [self updateSecureRow];
}

- (void)updateSecureRow {
    HUDMenuRow *r = self.rows.count > 1 ? self.rows[1] : nil;
    if (!r) return;
    [r setSubtitle:self.secureOn ? @"防截屏已开启" : @"允许截屏"];
    [r setHighlightedLook:self.secureOn];
}

#pragma mark - 主题

- (void)onSlider:(UISlider *)sl {
    if (sl == self.hueSlider) self.hue = sl.value;
    else if (sl == self.satSlider) self.sat = sl.value;
    else self.bri = sl.value;

    self.fab.backgroundColor = self.themeColor;
    self.card.layer.borderColor = [self.themeColor colorWithAlphaComponent:0.45].CGColor;
    if (self.onThemeChange) self.onThemeChange(self.themeColor);
}

- (void)onReset {
    self.hue = 0.58; self.sat = 0.85; self.bri = 1.0;
    self.hueSlider.value = self.hue;
    self.satSlider.value = self.sat;
    self.briSlider.value = self.bri;
    self.fab.backgroundColor = self.themeColor;
    self.card.layer.borderColor = [self.themeColor colorWithAlphaComponent:0.45].CGColor;
    if (self.onThemeChange) self.onThemeChange(self.themeColor);
}

@end
