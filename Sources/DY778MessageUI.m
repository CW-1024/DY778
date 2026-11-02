#import "DY778MessageUI.h"
#import "DY778Core.h"
#import "DY778Recall.h"
#import "DY778RecallPolicy.h"
#import "DY778EditHistory.h"
#import "DY778RecallMediaView.h"
#import "DY778ArchiveNative.h"
#import "DY778MessageLayout.h"
#import "DY778Avatar.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static char kDY778CellStateKey, kDY778HeaderStateKey;
static NSUInteger DY778DecorationGeneration = 1;
static NSMutableSet<NSString *> *DY778InstalledUIHooks;
static void DY778UpdateOfficialHeader(id header);
static void DY778QueueNativeTableRefresh(UIViewController *controller);
@class DY778CellDecorationState;
static BOOL DY778MessageAllowsBubbleTint(UITableViewCell *cell);
static UIColor *DY778TintColor(NSString *key);
static void DY778RestorePlainBubble(DY778CellDecorationState *state);
static NSTimeInterval DY778NormalizedTimestamp(double value) {
    if (!isfinite(value) || value <= 0) return 0;
    if (value > 100000000000.0) value /= 1000.0;
    if (value > 4133980800.0) return 0;
    return value;
}
static NSTimeInterval DY778TimestampForMessage(id message) {
    id value = DY778Read(message, @"createdAt");
    if ([value isKindOfClass:NSDate.class]) return DY778NormalizedTimestamp([value timeIntervalSince1970]);
    if ([value respondsToSelector:@selector(doubleValue)]) return DY778NormalizedTimestamp([value doubleValue]);
    value = DY778Read(message, @"createTime");
    return [value respondsToSelector:@selector(doubleValue)] ? DY778NormalizedTimestamp([value doubleValue]) : 0;
}
static NSString *DY778ConversationForMessage(id message) {
    NSString *value = DY778Identifier(DY778Read(message, @"belongingConversationIdentifier"));
    return value.length ? value : DY778Identifier(DY778Read(message, @"conversationID"));
}
static NSString *DY778MessageKey(id message, NSString *account, NSString *conversation) {
    NSString *identifier = DY778Identifier(DY778Read(message, @"identifier"));
    if (!identifier.length) identifier = DY778Identifier(DY778Read(message, @"messageID"));
    if (!identifier.length) identifier = DY778Identifier(DY778Read(message, @"serverMessageID"));
    return [NSString stringWithFormat:@"%@|%@|%@", account ?: @"", conversation ?: @"", identifier ?: @""];
}
static id DY778MessageForViewModel(id model) { return DY778Read(model, @"iesMessage") ?: DY778Read(model, @"message"); }
static id DY778ViewModelForCell(UITableViewCell *cell) {
    return DY778Read(DY778Read(cell, @"currentContext"), @"messageViewModel") ?: DY778Read(cell, @"viewModel");
}
static id DY778MessageForCell(UITableViewCell *cell) { return DY778MessageForViewModel(DY778ViewModelForCell(cell)) ?: DY778Read(cell, @"message"); }
static BOOL DY778MessageIsMine(id message, NSString *account) {
    NSString *sender = DY778Identifier(DY778Read(message, @"sender"));
    if (!sender.length) sender = DY778Identifier(DY778Read(message, @"fromUid"));
    return account.length && sender.length && [account isEqualToString:sender];
}
static UIFont *DY778TimeFont(void) {
    double value = DY778Number(@"time.fontSize");
    CGFloat size = isfinite(value) && value > 0 ? MIN(18, MAX(9, value)) : 11;
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2] scaledFontForFont:[UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightMedium] maximumPointSize:22];
}
static UIFont *DY778RecallFont(void) {
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold] maximumPointSize:18];
}
static UIColor *DY778ReadableTimeColor(void) {
    UIColor *chosen = DY778ColorFromHex(DY778String(@"time.color"), DY778Accent());
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        UIColor *resolved = [chosen resolvedColorWithTraitCollection:traits];
        CGFloat red = 0, green = 0, blue = 0, alpha = 1;
        if (![resolved getRed:&red green:&green blue:&blue alpha:&alpha]) return resolved;
        CGFloat luminance = red * .2126 + green * .7152 + blue * .0722;
        if (traits.userInterfaceStyle != UIUserInterfaceStyleDark && luminance > .55) {
            CGFloat scale = .42 / luminance;
            return [UIColor colorWithRed:red * scale green:green * scale blue:blue * scale alpha:1];
        }
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark && luminance < .3)
            return [UIColor colorWithRed:.55 + red * .45 green:.55 + green * .45 blue:.55 + blue * .45 alpha:1];
        return resolved;
    }];
}
NSString *DY778FormatMessageTime(NSTimeInterval timestamp) {
    timestamp = DY778NormalizedTimestamp(timestamp);
    if (!timestamp) return @"";
    NSString *pattern = DY778String(@"time.format");
    if (!pattern.length || pattern.length > 80) pattern = @"HH:mm:ss";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSDate *now = NSDate.date;
    NSMutableDictionary *thread = NSThread.currentThread.threadDictionary;
    NSDateFormatter *formatter = thread[@"DY778.MessageDateFormatter"];
    if (!formatter) { formatter = [NSDateFormatter new]; thread[@"DY778.MessageDateFormatter"] = formatter; }
    formatter.locale = NSLocale.autoupdatingCurrentLocale;
    formatter.calendar = NSCalendar.autoupdatingCurrentCalendar;
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = pattern;
    NSString *value = nil;
    @try { value = [formatter stringFromDate:date]; } @catch (__unused NSException *exception) { }
    if (!value.length) { formatter.dateFormat = @"HH:mm:ss"; value = [formatter stringFromDate:date]; }
    NSMutableString *tokens = [NSMutableString string];
    BOOL inLiteral = NO;
    for (NSUInteger index = 0; index < pattern.length; index++) {
        unichar character = [pattern characterAtIndex:index];
        if (character == '\'') { inLiteral = !inLiteral; continue; }
        if (!inLiteral) [tokens appendFormat:@"%C", character];
    }
    BOOL includesDate = [tokens rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"yYuUrQqMLwWdDFgEec"]].location != NSNotFound;
    if (!DY778Bool(@"time.smartDate") || includesDate) return value ?: @"";
    NSCalendar *calendar = NSCalendar.autoupdatingCurrentCalendar;
    if ([calendar isDate:date inSameDayAsDate:now]) return value ?: @"";
    NSDate *yesterday = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:now options:0];
    if (yesterday && [calendar isDate:date inSameDayAsDate:yesterday]) return [@"昨天 " stringByAppendingString:value ?: @""];
    formatter.dateFormat = [calendar component:NSCalendarUnitYear fromDate:date] == [calendar component:NSCalendarUnitYear fromDate:now] ? @"MM-dd" : @"yyyy-MM-dd";
    return [NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:date] ?: @"", value ?: @""];
}

static DY778LayoutPosition DY778PreferredPosition(NSString *key) {
    NSString *value = DY778String(key);
    if ([value isEqualToString:@"above"]) return DY778LayoutAbove;
    if ([value isEqualToString:@"below"]) return DY778LayoutBelow;
    return DY778LayoutRight;
}
static DY778LayoutRect DY778LayoutRectFromCGRect(CGRect rect) { return (DY778LayoutRect){rect.origin.x, rect.origin.y, rect.size.width, rect.size.height}; }
static CGRect DY778CGRectFromLayoutRect(DY778LayoutRect rect) { return CGRectMake(rect.x, rect.y, rect.width, rect.height); }
static BOOL DY778ValidRect(CGRect rect) { return !CGRectIsNull(rect) && !CGRectIsInfinite(rect) && isfinite(rect.origin.x + rect.origin.y + rect.size.width + rect.size.height) && rect.size.width > 8 && rect.size.height > 8; }
static BOOL DY778Signature(Class cls, SEL selector, const char *result, unsigned arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != arguments) return NO;
    char type[64] = {0}; method_getReturnType(method, type, sizeof(type));
    if (type[0] != result[0]) return NO;
    for (unsigned index = 2; index < arguments; index++) {
        method_getArgumentType(method, index, type, sizeof(type));
        if (type[0] != '@') return NO;
    }
    return YES;
}

@interface DY778RecallBadge : UIButton
@property(nonatomic, copy) NSString *conversationID;
@property(nonatomic, weak) UIViewController *source;
@end
@implementation DY778RecallBadge
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 7;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = .5;
        self.contentEdgeInsets = UIEdgeInsetsMake(2, 6, 2, 6);
        self.titleLabel.font = DY778RecallFont();
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addTarget:self action:@selector(openArchive) forControlEvents:UIControlEventTouchUpInside];
        self.accessibilityHint = @"打开当前会话的撤回记录";
    }
    return self;
}
- (void)openArchive {
    if (self.source && self.conversationID.length) DY778PresentRecallArchive(self.source, self.conversationID);
}
@end

static UIColor *DY778RecallAccent(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:.86 green:.64 blue:.69 alpha:1] : [UIColor colorWithRed:.51 green:.28 blue:.34 alpha:1];
    }];
}
static void DY778ConfigureTime(UILabel *label, NSString *text) {
    label.text = text;
    label.font = DY778TimeFont();
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = DY778ReadableTimeColor();
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.layer.cornerRadius = 7;
    label.layer.masksToBounds = YES;
    label.backgroundColor = DY778Bool(@"time.background") ? [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:.13 green:.15 blue:.16 alpha:.9] : [UIColor colorWithRed:.93 green:.95 blue:.95 alpha:.95];
    }] : UIColor.clearColor;
    label.layer.borderWidth = DY778Bool(@"time.background") ? .5 : 0;
    label.layer.borderColor = [[label.textColor colorWithAlphaComponent:.20] resolvedColorWithTraitCollection:label.traitCollection].CGColor;
    double opacity = DY778Number(@"time.opacity");
    label.alpha = isfinite(opacity) ? MIN(1, MAX(.35, opacity)) : .94;
    label.accessibilityLabel = [@"消息时间 " stringByAppendingString:text ?: @""];
}
static void DY778ConfigureRecall(DY778RecallBadge *badge, BOOL available) {
    badge.titleLabel.font = DY778RecallFont();
    [badge setTitle:DY778RecallMarkerText() forState:UIControlStateNormal];
    badge.titleLabel.numberOfLines = 1; badge.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    UIColor *color = DY778RecallAccent();
    [badge setTitleColor:color forState:UIControlStateNormal];
    badge.tintColor = color;
    badge.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:.20 green:.16 blue:.18 alpha:.9] : [UIColor colorWithRed:.97 green:.93 blue:.94 alpha:.94];
    }];
    badge.layer.borderColor = [[color colorWithAlphaComponent:.27] resolvedColorWithTraitCollection:badge.traitCollection].CGColor;
    badge.accessibilityLabel = available ? @"对方已撤回，原始内容已保留" : @"对方已撤回，原文未取得";
}

@interface DY778EditBadge : UIButton
@property(nonatomic, weak) UIViewController *source;
@property(nonatomic, copy) NSDictionary *record;
@end
@implementation DY778EditBadge
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 7; self.layer.borderWidth = .5; self.clipsToBounds = YES;
        self.titleLabel.font = DY778RecallFont(); self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.contentEdgeInsets = UIEdgeInsetsMake(2, 6, 2, 6);
        [self addTarget:self action:@selector(openHistory) forControlEvents:UIControlEventTouchUpInside];
        self.accessibilityHint = @"查看这条消息的原文、编辑版本和时间";
    } return self;
}
- (void)openHistory {
    if ([self.record[@"account"] isEqual:DY778CurrentAccountID()]) DY778PresentEditHistory(self.source, self.record[@"conversation"], self.record[@"key"]);
}
@end
static void DY778ConfigureEdit(UIButton *badge, NSUInteger changes) {
    badge.titleLabel.font = DY778RecallFont(); badge.titleLabel.numberOfLines = 1;
    badge.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [badge setTitle:[NSString stringWithFormat:@"%@ · %lu", DY778EditMarkerText(), (unsigned long)changes] forState:UIControlStateNormal];
    [badge setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    badge.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:.96];
    badge.layer.borderColor = [UIColor.separatorColor resolvedColorWithTraitCollection:badge.traitCollection].CGColor;
    badge.accessibilityLabel = [NSString stringWithFormat:@"对方已编辑，已留存 %lu 次编辑，点按查看历史", (unsigned long)changes];
}
@interface DY778CellDecorationState : NSObject
@property(nonatomic, weak) UIViewController *controller;
@property(nonatomic, weak) id message;
@property(nonatomic, weak) id observedMessage;
@property(nonatomic, copy) NSString *messageKey;
@property(nonatomic, copy) NSString *conversationID;
@property(nonatomic) NSTimeInterval timestamp;
@property(nonatomic) BOOL outgoing;
@property(nonatomic, strong) UILabel *timeLabel;
@property(nonatomic, strong) DY778RecallBadge *recallBadge;
@property(nonatomic, strong) DY778EditBadge *editBadge;
@property(nonatomic, strong) DY778RecallCoverView *coverFallback;
@property(nonatomic, strong) UIImageView *authorFallback;
@property(nonatomic, weak) UIView *bubbleView;
@property(nonatomic, weak) UIView *messageContentView;
@property(nonatomic) NSUInteger geometryGeneration;
@property(nonatomic, weak) UIView *tintedView;
@property(nonatomic, strong) UIImage *originalBubbleImage;
@property(nonatomic, strong) UIImage *appliedBubbleImage;
@property(nonatomic, weak) CAGradientLayer *tintedGradient;
@property(nonatomic, copy) NSArray *originalGradientColors;
@property(nonatomic, copy) NSArray *appliedGradientColors;
@property(nonatomic, weak) CALayer *tintedContentsLayer;
@property(nonatomic, strong) id originalLayerContents;
@property(nonatomic, strong) id appliedLayerContents;
@property(nonatomic, strong) UIColor *originalFill;
@property(nonatomic, strong) UIColor *appliedFill;
@property(nonatomic, copy) NSString *fillProperty;
@property(nonatomic) NSUInteger appearanceGeneration;
@property(nonatomic, copy) NSString *styleKey;
@property(nonatomic) NSUInteger layoutDepth;
@property(nonatomic) BOOL queued;
@property(nonatomic) BOOL updating;
@property(nonatomic) BOOL recalled;
@property(nonatomic) BOOL available;
@property(nonatomic) BOOL plainBubbleActive;
@property(nonatomic) NSUInteger plainBubbleGeneration;
@property(nonatomic, strong) NSArray *plainBubbleParts;
@property(nonatomic, strong) NSArray *plainBubbleTextParts;
@end
@implementation DY778CellDecorationState @end

@interface DY778PlainBubblePart : NSObject
@property(nonatomic, weak) UIView *view;
@property(nonatomic) BOOL originalHidden;
@property(nonatomic) BOOL changedHidden;
@property(nonatomic, strong) UIColor *originalBackground;
@property(nonatomic, strong) UIColor *appliedBackground;
@property(nonatomic, strong) UIColor *originalFill;
@property(nonatomic, strong) UIColor *appliedFill;
@property(nonatomic) CGFloat originalCornerRadius;
@property(nonatomic) CGFloat appliedCornerRadius;
@property(nonatomic) BOOL originalClips;
@property(nonatomic) BOOL appliedClips;
@property(nonatomic, weak) CALayer *layer;
@property(nonatomic, strong) id originalContents;
@property(nonatomic, strong) id appliedContents;
@property(nonatomic) BOOL clearedContents;
@property(nonatomic, copy) NSArray *originalColors;
@property(nonatomic, copy) NSArray *appliedColors;
@end
@implementation DY778PlainBubblePart @end

@interface DY778PlainBubbleTextPart : NSObject
@property(nonatomic, weak) UIView *view;
@property(nonatomic, strong) NSAttributedString *originalText;
@property(nonatomic, strong) NSAttributedString *appliedText;
@end
@implementation DY778PlainBubbleTextPart @end
static DY778CellDecorationState *DY778CellState(UITableViewCell *cell, BOOL create) {
    DY778CellDecorationState *state = objc_getAssociatedObject(cell, &kDY778CellStateKey);
    if (!state && create) { state = [DY778CellDecorationState new]; objc_setAssociatedObject(cell, &kDY778CellStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return state;
}
static void DY778ClearNativeMediaFallback(DY778CellDecorationState *state) {
    [state.coverFallback cancel]; [state.coverFallback removeFromSuperview]; state.coverFallback = nil;
    [state.authorFallback removeFromSuperview]; state.authorFallback = nil;
}
static void DY778RepairNativeMedia(UITableViewCell *cell, DY778CellDecorationState *state, NSDictionary *record) {
    if (!record || !state.recalled) { DY778ClearNativeMediaFallback(state); return; }
    NSMutableArray *pending = [NSMutableArray arrayWithObject:cell.contentView]; NSUInteger budget = 160;
    UIImageView *cover = nil, *avatar = nil;
    while (pending.count && budget--) {
        UIView *view = pending.lastObject; [pending removeLastObject];
        NSString *name = NSStringFromClass(view.class);
        if ([@[@"AWEIMShareFeedCardView", @"AWEIMMediaView", @"AWEIMFeedInfoCardView", @"AWEIMShareLongVideoCardView"] containsObject:name]) {
            id candidate = DY778Read(view, @"coverImageView"); if ([candidate isKindOfClass:UIImageView.class]) cover = candidate;
            candidate = DY778Read(view, @"cardAvatarImageView"); if ([candidate isKindOfClass:UIImageView.class]) avatar = candidate;
            if (cover) break;
        }
        if (view != state.coverFallback && view != state.authorFallback) [pending addObjectsFromArray:view.subviews];
    }
    if (!cover || cover.image) { [state.coverFallback cancel]; [state.coverFallback removeFromSuperview]; state.coverFallback = nil; }
    else {
        if (!state.coverFallback) state.coverFallback = [DY778RecallCoverView new];
        if (state.coverFallback.superview != cover) { [state.coverFallback removeFromSuperview]; [cover insertSubview:state.coverFallback atIndex:0]; }
        state.coverFallback.frame = cover.bounds; state.coverFallback.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [state.coverFallback configureRecord:record];
    }
    NSDictionary *share = record[@"share"];
    if (!avatar || avatar.image || ![share[@"authorID"] length] || ![share[@"authorAvatarURLs"] count]) { [state.authorFallback removeFromSuperview]; state.authorFallback = nil; }
    else {
        if (!state.authorFallback) { state.authorFallback = [UIImageView new]; state.authorFallback.userInteractionEnabled = NO; state.authorFallback.contentMode = UIViewContentModeScaleAspectFill; state.authorFallback.clipsToBounds = YES; }
        if (state.authorFallback.superview != avatar) { [state.authorFallback removeFromSuperview]; [avatar addSubview:state.authorFallback]; }
        state.authorFallback.frame = avatar.bounds; state.authorFallback.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        DY778LoadAvatarURLs(state.authorFallback, share[@"authorAvatarURLs"], [NSString stringWithFormat:@"%@/author/%@", record[@"key"], share[@"authorID"]]);
    }
}
static void DY778RestoreTint(DY778CellDecorationState *state) {
    UIView *view = state.tintedView;
    UIColor *current = view ? DY778Read(view, state.fillProperty) : nil;
    if (view && [current isKindOfClass:UIColor.class] && [current isEqual:state.appliedFill]) DY778Write(view, state.fillProperty, state.originalFill);
    if ([view isKindOfClass:UIImageView.class] && state.appliedBubbleImage && [(UIImageView *)view image] == state.appliedBubbleImage)
        [(UIImageView *)view setImage:state.originalBubbleImage];
    if (state.tintedGradient && [state.tintedGradient.colors isEqual:state.appliedGradientColors]) state.tintedGradient.colors = state.originalGradientColors;
    if (state.tintedContentsLayer && state.tintedContentsLayer.contents == state.appliedLayerContents) state.tintedContentsLayer.contents = state.originalLayerContents;
    state.tintedContentsLayer = nil; state.originalLayerContents = nil; state.appliedLayerContents = nil;
    state.originalBubbleImage = nil; state.appliedBubbleImage = nil; state.tintedGradient = nil; state.originalGradientColors = nil; state.appliedGradientColors = nil;
    state.tintedView = nil; state.originalFill = nil; state.appliedFill = nil; state.fillProperty = nil;
}
static void DY778HideCellDecorations(DY778CellDecorationState *state) {
    if (state.timeLabel && !state.timeLabel.hidden) state.timeLabel.hidden = YES;
    if (state.recallBadge && !state.recallBadge.hidden) state.recallBadge.hidden = YES;
    state.editBadge.hidden = YES; state.editBadge.record = nil;
    DY778RestoreTint(state); DY778RestorePlainBubble(state);
}
static BOOL DY778IsOwnDecoration(UIView *view, DY778CellDecorationState *state) { return view == state.timeLabel || view == state.recallBadge || view == state.editBadge; }

static BOOL DY778DisplayedInCell(UIView *view, UITableViewCell *cell) {
    if (![view isKindOfClass:UIView.class] || view == cell || view == cell.contentView) return NO;
    UIView *ancestor = view;
    for (NSUInteger depth = 0; ancestor && depth < 20; depth++, ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha < .01) return NO;
        if (ancestor == cell) return YES;
    }
    return NO;
}
static BOOL DY778CanBeBubble(UIView *view, UITableViewCell *cell) {
    if (!DY778DisplayedInCell(view, cell)) return NO;
    CGRect rect = [view convertRect:view.bounds toView:cell];
    if (!DY778ValidRect(rect) || rect.size.width > cell.bounds.size.width - 24 || !CGRectIntersectsRect(cell.bounds, rect)) return NO;
    NSString *name = NSStringFromClass(view.class);
    for (NSString *exclude in @[@"Avatar", @"Nickname", @"NameLabel", @"State", @"ReplyButton", @"QuickReply", @"Header", @"Footer"])
        if ([name containsString:exclude]) return NO;
    UIView *parent = view.superview;
    for (NSUInteger depth = 0; parent && parent != cell.contentView && depth < 12; depth++, parent = parent.superview) {
        if (![NSStringFromClass(parent.class) isEqual:@"AWEIMAudioContentView"]) continue;
        for (NSString *key in @[@"backPathView", @"forePathView", @"playStatusView"]) {
            UIView *wave = DY778Read(parent, key);
            if ([wave isKindOfClass:UIView.class] && (view == wave || [view isDescendantOfView:wave])) return NO;
        }
    }
    return YES;
}
static UIView *DY778ActualBubbleView(UIView *view, UITableViewCell *cell) {
    if (![view isKindOfClass:UIView.class]) return nil;
    if ([NSStringFromClass(view.class) isEqualToString:@"AWEIMMessageBubbleGradientView"]) {
        // updateContentRect: positions these inside a wider carrier view.
        for (NSString *key in @[@"userBubbleView", @"gradientView"]) {
            UIView *inner = DY778Read(view, key);
            if (DY778CanBeBubble(inner, cell) && [inner isDescendantOfView:view]) {
                if (![inner isKindOfClass:UIImageView.class] || [(UIImageView *)inner image]) return inner;
            }
        }
    }
    return DY778CanBeBubble(view, cell) ? view : nil;
}
static NSInteger DY778BubbleScore(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    if ([name isEqualToString:@"AWEIMShapeView"]) return 120;
    if ([name isEqualToString:@"AWEIMMessageBubbleGradientView"]) return 150;
    if ([name isEqualToString:@"AWEIMMessageBubbleThemeView"]) return 110;
    if ([name hasPrefix:@"AWEIM"] && [name containsString:@"Bubble"] && ![name containsString:@"Window"]) return 100;
    if ([name hasPrefix:@"AWEIM"] && ([name containsString:@"ImageContentView"] || [name containsString:@"VideoContentView"] || [name containsString:@"AudioContentView"])) return 95;
    if ([name hasPrefix:@"AWEIM"] && [name containsString:@"CardView"]) return 105;
    if ([name hasPrefix:@"AWEIM"] && [name hasSuffix:@"ContentView"] &&
        ([name containsString:@"Share"] || [name containsString:@"Feed"] || [name containsString:@"Aweme"] ||
         [name containsString:@"Lynx"] || [name containsString:@"BigPicture"] || [name containsString:@"LinkPreview"])) return 105;
    if ([name hasPrefix:@"AWEIM"] && ([name containsString:@"TextContent"] || [name containsString:@"RichText"])) return 80;
    if ([name hasPrefix:@"AWEIM"] && [name containsString:@"GiphyContentView"]) return 90;
    return 0;
}
static void DY778ConsiderBubble(UIView *view, UITableViewCell *cell, NSInteger priority, UIView **best, NSInteger *score) {
    if (![view isKindOfClass:UIView.class] || priority <= *score) return;
    UIView *actual = DY778ActualBubbleView(view, cell);
    if (actual) { *best = actual; *score = priority; }
}
static void DY778FindBubbleInView(UIView *view, UITableViewCell *cell, NSUInteger depth, NSUInteger *budget, UIView **best, NSInteger *score) {
    if (depth > 8 || !*budget || view.hidden || view.alpha < .01) return;
    (*budget)--;
    NSInteger candidate = DY778BubbleScore(view);
    DY778ConsiderBubble(view, cell, candidate, best, score);
    for (UIView *child in view.subviews) DY778FindBubbleInView(child, cell, depth + 1, budget, best, score);
}
static UIView *DY778ContentFromComponents(id manager, UITableViewCell *cell, NSUInteger depth, NSUInteger *budget) {
    if (!manager || depth > 3 || !*budget) return nil;
    id components = DY778Read(manager, @"components");
    if (![components isKindOfClass:NSArray.class]) return nil;
    for (id component in components) {
        if (!*budget) break;
        (*budget)--;
        NSString *name = NSStringFromClass([component class]);
        if (![name hasPrefix:@"AWEIM"] || ![name containsString:@"ContentComponent"]) continue;
        // These native getters identify message content without guessing UILabels
        // (nicknames and other plugins may use the same label class).
        UIView *visible = DY778Read(component, @"visibleContentView");
        if (DY778CanBeBubble(visible, cell)) return visible;
        visible = DY778Read(DY778Read(component, @"presenter"), @"view");
        if (DY778CanBeBubble(visible, cell)) return visible;
        visible = DY778ContentFromComponents(DY778Read(component, @"componentManager"), cell, depth + 1, budget);
        if (visible) return visible;
    }
    return nil;
}
static UIView *DY778FindBubble(UITableViewCell *cell, UIView **content) {
    id model = DY778ViewModelForCell(cell);
    UIView *visible = DY778Read(cell, @"visibleContentView");
    if (!DY778CanBeBubble(visible, cell)) {
        NSUInteger componentBudget = 48;
        visible = DY778ContentFromComponents(DY778Read(model, @"componentManager"), cell, 0, &componentBudget);
    }
    if (!DY778CanBeBubble(visible, cell)) visible = DY778Read(cell, @"contentTargetView");
    *content = DY778CanBeBubble(visible, cell) ? visible : nil;
    UIView *best = nil; NSInteger score = 0; NSUInteger budget = 220;
    DY778ConsiderBubble(DY778Read(cell, @"bubbleView"), cell, 175, &best, &score);
    DY778ConsiderBubble(*content, cell, 90, &best, &score);
    DY778FindBubbleInView(cell.contentView, cell, 0, &budget, &best, &score);
    if (*content && best && best != *content &&
        !CGRectIntersectsRect([best convertRect:best.bounds toView:cell], [*content convertRect:(*content).bounds toView:cell])) best = *content;
    return best;
}
static UIColor *DY778PlainBubbleFallbackColor(BOOL outgoing, UITraitCollection *traits) {
    if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) return outgoing ? [UIColor colorWithRed:.24 green:.25 blue:.29 alpha:1] : [UIColor colorWithRed:.22 green:.22 blue:.23 alpha:1];
    return outgoing ? [UIColor colorWithRed:.87 green:.89 blue:.96 alpha:1] : [UIColor colorWithRed:.93 green:.93 blue:.94 alpha:1];
}
static UIColor *DY778PlainBubbleReferenceColor(UITableViewCell *cell, BOOL outgoing, UITraitCollection *traits) {
    UITableView *table = DY778Read(DY778Read(DY778CellState(cell,NO),@"controller"),@"tableView");
    for (UITableViewCell *other in table.visibleCells) {
        if (other == cell || !DY778MessageAllowsBubbleTint(other)) continue;
        NSDictionary *record = DY778RecallRecordForMessage(DY778MessageForCell(other));
        BOOL otherOutgoing = [record[@"sender"] length] ? [record[@"sender"] isEqualToString:record[@"account"]] : DY778MessageIsMine(DY778MessageForCell(other),DY778CurrentAccountID());
        if (otherOutgoing != outgoing) continue;
        UIView *root = other.contentView; NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root]; BOOL hasSkin = NO;
        for (NSUInteger visited=0; pending.count && visited<128; visited++) {
            UIView *view = pending.lastObject; [pending removeLastObject]; NSString *name = NSStringFromClass(view.class);
            UIView *skin = DY778Read(view,@"userBubbleView");
            if ([name isEqual:@"AWEIMMessageBubbleGradientView"] && [skin isKindOfClass:UIImageView.class] && ((UIImageView *)skin).image) { hasSkin=YES; break; }
            for (UIView *child in view.subviews) { if (pending.count>=128) break; [pending addObject:child]; }
        }
        if (hasSkin) continue;
        UIView *content=nil; UIView *bubble = DY778FindBubble(other,&content); UIColor *color = DY778Read(bubble,@"fillColor");
        if (![color isKindOfClass:UIColor.class] || CGColorGetAlpha(color.CGColor)<.05) color=bubble.backgroundColor;
        if ([color isKindOfClass:UIColor.class] && CGColorGetAlpha(color.CGColor)>=.05) return [color resolvedColorWithTraitCollection:traits];
        CAGradientLayer *gradient = [bubble.layer isKindOfClass:CAGradientLayer.class] ? (id)bubble.layer : nil;
        if (!gradient) for (CALayer *layer in bubble.layer.sublayers) if ([layer isKindOfClass:CAGradientLayer.class]) { gradient=(id)layer; break; }
        id value=gradient.colors.firstObject;
        if (value && CFGetTypeID((__bridge CFTypeRef)value)==CGColorGetTypeID()) return [UIColor colorWithCGColor:(__bridge CGColorRef)value];
    }
    return DY778PlainBubbleFallbackColor(outgoing,traits);
}
static void DY778RestorePlainBubble(DY778CellDecorationState *state) {
    for (DY778PlainBubbleTextPart *part in state.plainBubbleTextParts) {
        UIView *view=part.view;
        id current=view ? DY778Read(view,@"attributedText") : nil;
        if ([current isKindOfClass:NSAttributedString.class] && [current isEqualToAttributedString:part.appliedText]) DY778Write(view,@"attributedText",part.originalText);
    }
    for (DY778PlainBubblePart *part in state.plainBubbleParts) {
        UIView *view=part.view; CALayer *layer=part.layer;
        if (view && part.changedHidden && view.hidden) view.hidden=part.originalHidden;
        if (view && part.appliedBackground && [view.backgroundColor isEqual:part.appliedBackground]) view.backgroundColor=part.originalBackground;
        UIColor *fill=view ? DY778Read(view,@"fillColor") : nil;
        if (view && part.appliedFill && [fill isEqual:part.appliedFill]) DY778Write(view,@"fillColor",part.originalFill);
        if (view && part.appliedCornerRadius && fabs(view.layer.cornerRadius-part.appliedCornerRadius)<.001) view.layer.cornerRadius=part.originalCornerRadius;
        if (view && part.appliedClips && view.clipsToBounds==part.appliedClips) view.clipsToBounds=part.originalClips;
        if (layer && part.clearedContents && !layer.contents) layer.contents=part.originalContents;
        else if (layer && part.appliedContents && layer.contents==part.appliedContents) layer.contents=part.originalContents;
        if (layer && part.appliedColors && [layer isKindOfClass:CAGradientLayer.class] && [((CAGradientLayer *)layer).colors isEqual:part.appliedColors]) ((CAGradientLayer *)layer).colors=part.originalColors;
    }
    state.plainBubbleTextParts=nil; state.plainBubbleParts=nil; state.plainBubbleActive=NO; state.plainBubbleGeneration=0;
}
static DY778PlainBubblePart *DY778PlainPartForView(NSMutableArray *parts, UIView *view) {
    for (DY778PlainBubblePart *part in parts) if (part.view==view) return part;
    DY778PlainBubblePart *part=[DY778PlainBubblePart new]; part.view=view; part.originalHidden=view.hidden;
    part.originalBackground=view.backgroundColor; part.originalFill=DY778Read(view,@"fillColor");
    part.originalCornerRadius=view.layer.cornerRadius; part.originalClips=view.clipsToBounds; [parts addObject:part]; return part;
}
static void DY778HidePlainSkinView(NSMutableArray *parts, UIView *view) {
    if (!view || view.hidden) return;
    DY778PlainBubblePart *part=DY778PlainPartForView(parts,view); part.changedHidden=YES; view.hidden=YES;
}
static void DY778SetPlainBubbleSurface(NSMutableArray *parts, UIView *view, UIColor *color) {
    if (!view || ![view isKindOfClass:UIView.class]) return;
    DY778PlainBubblePart *part=DY778PlainPartForView(parts,view);
    view.backgroundColor=color; part.appliedBackground=color;
    if ([view respondsToSelector:NSSelectorFromString(@"setFillColor:")]) { DY778Write(view,@"fillColor",color); part.appliedFill=color; }
    if (view.layer.cornerRadius<6) { part.appliedCornerRadius=16; view.layer.cornerRadius=16; }
    if (!view.clipsToBounds) { part.appliedClips=YES; view.clipsToBounds=YES; }
}
static void DY778FlattenPlainGradient(NSMutableArray *parts, CALayer *root, UIColor *color, NSUInteger depth) {
    if (depth>4) return;
    for (CALayer *layer in root.sublayers) {
        if ([layer isKindOfClass:CAGradientLayer.class] && ((CAGradientLayer *)layer).colors.count) {
            DY778PlainBubblePart *part=[DY778PlainBubblePart new]; part.layer=layer; part.originalColors=((CAGradientLayer *)layer).colors;
            NSMutableArray *flat=[NSMutableArray array]; for (NSUInteger i=0;i<part.originalColors.count;i++) [flat addObject:(__bridge id)color.CGColor];
            part.appliedColors=flat; ((CAGradientLayer *)layer).colors=flat; [parts addObject:part];
        }
        if (layer.contents) { DY778PlainBubblePart *part=[DY778PlainBubblePart new]; part.layer=layer; part.originalContents=layer.contents; part.clearedContents=YES; layer.contents=nil; [parts addObject:part]; }
        DY778FlattenPlainGradient(parts,layer,color,depth+1);
    }
}
static BOOL DY778RecolorPlainBubbleText(NSMutableArray *textParts, UIView *cell, UIColor *color) {
    CGFloat red=0,green=0,blue=0,alpha=1; [color getRed:&red green:&green blue:&blue alpha:&alpha];
    UIColor *textColor=(red*.2126+green*.7152+blue*.0722)*alpha+1-alpha>.50 ? [UIColor colorWithRed:.10 green:.10 blue:.12 alpha:1] : [UIColor colorWithRed:.96 green:.96 blue:.97 alpha:1];
    Class labelClass=NSClassFromString(@"IESIMTextKitLabel"); if (!labelClass) return NO;
    NSMutableArray<UIView *> *pending=[NSMutableArray arrayWithObject:cell]; BOOL changed=NO;
    for (NSUInteger visited=0; pending.count && visited<180; visited++) {
        UIView *view=pending.lastObject; [pending removeLastObject]; NSString *name=NSStringFromClass(view.class);
        if ([name containsString:@"Giphy"] || [name containsString:@"Emoticon"] || [name containsString:@"Sticker"] || [name containsString:@"Emoji"]) continue;
        if ([view isKindOfClass:labelClass]) {
            NSAttributedString *original=DY778Read(view,@"attributedText");
            if (original.length && original.length<8192) {
                __block UIColor *dominant=nil; __block NSUInteger largest=0;
                [original enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0,original.length) options:0 usingBlock:^(id value,NSRange range,BOOL *stop){
                    if (![value isKindOfClass:UIColor.class] || [original attribute:NSLinkAttributeName atIndex:range.location effectiveRange:NULL] || [original attribute:NSAttachmentAttributeName atIndex:range.location effectiveRange:NULL]) return;
                    NSUInteger weight=range.length;
                    if (weight>largest) { largest=weight; dominant=value; }
                }];
                if (dominant) {
                    NSMutableAttributedString *copy=[original mutableCopy];
                    [original enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0,original.length) options:0 usingBlock:^(id value,NSRange range,BOOL *stop){
                        if ([value isKindOfClass:UIColor.class] && [value isEqual:dominant] &&
                            ![original attribute:NSLinkAttributeName atIndex:range.location effectiveRange:NULL] &&
                            ![original attribute:NSAttachmentAttributeName atIndex:range.location effectiveRange:NULL]) [copy addAttribute:NSForegroundColorAttributeName value:textColor range:range];
                    }];
                    if (![copy isEqualToAttributedString:original]) { DY778PlainBubbleTextPart *part=[DY778PlainBubbleTextPart new]; part.view=view; part.originalText=original; part.appliedText=copy; [textParts addObject:part]; DY778Write(view,@"attributedText",copy); changed=YES; }
                }
            }
        } else for (UIView *child in view.subviews) { if (pending.count>=180) break; [pending addObject:child]; }
    }
    return changed;
}
static BOOL DY778ApplyPlainBubbleSkin(DY778CellDecorationState *state, UITableViewCell *cell, BOOL outgoing, UITraitCollection *traits) {
    NSMutableArray<UIView *> *pending=[NSMutableArray arrayWithObject:cell.contentView], *skinViews=[NSMutableArray array], *hosts=[NSMutableArray array], *surfaces=[NSMutableArray array];
    for (NSUInteger visited=0; pending.count && visited<220; visited++) {
        UIView *view=pending.lastObject; [pending removeLastObject]; NSString *name=NSStringFromClass(view.class);
        if ([name isEqual:@"AWEIMMessageBubbleGradientView"]) {
            UIView *bubble=DY778Read(view,@"userBubbleView");
            if ([bubble isKindOfClass:UIImageView.class] && ((UIImageView *)bubble).image) { [skinViews addObject:bubble]; [hosts addObject:view]; }
        } else if ([name isEqual:@"AWEIMMessageBubbleThemeView"]) {
            BOOL themed=NO;
            for (NSString *key in @[@"leftTopView",@"rightTopView",@"leftBottomView",@"rightBottomView"]) { id image=DY778Read(view,key); if ([image isKindOfClass:UIImageView.class] && ((UIImageView *)image).image) themed=YES; }
            if (themed) {
                [skinViews addObject:view];
                for (UIView *parent=view.superview; parent && parent!=cell.contentView; parent=parent.superview) {
                    NSString *parentName=NSStringFromClass(parent.class);
                    if ([parentName isEqual:@"AWEIMShapeView"] || [parentName containsString:@"MessageBubble"]) { [surfaces addObject:parent]; break; }
                }
            }
        } else if ([name isEqual:@"AWEIMMessageAnimationBubbleView"] && DY778Identifier(DY778Read(view,@"bubbleID")).length) [skinViews addObject:view];
        for (UIView *child in view.subviews) { if (pending.count>=220) break; [pending addObject:child]; }
    }
    if (!DY778RecallShouldNormalizeBubbleSkin(state.recalled,DY778Bool(@"recall.plainBubbleOnSkin"),DY778MessageAllowsBubbleTint(cell),skinViews.count>0)) return NO;
    UIColor *fill=DY778PlainBubbleReferenceColor(cell,outgoing,traits);
    if (DY778Bool(@"recall.tintBubble")) fill=[DY778TintColor(@"recall.bubbleColor") resolvedColorWithTraitCollection:traits];
    NSMutableArray *parts=[NSMutableArray array], *textParts=[NSMutableArray array];
    for (UIView *view in skinViews) DY778HidePlainSkinView(parts,view);
    for (UIView *host in hosts) {
        UIView *surface=DY778Read(host,@"gradientView");
        if ([surface isKindOfClass:UIView.class]) { DY778SetPlainBubbleSurface(parts,surface,fill); DY778FlattenPlainGradient(parts,surface.layer,fill,0); }
    }
    for (UIView *surface in surfaces) DY778SetPlainBubbleSurface(parts,surface,fill);
    UIView *content=state.messageContentView;
    if (!DY778CanBeBubble(content,cell)) {
        NSUInteger componentBudget=48;
        content=DY778ContentFromComponents(DY778Read(DY778ViewModelForCell(cell),@"componentManager"),cell,0,&componentBudget);
    }
    if (!surfaces.count && !hosts.count) {
        UIView *candidate=state.bubbleView;
        if (!DY778CanBeBubble(candidate,cell)) candidate=DY778FindBubble(cell,&content);
        NSString *candidateName=NSStringFromClass(candidate.class);
        if ([candidateName isEqual:@"AWEIMShapeView"] || [candidateName containsString:@"MessageBubble"]) DY778SetPlainBubbleSurface(parts,candidate,fill);
    }
    DY778RecolorPlainBubbleText(textParts,content ?: cell,fill);
    state.plainBubbleParts=parts; state.plainBubbleTextParts=textParts; state.plainBubbleActive=YES; state.plainBubbleGeneration=DY778DecorationGeneration;
    return YES;
}
static CGRect DY778BubbleRect(UITableViewCell *cell, UIView *bubble, UIView *content) {
    CGRect rect = bubble ? [bubble convertRect:bubble.bounds toView:cell] : CGRectNull;
    if (bubble && [NSStringFromClass(bubble.class) isEqualToString:@"AWEIMShapeView"]) {
        CAShapeLayer *layer = DY778Read(bubble, @"shapeLayer");
        if ([layer isKindOfClass:CAShapeLayer.class] && layer.path) {
            CGRect path = CGPathGetBoundingBox(layer.path);
            if (DY778ValidRect(path)) rect = [bubble convertRect:path toView:cell];
        }
    }
    if (content && content != bubble) {
        CGRect contentRect = [content convertRect:content.bounds toView:cell];
        CGRect combined = CGRectIsNull(rect) ? contentRect : CGRectUnion(rect, contentRect);
        if (DY778ValidRect(combined) && combined.size.width <= cell.bounds.size.width - 24) rect = combined;
    }
    if (DY778ValidRect(rect)) return rect;
    SEL selector = NSSelectorFromString(@"messageBubbleFrame");
    Method method = class_getInstanceMethod(cell.class, selector);
    char result[160] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return CGRectNull;
    method_getReturnType(method, result, sizeof(result));
    if (strcmp(result, @encode(CGRect)) != 0) return CGRectNull;
    rect = ((CGRect (*)(id, SEL))objc_msgSend)(cell, selector);
    return DY778ValidRect(rect) ? rect : CGRectNull;
}
static CGRect DY778VisibleObstacleBounds(UIView *view) {
    UIColor *background = view.backgroundColor;
    BOOL filled = background && CGColorGetAlpha(background.CGColor) > .01;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (!label.text.length && !label.attributedText.length) return filled ? view.bounds : CGRectNull;
        if (filled) return view.bounds;
        // textRect reflects line wrapping, alignment and native insets. A label's
        // transparent full-width frame is not itself painted content.
        CGRect text = [label textRectForBounds:label.bounds limitedToNumberOfLines:label.numberOfLines];
        return CGRectIsEmpty(text) ? view.bounds : CGRectIntersection(view.bounds, text);
    }
    if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *image = (UIImageView *)view;
        if (!image.image && !image.highlightedImage && !image.animationImages.count && !filled) return CGRectNull;
    }
    return view.bounds;
}
static void DY778CollectObstacles(UIView *view, UITableViewCell *cell, UIView *bubble, UIView *content, DY778CellDecorationState *state,
    NSUInteger depth, NSUInteger *budget, DY778LayoutRect *rects, size_t *count) {
    if (!view || depth > 8 || !*budget || *count >= 128 || view.hidden || view.alpha < .01 || DY778IsOwnDecoration(view, state)) return;
    (*budget)--;
    if (view == bubble || view == content) return;
    NSString *name = NSStringFromClass(view.class);
    BOOL ornament = [name containsString:@"Separator"] || [name containsString:@"Background"] || [name containsString:@"Highlight"] || [name containsString:@"Selection"];
    BOOL container = (bubble && [bubble isDescendantOfView:view]) || (content && [content isDescendantOfView:view]);
    BOOL paint = [view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UIControl.class] || [name containsString:@"Label"] || [name containsString:@"Avatar"];
    if (view != cell.contentView && paint && !ornament && !container) {
        CGRect local = DY778VisibleObstacleBounds(view);
        if (!CGRectIsNull(local) && !CGRectIsEmpty(local)) {
            CGRect rect = CGRectIntersection(cell.bounds, [view convertRect:local toView:cell]);
            if (!CGRectIsNull(rect) && !CGRectIsEmpty(rect)) rects[(*count)++] = DY778LayoutRectFromCGRect(CGRectInset(rect, -1, -1));
        }
    }
    for (UIView *child in view.subviews) DY778CollectObstacles(child, cell, bubble, content, state, depth + 1, budget, rects, count);
}
static BOOL DY778ViewContainsTransparentMedia(UIView *view, NSUInteger depth, NSUInteger *budget) {
    if (!view || depth > 6 || !*budget) return NO;
    (*budget)--;
    NSString *name = NSStringFromClass(view.class);
    for (NSString *word in @[@"Giphy", @"Emoticon", @"Emoji", @"Sticker", @"ImageContent", @"VideoContent", @"WatchOnce"])
        if ([name containsString:word]) return YES;
    for (UIView *child in view.subviews) if (DY778ViewContainsTransparentMedia(child, depth + 1, budget)) return YES;
    return NO;
}
static UIColor *DY778TintColor(NSString *key) {
    UIColor *chosen = DY778ColorFromHex(DY778String(key), [UIColor colorWithRed:.29 green:.19 blue:.22 alpha:1]);
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) return chosen;
        CGFloat r = 0, g = 0, b = 0, a = 1; [chosen getRed:&r green:&g blue:&b alpha:&a];
        return [UIColor colorWithRed:.78 + .22*r green:.78 + .22*g blue:.78 + .22*b alpha:1];
    }];
}
static void DY778ApplyTint(DY778CellDecorationState *state, UIView *bubble, NSString *colorKey, UITraitCollection *traits) {
    if (!colorKey.length || !bubble) { DY778RestoreTint(state); return; }
    NSUInteger budget = 100;
    if (DY778ViewContainsTransparentMedia(bubble, 0, &budget)) { DY778RestoreTint(state); return; }
    UIColor *color = [DY778TintColor(colorKey) resolvedColorWithTraitCollection:traits];
    if ([bubble isKindOfClass:UIImageView.class]) {
        UIImageView *image = (UIImageView *)bubble;
        if (!image.image || DY778Read(bubble.superview, @"userBubbleView") != bubble) { DY778RestoreTint(state); return; }
        if (state.tintedView != image || image.image != state.appliedBubbleImage) {
            DY778RestoreTint(state); state.originalBubbleImage = image.image;
            state.appliedBubbleImage = [image.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            state.originalFill = image.tintColor; state.tintedView = image; state.fillProperty = @"tintColor";
        } else if (![image.tintColor isEqual:state.appliedFill]) state.originalFill = image.tintColor;
        image.image = state.appliedBubbleImage; image.tintColor = color; state.appliedFill = color; return;
    }
    CAGradientLayer *gradient = nil;
    BOOL nativeGradient = [NSStringFromClass(bubble.superview.class) isEqual:@"AWEIMMessageBubbleGradientView"] && DY778Read(bubble.superview, @"gradientView") == bubble;
    if (nativeGradient) {
        if ([bubble.layer isKindOfClass:CAGradientLayer.class]) gradient = (CAGradientLayer *)bubble.layer;
        else for (CALayer *layer in bubble.layer.sublayers) if ([layer isKindOfClass:CAGradientLayer.class]) { gradient = (CAGradientLayer *)layer; break; }
    }
    if (gradient.colors.count) {
        if (state.tintedGradient != gradient) { DY778RestoreTint(state); state.tintedGradient = gradient; state.originalGradientColors = gradient.colors; }
        else if (![gradient.colors isEqual:state.appliedGradientColors]) state.originalGradientColors = gradient.colors;
        NSMutableArray *colors = [NSMutableArray array];
        for (NSUInteger i = 0; i < state.originalGradientColors.count; i++) [colors addObject:(__bridge id)color.CGColor];
        if (![gradient.colors isEqual:colors]) gradient.colors = colors;
        state.appliedGradientColors = colors; return;
    }
    id contents = bubble.layer.contents;
    if (nativeGradient && contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID()) {
        if (state.tintedContentsLayer == bubble.layer && contents == state.appliedLayerContents && [state.appliedFill isEqual:color]) return;
        if (state.tintedContentsLayer != bubble.layer || contents != state.appliedLayerContents) {
            DY778RestoreTint(state); state.tintedContentsLayer = bubble.layer; state.originalLayerContents = contents;
        }
        UIImage *original = [UIImage imageWithCGImage:(__bridge CGImageRef)state.originalLayerContents];
        UIImage *painted = [original imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (!painted.CGImage) { DY778RestoreTint(state); return; }
        state.appliedLayerContents = (__bridge id)painted.CGImage; state.appliedFill = color;
        bubble.layer.contents = state.appliedLayerContents; return;
    }
    UIView *target = bubble;
    NSString *property = [NSStringFromClass(target.class) isEqualToString:@"AWEIMShapeView"] ? @"fillColor" : @"backgroundColor";
    UIColor *current = DY778Read(target, property);
    if ((!current || ![current isKindOfClass:UIColor.class] || CGColorGetAlpha(current.CGColor) < .05) && [NSStringFromClass(bubble.class) isEqualToString:@"AWEIMMessageBubbleGradientView"]) {
        UIView *gradient = DY778Read(bubble, @"gradientView");
        if ([gradient isKindOfClass:UIView.class] && ![gradient isKindOfClass:UIImageView.class]) { target = gradient; property = @"backgroundColor"; current = gradient.backgroundColor; }
    }
    if (![current isKindOfClass:UIColor.class] || CGColorGetAlpha(current.CGColor) < .05) { DY778RestoreTint(state); return; }
    if (state.tintedView == target && [state.fillProperty isEqualToString:property] && [state.appliedFill isEqual:color] && [current isEqual:color]) return;
    if (state.tintedGradient || state.tintedContentsLayer || state.appliedBubbleImage || state.tintedView != target || ![state.fillProperty isEqualToString:property]) { DY778RestoreTint(state); state.originalFill = current; }
    else if (![current isEqual:state.appliedFill]) state.originalFill = current;
    state.tintedView = target; state.fillProperty = property; state.appliedFill = color;
    DY778Write(target, property, color);
}
static BOOL DY778MessageAllowsBubbleTint(UITableViewCell *cell) {
    NSString *name = NSStringFromClass([DY778ViewModelForCell(cell) class]);
    for (NSString *word in @[@"Giphy", @"Emoticon", @"Emoji", @"Sticker", @"NormalImage", @"MixImage", @"VideoMessage", @"EncryptedImage", @"MixVideo"])
        if ([name containsString:word]) return NO;
    return YES;
}
static UIUserInterfaceStyle DY778ChatStyle(UIView *view) {
    Class cls = NSClassFromString(@"AWEUIThemeManager");
    Method method = class_getClassMethod(cls, NSSelectorFromString(@"isLightTheme"));
    if (method && method_getNumberOfArguments(method) == 2) {
        char result[8] = {0}; method_getReturnType(method, result, sizeof(result));
        if (result[0] == 'B' || result[0] == 'c') return ((BOOL (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"isLightTheme")) ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    }
    return view.window.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
}
static void DY778UpdateCell(UITableViewCell *cell) {
    DY778CellDecorationState *state = DY778CellState(cell, NO);
    if (!NSThread.isMainThread || !state || state.updating || !state.controller || !cell.window) return;
    state.updating = YES;
    @try {
        if (!DY778Bool(@"time.enabled") && !DY778Bool(@"recall.enabled") && !DY778Bool(@"edit.enabled")) { DY778HideCellDecorations(state); DY778ClearNativeMediaFallback(state); return; }
        id message = DY778MessageForCell(cell);
        if (!message) { DY778HideCellDecorations(state); DY778ClearNativeMediaFallback(state); return; }
        BOOL bindingChanged = state.message != message;
        if (bindingChanged) {
            DY778HideCellDecorations(state); DY778ClearNativeMediaFallback(state);
            state.message = message; state.observedMessage = nil; state.appearanceGeneration = 0; state.geometryGeneration = 0; state.styleKey = nil;
            // Resolve SDK metadata once per binding, after the native layout stack
            // has returned. All subsequent geometry passes use these plain values.
            NSDictionary *record = DY778RecallRecordForMessage(message);
            NSString *account = record[@"account"] ?: DY778CurrentAccountID();
            state.conversationID = record[@"conversation"] ?: DY778ConversationForMessage(message);
            state.messageKey = record[@"key"] ?: DY778MessageKey(message, account, state.conversationID);
            state.timestamp = DY778NormalizedTimestamp([record[@"createdAt"] doubleValue]);
            if (!state.timestamp) state.timestamp = DY778TimestampForMessage(message);
            state.outgoing = [record[@"sender"] length] ? [record[@"sender"] isEqualToString:account] : DY778MessageIsMine(message, account);
        }
        if (!DY778Bool(@"recall.enabled") && !DY778Bool(@"edit.enabled")) state.observedMessage = nil;
        else if (state.observedMessage != message) {
            state.observedMessage = message;
            DY778ObserveMessage(message);
            DY778ObserveMessageContext(DY778ViewModelForCell(cell));
        }
        BOOL recallEnabled = DY778RecallEnabledForMessage(message);
        if (state.appearanceGeneration != DY778DecorationGeneration || bindingChanged) {
            state.appearanceGeneration = DY778DecorationGeneration;
            NSDictionary *record = DY778RecallRecordForMessage(message);
            NSTimeInterval updated = DY778NormalizedTimestamp([record[@"createdAt"] doubleValue]);
            if (updated) state.timestamp = updated;
            if ([record[@"conversation"] length]) state.conversationID = record[@"conversation"];
            if ([record[@"key"] length]) state.messageKey = record[@"key"];
            if ([record[@"account"] length] && [record[@"sender"] length]) state.outgoing = [record[@"account"] isEqualToString:record[@"sender"]];
            state.recalled = recallEnabled && !state.outgoing && DY778MessageWasRecalled(message);
            state.available = state.recalled && [record[@"available"] boolValue];
        }
        BOOL recalled = recallEnabled && state.recalled;
        BOOL plainSkinEnabled = recalled && DY778Bool(@"recall.plainBubbleOnSkin") && DY778MessageAllowsBubbleTint(cell);
        if (state.plainBubbleActive && (!plainSkinEnabled || state.plainBubbleGeneration != DY778DecorationGeneration)) { DY778RestoreTint(state); DY778RestorePlainBubble(state); state.geometryGeneration=0; }
        if (recalled && state.available && DY778RestoreRecallPresentation(DY778ViewModelForCell(cell), message)) {
            state.geometryGeneration = 0; DY778QueueNativeTableRefresh(state.controller); return;
        }
        DY778RepairNativeMedia(cell, state, recalled ? DY778RecallRecordForMessage(message) : nil);
        BOOL showTime = DY778Bool(@"time.enabled") && state.timestamp > 0;
        BOOL showRecall = recalled && DY778Bool(@"recall.badge");
        NSDictionary *editRecord = DY778EditRecordForMessage(message);
        BOOL showEdit = !state.outgoing && DY778Bool(@"edit.badge") && editRecord != nil;
        NSString *tintKey = recalled && DY778Bool(@"recall.tintBubble") ? @"recall.bubbleColor" :
            (!state.outgoing && editRecord && DY778Bool(@"edit.tintBubble") ? @"edit.bubbleColor" : nil);
        if (!showTime && !showRecall && !showEdit && !tintKey && !plainSkinEnabled) { DY778HideCellDecorations(state); return; }
        if ([DY778Read(cell, @"isMultiselect") boolValue] || [DY778Read(state.controller, @"isMultiselect") boolValue]) { DY778HideCellDecorations(state); return; }
        if (plainSkinEnabled && !state.plainBubbleActive) {
            UIUserInterfaceStyle skinStyle=DY778ChatStyle(cell);
            state.plainBubbleActive=DY778ApplyPlainBubbleSkin(state,cell,state.outgoing,[UITraitCollection traitCollectionWithUserInterfaceStyle:skinStyle]);
            if (state.plainBubbleActive) state.geometryGeneration=0;
        }
        UIView *content = state.messageContentView;
        UIView *bubble = state.bubbleView;
        if (state.geometryGeneration != DY778DecorationGeneration || !DY778CanBeBubble(bubble, cell) || (content && !DY778CanBeBubble(content, cell))) {
            content = nil; bubble = DY778FindBubble(cell, &content);
            state.bubbleView = bubble; state.messageContentView = content; state.geometryGeneration = DY778DecorationGeneration;
        }
        CGRect bubbleRect = DY778BubbleRect(cell, bubble, content);
        if (!DY778ValidRect(bubbleRect) || !CGRectIntersectsRect(cell.bounds, bubbleRect)) {
            if (!showRecall && !showEdit) { DY778HideCellDecorations(state); return; }
            bubbleRect = CGRectInset(cell.contentView.frame, 8, 3);
        }
        UIUserInterfaceStyle style = DY778ChatStyle(cell);
        UITraitCollection *traits = [UITraitCollection traitCollectionWithUserInterfaceStyle:style];
        DY778ApplyTint(state, bubble, DY778MessageAllowsBubbleTint(cell) ? tintKey : nil, traits);
        if (!showTime && !showRecall && !showEdit) { state.timeLabel.hidden = YES; state.recallBadge.hidden = YES; state.editBadge.hidden = YES; return; }
        if (!state.timeLabel) {
            state.timeLabel = [UILabel new]; state.timeLabel.userInteractionEnabled = NO; state.timeLabel.isAccessibilityElement = YES;
            state.timeLabel.accessibilityIdentifier = @"DY778.MessageTime";
            [cell.contentView addSubview:state.timeLabel];
        }
        if (!state.recallBadge) { state.recallBadge = [DY778RecallBadge new]; state.recallBadge.accessibilityIdentifier = @"DY778.RecallBadge"; [cell.contentView addSubview:state.recallBadge]; }
        if (state.timeLabel.superview != cell.contentView) [cell.contentView addSubview:state.timeLabel];
        if (state.recallBadge.superview != cell.contentView) [cell.contentView addSubview:state.recallBadge];
        if (state.timeLabel.overrideUserInterfaceStyle != style) state.timeLabel.overrideUserInterfaceStyle = style;
        if (state.recallBadge.overrideUserInterfaceStyle != style) state.recallBadge.overrideUserInterfaceStyle = style;
        NSString *time = showTime ? DY778FormatMessageTime(state.timestamp) : @"";
        NSString *styleKey = [NSString stringWithFormat:@"%lu|%ld|%d|%@", (unsigned long)DY778DecorationGeneration, (long)style, state.available, time];
        if (![state.styleKey isEqualToString:styleKey]) {
            state.styleKey = styleKey; DY778ConfigureTime(state.timeLabel, time); DY778ConfigureRecall(state.recallBadge, state.available);
        }
        if (!state.editBadge && showEdit) { state.editBadge = [DY778EditBadge new]; state.editBadge.accessibilityIdentifier = @"DY778.EditHistoryBadge"; [cell.contentView addSubview:state.editBadge]; }
        state.editBadge.hidden = !showEdit; state.editBadge.record = editRecord; state.editBadge.source = state.controller;
        state.editBadge.overrideUserInterfaceStyle = style;
        if (showEdit) DY778ConfigureEdit(state.editBadge, [editRecord[@"changes"] unsignedIntegerValue]);
        state.recallBadge.source = state.controller; state.recallBadge.conversationID = state.conversationID;
        CGFloat timeWidth = MIN(200, ceil([time sizeWithAttributes:@{NSFontAttributeName:state.timeLabel.font}].width) + 10);
        CGFloat recallWidth = MIN(156, ceil([state.recallBadge.currentTitle sizeWithAttributes:@{NSFontAttributeName:state.recallBadge.titleLabel.font}].width) + 12);
        DY778LayoutItem timeItem = {timeWidth, ceil(state.timeLabel.font.lineHeight) + 4, showTime, DY778PreferredPosition(@"time.position")};
        CGFloat recallHeight = ceil(state.recallBadge.titleLabel.font.lineHeight) + 4;
        CGFloat editWidth = showEdit ? MIN(160, ceil([state.editBadge.currentTitle sizeWithAttributes:@{NSFontAttributeName:state.editBadge.titleLabel.font}].width) + 12) : 0;
        CGFloat editHeight = showEdit ? ceil(state.editBadge.titleLabel.font.lineHeight) + 4 : 0;
        DY778LayoutItem recallItem = {recallWidth, recallHeight, showRecall, DY778PreferredPosition(@"recall.position")};
        DY778LayoutItem editItem = {editWidth, editHeight, showEdit, DY778PreferredPosition(@"edit.position")};
        CGRect layoutBounds = CGRectIntersection(cell.bounds, [cell.contentView convertRect:cell.contentView.bounds toView:cell]);
        CGFloat available = CGRectGetMaxX(layoutBounds) - CGRectGetMaxX(bubbleRect) - 9;
        if (available >= 40) {
            if (recallItem.position == DY778LayoutRight) recallItem.width = MIN(recallItem.width, available);
            if (editItem.position == DY778LayoutRight) editItem.width = MIN(editItem.width, available);
        }
        BOOL compact = showTime && (showRecall || showEdit) && timeItem.height + MAX(recallHeight, editHeight) + 2 > layoutBounds.size.height - 4;
        if (compact) { timeItem.height -= 2; recallItem.height -= 2; editItem.height -= 2; }
        UIEdgeInsets badgeInsets = UIEdgeInsetsMake(compact ? 1 : 2, 6, compact ? 1 : 2, 6);
        state.recallBadge.contentEdgeInsets = badgeInsets; state.editBadge.contentEdgeInsets = badgeInsets;
        DY778LayoutRect obstacles[128]; size_t count = 0; NSUInteger budget = 240;
        DY778CollectObstacles(cell, cell, bubble, content, state, 0, &budget, obstacles, &count);
        DY778DecorationLayoutResult layout = DY778ComputeDecorationLayout(DY778LayoutRectFromCGRect(layoutBounds), DY778LayoutRectFromCGRect(bubbleRect), timeItem, recallItem, editItem, state.outgoing, obstacles, count);
        UIView *views[3] = {state.timeLabel, state.recallBadge, state.editBadge};
        for (NSUInteger i = 0; i < 3; i++) {
            views[i].hidden = !layout.visible[i];
            if (layout.visible[i]) {
                views[i].frame = [cell convertRect:DY778CGRectFromLayoutRect(layout.frames[i]) toView:cell.contentView];
                [cell.contentView bringSubviewToFront:views[i]];
            }
        }
    } @finally { state.updating = NO; }
}
static void DY778QueueCellUpdate(UITableViewCell *cell) {
    DY778CellDecorationState *state = DY778CellState(cell, NO);
    if (!state || state.queued || state.updating) return;
    state.queued = YES;
    __weak UITableViewCell *weakCell = cell;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableViewCell *strongCell = weakCell;
        if (!strongCell) return;
        DY778CellState(strongCell, NO).queued = NO;
        DY778UpdateCell(strongCell);
    });
}
@interface DY778MessageUICoordinator : NSObject
@property(nonatomic, strong) NSHashTable<UIViewController *> *controllers;
@property(nonatomic) BOOL scheduled;
@property(nonatomic) BOOL invalidationPending;
+ (instancetype)shared;
- (void)scheduleInvalidation:(BOOL)invalidate;
@end
@implementation DY778MessageUICoordinator
+ (instancetype)shared {
    static DY778MessageUICoordinator *coordinator; static dispatch_once_t once;
    dispatch_once(&once, ^{
        coordinator = [self new]; coordinator.controllers = [NSHashTable weakObjectsHashTable];
        for (NSNotificationName name in @[DY778PreferencesChangedNotification, DY778RecallChangedNotification, DY778EditHistoryChangedNotification, UIContentSizeCategoryDidChangeNotification,
            UIApplicationSignificantTimeChangeNotification, NSSystemTimeZoneDidChangeNotification, NSCurrentLocaleDidChangeNotification, UIApplicationDidBecomeActiveNotification])
            [NSNotificationCenter.defaultCenter addObserver:coordinator selector:@selector(changed:) name:name object:nil];
    });
    return coordinator;
}
- (void)changed:(NSNotification *)notification { [self scheduleInvalidation:YES]; }
- (void)scheduleInvalidation:(BOOL)invalidate {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self scheduleInvalidation:invalidate]; }); return; }
    self.invalidationPending |= invalidate;
    if (self.scheduled) return;
    self.scheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.scheduled = NO;
        if (self.invalidationPending) { DY778DecorationGeneration++; self.invalidationPending = NO; }
        for (UIViewController *controller in self.controllers) {
            if (!controller.isViewLoaded || !controller.view.window) continue;
            UITableView *table = DY778Read(controller, @"tableView");
            if (![table isKindOfClass:UITableView.class]) continue;
            for (UITableViewCell *cell in table.visibleCells) {
                DY778CellState(cell, YES).controller = controller;
                DY778QueueCellUpdate(cell);
            }
            NSMutableIndexSet *sections = [NSMutableIndexSet indexSet];
            for (NSIndexPath *path in table.indexPathsForVisibleRows) [sections addIndex:path.section];
            [sections enumerateIndexesUsingBlock:^(NSUInteger section, BOOL *stop) { DY778UpdateOfficialHeader([table headerViewForSection:section]); }];
        }
    });
}
@end
static void DY778QueueNativeTableRefresh(UIViewController *controller) {
    if (!controller) return;
    static NSHashTable *pending; static BOOL scheduled;
    if (!pending) pending = [NSHashTable weakObjectsHashTable]; [pending addObject:controller];
    if (scheduled) return; scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *controllers = pending.allObjects; [pending removeAllObjects]; scheduled = NO;
        for (UIViewController *active in controllers) {
            if (!active.isViewLoaded || !active.view.window) continue;
            UITableView *table = DY778Read(active, @"tableView"); if (![table isKindOfClass:UITableView.class]) continue;
            NSIndexPath *anchor = table.indexPathsForVisibleRows.firstObject; CGFloat anchorDelta = anchor ? table.contentOffset.y - CGRectGetMinY([table rectForRowAtIndexPath:anchor]) : 0;
            CGPoint previousOffset = table.contentOffset;
            SEL selector = NSSelectorFromString(@"updateAllCellHeight:"); Method method = class_getInstanceMethod(active.class, selector);
            char returned[8] = {0}, argument[8] = {0};
            if (method) { method_getReturnType(method, returned, sizeof(returned)); method_getArgumentType(method, 2, argument, sizeof(argument)); }
            BOOL canUpdateHeight = method && method_getNumberOfArguments(method) == 3 && returned[0] == 'v' && strchr("Bc", argument[0]);
            [UIView performWithoutAnimation:^{
                if (canUpdateHeight) ((void (*)(id, SEL, BOOL))objc_msgSend)(active, selector, NO);
                [table reloadData];
                [table layoutIfNeeded];
                CGPoint offset = previousOffset;
                if (anchor && anchor.section < [table numberOfSections] && anchor.row < [table numberOfRowsInSection:anchor.section]) offset.y = CGRectGetMinY([table rectForRowAtIndexPath:anchor]) + anchorDelta;
                CGFloat minimum = -table.adjustedContentInset.top, maximum = MAX(minimum, table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom);
                offset.y = MIN(maximum, MAX(minimum, offset.y)); [table setContentOffset:offset animated:NO];
            }];
        }
        [[DY778MessageUICoordinator shared] scheduleInvalidation:YES];
    });
}
void DY778RefreshMessageDecorations(void) { [[DY778MessageUICoordinator shared] scheduleInvalidation:YES]; }
static void (*DY778OriginalWillDisplay)(id, SEL, id, id, id);
static void DY778WillDisplay(id controller, SEL selector, UITableView *table, UITableViewCell *cell, NSIndexPath *path) {
    DY778OriginalWillDisplay(controller, selector, table, cell, path);
    if (![cell isKindOfClass:UITableViewCell.class]) return;
    [[DY778MessageUICoordinator shared].controllers addObject:controller];
    DY778CellState(cell, YES).controller = controller;
    DY778QueueCellUpdate(cell);
}
static void DY778InstallLifecycleHook(NSString *name) {
    NSString *key = [@"lifecycle:" stringByAppendingString:name];
    if ([DY778InstalledUIHooks containsObject:key]) return;
    Class cls = NSClassFromString(@"AWEIMMessageListViewController"); SEL selector = NSSelectorFromString(name);
    if (!DY778Signature(cls, selector, "v", 2)) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(UIViewController *controller) {
        ((void (*)(id, SEL))original)(controller, selector);
        [[DY778MessageUICoordinator shared].controllers addObject:controller];
        [[DY778MessageUICoordinator shared] scheduleInvalidation:NO];
    });
    BOOL installed = DY778Hook(cls, selector, replacement, &original);
    if (installed) [DY778InstalledUIHooks addObject:key]; else imp_removeBlock(replacement);
    DY778RecordHook([@"消息列表 / " stringByAppendingString:name], installed);
}
static void DY778InstallAppearanceHook(void) {
    NSString *key = @"lifecycle:viewDidAppear:";
    if ([DY778InstalledUIHooks containsObject:key]) return;
    Class cls = NSClassFromString(@"AWEIMMessageListViewController"); SEL selector = @selector(viewDidAppear:);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 3) return;
    char result[16] = {0}, argument[16] = {0}; method_getReturnType(method, result, 16); method_getArgumentType(method, 2, argument, 16);
    if (result[0] != 'v' || (argument[0] != 'B' && argument[0] != 'c')) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(UIViewController *controller, BOOL animated) {
        ((void (*)(id, SEL, BOOL))original)(controller, selector, animated);
        [[DY778MessageUICoordinator shared].controllers addObject:controller];
        [[DY778MessageUICoordinator shared] scheduleInvalidation:YES];
    });
    if (DY778Hook(cls, selector, replacement, &original)) [DY778InstalledUIHooks addObject:key]; else imp_removeBlock(replacement);
}
static void DY778InstallCellHooks(NSString *name) {
    Class cls = NSClassFromString(name);
    if (!cls || ![cls isSubclassOfClass:UITableViewCell.class]) return;
    NSString *layoutKey = [name stringByAppendingString:@":layoutSubviews"]; SEL layout = @selector(layoutSubviews);
    if (![DY778InstalledUIHooks containsObject:layoutKey] && DY778Signature(cls, layout, "v", 2)) {
        __block IMP original = NULL;
        IMP replacement = imp_implementationWithBlock(^(UITableViewCell *cell) {
            DY778CellDecorationState *state = DY778CellState(cell, NO);
            if (state) state.layoutDepth++;
            @try { ((void (*)(id, SEL))original)(cell, layout); }
            @finally { if (state && state.layoutDepth) state.layoutDepth--; }
            if (state && !state.layoutDepth) DY778QueueCellUpdate(cell);
        });
        BOOL installed = DY778Hook(cls, layout, replacement, &original);
        if (installed) [DY778InstalledUIHooks addObject:layoutKey]; else imp_removeBlock(replacement);
        DY778RecordHook([name stringByAppendingString:@" / 异步标签布局"], installed);
    }
    NSString *reuseKey = [name stringByAppendingString:@":prepareForReuse"]; SEL reuse = @selector(prepareForReuse);
    if (![DY778InstalledUIHooks containsObject:reuseKey] && DY778Signature(cls, reuse, "v", 2)) {
        __block IMP original = NULL;
        IMP replacement = imp_implementationWithBlock(^(UITableViewCell *cell) {
            DY778ArchiveCellWillReuse(cell);
            DY778CellDecorationState *state = DY778CellState(cell, NO);
            DY778HideCellDecorations(state); DY778ClearNativeMediaFallback(state); state.controller = nil; state.message = nil; state.observedMessage = nil; state.messageKey = nil; state.conversationID = nil; state.timestamp = 0; state.outgoing = NO; state.appearanceGeneration = 0; state.geometryGeneration = 0; state.bubbleView = nil; state.messageContentView = nil;
            ((void (*)(id, SEL))original)(cell, reuse);
        });
        if (DY778Hook(cls, reuse, replacement, &original)) [DY778InstalledUIHooks addObject:reuseKey]; else imp_removeBlock(replacement);
    }
}
static void DY778RestoreOfficialHeader(id header) {
    NSArray *saved = objc_getAssociatedObject(header, &kDY778HeaderStateKey);
    if (saved.count != 4) return;
    if ([saved[0] isKindOfClass:UIView.class] && [saved[0] isHidden]) [saved[0] setHidden:[saved[1] boolValue]];
    if ([saved[2] isKindOfClass:UIView.class] && [saved[2] isHidden]) [saved[2] setHidden:[saved[3] boolValue]];
    objc_setAssociatedObject(header, &kDY778HeaderStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void DY778UpdateOfficialHeader(id header) {
    if (!header) return;
    if (!DY778Bool(@"time.enabled") || !DY778Bool(@"time.hideOfficial")) { DY778RestoreOfficialHeader(header); return; }
    UIView *label = DY778Read(header, @"timeLabel"), *background = DY778Read(header, @"timeLabelBgView");
    if (![label isKindOfClass:UIView.class] || ![background isKindOfClass:UIView.class]) return;
    NSArray *saved = objc_getAssociatedObject(header, &kDY778HeaderStateKey);
    if (saved.count != 4 || saved[0] != label || saved[2] != background) {
        DY778RestoreOfficialHeader(header);
        objc_setAssociatedObject(header, &kDY778HeaderStateKey, @[label, @(label.hidden), background, @(background.hidden)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!label.hidden) label.hidden = YES;
    if (!background.hidden) background.hidden = YES;
}
static void DY778InstallOfficialHeaderHook(void) {
    NSString *key = @"header:configWithText:chatHasBackground:";
    if ([DY778InstalledUIHooks containsObject:key]) return;
    Class cls = NSClassFromString(@"AWEIMMessageBaseHeaderView"); SEL selector = NSSelectorFromString(@"configWithText:chatHasBackground:");
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 4) return;
    char result[16] = {0}, first[16] = {0}, last[16] = {0};
    method_getReturnType(method, result, 16); method_getArgumentType(method, 2, first, 16); method_getArgumentType(method, 3, last, 16);
    if (result[0] != 'v' || first[0] != '@' || (last[0] != 'B' && last[0] != 'c')) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(id header, id text, BOOL background) {
        DY778RestoreOfficialHeader(header);
        ((void (*)(id, SEL, id, BOOL))original)(header, selector, text, background);
        DY778UpdateOfficialHeader(header);
    });
    BOOL installed = DY778Hook(cls, selector, replacement, &original);
    if (installed) [DY778InstalledUIHooks addObject:key]; else imp_removeBlock(replacement);
    DY778RecordHook(@"消息 / 原生时间配置", installed);
}
void DY778InstallMessageUIHooks(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallMessageUIHooks(); }); return; }
    if (!DY778InstalledUIHooks) DY778InstalledUIHooks = [NSMutableSet set];
    [DY778MessageUICoordinator shared];
    Class cls = NSClassFromString(@"AWEIMMessageListViewController");
    if (!DY778OriginalWillDisplay) {
        SEL selector = NSSelectorFromString(@"tableView:willDisplayCell:forRowAtIndexPath:");
        BOOL installed = DY778Signature(cls, selector, "v", 5) && DY778Hook(cls, selector, (IMP)DY778WillDisplay, (IMP *)&DY778OriginalWillDisplay);
        DY778RecordHook(@"消息 / 绑定消息装饰", installed);
    }
    DY778InstallLifecycleHook(@"viewDidLoad"); DY778InstallLifecycleHook(@"vm_afterReloadData"); DY778InstallLifecycleHook(@"vm_afterUpdateData"); DY778InstallAppearanceHook();
    for (NSString *name in @[@"AWEIMReusableCommonCell", @"AWEIMMessageBaseTableViewCell", @"AWEIMUserMessageTableViewCell",
        @"AWEIMCloseFriendInviteMessageTableViewCell", @"AWEIMInviteFriendTableViewCell", @"AWEIMShareH5GoodsMessageTableViewCell", @"AWEIMShareGameMessageTableViewCell",
        @"AWEIMShareLiveMessageTableViewCell", @"AWEIMTextLinkMessageTableViewCell", @"AWEIMThirdPartLinkMessageTableViewCell", @"AWEIMVoipMessageTableViewCell"]) DY778InstallCellHooks(name);
    DY778InstallOfficialHeaderHook();

}
@interface DY778TimePreview : UIView
@property(nonatomic) BOOL editPreview;
@property(nonatomic, strong) UILabel *caption;
@property(nonatomic, strong) UILabel *bubble;
@property(nonatomic, strong) UIImageView *avatar;
@property(nonatomic, strong) UILabel *hint;
@property(nonatomic, strong) UILabel *timeLabel;
@property(nonatomic, strong) DY778RecallBadge *recallBadge;
@end
@implementation DY778TimePreview
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 18; self.layer.masksToBounds = YES; self.clipsToBounds = YES; self.opaque = YES;
        self.caption = [UILabel new]; self.caption.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium]; self.caption.textColor = UIColor.secondaryLabelColor;
        self.avatar = [UIImageView new]; self.avatar.contentMode = UIViewContentModeScaleAspectFill; self.avatar.image = [UIImage systemImageNamed:@"person.crop.circle.fill"]; self.avatar.layer.cornerRadius = 15; self.avatar.layer.masksToBounds = YES;
        self.bubble = [UILabel new]; self.bubble.text = @"  每一句，都有迹可循。 "; self.bubble.font = [UIFont systemFontOfSize:13]; self.bubble.textColor = UIColor.labelColor; self.bubble.numberOfLines = 2; self.bubble.layer.cornerRadius = 12; self.bubble.layer.masksToBounds = YES;
        self.hint = [UILabel new]; self.hint.font = [UIFont systemFontOfSize:10]; self.hint.textColor = UIColor.tertiaryLabelColor; self.hint.numberOfLines = 2; self.hint.text = @"右侧共用一列 · 空间不足时整体避让";
        self.timeLabel = [UILabel new]; self.recallBadge = [DY778RecallBadge new]; self.recallBadge.userInteractionEnabled = NO;
        for (UIView *view in @[self.caption, self.avatar, self.bubble, self.hint, self.timeLabel, self.recallBadge]) [self addSubview:view];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:) name:DY778PreferencesChangedNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:) name:UIContentSizeCategoryDidChangeNotification object:nil];
        [self refresh:nil];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)didMoveToWindow { [super didMoveToWindow]; if (self.window) DY778LoadCurrentAccountAvatar(self.avatar); }
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 194 + MAX(0, DY778TimeFont().lineHeight - 15)); }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(size.width, self.intrinsicContentSize.height); }
- (void)refresh:(NSNotification *)notification {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self refresh:notification]; }); return; }
    UIUserInterfaceStyle style = DY778InterfaceStyle();
    if (self.overrideUserInterfaceStyle != style) self.overrideUserInterfaceStyle = style;
    self.backgroundColor = DY778CardBackground();
    self.caption.text = DY778Bool(self.editPreview ? @"edit.enabled" : @"recall.enabled") || DY778Bool(@"time.enabled") ? @"样式预览" : @"样式预览 · 尚未启用";
    self.avatar.tintColor = DY778Accent(); self.avatar.backgroundColor = [DY778Accent() colorWithAlphaComponent:.12]; DY778LoadCurrentAccountAvatar(self.avatar);
    BOOL recallPlain=DY778Bool(@"recall.plainBubbleOnSkin");
    BOOL recallTint=DY778Bool(@"recall.tintBubble");
    if (self.editPreview) self.bubble.backgroundColor=DY778Bool(@"edit.tintBubble") ? DY778TintColor(@"edit.bubbleColor") : [DY778Accent() colorWithAlphaComponent:.11];
    else if (recallTint) self.bubble.backgroundColor=DY778TintColor(@"recall.bubbleColor");
    else if (recallPlain) self.bubble.backgroundColor=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark ? [UIColor colorWithRed:.22 green:.22 blue:.23 alpha:1] : [UIColor colorWithRed:.93 green:.93 blue:.94 alpha:1];
    else self.bubble.backgroundColor=[DY778Accent() colorWithAlphaComponent:.11];
    DY778ConfigureTime(self.timeLabel, DY778FormatMessageTime(NSDate.date.timeIntervalSince1970));
    if (self.editPreview) DY778ConfigureEdit(self.recallBadge, 1); else DY778ConfigureRecall(self.recallBadge, YES);
    [self invalidateIntrinsicContentSize]; [self setNeedsLayout];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) {
        DY778ConfigureTime(self.timeLabel, self.timeLabel.text); if (self.editPreview) DY778ConfigureEdit(self.recallBadge, 1); else DY778ConfigureRecall(self.recallBadge, YES);
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    self.caption.frame = CGRectMake(16, 15, MAX(0,width-32), 20);
    self.hint.frame = CGRectMake(16, self.bounds.size.height-31, MAX(0,width-32), 25);
    CGRect bubble = CGRectMake(52, 75, MAX(80,MIN(160,width-142)), 42);
    self.avatar.frame = CGRectMake(14, bubble.origin.y+2, 30, 30); self.bubble.frame = bubble;
    DY778LayoutRect obstacle = DY778LayoutRectFromCGRect(self.avatar.frame);
    DY778LayoutItem time = {MIN(200, ceil([self.timeLabel.text sizeWithAttributes:@{NSFontAttributeName:self.timeLabel.font}].width)+10), ceil(self.timeLabel.font.lineHeight)+4, 1, DY778PreferredPosition(@"time.position")};
    DY778LayoutItem recall = {MIN(156, ceil([self.recallBadge.currentTitle sizeWithAttributes:@{NSFontAttributeName:self.recallBadge.titleLabel.font}].width)+12), ceil(self.recallBadge.titleLabel.font.lineHeight)+4, 1, DY778PreferredPosition(self.editPreview ? @"edit.position" : @"recall.position")};
    DY778LayoutRect bounds = {0, 36, width, MAX(0,self.bounds.size.height-72)};
    if (recall.position == DY778LayoutRight) { CGFloat available = width - CGRectGetMaxX(bubble) - 9; if (available >= 40) recall.width = MIN(recall.width, available); }
    DY778LayoutItem hidden = {0};
    DY778DecorationLayoutResult layout = DY778ComputeDecorationLayout(bounds, DY778LayoutRectFromCGRect(bubble), time, self.editPreview ? hidden : recall, self.editPreview ? recall : hidden, 0, &obstacle, 1);
    NSUInteger status = self.editPreview ? 2 : 1;
    self.timeLabel.hidden = !layout.visible[0]; self.recallBadge.hidden = !layout.visible[status];
    if (layout.visible[0]) self.timeLabel.frame = DY778CGRectFromLayoutRect(layout.frames[0]);
    if (layout.visible[status]) self.recallBadge.frame = DY778CGRectFromLayoutRect(layout.frames[status]);
}
@end
UIView *DY778CreateTimePreview(void) { return [[DY778TimePreview alloc] initWithFrame:CGRectMake(0,0,340,194)]; }

UIView *DY778CreateEditPreview(void) { DY778TimePreview *preview = [[DY778TimePreview alloc] initWithFrame:CGRectMake(0,0,340,194)]; preview.editPreview = YES; [preview refresh:nil]; return preview; }
