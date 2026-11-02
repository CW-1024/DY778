#import "DY778Core.h"
#import "DY778PlaybackPolicy.h"
#import <QuartzCore/QuartzCore.h>

@interface DY778ToastCapsule : UIView
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) UIView *statusView;
@property(nonatomic, strong) CAShapeLayer *check;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, copy) NSString *activityToken;
@property(nonatomic, strong) NSArray<CAShapeLayer *> *speedMarks;
- (void)setSpeedActivity:(BOOL)active;
@end
@implementation DY778ToastCapsule
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.translatesAutoresizingMaskIntoConstraints = NO; self.userInteractionEnabled = NO;
        self.accessibilityIdentifier = @"DY778.Toast";
        self.backgroundColor = [UIColor colorWithWhite:.08 alpha:.94]; self.layer.cornerRadius = 16;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = UIColor.blackColor.CGColor; self.layer.shadowOpacity = .12;
        self.layer.shadowRadius = 7; self.layer.shadowOffset = CGSizeMake(0, 3);
        _label = [UILabel new]; _label.textColor = UIColor.whiteColor; _label.numberOfLines = 2;
        _label.textAlignment = NSTextAlignmentCenter; _label.lineBreakMode = NSLineBreakByTruncatingTail;
        _label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[UIFont systemFontOfSize:12 weight:UIFontWeightMedium] maximumPointSize:16];
        _label.adjustsFontForContentSizeCategory = YES;
        _statusView = [UIView new]; _statusView.translatesAutoresizingMaskIntoConstraints = NO;
        [_statusView.widthAnchor constraintEqualToConstant:16].active = YES;
        [_statusView.heightAnchor constraintEqualToConstant:16].active = YES;
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.color = UIColor.whiteColor; _spinner.transform = CGAffineTransformMakeScale(.7, .7);
        _spinner.center = CGPointMake(8, 8); [_statusView addSubview:_spinner];
        UIBezierPath *path = [UIBezierPath bezierPath]; [path moveToPoint:CGPointMake(2, 8)];
        [path addLineToPoint:CGPointMake(6, 12)]; [path addLineToPoint:CGPointMake(14, 4)];
        _check = [CAShapeLayer layer]; _check.path = path.CGPath; _check.strokeColor = [UIColor colorWithRed:.4 green:.91 blue:.72 alpha:1].CGColor;
        _check.fillColor = UIColor.clearColor.CGColor; _check.lineWidth = 2;
        _check.lineCap = kCALineCapRound; _check.lineJoin = kCALineJoinRound; _check.hidden = YES;
        [_statusView.layer addSublayer:_check];
        UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[_statusView, _label]];
        content.spacing = 7; content.alignment = UIStackViewAlignmentCenter; content.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:content];
        [NSLayoutConstraint activateConstraints:@[[content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [content.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8]]];
    } return self;
}
- (void)setSpeedActivity:(BOOL)active {
    if (active && !self.speedMarks) {
        NSMutableArray *marks = [NSMutableArray new];
        for (NSUInteger i = 0; i < 2; i++) {
            CGFloat x = 2 + i * 7;
            UIBezierPath *path = [UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(x,4)]; [path addLineToPoint:CGPointMake(x+4,8)]; [path addLineToPoint:CGPointMake(x,12)];
            CAShapeLayer *mark = [CAShapeLayer layer]; mark.path = path.CGPath;
            mark.fillColor = UIColor.clearColor.CGColor; mark.strokeColor = UIColor.whiteColor.CGColor;
            mark.lineWidth = 1.8; mark.lineCap = kCALineCapRound; mark.lineJoin = kCALineJoinRound;
            [self.statusView.layer addSublayer:mark]; [marks addObject:mark];
        }
        self.speedMarks = marks;
    }
    [self.speedMarks enumerateObjectsUsingBlock:^(CAShapeLayer *mark, NSUInteger index, BOOL *stop) {
        mark.hidden = !active;
        if (!active || UIAccessibilityIsReduceMotionEnabled()) { [mark removeAllAnimations]; return; }
        if ([mark animationForKey:@"speed"]) return;
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue = @.3; pulse.toValue = @1; pulse.duration = .42; pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF; pulse.beginTime = CACurrentMediaTime() + index * .14;
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [mark addAnimation:pulse forKey:@"speed"];
    }];
}
@end

static NSMutableDictionary<NSString *, DY778ToastCapsule *> *DY778Toasts;
static UIStackView *DY778ToastStack;
static void DY778RemoveToast(NSString *channel, DY778ToastCapsule *card) {
    if (!card || DY778Toasts[channel] != card) return;
    [card setSpeedActivity:NO]; [card.spinner stopAnimating]; [card.layer removeAllAnimations];
    [DY778Toasts removeObjectForKey:channel];
    [DY778ToastStack removeArrangedSubview:card]; [card removeFromSuperview];
    if (!DY778Toasts.count) { [DY778ToastStack removeFromSuperview]; DY778ToastStack = nil; }
}
void DY778DismissToast(NSString *channel) {
    dispatch_async(dispatch_get_main_queue(), ^{ DY778RemoveToast(channel, DY778Toasts[channel]); });
}
static void DY778PresentToast(NSString *channel, NSString *message, BOOL loading, BOOL success, NSString *activityToken) {
    if (!channel.length || !message.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = DY778ActiveWindow(); if (!window) return;
        static dispatch_once_t once; dispatch_once(&once, ^{
            DY778Toasts = [NSMutableDictionary dictionary];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                for (NSString *key in DY778Toasts.allKeys) DY778RemoveToast(key, DY778Toasts[key]);
            }];
        });
        if (DY778ToastStack.superview != window) {
            [DY778ToastStack removeFromSuperview]; [DY778Toasts removeAllObjects];
            DY778ToastStack = [UIStackView new]; DY778ToastStack.axis = UILayoutConstraintAxisVertical;
            DY778ToastStack.alignment = UIStackViewAlignmentCenter; DY778ToastStack.spacing = 6;
            DY778ToastStack.userInteractionEnabled = NO; DY778ToastStack.translatesAutoresizingMaskIntoConstraints = NO;
            [window addSubview:DY778ToastStack];
            [NSLayoutConstraint activateConstraints:@[[DY778ToastStack.centerXAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.centerXAnchor],
                [DY778ToastStack.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:8],
                [DY778ToastStack.widthAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.widthAnchor constant:-32]]];
        }
        DY778ToastCapsule *card = DY778Toasts[channel]; BOOL fresh = card == nil;
        if (!card) {
            card = [DY778ToastCapsule new]; DY778Toasts[channel] = card;
            [DY778ToastStack addArrangedSubview:card];
            [card.widthAnchor constraintLessThanOrEqualToAnchor:DY778ToastStack.widthAnchor].active = YES;
            [card.widthAnchor constraintLessThanOrEqualToConstant:304].active = YES;
        }
        [card.layer removeAllAnimations]; card.alpha = 1; card.transform = CGAffineTransformIdentity;
        NSUInteger generation = ++card.generation;
        BOOL speed = activityToken.length > 0;
        card.activityToken = activityToken;
        card.label.text = message; card.statusView.hidden = !(loading || success || speed);
        card.check.hidden = !success; [card.check removeAllAnimations];
        [card setSpeedActivity:speed];
        if (loading) [card.spinner startAnimating]; else [card.spinner stopAnimating];
        [window bringSubviewToFront:DY778ToastStack]; [window layoutIfNeeded];
        if (fresh) {
            card.alpha = 0; card.transform = CGAffineTransformMakeTranslation(0, -6);
            [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : .22 animations:^{ card.alpha = 1; card.transform = CGAffineTransformIdentity; }];
        }
        if (success && !UIAccessibilityIsReduceMotionEnabled()) {
            CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
            animation.fromValue = @0; animation.toValue = @1; animation.duration = .25;
            [card.check addAnimation:animation forKey:@"complete"];
        }
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
        if (speed) return;
        NSTimeInterval duration = loading ? 65 : UIAccessibilityIsVoiceOverRunning() ? 6 : 2.8;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (DY778Toasts[channel] != card || card.generation != generation) return;
            [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : .18 animations:^{ card.alpha = 0; } completion:^(__unused BOOL finished) {
                if (card.generation == generation) DY778RemoveToast(channel, card);
            }];
        });
    });
}
void DY778ShowToast(NSString *channel, NSString *message, BOOL loading, BOOL success) {
    DY778PresentToast(channel,message,loading,success,nil);
}
void DY778ShowSpeedToast(NSString *token, double rate) {
    if (!token.length) return;
    char label[16]; DY778PlaybackRateLabel(label,sizeof(label),rate);
    DY778PresentToast(@"playback",[NSString stringWithFormat:@"%s 快进中",label],NO,NO,token);
}
void DY778DismissSpeedToast(NSString *token) {
    if (!token.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        DY778ToastCapsule *card = DY778Toasts[@"playback"];
        if (![card.activityToken isEqual:token]) return;
        NSUInteger generation = ++card.generation;
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : .15 animations:^{
            card.alpha = 0; card.transform = CGAffineTransformMakeTranslation(0,-3);
        } completion:^(__unused BOOL finished) {
            if (card.generation == generation && [card.activityToken isEqual:token]) DY778RemoveToast(@"playback",card);
        }];
    });
}
void DY778Toast(NSString *message) { DY778ShowToast(@"general", message, NO, NO); }
