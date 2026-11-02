#import "DY778Playback.h"
#import "DY778Core.h"
#import "DY778PlaybackPolicy.h"

static BOOL DY778DefaultEnabled;
static double DY778DefaultSpeed = 1.25;
static NSHashTable *DY778DefaultOwners;
static NSMutableSet *DY778DefaultHooks;
static char DY778DefaultStateKey;
static _Thread_local DY778PlaybackFrame *DY778DefaultStack;

@interface DY778DefaultSpeedState : NSObject
@property(nonatomic, weak) id model;
@property(nonatomic) double before;
@property(nonatomic) double applied;
@property(nonatomic) BOOL owned;
@property(nonatomic) NSUInteger generation;
@end
@implementation DY778DefaultSpeedState @end

static BOOL DY778DefaultSignature(Class cls, SEL selector, char result, const char *arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char type[64]; method_getReturnType(method, type, sizeof(type));
    if (type[0] != result) return NO;
    for (unsigned i = 0; arguments[i]; i++) {
        method_getArgumentType(method, i + 2, type, sizeof(type));
        if (arguments[i] == 'B' ? (type[0] != 'B' && type[0] != 'c') : type[0] != arguments[i]) return NO;
    }
    return YES;
}
static BOOL DY778DefaultPressActive(id owner) {
    return [DY778Read(owner, @"isInLongPressSpeed") boolValue] ||
        [DY778Read(DY778Read(owner, @"speedContainer"), @"isInLongPressFastSpeed") boolValue];
}
static BOOL DY778DefaultVideo(id model) {
    id images = DY778Read(model, @"images"), albums = DY778Read(model, @"albumImages");
    return model && DY778Read(model, @"video") && !DY778Read(model, @"liveStreamURL") &&
        !([images isKindOfClass:NSArray.class] && [images count]) && !([albums isKindOfClass:NSArray.class] && [albums count]);
}
static BOOL DY778DefaultVisible(id owner) {
    UIView *view = DY778Read(owner, @"view");
    return UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
        [view isKindOfClass:UIView.class] && view.window && !view.hidden;
}
static double DY778DefaultRead(id owner) {
    if (!DY778DefaultSignature([owner class], @selector(playbackRate), 'f', "")) return NAN;
    return ((float (*)(id,SEL))objc_msgSend)(owner,@selector(playbackRate));
}
static void DY778DefaultWrite(id owner, double speed) {
    if (DY778DefaultSignature([owner class], NSSelectorFromString(@"setPlaybackRate:"), 'v', "f"))
        ((void (*)(id,SEL,float))objc_msgSend)(owner,NSSelectorFromString(@"setPlaybackRate:"),(float)speed);
}
static void DY778DefaultRestore(id owner) {
    DY778DefaultSpeedState *state = objc_getAssociatedObject(owner, &DY778DefaultStateKey);
    if (!state.owned || DY778DefaultPressActive(owner)) return;
    BOOL same = state.model && state.model == DY778Read(owner, @"awemeModel");
    state.owned = NO;
    if (same && fabs(DY778DefaultRead(owner) - state.applied) < .01) DY778DefaultWrite(owner, state.before);
}
double DY778DefaultRestoreSpeed(id owner, double speed) {
    if (!NSThread.isMainThread) return speed;
    id target = DY778Read(owner, @"playerProvider") ?: owner;
    DY778DefaultSpeedState *state = objc_getAssociatedObject(target, &DY778DefaultStateKey);
    if (!state.owned || !state.model || state.model != DY778Read(target, @"awemeModel") || fabs(speed-state.applied) >= .01) return speed;
    if (DY778DefaultEnabled) { state.applied = DY778DefaultSpeed; return DY778DefaultSpeed; }
    state.owned = NO; return state.before;
}
static void DY778DefaultApply(id owner, DY778DefaultSpeedState *state, id model, NSUInteger generation, unsigned retries) {
    if (state.generation != generation || DY778Read(owner, @"awemeModel") != model) return;
    if (!DY778DefaultEnabled) { DY778DefaultRestore(owner); return; }
    if (!DY778DefaultRateAllowed(YES, DY778DefaultVideo(model), DY778DefaultVisible(owner), DY778DefaultPressActive(owner))) return;
    double current = DY778DefaultRead(owner);
    if (!isfinite(current) || current <= 0 || current > 8) return;
    if (state.model != model) { state.model = model; state.owned = NO; }
    if (fabs(current-DY778DefaultSpeed) >= .001) {
        if (!state.owned) state.before = current;
        state.owned = YES; state.applied = DY778DefaultSpeed;
        DY778DefaultWrite(owner, DY778DefaultSpeed);
    }
    if (retries) {
        __weak id weakOwner = owner;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            id currentOwner = weakOwner;
            if (currentOwner) DY778DefaultApply(currentOwner, state, model, generation, retries-1);
        });
    }
}
static void DY778DefaultSchedule(id owner) {
    if (!NSThread.isMainThread || !DY778DefaultEnabled) return;
    DY778DefaultSpeedState *state = objc_getAssociatedObject(owner, &DY778DefaultStateKey);
    if (!state) { state = [DY778DefaultSpeedState new]; objc_setAssociatedObject(owner, &DY778DefaultStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    [DY778DefaultOwners addObject:owner];
    id model = DY778Read(owner, @"awemeModel"); NSUInteger generation = ++state.generation;
    if (!DY778DefaultVideo(model)) return;
    __weak id weakOwner = owner;
    dispatch_async(dispatch_get_main_queue(), ^{
        id current = weakOwner; if (current) DY778DefaultApply(current, state, model, generation, 1);
    });
}
static void DY778DefaultReload(void) {
    DY778DefaultEnabled = DY778Bool(@"playback.defaultEnabled"); DY778DefaultSpeed = DY778PlaybackRate(DY778Number(@"playback.defaultRate"));
    for (id owner in DY778DefaultOwners.allObjects) {
        DY778DefaultSpeedState *state = objc_getAssociatedObject(owner, &DY778DefaultStateKey); state.generation++;
        if (DY778DefaultEnabled) DY778DefaultSchedule(owner); else DY778DefaultRestore(owner);
    }
}
static void DY778DefaultInstall(NSString *name, NSString *arguments) {
    Class cls = NSClassFromString(@"AWEDPlayerSpeedController"); SEL selector = NSSelectorFromString(name);
    if ([DY778DefaultHooks containsObject:name] || !DY778DefaultSignature(cls, selector, 'v', arguments.UTF8String)) return;
    __block IMP original = NULL;
    void (^perform)(id, id, BOOL) = ^(id owner, id argument, BOOL flag) {
        const void *hook = (__bridge const void *)name;
        if (DY778PlaybackFrameContains(DY778DefaultStack, (__bridge const void *)owner, hook)) return;
        DY778PlaybackFrame frame = {(__bridge const void *)owner, hook, DY778DefaultStack}; DY778DefaultStack = &frame;
        @try {
            if ([arguments isEqual:@"@B"]) ((void (*)(id,SEL,id,BOOL))original)(owner,selector,argument,flag);
            else if (arguments.length) ((void (*)(id,SEL,id))original)(owner,selector,argument);
            else ((void (*)(id,SEL))original)(owner,selector);
        } @finally { DY778DefaultStack = frame.previous; }
        if (!NSThread.isMainThread) return;
        if ([name isEqual:@"viewWillDisappear"] || [name isEqual:@"reset"]) {
            DY778DefaultSpeedState *state = objc_getAssociatedObject(owner, &DY778DefaultStateKey); state.generation++;
            DY778DefaultRestore(owner); return;
        }
        if ([name isEqual:@"handleLongPressFastSpeed:"]) {
            if (![argument isKindOfClass:UIGestureRecognizer.class]) return;
            UIGestureRecognizerState value = [(UIGestureRecognizer *)argument state];
            if (value != UIGestureRecognizerStateEnded && value != UIGestureRecognizerStateCancelled && value != UIGestureRecognizerStateFailed) return;
            if (!DY778DefaultEnabled) { DY778DefaultRestore(owner); return; }
        }
        if (![arguments isEqual:@"@B"] || flag) DY778DefaultSchedule(owner);
    };
    IMP replacement;
    if ([arguments isEqual:@"@B"]) replacement = imp_implementationWithBlock(^(id owner, id player, BOOL playing) { perform(owner,player,playing); });
    else if (arguments.length) replacement = imp_implementationWithBlock(^(id owner,id data) { perform(owner,data,NO); });
    else replacement = imp_implementationWithBlock(^(id owner) { perform(owner,nil,NO); });
    BOOL installed = DY778Hook(cls,selector,replacement,&original);
    if (installed) [DY778DefaultHooks addObject:name]; else imp_removeBlock(replacement);
    DY778RecordHook([@"DY778 默认倍速 / " stringByAppendingString:name],installed);
}
void DY778InstallDefaultPlaybackHooks(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallDefaultPlaybackHooks(); }); return; }
    static dispatch_once_t once; dispatch_once(&once, ^{
        DY778DefaultOwners = [NSHashTable weakObjectsHashTable]; DY778DefaultHooks = [NSMutableSet set]; DY778DefaultReload();
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSString *key = note.userInfo[@"key"]; if (!key.length || [key hasPrefix:@"playback.default"]) DY778DefaultReload();
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            for (id owner in DY778DefaultOwners.allObjects) { DY778DefaultSpeedState *state = objc_getAssociatedObject(owner, &DY778DefaultStateKey); state.generation++; }
        }];
    });
    for (NSString *name in @[@"viewDidLoad", @"viewWillAppear", @"viewWillDisappear", @"reset"]) DY778DefaultInstall(name, @"");
    DY778DefaultInstall(@"setData:", @"@"); DY778DefaultInstall(@"onPlayerPlay:ifPlay:", @"@B");
    DY778DefaultInstall(@"handleLongPressFastSpeed:", @"@");
}
