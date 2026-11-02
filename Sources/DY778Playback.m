#import "DY778Playback.h"
#import "DY778Core.h"
#import "DY778PlaybackPolicy.h"
#import <stdatomic.h>

static atomic_bool DY778StopAtEnd, DY778LongPressEnabled;
static _Atomic(double) DY778LongPressRate = 2;
static NSMutableSet<NSString *> *DY778PlaybackInstalled;
static NSHashTable *DY778PressOwners;
static char DY778PressStateKey, DY778EndTokenKey;
static _Thread_local DY778PlaybackFrame *DY778PlaybackStack;
static _Thread_local DY778PlaybackFrame *DY778ReplayStack;

@interface DY778PressState : NSObject
@property(nonatomic) DY778PressSession session;
@property(nonatomic, weak) id target;
@property(nonatomic) SEL setter;
@property(nonatomic) char setterType;
@property(nonatomic) NSUInteger depth;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, weak) id model;
@property(nonatomic, copy) NSString *toastToken;
@end
@implementation DY778PressState
- (void)dealloc { DY778DismissSpeedToast(_toastToken); }
@end
@interface DY778PlaybackEndState : NSObject
@property(nonatomic, weak) id model;
@property(nonatomic, weak) id player;
@end
@implementation DY778PlaybackEndState @end

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
static DY778PressState *DY778PressStateForOwner(id owner, BOOL create) {
    DY778PressState *state = objc_getAssociatedObject(owner, &DY778PressStateKey);
    if (!state && create) { state = [DY778PressState new]; objc_setAssociatedObject(owner, &DY778PressStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return state;
}
static void DY778RestorePress(id owner) {
    DY778PressState *state = DY778PressStateForOwner(owner, NO); if (!state) return;
    __block double rate; id target, model; SEL setter; char type; NSUInteger generation; NSString *toastToken;
    @synchronized (state) {
        generation = ++state.generation;
        DY778PressSession session = state.session;
        if (!DY778PressEnd(&session, &rate)) return;
        state.session = session;
        target = state.target; setter = state.setter; type = state.setterType; model = state.model;
        state.target = nil; state.setter = NULL; state.model = nil;
        toastToken = state.toastToken; state.toastToken = nil;
    }
    DY778DismissSpeedToast(toastToken);
    void (^restore)(void) = ^{
        if (!target || !setter) return;
        rate = DY778DefaultRestoreSpeed(target, rate);
        if (type == 'f') ((void (*)(id, SEL, float))objc_msgSend)(target, setter, (float)rate);
        else ((void (*)(id, SEL, double))objc_msgSend)(target, setter, rate);
    };
    if (NSThread.isMainThread) { restore(); return; }
    __weak id weakOwner = owner;
    dispatch_async(dispatch_get_main_queue(), ^{
        id currentOwner = weakOwner; if (!currentOwner || !model) return;
        @synchronized (state) { if (state.generation != generation || state.session.active) return; }
        id currentModel = DY778Read(currentOwner, @"model") ?: DY778Read(currentOwner, @"awemeModel");
        if (currentModel == model) restore();
    });
}
static void DY778BeginPress(id owner, BOOL nativeBegan) {
    if (!atomic_load_explicit(&DY778LongPressEnabled, memory_order_relaxed)) return;
    DY778PressState *state = DY778PressStateForOwner(owner, YES);
    @synchronized (state) { if (state.session.active) return; }
    id target = DY778SpeedTarget(owner);
    double rate = DY778ReadRate(target, @"playbackRate");
    if (!isfinite(rate)) rate = DY778ReadRate(DY778Read(owner, @"speedManager"), @"currentSpeed");
    if (nativeBegan) rate = DY778ReadRate(owner, @"speedBeforeLongPress");
    SEL setter = NSSelectorFromString(@"changeSpeed:"); char type = 'd';
    if (DY778PlaybackSignature([owner class], setter, 'v', "d")) target = owner;
    else {
        setter = NSSelectorFromString(@"setPlaybackRate:");
        if (DY778PlaybackSignature([target class], setter, 'v', "f")) type = 'f';
        else if (!DY778PlaybackSignature([target class], setter, 'v', "d")) return;
    }
    id model = DY778Read(owner, @"model") ?: DY778Read(owner, @"awemeModel");
    @synchronized (state) {
        DY778PressSession session = state.session;
        if (!DY778PressBegin(&session, YES, rate)) return;
        state.session = session; state.target = target; state.setter = setter; state.setterType = type; state.model = model; state.generation++;
    }
    [DY778PressOwners addObject:owner];
}
static BOOL DY778NativePressActive(id owner) {
    SEL active = NSSelectorFromString(@"isInLongPressFastSpeed");
    if (DY778PlaybackSignature([owner class], active, 'B', ""))
        return ((BOOL (*)(id, SEL))objc_msgSend)(owner, active);
    UIView *view = DY778Read(owner, @"longPressFastSpeedView");
    if ([view isKindOfClass:UIView.class] && view.window && !view.hidden && view.alpha > .01) return YES;
    DY778PressState *state = DY778PressStateForOwner(owner, NO);
    double current = DY778ReadRate(DY778SpeedTarget(owner), @"playbackRate");
    return state && state.session.active && isfinite(current) && fabs(current - state.session.before) > .001;
}
static void DY778DiscardPress(id owner) {
    DY778PressState *state = DY778PressStateForOwner(owner, NO);
    if (!state) return;
    @synchronized (state) {
        DY778PressSession session = state.session; session.active = 0; state.session = session;
        state.target = nil; state.setter = NULL; state.model = nil; state.generation++;
        DY778DismissSpeedToast(state.toastToken); state.toastToken = nil;
    }
}
static void DY778MaybeShowPressToast(id owner, double rate, NSUInteger generation, unsigned retries) {
    DY778PressState *state = DY778PressStateForOwner(owner,NO);
    if (!state || state.generation != generation || !state.session.active || state.toastToken.length ||
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
    if (!state || !state.session.active || !atomic_load_explicit(&DY778LongPressEnabled, memory_order_relaxed)) return;
    id target = state.target; SEL setter = state.setter;
    if (!target || !setter) return;
    double rate = atomic_load_explicit(&DY778LongPressRate, memory_order_relaxed);
    double current = DY778ReadRate(target, @"playbackRate");
    if (!isfinite(current) || fabs(current - rate) >= .001) {
        if (state.setterType == 'f') ((void (*)(id, SEL, float))objc_msgSend)(target, setter, (float)rate);
        else ((void (*)(id, SEL, double))objc_msgSend)(target, setter, rate);
    }
    DY778MaybeShowPressToast(owner,rate,state.generation,2);
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
static void DY778InstallGesture(NSString *name, NSString *method) {
    Class cls = NSClassFromString(name); SEL selector = NSSelectorFromString(method); NSString *key = [name stringByAppendingFormat:@".%@", method];
    if ([DY778PlaybackInstalled containsObject:key] || !DY778PlaybackSignature(cls, selector, 'v', "@")) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(id owner, UIGestureRecognizer *gesture) {
        const void *hook = (__bridge const void *)key;
        if (DY778PlaybackFrameContains(DY778PlaybackStack, (__bridge const void *)owner, hook)) return;
        DY778PlaybackFrame frame = {(__bridge const void *)owner, hook, DY778PlaybackStack}; DY778PlaybackStack = &frame;
        if (!NSThread.isMainThread || ![gesture isKindOfClass:UIGestureRecognizer.class]) {
            @try { ((void (*)(id, SEL, id))original)(owner, selector, gesture); } @finally { DY778PlaybackStack = frame.previous; } return;
        }
        DY778PressState *state = DY778PressStateForOwner(owner, atomic_load_explicit(&DY778LongPressEnabled, memory_order_relaxed));
        BOOL outer = !state.depth; state.depth++;
        if (outer && gesture.state == UIGestureRecognizerStateBegan) DY778BeginPress(owner, NO);
        @try { ((void (*)(id, SEL, id))original)(owner, selector, gesture); }
        @finally {
            DY778PlaybackStack = frame.previous;
            if (state.depth) state.depth--;
            if (outer && gesture.state == UIGestureRecognizerStateBegan) {
                if (DY778NativePressActive(owner)) { DY778BeginPress(owner, YES); DY778ApplyPressRate(owner); }
                else DY778DiscardPress(owner);
            }
            if (outer && (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed)) DY778RestorePress(owner);
        }
    });
    DY778PlaybackInstall(cls, selector, replacement, &original, key);
}
static void DY778InstallRestore(NSString *name, NSString *method, BOOL argument) {
    Class cls = NSClassFromString(name); SEL selector = NSSelectorFromString(method); NSString *key = [name stringByAppendingFormat:@".%@", method];
    if ([DY778PlaybackInstalled containsObject:key] || !DY778PlaybackSignature(cls, selector, 'v', argument ? "@" : "")) return;
    __block IMP original = NULL; IMP replacement;
    if (argument) replacement = imp_implementationWithBlock(^(id owner, id data) { DY778RestorePress(owner); ((void (*)(id, SEL, id))original)(owner, selector, data); });
    else replacement = imp_implementationWithBlock(^(id owner) { DY778RestorePress(owner); ((void (*)(id, SEL))original)(owner, selector); });
    DY778PlaybackInstall(cls, selector, replacement, &original, key);
}
static void DY778InstallLockGuard(NSString *name) {
    Class cls = NSClassFromString(name); SEL selector = NSSelectorFromString(@"canShowLockSpeed"); NSString *key = [name stringByAppendingString:@".canShowLockSpeed"];
    if ([DY778PlaybackInstalled containsObject:key] || !DY778PlaybackSignature(cls, selector, 'B', "")) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^BOOL(id owner) {
        return atomic_load_explicit(&DY778LongPressEnabled, memory_order_relaxed) ? NO : ((BOOL (*)(id, SEL))original)(owner, selector);
    }); DY778PlaybackInstall(cls, selector, replacement, &original, key);
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
    atomic_store_explicit(&DY778LongPressRate, rate, memory_order_relaxed);
    BOOL enabled = DY778Bool(@"playback.longPressEnabled"); atomic_store_explicit(&DY778LongPressEnabled, enabled, memory_order_relaxed);
    if (!enabled) {
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
    for (NSString *name in @[@"AWEDSpeedCoreContainer", @"AWEPlayInteractionSpeedController", @"AFDPureModePageLongPressFastSpeedController"]) {
        DY778InstallRateGetter(name, @"longPressFastSpeedValue", NO);
        DY778InstallGesture(name, [name isEqual:@"AWEDSpeedCoreContainer"] ? @"handleFastSpeed:" : @"handleLongPressFastSpeed:");
        DY778InstallRestore(name, @"setData:", YES); DY778InstallRestore(name, @"reset", NO); DY778InstallRestore(name, @"viewWillDisappear", NO);
        DY778InstallLockGuard(name);
    }
    DY778InstallLockGuard(@"AWEDSpeedLockSpeedContainer");
    for (NSString *name in @[@"AWEDPlayerVideoController", @"AWEDPlayerVideoController_Merge", @"AWEDPlayerViewController", @"AWEDPlayerViewController_Merge", @"AWEDPlayerFeedPlayerViewController", @"AWEAwemePlayVideoViewController"]) {
        DY778InstallReplayGuard(name);
        for (NSString *method in @[@"play", @"setModel:", @"reset"]) DY778InstallEndInvalidation(name,method);
        for (NSString *method in @[@"playerWillLoopPlaying:", @"playerWillStartNextLoop:", @"playerWillStartNextLoopFinished:"]) DY778InstallEndHook(name, method);
    }
}
