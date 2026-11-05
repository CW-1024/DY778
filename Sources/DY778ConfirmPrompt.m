#import "DY778ConfirmPrompt.h"

static __weak DY778ConfirmPrompt *DY778ConfirmVisiblePrompt;

@interface DY778ConfirmPrompt ()
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIStackView *buttons;
@property(nonatomic, strong) UILabel *heading;
@property(nonatomic, copy) void (^decision)(BOOL);
@property(nonatomic) BOOL finishing;
@end

@implementation DY778ConfirmPrompt

+ (void)presentForAction:(DY778ConfirmActionType)action intent:(DY778ConfirmIntent)intent
                    name:(NSString *)name isComment:(BOOL)isComment
                decision:(void (^)(BOOL))decision {
    NSAssert(NSThread.isMainThread, @"Present confirmations on the main thread");
    UIWindow *window = DY778ConfirmActiveWindow();
    if (!window || DY778ConfirmVisiblePrompt) {
        if (decision) decision(NO);
        return;
    }
    DY778ConfirmPrompt *prompt = [[self alloc] initWithFrame:window.bounds];
    prompt.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    prompt.overrideUserInterfaceStyle = DY778ConfirmUserInterfaceStyle();
    prompt.decision = decision;
    DY778ConfirmVisiblePrompt = prompt;
    [window addSubview:prompt];
    [prompt configureAction:action intent:intent name:name isComment:isComment];
    [NSNotificationCenter.defaultCenter addObserver:prompt selector:@selector(cancel)
        name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:prompt selector:@selector(updateTheme)
        name:DY778PreferencesChangedNotification object:nil];
    [prompt layoutIfNeeded];
    prompt.alpha = 0;
    prompt.panel.transform = UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.97, 0.97);
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.18 animations:^{
        prompt.alpha = 1;
        prompt.panel.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL finished) {
        if (!prompt.finishing) UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, prompt.heading);
    }];
}

- (UILabel *)labelWithText:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = UIColor.labelColor;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:size weight:weight] maximumPointSize:30];
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title primary:(BOOL)primary accent:(UIColor *)accent {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] maximumPointSize:24];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.8;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 10, 12, 10);
    button.layer.cornerRadius = 12;
    button.backgroundColor = primary ? accent : UIColor.tertiarySystemFillColor;
    [button setTitleColor:primary ? DY778AccentForeground() : UIColor.labelColor forState:UIControlStateNormal];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:46].active = YES;
    [button addTarget:self action:primary ? @selector(confirm) : @selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)configureAction:(DY778ConfirmActionType)action intent:(DY778ConfirmIntent)intent name:(NSString *)name isComment:(BOOL)isComment {
    self.accessibilityViewIsModal = YES;
    UIControl *scrim = [[UIControl alloc] initWithFrame:self.bounds];
    scrim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.46];
    scrim.isAccessibilityElement = NO;
    [scrim addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:scrim];

    BOOL isLike = action == DY778ConfirmActionLike || action == DY778ConfirmActionCommentLike;
    NSString *verb = isLike ? @"点赞" : action == DY778ConfirmActionCommentDislike ? @"点踩" :
                     action == DY778ConfirmActionFavorite ? @"收藏" : @"关注";
    NSString *symbol = isLike ? @"heart.fill" : action == DY778ConfirmActionCommentDislike ? @"hand.thumbsdown.fill" :
                       action == DY778ConfirmActionFavorite ? @"bookmark.fill" : @"person.badge.plus";
    NSString *object = action == DY778ConfirmActionFollow ? @"这位用户" : isComment ? @"这条评论" : @"当前内容";
    NSString *title = [NSString stringWithFormat:@"确认%@%@？", verb, object];
    NSString *message = isLike ? (isComment ? @"确认后将为这条评论点赞。" : @"喜欢这条内容，就留下你的赞。") :
                        action == DY778ConfirmActionCommentDislike ? @"确认后将对这条评论点踩。" :
                        action == DY778ConfirmActionFavorite ? @"保存到收藏，留待以后回看。" : @"关注后，更方便找到对方的动态。";
    NSString *confirmTitle = [@"确认" stringByAppendingString:verb];
    if (intent == DY778ConfirmIntentRemove) {
        title = [NSString stringWithFormat:@"取消对%@的%@？", object, verb];
        message = [NSString stringWithFormat:@"确认后将取消对%@的%@。", object, verb];
        confirmTitle = @"确认取消";
        if (action == DY778ConfirmActionFollow) symbol = @"person.badge.minus";

    }

    self.panel = [UIView new];
    self.panel.translatesAutoresizingMaskIntoConstraints = NO;
    self.panel.backgroundColor = DY778CardBackground();
    self.panel.layer.cornerRadius = 20;
    self.panel.layer.cornerCurve = kCACornerCurveContinuous;
    self.panel.clipsToBounds = YES;
    [self addSubview:self.panel];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = NO;
    [self.panel addSubview:scroll];
    UIStackView *content = [UIStackView new];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 10;
    content.alignment = UIStackViewAlignmentFill;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold]]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = DY778ConfirmAccent(action);
    icon.isAccessibilityElement = NO;
    [icon.heightAnchor constraintEqualToConstant:28].active = YES;
    [content addArrangedSubview:icon];
    self.heading = [self labelWithText:title size:17 weight:UIFontWeightSemibold];
    self.heading.accessibilityTraits |= UIAccessibilityTraitHeader;
    [content addArrangedSubview:self.heading];
    if (name.length) {
        UILabel *nameLabel = [self labelWithText:name size:15 weight:UIFontWeightMedium];
        nameLabel.numberOfLines = 3;
        nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [content addArrangedSubview:nameLabel];
    }
    UILabel *body = [self labelWithText:message size:14 weight:UIFontWeightRegular];
    body.textColor = UIColor.secondaryLabelColor;
    [content addArrangedSubview:body];

    self.buttons = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self buttonWithTitle:@"暂不操作" primary:NO accent:DY778ConfirmAccent(action)],
        [self buttonWithTitle:confirmTitle primary:YES accent:DY778ConfirmAccent(action)]
    ]];
    self.buttons.translatesAutoresizingMaskIntoConstraints = NO;
    self.buttons.spacing = 10;
    self.buttons.distribution = UIStackViewDistributionFillEqually;
    [self.panel addSubview:self.buttons];
    [self updateButtonAxis];

    NSLayoutConstraint *preferredWidth = [self.panel.widthAnchor constraintEqualToConstant:288];
    preferredWidth.priority = 999;
    NSLayoutConstraint *contentHeight = [scroll.heightAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.heightAnchor];
    contentHeight.priority = 750;
    [NSLayoutConstraint activateConstraints:@[
        preferredWidth,
        [self.panel.widthAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.widthAnchor constant:-40],
        [self.panel.centerXAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerXAnchor],
        [self.panel.centerYAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerYAnchor],
        [self.panel.topAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:12],
        [self.panel.bottomAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [scroll.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:16],
        [scroll.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:18],
        [scroll.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-18],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:44], contentHeight,
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [self.buttons.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:16],
        [self.buttons.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:18],
        [self.buttons.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-18],
        [self.buttons.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-18]
    ]];
}

- (void)updateButtonAxis {
    self.buttons.axis = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory) ?
        UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
}

- (void)updateTheme {
    UIUserInterfaceStyle style = DY778ConfirmUserInterfaceStyle();
    if (self.overrideUserInterfaceStyle != style) self.overrideUserInterfaceStyle = style;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateTheme];
    [self updateButtonAxis];
}

- (void)confirm { [self finish:YES]; }
- (void)cancel { [self finish:NO]; }
- (BOOL)accessibilityPerformEscape { [self cancel]; return YES; }

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window && self.decision && !self.finishing) {
        self.finishing = YES;
        void (^decision)(BOOL) = self.decision;
        self.decision = nil;
        DY778ConfirmVisiblePrompt = nil;
        [NSNotificationCenter.defaultCenter removeObserver:self];
        dispatch_async(dispatch_get_main_queue(), ^{ decision(NO); });
    }
}

- (void)finish:(BOOL)confirmed {
    if (self.finishing) return;
    self.finishing = YES;
    self.buttons.userInteractionEnabled = NO;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    void (^decision)(BOOL) = self.decision;
    self.decision = nil;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.15 animations:^{
        self.alpha = 0;
    } completion:^(__unused BOOL finished) {
        [self removeFromSuperview];
        DY778ConfirmVisiblePrompt = nil;
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
        dispatch_async(dispatch_get_main_queue(), ^{ if (decision) decision(confirmed); });
    }];
}

+ (void)showStaleNotice { DY778Toast(@"内容已变化，本次操作已取消"); }
@end
