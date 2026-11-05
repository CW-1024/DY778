#import "DY778LiveLike.h"
#import "DY778Core.h"
#import "DY778LiveLikePolicy.h"
#import <QuartzCore/QuartzCore.h>

// 观察原生手势，分别计数动作与上报。仅有动画
// 回调不算一次提交，且直播间总数还包含其他观众。
static NSString *const DY778LikeChannel = @"liveLike";
static char DY778LikeReceiptKey;
static SEL DY778LikeCountSelector(void) { return NSSelectorFromString(@"diggClicked:touchPoint:gapTime:isCountDigg:"); }
static const char *DY778LikeType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}
static BOOL DY778LikeMatchesSignature(NSMethodSignature *s, const char *result, NSArray<NSString *> *arguments) {
    if (!s || strcmp(DY778LikeType(s.methodReturnType), result) || s.numberOfArguments != arguments.count + 2) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        const char *actual = DY778LikeType([s getArgumentTypeAtIndex:i + 2]), *expected = arguments[i].UTF8String;
        if (!strcmp(expected, "B")) { if (strcmp(actual, "B") && strcmp(actual, "c")) return NO; }
        else if (!strcmp(expected, "@")) { if (actual[0] != '@') return NO; }
        else if (!strcmp(expected, "CGPoint")) { if (strcmp(actual, @encode(CGPoint))) return NO; }
        else if (strcmp(actual, expected)) return NO;
    }
    return YES;
}
static BOOL DY778LikeSignature(Class cls, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    return method && DY778LikeMatchesSignature([NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)], result, arguments);
}
static BOOL DY778LikeCanCall(id object, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    if (!object) return NO;
    if (DY778LikeSignature(object_getClass(object), selector, result, arguments)) return YES;
    @try { return DY778LikeMatchesSignature([object methodSignatureForSelector:selector], result, arguments); }
    @catch (__unused NSException *exception) { return NO; }
}
static id DY778LikeObject(id object, NSString *key) {
    id value = DY778Read(object, key); if (value) return value;
    SEL selector = NSSelectorFromString(key);
    if (!DY778LikeCanCall(object, selector, "@", @[])) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}
static NSString *DY778LikeDirectRoomID(id object) {
    for (NSString *key in @[@"roomID", @"roomIdStr", @"roomId"]) {
        NSString *identifier = DY778Identifier(DY778LikeObject(object, key));
        if (identifier.length && ![identifier isEqualToString:@"0"]) return identifier;
    }
    return nil;
}
static NSString *DY778LikeRoomID(id object) {
    return DY778LikeDirectRoomID(object) ?: DY778LikeDirectRoomID(DY778LikeObject(object, @"roomModel"));
}
static NSString *DY778LikeContextRoom(id fragment, id store, UIViewController *host) {
    NSArray<NSString *> * __attribute__((objc_precise_lifetime)) rooms = @[
        DY778LikeRoomID(DY778LikeObject(fragment, @"room")) ?: @"",
        DY778LikeRoomID(DY778LikeObject(fragment, @"roomService")) ?: @"",
        DY778LikeRoomID(DY778LikeObject(fragment, @"roomModel")) ?: @"",
        DY778LikeRoomID(DY778LikeObject(store, @"roomModel")) ?: @"",
        DY778LikeRoomID(DY778LikeObject(host, @"roomModel")) ?: @"",
        DY778LikeRoomID(DY778LikeObject(DY778LikeObject(host, @"roomConfig"), @"roomModel")) ?: @""];
    const char *candidates[6];
    for (NSUInteger i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) candidates[i] = rooms[i].UTF8String;
    const char *room = DY778LiveLikeResolveRoom(candidates, sizeof(candidates) / sizeof(candidates[0]));
    return room ? [NSString stringWithUTF8String:room] : nil;
}
static UIViewController *DY778LikeHost(UIView *view) {
    Class audience = NSClassFromString(@"IESLiveAudienceViewController");
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        UIViewController *c = (UIViewController *)r;
        for (NSUInteger i = 0; c && i < 20; i++, c = c.parentViewController)
            if ([c isKindOfClass:audience]) return c;
    }
    return nil;
}
static BOOL DY778LikeVisible(UIView *view) {
    if (!view.window || view.window != DY778ActiveWindow()) return NO;
    for (UIView *v = view; v; v = v.superview) if (v.hidden || v.alpha < .01) return NO;
    return YES;
}

@interface DY778LikeRun : NSObject {
@public DY778LiveLikeProgress progress;
}
@property(nonatomic, strong) id store;
@property(nonatomic, strong) id fragment;
@property(nonatomic, weak) UIViewController *host;
@property(nonatomic, weak) UIView *surface;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, copy) NSString *accountID;
@property(nonatomic) CGPoint point;
@property(nonatomic) NSUInteger misses;
@end
@implementation DY778LikeRun
@end

@interface DY778LikeCapture : NSObject
@property(nonatomic, strong) id store;
@property(nonatomic, strong) id fragment;
@property(nonatomic) CGPoint point;
@property(nonatomic) BOOL counting;
@property(nonatomic) BOOL generated;
@property(nonatomic) BOOL accepted;
@property(nonatomic) double nativeGap;
@end
@implementation DY778LikeCapture
@end
// 仅在主线程使用，对应同步的原生调用栈。
static DY778LikeCapture *DY778LikeCurrentCapture;

@interface DY778LikeReceipt : NSObject
@property(nonatomic) unsigned credit;
@property(nonatomic) BOOL handled;
@end
@implementation DY778LikeReceipt
@end

@interface DY778LikeCoordinator : NSObject
@property(atomic, strong) DY778LikeRun *run;
@property(nonatomic, strong) NSTimer *timer;
+ (instancetype)shared;
- (void)stop:(NSString *)message;
- (void)start:(DY778LikeCapture *)capture gesture:(UITapGestureRecognizer *)gesture;
- (void)tick;
- (void)showProgress;
- (void)received:(DY778LikeReceipt *)receipt run:(DY778LikeRun *)run success:(BOOL)success;
@end

@implementation DY778LikeCoordinator
+ (instancetype)shared {
    static DY778LikeCoordinator *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [self new]; }); return value;
}
- (BOOL)valid:(DY778LikeRun *)run {
    return run && DY778Bool(@"liveLike.enabled") && UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
        DY778LikeVisible(run.surface) && DY778LikeVisible(run.host.viewIfLoaded) && !run.host.isBeingDismissed &&
        !run.host.isMovingFromParentViewController && !run.host.presentedViewController &&
        [DY778LikeContextRoom(run.fragment, run.store, run.host) isEqualToString:run.roomID] &&
        DY778LiveLikeSameAccount(run.accountID.UTF8String, DY778CurrentAccountID().UTF8String);
}
- (void)stop:(NSString *)message {
    BOOL hadRun = self.run != nil;
    self.run = nil; [self.timer invalidate]; self.timer = nil;
    DY778DismissToast(DY778LikeChannel);
    if (hadRun && message.length) DY778ShowToast(DY778LikeChannel, message, NO, NO);
}
- (void)start:(DY778LikeCapture *)capture gesture:(UITapGestureRecognizer *)gesture {
    if (self.run) return;
    if (!capture.accepted || !capture.store || !capture.fragment) {
        DY778ShowToast(DY778LikeChannel, @"本次未能开始自动点赞，请稍后重试", NO, NO); return;
    }
    UIViewController *host = DY778LikeHost(gesture.view);
    NSString *room = DY778LikeContextRoom(capture.fragment, capture.store, host);
    NSString *account = DY778CurrentAccountID() ?: @"";
    if (!host || !room.length) {
        DY778ShowToast(DY778LikeChannel, @"尚未取得当前直播间信息\n请重新进入直播后重试", NO, NO); return;
    }
    if (!DY778LikeCanCall(capture.store, DY778LikeCountSelector(), "v", @[@"B", @"CGPoint", @"d", @"B"])) {
        DY778ShowToast(DY778LikeChannel, @"当前版本的点赞接口暂不可用", NO, NO); return;
    }
    DY778LikeRun *run = [DY778LikeRun new];
    run.store = capture.store; run.fragment = capture.fragment; run.host = host;
    run.surface = gesture.view; run.roomID = room; run.accountID = account; run.point = capture.point;
    run->progress.target = DY778LiveLikeTarget(DY778Number(@"liveLike.target"));
    run->progress.interval = DY778LiveLikeInterval(DY778Number(@"liveLike.interval"));
    run->progress.pause = DY778LiveLikePause(DY778Number(@"liveLike.pause"));
    run->progress.nextAction = CACurrentMediaTime() + DY778LiveLikeInitialDelay(run->progress.interval, capture.nativeGap);
    if (![self valid:run]) {
        DY778ShowToast(DY778LikeChannel, @"请在直播画面双击开始\n如有弹出面板，请先收起", NO, NO); return;
    }
    self.run = run;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:.1 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf tick]; }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self showProgress];
}
- (void)showProgress {
    DY778LikeRun *run = self.run; if (!run) return;
    DY778ShowToast(DY778LikeChannel, [NSString stringWithFormat:@"自动点赞中 %u/%u", run->progress.emitted, run->progress.target], YES, NO);
}
- (void)tick {
    DY778LikeRun *run = self.run; if (!run) return;
    if (![self valid:run]) { [self stop:nil]; return; }
    double now = CACurrentMediaTime();
    if (DY778LiveLikeTimedOut(&run->progress, now)) { [self stop:@"点赞提交暂未完成，已停止本轮"]; return; }
    if (!DY778LiveLikeCanEmit(&run->progress, now)) return;
    DY778LikeCapture *capture = [DY778LikeCapture new]; capture.generated = YES;
    DY778LikeCapture *previous = DY778LikeCurrentCapture; DY778LikeCurrentCapture = capture;
    @try {
        ((void (*)(id, SEL, BOOL, CGPoint, double, BOOL))objc_msgSend)(run.store, DY778LikeCountSelector(), YES, run.point,
            DY778LiveLikeNativeGap(run->progress.interval), YES);
    } @catch (__unused NSException *exception) {
        [self stop:@"当前直播点赞暂不可用，已停止本轮"];
    } @finally { DY778LikeCurrentCapture = previous; }
    if (self.run != run) return;
    if (!capture.accepted) {
        run->progress.nextAction = now + run->progress.interval;
        if (++run.misses >= 3) [self stop:@"当前直播未响应点赞，已停止本轮"];
        return;
    }
    run.misses = 0;
    [self showProgress];
}
- (void)received:(DY778LikeReceipt *)receipt run:(DY778LikeRun *)run success:(BOOL)success {
    if (self.run != run || receipt.handled || !receipt.credit) return;
    receipt.handled = YES;
    if (![self valid:run]) { [self stop:nil]; return; }
    if (!DY778LiveLikeConfirm(&run->progress, receipt.credit, success, CACurrentMediaTime())) {
        if (!success) [self stop:@"点赞提交未成功，已停止本轮"];
        return;
    }
    if (DY778LiveLikeComplete(&run->progress)) {
        [self stop:nil];
    } else [self showProgress];
}
@end

static IMP DY778LikeOriginalGesture, DY778LikeOriginalPost;
static IMP DY778LikeOriginalCount[2], DY778LikeOriginalClick[2], DY778LikeOriginalReaction[2];
static IMP DY778LikeOriginalUnmount[2], DY778LikeOriginalDisappear[2];
static IMP DY778LikeOriginalSetRoom[2];
static IMP DY778LikeOriginalAudienceDisappear, DY778LikeOriginalAudienceResign, DY778LikeOriginalAudienceLeave;
static BOOL DY778LikeReady;

static void DY778LikeGesture(id service, SEL cmd, id argument) {
    if (!NSThread.isMainThread || !DY778Bool(@"liveLike.enabled") || DY778LikeCurrentCapture ||
        ![argument isKindOfClass:UITapGestureRecognizer.class]) {
        ((void (*)(id, SEL, id))DY778LikeOriginalGesture)(service, cmd, argument); return;
    }
    UITapGestureRecognizer *gesture = argument;
    if (gesture.numberOfTapsRequired != 2 || gesture.state != UIGestureRecognizerStateRecognized || !DY778LikeHost(gesture.view)) {
        ((void (*)(id, SEL, id))DY778LikeOriginalGesture)(service, cmd, argument); return;
    }
    if (!DY778LikeReady) {
        ((void (*)(id, SEL, id))DY778LikeOriginalGesture)(service, cmd, argument);
        DY778ShowToast(DY778LikeChannel, @"当前版本暂不支持直播自动点赞", NO, NO); return;
    }
    DY778LikeCoordinator *coordinator = DY778LikeCoordinator.shared;
    BOOL stopping = coordinator.run != nil;
    if (stopping) [coordinator stop:@"已停止自动点赞"];
    DY778LikeCapture *capture = [DY778LikeCapture new], *previous = DY778LikeCurrentCapture;
    DY778LikeCurrentCapture = capture;
    @try { ((void (*)(id, SEL, id))DY778LikeOriginalGesture)(service, cmd, argument); }
    @finally { DY778LikeCurrentCapture = previous; }
    if (!stopping) [coordinator start:capture gesture:gesture];
}
static void DY778LikeCountCall(id store, SEL cmd, BOOL start, CGPoint point, double gap, BOOL count, IMP original, BOOL shortForm) {
    DY778LikeCapture *capture = NSThread.isMainThread ? DY778LikeCurrentCapture : nil;
    BOOL previousCounting = capture.counting;
    if (capture) { capture.store = store; capture.point = point; capture.counting = count; capture.nativeGap = gap; }
    @try {
        if (shortForm) ((void (*)(id, SEL, BOOL, CGPoint, double))original)(store, cmd, start, point, gap);
        else ((void (*)(id, SEL, BOOL, CGPoint, double, BOOL))original)(store, cmd, start, point, gap, count);
    } @finally { capture.counting = previousCounting; }
}
static void DY778LikeReactionCall(id fragment, SEL cmd, CGPoint point, IMP original) {
    DY778LikeCapture *capture = NSThread.isMainThread ? DY778LikeCurrentCapture : nil;
    if (capture.counting && !capture.accepted) {
        capture.fragment = fragment;
        if (!capture.generated) capture.accepted = YES;
        else {
            DY778LikeRun *run = DY778LikeCoordinator.shared.run;
            if (run && run.store == capture.store && run.fragment == fragment)
                capture.accepted = DY778LiveLikeAccept(&run->progress, CACurrentMediaTime());
        }
    }
    ((void (*)(id, SEL, CGPoint))original)(fragment, cmd, point);
}
static void DY778LikeFragmentLeaving(id fragment) {
    if (!NSThread.isMainThread) return;
    if (DY778LikeCoordinator.shared.run.fragment == fragment) [DY778LikeCoordinator.shared stop:nil];
}
static void DY778LikeFragmentSetRoom(id fragment, id room) {
    if (!NSThread.isMainThread) return;
    DY778LikeRun *run = DY778LikeCoordinator.shared.run;
    if (run.fragment == fragment && ![DY778LikeRoomID(room) isEqualToString:run.roomID])
        [DY778LikeCoordinator.shared stop:nil];
}
#define DY778_LIKE_VARIANT(N) \
static void DY778LikeCount##N(id s, SEL c, BOOL b, CGPoint p, double d, BOOL count) { DY778LikeCountCall(s,c,b,p,d,count,DY778LikeOriginalCount[N],NO); } \
static void DY778LikeClick##N(id s, SEL c, BOOL b, CGPoint p, double d) { DY778LikeCountCall(s,c,b,p,d,YES,DY778LikeOriginalClick[N],YES); } \
static void DY778LikeReaction##N(id s, SEL c, CGPoint p) { DY778LikeReactionCall(s,c,p,DY778LikeOriginalReaction[N]); } \
static void DY778LikeUnmount##N(id s, SEL c) { DY778LikeFragmentLeaving(s); ((void (*)(id,SEL))DY778LikeOriginalUnmount[N])(s,c); } \
static void DY778LikeDisappear##N(id s, SEL c) { DY778LikeFragmentLeaving(s); ((void (*)(id,SEL))DY778LikeOriginalDisappear[N])(s,c); } \
static void DY778LikeSetRoom##N(id s, SEL c, id r, id context, id track) { DY778LikeFragmentSetRoom(s,r); ((void (*)(id,SEL,id,id,id))DY778LikeOriginalSetRoom[N])(s,c,r,context,track); }
DY778_LIKE_VARIANT(0)
DY778_LIKE_VARIANT(1)
#undef DY778_LIKE_VARIANT

// HTSLiveApiRequest.callback 收到 (解析后的模型, NSError)。包装前先校验
// block 的 ABI；保留原始回调与请求数据。
typedef struct { void *isa; int flags, reserved; void *invoke; void *descriptor; } DY778LikeBlockLayout;
static BOOL DY778LikeCallbackCompatible(id callback) {
    if (!callback || ![callback isKindOfClass:NSClassFromString(@"NSBlock")]) return NO;
    const DY778LikeBlockLayout *block = (__bridge const void *)callback;
    if (!(block->flags & (1 << 30)) || !block->descriptor) return NO;
    const uint8_t *descriptor = block->descriptor;
    descriptor += sizeof(unsigned long) * 2;
    if (block->flags & (1 << 25)) descriptor += sizeof(void *) * 2;
    const char *types = *(const char *const *)descriptor;
    if (!types) return NO;
    NSMethodSignature *s = [NSMethodSignature signatureWithObjCTypes:types];
    return !strcmp(s.methodReturnType, "v") && s.numberOfArguments == 3 &&
        [s getArgumentTypeAtIndex:1][0] == '@' && [s getArgumentTypeAtIndex:2][0] == '@';
}
static void DY778LikeOnMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}
static id DY778LikePost(id api, SEL cmd, id request) {
    DY778LikeRun *run = DY778LikeCoordinator.shared.run;
    if (!run) return ((id (*)(id, SEL, id))DY778LikeOriginalPost)(api, cmd, request);
    NSString *path = DY778Read(request, @"path");
    if (run && !objc_getAssociatedObject(request, &DY778LikeReceiptKey) && [path isKindOfClass:NSString.class] &&
        ([path isEqual:@"/room/like/"] || [path isEqual:@"/room/digg/"])) {
        NSDictionary *parameters = DY778Read(request, @"parameters");
        NSString *room = [parameters isKindOfClass:NSDictionary.class] ? DY778Identifier(parameters[@"room_id"]) : nil;
        id count = [parameters isKindOfClass:NSDictionary.class] ? parameters[@"count"] : nil;
        id callback = DY778Read(request, @"callback");
        if ([room isEqual:run.roomID] && [count respondsToSelector:@selector(longLongValue)] &&
            [count longLongValue] > 0 && DY778LikeCallbackCompatible(callback)) {
            unsigned batch = (unsigned)MIN([count longLongValue], DY778LiveLikeMaximumTarget);
            DY778LikeReceipt *receipt = [DY778LikeReceipt new];
            void (^original)(id, id) = [callback copy];
            void (^wrapped)(id, id) = ^(id model, id error) {
                @try { original(model, error); }
                @finally {
                    BOOL success = model != nil && error == nil;
                    DY778LikeOnMain(^{ [DY778LikeCoordinator.shared received:receipt run:run success:success]; });
                }
            };
            if (DY778Write(request, @"callback", [wrapped copy])) {
                objc_setAssociatedObject(request, &DY778LikeReceiptKey, receipt, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                DY778LikeOnMain(^{
                    if (DY778LikeCoordinator.shared.run == run)
                        receipt.credit = DY778LiveLikeAssign(&run->progress, batch);
                });
            }
        }
    }
    return ((id (*)(id, SEL, id))DY778LikeOriginalPost)(api, cmd, request);
}
static void DY778LikeAudienceLeaving(id host) {
    if (NSThread.isMainThread && DY778LikeCoordinator.shared.run.host == host) [DY778LikeCoordinator.shared stop:nil];
}
static void DY778LikeAudienceDisappear(id host, SEL cmd, BOOL animated) {
    DY778LikeAudienceLeaving(host);
    ((void (*)(id, SEL, BOOL))DY778LikeOriginalAudienceDisappear)(host, cmd, animated);
}
static void DY778LikeAudienceResign(id host, SEL cmd, id room) {
    DY778LikeAudienceLeaving(host);
    ((void (*)(id, SEL, id))DY778LikeOriginalAudienceResign)(host, cmd, room);
}
static void DY778LikeAudienceLeave(id host, SEL cmd) {
    DY778LikeAudienceLeaving(host);
    ((void (*)(id, SEL))DY778LikeOriginalAudienceLeave)(host, cmd);
}
static void DY778LikeInstall(NSString *name, NSString *selector, const char *result, NSArray *arguments, IMP replacement, IMP *original) {
    if (*original) return;
    Class cls = NSClassFromString(name); SEL sel = NSSelectorFromString(selector);
    BOOL installed = DY778LikeSignature(cls, sel, result, arguments) && DY778Hook(cls, sel, replacement, original);
    DY778RecordHook([NSString stringWithFormat:@"直播点赞 / %@.%@", name, selector], installed);
}
void DY778InstallLiveLikeHooks(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallLiveLikeHooks(); }); return; }
    DY778LikeInstall(@"IESLiveRoomAllGestureService", @"respondAction:", "v", @[@"@"], (IMP)DY778LikeGesture, &DY778LikeOriginalGesture);
    DY778LikeInstall(@"HTSLiveApi", @"post:", "@", @[@"@"], (IMP)DY778LikePost, &DY778LikeOriginalPost);
    NSArray *stores = @[@"HTSLiveDiggStore", @"_TtC25IESLiveCommunitySwiftImpl16HTSLiveDiggStore"];
    NSArray *fragments = @[@"HTSLiveDiggFragment", @"HTSLiveDiggSwiftFragment"];
    IMP counts[] = {(IMP)DY778LikeCount0, (IMP)DY778LikeCount1}, clicks[] = {(IMP)DY778LikeClick0, (IMP)DY778LikeClick1};
    IMP reactions[] = {(IMP)DY778LikeReaction0, (IMP)DY778LikeReaction1};
    IMP unmounts[] = {(IMP)DY778LikeUnmount0, (IMP)DY778LikeUnmount1}, disappears[] = {(IMP)DY778LikeDisappear0, (IMP)DY778LikeDisappear1};
    IMP setRooms[] = {(IMP)DY778LikeSetRoom0, (IMP)DY778LikeSetRoom1};
    for (NSUInteger i = 0; i < sizeof(counts) / sizeof(counts[0]); i++) {
        DY778LikeInstall(stores[i], NSStringFromSelector(DY778LikeCountSelector()), "v", @[@"B", @"CGPoint", @"d", @"B"], counts[i], &DY778LikeOriginalCount[i]);
        DY778LikeInstall(stores[i], @"diggClicked:touchPoint:gapTime:", "v", @[@"B", @"CGPoint", @"d"], clicks[i], &DY778LikeOriginalClick[i]);
        DY778LikeInstall(fragments[i], @"dispatchOwnDiggMessageWithTouchPoint:", "v", @[@"CGPoint"], reactions[i], &DY778LikeOriginalReaction[i]);
        DY778LikeInstall(fragments[i], @"componentUnmount", "v", @[], unmounts[i], &DY778LikeOriginalUnmount[i]);
        DY778LikeInstall(fragments[i], @"componentDidDisappear", "v", @[], disappears[i], &DY778LikeOriginalDisappear[i]);
        DY778LikeInstall(fragments[i], @"setRoom:componentContext:trackContext:", "v", @[@"@", @"@", @"@"], setRooms[i], &DY778LikeOriginalSetRoom[i]);
    }
    DY778LikeInstall(@"IESLiveAudienceViewController", @"viewWillDisappear:", "v", @[@"B"], (IMP)DY778LikeAudienceDisappear, &DY778LikeOriginalAudienceDisappear);
    DY778LikeInstall(@"IESLiveAudienceViewController", @"roomWillResignActive:", "v", @[@"@"], (IMP)DY778LikeAudienceResign, &DY778LikeOriginalAudienceResign);
    DY778LikeInstall(@"IESLiveAudienceViewController", @"onStartLeaveRoomAnimation", "v", @[], (IMP)DY778LikeAudienceLeave, &DY778LikeOriginalAudienceLeave);
    DY778LikeReady = DY778LikeOriginalGesture && DY778LikeOriginalPost &&
        ((DY778LikeOriginalCount[0] && DY778LikeOriginalClick[0] && DY778LikeOriginalReaction[0]) ||
         (DY778LikeOriginalCount[1] && DY778LikeOriginalClick[1] && DY778LikeOriginalReaction[1]));
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue
                       usingBlock:^(__unused NSNotification *note) { [DY778LikeCoordinator.shared stop:nil]; }];
        [center addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSString *key = note.userInfo[@"key"];
            if (!key.length || [key hasPrefix:@"liveLike."]) [DY778LikeCoordinator.shared stop:nil];
        }];
    });
}
