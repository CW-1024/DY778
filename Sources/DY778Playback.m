#import "DY778Playback.h"
#import "DY778Core.h"
#import "DY778PlaybackPolicy.h"
#import "DY778SpeedLockPolicy.h"
#import <stdatomic.h>

static atomic_bool DY778StopAtEnd, DY778LongPressEnabled;
static _Atomic(double) DY778LongPressRate = 2;
static NSMutableSet<NSString *> *DY778PlaybackInstalled;
static NSHashTable *DY778PressOwners;
static char DY778PressStateKey, DY778EndTokenKey, DY778SpeedBindingKey, DY778SpeedGestureKey;
static _Thread_local DY778PlaybackFrame *DY778PlaybackStack;
static _Thread_local DY778PlaybackFrame *DY778ReplayStack;

@interface DY778PressState : NSObject
@property(nonatomic) DY778PressSession session;
@property(nonatomic) DY778SpeedLockState lock;
@property(nonatomic, weak) id owner;
@property(nonatomic, weak) id target;
@property(nonatomic, weak) id model;
@property(nonatomic, weak) id manager;
@property(nonatomic) SEL setter;
@property(nonatomic) char setterType;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL accepted, armed, geometryValid, settling, markerOwned;
@property(nonatomic) double pressRate, settledRate;
@property(nonatomic) CGPoint startPoint;
@property(nonatomic) CGSize windowSize;
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIGestureRecognizer *gesture;
@property(nonatomic, weak) UIView *speedView;
@property(nonatomic, strong) UILabel *fallbackHint;
@property(nonatomic, copy) NSString *toastToken;
@end
@implementation DY778PressState
- (void)dealloc { DY778DismissSpeedToast(_toastToken); [_fallbackHint removeFromSuperview]; }
@end
@interface DY778SpeedBinding : NSObject
@property(nonatomic, weak) DY778PressState *state;
@end
@implementation DY778SpeedBinding @end
@interface DY778PlaybackEndState : NSObject
@property(nonatomic, weak) id model;
@property(nonatomic, weak) id player;
@end
@implementation DY778PlaybackEndState @end

typedef struct DY778PressGestureFrame {
    const void *state;
    struct DY778PressGestureFrame *previous;
} DY778PressGestureFrame;
static _Thread_local DY778PressGestureFrame *DY778PressGestureStack;

static BOOL DY778PlaybackSignature(Class cls, SEL selector, char result, const char *arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char type[64] = {0}; method_getReturnType(method, type, sizeof(type));
    if (result == 'B' ? (type[0] != 'B' && type[0] != 'c') : type[0] != result) return NO;
    for (unsigned i = 0; arguments[i]; i++) { method_getArgumentType(method, i + 2, type, sizeof(type)); if (type[0] != arguments[i]) return NO; }
    return YES;
}
static BOOL DY778PlaybackInstall(Class cls, SEL selector, IMP replacement, IMP *original, NSString *key) {
    if ([DY778PlaybackInstalled containsObject:key]) { imp_removeBlock(replacement); return NO; }
    BOOL installed = DY778Hook(cls, selector, replacement, original);
    if (installed) [DY778PlaybackInstalled addObject:key]; else imp_removeBlock(replacement);
    DY778RecordHook([@"DY778 播放 / " stringByAppendingString:key], installed); return installed;
}
static double DY778ReadRate(id object, NSString *key) {
    SEL selector = NSSelectorFromString(key);
    if (DY778PlaybackSignature([object class], selector, 'd', "")) return ((double (*)(id, SEL))objc_msgSend)(object, selector);
    if (DY778PlaybackSignature([object class], selector, 'f', "")) return ((float (*)(id, SEL))objc_msgSend)(object, selector);
    return NAN;
}
static id DY778SpeedTarget(id owner) {
    id provider = DY778Read(owner, @"playerProvider");
    if (provider) return provider;
    id video = DY778Read(owner, @"playVideoViewController");
    if (video) return DY778Read(video, @"playerController") ?: video;
    return DY778Read(owner, @"playerController") ?: owner;
}
static id DY778SpeedModel(id owner) { return DY778Read(owner, @"model") ?: DY778Read(owner, @"awemeModel"); }
static id DY778SpeedManager(id owner) {
    return DY778Read(owner, @"speedManager") ?: DY778Read(DY778Read(owner, @"context"), @"speedManager");
}
static DY778PressState *DY778PressStateForOwner(id owner, BOOL create) {
    if (!owner) return nil;
    DY778PressState *state = objc_getAssociatedObject(owner, &DY778PressStateKey);
    if (!state && create) { state = [DY778PressState new]; state.owner = owner; objc_setAssociatedObject(owner, &DY778PressStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return state;
}
static BOOL DY778SpeedStateCurrent(DY778PressState *state) {
    return NSThread.isMainThread && state.owner && state.model && state.model == DY778SpeedModel(state.owner);
}
BOOL DY778PlaybackHasNativeLock(id owner) {
    if (!NSThread.isMainThread || !owner) return NO;
    owner = DY778Read(owner, @"speedContainer") ?: owner;
    DY778PressState *state = DY778PressStateForOwner(owner, NO);
    if (DY778SpeedStateCurrent(state) && state.lock.locked) return YES;
    NSString *itemID = DY778Identifier(DY778Read(DY778SpeedModel(owner), @"itemID"));
    if (!itemID.length) return NO;
    id manager = DY778SpeedManager(owner);
    if ([manager respondsToSelector:NSSelectorFromString(@"isLockedSpeedAwemeID")])
        return [DY778Identifier(DY778Read(manager, @"isLockedSpeedAwemeID")) isEqualToString:itemID];
    id lock = DY778Read(owner, @"lockSpeedContainer") ?: owner;
    return [DY778Identifier(DY778Read(DY778SpeedModel(lock), @"itemID")) isEqualToString:itemID] && [DY778Read(lock, @"isLockSpeed") boolValue];
}
static DY778PressState *DY778BoundSpeedState(id object) {
    DY778SpeedBinding *binding = objc_getAssociatedObject(object, &DY778SpeedBindingKey);
    DY778PressState *state = binding.state;
    if (!DY778SpeedStateCurrent(state)) return nil;
    id model = DY778SpeedModel(object);
    return !model || model == state.model ? state : nil;
}
static void DY778BindSpeedState(id object, DY778PressState *state) {
    if (!object) return;
    DY778SpeedBinding *binding = [DY778SpeedBinding new]; binding.state = state;
    objc_setAssociatedObject(object, &DY778SpeedBindingKey, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static double DY778PreferredSpeed(id object, double requested) {
    DY778PressState *state = DY778BoundSpeedState(object);
    if (!state) return requested;
    // 短暂的释放作用域也覆盖在我们处理返回后才写入的外层 hook。
    return DY778SpeedLockPriority(state.lock, state.accepted && state.session.active, state.pressRate,
                                  state.settling, state.settledRate, requested);
}
static void DY778InstallSpeedSink(id object, NSString *name) {
    Class cls = [object class]; SEL selector = NSSelectorFromString(name);
    BOOL single = DY778PlaybackSignature(cls, selector, 'v', "f");
    if (!single && !DY778PlaybackSignature(cls, selector, 'v', "d")) return;
    NSString *key = [NSStringFromClass(cls) stringByAppendingFormat:@".speedPriority.%@", name];
    if ([DY778PlaybackInstalled containsObject:key]) return;
    __block IMP original = NULL; IMP replacement;
    void (^apply)(id, double) = ^(id target, double rate) {
        const void *hook = (__bridge const void *)key;
        if (DY778PlaybackFrameContains(DY778PlaybackStack, (__bridge const void *)target, hook)) return;
        DY778PlaybackFrame frame = {(__bridge const void *)target, hook, DY778PlaybackStack}; DY778PlaybackStack = &frame;
        @try {
            rate = DY778PreferredSpeed(target, rate);
            if (single) ((void (*)(id, SEL, float))original)(target, selector, (float)rate);
            else ((void (*)(id, SEL, double))original)(target, selector, rate);
        } @finally { DY778PlaybackStack = frame.previous; }
    };
    if (single) replacement = imp_implementationWithBlock(^(id target, float rate) { apply(target, rate); });
    else replacement = imp_implementationWithBlock(^(id target, double rate) { apply(target, rate); });
    DY778PlaybackInstall(cls, selector, replacement, &original, key);
}
static void DY778BindSpeedTargets(DY778PressState *state) {
    // 只绑定当前视频的具体播放器图，包括最终的速率出口。
    NSMutableArray *objects = [NSMutableArray arrayWithObject:state.owner];
    for (NSUInteger i = 0; i < objects.count && i < 24; i++) {
        id object = objects[i]; DY778BindSpeedState(object, state);
        for (NSString *name in @[@"changeSpeed:", @"setPlaybackRate:", @"updatePlaybackRate:", @"setVideoControllerPlaybackRate:"])
            DY778InstallSpeedSink(object, name);
        for (NSString *key in @[@"playerProvider", @"playerController", @"playerViewController", @"playVideoViewController", @"speedManager", @"dPlayerSpeed"] ) {
            id child = DY778Read(object, key);
            if (child && [objects indexOfObjectIdenticalTo:child] == NSNotFound && objects.count < 24) [objects addObject:child];
        }
    }
    DY778BindSpeedState(DY778Read(state.owner, @"portraitContainer"), state);
    DY778BindSpeedState(DY778Read(state.owner, @"lockSpeedContainer"), state);
}
static void DY778WritePressSpeed(DY778PressState *state, double rate) {
    if (!DY778SpeedStateCurrent(state) || !state.target || !state.setter || !DY778SpeedValid(rate)) return;
    if (state.setterType == 'f') ((void (*)(id, SEL, float))objc_msgSend)(state.target, state.setter, (float)rate);
    else ((void (*)(id, SEL, double))objc_msgSend)(state.target, state.setter, rate);
    id manager = state.manager; SEL setter = NSSelectorFromString(@"setCurrentSpeed:");
    // 该管理器可能与预加载视频共用。在此同步，
    // 但绝不在那个全局对象上装持久的速率守卫。
    if (DY778PlaybackSignature([manager class], setter, 'v', "d")) ((void (*)(id, SEL, double))objc_msgSend)(manager, setter, rate);
}
static void DY778SyncLockMarker(DY778PressState *state) {
    NSString *itemID = DY778Identifier(DY778Read(state.model, @"itemID"));
    id manager = state.manager; SEL setter = NSSelectorFromString(@"setIsLockedSpeedAwemeID:");
    if (state.lock.locked && DY778SpeedStateCurrent(state)) {
        if (itemID.length && DY778PlaybackSignature([manager class], setter, 'v', "@"))
            ((void (*)(id, SEL, id))objc_msgSend)(manager, setter, itemID);
        state.markerOwned = YES;
    } else if (state.markerOwned) {
        if (itemID.length && [DY778Read(manager, @"isLockedSpeedAwemeID") isEqual:itemID] &&
            DY778PlaybackSignature([manager class], setter, 'v', "@")) ((void (*)(id, SEL, id))objc_msgSend)(manager, setter, nil);
        state.markerOwned = NO;
    } else return;
    id lock = DY778Read(state.owner, @"lockSpeedContainer") ?: state.owner;
    setter = NSSelectorFromString(@"setIsLockSpeed:");
    if (DY778SpeedStateCurrent(state) && (DY778PlaybackSignature([lock class], setter, 'v', "B") || DY778PlaybackSignature([lock class], setter, 'v', "c")))
        ((void (*)(id, SEL, BOOL))objc_msgSend)(lock, setter, state.lock.locked != 0);
}
static NSString *DY778PressHint(DY778PressState *state) {
    if (state.lock.locked) return state.armed ? @"松手恢复原倍速" : @"移动到此处恢复原倍速";
    return [NSString stringWithFormat:state.armed ? @"松手固定 %g 倍速" : @"移动到此处固定 %g 倍速", state.pressRate];
}
static void DY778CorrectSpeedHint(UIView *view, DY778PressState *state) {
    if (!DY778SpeedStateCurrent(state) || !state.accepted || !state.session.active || state.settling) return;
    UILabel *label = DY778Read(view, @"bottomTextView");
    if (![label isKindOfClass:UILabel.class]) return;
    NSString *text = DY778PressHint(state); if (![label.text isEqual:text]) label.text = text;
    label.hidden = NO;
    for (NSString *key in @[@"bottomArrowView", @"speedImageView", @"bottomSpeedTextView"]) {
        UIView *part = DY778Read(view, key); if ([part isKindOfClass:UIView.class]) part.hidden = YES;
    }
    UIView *arrow = DY778Read(view, @"downLockArrowView"); if ([arrow isKindOfClass:UIView.class]) arrow.hidden = NO;
}
static void DY778RefreshSpeedHint(DY778PressState *state) {
    if (!DY778SpeedStateCurrent(state) || !state.accepted || !state.session.active || state.settling) return;
    id portrait = DY778Read(state.owner, @"portraitContainer") ?: state.owner;
    UIView *view = DY778Read(portrait, @"longPressFastSpeedView");
    if ([view isKindOfClass:UIView.class] && view.window && !view.hidden) {
        state.speedView = view; DY778BindSpeedState(view, state);
        SEL update = NSSelectorFromString(@"updateSpeedLockBottomWithText:Type:");
        if (DY778PlaybackSignature([view class], update, 'v', "@q"))
            ((void (*)(id, SEL, id, long long))objc_msgSend)(view, update, DY778PressHint(state), state.armed ? 1 : 0);
        DY778CorrectSpeedHint(view, state);
        if ([DY778Read(view, @"bottomTextView") isKindOfClass:UILabel.class]) { [state.fallbackHint removeFromSuperview]; state.fallbackHint = nil; return; }
    }
    // 部分原生配置没有锁定 UI；保持同样的下滑手势可用。
    UIWindow *window = state.window; if (!window) return;
    if (!state.fallbackHint) {
        UILabel *hint = [UILabel new]; hint.userInteractionEnabled = NO; hint.textAlignment = NSTextAlignmentCenter;
        hint.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium]; hint.textColor = UIColor.whiteColor;
        hint.backgroundColor = [UIColor colorWithWhite:0 alpha:.65]; hint.layer.cornerRadius = 17; hint.clipsToBounds = YES;
        state.fallbackHint = hint; [window addSubview:hint];
    }
    UILabel *hint = state.fallbackHint; hint.text = DY778PressHint(state);
    CGSize size = [hint sizeThatFits:CGSizeMake(CGRectGetWidth(window.bounds)-48, 36)];
    CGFloat width = MIN(CGRectGetWidth(window.bounds)-48, size.width+32);
    CGFloat bottom = window.safeAreaInsets.bottom + (CGRectGetHeight(window.bounds) > CGRectGetWidth(window.bounds) ? 100 : 32);
    hint.frame = CGRectMake((CGRectGetWidth(window.bounds)-width)/2, CGRectGetHeight(window.bounds)-bottom-36, width, 36);
}
static void DY778EndPressUI(DY778PressState *state) {
    DY778DismissSpeedToast(state.toastToken); state.toastToken = nil;
    [state.fallbackHint removeFromSuperview]; state.fallbackHint = nil; state.speedView = nil;
}
static void DY778DiscardPress(id owner) {
    DY778PressState *state = DY778PressStateForOwner(owner, NO); if (!state) return;
    state.generation++; state.accepted = NO; state.armed = NO; state.settling = NO;
    DY778PressSession session = state.session; session.active = 0; state.session = session;
    DY778EndPressUI(state);
    if (!state.lock.locked) { state.target = nil; state.setter = NULL; state.model = nil; state.manager = nil; }
}
static void DY778RestorePress(id owner) {
    DY778PressState *state = DY778PressStateForOwner(owner, NO); if (!state) return;
    if (!NSThread.isMainThread) {
        NSUInteger generation = state.generation; __weak id weakOwner = owner;
        dispatch_async(dispatch_get_main_queue(), ^{ if (weakOwner && state.generation == generation) DY778RestorePress(weakOwner); }); return;
    }
    BOOL restore = state.lock.locked || (state.accepted && state.session.active);
    double rate = state.lock.locked ? state.lock.before : state.session.before;
    DY778SpeedLockState lock = state.lock; lock.locked = 0; state.lock = lock;
    state.accepted = NO; state.settling = NO; DY778SyncLockMarker(state);
    if (restore && DY778SpeedStateCurrent(state)) DY778WritePressSpeed(state, DY778DefaultRestoreSpeed(state.owner, rate));
    DY778DiscardPress(owner);
}
static void DY778BeginPress(id owner, UIGestureRecognizer *gesture) {
    if (!atomic_load_explicit(&DY778LongPressEnabled, memory_order_relaxed)) return;
    DY778PressState *state = DY778PressStateForOwner(owner, YES);
    if (state.session.active) return;
    if (state.model && !DY778SpeedStateCurrent(state)) DY778RestorePress(owner);
    id model = DY778SpeedModel(owner);
    if (!model || !DY778Read(model, @"video") || DY778Read(model, @"liveStreamURL")) return;
    id target = DY778SpeedTarget(owner);
    double rate = DY778ReadRate(target, @"playbackRate");
    if (!DY778SpeedValid(rate)) rate = DY778ReadRate(DY778SpeedManager(owner), @"currentSpeed");
    if (!state.lock.locked) rate = DY778DefaultRestoreSpeed(owner, rate);
    SEL setter = NSSelectorFromString(@"changeSpeed:"); char type = 'd';
    if (DY778PlaybackSignature([owner class], setter, 'v', "d")) target = owner;
    else {
        setter = NSSelectorFromString(@"setPlaybackRate:");
        if (DY778PlaybackSignature([target class], setter, 'v', "f")) type = 'f';
        else if (!DY778PlaybackSignature([target class], setter, 'v', "d")) return;
    }
    DY778PressSession session = state.session;
    if (!DY778PressBegin(&session, YES, rate)) return;
    state.session = session; state.target = target; state.setter = setter; state.setterType = type; state.model = model;
    state.manager = DY778SpeedManager(owner); state.generation++; state.accepted = NO; state.settling = NO; state.armed = NO;
    state.pressRate = atomic_load_explicit(&DY778LongPressRate, memory_order_relaxed);
    state.window = gesture.view.window; state.windowSize = state.window.bounds.size;
    state.startPoint = [gesture locationInView:state.window]; state.geometryValid = state.window != nil; state.gesture = gesture;
    [DY778PressOwners addObject:owner];
}
static BOOL DY778NativePressActive(id owner) {
    SEL active = NSSelectorFromString(@"isInLongPressFastSpeed");
    if (DY778PlaybackSignature([owner class], active, 'B', "")) return ((BOOL (*)(id, SEL))objc_msgSend)(owner, active);
    UIView *view = DY778Read(owner, @"longPressFastSpeedView");
    if ([view isKindOfClass:UIView.class] && view.window && !view.hidden && view.alpha > .01) return YES;
    DY778PressState *state = DY778PressStateForOwner(owner, NO);
    double current = DY778ReadRate(DY778SpeedTarget(owner), @"playbackRate");
    return state.session.active && DY778SpeedValid(current) && fabs(current-state.session.before) > .001;
}
static void DY778UpdatePressSlide(DY778PressState *state, UIGestureRecognizer *gesture) {
    UIWindow *window = state.window;
    if (!DY778SpeedLockGeometry(window && gesture.view.window == window, window.bounds.size.width, window.bounds.size.height,
                               state.windowSize.width, state.windowSize.height)) state.geometryValid = NO;
    if (!state.geometryValid || !DY778SpeedStateCurrent(state)) { state.armed = NO; return; }
    CGPoint point = [gesture locationInView:window];
    UIView *label = DY778Read(state.speedView, @"bottomTextView") ?: state.fallbackHint;
    BOOL inArea = [label isKindOfClass:UIView.class] && label.window == window && !label.hidden &&
        CGRectContainsPoint(CGRectInset([label convertRect:label.bounds toView:window], -20, -16), point);
    id lock = DY778Read(state.owner, @"lockSpeedContainer") ?: state.owner;
    double threshold = DY778ReadRate(lock, @"getTriggerLockDistance");
    state.armed = CGRectContainsPoint(window.bounds, point) && DY778SpeedLockSlide(point.x-state.startPoint.x, point.y-state.startPoint.y,
            threshold, CGRectGetHeight(window.bounds)-state.startPoint.y, inArea);
}
static void DY778MaybeShowPressToast(id owner, double rate, NSUInteger generation, unsigned retries) {
    DY778PressState *state = DY778PressStateForOwner(owner,NO);
    if (!state || state.generation != generation || !state.session.active || !state.accepted || state.settling || state.toastToken.length ||
        !atomic_load_explicit(&DY778LongPressEnabled,memory_order_relaxed)) return;
    double actual = DY778ReadRate(DY778SpeedTarget(owner),@"playbackRate");
    if (isfinite(actual) && fabs(actual-rate) > .01) {
        if (retries) {
            __weak id weakOwner = owner;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.08*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                id currentOwner = weakOwner; if (currentOwner) DY778MaybeShowPressToast(currentOwner,rate,generation,retries-1);
            });
        }
        return;
    }
    state.toastToken = NSUUID.UUID.UUIDString; DY778ShowSpeedToast(state.toastToken,rate);
}
static void DY778ApplyPressRate(id owner) {
    DY778PressState *state = DY778PressStateForOwner(owner, NO);
    if (!state.session.active || !state.accepted || !atomic_load_explicit(&DY778LongPressEnabled, memory_order_relaxed)) return;
    DY778WritePressSpeed(state, state.pressRate);
    DY778RefreshSpeedHint(state); DY778MaybeShowPressToast(owner,state.pressRate,state.generation,2);
}
static int DY778PreparePressEnd(DY778PressState *state, UIGestureRecognizer *gesture) {
    if (!state.accepted || !state.session.active || !DY778SpeedStateCurrent(state)) return 0;
    DY778UpdatePressSlide(state, gesture);
    DY778SpeedLockState lock = state.lock; double rate = state.session.before;
    int action = DY778SpeedLockComplete(&lock, gesture.state == UIGestureRecognizerStateEnded, state.armed,
                                       state.session.before, state.pressRate, &rate);
    if (!lock.locked) rate = DY778DefaultRestoreSpeed(state.owner, rate);
    state.lock = lock; state.settling = YES; state.settledRate = rate;
    return action;
}
static void DY778FinishPress(id owner, int action) {
    DY778PressState *state = DY778PressStateForOwner(owner, NO);
    if (!state.accepted || !state.session.active || !DY778SpeedStateCurrent(state)) { DY778RestorePress(owner); return; }
    DY778PressSession session = state.session; session.active = 0; state.session = session; state.accepted = NO;
    DY778EndPressUI(state); DY778SyncLockMarker(state); DY778WritePressSpeed(state, state.settledRate);
    if (action) DY778ShowSpeedResultToast(action > 0, state.settledRate);
    NSUInteger generation = ++state.generation; __weak id weakOwner = owner;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!weakOwner || !DY778SpeedLockDeferred(state.generation, generation, state.session.active)) return;
        if (!DY778SpeedStateCurrent(state)) { DY778RestorePress(weakOwner); return; }
        state.settling = NO;
        if (!state.lock.locked) DY778DiscardPress(weakOwner);
    });
}
static void DY778InstallRateGetter(NSString *name, NSString *method, BOOL classMethod) {
    Class cls = NSClassFromString(name); if (classMethod) cls = object_getClass(cls);
    SEL selector = NSSelectorFromString(method); NSString *key = [NSString stringWithFormat:@"%@%@.%@", classMethod ? @"+" : @"-", name, method];
    if ([DY778PlaybackInstalled containsObject:key] || !DY778PlaybackSignature(cls, selector, 'd', "")) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^double(id owner) {
        if (atomic_load_explicit(&DY778LongPressEnabled, memory_order_relaxed)) return atomic_load_explicit(&DY778LongPressRate, memory_order_relaxed);
        const void *hook = (__bridge const void *)key;
        if (DY778PlaybackFrameContains(DY778PlaybackStack, (__bridge const void *)owner, hook)) return 2;
        DY778PlaybackFrame frame = {(__bridge const void *)owner, hook, DY778PlaybackStack}; DY778PlaybackStack = &frame;
        @try { return ((double (*)(id, SEL))original)(owner, selector); }
        @finally { DY778PlaybackStack = frame.previous; }
    });
    DY778PlaybackInstall(cls, selector, replacement, &original, key);
}

static id DY778PressOwner(id owner) {
    id core = DY778Read(owner, @"speedContainer") ?: DY778Read(DY778Read(owner, @"dPlayerSpeed"), @"speedContainer");
    return core ?: owner;
}
static void DY778InstallGesture(NSString *name, NSString *method) {
    Class cls = NSClassFromString(name); SEL selector = NSSelectorFromString(method); NSString *key = [name stringByAppendingFormat:@".%@", method];
    if ([DY778PlaybackInstalled containsObject:key] || !DY778PlaybackSignature(cls, selector, 'v', "@")) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(id source, UIGestureRecognizer *gesture) {
        const void *hook = (__bridge const void *)key;
        if (DY778PlaybackFrameContains(DY778PlaybackStack, (__bridge const void *)source, hook)) return;
        DY778PlaybackFrame frame = {(__bridge const void *)source, hook, DY778PlaybackStack}; DY778PlaybackStack = &frame;
        BOOL enabled = atomic_load_explicit(&DY778LongPressEnabled, memory_order_relaxed);
        if (!NSThread.isMainThread || !enabled || ![gesture isKindOfClass:UIGestureRecognizer.class]) {
            @try { ((void (*)(id, SEL, id))original)(source, selector, gesture); } @finally { DY778PlaybackStack = frame.previous; } return;
        }
        // 旧版控制器可能把同一个识别器转发给核心容器。
        // 一个识别器对应一次会话，转发来的 End 不会把它切换两次。
        DY778SpeedBinding *binding = objc_getAssociatedObject(gesture, &DY778SpeedGestureKey);
        DY778PressState *state = binding.state;
        BOOL nested = NO;
        for (DY778PressGestureFrame *parent = DY778PressGestureStack; parent; parent = parent->previous) {
            DY778PressState *active = (__bridge DY778PressState *)parent->state;
            if (active.gesture == gesture) { nested = YES; break; }
        }
        if (nested) {
            @try { ((void (*)(id, SEL, id))original)(source, selector, gesture); } @finally { DY778PlaybackStack = frame.previous; } return;
        }
        id owner = DY778PressOwner(source);
        if (gesture.state == UIGestureRecognizerStateBegan) {
            DY778BeginPress(owner, gesture); state = DY778PressStateForOwner(owner, NO);
            binding = [DY778SpeedBinding new]; binding.state = state;
            objc_setAssociatedObject(gesture, &DY778SpeedGestureKey, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (state.owner) owner = state.owner;
        BOOL ending = gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed;
        int action = ending ? DY778PreparePressEnd(state, gesture) : 0;
        DY778PressGestureFrame gestureFrame = {(__bridge const void *)state, DY778PressGestureStack}; DY778PressGestureStack = &gestureFrame;
        @try { ((void (*)(id, SEL, id))original)(source, selector, gesture); }
        @finally {
            DY778PlaybackStack = frame.previous; DY778PressGestureStack = gestureFrame.previous;
            if (gesture.state == UIGestureRecognizerStateBegan) {
                if (state.session.active && DY778NativePressActive(owner)) {
                    state.accepted = YES; DY778BindSpeedTargets(state); DY778ApplyPressRate(owner);
                    // 原生竖屏 UI 可能在下一次主队列轮转时才挂上。
                    NSUInteger generation = state.generation; __weak id weakOwner = owner;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (weakOwner && state.generation == generation) DY778RefreshSpeedHint(state);
                    });
                } else DY778DiscardPress(owner);
            } else if (gesture.state == UIGestureRecognizerStateChanged && state.accepted) {
                DY778UpdatePressSlide(state, gesture); DY778ApplyPressRate(owner);
            } else if (ending && state.session.active) DY778FinishPress(owner, action);
        }
    });
    DY778PlaybackInstall(cls, selector, replacement, &original, key);
}
static void DY778InstallRestore(NSString *name, NSString *method, BOOL argument) {
    Class cls = NSClassFromString(name); SEL selector = NSSelectorFromString(method); NSString *key = [name stringByAppendingFormat:@".%@", method];
    if ([DY778PlaybackInstalled containsObject:key] || !DY778PlaybackSignature(cls, selector, 'v', argument ? "@" : "")) return;
    __block IMP original = NULL; IMP replacement;
    void (^restore)(id) = ^(id owner) { DY778RestorePress(DY778PressOwner(owner)); };
    if (argument) replacement = imp_implementationWithBlock(^(id owner, id data) { restore(owner); ((void (*)(id, SEL, id))original)(owner, selector, data); });
    else replacement = imp_implementationWithBlock(^(id owner) { restore(owner); ((void (*)(id, SEL))original)(owner, selector); });
    DY778PlaybackInstall(cls, selector, replacement, &original, key);
}
static BOOL DY778OwnsLockCompletion(id owner) {
    for (DY778PressGestureFrame *frame = DY778PressGestureStack; frame; frame = frame->previous) {
        DY778PressState *state = (__bridge DY778PressState *)frame->state;
        if (state.accepted && state.session.active && DY778SpeedStateCurrent(state) &&
            (state.owner == owner || DY778Read(state.owner, @"lockSpeedContainer") == owner || DY778PressOwner(owner) == state.owner)) return YES;
    }
    return NO;
}
static void DY778InstallLockEnd(NSString *name, BOOL withGesture) {
    Class cls = NSClassFromString(name);
    SEL selector = NSSelectorFromString(withGesture ? @"handleLongPressLockedDoubleSpeedEnded:gesture:" : @"handleLongPressLockedDoubleSpeedEnded:");
    NSString *key = [name stringByAppendingFormat:@".%@", NSStringFromSelector(selector)];
    if ([DY778PlaybackInstalled containsObject:key] || !DY778PlaybackSignature(cls, selector, 'v', withGesture ? "{@" : "{")) return;
    char pointType[64] = {0}; method_getArgumentType(class_getInstanceMethod(cls, selector), 2, pointType, sizeof(pointType));
    if (strcmp(pointType, @encode(CGPoint))) return;
    __block IMP original = NULL; IMP replacement;
    // 外层原生手势仍会收尾；只替换它写死的 2x/1x 提交。
    if (withGesture) replacement = imp_implementationWithBlock(^(id owner, CGPoint point, id gesture) {
        if (!DY778OwnsLockCompletion(owner)) ((void (*)(id, SEL, CGPoint, id))original)(owner, selector, point, gesture);
    });
    else replacement = imp_implementationWithBlock(^(id owner, CGPoint point) {
        if (!DY778OwnsLockCompletion(owner)) ((void (*)(id, SEL, CGPoint))original)(owner, selector, point);
    });
    DY778PlaybackInstall(cls, selector, replacement, &original, key);
}
static BOOL DY778IsLockFeedback(id text) {
    return [text isKindOfClass:NSString.class] && ([text containsString:@"倍速"] || [text containsString:@"速度"]) &&
        ([text containsString:@"取消"] || [text containsString:@"恢复"] || [text containsString:@"固定"] || [text containsString:@"锁定"]);
}
static void DY778InstallSpeedHintHooks(void) {
    Class cls = NSClassFromString(@"AFDFastSpeedView");
    SEL update = NSSelectorFromString(@"updateSpeedLockBottomWithText:Type:");
    NSString *key = @"AFDFastSpeedView.speedLockHint";
    if (![DY778PlaybackInstalled containsObject:key] && DY778PlaybackSignature(cls, update, 'v', "@q")) {
        __block IMP original = NULL;
        IMP replacement = imp_implementationWithBlock(^(UIView *view, NSString *text, long long type) {
            ((void (*)(id, SEL, id, long long))original)(view, update, text, type);
            DY778CorrectSpeedHint(view, DY778BoundSpeedState(view));
        }); DY778PlaybackInstall(cls, update, replacement, &original, key);
    }
    SEL layout = @selector(layoutSubviews); key = @"AFDFastSpeedView.speedLockLayout";
    if (![DY778PlaybackInstalled containsObject:key] && DY778PlaybackSignature(cls, layout, 'v', "")) {
        __block IMP original = NULL;
        IMP replacement = imp_implementationWithBlock(^(UIView *view) {
            ((void (*)(id, SEL))original)(view, layout);
            DY778CorrectSpeedHint(view, DY778BoundSpeedState(view));
        }); DY778PlaybackInstall(cls, layout, replacement, &original, key);
    }
    for (NSString *name in @[@"AWEDSpeedPortraitContainer", @"AWEPlayInteractionSpeedController", @"AFDPureModePageLongPressFastSpeedController"]) {
        cls = NSClassFromString(name); SEL selector = NSSelectorFromString(@"showToastWithText:"); key = [name stringByAppendingString:@".speedLockFeedback"];
        if (![DY778PlaybackInstalled containsObject:key] && DY778PlaybackSignature(cls, selector, 'v', "@")) {
            __block IMP original = NULL;
            IMP replacement = imp_implementationWithBlock(^(id owner, NSString *text) {
                DY778PressState *state = DY778BoundSpeedState(owner);
                if (state && (state.accepted || state.settling) && DY778IsLockFeedback(text)) return;
                ((void (*)(id, SEL, id))original)(owner, selector, text);
            }); DY778PlaybackInstall(cls, selector, replacement, &original, key);
        }
    }
    cls = NSClassFromString(@"AWEDSpeedPortraitContainer");
    SEL refresh = NSSelectorFromString(@"updateFastSpeedView:"); key = @"AWEDSpeedPortraitContainer.speedLockRefresh";
    if (![DY778PlaybackInstalled containsObject:key] && DY778PlaybackSignature(cls, refresh, 'v', "d")) {
        __block IMP original = NULL;
        IMP replacement = imp_implementationWithBlock(^(id owner, double rate) {
            DY778PressState *state = DY778BoundSpeedState(owner);
            ((void (*)(id, SEL, double))original)(owner, refresh, DY778PreferredSpeed(owner, rate));
            DY778RefreshSpeedHint(state);
        }); DY778PlaybackInstall(cls, refresh, replacement, &original, key);
    }
}

static id DY778PlaybackModel(id owner) {
    return DY778Read(owner, @"model") ?: DY778Read(owner, @"awemeModel");
}
static BOOL DY778PlaybackVisible(id owner) {
    UIViewController *controller = [owner isKindOfClass:UIViewController.class] ? owner : (DY778Read(owner, @"viewController") ?: DY778Read(owner, @"playerViewController"));
    return [controller isKindOfClass:UIViewController.class] && controller.isViewLoaded && controller.view.window && !controller.isBeingDismissed;
}
static void DY778PauseAtEnd(id owner) {
    SEL paused = NSSelectorFromString(@"setIsPausedByUserClick:");
    Method setter = class_getInstanceMethod([owner class], paused);
    if (setter) {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(setter)];
        if (signature.numberOfArguments == 3 && signature.methodReturnType[0] == 'v' && strchr("Bc", [signature getArgumentTypeAtIndex:2][0]))
            ((void (*)(id, SEL, BOOL))objc_msgSend)(owner, paused, YES);
    }
    SEL pause = NSSelectorFromString(@"pause");
    if (DY778PlaybackSignature([owner class], pause, 'B', "")) ((BOOL (*)(id, SEL))objc_msgSend)(owner, pause);
    else if (DY778PlaybackSignature([owner class], pause, 'v', "")) ((void (*)(id, SEL))objc_msgSend)(owner, pause);
    SEL animation = NSSelectorFromString(@"pauseWithAnimation");
    if (![DY778Read(owner, @"pauseBySingleClick") boolValue] && DY778PlaybackSignature([owner class], animation, 'v', ""))
        ((void (*)(id, SEL))objc_msgSend)(owner, animation);
}
static void DY778QueueEndPause(id owner, id model, id player) {
    if (!atomic_load_explicit(&DY778StopAtEnd, memory_order_relaxed) || !model) return;
    if (DY778Read(model, @"liveStreamURL") || !DY778Read(model, @"video")) return;
    DY778PlaybackEndState *token = [DY778PlaybackEndState new]; token.model = model; token.player = player;
    objc_setAssociatedObject(owner, &DY778EndTokenKey, token, OBJC_ASSOCIATION_RETAIN);
    __weak id weakOwner = owner;
    dispatch_block_t pause = ^{
        id current = weakOwner;
        if (!current || !atomic_load_explicit(&DY778StopAtEnd, memory_order_relaxed) || objc_getAssociatedObject(current, &DY778EndTokenKey) != token || DY778PlaybackModel(current) != model || !DY778PlaybackVisible(current)) return;
        id currentPlayer = DY778Read(current, @"playerController") ?: DY778Read(current, @"playerViewController");
        if (player && currentPlayer != player) return;
        DY778PauseAtEnd(current);
    };
    if (NSThread.isMainThread) pause();
    dispatch_async(dispatch_get_main_queue(), pause);
}
static void DY778InstallEndInvalidation(NSString *name, NSString *method) {
    Class cls = NSClassFromString(name); SEL selector = NSSelectorFromString(method); NSString *key = [name stringByAppendingFormat:@".%@", method];
    BOOL playing = [method isEqual:@"play"], modelSetter = [method isEqual:@"setModel:"];
    if ([DY778PlaybackInstalled containsObject:key] || !DY778PlaybackSignature(cls, selector, playing ? 'B' : 'v', modelSetter ? "@" : "")) return;
    __block IMP original = NULL; IMP replacement;
    if (playing) replacement = imp_implementationWithBlock(^BOOL(id owner) {
        const void *hook = (__bridge const void *)key;
        if (DY778PlaybackFrameContains(DY778PlaybackStack, (__bridge const void *)owner, hook)) return NO;
        DY778PlaybackFrame frame = {(__bridge const void *)owner, hook, DY778PlaybackStack}; DY778PlaybackStack = &frame;
        objc_setAssociatedObject(owner, &DY778EndTokenKey, nil, OBJC_ASSOCIATION_RETAIN);
        @try { return ((BOOL (*)(id,SEL))original)(owner,selector); }
        @finally { DY778PlaybackStack = frame.previous; }
    });
    else if (modelSetter) replacement = imp_implementationWithBlock(^(id owner, id model) {
        const void *hook = (__bridge const void *)key;
        if (DY778PlaybackFrameContains(DY778PlaybackStack, (__bridge const void *)owner, hook)) return;
        DY778PlaybackFrame frame = {(__bridge const void *)owner, hook, DY778PlaybackStack}; DY778PlaybackStack = &frame;
        objc_setAssociatedObject(owner, &DY778EndTokenKey, nil, OBJC_ASSOCIATION_RETAIN);
        @try { ((void (*)(id,SEL,id))original)(owner,selector,model); }
        @finally { DY778PlaybackStack = frame.previous; }
    });
    else replacement = imp_implementationWithBlock(^(id owner) {
        const void *hook = (__bridge const void *)key;
        if (DY778PlaybackFrameContains(DY778PlaybackStack, (__bridge const void *)owner, hook)) return;
        DY778PlaybackFrame frame = {(__bridge const void *)owner, hook, DY778PlaybackStack}; DY778PlaybackStack = &frame;
        objc_setAssociatedObject(owner, &DY778EndTokenKey, nil, OBJC_ASSOCIATION_RETAIN);
        @try { ((void (*)(id,SEL))original)(owner,selector); }
        @finally { DY778PlaybackStack = frame.previous; }
    });
    DY778PlaybackInstall(cls, selector, replacement, &original, key);
}
static void DY778InstallReplayGuard(NSString *name) {
    Class cls = NSClassFromString(name); SEL selector = NSSelectorFromString(@"replay"); NSString *key = [name stringByAppendingString:@".replay"];
    if ([DY778PlaybackInstalled containsObject:key] || !DY778PlaybackSignature(cls, selector, 'v', "")) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(id owner) {
        const void *hook = (__bridge const void *)key;
        if (DY778PlaybackFrameContains(DY778ReplayStack, (__bridge const void *)owner, hook)) return;
        DY778PlaybackFrame frame = {(__bridge const void *)owner, hook, DY778ReplayStack}; DY778ReplayStack = &frame;
        objc_setAssociatedObject(owner, &DY778EndTokenKey, nil, OBJC_ASSOCIATION_RETAIN);
        @try { ((void (*)(id, SEL))original)(owner, selector); }
        @finally { DY778ReplayStack = frame.previous; }
    });
    DY778PlaybackInstall(cls, selector, replacement, &original, key);
}
static void DY778InstallEndHook(NSString *name, NSString *method) {
    Class cls = NSClassFromString(name); SEL selector = NSSelectorFromString(method); NSString *key = [name stringByAppendingFormat:@".%@", method];
    if ([DY778PlaybackInstalled containsObject:key] || !DY778PlaybackSignature(cls, selector, 'v', "@")) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(id owner, id callbackPlayer) {
        const void *hook = (__bridge const void *)key;
        if (DY778PlaybackFrameContains(DY778PlaybackStack, (__bridge const void *)owner, hook)) return;
        DY778PlaybackFrame frame = {(__bridge const void *)owner, hook, DY778PlaybackStack}; DY778PlaybackStack = &frame;
        BOOL requested = atomic_load_explicit(&DY778StopAtEnd, memory_order_relaxed) && DY778ReplayStack == NULL;
        id model = requested ? DY778PlaybackModel(owner) : nil;
        if ([method isEqual:@"playerWillStartNextLoopFinished:"]) {
            DY778PlaybackEndState *pending = objc_getAssociatedObject(owner, &DY778EndTokenKey);
            requested = requested && pending && pending.model == model;
        }
        id player = requested ? (DY778Read(owner, @"playerController") ?: DY778Read(owner, @"playerViewController")) : nil;
        @try { ((void (*)(id, SEL, id))original)(owner, selector, callbackPlayer); }
        @finally {
            DY778PlaybackStack = frame.previous;
            if (requested && DY778PlaybackModel(owner) == model) DY778QueueEndPause(owner, model, player);
        }
    });
    DY778PlaybackInstall(cls, selector, replacement, &original, key);
}
static void DY778PlaybackReload(void) {
    atomic_store_explicit(&DY778StopAtEnd, DY778Bool(@"playback.stopAtEnd"), memory_order_relaxed);
    double stored = DY778Number(@"playback.longPressRate"), rate = DY778PlaybackRate(stored);
    if (!isfinite(stored) || stored != rate) [DY778Preferences() setDouble:rate forKey:@"playback.longPressRate"];
    double previousRate = atomic_exchange_explicit(&DY778LongPressRate, rate, memory_order_relaxed);
    BOOL enabled = DY778Bool(@"playback.longPressEnabled"); atomic_store_explicit(&DY778LongPressEnabled, enabled, memory_order_relaxed);
    if (!enabled || fabs(previousRate-rate) > .001) {
        for (id owner in DY778PressOwners.allObjects) DY778RestorePress(owner);
        DY778DismissToast(@"playback");
    }
}
void DY778InstallPlaybackHooks(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallPlaybackHooks(); }); return; }
    static dispatch_once_t once; dispatch_once(&once, ^{
        DY778PlaybackInstalled = [NSMutableSet set]; DY778PressOwners = [NSHashTable weakObjectsHashTable]; DY778PlaybackReload();
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSString *key = note.userInfo[@"key"]; if (!key.length || [key hasPrefix:@"playback."]) DY778PlaybackReload();
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            for (id owner in DY778PressOwners.allObjects) DY778RestorePress(owner);
        }];
    });
    DY778InstallRateGetter(@"AWEDSpeedBasicConfig", @"longPressSpeed", NO);
    DY778InstallRateGetter(@"AFDLongPressFastSpeedHelper", @"longPressFastSpeedValue", YES);
    DY778InstallRateGetter(@"AWEDSpeedPortraitContainer", @"longPressSpeedValue", NO);
    DY778InstallRateGetter(@"AWEDSpeedLockSpeedContainer", @"longPressSpeedValue", NO);
    for (NSString *name in @[@"AWEDSpeedCoreContainer", @"AWEPlayInteractionSpeedController", @"AFDPureModePageLongPressFastSpeedController"]) {
        DY778InstallRateGetter(name, @"longPressFastSpeedValue", NO);
        DY778InstallGesture(name, [name isEqual:@"AWEDSpeedCoreContainer"] ? @"handleFastSpeed:" : @"handleLongPressFastSpeed:");
        DY778InstallRestore(name, @"setData:", YES); DY778InstallRestore(name, @"reset", NO); DY778InstallRestore(name, @"viewWillDisappear", NO);
    }
    for (NSString *name in @[@"AWEDSpeedLockSpeedContainer", @"AWEPlayInteractionSpeedController", @"AFDPureModePageLongPressFastSpeedController"]) {
        DY778InstallLockEnd(name, ![name isEqualToString:@"AFDPureModePageLongPressFastSpeedController"]);
    }
    DY778InstallSpeedHintHooks();
    DY778InstallRestore(@"AWEDPlayerSpeedController", @"setData:", YES);
    DY778InstallRestore(@"AWEDPlayerSpeedController", @"reset", NO);
    DY778InstallRestore(@"AWEDPlayerSpeedController", @"viewWillDisappear", NO);
    for (NSString *name in @[@"AWEDPlayerVideoController", @"AWEDPlayerVideoController_Merge", @"AWEDPlayerViewController", @"AWEDPlayerViewController_Merge", @"AWEDPlayerFeedPlayerViewController", @"AWEAwemePlayVideoViewController"]) {
        DY778InstallReplayGuard(name);
        for (NSString *method in @[@"play", @"setModel:", @"reset"]) DY778InstallEndInvalidation(name,method);
        for (NSString *method in @[@"playerWillLoopPlaying:", @"playerWillStartNextLoop:", @"playerWillStartNextLoopFinished:"]) DY778InstallEndHook(name, method);
    }
}
