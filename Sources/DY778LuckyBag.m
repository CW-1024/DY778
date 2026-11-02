#import "DY778LuckyBag.h"
#import "DY778LuckyPolicy.h"
#import "DY778LuckyClock.h"
#import "DY778Core.h"
#import "DY778Avatar.h"
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

// Coordinator state is confined to the main queue.
static NSNotificationName const DY778LuckyStateChanged = @"DY778LuckyStateChanged";
static char DY778LuckyComponentAccountKey;
static char DY778LuckyComponentMountKey;
static char DY778LuckyComponentRetiredKey;
static char DY778LuckyClockSampleKey;
static char DY778LuckyComponentRoomKey;
static char DY778LuckyQuietRequestKey;
static char DY778LuckyAuthorizationKey;
static BOOL DY778LuckyQuietHooksReady;
static NSString *DY778LuckyRouteToken;
static void DY778MarkLiveComponent(id component) {
    objc_setAssociatedObject(component, &DY778LuckyComponentRetiredKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(component, &DY778LuckyComponentAccountKey, DY778CurrentAccountID() ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(component, &DY778LuckyComponentMountKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@protocol DY778LuckyTouchInitializing <NSObject>
- (instancetype)initWithName:(NSString *)name targetTag:(long long)tag;
@end
@protocol DY778LuckyContextInitializing <NSObject>
- (instancetype)initWithState:(long long)state enterSource:(long long)source type:(long long)type;
@end
static NSString *DY778LiveString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return @"";
}
static NSString *DY778LiveID(id value) {
    NSString *s = DY778LiveString(value);
    return s.length && ![s isEqualToString:@"0"] ? s : nil;
}
static void DY778LiveMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}
static char DY778LuckyWebReadyKey, DY778LuckyWebAttachedKey;
static void DY778LuckyToast(NSString *text) {
    if (DY778Bool(@"lucky.enabled")) DY778ShowToast(@"lucky", text, NO, NO);
}
static const char *DY778Type(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}
static BOOL DY778LiveSignature(Class cls, SEL sel, const char *result, const char *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!method || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char buffer[32] = {0}; method_getReturnType(method, buffer, sizeof(buffer));
    if (!strchr(result, *DY778Type(buffer))) return NO;
    for (NSUInteger i = 0; i < strlen(arguments); i++) {
        method_getArgumentType(method, (unsigned int)i + 2, buffer, sizeof(buffer));
        char actual = *DY778Type(buffer), expected = arguments[i];
        if (expected == 'B' ? !(actual == 'B' || actual == 'c') :
            expected == 'q' ? !(actual == 'q' || actual == 'Q') : actual != expected) return NO;
    }
    return YES;
}
static BOOL DY778LiveCanCall(id object, NSString *selector, const char *result, const char *arguments) {
    if (!object) return NO;
    SEL sel = NSSelectorFromString(selector);
    if (DY778LiveSignature(object_getClass(object), sel, result, arguments)) return YES;
    @try {
        NSMethodSignature *signature = [object methodSignatureForSelector:sel];
        if (!signature || signature.numberOfArguments != strlen(arguments) + 2 ||
            !strchr(result, *DY778Type(signature.methodReturnType))) return NO;
        for (NSUInteger i = 0; i < strlen(arguments); i++) {
            char actual = *DY778Type([signature getArgumentTypeAtIndex:i + 2]), expected = arguments[i];
            if (expected == 'B' ? !(actual == 'B' || actual == 'c') :
                expected == 'q' ? !(actual == 'q' || actual == 'Q') : actual != expected) return NO;
        }
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
static id DY778LiveObject(id object, NSString *key) {
    id value = DY778Read(object,key); if (value) return value;
    if (!DY778LiveCanCall(object,key,"@","")) return nil;
    @try { return ((id (*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(key)); }
    @catch (__unused NSException *exception) { return nil; }
}
static void DY778LiveCallVoid(id object, NSString *selector) {
    if (DY778LiveCanCall(object, selector, "v", ""))
        ((void (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selector));
}
static BOOL DY778LiveCallBool(id object, NSString *selector) {
    if (!DY778LiveCanCall(object, selector, "Bc", "")) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(selector));
}
static NSString *DY778LiveRoomID(id object) {
    NSString *identifier = DY778LiveID(DY778LiveObject(object, @"roomID")) ?: DY778LiveID(DY778LiveObject(object, @"roomIdStr")) ?:
           DY778LiveID(DY778Read(object, @"roomId"));
    id model = DY778LiveObject(object, @"roomModel");
    if (!identifier && model != object) identifier = DY778LiveID(DY778Read(model,@"roomID")) ?:
        DY778LiveID(DY778Read(model,@"roomIdStr")) ?: DY778LiveID(DY778Read(model,@"roomId"));
    return identifier;
}
static NSString *DY778FragmentRoomID(id component) {
    return DY778LiveRoomID(DY778LiveObject(component, @"room")) ?: DY778LiveRoomID(DY778LiveObject(component, @"roomService")) ?:
           DY778LiveRoomID(DY778LiveObject(DY778LiveObject(component, @"store"), @"roomModel")) ?:
           DY778LiveRoomID(DY778LiveObject(DY778LiveObject(component, @"store"), @"currentLottery")) ?:
           DY778LiveRoomID(DY778LiveObject(component, @"roomModel")) ?:
           objc_getAssociatedObject(component, &DY778LuckyComponentRoomKey);
}
static BOOL DY778LiveBindCommentRoom(id object, NSString *roomID) {
    if (!object || !roomID.length || [objc_getAssociatedObject(object,&DY778LuckyComponentRetiredKey) boolValue]) return NO;
    NSString *room = DY778FragmentRoomID(object);
    NSString *account = objc_getAssociatedObject(object,&DY778LuckyComponentAccountKey);
    if ((room.length && ![room isEqual:roomID]) || (account && ![account isEqual:(DY778CurrentAccountID() ?: @"")])) return NO;
    objc_setAssociatedObject(object,&DY778LuckyComponentRoomKey,roomID,OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!account) DY778MarkLiveComponent(object);
    return YES;
}
static NSString *DY778LotteryID(id lottery) {
    return DY778LiveID(DY778Read(lottery, @"lotteryIdStr")) ?: DY778LiveID(DY778Read(lottery, @"lotteryId"));
}
static NSString *DY778LuckyConditionCaption(NSString *text) {
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([text hasPrefix:@"参与条件"]) text = [[text substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"：: \n"]];
    return text ?: @"";
}
static BOOL DY778LuckyContains(NSString *text, NSArray<NSString *> *words) {
    for (NSString *word in words) if ([text containsString:word]) return YES;
    return NO;
}
static long long DY778LuckyCaptionLevel(NSString *text) {
    static NSRegularExpression *pattern; static dispatch_once_t once;
    dispatch_once(&once, ^{ pattern = [NSRegularExpression regularExpressionWithPattern:@"(?:([0-9]+)\\s*级|(?:等级|级别|Lv\\.?)\\s*[:：]?\\s*([0-9]+))" options:NSRegularExpressionCaseInsensitive error:nil]; });
    NSTextCheckingResult *match = [pattern firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
    if (!match) return 0;
    for (NSUInteger i = 1; i < match.numberOfRanges; i++) if ([match rangeAtIndex:i].location != NSNotFound)
        return [[text substringWithRange:[match rangeAtIndex:i]] longLongValue];
    return 0;
}
static UIViewController *DY778LiveControllerForView(UIView *view) {
    if (![view isKindOfClass:UIView.class] || !view.window) return nil;
    for (UIResponder *responder = view; responder; responder = responder.nextResponder)
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
    return nil;
}
static UIView *DY778LiveVisibleView(id fragment) {
    id shortcut = DY778Read(fragment, @"shortTouchitem");
    NSArray *candidates = @[DY778Read(fragment, @"lotteryFloatingView") ?: NSNull.null,
        DY778Read(shortcut, @"view") ?: NSNull.null, DY778Read(shortcut, @"entranceView") ?: NSNull.null,
        DY778Read(shortcut, @"control") ?: NSNull.null];
    for (UIView *view in candidates) {
        if (![view isKindOfClass:UIView.class] || !view.window || view.hidden || view.alpha < 0.01) continue;
        BOOL hidden = NO; for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview)
            if (ancestor.hidden || ancestor.alpha < 0.01) { hidden = YES; break; }
        if (hidden) continue;
        CGRect rect = [view convertRect:view.bounds toView:view.window];
        if (!CGRectIsEmpty(CGRectIntersection(rect, view.window.bounds))) return view;
    }
    return nil;
}
static NSString *DY778LiveHostRoomID(id host) {
    return DY778LiveRoomID(DY778Read(host, @"roomModel")) ?:
        DY778LiveRoomID(DY778Read(DY778Read(host, @"roomConfig"), @"roomModel"));
}
static BOOL DY778LiveSameHierarchy(UIViewController *a, UIViewController *b) {
    if (!a || !b) return NO;
    for (UIViewController *controller = a; controller; controller = controller.parentViewController)
        if (controller == b) return YES;
    for (UIViewController *controller = b; controller; controller = controller.parentViewController)
        if (controller == a) return YES;
    return NO;
}
static double DY778LiveDisplayedSeconds(id value) {
    NSString *text = DY778LiveString(value);
    if (!text.length) return -1;
    static NSRegularExpression *clock, *seconds; static dispatch_once_t once;
    dispatch_once(&once, ^{
        clock = [NSRegularExpression regularExpressionWithPattern:@"(?<![0-9])(?:(\\d{1,2}):)?(\\d{1,2}):(\\d{2})(?![0-9])" options:0 error:nil];
        seconds = [NSRegularExpression regularExpressionWithPattern:@"(?<![0-9])(\\d{1,3})\\s*(?:秒|s)(?![A-Za-z])" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSTextCheckingResult *match = [clock firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
    if (match) {
        NSInteger hours = [match rangeAtIndex:1].location == NSNotFound ? 0 : [[text substringWithRange:[match rangeAtIndex:1]] integerValue];
        NSInteger minutes = [[text substringWithRange:[match rangeAtIndex:2]] integerValue];
        NSInteger second = [[text substringWithRange:[match rangeAtIndex:3]] integerValue];
        return minutes < 60 && second < 60 ? hours * 3600 + minutes * 60 + second : -1;
    }
    match = [seconds firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
    return match ? [[text substringWithRange:[match rangeAtIndex:1]] doubleValue] : -1;
}
static double DY778LiveFloatingSeconds(id view) {
    for (NSString *key in @[@"countLabel", @"descLabel", @"titleLabel"]) {
        double seconds = DY778LiveDisplayedSeconds(DY778Read(DY778Read(view, key), @"text"));
        if (seconds >= 0) return seconds;
    }
    return -1;
}
static double DY778LiveServerSeconds(id lottery) {
    return DY778LuckyServerRemaining([DY778Read(lottery, @"drawTime") doubleValue], [DY778Read(lottery, @"currentTime") doubleValue]);
}
static void DY778CaptureNativeClock(id floating, double raw) {
    id store = DY778Read(floating, @"store"); id lottery = DY778Read(store, @"currentLottery");
    NSString *identifier = DY778LotteryID(lottery); if (!identifier.length) return;
    double display = DY778LiveFloatingSeconds(floating);
    double reference = display >= 0 ? display : DY778LiveServerSeconds(lottery);
    BOOL hasStoreClock = DY778LiveCanCall(store, @"getCurrentLotteryRemainTime", "qQ", "");
    double liveRaw = hasStoreClock ? ((long long (*)(id,SEL))objc_msgSend)(store,NSSelectorFromString(@"getCurrentLotteryRemainTime")) : raw;
    double seconds = display >= 0 ? display : hasStoreClock ? DY778LuckyStoreDurationSeconds(liveRaw) : DY778LuckyDurationSeconds(raw,reference);
    if (seconds < 0 || seconds > 86400) return;
    objc_setAssociatedObject(store, &DY778LuckyClockSampleKey, @{@"lottery":identifier,@"seconds":@(seconds),@"at":@(CACurrentMediaTime())}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL DY778LiveCommentCanSend(id candidate) {
    return DY778LiveCanCall(candidate, @"sendComment:commentContext:completion:", "v", "@@@") ||
        DY778LiveCanCall(candidate, @"sendComment:enterSource:requestSource:trackParams:completion:", "v", "@q@@@") ||
        DY778LiveCanCall(candidate, @"sendCommentWithCommentContext:completion:", "v", "@@");
}
static id DY778LiveRoomDI(id attacher) {
    id context = DY778LiveObject(attacher,@"attachingDIContext"); if (!context) return nil;
    Class cls = NSClassFromString(@"IESLiveDIManager");
    if (!DY778LiveCanCall(cls,@"shared","@","")) return nil;
    id manager = ((id (*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"shared"));
    if (!DY778LiveCanCall(manager,@"aDIForContext:","@","@")) return nil;
    @try { return ((id (*)(id,SEL,id))objc_msgSend)(manager,NSSelectorFromString(@"aDIForContext:"),context); }
    @catch (__unused NSException *exception) { return nil; }
}
static BOOL DY778LiveDIOwnsRoom(id di, NSString *roomID) {
    id room = DY778LiveObject(di,@"roomService") ?: DY778LiveObject(di,@"getRoomService");
    return roomID.length && [DY778LiveRoomID(room) isEqual:roomID];
}
static id DY778LiveCommentFromAttacher(id attacher) {
    Class cls = NSClassFromString(@"IESLiveDIManager");
    Protocol *protocol = NSProtocolFromString(@"IESLiveCommentService");
    if (!attacher || !protocol || !DY778LiveCanCall(cls,@"objectforProtocol:withContextAtttacher:","@","@@")) return nil;
    @try { return ((id (*)(id,SEL,id,id))objc_msgSend)(cls,NSSelectorFromString(@"objectforProtocol:withContextAtttacher:"),protocol,attacher); }
    @catch (__unused NSException *exception) { return nil; }
}
static BOOL DY778LiveHasEditingDraft(UIView *view, NSUInteger *budget) {
    if (!view || !*budget || view.hidden) return NO; (*budget)--;
    if ([view isKindOfClass:UITextView.class] && [(UITextView *)view isFirstResponder] && [(UITextView *)view text].length) return YES;
    if ([view isKindOfClass:UITextField.class] && [(UITextField *)view isFirstResponder] && [(UITextField *)view text].length) return YES;
    for (UIView *child in view.subviews) if (DY778LiveHasEditingDraft(child,budget)) return YES;
    return NO;
}
static id DY778LiveDICommentService(id di) {
    Protocol *protocol = NSProtocolFromString(@"IESLiveCommentService"); if (!protocol || !di) return nil;
    for (NSString *selector in @[@"cacheObjectWithProtocol:", @"objectWithProtocol:"]) {
        if (!DY778LiveCanCall(di, selector, "@", "@")) continue;
        @try {
            id service = ((id (*)(id,SEL,id))objc_msgSend)(di, NSSelectorFromString(selector), protocol);
            if (service) return service;
        } @catch (__unused NSException *exception) {}
    }
    return nil;
}
static UIView *DY778LuckyPanelView(id panel) {
    id kit = DY778LiveObject(panel, @"kitView");
    if ([kit isKindOfClass:UIView.class]) return kit;
    id view = DY778LiveObject(kit, @"view");
    if ([view isKindOfClass:UIView.class]) return view;
    if ([panel isKindOfClass:UIView.class]) return panel;
    if ([panel isKindOfClass:UIViewController.class]) return [(UIViewController *)panel viewIfLoaded];
    view = DY778LiveObject(panel, @"view");
    return [view isKindOfClass:UIView.class] ? view : nil;
}
static void DY778LuckyCollectWebViews(UIView *view, NSUInteger depth, NSUInteger *budget, NSMutableArray *result) {
    if (!view || depth > 24 || !*budget || view.hidden || view.alpha < .01) return;
    (*budget)--;
    if ([view isKindOfClass:WKWebView.class]) { if (![result containsObject:view]) [result addObject:view]; return; }
    for (UIView *child in view.subviews.reverseObjectEnumerator) DY778LuckyCollectWebViews(child, depth + 1, budget, result);
}
static BOOL DY778LuckyWebVisible(WKWebView *web) {
    if (!web.window || CGRectIsEmpty(web.bounds)) return NO;
    for (UIView *view = web; view; view = view.superview) if (view.hidden || view.alpha < .01) return NO;
    return YES;
}
static NSString *DY778LuckyButtonText(id value) {
    NSString *text = [value isKindOfClass:NSAttributedString.class] ? [value string] : DY778LiveString(value);
    return [[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
}
static BOOL DY778LuckyVisibleInPanel(UIView *view, UIView *panel) {
    if (![view isKindOfClass:UIView.class] || !view.window || ![view isDescendantOfView:panel] || CGRectIsEmpty(view.bounds)) return NO;
    for (UIView *parent = view; parent; parent = parent.superview) {
        if (parent.hidden || parent.alpha < 0.05) return NO;
        if (parent == panel) break;
    }
    CGRect rect = [view convertRect:view.bounds toView:panel];
    CGRect visible = CGRectIntersection(rect,panel.bounds);
    return !CGRectIsNull(visible) && visible.size.width >= 8 && visible.size.height >= 8;
}
static NSString *DY778LuckyViewText(UIView *view) {
    if ([view isKindOfClass:UIButton.class]) return [(UIButton *)view currentTitle] ?: [(UIButton *)view currentAttributedTitle].string ?: view.accessibilityLabel;
    if ([view isKindOfClass:UILabel.class]) return [(UILabel *)view text];
    return view.accessibilityLabel;
}
static NSString *DY778LuckyLynxText(id ui) {
    id text = DY778LiveObject(ui,@"accessibilityText");
    if (![DY778LuckyButtonText(text) length]) text = DY778LiveObject(ui,@"lynxAccessibilityLabel");
    if (![DY778LuckyButtonText(text) length]) {
        id view = DY778LiveObject(ui,@"view"); if ([view isKindOfClass:UIView.class]) text = DY778LuckyViewText(view);
    }
    return DY778LuckyButtonText(text);
}
static NSString *DY778LuckyLynxEvent(id ui) {
    id events = DY778LiveObject(ui,@"eventSet"); if (![events isKindOfClass:NSDictionary.class]) return nil;
    for (NSString *name in @[@"tap",@"click"]) if (events[name]) return name;
    return nil;
}
static BOOL DY778LuckyLynxEnabled(id ui) {
    id props = DY778LiveObject(ui,@"lynxProps");
    if ([props isKindOfClass:NSDictionary.class]) {
        for (NSString *key in @[@"disabled",@"aria-disabled",@"ariaDisabled"]) {
            id value = props[key];
            if ([value isKindOfClass:NSNumber.class] && [value boolValue]) return NO;
            if ([value isKindOfClass:NSString.class] && [@[@"true",@"1",@"disabled"] containsObject:[value lowercaseString]]) return NO;
        }
        NSString *status = DY778LiveString(props[@"accessibility-status"]);
        if ([status isEqualToString:@"disabled"]) return NO;
    }
    NSString *status = DY778LiveString(DY778LiveObject(ui,@"lynxAccessibilityStatus"));
    if ([status isEqualToString:@"disabled"]) return NO;
    UIView *view = DY778LiveObject(ui,@"view");
    return ![view isKindOfClass:UIControl.class] || [(UIControl *)view isEnabled];
}
@interface DY778LuckyJoinTarget : NSObject
@property(nonatomic, strong) UIControl *control;
@property(nonatomic, strong) id lynxUI;
@property(nonatomic, strong) UIView *view;
@property(nonatomic, copy) NSString *eventName;
@property(nonatomic) UIControlEvents controlEvent;
@property(nonatomic) BOOL enabled;
@end
@implementation DY778LuckyJoinTarget
@end
static BOOL DY778LuckyPaymentText(NSString *text) {
    if (!text.length) return NO;
    static NSRegularExpression *pattern; static dispatch_once_t once;
    dispatch_once(&once, ^{ pattern = [NSRegularExpression regularExpressionWithPattern:@"(?:支付|扣除|消耗|花费)\\s*[0-9一二三四五六七八九十]+\\s*(?:钻石|抖币|元)" options:0 error:nil]; });
    return [pattern firstMatchInString:text options:0 range:NSMakeRange(0,text.length)] != nil;
}
static NSArray<DY778LuckyJoinTarget *> *DY778LuckyNativeTargets(UIView *panel, BOOL *pageSubmitted, BOOL *paymentRequired) {
    NSMutableArray *targets = [NSMutableArray new], *views = [NSMutableArray arrayWithObject:panel];
    NSMutableArray *lynxViews = [NSMutableArray new]; NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    Class lynxClass = NSClassFromString(@"LynxView"); NSUInteger count = 0;
    while (views.count && count++ < 650) {
        UIView *view = views.lastObject; [views removeLastObject];
        if (!DY778LuckyVisibleInPanel(view,panel)) continue;
        if (lynxClass && [view isKindOfClass:lynxClass]) { [lynxViews addObject:view]; continue; }
        [views addObjectsFromArray:view.subviews];
        NSString *text = DY778LuckyButtonText(DY778LuckyViewText(view));
        if (DY778LuckyPaymentText(text)) *paymentRequired = YES;
        DY778LuckyButtonKind kind = DY778LuckyClassifyButton(text.UTF8String);
        if (kind == DY778LuckyButtonSubmitted) *pageSubmitted = YES;
        if (kind != DY778LuckyButtonJoin) continue;
        UIView *ancestor = view;
        for (NSUInteger depth = 0; ancestor && ancestor != panel && depth < 4; depth++, ancestor = ancestor.superview) {
            if (![ancestor isKindOfClass:UIControl.class]) continue;
            UIControl *control = (UIControl *)ancestor; UIControlEvents events = control.allControlEvents;
            UIControlEvents action = events & UIControlEventTouchUpInside ? UIControlEventTouchUpInside : events & UIControlEventPrimaryActionTriggered ? UIControlEventPrimaryActionTriggered : 0;
            if (!action || [seen containsObject:control]) break;
            [seen addObject:control]; DY778LuckyJoinTarget *target = [DY778LuckyJoinTarget new]; target.control = control;
            target.view = control; target.controlEvent = action; target.enabled = control.enabled && control.userInteractionEnabled;
            [targets addObject:target]; break;
        }
    }
    for (UIView *lynx in lynxViews) {
        id owner = DY778LiveObject(DY778LiveObject(lynx,@"templateRender"),@"uiOwner");
        id root = DY778LiveObject(owner,@"rootUI") ?: DY778LiveObject(DY778LiveObject(DY778LiveObject(lynx,@"rendererContext"),@"uiContext"),@"rootUI");
        if (!root) continue;
        NSMutableArray *pending = [NSMutableArray arrayWithObject:root]; count = 0;
        while (pending.count && count++ < 1000) {
            id ui = pending.lastObject; [pending removeLastObject];
            id children = DY778LiveObject(ui,@"children"); if ([children isKindOfClass:NSArray.class]) [pending addObjectsFromArray:children];
            NSString *text = DY778LuckyLynxText(ui);
            if (DY778LuckyPaymentText(text) && DY778LuckyVisibleInPanel(DY778LiveObject(ui,@"view"),panel)) *paymentRequired = YES;
            DY778LuckyButtonKind kind = DY778LuckyClassifyButton(text.UTF8String);
            if (kind == DY778LuckyButtonSubmitted && DY778LuckyVisibleInPanel(DY778LiveObject(ui,@"view"),panel)) *pageSubmitted = YES;
            if (kind != DY778LuckyButtonJoin) continue;
            id candidate = ui;
            for (NSUInteger depth = 0; candidate && candidate != root && depth < 5; depth++, candidate = DY778LiveObject(candidate,@"parent")) {
                NSString *event = DY778LuckyLynxEvent(candidate); if (!event.length) continue;
                UIView *view = DY778LiveObject(candidate,@"view");
                if (!DY778LuckyVisibleInPanel(view,panel) || [seen containsObject:candidate]) break;
                [seen addObject:candidate]; DY778LuckyJoinTarget *target = [DY778LuckyJoinTarget new];
                target.lynxUI = candidate; target.view = view; target.eventName = event; target.enabled = DY778LuckyLynxEnabled(candidate);
                [targets addObject:target]; break;
            }
        }
    }
    return targets;
}

static BOOL DY778LuckyActivateTarget(DY778LuckyJoinTarget *target, UIView *panel, dispatch_block_t submitted) {
    if (!DY778LuckyVisibleInPanel(target.view,panel) || !target.enabled) return NO;
    if (target.control) {
        if (!target.control.enabled || !target.control.userInteractionEnabled) return NO;
        submitted(); [target.control sendActionsForControlEvents:target.controlEvent]; return YES;
    }
    id ui = target.lynxUI, context = DY778LiveObject(ui,@"context");
    id emitter = DY778LiveObject(context,@"eventEmitter") ?: DY778LiveObject(DY778LiveObject(context,@"eventHandler"),@"eventEmitter");
    Class eventClass = NSClassFromString(@"LynxTouchEvent");
    if (!DY778LuckyLynxEnabled(ui) || ![DY778LuckyLynxEvent(ui) isEqual:target.eventName] ||
        !DY778LiveSignature(eventClass,NSSelectorFromString(@"initWithName:targetTag:"),"@","@q") ||
        !DY778LiveCanCall(ui,@"signature","qQ","") || !DY778LiveCanCall(emitter,@"dispatchTouchEvent:","Bc","@")) return NO;
    long long sign = ((long long (*)(id,SEL))objc_msgSend)(ui,NSSelectorFromString(@"signature"));
    id event = [(id<DY778LuckyTouchInitializing>)[eventClass alloc] initWithName:target.eventName targetTag:sign];
    if (!event || !DY778Write(event,@"eventTarget",ui) || !DY778Write(event,@"timestamp",@(NSDate.date.timeIntervalSince1970 * 1000))) return NO;
    submitted();
    ((BOOL (*)(id,SEL,id))objc_msgSend)(emitter,NSSelectorFromString(@"dispatchTouchEvent:"),event);
    return YES;
}

// DY778_JS_BEGIN
static NSString *const DY778LuckyJoinFunction =
@"function(spec){"
@"'use strict';"
@"if(Date.now()>spec.deadline||document.hidden)return 'inactive';"
@"if(window.__cgnLuckyCancelled&&window.__cgnLuckyCancelled[spec.token])return 'cancelled';"
@"var root=document.querySelector('.lottery-join-panel-btn');if(!root)return 'page-missing';"
@"var address=String(location.href),url;try{url=new URL(address);}catch(e){}"
@"function get(names){if(!url)return '';var hash=url.hash||'';var h=new URLSearchParams(hash.indexOf('?')>=0?hash.slice(hash.indexOf('?')+1):hash.replace(/^#/,''));for(var i=0;i<names.length;i++){var v=url.searchParams.get(names[i])||h.get(names[i]);if(v)return v;}return '';}"
@"var room=get(['room_id','roomId','room_id_str'])||root.getAttribute('data-room-id');"
@"var lottery=get(['lottery_id','lotteryId','lottery_id_str'])||root.getAttribute('data-lottery-id');"
@"if((room&&String(room)!==spec.room)||(lottery&&String(lottery)!==spec.lottery))return 'context';"
@"if((!room||!lottery)&&!spec.ownerBound&&!spec.requestBound)return 'context';"
@"function label(b){return (b.textContent||'').replace(/\\s+/g,'');}"
@"function join(t){return /^(免费)?(立即|一键|点击)?(参与|报名)(抽奖|福袋)?$/.test(t);}"
@"function done(t){return /^(已参与|参与成功|已参与福袋|等待开奖|报名成功)$/.test(t);}"
@"var buttons=Array.prototype.slice.call(root.querySelectorAll('.lottery-button')).filter(function(b){var s=getComputedStyle(b);return b.getClientRects().length&&s.display!=='none'&&s.visibility!=='hidden'&&s.opacity!=='0';});"
@"var matches=buttons.filter(function(b){return join(label(b));});"
@"if(!matches.length){if(buttons.some(function(b){return done(label(b));}))return 'already';return buttons.length?'manual':'waiting';}"
@"if(matches.length!==1)return 'waiting';var btn=matches[0];"
@"if(/(?:支付|扣除|消耗|花费)\\s*[0-9一二三四五六七八九十]+\\s*(?:钻石|抖币|元)/.test(root.textContent||''))return 'manual';"
@"if(spec.hasPhrase&&!spec.phraseSubmitted)return 'waiting';"
@"if(btn.disabled||btn.getAttribute('aria-disabled')==='true')return 'waiting';"
@"var seen=window.__cgnLuckyClicked||(window.__cgnLuckyClicked=Object.create(null));var state=seen[spec.token];"
@"if(state&&(state===true||state.count>=3||Date.now()-state.at<2500))return 'submitted';"
@"seen[spec.token]={count:state?state.count+1:1,at:Date.now()};"
@"try{btn.click();if(!document.hidden&&Date.now()<=spec.deadline&&String(location.href)===address&&!(window.__cgnLuckyCancelled&&window.__cgnLuckyCancelled[spec.token]))btn.dispatchEvent(new Event('touchend',{bubbles:true}));return 'clicked';}catch(e){return 'click-error';}"
@"}";
// DY778_JS_END

@class DY778LuckyCoordinator, DY778LuckyPanelController;
@interface DY778LuckyCard : UIControl
@property(nonatomic, weak) DY778LuckyCoordinator *coordinator;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *detailLabel;
@property(nonatomic, strong) UIImageView *symbol;
- (void)refresh;
@end

typedef NS_ENUM(NSUInteger, DY778LuckyPhase) {
    DY778LuckyIdle, DY778LuckyAvailable, DY778LuckyScheduled, DY778LuckyOpening,
    DY778LuckySubmitted, DY778LuckyJoined, DY778LuckyManual, DY778LuckyEnded
};
@interface DY778LuckyQuietHostController : UIViewController
@end
@implementation DY778LuckyQuietHostController
- (BOOL)shouldAutomaticallyForwardAppearanceMethods { return NO; }
- (void)loadView {
    UIView *view = [UIView new];
    view.backgroundColor = UIColor.clearColor;
    view.userInteractionEnabled = NO; view.accessibilityElementsHidden = YES; view.clipsToBounds = YES;
    CALayer *mask = [CALayer layer]; mask.backgroundColor = UIColor.clearColor.CGColor;
    view.layer.mask = mask;
    self.view = view;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.view.layer.mask.frame = self.view.bounds;
    [CATransaction commit];
}
@end
@interface DY778LuckyCoordinator : NSObject
@property(nonatomic, weak) UIViewController *host;
@property(nonatomic, weak) id fragment;
@property(nonatomic, weak) id comment;
@property(nonatomic, weak) id commentService;
@property(nonatomic, strong) NSMapTable<NSString *, id> *commentServices;
@property(nonatomic, strong) NSHashTable *seenComments;
@property(nonatomic, weak) UIView *anchorView;
@property(nonatomic, strong) NSHashTable *seenFragments;
@property(nonatomic, strong) NSMutableSet *toastKeys;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *records;
@property(nonatomic, copy) NSArray<NSString *> *conditionLines;
@property(nonatomic, copy) NSDictionary<NSString *, NSNumber *> *conditionHighlights;
@property(nonatomic, copy) NSString *eligibilityKey;
@property(nonatomic, strong) id userCondition;
@property(nonatomic) NSTimeInterval eligibilityCheckedAt;
@property(nonatomic) BOOL eligibilityPending;
@property(nonatomic) BOOL requiresFans;
@property(nonatomic) BOOL fanEligibilityKnown;
@property(nonatomic) BOOL eligibilityBlocked;
@property(nonatomic) DY778LuckyEligibilityNotice eligibilityNotice;
@property(nonatomic) NSUInteger eligibilityGeneration;
@property(nonatomic) NSUInteger eligibilitySession;
@property(nonatomic, strong) UIViewController *quietController;
@property(nonatomic, strong) DY778LuckyQuietHostController *quietParent;
@property(nonatomic, strong) id quietPanel;
@property(nonatomic, strong) UIView *quietContainer;
@property(nonatomic, weak) id quietFragment;
@property(nonatomic, copy) NSString *quietToken;
@property(nonatomic) BOOL quietCreating;
@property(nonatomic, copy) NSString *prizeTitle;
@property(nonatomic, copy) NSString *roomTitle;
@property(nonatomic, copy) NSString *ownerAvatarURL;
@property(nonatomic, copy) NSString *ownerID;
@property(nonatomic, copy) NSString *prizeQuantity;
@property(nonatomic, copy) NSString *explicitPhraseKey;
@property(nonatomic) NSUInteger explicitPhraseSession;
@property(nonatomic) BOOL discovering;
@property(nonatomic) BOOL needsManualConditions;
@property(nonatomic) BOOL pendingManual;
@property(nonatomic) NSTimeInterval lastToastTime;
@property(nonatomic, strong) NSMapTable<NSString *, id> *fragments;
@property(nonatomic, strong) NSMapTable<NSString *, id> *comments;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, copy) NSString *accountID;
@property(nonatomic, copy) NSString *lotteryID;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, copy) NSString *detail;
@property(nonatomic, copy) NSString *phrase;
@property(nonatomic, copy) NSString *restriction;
@property(nonatomic, copy) NSString *announcedKey;
@property(nonatomic, copy) NSString *attemptedKey;
@property(nonatomic) NSUInteger attemptedSession;
@property(nonatomic, weak) WKWebView *activeWebView;
@property(nonatomic, weak) WKWebView *evaluatingWebView;
@property(nonatomic, strong) NSHashTable<WKWebView *> *webCandidates;
@property(nonatomic, weak) UIWindowScene *requestScene;
@property(nonatomic) NSUInteger probeIndex;
@property(nonatomic, copy) NSString *lastProbeStatus;
@property(nonatomic, copy) NSString *activeWebToken;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) DY778LuckyCard *card;
@property(nonatomic, weak) DY778LuckyPanelController *panel;
@property(nonatomic, strong) NSMutableDictionary *history;
@property(nonatomic) DY778LuckyPhase phase;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger session;
@property(nonatomic) NSUInteger pollGeneration;
@property(nonatomic) BOOL openedPanelByAssistant;
@property(nonatomic, weak) id openedPanel;
@property(nonatomic) NSTimeInterval presentationDeadline;
@property(nonatomic) BOOL roomInactive;
@property(nonatomic) NSUInteger commentRetries;
@property(nonatomic) NSUInteger confirmationRefreshes;
@property(nonatomic) NSTimeInterval confirmationRefreshedAt;
@property(nonatomic) NSTimeInterval deadline;
@property(nonatomic) NSTimeInterval scheduledAt;
@property(nonatomic) NSTimeInterval openedAt;
@property(nonatomic) BOOL paused;
@property(nonatomic) BOOL backgrounded;
@property(nonatomic) BOOL evaluating;
@property(nonatomic) BOOL joinActionSent;
@property(nonatomic) BOOL openingAuthorized;
+ (instancetype)shared;
- (void)enterHost:(UIViewController *)host;
- (void)enterHost:(UIViewController *)host roomID:(NSString *)roomID;
- (void)discoverVisibleRoom;
- (void)observeCommentService:(id)service;
- (void)observeCommentFromLoader:(id)loader;
- (id)resolveCommentSender;
- (void)synchronizeCountdown;
- (void)nativeClockUpdated:(id)store;
- (BOOL)phraseAuthorized;
- (void)observeComponent:(id)component comment:(BOOL)isComment service:(BOOL)service;
- (void)announce:(NSString *)stage message:(NSString *)message;
- (void)recordStage:(NSString *)stage message:(NSString *)message;
- (void)showDiscoveryPrompt;
- (BOOL)attempted;
- (NSString *)conditionSummary;
- (void)leaveHost:(UIViewController *)host;
- (void)suspendHost:(UIViewController *)host;
- (BOOL)ownsVisiblePanel;
- (void)considerAutoJoin;
- (void)bindFragment:(id)fragment comment:(BOOL)isComment;
- (void)unbindFragment:(id)fragment comment:(BOOL)isComment;
- (void)lotteryChanged:(id)fragment;
- (void)lotteryEnded:(id)fragment;
- (void)participationChanged:(id)fragment;
- (void)webReady:(WKWebView *)web;
- (void)webAppeared:(WKWebView *)web;
- (BOOL)requestValid;
- (void)recordProbe:(NSString *)status;
- (void)closeOwnedOfficialPanel;
- (void)resetEligibility;
- (void)refreshFanEligibility;
- (BOOL)eligibilityAllowsJoin;
- (BOOL)quietRequestValid;
- (BOOL)attachQuietController:(UIViewController *)controller router:(id)router schema:(id)schema context:(id)context completion:(id)completion;
- (void)captureQuietPanel:(id)panel;
- (void)removeQuietPanel;
- (void)userOpenedLottery:(id)fragment;
- (void)preferencesChanged;
- (void)tick;
- (void)emit;
- (void)cancelPending;
- (void)joinRequested;
- (void)openOfficial;
- (void)togglePause;
- (BOOL)contextValid;
- (NSString *)countdown;
- (NSString *)key;
- (void)presentFrom:(UIViewController *)source;
- (void)presentFrom:(UIViewController *)source prompt:(BOOL)prompt;
@end

@interface DY778LuckyPanelController : UIViewController
@property(nonatomic, weak) DY778LuckyCoordinator *coordinator;
@property(nonatomic) NSUInteger boundSession;
@property(nonatomic) BOOL liveBound;
@property(nonatomic) BOOL discoveryPrompt;
@property(nonatomic, strong) UIButton *laterButton;
@property(nonatomic, strong) UIButton *muteButton;
@property(nonatomic, strong) UILabel *countdownLabel;
@property(nonatomic, strong) UILabel *detailLabel;
@property(nonatomic, strong) UILabel *modeLabel;
@property(nonatomic, strong) UILabel *prizeLabel;
@property(nonatomic, strong) UILabel *quantityLabel;
@property(nonatomic, strong) UILabel *hostLabel;
@property(nonatomic, strong) UIImageView *avatarView;
@property(nonatomic, strong) UIView *centerCard;
@property(nonatomic, strong) UIButton *joinButton;
- (void)refresh;
@end
static UIColor *DY778LuckyLiveAccent(void) {
    return [DY778Accent() resolvedColorWithTraitCollection:[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]];
}
static UIColor *DY778LuckyButtonTitleColor(void) {
    UIColor *accent = DY778Accent();
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        CGFloat red = 0, green = 0, blue = 0, alpha = 1;
        [[accent resolvedColorWithTraitCollection:traits] getRed:&red green:&green blue:&blue alpha:&alpha];
        double r = red <= 0.04045 ? red / 12.92 : pow((red + 0.055) / 1.055, 2.4);
        double g = green <= 0.04045 ? green / 12.92 : pow((green + 0.055) / 1.055, 2.4);
        double b = blue <= 0.04045 ? blue / 12.92 : pow((blue + 0.055) / 1.055, 2.4);
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.179 ? UIColor.blackColor : UIColor.whiteColor;
    }];
}
@implementation DY778LuckyCard
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.07 alpha:0.94];
        self.layer.cornerRadius = 20;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.18; self.layer.shadowRadius = 9; self.layer.shadowOffset = CGSizeMake(0, 4);
        self.symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"gift.fill"]];
        self.symbol.tintColor = DY778LuckyLiveAccent(); self.symbol.contentMode = UIViewContentModeScaleAspectFit;
        self.nameLabel = [UILabel new]; self.nameLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]; self.nameLabel.textColor = UIColor.whiteColor;
        self.detailLabel = [UILabel new]; self.detailLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
        self.detailLabel.textColor = [UIColor colorWithWhite:0.86 alpha:1];
        self.nameLabel.adjustsFontSizeToFitWidth = YES; self.nameLabel.minimumScaleFactor = 0.85;
        self.detailLabel.adjustsFontSizeToFitWidth = YES; self.detailLabel.minimumScaleFactor = 0.85;
        for (UIView *view in @[self.symbol, self.nameLabel, self.detailLabel]) { view.userInteractionEnabled = NO; [self addSubview:view]; }
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)]];
        [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]];
        self.isAccessibilityElement = YES; self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityHint = @"点按打开福袋，长按展开或收起，也可拖动位置";
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    BOOL compact = DY778Bool(@"lucky.compact");
    self.symbol.frame = compact ? CGRectMake((w-19)/2,6,19,19) : CGRectMake(10,(h-20)/2,20,20);
    self.nameLabel.hidden = YES;
    self.detailLabel.frame = compact ? CGRectMake(2,28,w-4,13) : CGRectMake(37,(h-18)/2,w-43,18);
    self.detailLabel.textAlignment = compact ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    self.detailLabel.font = [UIFont monospacedDigitSystemFontOfSize:compact ? 9 : 12 weight:UIFontWeightSemibold];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:20].CGPath;
}
- (void)refresh {
    DY778LuckyCoordinator *c = self.coordinator;
    self.symbol.tintColor = DY778LuckyLiveAccent();
    NSInteger seconds = MAX(0,(NSInteger)ceil(c.deadline-CACurrentMediaTime()));
    self.detailLabel.text = c.paused ? @"已暂停" : c.lotteryID.length && c.deadline > 0 && c.phase != DY778LuckyEnded ?
        [NSString stringWithFormat:@"%02ld:%02ld",(long)(seconds/60),(long)(seconds%60)] : @"福袋";
    self.accessibilityLabel = [NSString stringWithFormat:@"DY778福袋，%@，%@", c.status ?: @"等待福袋", [c countdown]];
}
- (void)held:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [DY778Preferences() setBool:!DY778Bool(@"lucky.compact") forKey:@"lucky.compact"];
    [self.coordinator emit]; [self setNeedsLayout];
}
- (void)tapped { [self.coordinator presentFrom:self.coordinator.host]; }
- (void)panned:(UIPanGestureRecognizer *)gesture {
    UIView *parent = self.superview; if (!parent) return;
    CGPoint delta = [gesture translationInView:parent];
    CGRect available = UIEdgeInsetsInsetRect(parent.bounds, parent.safeAreaInsets);
    available = CGRectInset(available, 10, 10);
    CGRect frame = CGRectOffset(self.frame, delta.x, delta.y);
    frame.origin.x = fmax(CGRectGetMinX(available), fmin(frame.origin.x, CGRectGetMaxX(available) - frame.size.width));
    frame.origin.y = fmax(CGRectGetMinY(available), fmin(frame.origin.y, CGRectGetMaxY(available) - frame.size.height));
    self.frame = frame; [gesture setTranslation:CGPointZero inView:parent];
    if (gesture.state == UIGestureRecognizerStateEnded) {
        frame.origin.x = CGRectGetMidX(frame) < CGRectGetMidX(available) ? CGRectGetMinX(available) : CGRectGetMaxX(available)-frame.size.width;
        [UIView animateWithDuration:0.18 animations:^{ self.frame = frame; }];
        // Persist placement without a settings-change notification that could cancel a running task.
        [DY778Preferences() setDouble:frame.origin.x / fmax(1, parent.bounds.size.width) forKey:@"lucky.cardX"];
        [DY778Preferences() setDouble:frame.origin.y / fmax(1, parent.bounds.size.height) forKey:@"lucky.cardY"];
    }
}
@end

static UILabel *DY778LuckyLabel(UIFontTextStyle style, UIColor *color) {
    UILabel *label = [UILabel new]; label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES; label.textColor = color; label.numberOfLines = 0;
    return label;
}
static UIButton *DY778LuckyButton(NSString *title, BOOL filled, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal]; button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold] maximumPointSize:24];
    button.titleLabel.adjustsFontForContentSizeCategory = YES; button.titleLabel.numberOfLines = 0;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(14, 14, 14, 14);
    button.layer.cornerRadius = 16; button.layer.cornerCurve = kCACornerCurveContinuous;
    button.backgroundColor = filled ? DY778Accent() : DY778CardBackground();
    [button setTitleColor:filled ? DY778LuckyButtonTitleColor() : UIColor.labelColor forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;
    return button;
}
static UIColor *DY778LuckyTint(UIColor *color) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return [[color resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:traits.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.18 : 0.10];
    }];
}
static UIView *DY778LuckyInfoBlock(UILabel *label, NSString *symbol, UIColor *color) {
    UIView *block = [UIView new]; block.backgroundColor = DY778LuckyTint(color);
    block.layer.cornerRadius = 16; block.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = color; icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO; label.translatesAutoresizingMaskIntoConstraints = NO;
    [block addSubview:icon]; [block addSubview:label];
    [NSLayoutConstraint activateConstraints:@[[icon.widthAnchor constraintEqualToConstant:22], [icon.heightAnchor constraintEqualToConstant:24],
        [icon.leadingAnchor constraintEqualToAnchor:block.leadingAnchor constant:14], [icon.topAnchor constraintEqualToAnchor:block.topAnchor constant:15],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:11], [label.trailingAnchor constraintEqualToAnchor:block.trailingAnchor constant:-15],
        [label.topAnchor constraintEqualToAnchor:block.topAnchor constant:14], [label.bottomAnchor constraintEqualToAnchor:block.bottomAnchor constant:-14],
        [block.heightAnchor constraintGreaterThanOrEqualToConstant:52]]];
    return block;
}
@implementation DY778LuckyPanelController
- (void)viewDidLoad {
    [super viewDidLoad]; self.overrideUserInterfaceStyle = DY778InterfaceStyle();
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42]; self.view.accessibilityViewIsModal = YES;
    UIView *card = [UIView new]; self.centerCard = card; card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = DY778CardBackground(); card.layer.cornerRadius = 24; card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.shadowColor = UIColor.blackColor.CGColor; card.layer.shadowOpacity = 0.2; card.layer.shadowRadius = 24;
    card.layer.shadowOffset = CGSizeMake(0,10); [self.view addSubview:card];
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = NO; scroll.showsVerticalScrollIndicator = YES; [card addSubview:scroll];
    UIStackView *body = [UIStackView new]; body.axis = UILayoutConstraintAxisVertical; body.spacing = 8;
    body.translatesAutoresizingMaskIntoConstraints = NO; [scroll addSubview:body];
    UIView *avatarRow = [UIView new]; self.avatarView = [UIImageView new]; self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarView.backgroundColor = DY778LuckyTint(DY778Accent()); self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarView.clipsToBounds = YES; self.avatarView.layer.cornerRadius = 28;
    self.avatarView.isAccessibilityElement = NO; [avatarRow addSubview:self.avatarView]; [body addArrangedSubview:avatarRow];
    [NSLayoutConstraint activateConstraints:@[[avatarRow.heightAnchor constraintEqualToConstant:56],
        [self.avatarView.widthAnchor constraintEqualToConstant:56], [self.avatarView.heightAnchor constraintEqualToConstant:56],
        [self.avatarView.centerXAnchor constraintEqualToAnchor:avatarRow.centerXAnchor], [self.avatarView.topAnchor constraintEqualToAnchor:avatarRow.topAnchor]]];
    self.hostLabel = DY778LuckyLabel(UIFontTextStyleSubheadline,UIColor.labelColor); self.hostLabel.textAlignment = NSTextAlignmentCenter;
    self.hostLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] maximumPointSize:20];
    [body addArrangedSubview:self.hostLabel]; [body setCustomSpacing:12 afterView:self.hostLabel];
    self.prizeLabel = DY778LuckyLabel(UIFontTextStyleHeadline,UIColor.labelColor); self.prizeLabel.textAlignment = NSTextAlignmentCenter;
    self.prizeLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[UIFont systemFontOfSize:19 weight:UIFontWeightSemibold] maximumPointSize:25];
    [body addArrangedSubview:self.prizeLabel];
    self.quantityLabel = DY778LuckyLabel(UIFontTextStyleSubheadline,UIColor.systemOrangeColor); self.quantityLabel.textAlignment = NSTextAlignmentCenter;
    [body addArrangedSubview:self.quantityLabel];
    self.countdownLabel = DY778LuckyLabel(UIFontTextStyleHeadline,DY778Accent()); self.countdownLabel.textAlignment = NSTextAlignmentCenter;
    self.countdownLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[UIFont monospacedDigitSystemFontOfSize:21 weight:UIFontWeightSemibold] maximumPointSize:28];
    [body addArrangedSubview:self.countdownLabel]; [body setCustomSpacing:12 afterView:self.countdownLabel];
    self.detailLabel = DY778LuckyLabel(UIFontTextStyleSubheadline,UIColor.labelColor);
    self.detailLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[UIFont systemFontOfSize:14] maximumPointSize:21];
    UILabel *conditionHeading = DY778LuckyLabel(UIFontTextStyleCaption1,UIColor.secondaryLabelColor);
    conditionHeading.text = @"参与条件"; conditionHeading.accessibilityTraits |= UIAccessibilityTraitHeader;
    [body addArrangedSubview:conditionHeading];
    [body addArrangedSubview:DY778LuckyInfoBlock(self.detailLabel,@"text.bubble",UIColor.systemBlueColor)];
    self.modeLabel = DY778LuckyLabel(UIFontTextStyleCaption1,UIColor.secondaryLabelColor); self.modeLabel.textAlignment = NSTextAlignmentCenter;
    [body addArrangedSubview:self.modeLabel];
    self.joinButton = DY778LuckyButton(@"一键参与",YES,self,@selector(join));
    self.joinButton.contentEdgeInsets = UIEdgeInsetsMake(10,12,10,12);
    self.laterButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.laterButton setTitle:@"稍后再说" forState:UIControlStateNormal];
    self.muteButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.muteButton setTitle:@"不再提示" forState:UIControlStateNormal];
    for (UIButton *button in @[self.laterButton,self.muteButton]) {
        button.tintColor = UIColor.secondaryLabelColor; button.titleLabel.font = [UIFont systemFontOfSize:13];
        button.contentEdgeInsets = UIEdgeInsetsMake(9,4,9,4);
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:36].active = YES;
    }
    self.muteButton.accessibilityHint = @"本场福袋不再提醒，下一场仍会按设置提示";
    [self.laterButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.muteButton addTarget:self action:@selector(muteCurrent) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *secondary = [[UIStackView alloc] initWithArrangedSubviews:@[self.laterButton,self.muteButton]];
    secondary.axis = UILayoutConstraintAxisHorizontal; secondary.distribution = UIStackViewDistributionFillEqually; secondary.spacing = 8;
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[self.joinButton,secondary]];
    actions.axis = UILayoutConstraintAxisVertical; actions.spacing = 4; actions.translatesAutoresizingMaskIntoConstraints = NO; [card addSubview:actions];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal]; close.tintColor = UIColor.secondaryLabelColor;
    close.accessibilityLabel = @"关闭福袋弹窗"; [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside]; [card addSubview:close];
    NSLayoutConstraint *width = [card.widthAnchor constraintEqualToConstant:304]; width.priority = 999;
    NSLayoutConstraint *bodyHeight = [scroll.heightAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.heightAnchor]; bodyHeight.priority = 749;
    [NSLayoutConstraint activateConstraints:@[width,bodyHeight,
        [card.widthAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-40],
        [card.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [card.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [scroll.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [scroll.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [scroll.heightAnchor constraintLessThanOrEqualToConstant:330],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:65],
        [body.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [body.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [body.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [body.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [actions.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:12],
        [actions.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [actions.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [actions.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
        [close.topAnchor constraintEqualToAnchor:card.topAnchor constant:2],
        [close.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:2],
        [close.widthAnchor constraintEqualToConstant:44], [close.heightAnchor constraintEqualToConstant:44]
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:DY778LuckyStateChanged object:nil]; [self refresh];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; self.overrideUserInterfaceStyle = DY778InterfaceStyle(); self.coordinator.card.hidden = YES; [self refresh];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification,self.hostLabel); }
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated]; DY778LuckyCoordinator *c = self.coordinator;
    if (c.panel == self) c.panel = nil; [c emit];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)refresh {
    if (!self.isViewLoaded) return;
    DY778LuckyCoordinator *c = self.coordinator;
    BOOL bound = self.liveBound && self.boundSession == c.session;
    BOOL available = bound && [c contextValid] && c.lotteryID.length && c.phase != DY778LuckyEnded;
    self.hostLabel.text = c.roomTitle.length ? c.roomTitle : @"当前主播";
    DY778LoadAvatar(self.avatarView,c.ownerAvatarURL,c.ownerID.length ? c.ownerID : c.roomID);
    self.prizeLabel.text = c.prizeTitle ?: @"本场福袋";
    self.quantityLabel.text = c.prizeQuantity; self.quantityLabel.hidden = !c.prizeQuantity.length;
    self.countdownLabel.text = [c countdown];
    NSMutableArray *numberedConditions = [NSMutableArray new];
    [c.conditionLines enumerateObjectsUsingBlock:^(NSString *line,NSUInteger index,BOOL *stop) {
        [numberedConditions addObject:c.conditionLines.count > 1 ? [NSString stringWithFormat:@"%lu. %@",(unsigned long)index+1,line] : line];
    }];
    NSMutableAttributedString *details = [[NSMutableAttributedString alloc] initWithString:@""];
    [numberedConditions enumerateObjectsUsingBlock:^(NSString *line, NSUInteger index, BOOL *stop) {
        NSInteger highlight = [c.conditionHighlights[c.conditionLines[index]] integerValue];
        UIColor *color = highlight == 2 ? UIColor.systemGreenColor : highlight == 1 ? UIColor.systemOrangeColor : UIColor.labelColor;
        UIFont *font = highlight ? [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold] maximumPointSize:21] : self.detailLabel.font;
        [details appendAttributedString:[[NSAttributedString alloc] initWithString:[(index ? @"\n" : @"") stringByAppendingString:line] attributes:@{NSForegroundColorAttributeName:color,NSFontAttributeName:font}]];
    }];
    if (!details.length) [details appendAttributedString:[[NSAttributedString alloc] initWithString:@"无需额外条件" attributes:@{NSForegroundColorAttributeName:UIColor.labelColor,NSFontAttributeName:self.detailLabel.font}]];
    self.detailLabel.attributedText = details;
    BOOL pending = c.phase == DY778LuckyScheduled || c.phase == DY778LuckyOpening || c.phase == DY778LuckySubmitted;
    NSString *note = !DY778Bool(@"lucky.enabled") ? @"福袋助手未开启" : !bound ? @"本场会话已结束" :
        c.phase == DY778LuckyJoined ? @"抖音已确认参与，等待开奖" : c.phase == DY778LuckyManual ? c.detail :
        pending ? c.status : c.needsManualConditions ? c.restriction : c.phrase.length ? @"参与时发送上方口令一次" : @"";
    self.modeLabel.text = note; self.modeLabel.hidden = !note.length;
    NSString *title = c.paused ? @"继续本场助手" : c.phase == DY778LuckyJoined ? @"已参与 · 等待开奖" :
        pending ? @"正在参与…" : c.needsManualConditions ? (c.eligibilityPending ? @"正在核对条件…" : @"本场不自动参与") : @"一键参与";
    [self.joinButton setTitle:title forState:UIControlStateNormal];
    self.joinButton.enabled = available && DY778Bool(@"lucky.enabled") && !pending && !c.needsManualConditions && c.phase != DY778LuckyJoined;
    self.joinButton.alpha = self.joinButton.enabled ? 1 : 0.55;
    self.muteButton.enabled = available; self.joinButton.backgroundColor = DY778Accent();
    [self.joinButton setTitleColor:DY778LuckyButtonTitleColor() forState:UIControlStateNormal];
}
- (void)muteCurrent {
    DY778LuckyCoordinator *c = self.coordinator;
    if (!self.liveBound || c.session != self.boundSession || ![c key].length) return;
    NSString *key = [c key]; NSMutableDictionary *entry = [c.history[key] mutableCopy] ?: [NSMutableDictionary new];
    entry[@"muted"] = @YES; entry[@"time"] = @(NSDate.date.timeIntervalSince1970); c.history[key] = entry;
    [DY778Preferences() setObject:c.history forKey:@"lucky.handled"]; [self close];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)join {
    DY778LuckyCoordinator *c = self.coordinator; if (!self.liveBound || self.boundSession != c.session) return;
    if (c.paused) { [c togglePause]; return; }
    NSUInteger session = c.session; NSString *key = [c key];
    [self dismissViewControllerAnimated:YES completion:^{
        if (c.session == session && key.length && [key isEqual:[c key]]) [c joinRequested];
        else DY778LuckyToast(@"本场福袋已变化，请重新确认。");
    }];
}
@end
@implementation DY778LuckyCoordinator
+ (instancetype)shared {
    static DY778LuckyCoordinator *coordinator; static dispatch_once_t once;
    dispatch_once(&once, ^{ coordinator = [DY778LuckyCoordinator new]; }); return coordinator;
}
- (instancetype)init {
    if ((self = [super init])) {
        _fragments = [NSMapTable strongToWeakObjectsMapTable]; _comments = [NSMapTable strongToWeakObjectsMapTable];
        _seenFragments = [NSHashTable weakObjectsHashTable]; _seenComments = [NSHashTable weakObjectsHashTable];
        _commentServices = [NSMapTable strongToWeakObjectsMapTable]; _toastKeys = [NSMutableSet new];
        id records = [DY778Preferences() objectForKey:@"lucky.records"];
        _records = [NSMutableArray new];
        if ([records isKindOfClass:NSArray.class]) for (id record in records)
            if ([record isKindOfClass:NSDictionary.class] && [record[@"updated"] respondsToSelector:@selector(doubleValue)] &&
                [record[@"updated"] doubleValue] > NSDate.date.timeIntervalSince1970 - 30 * 86400) [_records addObject:record];
        id history = [DY778Preferences() objectForKey:@"lucky.handled"];
        _history = [history isKindOfClass:NSDictionary.class] ? [history mutableCopy] : [NSMutableDictionary new];
        _status = @"等待进入直播间"; _detail = @"进入直播间后，DY778会为你留意当前福袋。";
        _backgrounded = UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationWillResignActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];
        [self pruneHistory];
    } return self;
}
- (NSString *)key {
    if (!self.roomID.length || !self.lotteryID.length) return nil;
    return [NSString stringWithFormat:@"%@/%@/%@", self.accountID.length ? self.accountID : @"local", self.roomID, self.lotteryID];
}
- (void)pruneHistory {
    NSTimeInterval cutoff = NSDate.date.timeIntervalSince1970 - 48 * 3600;
    for (NSString *key in self.history.allKeys) {
        id value = self.history[key];
        if (![value isKindOfClass:NSDictionary.class] || [value[@"time"] doubleValue] < cutoff) [self.history removeObjectForKey:key];
    }
    if (self.history.count > 128) {
        NSArray *ordered = [self.history.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [self.history[a][@"time"] compare:self.history[b][@"time"]];
        }];
        [self.history removeObjectsForKeys:[ordered subarrayWithRange:NSMakeRange(0, self.history.count - 128)]];
    }
}
- (void)remember:(NSString *)stage phrase:(BOOL)phrase {
    NSString *key = [self key]; if (!key) return;
    NSMutableDictionary *entry = [self.history[key] mutableCopy] ?: [NSMutableDictionary new];
    entry[@"time"] = @(NSDate.date.timeIntervalSince1970);
    if (stage) entry[@"stage"] = stage;
    if ([@[@"submitted", @"joined"] containsObject:stage]) entry[@"submitted"] = @YES;
    if (phrase) entry[@"phrase"] = @YES;
    self.history[key] = entry; [self pruneHistory];
    [DY778Preferences() setObject:self.history forKey:@"lucky.handled"];
}
- (BOOL)attempted {
    NSString *stage = self.history[[self key] ?: @""][@"stage"];
    return [stage isEqual:@"joined"] || (self.attemptedSession == self.session && [self.attemptedKey isEqual:[self key]]);
}
- (NSString *)conditionSummary {
    return self.conditionLines.count ? [self.conditionLines componentsJoinedByString:@"\n"] : @"无需额外条件，以官方页面为准。";
}
- (void)recordStage:(NSString *)stage message:(NSString *)message {
    NSString *key = [self key]; if (!key.length || !stage.length) return;
    NSTimeInterval cutoff = NSDate.date.timeIntervalSince1970 - 30 * 86400;
    NSIndexSet *expired = [self.records indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) { return [obj[@"updated"] doubleValue] < cutoff; }];
    [self.records removeObjectsAtIndexes:expired];
    NSUInteger index = [self.records indexOfObjectPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) { return [obj[@"key"] isEqual:key]; }];
    NSMutableDictionary *record = index != NSNotFound ? [self.records[index] mutableCopy] : [NSMutableDictionary new];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (!record[@"created"]) record[@"created"] = @(now);
    record[@"key"] = key; record[@"account"] = self.accountID ?: @"";
    record[@"room"] = self.roomID ?: @""; record[@"lottery"] = self.lotteryID ?: @"";
    record[@"roomTitle"] = self.roomTitle ?: @"直播间"; record[@"prize"] = self.prizeTitle ?: @"福袋";
    record[@"conditions"] = self.conditionLines ?: @[]; record[@"updated"] = @(now);
    NSMutableArray *events = [record[@"events"] mutableCopy] ?: [NSMutableArray new];
    if (![record[@"stage"] isEqual:stage]) {
        [events addObject:@{@"stage": stage, @"message": message ?: @"", @"time": @(now)}];
        while (events.count > 20) [events removeObjectAtIndex:0];
    }
    if ([stage isEqual:@"joined"]) record[@"confirmed"] = @YES;
    if ([stage isEqual:@"phrase-awaiting"]) record[@"phraseSubmitted"] = @YES;
    if ([stage isEqual:@"submitted"]) record[@"joinSubmitted"] = @YES;
    if ([stage isEqual:@"left"]) record[@"roomLeft"] = @YES;
    record[@"stage"] = stage; record[@"message"] = message ?: @""; record[@"events"] = events;
    if (index != NSNotFound) [self.records removeObjectAtIndex:index];
    [self.records insertObject:record atIndex:0];
    while (self.records.count > 200) [self.records removeLastObject];
    [DY778Preferences() setObject:self.records forKey:@"lucky.records"];
}
- (void)announce:(NSString *)stage message:(NSString *)message {
    if (!DY778Bool(@"lucky.enabled") || !message.length) return;
    [self recordStage:stage message:message];
    BOOL joined = [stage isEqual:@"joined"];
    BOOL skipped = [@[@"fans-unmet", @"eligibility-unknown", @"eligibility-restricted"] containsObject:stage];
    if (!joined && (!skipped || ![DY778String(@"lucky.mode") isEqual:@"auto"])) return;
    if (joined) message = @"本场福袋已参与";
    if (skipped && [self.history[[self key] ?: @""][@"skipNotice"] boolValue]) return;
    NSString *token = [NSString stringWithFormat:@"%lu/%@/%@", (unsigned long)self.session, [self key] ?: self.roomID ?: @"", skipped ? @"eligibility-skip" : stage];
    if ([self.toastKeys containsObject:token]) return;
    [self.toastKeys addObject:token];
    NSUInteger session = self.session; NSString *lotteryKey = [self key];
    DY778LuckyEligibilityNotice notice = self.eligibilityNotice;
    NSTimeInterval now = CACurrentMediaTime();
    NSTimeInterval delay = fmax(0, self.lastToastTime + 0.9 - now); self.lastToastTime = now + delay;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DY778LuckyCoordinator *c = weakSelf;
        if (!c || c.session != session || ![lotteryKey isEqual:[c key]] || c.backgrounded ||
            !DY778Bool(@"lucky.enabled") || ![c contextValid]) {
            if (skipped && c.session == session) [c.toastKeys removeObject:token];
            return;
        }
        if (skipped) {
            if (![DY778String(@"lucky.mode") isEqual:@"auto"] || c.paused || c.eligibilityPending ||
                c.phase != DY778LuckyAvailable || c.eligibilityNotice == DY778LuckyEligibilityNoticeNone) {
                [c.toastKeys removeObject:token]; return;
            }
            if (notice != c.eligibilityNotice) {
                [c.toastKeys removeObject:token]; [c announceEligibilitySkip]; return;
            }
            NSMutableDictionary *entry = [c.history[lotteryKey] mutableCopy] ?: [NSMutableDictionary new];
            entry[@"skipNotice"] = @YES; entry[@"time"] = @(NSDate.date.timeIntervalSince1970);
            c.history[lotteryKey] = entry; [c pruneHistory];
            [DY778Preferences() setObject:c.history forKey:@"lucky.handled"];
        }
        DY778ShowToast(@"lucky", message, NO, joined);
    });
}
- (void)announceEligibilitySkip {
    if (self.eligibilityPending || ![DY778String(@"lucky.mode") isEqual:@"auto"] ||
        [self.history[[self key] ?: @""][@"skipNotice"] boolValue]) return;
    switch (self.eligibilityNotice) {
        case DY778LuckyEligibilityNoticeFans:
            [self announce:@"fans-unmet" message:@"灯牌条件未满足，已跳过本场福袋"]; break;
        case DY778LuckyEligibilityNoticeUnknown:
            [self announce:@"eligibility-unknown" message:@"暂未确认参与资格，已跳过本场福袋"]; break;
        case DY778LuckyEligibilityNoticeRestricted:
            [self announce:@"eligibility-restricted" message:@"本场参与资格受限，已跳过自动参与"]; break;
        default: break;
    }
}
- (void)observeComponent:(id)component comment:(BOOL)isComment service:(BOOL)service {
    if (!component) return;
    if (service) DY778MarkLiveComponent(component);
    else {
        if ([objc_getAssociatedObject(component, &DY778LuckyComponentRetiredKey) boolValue]) return;
        if (!objc_getAssociatedObject(component, &DY778LuckyComponentAccountKey)) DY778MarkLiveComponent(component);
    }
    if (!isComment) [self.seenFragments addObject:component]; else [self.seenComments addObject:component];
    DY778RecordHook(isComment ? @"福袋运行 / 已观察评论组件" : @"福袋运行 / 已观察福袋组件", YES);
    [self bindFragment:component comment:isComment];
    if (!isComment && DY778Bool(@"lucky.enabled")) [self discoverVisibleRoom];
}
- (void)discoverVisibleRoom {
    if (self.discovering || self.backgrounded || !DY778Bool(@"lucky.enabled")) return;
    self.discovering = YES;
    NSArray *candidates = [self.seenFragments.allObjects sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [objc_getAssociatedObject(b, &DY778LuckyComponentMountKey) compare:objc_getAssociatedObject(a, &DY778LuckyComponentMountKey)];
    }];
    for (id fragment in candidates) {
        if ([objc_getAssociatedObject(fragment, &DY778LuckyComponentRetiredKey) boolValue] ||
            ![(objc_getAssociatedObject(fragment, &DY778LuckyComponentAccountKey) ?: @"") isEqual:(DY778CurrentAccountID() ?: @"")]) continue;
        UIView *view = DY778LiveVisibleView(fragment);
        UIViewController *controller = DY778LiveControllerForView(view);
        NSString *roomID = DY778FragmentRoomID(fragment);
        if (!controller || !roomID.length) continue;
        NSString *controllerRoom = DY778LiveHostRoomID(controller);
        if (controllerRoom.length && ![controllerRoom isEqual:roomID]) continue;
        self.anchorView = view; DY778RecordHook(@"福袋运行 / 已关联可见房间", YES);
        [self.fragments setObject:fragment forKey:roomID];
        [self enterHost:controller roomID:roomID];
        self.fragment = fragment; [self lotteryChanged:fragment];
        break;
    }
    self.discovering = NO;
}
- (void)observeCommentService:(id)service {
    if (!service || !DY778LiveCommentCanSend(service)) return;
    NSString *roomID = DY778FragmentRoomID(service); id injector = DY778LiveObject(service, @"injector");
    if (!roomID.length) roomID = DY778FragmentRoomID(injector);
    if (!roomID.length) return;
    DY778MarkLiveComponent(service); [self.commentServices setObject:service forKey:roomID];
    DY778RecordHook(@"福袋运行 / 已观察评论服务", YES);
    if ([self.roomID isEqual:roomID]) self.commentService = service;
    NSString *injectorAccount = objc_getAssociatedObject(injector,&DY778LuckyComponentAccountKey);
    if (DY778LiveCommentCanSend(injector) && [roomID isEqual:DY778FragmentRoomID(injector)] &&
        (!injectorAccount || [injectorAccount isEqual:(DY778CurrentAccountID() ?: @"")]) &&
        ![objc_getAssociatedObject(injector,&DY778LuckyComponentRetiredKey) boolValue])
        [self observeComponent:injector comment:YES service:NO];
}
- (void)observeCommentFromLoader:(id)loader {
    if (!loader || !self.roomID.length) return;
    NSString *room = DY778FragmentRoomID(loader);
    if (room.length && ![room isEqual:self.roomID]) return;
    DY778RecordHook(@"福袋运行 / 已读取本房组件加载器",YES);
    NSMutableArray *pending = [NSMutableArray new];
    for (NSString *key in @[@"components",@"componentMaps"]) {
        id value = DY778Read(loader,key); if (value) [pending addObject:value];
    }
    NSUInteger visited = 0;
    while (pending.count && visited++ < 512) {
        id candidate = pending.lastObject; [pending removeLastObject];
        if ([candidate isKindOfClass:NSDictionary.class]) { [pending addObjectsFromArray:[candidate allValues]]; continue; }
        if ([candidate isKindOfClass:NSArray.class]) { [pending addObjectsFromArray:candidate]; continue; }
        if (!DY778LiveCommentCanSend(candidate)) continue;
        NSString *ownRoom = DY778FragmentRoomID(candidate);
        if (![ownRoom isEqual:self.roomID] && ![room isEqual:self.roomID]) continue;
        if (DY778LiveBindCommentRoom(candidate,self.roomID)) [self observeComponent:candidate comment:YES service:NO];
    }
}
- (id)resolveCommentSender {
    if (!self.roomID.length || ![self contextValid]) return nil;
    NSMutableArray *candidates = [NSMutableArray new];
    if (self.comment) [candidates addObject:self.comment];
    id cached = [self.comments objectForKey:self.roomID]; if (cached && cached != self.comment) [candidates addObject:cached];
    for (id comment in self.seenComments.allObjects) if (![candidates containsObject:comment]) [candidates addObject:comment];
    NSMutableArray *services = [NSMutableArray new];
    if (self.commentService) [services addObject:self.commentService];
    id service = [self.commentServices objectForKey:self.roomID]; if (service && ![services containsObject:service]) [services addObject:service];
    NSMutableArray *attachers = [NSMutableArray new];
    for (id object in @[self.fragment ?: NSNull.null, DY778LiveObject(self.fragment,@"room") ?: NSNull.null,
        DY778LiveObject(self.fragment,@"roomService") ?: NSNull.null, DY778LiveObject(self.fragment,@"store") ?: NSNull.null])
        if (object != NSNull.null) [attachers addObject:object];
    NSMutableArray *roomDIs = [NSMutableArray new];
    for (id attacher in attachers) {
        id di = DY778LiveRoomDI(attacher); if (di && ![roomDIs containsObject:di]) [roomDIs addObject:di];
        id resolved = DY778LiveCommentFromAttacher(attacher);
        if (resolved && ![services containsObject:resolved]) {
            NSString *sourceRoom = DY778FragmentRoomID(attacher) ?: DY778LiveRoomID(attacher);
            BOOL contextBound = DY778LiveObject(attacher,@"attachingDIContext") != nil && [sourceRoom isEqual:self.roomID];
            if ([DY778FragmentRoomID(resolved) isEqual:self.roomID] || DY778LiveDIOwnsRoom(di,self.roomID) || contextBound) {
                if (DY778LiveBindCommentRoom(resolved,self.roomID)) [services addObject:resolved];
            }
        }
    }
    UIViewController *controller = self.host;
    for (NSUInteger depth = 0; controller && depth < 6; depth++, controller = controller.parentViewController) {
        id di = DY778LiveObject(controller, @"roomDI") ?: DY778LiveObject(DY778LiveObject(controller, @"roomConfig"), @"roomDI") ?:
            DY778LiveObject(DY778LiveObject(controller, @"containerContext"), @"roomDI");
        if (di && ![roomDIs containsObject:di]) [roomDIs addObject:di];
        [self observeCommentFromLoader:DY778Read(DY778Read(controller,@"componentLoader"),@"realLoader")];
        [self observeCommentFromLoader:DY778Read(DY778Read(controller,@"componentProcess"),@"componentLoader")];
    }
    for (id di in roomDIs) {
        id resolved = DY778LiveDICommentService(di);
        if (resolved && ![services containsObject:resolved]) {
            if (DY778LiveDIOwnsRoom(di,self.roomID)) DY778LiveBindCommentRoom(resolved,self.roomID);
            [services addObject:resolved];
        }
    }
    DY778RecordHook(@"福袋运行 / 已找到房间依赖容器",roomDIs.count > 0);
    for (id comment in self.seenComments.allObjects) if (![candidates containsObject:comment]) [candidates addObject:comment];
    for (id current in services) {
        NSString *boundAccount = objc_getAssociatedObject(current, &DY778LuckyComponentAccountKey);
        if (boundAccount && ![boundAccount isEqual:(DY778CurrentAccountID() ?: @"")]) continue;
        if ([objc_getAssociatedObject(current,&DY778LuckyComponentRetiredKey) boolValue]) continue;
        NSString *room = DY778FragmentRoomID(current);
        if (room.length && ![room isEqual:self.roomID]) continue;
        [self observeCommentService:current];
        id injector = DY778LiveObject(current, @"injector");
        if ([DY778FragmentRoomID(current) isEqual:self.roomID]) DY778LiveBindCommentRoom(injector,self.roomID);
        if (injector && ![candidates containsObject:injector]) [candidates addObject:injector];
        if (![candidates containsObject:current]) [candidates addObject:current];
    }
    [candidates sortUsingComparator:^NSComparisonResult(id a,id b) {
        NSInteger (^rank)(id) = ^NSInteger(id value) {
            if (DY778LiveCanCall(value,@"sendComment:commentContext:completion:","v","@@@")) return 0;
            if (DY778LiveCanCall(value,@"sendComment:enterSource:requestSource:trackParams:completion:","v","@q@@@")) return 1;
            return 2;
        };
        NSInteger left = rank(a), right = rank(b); return left < right ? NSOrderedAscending : left > right ? NSOrderedDescending : NSOrderedSame;
    }];
    for (id candidate in candidates) {
        if (!DY778LiveCommentCanSend(candidate) || ![self.roomID isEqual:DY778FragmentRoomID(candidate)] ||
            [objc_getAssociatedObject(candidate, &DY778LuckyComponentRetiredKey) boolValue]) continue;
        NSString *account = objc_getAssociatedObject(candidate, &DY778LuckyComponentAccountKey);
        if (account && ![account isEqual:(DY778CurrentAccountID() ?: @"")]) continue;
        if (!account) DY778MarkLiveComponent(candidate);
        if (DY778LiveCanCall(candidate, @"sendComment:commentContext:completion:", "v", "@@@")) self.comment = candidate;
        else if (DY778LiveCanCall(candidate,@"sendComment:enterSource:requestSource:trackParams:completion:","v","@q@@@")) self.commentService = candidate;
        DY778RecordHook(@"福袋运行 / 本房口令发送路径已就绪", YES);
        DY778RecordHook(@"福袋运行 / 普通评论组件发送",DY778LiveCanCall(candidate,@"sendComment:commentContext:completion:","v","@@@"));
        DY778RecordHook(@"福袋运行 / 普通评论服务发送",DY778LiveCanCall(candidate,@"sendComment:enterSource:requestSource:trackParams:completion:","v","@q@@@"));
        DY778RecordHook(@"福袋运行 / 普通评论存储发送",DY778LiveCanCall(candidate,@"sendCommentWithCommentContext:completion:","v","@@"));
        return candidate;
    }
    DY778RecordHook(@"福袋运行 / 本房口令发送路径已就绪",NO);
    return nil;
}
- (BOOL)ownsVisiblePanel {
    BOOL ownPanel = self.panel.liveBound && self.panel.boundSession == self.session &&
        self.panel.isViewLoaded && self.panel.view.window != nil;
    id panel = DY778Read(self.fragment, @"hybridLotteryPanel");
    UIView *panelView = DY778LuckyPanelView(panel);
    BOOL officialPanel = !self.quietToken.length && (panelView.window != nil || DY778LuckyWebVisible(self.activeWebView) ||
        DY778LiveCallBool(self.fragment, @"lotteryPannelViewShowing"));
    return ownPanel || officialPanel;
}
- (BOOL)requestValid {
    if (!self.host || !self.fragment || !self.roomID.length || self.backgrounded ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    if ([objc_getAssociatedObject(self.fragment, &DY778LuckyComponentMountKey) doubleValue] <= 0 ||
        ![(objc_getAssociatedObject(self.fragment, &DY778LuckyComponentAccountKey) ?: @"__unbound__") isEqual:self.accountID] ||
        (DY778LiveHostRoomID(self.host).length && ![self.roomID isEqual:DY778LiveHostRoomID(self.host)]) ||
        ![self.roomID isEqual:DY778FragmentRoomID(self.fragment)] ||
        ![(self.accountID ?: @"") isEqual:(DY778CurrentAccountID() ?: @"")]) return NO;
    if (self.lotteryID.length) {
        id lottery = DY778Read(DY778Read(self.fragment, @"store"), @"currentLottery");
        NSString *lotteryRoom = DY778LiveRoomID(lottery);
        if (![self.lotteryID isEqual:DY778LotteryID(lottery)] || (lotteryRoom.length && ![self.roomID isEqual:lotteryRoom])) return NO;
    }
    return YES;
}
- (BOOL)contextValid {
    if (![self requestValid]) return NO;
    BOOL panel = [self ownsVisiblePanel];
    BOOL transition = self.presentationDeadline > CACurrentMediaTime();
    BOOL covered = NO; for (UIViewController *controller = self.host; controller; controller = controller.parentViewController)
        if (controller.presentedViewController) { covered = YES; break; }
    BOOL foreignModal = covered && !panel && !transition;
    if ((self.roomInactive || foreignModal) && !panel && !transition) return NO;
    BOOL hostVisible = self.host.isViewLoaded && self.host.view.window != nil;
    if (!DY778LiveHostRoomID(self.host).length) hostVisible = hostVisible && DY778LiveVisibleView(self.fragment) != nil;
    return hostVisible || panel || transition;
}
- (void)suspendHost:(UIViewController *)host {
    if (host != self.host) return;
    if (self.quietCreating && self.quietContainer.window && [self quietRequestValid]) return;
    if ([self ownsVisiblePanel] || self.presentationDeadline > CACurrentMediaTime()) return;
    self.roomInactive = YES; [self cancelPending];
    self.card.hidden = YES;
    if (self.phase == DY778LuckyScheduled || self.phase == DY778LuckyOpening || self.phase == DY778LuckySubmitted) {
        self.phase = DY778LuckyManual; self.status = @"等待回到直播间";
        self.detail = @"直播页面暂时不可见，待执行操作已取消。";
        [self recordProbe:@"直播页面不可见，操作已停止"];
    }
    [self.panel refresh];
}
- (void)enterHost:(UIViewController *)host {
    NSString *roomID = DY778LiveHostRoomID(host);
    if (!roomID.length && DY778LiveSameHierarchy(host, DY778LiveControllerForView(self.anchorView))) roomID = DY778FragmentRoomID(self.fragment);
    if (host && roomID.length) [self enterHost:host roomID:roomID];
    else [self discoverVisibleRoom];
}
- (void)enterHost:(UIViewController *)host roomID:(NSString *)roomID {
    if (!host || !roomID.length) return;
    NSString *account = DY778CurrentAccountID() ?: @"";
    BOOL accountChanged = self.accountID != nil && ![account isEqual:self.accountID];
    BOOL changed = ![roomID isEqual:self.roomID] || accountChanged || (self.host != host && !DY778LiveSameHierarchy(self.host, host));
    if (changed) {
        self.session++; [self.toastKeys removeAllObjects]; self.lastToastTime = 0;
        if (accountChanged) { [self.fragments removeAllObjects]; [self.comments removeAllObjects]; [self.seenFragments removeAllObjects]; [self.seenComments removeAllObjects]; [self.commentServices removeAllObjects]; }
        [self cancelPending]; [self resetEligibility]; [self.timer invalidate]; self.timer = nil;
        [self.card removeFromSuperview]; self.card = nil;
        if (self.panel.liveBound && (self.panel.presentingViewController || self.panel.navigationController.presentingViewController))
            [self.panel dismissViewControllerAnimated:NO completion:nil];
        self.roomID = roomID; self.accountID = account; self.lotteryID = nil;
        self.phase = DY778LuckyIdle; self.paused = NO; self.deadline = 0; self.restriction = nil; self.phrase = nil;
        self.announcedKey = nil; self.status = @"等待福袋";
        self.detail = @"助手已就绪。发现福袋后，会显示倒计时和本场参与方式。";
    }
    self.roomInactive = NO;
    self.host = host; self.fragment = [self.fragments objectForKey:roomID]; self.comment = [self.comments objectForKey:roomID]; self.commentService = [self.commentServices objectForKey:roomID];
    self.backgrounded = UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
    if (DY778Bool(@"lucky.enabled")) {
        [self ensureTimer]; [self lotteryChanged:self.fragment]; [self emit];
        if (changed) {
            self.card.accessibilityHint = @"助手已就绪，点按查看本场福袋，拖动可调整位置";
        }
    }
}
- (void)leaveHost:(UIViewController *)host {
    if (self.host != host) return;
    if (self.lotteryID.length) [self recordStage:@"left" message:@"已离开直播间，待执行操作已停止。"];
    self.session++; self.roomInactive = YES;
    [self cancelPending]; [self resetEligibility]; [self.timer invalidate]; self.timer = nil;
    [self.card removeFromSuperview]; self.card = nil;
    if (self.panel.liveBound) [self.panel dismissViewControllerAnimated:NO completion:nil];
    self.host = nil; self.fragment = nil; self.comment = nil; self.commentService = nil; self.roomID = nil; self.lotteryID = nil;
    self.phase = DY778LuckyIdle; self.deadline = 0; self.status = @"等待进入直播间";
    self.detail = @"已离开直播间，待执行的福袋操作已取消。"; self.anchorView = nil; [self emit];
}
- (void)bindFragment:(id)fragment comment:(BOOL)isComment {
    NSString *boundAccount = objc_getAssociatedObject(fragment, &DY778LuckyComponentAccountKey);
    if (!boundAccount || ![boundAccount isEqual:(DY778CurrentAccountID() ?: @"")] ||
        [objc_getAssociatedObject(fragment, &DY778LuckyComponentMountKey) doubleValue] <= 0) return;
    NSString *roomID = DY778FragmentRoomID(fragment); if (!roomID.length) return;
    if (self.host && ![self.accountID isEqual:boundAccount]) [self enterHost:self.host];
    NSMapTable *map = isComment ? self.comments : self.fragments;
    id existing = [map objectForKey:roomID];
    if (existing != fragment && [objc_getAssociatedObject(existing, &DY778LuckyComponentMountKey) doubleValue] >
        [objc_getAssociatedObject(fragment, &DY778LuckyComponentMountKey) doubleValue]) return;
    [map setObject:fragment forKey:roomID];
    if (map.count > 16) for (NSString *key in map.keyEnumerator.allObjects)
        if (![map objectForKey:key]) [map removeObjectForKey:key];
    if (![self.roomID isEqual:roomID]) return;
    if (isComment) self.comment = fragment;
    else { self.fragment = fragment; [self lotteryChanged:fragment]; }
}
- (void)unbindFragment:(id)fragment comment:(BOOL)isComment {
    objc_setAssociatedObject(fragment, &DY778LuckyComponentRetiredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(fragment, &DY778LuckyComponentMountKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMapTable *map = isComment ? self.comments : self.fragments;
    NSString *roomID = DY778FragmentRoomID(fragment);
    if (roomID && [map objectForKey:roomID] == fragment) [map removeObjectForKey:roomID];
    if (isComment && self.comment == fragment) self.comment = nil;
    if (!isComment && self.fragment == fragment) {
        self.session++;
        if (self.panel.liveBound) [self.panel dismissViewControllerAnimated:NO completion:nil];
        [self cancelPending]; [self resetEligibility]; self.fragment = nil; self.lotteryID = nil; self.deadline = 0;
        self.phase = DY778LuckyIdle; self.status = @"等待福袋";
        self.detail = @"当前福袋组件已离开，待执行操作已取消。"; [self emit];
    }
}
- (NSTimeInterval)remainingForLottery:(id)lottery {
    id store = DY778Read(self.fragment, @"store");
    NSDictionary *sample = objc_getAssociatedObject(store, &DY778LuckyClockSampleKey);
    if ([sample[@"lottery"] isEqual:DY778LotteryID(lottery)] && CACurrentMediaTime() - [sample[@"at"] doubleValue] < 3)
        return DY778LuckyClockRemaining([sample[@"seconds"] doubleValue], [sample[@"at"] doubleValue], CACurrentMediaTime());
    double display = DY778LiveFloatingSeconds(DY778Read(self.fragment, @"lotteryFloatingView"));
    if (display >= 0) return display;
    double server = DY778LiveServerSeconds(lottery);
    if (DY778LiveCanCall(store, @"getCurrentLotteryRemainTime", "qQ", ""))
        return DY778LuckyStoreDurationSeconds(((long long (*)(id, SEL))objc_msgSend)(store, NSSelectorFromString(@"getCurrentLotteryRemainTime")));
    double raw = [DY778Read(lottery, @"remainTime") doubleValue];
    return raw > 0 ? DY778LuckyDurationSeconds(raw, server) : server;
}
- (void)nativeClockUpdated:(id)store {
    if (store != DY778Read(self.fragment, @"store") || !self.lotteryID.length) return;
    [self synchronizeCountdown]; [self emit];
}
- (void)synchronizeCountdown {
    id store = DY778Read(self.fragment, @"store");
    NSDictionary *sample = objc_getAssociatedObject(store, &DY778LuckyClockSampleKey);
    if (![sample[@"lottery"] isEqual:self.lotteryID] || CACurrentMediaTime() - [sample[@"at"] doubleValue] > 3) return;
    double remaining = DY778LuckyClockRemaining([sample[@"seconds"] doubleValue], [sample[@"at"] doubleValue], CACurrentMediaTime());
    if (remaining >= 0) self.deadline = CACurrentMediaTime() + remaining;
}
- (void)readConditions:(id)lottery {
    self.phrase = nil; self.restriction = nil; self.needsManualConditions = NO; self.requiresFans = NO;
    id prize = DY778Read(lottery, @"prizeInfo");
    self.prizeTitle = DY778LiveString(DY778Read(prize, @"name"));
    if (!self.prizeTitle.length) self.prizeTitle = DY778LiveString(DY778Read(prize, @"prizeDescription"));
    if (!self.prizeTitle.length) self.prizeTitle = @"本场福袋";
    id room = DY778Read(self.fragment, @"room") ?: DY778Read(DY778Read(self.fragment, @"store"), @"roomModel");
    id owner = DY778Read(room, @"owner") ?: DY778Read(DY778Read(room, @"roomModel"), @"owner");
    self.roomTitle = DY778LiveString(DY778Read(owner, @"nickname"));
    if (!self.roomTitle.length) self.roomTitle = DY778LiveString(DY778Read(room, @"title"));
    if (!self.roomTitle.length) self.roomTitle = @"当前主播";
    self.ownerID = DY778LiveID(DY778Read(owner,@"userID")) ?: DY778LiveID(DY778Read(lottery,@"anchorId")) ?: @"";
    NSString *eligibilityKey = [NSString stringWithFormat:@"%@/%@", [self key] ?: @"", self.ownerID];
    if (![self.eligibilityKey isEqual:eligibilityKey] || self.eligibilitySession != self.session) {
        [self resetEligibility]; self.eligibilityKey = eligibilityKey; self.eligibilitySession = self.session;
    }
    BOOL fresh = DY778LuckyEligibilityFresh(YES,self.eligibilityCheckedAt,CACurrentMediaTime());
    self.ownerAvatarURL = DY778AvatarURL(DY778Read(owner,@"avatarMedium"));
    if (!self.ownerAvatarURL.length) self.ownerAvatarURL = DY778AvatarURL(DY778Read(owner,@"avatarThumb"));
    long long luckyCount = [DY778Read(lottery,@"luckyCount") longLongValue];
    long long prizeCount = [DY778Read(lottery,@"prizeCount") longLongValue];
    NSMutableArray *quantity = [NSMutableArray new];
    if (luckyCount > 0) [quantity addObject:[NSString stringWithFormat:@"%lld 个福袋",luckyCount]];
    NSString *unit = [self.prizeTitle containsString:@"钻石"] ? @"钻石" : [self.prizeTitle containsString:@"抖币"] ? @"抖币" : nil;
    if (prizeCount > 0) [quantity addObject:unit ? [NSString stringWithFormat:@"共 %lld %@",prizeCount,unit] : [NSString stringWithFormat:@"共 %lld 份奖励",prizeCount]];
    self.prizeQuantity = [quantity componentsJoinedByString:@" · "];
    id conditions = DY778Read(lottery, @"conditionsArray");
    NSMutableArray *lines = [NSMutableArray new];
    NSMutableDictionary *highlights = [NSMutableDictionary new];
    BOOL extraConditions = NO, fansUnmet = NO, unknownLevel = NO;
    if (![conditions isKindOfClass:NSArray.class]) {
        [lines addObject:@"参与条件尚未同步"]; extraConditions = YES;
    } else for (id condition in conditions) {
        NSInteger type = [DY778Read(condition, @"type") integerValue];
        NSString *content = DY778LiveString(DY778Read(condition, @"content"));
        NSString *description = DY778LiveString(DY778Read(condition, @"description_p"));
        NSString *remarks = DY778LiveString(DY778Read(condition, @"remarks"));
        BOOL paid = [DY778Read(condition, @"needDiamondCount") longLongValue] > 0 ||
            [DY778Read(condition, @"giftCount") longLongValue] > 0 || [DY778Read(condition, @"giftId") longLongValue] > 0;
        long long level = MAX(0,[DY778Read(condition,@"minFansLevel") longLongValue]);
        NSString *caption = DY778LuckyConditionCaption(description.length ? description : remarks.length ? remarks : content);
        if (DY778LuckyConditionIsInstruction(caption.UTF8String)) for (NSString *candidate in @[remarks,content]) {
            NSString *clean = DY778LuckyConditionCaption(candidate);
            if (clean.length && !DY778LuckyConditionIsInstruction(clean.UTF8String)) { caption = clean; break; }
        }
        NSString *metadata = [NSString stringWithFormat:@"%@ %@ %@",description,remarks,type == 3 ? @"" : content];
        BOOL fans = level > 0 || (type != 3 && DY778LuckyContains(metadata,@[@"粉丝团",@"灯牌",@"粉丝牌",@"粉丝等级"]));
        if (fans && !level) level = DY778LuckyCaptionLevel(metadata);
        BOOL extraAction = type != 3 && DY778LuckyContains(metadata,@[@"关注",@"送礼",@"赠送",@"送出",@"支付",@"购买",@"订阅",@"分享直播",@"心愿",@"激活任务"]);
        DY778LuckyConditionKind kind = DY778LuckyClassifyCondition((int)type,content.length > 0 && content.length <= 500,
            caption.length > 0,paid,fans,extraAction,DY778LuckyConditionIsInstruction(caption.UTF8String));
        if (kind == DY778LuckyConditionIgnore) continue;
        NSString *line = caption; NSInteger highlight = 0;
        if (kind == DY778LuckyConditionFans) {
            self.requiresFans = YES;
            BOOL known = self.fanEligibilityKnown && fresh && !self.eligibilityBlocked;
            BOOL eligible = DY778LuckyFanEligible(known,[DY778Read(self.userCondition,@"isFansclubMember") boolValue],
                [DY778Read(self.userCondition,@"fansclubStatusActive") boolValue],[DY778Read(self.userCondition,@"fansLevel") longLongValue],level);
            if (!level && DY778LuckyContains(metadata,@[@"等级",@"级别"])) { eligible = NO; unknownLevel = YES; }
            if (!caption.length || DY778LuckyConditionIsInstruction(caption.UTF8String))
                line = level > 0 ? [NSString stringWithFormat:@"有效粉丝灯牌达到 %lld 级",level] : @"已点亮本主播粉丝灯牌";
            line = [line stringByAppendingString:eligible ? @" · 已满足" : known ? @" · 未满足" : @" · 待核对"];
            highlight = eligible ? 2 : 1; fansUnmet |= !eligible;
            extraConditions |= paid || extraAction;
        } else if (kind == DY778LuckyConditionPhrase) {
            if (self.phrase.length && ![self.phrase isEqual:content]) extraConditions = YES;
            self.phrase = content; line = [NSString stringWithFormat:@"评论：%@",content];
        } else {
            if (!line.length) line = paid ? @"包含礼物或付费条件" : @"当前条件暂不支持自动处理";
            extraConditions = YES;
        }
        if (line.length && ![lines containsObject:line]) [lines addObject:line];
        if (highlight && line.length) highlights[line] = @(highlight);
    }
    self.needsManualConditions = extraConditions || fansUnmet || (self.requiresFans && self.eligibilityBlocked);
    self.eligibilityNotice = DY778LuckyFanNotice(self.requiresFans, self.eligibilityPending, fresh,
        self.fanEligibilityKnown, self.eligibilityBlocked, fansUnmet, unknownLevel);
    if (extraConditions) self.restriction = @"本场含有评论以外的待处理条件，助手会跳过，不会送礼或付费。";
    else if (self.eligibilityBlocked && self.requiresFans) self.restriction = @"平台暂未允许当前账号参与，助手会跳过本场。";
    else if (fansUnmet) self.restriction = self.eligibilityPending ? @"正在核对本主播的灯牌与等级，确认达标后继续。" :
        self.fanEligibilityKnown && fresh ? @"本主播的灯牌或等级尚未满足，助手不会代为点亮或升级。" : @"尚未确认本主播的灯牌资格，确认前不发送评论或报名。";
    self.conditionLines = lines; self.conditionHighlights = highlights;
}
- (void)resetEligibility {
    self.eligibilityGeneration++; self.eligibilityPending = NO; self.fanEligibilityKnown = NO;
    self.eligibilityCheckedAt = 0; self.userCondition = nil; self.eligibilityKey = nil; self.eligibilityBlocked = NO;
    self.eligibilityNotice = DY778LuckyEligibilityNoticeNone;
}
- (void)refreshFanEligibility {
    if (!self.requiresFans || self.eligibilityPending || !DY778Bool(@"lucky.enabled") || self.paused || ![self contextValid] || !self.accountID.length) return;
    if (DY778LuckyEligibilityFresh(YES,self.eligibilityCheckedAt,CACurrentMediaTime())) return;
    self.eligibilityCheckedAt = CACurrentMediaTime(); self.fanEligibilityKnown = NO; self.userCondition = nil;
    id api = DY778LiveObject(DY778LiveObject(self.fragment,@"store"),@"lotteryApi");
    NSString *selector = @"checkLotteryUserRightWithLotteryID:roomID:retry:completion:";
    if (!DY778LiveCanCall(api,selector,"v","@@q@")) return;
    self.eligibilityPending = YES;
    NSString *key = self.eligibilityKey, *room = self.roomID, *lotteryID = self.lotteryID, *owner = self.ownerID;
    NSUInteger serial = ++self.eligibilityGeneration, session = self.session;
    __weak id fragment = self.fragment; __weak typeof(self) weakSelf = self;
    void (^complete)(id,id) = ^(id data,id error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778LuckyCoordinator *c = weakSelf;
            if (!c || serial != c.eligibilityGeneration || session != c.session || !c.eligibilityPending ||
                ![key isEqual:c.eligibilityKey] || fragment != c.fragment || ![c requestValid] || !DY778Bool(@"lucky.enabled")) return;
            c.eligibilityPending = NO; c.eligibilityCheckedAt = CACurrentMediaTime();
            id info = DY778Read(data,@"lotteryInfo"), condition = DY778Read(data,@"userCondition");
            NSString *responseID = DY778LotteryID(info), *responseRoom = DY778LiveRoomID(info), *anchor = DY778LiveID(DY778Read(info,@"anchorId"));
            BOOL matched = (!responseID.length || [responseID isEqual:lotteryID]) &&
                (!responseRoom.length || [responseRoom isEqual:room]) && (!anchor.length || !owner.length || [anchor isEqual:owner]);
            id member = DY778Read(condition,@"isFansclubMember"), active = DY778Read(condition,@"fansclubStatusActive"), level = DY778Read(condition,@"fansLevel");
            c.eligibilityBlocked = !error && matched && [DY778Read(data,@"hitBlackList") boolValue];
            c.fanEligibilityKnown = !error && matched && [DY778Read(data,@"hasUserCondition") boolValue] &&
                [member isKindOfClass:NSNumber.class] && [active isKindOfClass:NSNumber.class] && [level isKindOfClass:NSNumber.class];
            c.userCondition = c.fanEligibilityKnown ? @{@"isFansclubMember":member,@"fansclubStatusActive":active,@"fansLevel":level} : nil;
            [c readConditions:DY778Read(DY778Read(c.fragment,@"store"),@"currentLottery")];
            [c emit]; [c considerAutoJoin];
        });
    };
    @try { ((void (*)(id,SEL,id,id,long long,id))objc_msgSend)(api,NSSelectorFromString(selector),lotteryID,room,0,complete); }
    @catch (__unused NSException *exception) { self.eligibilityPending = NO; }
    [self readConditions:DY778Read(DY778Read(self.fragment,@"store"),@"currentLottery")];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        DY778LuckyCoordinator *c = weakSelf;
        if (!c || serial != c.eligibilityGeneration || !c.eligibilityPending) return;
        c.eligibilityPending = NO; c.eligibilityGeneration++; c.eligibilityCheckedAt = CACurrentMediaTime();
        [c readConditions:DY778Read(DY778Read(c.fragment,@"store"),@"currentLottery")]; [c emit]; [c considerAutoJoin];
    });
}
- (BOOL)eligibilityAllowsJoin {
    [self readConditions:DY778Read(DY778Read(self.fragment,@"store"),@"currentLottery")];
    if (!self.accountID.length) {
        self.needsManualConditions = YES; self.restriction = @"登录抖音后再参与本场福袋。"; return NO;
    }
    [self refreshFanEligibility];
    return !self.needsManualConditions && !self.eligibilityPending;
}
- (void)lotteryChanged:(id)fragment {
    if (!DY778Bool(@"lucky.enabled")) return;
    if (!fragment || ![self.roomID isEqual:DY778FragmentRoomID(fragment)] ||
        ![(objc_getAssociatedObject(fragment, &DY778LuckyComponentAccountKey) ?: @"__unbound__") isEqual:self.accountID]) return;
    self.fragment = fragment;
    id lottery = DY778Read(DY778Read(fragment, @"store"), @"currentLottery");
    NSString *identifier = DY778LotteryID(lottery);
    NSString *lotteryRoom = DY778LiveRoomID(lottery);
    if (!identifier.length || (lotteryRoom.length && ![self.roomID isEqual:lotteryRoom])) return;
    if ([self.lotteryID isEqual:identifier]) { [self readConditions:lottery]; [self participationChanged:fragment]; [self emit]; [self considerAutoJoin]; [self showDiscoveryPrompt]; return; }
    [self cancelPending]; self.lotteryID = identifier;
    self.phase = DY778LuckyAvailable;
    NSTimeInterval remain = [self remainingForLottery:lottery]; self.deadline = remain > 0 ? CACurrentMediaTime() + remain : 0;
    [self readConditions:lottery];
    self.status = self.paused ? @"本场已暂停" : @"发现福袋";
    self.detail = @"一键参与会提交本场口令并完成免费报名，结果以抖音确认为准。";
    [self participationChanged:fragment];
    if ([self attempted] && self.phase != DY778LuckyJoined) {
        self.phase = DY778LuckyManual; self.status = @"本场已处理";
        self.detail = @"这场福袋已处理过。可打开官方页面核对进度，助手不会重复提交。";
    }
    [self emit];
    if (!DY778Bool(@"lucky.enabled") || self.paused || ![self contextValid] || self.phase == DY778LuckyJoined) return;
    [self announce:@"found" message:[NSString stringWithFormat:@"发现福袋 · %@", self.prizeTitle]];
    [self considerAutoJoin]; [self showDiscoveryPrompt];
}
- (void)considerAutoJoin {
    if (!DY778Bool(@"lucky.enabled")) return;
    [self refreshFanEligibility];
    if ([DY778String(@"lucky.mode") isEqual:@"auto"] && self.phase == DY778LuckyAvailable &&
        ![self attempted] && ![self ownsVisiblePanel] && self.host.presentedViewController == nil)
        [self scheduleJoin];
}
- (void)showDiscoveryPrompt {
    if (!DY778Bool(@"lucky.enabled")) return;
    NSString *key = [self key];
    if (!DY778Bool(@"lucky.prompt") || [DY778String(@"lucky.mode") isEqual:@"auto"] || self.paused ||
        self.phase != DY778LuckyAvailable || ![self contextValid] || !key.length ||
        [self.announcedKey isEqual:key] || [self.history[key][@"muted"] boolValue] || [self attempted]) return;
    if ([self ownsVisiblePanel] || self.host.presentedViewController) return;
    self.announcedKey = key;
    [self announce:@"awaiting-confirmation" message:@"福袋已准备好 · 请确认本场参与条件"];
    if (DY778Bool(@"lucky.haptics")) [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self presentFrom:self.host prompt:YES];
}
- (void)lotteryEnded:(id)fragment {
    if (fragment != self.fragment) return;
    [self cancelPending]; self.phase = DY778LuckyEnded; self.status = @"本场已结束";
    self.detail = @"开奖已结束，结果请查看官方福袋页面。下一场开始后会继续留意。"; self.deadline = 0;
    [self announce:@"ended" message:@"本场福袋已结束 · 请查看官方开奖结果"]; [self emit];
}
- (void)participationChanged:(id)fragment {
    if (!DY778Bool(@"lucky.enabled") || fragment != self.fragment || !self.lotteryID.length || self.phase == DY778LuckyEnded) return;
    if (DY778LiveCallBool(fragment, @"userHasParticipatedCurrentVote")) {
        BOOL wasJoined = self.phase == DY778LuckyJoined;
        id owned = self.openedPanelByAssistant && !self.quietToken.length ? self.openedPanel : nil;
        [self cancelPending]; self.phase = DY778LuckyJoined; self.status = @"已参与福袋";
        self.detail = @"抖音已确认本场参与状态。安心等待开奖，结果会在官方页面显示。";
        if (!wasJoined) {
            [self remember:@"joined" phrase:NO];
            [self announce:@"joined" message:@"报名已确认 · 等待平台开奖"];
            [self recordProbe:@"平台已确认参与状态"];
            if (DY778Bool(@"lucky.enabled") && DY778Bool(@"lucky.haptics")) [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
        }
        [self emit];
        if (owned && !wasJoined) {
            self.openedPanel = owned; self.openedPanelByAssistant = YES;
            [self closeOwnedOfficialPanel];
        }
    }
}
- (void)closeOwnedOfficialPanel {
    if (self.quietToken.length) { [self cancelPending]; return; }
    id panel = self.openedPanel;
    BOOL own = self.openedPanelByAssistant && panel && panel == DY778Read(self.fragment, @"hybridLotteryPanel");
    self.openedPanel = nil; self.openedPanelByAssistant = NO;
    if (own && DY778LiveCanCall(panel, @"dismissWithAnimated:completion:", "v", "B@")) {
        @try { ((void (*)(id, SEL, BOOL, id))objc_msgSend)(panel, NSSelectorFromString(@"dismissWithAnimated:completion:"), !UIAccessibilityIsReduceMotionEnabled(), nil); }
        @catch (__unused NSException *exception) {}
    }
}
- (BOOL)quietRequestValid {
    return self.quietToken.length && [self.quietToken isEqual:self.activeWebToken] &&
        DY778Bool(@"lucky.enabled") && [DY778String(@"lucky.mode") isEqual:@"auto"] && !self.paused &&
        [self requestValid] && (self.phase == DY778LuckyOpening || self.phase == DY778LuckySubmitted);
}
- (BOOL)attachQuietController:(UIViewController *)controller router:(id)router schema:(id)schema context:(id)context completion:(id)completion {
    if (![self quietRequestValid] || !self.quietCreating || self.quietController ||
        ![controller isKindOfClass:UIViewController.class]) return NO;
    NSString *selector = @"_addChildViewController:fromVC:targetView:animated:context:completion:";
    if (!DY778LiveCanCall(router, selector, "v", "@@@B@@") ||
        !DY778LiveCanCall(router, @"getQueryItemsWithSchema:", "@", "@")) return NO;
    UIViewController *host = self.host;
    if (controller == host || controller.parentViewController || controller.presentingViewController ||
        !host.view.window || CGRectIsEmpty(host.view.bounds)) return NO;
    NSString *token = self.quietToken; NSUInteger generation = self.generation;
    DY778LuckyQuietHostController *parent = [DY778LuckyQuietHostController new];
    UIView *container = parent.view; container.frame = host.view.bounds;
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.quietPanel = controller; self.quietController = controller; self.quietParent = parent;
    self.quietFragment = self.fragment; self.quietContainer = container;
    [host addChildViewController:parent];
    [parent beginAppearanceTransition:YES animated:NO];
    [host.view insertSubview:container atIndex:0];
    [parent didMoveToParentViewController:host]; [parent endAppearanceTransition];
    id parameters = ((id (*)(id,SEL,id))objc_msgSend)(router,NSSelectorFromString(@"getQueryItemsWithSchema:"),schema);
    if (parameters) DY778Write(router,@"routerParams",parameters);
    ((void (*)(id,SEL,id,id,id,BOOL,id,id))objc_msgSend)(router,NSSelectorFromString(selector),controller,parent,container,NO,context,completion);
    if (generation != self.generation || ![token isEqual:self.quietToken]) return NO;
    controller.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container setNeedsLayout]; [container layoutIfNeeded];
    if (controller.parentViewController != parent || controller.view.window != host.view.window) return NO;
    [self recordProbe:@"本场报名容器已挂载，已保留官方页面展示生命周期"];
    [self queuePoll:self.generation]; return YES;
}
- (void)captureQuietPanel:(id)panel {
    if (![self quietRequestValid] || !self.quietController || !panel) return;
    id controller = panel == self.quietController ? panel : DY778LiveObject(panel,@"viewControllerOfContainer");
    if (!controller) controller = DY778LiveObject(panel,@"bdxBase");
    if (controller == self.quietController) self.quietPanel = panel;
}
- (void)removeQuietPanel {
    UIViewController *controller = self.quietController;
    UIViewController *parent = self.quietParent;
    UIView *container = self.quietContainer; id fragment = self.quietFragment, panel = self.quietPanel;
    BOOL ownsRequest = self.quietToken.length && [self.quietToken isEqual:objc_getAssociatedObject(fragment,&DY778LuckyQuietRequestKey)];
    self.quietPanel = nil;
    self.quietController = nil; self.quietParent = nil; self.quietContainer = nil; self.quietFragment = nil;
    self.quietCreating = NO; self.quietToken = nil;
    if (ownsRequest && (!DY778Read(fragment,@"hybridLotteryPanel") || DY778Read(fragment,@"hybridLotteryPanel") == panel)) {
        DY778Write(fragment,@"hybridLotteryPanel",nil); DY778Write(fragment,@"lotteryPannelViewShowing",@NO);
    }
    if (parent && controller.parentViewController == parent) {
        [controller beginAppearanceTransition:NO animated:NO];
        [controller willMoveToParentViewController:nil];
        [controller.viewIfLoaded removeFromSuperview]; [controller removeFromParentViewController];
        [controller endAppearanceTransition];
    }
    if (parent.parentViewController) {
        [parent beginAppearanceTransition:NO animated:NO];
        [parent willMoveToParentViewController:nil];
        [parent.viewIfLoaded removeFromSuperview]; [parent removeFromParentViewController];
        [parent endAppearanceTransition];
    }
    [container removeFromSuperview];
}
- (void)userOpenedLottery:(id)fragment {
    if (fragment == self.fragment && (self.quietToken.length || self.phase == DY778LuckyScheduled)) {
        [self cancelPending]; self.phase = DY778LuckyManual; self.status = @"已打开官方福袋";
        self.detail = @"本场已交给官方页面处理，助手不再重复提交。"; [self emit];
    }
    objc_setAssociatedObject(fragment,&DY778LuckyQuietRequestKey,nil,OBJC_ASSOCIATION_COPY_NONATOMIC);
}
- (void)recordProbe:(NSString *)status {
    if (!status.length || [status isEqual:self.lastProbeStatus]) return;
    self.lastProbeStatus = status;
    [self recordStage:@"participation-check" message:status];
}
- (void)webAppeared:(WKWebView *)web {
    if (![web isKindOfClass:WKWebView.class] || !web.window) return;
    objc_setAssociatedObject(web, &DY778LuckyWebAttachedKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!DY778Bool(@"lucky.enabled") || ![self requestValid] || !self.activeWebToken.length ||
        (self.phase != DY778LuckyOpening && self.phase != DY778LuckySubmitted)) return;
    if (self.requestScene && web.window.windowScene != self.requestScene) return;
    [self.webCandidates addObject:web]; [self queuePoll:self.generation];
}
- (void)webReady:(WKWebView *)web {
    if (![web isKindOfClass:WKWebView.class]) return;
    objc_setAssociatedObject(web, &DY778LuckyWebReadyKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!DY778Bool(@"lucky.enabled") || ![self requestValid] || !self.activeWebToken.length ||
        (self.phase != DY778LuckyOpening && self.phase != DY778LuckySubmitted)) return;
    if (web.window && self.requestScene && web.window.windowScene != self.requestScene) return;
    [self.webCandidates addObject:web];
    [self recordProbe:@"已收到官方网页加载回调，正在匹配本场参与按钮"];
    [self queuePoll:self.generation];
}
- (void)cancelPending {
    self.openedPanel = nil; self.openedPanelByAssistant = NO;
    self.generation++; self.pollGeneration = NSNotFound; self.presentationDeadline = 0; self.scheduledAt = 0; self.openedAt = 0; self.evaluating = NO; self.openingAuthorized = NO; self.pendingManual = NO;
    NSMutableArray<WKWebView *> *webs = [NSMutableArray array];
    if (self.activeWebView) [webs addObject:self.activeWebView];
    if (self.evaluatingWebView && ![webs containsObject:self.evaluatingWebView]) [webs addObject:self.evaluatingWebView];
    NSString *token = self.activeWebToken; self.evaluatingWebView = nil;
    self.activeWebView = nil; self.activeWebToken = nil; [self.webCandidates removeAllObjects]; self.requestScene = nil;
    if (webs.count && token.length) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:@[token] options:0 error:nil];
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *js = [NSString stringWithFormat:@"(function(k){(window.__cgnLuckyCancelled||(window.__cgnLuckyCancelled=Object.create(null)))[k]=true;})(%@ [0]);", json];
        for (WKWebView *web in webs) [web evaluateJavaScript:js inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:nil];
    }
    [self removeQuietPanel];
}
- (void)ensureTimer {
    if (self.timer || !DY778Bool(@"lucky.enabled") || !self.host || self.backgrounded) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    self.timer.tolerance = 0.15; [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)background {
    self.backgrounded = YES; [self cancelPending]; [self resetEligibility]; [self.timer invalidate]; self.timer = nil;
    if (self.phase == DY778LuckyOpening || self.phase == DY778LuckyScheduled || self.phase == DY778LuckySubmitted) {
        self.phase = DY778LuckyManual; self.status = @"操作已暂停";
        self.detail = @"应用进入后台，待执行操作已取消。返回后可打开官方页面核对。";
        [self recordProbe:@"应用进入后台，操作已停止"];
    }
    [self.card removeFromSuperview]; [self emit];
}
- (void)foreground {
    self.backgrounded = NO; [self ensureTimer];
    if (self.host) [self enterHost:self.host]; else [self discoverVisibleRoom];
}
- (void)preferencesChanged {
    if (!DY778Bool(@"lucky.enabled")) [self closeOwnedOfficialPanel];
    [self cancelPending]; [self resetEligibility];
    if (!DY778Bool(@"lucky.enabled")) {
        self.session++; self.announcedKey = nil;
        DY778DismissToast(@"lucky");
        [self.panel dismissViewControllerAnimated:NO completion:nil]; self.panel = nil;
        [self.timer invalidate]; self.timer = nil; [self.card removeFromSuperview]; self.card = nil;
        self.phase = DY778LuckyIdle; self.status = @"福袋助手未开启"; self.detail = @"可在 DY778 设置中开启福袋助手。";
    } else {
        id lottery = DY778Read(DY778Read(self.fragment, @"store"), @"currentLottery");
        [self readConditions:lottery];
        if (self.phase == DY778LuckyScheduled || self.phase == DY778LuckyOpening || self.phase == DY778LuckySubmitted) {
            self.phase = DY778LuckyManual; self.status = @"设置已更新"; self.detail = @"待执行操作已取消，请确认本场状态后继续。";
        } else if (self.phase == DY778LuckyIdle && self.lotteryID.length) {
            self.phase = DY778LuckyAvailable; self.status = @"发现福袋"; self.detail = @"设置已更新，可以参与当前福袋。";
        }
        [self ensureTimer]; [self discoverVisibleRoom];
    }
    [self emit];
}
- (void)togglePause {
    self.paused = !self.paused; [self cancelPending];
    if (self.paused) { self.status = @"本场已暂停"; self.detail = @"助手已暂停，本场不会再自动提交口令或点击参与。"; }
    else {
        self.phase = [self attempted] ? DY778LuckyManual : DY778LuckyAvailable;
        self.status = @"本场已继续"; self.detail = @"助手已恢复。你可以点击参与，或打开官方页面查看状态。";
        [self participationChanged:self.fragment];
    }
    [self emit];
}
- (NSString *)countdown {
    if (!self.roomID.length) return @"等待直播";
    if (!self.lotteryID.length) return @"留意下一场福袋";
    if (self.paused) return @"点按可继续";
    if (self.phase == DY778LuckyEnded) return @"等待下一场";
    if (self.scheduledAt > CACurrentMediaTime()) return [NSString stringWithFormat:@"%.0f 秒后开始", ceil(self.scheduledAt - CACurrentMediaTime())];
    if (self.deadline <= 0) return @"等待平台开奖";
    NSInteger seconds = MAX(0, (NSInteger)ceil(self.deadline - CACurrentMediaTime()));
    return [NSString stringWithFormat:@"%02ld:%02ld 后开奖", (long)(seconds / 60), (long)(seconds % 60)];
}
- (void)tick {
    if (!DY778Bool(@"lucky.enabled") || self.backgrounded) return;
    if (!self.host) { [self discoverVisibleRoom]; if (!self.host) { [self leaveHost:nil]; return; } }
    if (self.host && DY778LiveHostRoomID(self.host).length && ![self.roomID isEqual:DY778LiveHostRoomID(self.host)]) { [self enterHost:self.host]; return; }
    if (self.host && ![self.accountID isEqual:(DY778CurrentAccountID() ?: @"")]) { [self enterHost:self.host]; return; }
    if (self.fragment && ![self.lotteryID isEqual:DY778LotteryID(DY778Read(DY778Read(self.fragment, @"store"), @"currentLottery"))])
        [self lotteryChanged:self.fragment];
    if (![self contextValid]) {
        if (self.phase == DY778LuckyScheduled || self.phase == DY778LuckyOpening || self.phase == DY778LuckySubmitted) {
            [self cancelPending]; self.phase = DY778LuckyManual; self.status = @"等待回到直播间";
            self.detail = @"当前直播间不可见，待执行操作已取消。";
        }
        self.card.hidden = YES; [self.panel refresh]; return;
    }
    [self synchronizeCountdown];
    if (self.deadline > 0 && CACurrentMediaTime() >= self.deadline && self.phase != DY778LuckyEnded) [self lotteryEnded:self.fragment];
    else [self participationChanged:self.fragment];
    if (self.phase == DY778LuckyAvailable) {
        [self readConditions:DY778Read(DY778Read(self.fragment,@"store"),@"currentLottery")]; [self considerAutoJoin];
    }
    [self emit]; [self showDiscoveryPrompt];
}
- (void)emit {
    BOOL show = DY778Bool(@"lucky.enabled") && DY778Bool(@"lucky.showStatus") && !self.backgrounded &&
        self.host.isViewLoaded && self.host.view.window && [self contextValid] && ![self ownsVisiblePanel] &&
        self.lotteryID.length;
    if (show) {
        if (!self.card) { self.card = [[DY778LuckyCard alloc] initWithFrame:CGRectZero]; self.card.coordinator = self; }
        if (self.card.superview != self.host.view) [self.host.view addSubview:self.card];
        UIView *container = self.host.view; CGRect safe = UIEdgeInsetsInsetRect(container.bounds, container.safeAreaInsets);
        CGFloat width = DY778Bool(@"lucky.compact") ? 48 : 106, height = DY778Bool(@"lucky.compact") ? 46 : 40;
        double savedX = [DY778Preferences() doubleForKey:@"lucky.cardX"], savedY = [DY778Preferences() doubleForKey:@"lucky.cardY"];
        CGFloat x = savedX > 0 ? savedX * container.bounds.size.width : CGRectGetMaxX(safe) - width - 12;
        CGFloat y = savedY > 0 ? savedY * container.bounds.size.height : CGRectGetMinY(safe) + safe.size.height * 0.38;
        x = fmax(CGRectGetMinX(safe) + 10, fmin(x, CGRectGetMaxX(safe) - width - 10));
        y = fmax(CGRectGetMinY(safe) + 10, fmin(y, CGRectGetMaxY(safe) - height - 10));
        if (!self.card.gestureRecognizers.firstObject || self.card.gestureRecognizers.firstObject.state != UIGestureRecognizerStateChanged)
            self.card.frame = CGRectMake(x, y, width, height);
        self.card.hidden = NO; [self.card refresh];
    } else self.card.hidden = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:DY778LuckyStateChanged object:self];
}
- (void)presentFrom:(UIViewController *)source { [self presentFrom:source prompt:NO]; }
- (void)presentFrom:(UIViewController *)source prompt:(BOOL)prompt {
    if (!DY778Bool(@"lucky.enabled") || self.backgrounded) return;
    [self discoverVisibleRoom];
    if (self.panel.presentingViewController || self.panel.navigationController.presentingViewController) return;
    UIViewController *presenter = source ?: DY778TopController();
    if (!presenter || presenter.presentedViewController) return;
    DY778LuckyPanelController *panel = [DY778LuckyPanelController new]; panel.coordinator = self; panel.discoveryPrompt = prompt;
    panel.liveBound = source == self.host && self.host != nil;
    panel.boundSession = self.session; self.panel = panel;
    self.card.hidden = YES;
    if (panel.liveBound) self.presentationDeadline = CACurrentMediaTime() + 2;
    panel.modalPresentationStyle = UIModalPresentationOverFullScreen;
    panel.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [presenter presentViewController:panel animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];}
- (void)joinRequested {
    if (!DY778Bool(@"lucky.enabled") || self.paused || ![self contextValid] || !self.lotteryID.length) {
        DY778LuckyToast(@"当前福袋已变化，请回到直播间查看。"); return;
    }
    if (DY778LiveCallBool(self.fragment, @"userHasParticipatedCurrentVote")) {
        [self participationChanged:self.fragment]; [self openOfficial]; return;
    }
    self.explicitPhraseKey = [self key]; self.explicitPhraseSession = self.session;
    [self scheduleJoin];
}
- (BOOL)phraseAuthorized {
    return [DY778String(@"lucky.mode") isEqual:@"auto"] || (self.explicitPhraseSession == self.session &&
        self.explicitPhraseKey.length && [self.explicitPhraseKey isEqual:[self key]]);
}
- (void)scheduleJoin {
    if (self.paused || !DY778Bool(@"lucky.enabled") || ![self contextValid] ||
        self.phase == DY778LuckyJoined || self.phase == DY778LuckyScheduled || self.phase == DY778LuckyOpening || self.phase == DY778LuckySubmitted) return;
    if (![self eligibilityAllowsJoin]) {
        NSString *status = self.eligibilityPending ? @"正在核对参与条件" : @"本场已跳过";
        BOOL changed = ![self.status isEqual:status]; self.status = status; self.detail = self.restriction;
        if (changed) [self announce:self.eligibilityPending ? @"eligibility-pending" : @"ineligible" message:self.restriction];
        [self announceEligibilitySkip];
        [self emit]; return;
    }
    if ([DY778Read(self.fragment, @"shouldForbidInteract") boolValue]) {
        self.phase = DY778LuckyManual; self.status = @"当前暂不可参与";
        self.detail = DY778LiveString(DY778Read(self.fragment, @"fobidInteractToast"));
        if (!self.detail.length) self.detail = @"直播间暂时限制了互动，请在官方页面查看。";
        [self announce:@"interaction-limited" message:self.detail]; [self emit]; return;
    }
    [self cancelPending];
    self.attemptedKey = [self key]; self.attemptedSession = self.session;
    double delay = DY778Number(@"lucky.delay"); if (!isfinite(delay)) delay = 1.2;
    delay = fmax(0.3, fmin(5, delay));
    self.commentRetries = 0; self.confirmationRefreshes = 0; self.confirmationRefreshedAt = 0;
    self.phase = DY778LuckyScheduled; self.status = @"准备参与"; self.scheduledAt = CACurrentMediaTime() + delay;
    self.detail = self.phrase.length && [self phraseAuthorized] ? [NSString stringWithFormat:@"稍后发送一次评论：%@\n随后提交本场报名。", self.phrase] : @"即将提交本场免费报名。";
    [self announce:@"scheduled" message:@"已确认本场 · 正在准备参与"];
    NSUInteger generation = self.generation; [self emit];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DY778LuckyCoordinator *c = weakSelf;
        if (!c || c.generation != generation || c.paused || !DY778Bool(@"lucky.enabled") || ![c contextValid]) return;
        [c performJoinForGeneration:generation];
    });
}
- (BOOL)submitPhraseIfNeeded {
    if (![self eligibilityAllowsJoin]) return NO;
    if (!self.phrase.length) return YES;
    if (![self phraseAuthorized]) return YES;
    if ([self.history[[self key] ?: @""][@"phrase"] boolValue]) return YES;
    id comment = [self resolveCommentSender];
    if (!comment || [objc_getAssociatedObject(comment, &DY778LuckyComponentMountKey) doubleValue] <= 0 ||
        ![DY778FragmentRoomID(comment) isEqual:self.roomID] ||
        ![(objc_getAssociatedObject(comment, &DY778LuckyComponentAccountKey) ?: @"__unbound__") isEqual:self.accountID]) {
        self.detail = @"当前直播间的评论组件尚未就绪，请在官方页面发送口令。"; return NO;
    }
    id injector = DY778LiveObject(comment, @"injector");
    id draftOwner = injector ?: comment;
    if (self.comment && [self.roomID isEqual:DY778FragmentRoomID(self.comment)] && !injector) draftOwner = self.comment;
    id store = DY778Read(draftOwner, @"store");
    if (!store && DY778LiveCanCall(comment,@"sendCommentWithCommentContext:completion:","v","@@")) store = comment;
    if (DY778LiveCallBool(comment, @"commentForbidden") || [DY778Read(store, @"isBanned") boolValue] || [DY778Read(store, @"isForbidden") boolValue] ||
        [DY778Read(store, @"disableComment") boolValue] || [DY778Read(store, @"disableInputComment") boolValue]) {
        self.detail = @"当前直播间限制了评论，无法自动提交口令。"; return NO;
    }
    NSUInteger draftBudget = 250;
    if (DY778LiveHasEditingDraft(self.host.view, &draftBudget) || [DY778Read(draftOwner, @"keyboardShown") boolValue] || DY778LiveCallBool(comment, @"isFirstResponder") ||
        DY778LiveCallBool(draftOwner, @"isFirstResponder") || DY778LiveString(DY778Read(DY778Read(draftOwner, @"commentContext"), @"plainText")).length) {
        self.detail = @"你正在编辑评论，助手保留了草稿。请完成编辑后在官方页面参与。"; return NO;
    }
    BOOL direct = DY778LiveCanCall(comment, @"sendComment:commentContext:completion:", "v", "@@@");
    BOOL servicePath = DY778LiveCanCall(comment, @"sendComment:enterSource:requestSource:trackParams:completion:", "v", "@q@@@");
    BOOL storePath = DY778LiveCanCall(comment,@"sendCommentWithCommentContext:completion:","v","@@");
    if (!direct && !servicePath && !storePath) { self.detail = @"当前评论发送接口不可用，请在官方页面发送口令。"; return NO; }
    @try {
        id context = nil;
        if (direct || storePath) {
            Class contextClass = NSClassFromString(@"IESLiveCommentContext"); SEL initSelector = NSSelectorFromString(@"initWithState:enterSource:type:");
            if (!DY778LiveSignature(contextClass, initSelector, "@", "qqq")) { self.detail = @"口令发送上下文尚未就绪。"; return NO; }
            id<DY778LuckyContextInitializing> allocated = [contextClass alloc];
            context = [allocated initWithState:0 enterSource:0 type:0];
            BOOL valid = DY778Write(context, @"publicScreenID", @(-1));
            valid = DY778Write(context, @"publicScreenType", @0) && valid;
            valid = DY778Write(context, @"currentState", @1) && valid;
            valid = DY778Write(context, @"plainText", self.phrase) && valid;
            valid = DY778Write(context, @"displayedText", [[NSAttributedString alloc] initWithString:self.phrase]) && valid;
            if (!valid) { self.detail = @"口令发送上下文尚未就绪。"; return NO; }
        }
        if (![self contextValid] || ![self phraseAuthorized]) return NO;
        [self remember:@"phrase-submitted" phrase:YES];
        [self recordProbe:@"正在提交本场口令"];
        [self announce:@"phrase-submitted" message:@"正在提交本场口令"];
        if (direct) ((void (*)(id, SEL, id, id, id))objc_msgSend)(comment, NSSelectorFromString(@"sendComment:commentContext:completion:"), self.phrase, context, nil);
        else if (storePath) ((void (*)(id,SEL,id,id))objc_msgSend)(comment,NSSelectorFromString(@"sendCommentWithCommentContext:completion:"),context,nil);
        else ((void (*)(id, SEL, id, long long, id, id, id))objc_msgSend)(comment,
            NSSelectorFromString(@"sendComment:enterSource:requestSource:trackParams:completion:"), self.phrase, 0, nil, @{}, nil);
        [self recordProbe:@"口令已提交"];
        [self announce:@"phrase-awaiting" message:@"口令已提交 · 正在继续参与"];
        return YES;
    } @catch (__unused NSException *exception) {
        self.detail = @"口令提交未完成，请在官方页面核对。";
        [self recordProbe:@"口令提交异常"];
        return NO;
    }
}
- (void)performJoinForGeneration:(NSUInteger)generation {
    if (![self contextValid] || self.generation != generation || self.paused || !DY778Bool(@"lucky.enabled")) return;
    if (![self eligibilityAllowsJoin]) {
        [self cancelPending]; self.phase = DY778LuckyAvailable;
        self.attemptedKey = nil; self.status = @"等待参与资格确认"; [self emit]; return;
    }
    BOOL automatic = [DY778String(@"lucky.mode") isEqual:@"auto"];
    if (automatic && [self ownsVisiblePanel]) {
        [self cancelPending]; self.phase = DY778LuckyManual; self.status = @"已打开福袋面板";
        self.detail = @"本场已有打开的面板，助手不会接管你的操作。"; [self emit]; return;
    }
    if (automatic && !DY778LuckyQuietHooksReady) {
        [self cancelPending]; self.phase = DY778LuckyManual; self.status = @"静默报名暂不可用";
        self.detail = @"当前版本未提供可用的静默容器，本场已跳过。"; [self emit]; return;
    }
    self.scheduledAt = 0;
    if (!DY778LiveCanCall(self.fragment, @"openLotteryPage", "v", "")) {
        self.phase = DY778LuckyManual; self.status = @"请手动打开福袋";
        self.detail = @"当前版本没有可用的福袋打开接口，请点击直播间原有福袋图标。";
        [self announce:@"open-unavailable" message:self.detail]; [self emit]; return;
    }
    unsigned plan = DY778LuckyParticipationPlan(DY778Bool(@"lucky.enabled"), [self contextValid], self.paused,
        self.phrase.length > 0, [self phraseAuthorized], [self.history[[self key] ?: @""][@"phrase"] boolValue],
        self.needsManualConditions, YES);
    if (!(plan & DY778LuckyPlanOpen)) return;
    if ((plan & DY778LuckyPlanPhrase) && ![self resolveCommentSender] && self.commentRetries++ < 6) {
        self.status = @"正在连接本场评论"; self.detail = @"正在等待当前直播间的评论服务就绪。";
        [self announce:@"comment-resolving" message:@"正在连接本场评论 · 请稍候"]; [self emit];
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DY778LuckyCoordinator *c = weakSelf;
            if (c && c.generation == generation && [c contextValid]) [c performJoinForGeneration:generation];
        });
        return;
    }
    if ((plan & DY778LuckyPlanPhrase) && ![self submitPhraseIfNeeded]) {
        self.phase = DY778LuckyManual; self.status = @"口令需要手动处理";
        [self announce:@"phrase-manual" message:self.detail];
        if (!automatic) [self openOfficial];
        else [self cancelPending];
        [self emit]; return;
    }
    if (plan & DY778LuckyPlanPhrase) {
        self.status = @"口令已提交"; self.detail = @"正在同步参与条件，随后提交本场报名。"; [self emit];
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            DY778LuckyCoordinator *c = weakSelf;
            if (c && c.generation == generation && [c contextValid]) [c performJoinForGeneration:generation];
        });
        return;
    }
    self.phase = DY778LuckyOpening; self.status = @"正在提交报名";
    [self announce:@"opening" message:automatic ? @"正在静默处理本场报名" : @"正在打开本场官方福袋页面"];
    self.detail = @"正在提交本场免费报名，参与结果等待抖音确认。";
    self.confirmationRefreshes = 0; self.confirmationRefreshedAt = 0; self.joinActionSent = NO; self.openedAt = CACurrentMediaTime();
    self.webCandidates = [NSHashTable weakObjectsHashTable]; self.probeIndex = 0; self.lastProbeStatus = nil;
    self.requestScene = self.host.view.window.windowScene;
    self.activeWebToken = [NSString stringWithFormat:@"%@/%lu", [self key], (unsigned long)generation];
    self.quietToken = automatic ? self.activeWebToken : nil;
    self.quietFragment = automatic ? self.fragment : nil;
    objc_setAssociatedObject(self.fragment,&DY778LuckyQuietRequestKey,self.quietToken,OBJC_ASSOCIATION_COPY_NONATOMIC);
    self.openedPanelByAssistant = ![DY778Read(self.fragment, @"lotteryPannelViewShowing") boolValue] && ![self ownsVisiblePanel];
    self.openedPanel = nil;
    self.openingAuthorized = YES; self.presentationDeadline = automatic ? 0 : CACurrentMediaTime() + 42;
    [self remember:@"opened" phrase:NO];
    @try { if (![DY778Read(self.fragment, @"lotteryPannelViewShowing") boolValue]) DY778LiveCallVoid(self.fragment, @"openLotteryPage"); }
    @catch (__unused NSException *exception) {
        self.openingAuthorized = NO; [self cancelPending]; self.phase = DY778LuckyManual;
        self.status = @"福袋页面未打开"; self.detail = @"请点击直播间原有福袋图标重试。";
        [self announce:@"open-failed" message:self.detail]; [self emit]; return;
    }
    self.openingAuthorized = NO;
    if (self.openedPanelByAssistant) self.openedPanel = DY778Read(self.fragment, @"hybridLotteryPanel");
    if (self.generation != generation) return;
    self.pendingManual = (plan & DY778LuckyPlanManual) != 0;
    [self emit]; [self queuePoll:generation];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 44 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DY778LuckyCoordinator *c = weakSelf;
        if (c.generation == generation && (c.phase == DY778LuckyOpening || c.phase == DY778LuckySubmitted)) [c finishUnconfirmed];
    });
}
- (void)queuePoll:(NSUInteger)generation {
    if (generation != self.generation || (self.phase != DY778LuckyOpening && self.phase != DY778LuckySubmitted)) return;
    if (self.pollGeneration == generation) return;
    self.pollGeneration = generation;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DY778LuckyCoordinator *c = weakSelf;
        if (!c || c.generation != generation) return;
        if (c.pollGeneration == generation) c.pollGeneration = NSNotFound;
        if (c.paused || !DY778Bool(@"lucky.enabled") || ![c requestValid]) return;
        [c poll:generation];
    });
}
- (void)finishUnconfirmed {
    BOOL submitted = self.phase == DY778LuckySubmitted;
    BOOL quiet = self.quietToken.length > 0;
    [self cancelPending]; self.phase = DY778LuckyManual;
    self.status = quiet ? @"本场未确认参与" : submitted ? @"等待平台确认" : @"请在页面内参与";
    self.detail = quiet ? @"本场尚未取得抖音的参与确认，助手已停止。可自行打开官方福袋核对状态。" : submitted ? @"参与操作已提交，但尚未取得抖音的参与确认。请以官方页面显示为准，助手不会重复点击。" :
        @"当前福袋页面未出现可确认的免费参与按钮。可直接在官方页面操作，助手已停止尝试。";
    [self announce:submitted ? @"unconfirmed" : @"manual" message:submitted ? @"尚未确认报名 · 请查看福袋" : @"未完成报名 · 请查看剩余条件"]; [self emit];
}
- (void)poll:(NSUInteger)generation {
    if (!DY778Bool(@"lucky.enabled") || self.paused || self.evaluating || self.generation != generation || ![self requestValid]) return;
    if (self.quietToken.length && ![self contextValid]) { [self cancelPending]; return; }
    if (self.needsManualConditions) { [self finishUnconfirmed]; return; }
    [self participationChanged:self.fragment]; if (self.generation != generation || self.phase == DY778LuckyJoined) return;
    if (DY778LuckyRequestExpired(self.openedAt, CACurrentMediaTime())) { [self finishUnconfirmed]; return; }
    if (self.phase == DY778LuckySubmitted && DY778LuckyShouldRefreshParticipation(self.confirmationRefreshes,
        self.confirmationRefreshedAt, CACurrentMediaTime())) {
        self.confirmationRefreshes++; self.confirmationRefreshedAt = CACurrentMediaTime();
        DY778LiveCallVoid(DY778LiveObject(self.fragment,@"store"),@"p_fetchLotteryInfo");
        if (generation != self.generation || ![self requestValid]) return;
    }
    id panel = DY778LiveObject(self.fragment, @"hybridLotteryPanel");
    UIView *view = self.quietToken.length ? self.quietContainer : DY778LuckyPanelView(panel);
    if (self.openedPanelByAssistant && !self.openedPanel) self.openedPanel = panel;
    if (self.pendingManual) { [self finishUnconfirmed]; return; }

    NSMutableArray<WKWebView *> *candidates = [NSMutableArray array];
    if (DY778LuckyWebVisible(self.activeWebView)) [candidates addObject:self.activeWebView];
    NSMutableArray *validCandidates = [NSMutableArray array];
    for (WKWebView *web in self.webCandidates.allObjects)
        if (DY778LuckyWebVisible(web) && ![candidates containsObject:web]) [validCandidates addObject:web];
    [candidates addObjectsFromArray:validCandidates];
    [self.webCandidates removeAllObjects];
    for (WKWebView *web in validCandidates) [self.webCandidates addObject:web];
    NSUInteger budget = 1200;
    DY778LuckyCollectWebViews(view, 0, &budget, candidates);
    if (!self.quietToken.length && !DY778LuckyWebVisible(self.activeWebView)) {
        UIView *topView = DY778TopController().viewIfLoaded;
        if (!self.requestScene || topView.window.windowScene == self.requestScene) DY778LuckyCollectWebViews(topView, 0, &budget, candidates);
        NSArray *windows = self.requestScene.windows ?: (self.host.view.window ? @[self.host.view.window] : @[]);
        for (UIWindow *window in windows.reverseObjectEnumerator) {
            if (window.hidden || window.alpha < .01 || window.windowLevel > UIWindowLevelNormal) continue;
            DY778LuckyCollectWebViews(window, 0, &budget, candidates);
            if (!budget) break;
        }
    }
    NSMutableArray<WKWebView *> *visible = [NSMutableArray array];
    for (WKWebView *web in candidates)
        if (DY778LuckyWebVisible(web) && (!self.requestScene || web.window.windowScene == self.requestScene) &&
            (!self.quietToken.length || [web isDescendantOfView:self.quietContainer])) [visible addObject:web];
    WKWebView *web = self.activeWebView && [visible containsObject:self.activeWebView] ? self.activeWebView :
        (visible.count ? visible[self.probeIndex++ % visible.count] : nil);
    if (!web) {
        if (!self.quietToken.length && !view.window) {
            UIViewController *top = DY778TopController();
            if (!self.requestScene || top.view.window.windowScene == self.requestScene) view = top.viewIfLoaded;
        }
        BOOL pageSubmitted = NO, paymentRequired = NO;
        NSArray<DY778LuckyJoinTarget *> *targets = view.window ? DY778LuckyNativeTargets(view,&pageSubmitted,&paymentRequired) : @[];
        DY778LuckyJoinTarget *target = targets.count == 1 ? targets.firstObject : nil;
        if (target && !self.joinActionSent && DY778LuckyCanActivate([self requestValid], DY778LuckyVisibleInPanel(target.view,view), target.enabled,
            (unsigned)targets.count, NO, paymentRequired, DY778LuckyButtonJoin)) {
            @try { DY778LuckyActivateTarget(target,view,^{
                self.joinActionSent = YES; self.phase = DY778LuckySubmitted;
                [self remember:@"submitted" phrase:NO]; [self recordProbe:@"已执行官方原生参与按钮，等待参与确认"];
            }); } @catch (__unused NSException *exception) { [self recordProbe:@"原生参与操作未完成，正在继续匹配页面"]; }
        } else if (pageSubmitted) [self recordProbe:@"官方页面显示已参与，正在核对平台状态"];
        else [self recordProbe:@"等待官方参与页面完成挂载"];
        [self queuePoll:generation]; return;
    }
    if (web.isLoading) { [self queuePoll:generation]; return; }
    NSNumber *ready = objc_getAssociatedObject(web, &DY778LuckyWebReadyKey);
    NSNumber *attached = objc_getAssociatedObject(web, &DY778LuckyWebAttachedKey);
    if (!ready) { ready = @(CACurrentMediaTime()); objc_setAssociatedObject(web, &DY778LuckyWebReadyKey, ready, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if (CACurrentMediaTime() - ready.doubleValue < 0.3) { [self queuePoll:generation]; return; }
    BOOL ownerBound = view && (web == view || [web isDescendantOfView:view]);
    BOOL requestBound = ready.doubleValue >= self.openedAt || attached.doubleValue >= self.openedAt;
    NSDictionary *parameters = @{@"room":self.roomID, @"lottery":self.lotteryID, @"token":self.activeWebToken,
        @"hasPhrase":@(self.phrase.length > 0), @"phraseSubmitted":@([self.history[[self key] ?: @""][@"phrase"] boolValue]),
        @"ownerBound":@(ownerBound), @"requestBound":@(requestBound), @"deadline":@((NSDate.date.timeIntervalSince1970 + 3) * 1000)};
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:nil];
    if (!jsonData) { [self finishUnconfirmed]; return; }
    NSString *script = [NSString stringWithFormat:@"(%@)(%@)",DY778LuckyJoinFunction,[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]];
    self.evaluating = YES; self.evaluatingWebView = web;
    __weak typeof(self) weakSelf = self;
    [web evaluateJavaScript:script inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id result,NSError *error) {
        DY778LuckyCoordinator *c = weakSelf;
        if (!c || c.generation != generation) return;
        c.evaluating = NO; c.evaluatingWebView = nil;
        if (![c requestValid] || c.paused || !DY778Bool(@"lucky.enabled")) { [c cancelPending]; return; }
        NSString *status = DY778LiveString(result);
        if (error) {
            [c recordProbe:[NSString stringWithFormat:@"网页执行返回错误 %ld，正在重试",(long)error.code]];
        } else if ([@[@"clicked",@"submitted",@"already",@"waiting",@"manual"] containsObject:status]) {
            c.activeWebView = web;
            if ([@[@"clicked",@"submitted",@"already"] containsObject:status]) {
                c.joinActionSent = YES; c.phase = DY778LuckySubmitted;
                c.status = [status isEqual:@"already"] ? @"页面显示已参与" : @"正在确认参与结果";
                c.detail = @"正在核对平台状态；参与按钮仍未响应时会自动补试。";
                if ([status isEqual:@"clicked"]) [c remember:@"submitted" phrase:NO];
                [c recordProbe:[status isEqual:@"already"] ? @"官方网页显示参与成功，等待原生确认" :
                    [status isEqual:@"clicked"] ? @"已完整触发官方参与按钮的点击与触摸事件" : @"参与操作已发送，等待页面状态更新"];
                [c emit];
            } else [c recordProbe:[status isEqual:@"manual"] ? @"已找到福袋页面，等待可直接参与的按钮" : @"已找到福袋页面，等待按钮就绪"];
        } else {
            if (c.activeWebView == web) c.activeWebView = nil;
            [c recordProbe:[status isEqual:@"context"] ? @"页面场次不匹配，正在查找当前福袋" :
                [status isEqual:@"page-missing"] ? @"页面未找到参与容器" : @"此网页尚未出现福袋按钮，继续检查其他页面"];
        }
        [c queuePoll:generation];
    }];
}
- (void)openOfficial {
    if (![self contextValid] || !self.lotteryID.length) {
        DY778LuckyToast(@"当前福袋已变化，请回到直播间查看。"); return;
    }
    [self cancelPending];
    objc_setAssociatedObject(self.fragment,&DY778LuckyQuietRequestKey,nil,OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (DY778LiveCanCall(self.fragment, @"openLotteryPage", "v", "")) {
        self.phase = DY778LuckyManual; self.status = @"请在官方页面参与";
        self.detail = @"已请求打开本场福袋。完成参与条件后，以官方页面状态为准。";
        self.presentationDeadline = CACurrentMediaTime() + 2;
        @try { DY778LiveCallVoid(self.fragment, @"openLotteryPage"); }
        @catch (__unused NSException *exception) { self.detail = @"打开失败，请点击直播间原有福袋图标。"; }
        [self emit];
    } else DY778LuckyToast(@"请点击直播间原有福袋图标。");
}
@end
@interface DY778LuckyHistoryController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@end
@implementation DY778LuckyHistoryController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"最近参与记录"; DY778StyleController(self);
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 100;
    self.tableView.backgroundColor = DY778Background(); self.tableView.showsVerticalScrollIndicator = NO;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
    self.navigationItem.rightBarButtonItem.tintColor = DY778Accent();
    [self reload];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; DY778StyleController(self); [self reload]; }
- (void)reload {
    NSString *account = DY778CurrentAccountID() ?: @""; NSMutableArray *records = [NSMutableArray new];
    for (NSDictionary *record in [DY778LuckyCoordinator shared].records)
        if ([record[@"account"] isEqual:account]) [records addObject:record];
    self.items = records;
    UILabel *empty = DY778LuckyLabel(UIFontTextStyleBody, UIColor.secondaryLabelColor);
    empty.textAlignment = NSTextAlignmentCenter; empty.text = @"还没有福袋记录\n\n开启助手并进入直播间后，\n会在这里留下发现、提交和确认进度。";
    self.tableView.backgroundView = self.items.count ? nil : empty; self.navigationItem.rightBarButtonItem.enabled = self.items.count > 0;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"只显示当前账号最近30天的记录，最多200场。已提交口令或点击参与不代表报名成功；中奖结果请查看官方页面。";
}
- (NSString *)dateText:(NSNumber *)time {
    NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateFormat = @"MM-dd HH:mm:ss";
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:time.doubleValue]];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *record = self.items[indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = DY778CardBackground(); cell.textLabel.text = record[@"prize"] ?: @"福袋";
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.numberOfLines = 0; cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@\n%@", [self dateText:record[@"updated"]], record[@"roomTitle"] ?: @"直播间", [record[@"confirmed"] boolValue] ? [@"已确认报名 · " stringByAppendingString:record[@"message"] ?: @""] : record[@"message"] ?: @"已记录"];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 0; cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.imageView.image = [UIImage systemImageNamed:[record[@"confirmed"] boolValue] ? @"checkmark.seal.fill" : @"gift.fill"];
    cell.imageView.tintColor = [record[@"confirmed"] boolValue] ? UIColor.systemGreenColor : DY778Accent();
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSDictionary *record = self.items[indexPath.row];
    UIViewController *detail = [UIViewController new]; detail.title = @"福袋记录"; DY778StyleController(detail);
    UITextView *text = [UITextView new]; text.translatesAutoresizingMaskIntoConstraints = NO; text.editable = NO;
    text.selectable = YES; text.backgroundColor = DY778Background(); text.textColor = UIColor.labelColor;
    text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; text.adjustsFontForContentSizeCategory = YES;
    text.textContainerInset = UIEdgeInsetsMake(22, 18, 28, 18); [detail.view addSubview:text];
    NSMutableString *body = [NSMutableString stringWithFormat:@"%@\n%@\n\n参与条件\n%@\n\n处理进度\n", record[@"prize"] ?: @"福袋", record[@"roomTitle"] ?: @"直播间", [record[@"conditions"] componentsJoinedByString:@"\n"] ?: @"未记录"];
    for (NSDictionary *event in record[@"events"]) [body appendFormat:@"%@  %@\n\n", [self dateText:event[@"time"]], event[@"message"] ?: @""];
    [body appendFormat:@"房间：%@\n福袋：%@\n\n这是历史记录，不会再次发送口令或提交参与。", record[@"room"] ?: @"", record[@"lottery"] ?: @""];
    text.text = body;
    [NSLayoutConstraint activateConstraints:@[[text.topAnchor constraintEqualToAnchor:detail.view.safeAreaLayoutGuide.topAnchor],
        [text.bottomAnchor constraintEqualToAnchor:detail.view.bottomAnchor], [text.leadingAnchor constraintEqualToAnchor:detail.view.leadingAnchor],
        [text.trailingAnchor constraintEqualToAnchor:detail.view.trailingAnchor]]];
    [self.navigationController pushViewController:detail animated:YES];
}
- (void)clear {
    __weak typeof(self) weakSelf = self;
    DY778Confirm(self, @"清空最近参与记录", @"清空当前账号的福袋记录。正在进行的直播操作和本场去重状态不会改变。", @"清空记录", YES, ^{
        DY778LuckyCoordinator *c = [DY778LuckyCoordinator shared]; NSString *account = DY778CurrentAccountID() ?: @"";
        NSIndexSet *indexes = [c.records indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) { return [obj[@"account"] isEqual:account]; }];
        [c.records removeObjectsAtIndexes:indexes]; [DY778Preferences() setObject:c.records forKey:@"lucky.records"]; [weakSelf reload];
    });
}
@end
static char DY778LuckyObservationPendingKey;
static char DY778LuckyObservationTimeKey;
static void DY778QueueLiveObservation(id component, BOOL isComment, BOOL service) {
    if (!component) return;
    DY778LiveMain(^{
        if (service) DY778MarkLiveComponent(component);
        if ([objc_getAssociatedObject(component, &DY778LuckyObservationPendingKey) boolValue]) return;
        double previous = [objc_getAssociatedObject(component, &DY778LuckyObservationTimeKey) doubleValue];
        if (!service && CACurrentMediaTime() - previous < 0.2) return;
        objc_setAssociatedObject(component, &DY778LuckyObservationTimeKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(component, &DY778LuckyObservationPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak id weakComponent = component;
        dispatch_async(dispatch_get_main_queue(), ^{
            id current = weakComponent; if (!current) return;
            [[DY778LuckyCoordinator shared] observeComponent:current comment:isComment service:NO];
            objc_setAssociatedObject(current, &DY778LuckyObservationPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        });
    });
}
static void DY778ObserveLotteryStore(id store) {
    id fragment = DY778Read(store, @"reaction");
    if ([fragment isKindOfClass:NSClassFromString(@"IESLiveLotteryFragment")]) DY778QueueLiveObservation(fragment, NO, NO);
}
static IMP DY778OrigCommentServiceBind, DY778OrigCommentServiceSetInjector, DY778OrigCommentServiceLaunch;
static IMP DY778OrigCommentServiceRebind, DY778OrigCommentServiceRoom, DY778OrigCommentServiceSetRoom, DY778OrigCommentServiceEnd;
static IMP DY778OrigCommentSetStore, DY778OrigCommentStoreReaction, DY778OrigCommentStoreRoom;
static IMP DY778OrigCommentStoreSetup, DY778OrigCommentStoreUpdate, DY778OrigCommentServiceReady;
static IMP DY778OrigLoaderMount, DY778OrigLoaderUnmount;
static void DY778ObserveCommentStore(id store) {
    id fragment = DY778Read(store, @"reactions");
    if (DY778LiveCommentCanSend(fragment)) DY778QueueLiveObservation(fragment, YES, YES);
    if (DY778LiveCommentCanSend(store)) DY778QueueLiveObservation(store,YES,YES);
}
static void DY778CommentStoreSetup(id self, SEL cmd) {
    ((void (*)(id,SEL))DY778OrigCommentStoreSetup)(self,cmd);
    DY778LiveMain(^{ DY778ObserveCommentStore(self); });
}
static void DY778CommentStoreUpdate(id self, SEL cmd, id room) {
    ((void (*)(id,SEL,id))DY778OrigCommentStoreUpdate)(self,cmd,room);
    DY778LiveMain(^{ DY778ObserveCommentStore(self); });
}
static void DY778CommentServiceReady(id self, SEL cmd) {
    ((void (*)(id,SEL))DY778OrigCommentServiceReady)(self,cmd);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] observeCommentService:self]; });
}
static void DY778LoaderMount(id self, SEL cmd, id component, long long level) {
    ((void (*)(id,SEL,id,long long))DY778OrigLoaderMount)(self,cmd,component,level);
    if (!DY778LiveCommentCanSend(component)) return;
    DY778LiveMain(^{
        objc_setAssociatedObject(component,&DY778LuckyComponentRoomKey,nil,OBJC_ASSOCIATION_COPY_NONATOMIC);
        NSString *room = DY778FragmentRoomID(component) ?: DY778FragmentRoomID(self);
        if (room.length) objc_setAssociatedObject(component,&DY778LuckyComponentRoomKey,room,OBJC_ASSOCIATION_COPY_NONATOMIC);
        DY778QueueLiveObservation(component,YES,YES);
    });
}
static void DY778LoaderUnmount(id self, SEL cmd, id component, long long level) {
    if (DY778LiveCommentCanSend(component)) DY778LiveMain(^{ [[DY778LuckyCoordinator shared] unbindFragment:component comment:YES]; });
    ((void (*)(id,SEL,id,long long))DY778OrigLoaderUnmount)(self,cmd,component,level);
}
static void DY778CommentServiceBind(id self, SEL cmd, id injector) {
    ((void (*)(id,SEL,id))DY778OrigCommentServiceBind)(self,cmd,injector);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] observeCommentService:self]; });
}
static void DY778CommentServiceSetInjector(id self, SEL cmd, id injector) {
    ((void (*)(id,SEL,id))DY778OrigCommentServiceSetInjector)(self,cmd,injector);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] observeCommentService:self]; });
}
static void DY778CommentServiceLaunch(id self, SEL cmd) {
    ((void (*)(id,SEL))DY778OrigCommentServiceLaunch)(self,cmd);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] observeCommentService:self]; });
}
static void DY778CommentServiceRebind(id self, SEL cmd) {
    ((void (*)(id,SEL))DY778OrigCommentServiceRebind)(self,cmd);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] observeCommentService:self]; });
}
static void DY778CommentServiceRoom(id self, SEL cmd, id room) {
    ((void (*)(id,SEL,id))DY778OrigCommentServiceRoom)(self,cmd,room);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] observeCommentService:self]; });
}
static void DY778CommentServiceSetRoom(id self, SEL cmd, id room) {
    ((void (*)(id,SEL,id))DY778OrigCommentServiceSetRoom)(self,cmd,room);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] observeCommentService:self]; });
}
static void DY778CommentServiceEnd(id self, SEL cmd) {
    DY778LiveMain(^{
        DY778LuckyCoordinator *c = [DY778LuckyCoordinator shared]; NSString *room = DY778FragmentRoomID(self);
        if (room.length && [c.commentServices objectForKey:room] == self) [c.commentServices removeObjectForKey:room];
        if (c.commentService == self) c.commentService = nil;
        objc_setAssociatedObject(self,&DY778LuckyComponentRetiredKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
    ((void (*)(id,SEL))DY778OrigCommentServiceEnd)(self,cmd);
}
static void DY778CommentSetStore(id self, SEL cmd, id store) {
    ((void (*)(id,SEL,id))DY778OrigCommentSetStore)(self,cmd,store); DY778QueueLiveObservation(self, YES, YES);
}
static void DY778CommentStoreReaction(id self, SEL cmd, id reaction) {
    ((void (*)(id,SEL,id))DY778OrigCommentStoreReaction)(self,cmd,reaction); DY778LiveMain(^{ DY778ObserveCommentStore(self); });
}
static void DY778CommentStoreRoom(id self, SEL cmd, id room) {
    ((void (*)(id,SEL,id))DY778OrigCommentStoreRoom)(self,cmd,room); DY778LiveMain(^{ DY778ObserveCommentStore(self); });
}
static IMP DY778OrigLotteryBind, DY778OrigCommentBind, DY778OrigLotteryGet, DY778OrigLotterySetStore;
static IMP DY778OrigLotterySetRoom, DY778OrigCommentSetRoom;
static IMP DY778OrigStoreSetLottery, DY778OrigStoreSetReaction, DY778OrigStoreReceive;
static IMP DY778OrigFloatingWindow, DY778OrigFloatingTime, DY778OrigWrapperSet, DY778OrigContainerShow, DY778OrigShortcutAppear;
static void DY778LotterySetRoom(id self, SEL cmd, id room, id context, id track) {
    ((void (*)(id, SEL, id, id, id))DY778OrigLotterySetRoom)(self, cmd, room, context, track);
    DY778QueueLiveObservation(self, NO, YES);
}
static void DY778CommentSetRoom(id self, SEL cmd, id room, id context, id track) {
    ((void (*)(id, SEL, id, id, id))DY778OrigCommentSetRoom)(self, cmd, room, context, track);
    DY778QueueLiveObservation(self, YES, YES);
}
static void DY778LotteryBind(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778OrigLotteryBind)(self, cmd); DY778QueueLiveObservation(self, NO, YES);
}
static void DY778CommentBind(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778OrigCommentBind)(self, cmd); DY778QueueLiveObservation(self, YES, YES);
}
static id DY778LotteryGet(id self, SEL cmd) {
    id value = ((id (*)(id, SEL))DY778OrigLotteryGet)(self, cmd); DY778QueueLiveObservation(self, NO, NO); return value;
}
static void DY778LotterySetStore(id self, SEL cmd, id store) {
    ((void (*)(id, SEL, id))DY778OrigLotterySetStore)(self, cmd, store); DY778QueueLiveObservation(self, NO, NO);
}
static void DY778StoreSetLottery(id self, SEL cmd, id lottery) {
    ((void (*)(id, SEL, id))DY778OrigStoreSetLottery)(self, cmd, lottery); DY778LiveMain(^{ DY778ObserveLotteryStore(self); });
}
static void DY778StoreSetReaction(id self, SEL cmd, id reaction) {
    ((void (*)(id, SEL, id))DY778OrigStoreSetReaction)(self, cmd, reaction); DY778LiveMain(^{ DY778ObserveLotteryStore(self); });
}
static void DY778StoreReceive(id self, SEL cmd, id lottery) {
    ((void (*)(id, SEL, id))DY778OrigStoreReceive)(self, cmd, lottery); DY778LiveMain(^{ DY778ObserveLotteryStore(self); });
}
static void DY778ShortcutAppear(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778OrigShortcutAppear)(self, cmd);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] discoverVisibleRoom]; });
}
static void DY778FloatingWindow(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778OrigFloatingWindow)(self, cmd);
    DY778LiveMain(^{ DY778ObserveLotteryStore(DY778Read(self, @"store")); });
}
static void DY778FloatingTime(id self, SEL cmd, long long remaining) {
    ((void (*)(id, SEL, long long))DY778OrigFloatingTime)(self, cmd, remaining);
    DY778LiveMain(^{ DY778CaptureNativeClock(self, remaining); DY778ObserveLotteryStore(DY778Read(self, @"store")); [[DY778LuckyCoordinator shared] nativeClockUpdated:DY778Read(self, @"store")]; });
}
static void DY778WrapperSet(id self, SEL cmd, id controller) {
    ((void (*)(id, SEL, id))DY778OrigWrapperSet)(self, cmd, controller);
    DY778LiveMain(^{
        if ([controller isKindOfClass:UIViewController.class]) {
            NSString *room = DY778LiveRoomID(DY778Read(self, @"roomModel"));
            if (room.length) [[DY778LuckyCoordinator shared] enterHost:controller roomID:room];
        }
    });
}
static void DY778ContainerShow(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778OrigContainerShow)(self, cmd);
    DY778LiveMain(^{
        id controller = DY778Read(self, @"audienceVC") ?: DY778Read(self, @"audienceViewController");
        NSString *room = DY778LiveRoomID(DY778Read(self, @"roomModel"));
        if ([controller isKindOfClass:UIViewController.class] && room.length) [[DY778LuckyCoordinator shared] enterHost:controller roomID:room];
        [[DY778LuckyCoordinator shared] discoverVisibleRoom];
    });
}
#pragma mark - Runtime integration
static IMP DY778OrigLotteryOpen, DY778OrigLotteryURL, DY778OrigLotteryRealOpen, DY778OrigLotteryPanel, DY778OrigAnnieTransition, DY778OrigLotteryPortrait;
static IMP DY778OrigLotteryAuthorization;
static IMP DY778OrigLotteryItemClick, DY778OrigLotteryItemDidClick, DY778OrigLotteryFloatingClick;
static void DY778LuckyUserAction(id fragment) {
    if (!NSThread.isMainThread) return;
    DY778LuckyCoordinator *c = [DY778LuckyCoordinator shared];
    if (fragment != c.fragment || !c.openingAuthorized) [c userOpenedLottery:fragment];
}
static void DY778LotteryOpen(id fragment, SEL cmd) {
    DY778LuckyUserAction(fragment);
    ((void (*)(id,SEL))DY778OrigLotteryOpen)(fragment,cmd);
}
static void DY778LotteryItemClick(id fragment, SEL cmd) {
    DY778LuckyUserAction(fragment); ((void (*)(id,SEL))DY778OrigLotteryItemClick)(fragment,cmd);
}
static void DY778LotteryItemDidClick(id fragment, SEL cmd) {
    DY778LuckyUserAction(fragment); ((void (*)(id,SEL))DY778OrigLotteryItemDidClick)(fragment,cmd);
}
static void DY778LotteryFloatingClick(id fragment, SEL cmd, id sender) {
    DY778LuckyUserAction(fragment); ((void (*)(id,SEL,id))DY778OrigLotteryFloatingClick)(fragment,cmd,sender);
}
static void DY778LotteryAuthorization(id fragment, SEL cmd, id params) {
    id request = [params isKindOfClass:NSDictionary.class] ? [params mutableCopy] : params;
    if ([request isKindOfClass:NSDictionary.class])
        objc_setAssociatedObject(request,&DY778LuckyAuthorizationKey,
            objc_getAssociatedObject(fragment,&DY778LuckyQuietRequestKey) ?: @"",OBJC_ASSOCIATION_COPY_NONATOMIC);
    ((void (*)(id,SEL,id))DY778OrigLotteryAuthorization)(fragment,cmd,request);
}
static void DY778LuckyRoute(id fragment, SEL cmd, id argument, IMP original) {
    NSString *authorization = cmd == NSSelectorFromString(@"p_realOpenLotteryPanelWithParams:") ?
        objc_getAssociatedObject(argument,&DY778LuckyAuthorizationKey) : nil;
    NSString *token = authorization ?: objc_getAssociatedObject(fragment,&DY778LuckyQuietRequestKey);
    if (!token.length) { ((void (*)(id,SEL,id))original)(fragment,cmd,argument); return; }
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([token isEqual:objc_getAssociatedObject(fragment,&DY778LuckyQuietRequestKey)]) DY778LuckyRoute(fragment,cmd,argument,original);
        }); return;
    }
    DY778LuckyCoordinator *c = [DY778LuckyCoordinator shared];
    if (DY778LuckyRoutePolicy(YES, fragment == c.fragment && [token isEqual:c.quietToken],
        [c quietRequestValid], c.quietController != nil) != DY778LuckyRouteQuiet) return;
    BOOL creating = c.quietCreating; NSString *previous = DY778LuckyRouteToken;
    c.quietCreating = YES; DY778LuckyRouteToken = token;
    @try { ((void (*)(id,SEL,id))original)(fragment,cmd,argument); }
    @finally { c.quietCreating = creating; DY778LuckyRouteToken = previous; }
}
static void DY778LotteryRealOpen(id fragment, SEL cmd, id params) {
    DY778LuckyRoute(fragment,cmd,params,DY778OrigLotteryRealOpen);
}
static void DY778LotteryURL(id fragment, SEL cmd, id url) {
    DY778LuckyRoute(fragment,cmd,url,DY778OrigLotteryURL);
}
static void DY778LotteryPortrait(id router, SEL cmd, void (^completion)(BOOL)) {
    NSString *token = NSThread.isMainThread ? DY778LuckyRouteToken : nil;
    if (!token.length || !completion) {
        ((void (*)(id,SEL,id))DY778OrigLotteryPortrait)(router,cmd,completion); return;
    }
    void (^scoped)(BOOL) = ^(BOOL finished) {
        DY778LiveMain(^{
            DY778LuckyCoordinator *c = [DY778LuckyCoordinator shared];
            if (DY778LuckyRoutePolicy(YES,[token isEqual:c.quietToken],[c quietRequestValid],c.quietController != nil) != DY778LuckyRouteQuiet) return;
            BOOL creating = c.quietCreating; NSString *previous = DY778LuckyRouteToken;
            c.quietCreating = YES; DY778LuckyRouteToken = token;
            @try { completion(finished); }
            @finally { c.quietCreating = creating; DY778LuckyRouteToken = previous; }
        });
    };
    ((void (*)(id,SEL,id))DY778OrigLotteryPortrait)(router,cmd,scoped);
}
static void DY778AnnieTransition(id router, SEL cmd, id schema, id controller, id fromVC, id context, id completion, id __autoreleasing *error) {
    if (!NSThread.isMainThread || !DY778LuckyRouteToken.length) {
        ((void (*)(id,SEL,id,id,id,id,id,id __autoreleasing *))DY778OrigAnnieTransition)(router,cmd,schema,controller,fromVC,context,completion,error);
        return;
    }
    DY778LuckyCoordinator *c = [DY778LuckyCoordinator shared];
    NSString *token = DY778LuckyRouteToken; NSUInteger generation = c.generation;
    BOOL attached = NO;
    if (DY778LuckyRoutePolicy(YES, [token isEqual:c.quietToken], [c quietRequestValid],
        c.quietController != nil) == DY778LuckyRouteQuiet) {
        @try { attached = [c attachQuietController:controller router:router schema:schema context:context completion:completion]; }
        @catch (__unused NSException *exception) { attached = NO; }
    }
    if (!attached) {
        if (error) *error = [NSError errorWithDomain:@"com.dy778.lottery" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"本场静默报名容器未就绪"}];
        if (generation == c.generation && [token isEqual:c.quietToken]) {
            [c recordProbe:@"本场静默容器未完成挂载，已停止报名"];
            [c finishUnconfirmed];
        }
    }
}
static void DY778LotteryPanel(id fragment, SEL cmd, id panel) {
    NSString *token = objc_getAssociatedObject(fragment,&DY778LuckyQuietRequestKey);
    if (NSThread.isMainThread && token.length && panel) {
        DY778LuckyCoordinator *c = [DY778LuckyCoordinator shared];
        if (fragment != c.fragment || ![token isEqual:c.quietToken] || ![c quietRequestValid]) return;
    }
    ((void (*)(id,SEL,id))DY778OrigLotteryPanel)(fragment,cmd,panel);
    if (!NSThread.isMainThread || !panel) return;
    DY778LuckyCoordinator *c = [DY778LuckyCoordinator shared];
    if (fragment == c.fragment && c.quietToken.length) [c captureQuietPanel:panel];
}
static IMP DY778OrigWebFinished, DY778OrigWebStarted, DY778OrigWebAttached;
static void DY778LuckyWebAttached(id web, SEL cmd) {
    ((void (*)(id,SEL))DY778OrigWebAttached)(web,cmd);
    if (DY778Bool(@"lucky.enabled")) DY778LiveMain(^{ [[DY778LuckyCoordinator shared] webAppeared:web]; });
}
static void DY778LuckyWebFinished(id owner, SEL cmd, WKWebView *web, id navigation) {
    ((void (*)(id, SEL, id, id))DY778OrigWebFinished)(owner, cmd, web, navigation);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] webReady:web]; });
}
static void DY778LuckyWebStarted(id owner, SEL cmd, WKWebView *web, id navigation) {
    ((void (*)(id, SEL, id, id))DY778OrigWebStarted)(owner, cmd, web, navigation);
    if ([web isKindOfClass:WKWebView.class]) objc_setAssociatedObject(web, &DY778LuckyWebReadyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static IMP DY778OrigLotteryMount, DY778OrigLotteryAppear, DY778OrigLotteryUnmount, DY778OrigLotteryDisappear;
static IMP DY778OrigCommentMount, DY778OrigCommentUnmount;
static IMP DY778OrigLotteryStart, DY778OrigLotteryEnd, DY778OrigParticipation;
static IMP DY778OrigAudienceAppear, DY778OrigAudienceEnter, DY778OrigAudienceLeave, DY778OrigAudienceResign, DY778OrigAudienceActive;

static void DY778LotteryMount(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778OrigLotteryMount)(self, cmd);
    DY778QueueLiveObservation(self, NO, YES);
}
static void DY778LotteryAppear(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778OrigLotteryAppear)(self, cmd);
    DY778QueueLiveObservation(self, NO, NO);
}
static void DY778LotteryUnmount(id self, SEL cmd) {
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] unbindFragment:self comment:NO]; });
    ((void (*)(id, SEL))DY778OrigLotteryUnmount)(self, cmd);
}
static void DY778LotteryDisappear(id self, SEL cmd) {
    DY778LiveMain(^{ DY778LuckyCoordinator *c = [DY778LuckyCoordinator shared]; if (c.fragment == self) [c suspendHost:c.host]; });
    ((void (*)(id, SEL))DY778OrigLotteryDisappear)(self, cmd);
}
static void DY778CommentMount(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778OrigCommentMount)(self, cmd);
    DY778QueueLiveObservation(self, YES, YES);
}
static void DY778CommentUnmount(id self, SEL cmd) {
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] unbindFragment:self comment:YES]; });
    ((void (*)(id, SEL))DY778OrigCommentUnmount)(self, cmd);
}
static void DY778LotteryStart(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778OrigLotteryStart)(self, cmd);
    DY778QueueLiveObservation(self, NO, NO);
}
static void DY778LotteryEnd(id self, SEL cmd, long long result) {
    ((void (*)(id, SEL, long long))DY778OrigLotteryEnd)(self, cmd, result);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] lotteryEnded:self]; });
}
static void DY778Participation(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778OrigParticipation)(self, cmd);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] participationChanged:self]; });
}

static void DY778AudienceAppear(id self, SEL cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))DY778OrigAudienceAppear)(self, cmd, animated);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] enterHost:self]; });
}
static void DY778AudienceEnter(id self, SEL cmd, id room) {
    ((void (*)(id, SEL, id))DY778OrigAudienceEnter)(self, cmd, room);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] enterHost:self]; });
}
static void DY778AudienceLeave(id self, SEL cmd) {
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] leaveHost:self]; });
    ((void (*)(id, SEL))DY778OrigAudienceLeave)(self, cmd);
}
static void DY778AudienceResign(id self, SEL cmd, id room) {
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] suspendHost:self]; });
    ((void (*)(id, SEL, id))DY778OrigAudienceResign)(self, cmd, room);
}
static void DY778AudienceActive(id self, SEL cmd, id room) {
    ((void (*)(id, SEL, id))DY778OrigAudienceActive)(self, cmd, room);
    DY778LiveMain(^{ [[DY778LuckyCoordinator shared] enterHost:self]; });
}
static void DY778LiveInstall(NSString *className, NSString *selector, const char *arguments, IMP replacement, IMP *original) {
    if (*original) return;
    Class cls = NSClassFromString(className); SEL sel = NSSelectorFromString(selector);
    BOOL valid = DY778LiveSignature(cls, sel, "v", arguments);
    BOOL installed = valid && DY778Hook(cls, sel, replacement, original);
    DY778RecordHook([NSString stringWithFormat:@"福袋 / %@.%@", className, selector], installed);
}
void DY778InstallLuckyBagHooks(void) {
    DY778LiveMain(^{
        DY778LiveInstall(@"IESLiveLotteryFragment", @"openLotteryPage", "", (IMP)DY778LotteryOpen, &DY778OrigLotteryOpen);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"p_checkAuthorizationAndShowLotteryPanelWithParams:", "@", (IMP)DY778LotteryAuthorization, &DY778OrigLotteryAuthorization);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"p_realOpenLotteryPanelWithParams:", "@", (IMP)DY778LotteryRealOpen, &DY778OrigLotteryRealOpen);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"p_openWebViewWithUrl:", "@", (IMP)DY778LotteryURL, &DY778OrigLotteryURL);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"setHybridLotteryPanel:", "@", (IMP)DY778LotteryPanel, &DY778OrigLotteryPanel);
        DY778LiveInstall(@"AnnieLiveBizRouter", @"makeTransitionForSchema:controller:fromVC:context:completion:error:", "@@@@@^", (IMP)DY778AnnieTransition, &DY778OrigAnnieTransition);
        DY778LiveInstall(@"IESLiveInternalRouterImpl", @"forceUpdateToPortraitWithCompletion:", "@", (IMP)DY778LotteryPortrait, &DY778OrigLotteryPortrait);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"lotteryItemClick", "", (IMP)DY778LotteryItemClick, &DY778OrigLotteryItemClick);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"lotteryItemDidClick", "", (IMP)DY778LotteryItemDidClick, &DY778OrigLotteryItemDidClick);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"lotteryFloatingViewClicked:", "@", (IMP)DY778LotteryFloatingClick, &DY778OrigLotteryFloatingClick);
        DY778LuckyQuietHooksReady = DY778OrigLotteryOpen && DY778OrigLotteryAuthorization && DY778OrigLotteryRealOpen && DY778OrigLotteryURL && DY778OrigLotteryPanel && DY778OrigAnnieTransition && DY778OrigLotteryPortrait &&
            DY778OrigLotteryItemClick && DY778OrigLotteryItemDidClick && DY778OrigLotteryFloatingClick &&
            DY778LiveSignature(NSClassFromString(@"AnnieLiveBizRouter"),NSSelectorFromString(@"_addChildViewController:fromVC:targetView:animated:context:completion:"),"v","@@@B@@") &&
            DY778LiveSignature(NSClassFromString(@"AnnieLiveBizRouter"),NSSelectorFromString(@"getQueryItemsWithSchema:"),"@","@");
        DY778LiveInstall(@"IESWKWebView", @"didMoveToWindow", "", (IMP)DY778LuckyWebAttached, &DY778OrigWebAttached);
        DY778LiveInstall(@"IESWKWebView", @"webView:didFinishNavigation:", "@@", (IMP)DY778LuckyWebFinished, &DY778OrigWebFinished);
        DY778LiveInstall(@"IESWKWebView", @"webView:didStartProvisionalNavigation:", "@@", (IMP)DY778LuckyWebStarted, &DY778OrigWebStarted);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"componentMount", "", (IMP)DY778LotteryMount, &DY778OrigLotteryMount);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"componentDidAppear", "", (IMP)DY778LotteryAppear, &DY778OrigLotteryAppear);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"componentUnmount", "", (IMP)DY778LotteryUnmount, &DY778OrigLotteryUnmount);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"componentDidDisappear", "", (IMP)DY778LotteryDisappear, &DY778OrigLotteryDisappear);
        DY778LiveInstall(@"HTSLiveCommentFragment", @"componentMount", "", (IMP)DY778CommentMount, &DY778OrigCommentMount);
        DY778LiveInstall(@"HTSLiveCommentFragment", @"componentUnmount", "", (IMP)DY778CommentUnmount, &DY778OrigCommentUnmount);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"receivedLotteryStart", "", (IMP)DY778LotteryStart, &DY778OrigLotteryStart);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"receivedLotteryEndForResult:", "q", (IMP)DY778LotteryEnd, &DY778OrigLotteryEnd);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"userParticipateStateChange", "", (IMP)DY778Participation, &DY778OrigParticipation);
        DY778LiveInstall(@"IESLiveAudienceViewController", @"viewDidAppear:", "B", (IMP)DY778AudienceAppear, &DY778OrigAudienceAppear);
        DY778LiveInstall(@"IESLiveAudienceViewController", @"didEnterRoom:", "@", (IMP)DY778AudienceEnter, &DY778OrigAudienceEnter);
        DY778LiveInstall(@"IESLiveAudienceViewController", @"onStartLeaveRoomAnimation", "", (IMP)DY778AudienceLeave, &DY778OrigAudienceLeave);
        DY778LiveInstall(@"IESLiveAudienceViewController", @"roomWillResignActive:", "@", (IMP)DY778AudienceResign, &DY778OrigAudienceResign);
        DY778LiveInstall(@"IESLiveAudienceViewController", @"roomDidBecomeActive:", "@", (IMP)DY778AudienceActive, &DY778OrigAudienceActive);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"setRoom:componentContext:trackContext:", "@@@", (IMP)DY778LotterySetRoom, &DY778OrigLotterySetRoom);
        DY778LiveInstall(@"HTSLiveCommentFragment", @"setRoom:componentContext:trackContext:", "@@@", (IMP)DY778CommentSetRoom, &DY778OrigCommentSetRoom);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"componentBindService", "", (IMP)DY778LotteryBind, &DY778OrigLotteryBind);
        DY778LiveInstall(@"HTSLiveCommentFragment", @"componentBindService", "", (IMP)DY778CommentBind, &DY778OrigCommentBind);
        DY778LiveInstall(@"IESLiveLotteryFragment", @"setStore:", "@", (IMP)DY778LotterySetStore, &DY778OrigLotterySetStore);
        DY778LiveInstall(@"IESLiveLotteryStore", @"setCurrentLottery:", "@", (IMP)DY778StoreSetLottery, &DY778OrigStoreSetLottery);
        DY778LiveInstall(@"IESLiveLotteryStore", @"setReaction:", "@", (IMP)DY778StoreSetReaction, &DY778OrigStoreSetReaction);
        DY778LiveInstall(@"IESLiveLotteryStore", @"p_receiveLotteryModel:", "@", (IMP)DY778StoreReceive, &DY778OrigStoreReceive);
        DY778LiveInstall(@"IESLiveShortTouchItem", @"didAppear", "", (IMP)DY778ShortcutAppear, &DY778OrigShortcutAppear);
        DY778LiveInstall(@"IESLiveLotteryFloatingView", @"didMoveToWindow", "", (IMP)DY778FloatingWindow, &DY778OrigFloatingWindow);
        DY778LiveInstall(@"IESLiveLotteryFloatingView", @"updateTime:", "q", (IMP)DY778FloatingTime, &DY778OrigFloatingTime);
        DY778LiveInstall(@"AWELiveAudienceViewController", @"setAudienceViewController:", "@", (IMP)DY778WrapperSet, &DY778OrigWrapperSet);
        DY778LiveInstall(@"AWELiveAudienceContainerController", @"alreadyShowAudience", "", (IMP)DY778ContainerShow, &DY778OrigContainerShow);
        if (!DY778OrigLotteryGet) {
            Class cls = NSClassFromString(@"IESLiveLotteryFragment"); SEL selector = NSSelectorFromString(@"getCurrentLottery");
            BOOL installed = DY778LiveSignature(cls, selector, "@", "") && DY778Hook(cls, selector, (IMP)DY778LotteryGet, &DY778OrigLotteryGet);
            DY778RecordHook(@"福袋 / IESLiveLotteryFragment.getCurrentLottery", installed);
        }
        DY778LiveInstall(@"IESLiveCommentServiceImpl", @"bindInjector:", "@", (IMP)DY778CommentServiceBind, &DY778OrigCommentServiceBind);
        DY778LiveInstall(@"IESLiveCommentServiceImpl", @"setInjector:", "@", (IMP)DY778CommentServiceSetInjector, &DY778OrigCommentServiceSetInjector);
        DY778LiveInstall(@"IESLiveCommentServiceImpl", @"serviceDidLaunch", "", (IMP)DY778CommentServiceLaunch, &DY778OrigCommentServiceLaunch);
        DY778LiveInstall(@"IESLiveCommentServiceImpl", @"injectorReady", "", (IMP)DY778CommentServiceReady, &DY778OrigCommentServiceReady);
        DY778LiveInstall(@"IESLiveCommentServiceImpl", @"serviceDidReBind", "", (IMP)DY778CommentServiceRebind, &DY778OrigCommentServiceRebind);
        DY778LiveInstall(@"IESLiveCommentServiceImpl", @"serviceRoomDataReady:", "@", (IMP)DY778CommentServiceRoom, &DY778OrigCommentServiceRoom);
        DY778LiveInstall(@"IESLiveCommentServiceImpl", @"setRoom:", "@", (IMP)DY778CommentServiceSetRoom, &DY778OrigCommentServiceSetRoom);
        DY778LiveInstall(@"IESLiveCommentServiceImpl", @"serviceUninstall", "", (IMP)DY778CommentServiceEnd, &DY778OrigCommentServiceEnd);
        DY778LiveInstall(@"HTSLiveCommentFragment", @"setStore:", "@", (IMP)DY778CommentSetStore, &DY778OrigCommentSetStore);
        DY778LiveInstall(@"HTSLiveCommentStore", @"setReactions:", "@", (IMP)DY778CommentStoreReaction, &DY778OrigCommentStoreReaction);
        DY778LiveInstall(@"HTSLiveCommentStore", @"setRoomModel:", "@", (IMP)DY778CommentStoreRoom, &DY778OrigCommentStoreRoom);
        DY778LiveInstall(@"HTSLiveCommentStore", @"setup", "", (IMP)DY778CommentStoreSetup, &DY778OrigCommentStoreSetup);
        DY778LiveInstall(@"HTSLiveCommentStore", @"didUpdateRoom:", "@", (IMP)DY778CommentStoreUpdate, &DY778OrigCommentStoreUpdate);
        DY778LiveInstall(@"IESLiveComponentBootLoader", @"callComponentMount:level:", "@q", (IMP)DY778LoaderMount, &DY778OrigLoaderMount);
        DY778LiveInstall(@"IESLiveComponentBootLoader", @"callComponentUnmount:level:", "@q", (IMP)DY778LoaderUnmount, &DY778OrigLoaderUnmount);
        (void)[DY778LuckyCoordinator shared];
    });
}
void DY778LuckyPreferencesChanged(void) { DY778LiveMain(^{ [[DY778LuckyCoordinator shared] preferencesChanged]; }); }
NSString *DY778LuckyStatusSummary(void) {
    if (!DY778Bool(@"lucky.enabled")) return @"未开启";
    __block NSString *value;
    if (NSThread.isMainThread) value = [DY778LuckyCoordinator shared].status;
    else dispatch_sync(dispatch_get_main_queue(), ^{ value = [DY778LuckyCoordinator shared].status; });
    return value ?: @"等待进入直播间";
}
void DY778PresentLuckyPanel(UIViewController *source) {
    DY778LiveMain(^{ DY778LuckyCoordinator *c = [DY778LuckyCoordinator shared]; [c discoverVisibleRoom];
        if ([c contextValid] && DY778LiveSameHierarchy(source, c.host)) [c presentFrom:c.host];
        else DY778LuckyToast(@"请在直播间打开福袋助手"); });
}
void DY778PresentLuckyHistory(UIViewController *source) {
    DY778LiveMain(^{ DY778PresentController(source, [DY778LuckyHistoryController new]); });
}
