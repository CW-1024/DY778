#import "DY778Core.h"
#import "DY778RadarUI.h"
#import "DY778RadarPolicy.h"
@interface DY778RadarNotice : UIView
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UILabel *heading;
@property(nonatomic, strong) UILabel *body;
@property(nonatomic, strong) UILabel *footer;
@property(nonatomic, strong) UILabel *lockHint;
@property(nonatomic, strong) UIButton *confirmButton;
@property(nonatomic, strong) UIButton *videoButton;
@property(nonatomic, strong) UIControl *backdrop;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *people;
@property(nonatomic, strong) NSMutableArray<NSString *> *order;
@property(nonatomic, strong) NSTimer *unlockTimer;
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *videoID;
@property(nonatomic) NSTimeInterval lockedAt;
@property(nonatomic) NSUInteger total;
@end
static __weak DY778RadarNotice *DY778RadarVisibleNotice;
@implementation DY778RadarNotice
- (UIButton *)button:(NSString *)title primary:(BOOL)primary action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:primary ? DY778AccentForeground() : DY778RadarAccent() forState:UIControlStateNormal];
    button.backgroundColor = primary ? DY778RadarButtonColor() : UIColor.tertiarySystemFillColor;
    button.layer.cornerRadius = 14; button.layer.cornerCurve = kCACornerCurveContinuous;
    button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold] maximumPointSize:24];
    button.titleLabel.adjustsFontForContentSizeCategory = YES; button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.75; button.contentEdgeInsets = UIEdgeInsetsMake(14, 12, 14, 12);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.overrideUserInterfaceStyle = DY778RadarStyle(); self.accessibilityViewIsModal = YES;
        self.people = [NSMutableDictionary dictionary]; self.order = [NSMutableArray array]; self.account = DY778RadarStore.shared.accountID;
        self.backdrop = [[UIControl alloc] initWithFrame:self.bounds]; self.backdrop.autoresizingMask = self.autoresizingMask;
        self.backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.38]; self.backdrop.accessibilityLabel = @"关闭动态提醒";
        [self.backdrop addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [self addSubview:self.backdrop];
        self.panel = [UIView new]; self.panel.translatesAutoresizingMaskIntoConstraints = NO;
        self.panel.backgroundColor = DY778CardBackground();
        self.panel.layer.cornerRadius = 24; self.panel.layer.cornerCurve = kCACornerCurveContinuous;
        self.panel.layer.shadowColor = UIColor.blackColor.CGColor; self.panel.layer.shadowOpacity = 0.16;
        self.panel.layer.shadowRadius = 28; self.panel.layer.shadowOffset = CGSizeMake(0, 10); [self addSubview:self.panel];
        UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO; [self.panel addSubview:scroll];
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"heart.circle.fill"]];
        icon.tintColor = DY778RadarAccent(); icon.contentMode = UIViewContentModeScaleAspectFit; [icon.heightAnchor constraintEqualToConstant:42].active = YES;
        self.heading = DY778RadarLabel(@"你留意的人有了新动态", 21, UIFontWeightBold); self.heading.textAlignment = NSTextAlignmentCenter;
        self.heading.accessibilityTraits |= UIAccessibilityTraitHeader;
        self.body = DY778RadarLabel(@"", 16, UIFontWeightRegular);
        self.footer = DY778RadarLabel(@"", 12, UIFontWeightRegular); self.footer.textColor = UIColor.secondaryLabelColor;
        UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[icon, self.heading, self.body, self.footer]];
        content.axis = UILayoutConstraintAxisVertical; content.spacing = 14; content.translatesAutoresizingMaskIntoConstraints = NO; [scroll addSubview:content];
        self.confirmButton = [self button:@"确定" primary:YES action:@selector(close)];
        self.videoButton = [self button:@"查看作品" primary:NO action:@selector(openVideo)]; self.videoButton.hidden = YES;
        self.lockHint = DY778RadarLabel(@"防误触保护 · 2 秒后可操作", 12, UIFontWeightRegular);
        self.lockHint.textAlignment = NSTextAlignmentCenter; self.lockHint.textColor = UIColor.secondaryLabelColor;
        UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.videoButton, self.confirmButton]];
        buttons.axis = UILayoutConstraintAxisHorizontal; buttons.distribution = UIStackViewDistributionFillEqually; buttons.spacing = 10;
        UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[self.lockHint, buttons]];
        actions.axis = UILayoutConstraintAxisVertical; actions.spacing = 10; actions.translatesAutoresizingMaskIntoConstraints = NO; [self.panel addSubview:actions];
        NSLayoutConstraint *width = [self.panel.widthAnchor constraintEqualToConstant:312]; width.priority = 999;
        NSLayoutConstraint *height = [scroll.heightAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.heightAnchor]; height.priority = 750;
        [NSLayoutConstraint activateConstraints:@[width, height,
            [self.panel.widthAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.widthAnchor constant:-36],
            [self.panel.centerXAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerXAnchor], [self.panel.centerYAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerYAnchor],
            [self.panel.topAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:12], [self.panel.bottomAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-12],
            [scroll.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:24], [scroll.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-24],
            [scroll.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:24], [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:44],
            [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor], [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
            [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor], [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
            [actions.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:20], [actions.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-20],
            [actions.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:18], [actions.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-20]
        ]];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(forceClose) name:UIApplicationWillResignActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(theme) name:DY778RadarThemeChanged object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountChanged) name:DY778RadarStoreChanged object:nil];
        [self lockActions];
    }
    return self;
}
- (void)theme { self.overrideUserInterfaceStyle = DY778RadarStyle(); }
- (void)accountChanged { if (![self.account isEqual:DY778RadarStore.shared.accountID] || ![DY778RadarStore.shared.options[@"alerts"] boolValue]) [self forceClose]; }
- (BOOL)canAct { return DY778RadarNoticeReady(NSProcessInfo.processInfo.systemUptime, self.lockedAt); }
- (void)setActionsEnabled:(BOOL)enabled {
    self.confirmButton.enabled = enabled; self.videoButton.enabled = enabled; self.backdrop.enabled = enabled;
    self.confirmButton.alpha = enabled ? 1 : 0.5; self.videoButton.alpha = enabled ? 1 : 0.5;
    self.lockHint.text = enabled ? @"请确认后关闭 · 提醒不会自动消失" : @"防误触保护 · 2 秒后可操作";
}
- (void)lockActions {
    self.lockedAt = NSProcessInfo.processInfo.systemUptime; [self setActionsEnabled:NO];
    [self.unlockTimer invalidate]; __weak typeof(self) weakSelf = self;
    self.unlockTimer = [NSTimer timerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
        typeof(self) self = weakSelf; if (!self) return;
        self.unlockTimer = nil; [self setActionsEnabled:[self canAct]];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.unlockTimer forMode:NSRunLoopCommonModes];
}
- (void)append:(NSArray *)events {
    // 按用户保存有上限的摘要；完整事件存档保留。
    NSString *newVideoID;
    for (NSDictionary *event in events) {
        NSDictionary *person = event[@"person"]; NSString *uid = person[@"uid"];
        if (!DY778RadarIdentifier(uid)) continue;
        NSMutableDictionary *summary = self.people[uid];
        if (!summary) {
            if (self.order.count >= 20) continue;
            summary = [@{@"person": person, @"changes": [NSMutableDictionary dictionary], @"likes": @0} mutableCopy];
            self.people[uid] = summary; [self.order addObject:uid];
        }
        summary[@"person"] = [DY778RadarStore.shared target:uid] ?: person; self.total++;
        if ([event[@"kind"] isEqual:@"like"]) {
            summary[@"likes"] = @([summary[@"likes"] unsignedIntegerValue] + 1);
            if (!newVideoID && DY778RadarIdentifier(event[@"video"][@"id"])) newVideoID = event[@"video"][@"id"];
        } else if ([event[@"kind"] isEqual:@"signature"]) {
            summary[@"signatureCount"] = @([summary[@"signatureCount"] unsignedIntegerValue] + 1);
            summary[@"signature"] = event[@"after"];
        } else for (NSDictionary *change in event[@"changes"]) {
            NSString *key = change[@"key"]; if (![@[@"received", @"following", @"followers", @"likes"] containsObject:key]) continue;
            NSMutableDictionary *changes = summary[@"changes"];
            NSNumber *before = changes[key][@"before"] ?: change[@"before"], *after = change[@"after"];
            changes[key] = @{@"before": before, @"after": after, @"delta": @(after.longLongValue - before.longLongValue)};
        }
    }
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *uid in self.order) {
        NSDictionary *summary = self.people[uid]; NSMutableArray *details = [NSMutableArray arrayWithObject:DY778RadarDisplayName(summary[@"person"])];
        for (NSString *key in @[@"received", @"following", @"followers", @"likes"]) {
            NSDictionary *change = summary[@"changes"][key]; if (!change) continue;
            long long delta = [change[@"delta"] longLongValue];
            NSString *difference = delta ? [NSString stringWithFormat:@"%@%lld", delta > 0 ? @"+" : @"", delta] : @"期间有变动";
            [details addObject:[NSString stringWithFormat:@"%@  %@ → %@（%@）", DY778RadarMetricName(key), change[@"before"], change[@"after"], difference]];
        }
        if ([summary[@"likes"] unsignedIntegerValue]) [details addObject:[NSString stringWithFormat:@"喜欢列表新发现 %@ 个作品", summary[@"likes"]]];
        if ([summary[@"signatureCount"] unsignedIntegerValue]) {
            NSString *preview = DY778RadarSignatureText(summary[@"signature"]);
            if (preview.length > 120) preview = [[preview substringWithRange:[preview rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 120)]] stringByAppendingString:@"…"];
            [details addObject:[NSString stringWithFormat:@"个人简介变化 %@ 次\n最新简介：%@", summary[@"signatureCount"], preview]];
        }
        [lines addObject:[details componentsJoinedByString:@"\n"]];
    }
    self.body.text = [lines componentsJoinedByString:@"\n\n"];
    self.footer.text = [NSString stringWithFormat:@"共 %lu 条记录，已存入\nDY778 → 特别关注 → 动态档案", (unsigned long)self.total];
    if (newVideoID && ![newVideoID isEqual:self.videoID]) {
        self.videoID = newVideoID; self.videoButton.hidden = NO;
        [self.videoButton setTitle:self.total > 1 ? @"查看最新作品" : @"查看作品" forState:UIControlStateNormal];
        [self lockActions]; // 新出现或变化的路由按钮也一并保护。
    }
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.heading);
}
- (BOOL)accessibilityPerformEscape { if (![self canAct]) return NO; [self close]; return YES; }
- (void)close { if ([self canAct]) [self forceClose]; }
- (void)openVideo {
    if (![self canAct] || ![self.account isEqual:DY778RadarStore.shared.accountID] || !DY778RadarIdentifier(self.videoID)) return;
    NSString *videoID = self.videoID; UIViewController *presenter = DY778RadarTopController(self.window.rootViewController);
    [self forceClose]; DY778RadarOpenVideo(presenter, videoID);
}
- (void)forceClose {
    [self.unlockTimer invalidate]; self.unlockTimer = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self]; [self removeFromSuperview];
    if (DY778RadarVisibleNotice == self) DY778RadarVisibleNotice = nil;
}
- (void)dealloc { [self.unlockTimer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
void DY778RadarShowNotice(NSArray<NSDictionary *> *events) {
    if (!events.count || ![DY778RadarStore.shared.options[@"alerts"] boolValue]) return;
    UIWindow *window = DY778RadarActiveWindow(); if (!window) return;
    if (DY778RadarVisibleNotice) { [DY778RadarVisibleNotice append:events]; return; }
    DY778RadarNotice *notice = [[DY778RadarNotice alloc] initWithFrame:window.bounds]; DY778RadarVisibleNotice = notice;
    [window addSubview:notice]; [notice append:events]; [notice layoutIfNeeded];
    notice.alpha = 0; notice.panel.transform = UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.97, 0.97);
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.2 animations:^{ notice.alpha = 1; notice.panel.transform = CGAffineTransformIdentity; }];
}
void DY778RadarDismissNotice(void) { [DY778RadarVisibleNotice forceClose]; }
