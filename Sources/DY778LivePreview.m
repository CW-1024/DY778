#import "DY778LiveInfo.h"
#import <QuartzCore/QuartzCore.h>
#import <errno.h>
#import <limits.h>
#import <stdlib.h>
#import <string.h>
static char DY778PreviewStateKey;
typedef NS_ENUM(NSInteger, DY778PreviewDisplayMode) { DY778PreviewDisplayModeDisabled, DY778PreviewDisplayModeFormatted, DY778PreviewDisplayModePrecise };
@protocol DY778PreviewRoomAPI <NSObject>
- (instancetype)initWithRoomID:(id)room;
- (void)fetchRoomInfoWithRoomID:(id)room completion:(id)completion;
@end
@interface DY778PreviewFormatter : NSObject
+ (NSString *)formatViewerCount:(long long)count;
+ (NSString *)preciseViewerCount:(long long)count;
@end
@implementation DY778PreviewFormatter

+ (NSString *)formatViewerCount:(long long)count {
    char text[40]; DY778LiveViewerCountLabel(text,sizeof(text),count,true);
    return [NSString stringWithUTF8String:text];
}

+ (NSString *)preciseViewerCount:(long long)count {
    char text[40]; DY778LiveViewerCountLabel(text,sizeof(text),count,false);
    return [NSString stringWithUTF8String:text];
}

@end

static id DY778PreviewValueForKey(id object, NSString *key) {
    if (!object || object == [NSNull null]) {
        return nil;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        id value = [object objectForKey:key];
        return value == [NSNull null] ? nil : value;
    }
    // 私有字段在不同版本中可能缺失，读取时避免抛出异常。
    Class objectClass = [object class];
    if (![object respondsToSelector:NSSelectorFromString(key)] &&
        !class_getInstanceVariable(objectClass, key.UTF8String) &&
        !class_getInstanceVariable(objectClass, [@"_" stringByAppendingString:key].UTF8String)) {
        return nil;
    }
    @try {
        id value = [object valueForKey:key];
        return value == [NSNull null] ? nil : value;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSNumber *DY778PreviewOnlineCount(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        value = [value stringValue];
    }
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
        return nil;
    }
    const char *digits = [value UTF8String];
    if (!digits || strlen(digits) != [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) {
        return nil;
    }
    for (const char *cursor = digits; *cursor; ++cursor) {
        if (*cursor < '0' || *cursor > '9') {
            return nil;
        }
    }
    errno = 0;
    char *end = NULL;
    unsigned long long count = strtoull(digits, &end, 10);
    if (errno == ERANGE || end == digits || *end || count > LLONG_MAX) {
        return nil;
    }
    return @((long long)count);
}

static id DY778PreviewDecodeRoomData(id object) {
    NSData *data = nil;
    if ([object isKindOfClass:[NSString class]]) {
        data = [object dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([object isKindOfClass:[NSData class]]) {
        data = object;
    } else {
        return object;
    }
    if (data.length == 0 || data.length > 1024 * 1024) {
        return nil;
    }
    id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [decoded isKindOfClass:[NSDictionary class]] ? decoded : nil;
}

static NSString *DY778PreviewRoomID(id room) {
    for (NSString *key in @[@"roomID", @"idStr", @"id_str", @"id"]) {
        NSNumber *number = DY778PreviewOnlineCount(DY778PreviewValueForKey(room, key));
        if (number.longLongValue > 0) {
            return number.stringValue;
        }
    }
    return nil;
}

static BOOL DY778PreviewIsRecommendationPreview(UIViewController *controller) {
    id viewModel = DY778PreviewValueForKey(controller, @"viewModel");
    if ([DY778PreviewValueForKey(controller, @"showInSearchResult") boolValue] ||
        [DY778PreviewValueForKey(viewModel, @"showInSearchResult") boolValue]) {
        return NO;
    }
    // 优先通过来源字段确认卡片是否来自推荐页。
    NSNumber *isHomepageHot = DY778PreviewValueForKey(viewModel, @"isFromHomepageHot");
    if (isHomepageHot) {
        return isHomepageHot.boolValue;
    }
    for (id object in @[controller, viewModel ?: [NSNull null],
                        DY778PreviewValueForKey(controller, @"model") ?: [NSNull null]]) {
        NSString *source = DY778PreviewValueForKey(object, @"referString");
        if (![source isKindOfClass:[NSString class]] || source.length == 0) {
            continue;
        }
        source = source.lowercaseString;
        return [source isEqualToString:@"homepage_hot"] ||
               [source hasPrefix:@"homepage_hot_"] ||
               [source isEqualToString:@"homepage_recommend"] ||
               [source isEqualToString:@"recommend"];
    }
    return NO;
}

static void DY778PreviewAppendRoom(NSMutableArray *rooms, id room) {
    if (room && room != [NSNull null] && [rooms indexOfObjectIdenticalTo:room] == NSNotFound) {
        [rooms addObject:room];
    }
}

static void DY778PreviewAppendAwemeRooms(NSMutableArray *rooms, id model) {
    id rawModel = DY778PreviewValueForKey(model, @"rawDataRoomModel");
    DY778PreviewAppendRoom(rooms, DY778PreviewValueForKey(model, @"rawHTSLiveRoomModel"));
    DY778PreviewAppendRoom(rooms, DY778PreviewValueForKey(rawModel, @"rawRoom"));
    DY778PreviewAppendRoom(rooms, rawModel);
    DY778PreviewAppendRoom(rooms, DY778PreviewValueForKey(model, @"roomModel"));
}

static NSArray *DY778PreviewPreviewRooms(UIViewController *controller, UIView *statusLabel,
                                 NSString *__autoreleasing *currentRoomID) {
    *currentRoomID = nil;
    id viewModel = DY778PreviewValueForKey(controller, @"viewModel");
    id model = DY778PreviewValueForKey(controller, @"model") ?: DY778PreviewValueForKey(viewModel, @"model");
    id cellRoom = DY778PreviewValueForKey(model, @"cellRoom");
    NSMutableArray *feedRooms = [NSMutableArray array];
    DY778PreviewAppendAwemeRooms(feedRooms, model);
    DY778PreviewAppendAwemeRooms(feedRooms, cellRoom);
    // 类型化房间模型尚未解码时，推荐流可能先提供原始房间数据。
    DY778PreviewAppendRoom(feedRooms, DY778PreviewDecodeRoomData(DY778PreviewValueForKey(model, @"liveRoomRawData")));
    DY778PreviewAppendRoom(feedRooms, DY778PreviewDecodeRoomData(DY778PreviewValueForKey(cellRoom, @"liveRoomRawData")));
    NSString *roomID = DY778PreviewRoomID(model);
    for (id room in feedRooms) {
        if (!roomID) {
            roomID = DY778PreviewRoomID(room);
        }
    }
    if (model && !roomID) {
        return @[];
    }

    id streamView = DY778PreviewValueForKey(controller, @"streamView");
    id statusModel = DY778PreviewValueForKey(statusLabel, @"viewModel");
    NSMutableArray *rooms = [NSMutableArray array];
    DY778PreviewAppendRoom(rooms, DY778PreviewValueForKey(viewModel, @"room"));
    DY778PreviewAppendRoom(rooms, DY778PreviewValueForKey(controller, @"roomService"));
    DY778PreviewAppendRoom(rooms, DY778PreviewValueForKey(streamView, @"room"));
    for (id room in feedRooms) {
        DY778PreviewAppendRoom(rooms, room);
    }
    DY778PreviewAppendRoom(rooms, DY778PreviewValueForKey(statusModel, @"roomModel"));
    for (id room in rooms) {
        if (!roomID) {
            roomID = DY778PreviewRoomID(room);
        }
    }
    if (!roomID) {
        return @[];
    }
    *currentRoomID = roomID;
    NSMutableArray *matchingRooms = [NSMutableArray array];
    for (id room in rooms) {
        // 控制器复用时可能暂时保留上一个房间，必须按房间 ID 过滤。
        if ([DY778PreviewRoomID(room) isEqualToString:roomID]) {
            [matchingRooms addObject:room];
        }
    }
    return matchingRooms;
}

static NSNumber *DY778PreviewViewerCount(NSArray *rooms) {
    NSArray<NSString *> *keys = @[
        @"onlineCountByIM", @"userCount", @"user_count"
    ];
    for (id room in rooms) {
        for (NSString *key in keys) {
            NSNumber *count = DY778PreviewOnlineCount(DY778PreviewValueForKey(room, key));
            // 预览模型可能先返回零，在线人数填充后再使用有效值。
            if (count.longLongValue > 0) {
                return count;
            }
        }
    }
    return nil;
}

static NSNumber *DY778PreviewNetworkViewerCount(id object, NSString *roomID, NSUInteger depth) {
    if (!object || object == [NSNull null] || depth > 5) {
        return nil;
    }
    NSString *responseRoomID = DY778PreviewRoomID(object);
    if (responseRoomID && ![responseRoomID isEqualToString:roomID]) {
        return nil;
    }
    NSNumber *direct = DY778PreviewViewerCount(@[object]);
    if (direct) {
        return direct;
    }
    NSArray<NSString *> *nestedKeys = @[
        @"data", @"room", @"roomModel", @"room_info", @"roomInfo", @"liveRoom",
        @"live_room", @"stats", @"roomViewStats", @"response", @"result", @"data_list", @"rooms"
    ];
    for (NSString *key in nestedKeys) {
        id nested = DY778PreviewValueForKey(object, key);
        NSNumber *count = DY778PreviewNetworkViewerCount(nested, roomID, depth + 1);
        if (count) {
            return count;
        }
    }
    if ([object isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)object) {
            NSNumber *count = DY778PreviewNetworkViewerCount(item, roomID, depth + 1);
            if (count) {
                return count;
            }
        }
    }
    return nil;
}

static DY778PreviewDisplayMode DY778PreviewCurrentDisplayMode(void) {
    return !DY778Bool(@"liveInfo.viewers") ? DY778PreviewDisplayModeDisabled : [DY778String(@"liveInfo.countFormat") isEqual:@"exact"] ? DY778PreviewDisplayModePrecise : DY778PreviewDisplayModeFormatted;
}

#pragma mark - 预览徽章生命周期

static UIViewController *DY778PreviewPreviewControllerForView(UIView *view) {
    Class previewClass = NSClassFromString(@"AWELiveNewPreStreamViewController");
    if (!previewClass) {
        return nil;
    }
    for (UIResponder *responder = view; responder; responder = responder.nextResponder) {
        if (![responder isKindOfClass:[UIViewController class]]) {
            continue;
        }
        for (UIViewController *controller = (UIViewController *)responder;
             controller; controller = controller.parentViewController) {
            if ([controller isKindOfClass:previewClass]) {
                return controller;
            }
        }
    }
    return nil;
}

static UIView *DY778PreviewFindStatusLabel(UIView *root, NSUInteger depth) {
    if (!root || depth > 20) {
        return nil;
    }
    Class labelClass = NSClassFromString(@"AWELiveFeedStatusLabel");
    if (labelClass && [root isKindOfClass:labelClass]) {
        return root;
    }
    for (UIView *subview in root.subviews) {
        UIView *label = DY778PreviewFindStatusLabel(subview, depth + 1);
        if (label) {
            return label;
        }
    }
    return nil;
}

static BOOL DY778PreviewUsableRect(CGRect rect) {
    return !CGRectIsNull(rect) && !CGRectIsInfinite(rect) && !CGRectIsEmpty(rect) &&
           isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
           isfinite(rect.size.width) && isfinite(rect.size.height);
}

// 滑动转场的回调可能早于手势最终结果。
// 结合裁剪区域和容器控制器状态确认卡片是否真正离开。
static BOOL DY778PreviewPreviewIsMostlyVisible(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    UIWindow *window = root.window;
    if (!window) {
        return NO;
    }
    for (UIViewController *child = controller; child; child = child.parentViewController) {
        UIViewController *parent = child.parentViewController;
        if ([parent isKindOfClass:UINavigationController.class] &&
            ((UINavigationController *)parent).visibleViewController != child) {
            return NO;
        }
        if ([parent isKindOfClass:UITabBarController.class] &&
            ((UITabBarController *)parent).selectedViewController != child) {
            return NO;
        }
        UIViewController *presented = child.presentedViewController;
        if (presented.viewIfLoaded.window && !presented.isBeingDismissed) {
            return NO;
        }
    }
    CGRect frame = [root convertRect:root.bounds toView:window];
    if (!DY778PreviewUsableRect(frame)) {
        return NO;
    }
    CGRect visible = CGRectIntersection(frame, window.bounds);
    for (UIView *view = root; view; view = view.superview) {
        if (view.hidden || view.alpha <= 0.01) {
            return NO;
        }
        if (view.clipsToBounds) {
            CGRect clip = [view convertRect:view.bounds toView:window];
            if (!DY778PreviewUsableRect(clip)) {
                return NO;
            }
            visible = CGRectIntersection(visible, clip);
        }
    }
    return DY778PreviewUsableRect(visible) &&
        visible.size.width >= frame.size.width * 0.5 &&
        visible.size.height >= frame.size.height * 0.5;
}

static BOOL DY778PreviewScrollIsMoving(UIScrollView *scrollView) {
    return scrollView.tracking || scrollView.dragging || scrollView.decelerating;
}

static UIScrollView *DY778PreviewPreviewScrollView(UIView *root) {
    UIScrollView *nearest = nil;
    for (UIView *view = root.superview; view; view = view.superview) {
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *scrollView = (UIScrollView *)view;
            if (DY778PreviewScrollIsMoving(scrollView)) {
                return scrollView;
            }
            if (!nearest) nearest = scrollView;
        }
    }
    return nearest;
}

@interface DY778PreviewPreviewState : NSObject
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, weak) UIView *statusLabel;
@property (nonatomic, strong) DY778LiveCapsule *badge;
@property(nonatomic, strong) DY778LiveCapsule *durationBadge;
@property(nonatomic) double roomStart, lastRequestAt, stableAt;
@property(nonatomic) CGRect stableRect;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSTimer *visibilityTimer;
@property (nonatomic, strong) NSTimer *layoutRetryTimer;
@property (nonatomic, weak) UIScrollView *disappearingScrollView;
@property (nonatomic, assign) BOOL disappearancePending;
@property (nonatomic, assign) BOOL transitionInProgress;
@property (nonatomic, assign) NSUInteger disappearanceGeneration;
@property (nonatomic, assign) NSUInteger settledVisibilityPasses;
@property (nonatomic, assign) NSUInteger layoutRetriesRemaining;
@property (nonatomic, assign) CGRect lastVisibilityRect;
@property (nonatomic, assign) CGRect badgeAnchor;
@property (nonatomic, assign) CGRect badgeAnchorBounds;
@property (nonatomic, assign) UIEdgeInsets badgeAnchorInsets;
@property (nonatomic, strong) id defaultsObserver;
@property (nonatomic, strong) id backgroundObserver;
@property (nonatomic, strong) id foregroundObserver;
@property (nonatomic, strong) id roomAPI;
@property (nonatomic, strong) NSTimer *requestTimeoutTimer;
@property (nonatomic, copy) NSString *viewerRoomID;
@property (nonatomic, copy) NSString *requestRoomID;
@property (nonatomic, strong) NSNumber *lastViewerCount;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL refreshScheduled;
@property (nonatomic, assign) BOOL sampleRequested;
@property (nonatomic, assign) BOOL requestInFlight;
@property (nonatomic, assign) BOOL hasNetworkCount;
@property (nonatomic, assign) NSUInteger requestGeneration;
- (instancetype)initWithController:(UIViewController *)controller;
- (void)scheduleRefresh;
- (void)refresh;
- (void)activate;
- (void)beginDisappearance;
- (void)deactivate;
- (void)clearContent;
- (void)resetViewerCount;
@end

@implementation DY778PreviewPreviewState

- (instancetype)initWithController:(UIViewController *)controller {
    self = [super init];
    if (self) {
        _controller = controller;
        _badgeAnchor = CGRectNull;
        _layoutRetriesRemaining = 15;
        __weak DY778PreviewPreviewState *weakSelf = self;
        _defaultsObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:DY778PreferencesChangedNotification
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *notification) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [weakSelf scheduleRefresh];
                        });
                    }];
        _backgroundObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *notification) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [weakSelf pauseForApplicationState];
                        });
                    }];
        _foregroundObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *notification) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [weakSelf resumeForApplicationState];
                        });
                    }];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [_visibilityTimer invalidate];
    [_layoutRetryTimer invalidate];
    [_requestTimeoutTimer invalidate];
    if (_defaultsObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_defaultsObserver];
    }
    if (_backgroundObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_backgroundObserver];
    }
    if (_foregroundObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_foregroundObserver];
    }
    [_badge removeFromSuperview]; [_durationBadge removeFromSuperview];
}

- (void)stopLayoutRetry {
    [self.layoutRetryTimer invalidate];
    self.layoutRetryTimer = nil;
}

- (void)removeBadge {
    [self stopLayoutRetry];
    [self.badge removeFromSuperview];
    self.badge = nil; [self.durationBadge removeFromSuperview]; self.durationBadge = nil;
}

- (void)stopTimer {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)cancelDisappearance {
    [self.visibilityTimer invalidate];
    self.visibilityTimer = nil;
    self.disappearancePending = NO;
    self.transitionInProgress = NO;
    self.disappearingScrollView = nil;
    self.settledVisibilityPasses = 0;
    self.disappearanceGeneration += 1;
}

- (void)activate {
    BOOL wasActive = self.active;
    [self cancelDisappearance];
    self.active = YES;
    // 同一张卡片可能收到多次出现回调，不能因此重复发起请求。
    if (!wasActive) self.sampleRequested = YES;
    [self scheduleRefresh];
}

- (void)checkVisibilityAfterTransition {
    if (!self.active || !self.disappearancePending) {
        return;
    }
    UIView *root = self.controller.viewIfLoaded;
    UIScrollView *scrollView = DY778PreviewPreviewScrollView(root);
    if (self.transitionInProgress || DY778PreviewScrollIsMoving(scrollView) ||
        DY778PreviewScrollIsMoving(self.disappearingScrollView)) {
        self.settledVisibilityPasses = 0;
        return;
    }
    CGRect frame = root.window ? [root convertRect:root.bounds toView:root.window] : CGRectNull;
    self.settledVisibilityPasses = CGRectEqualToRect(frame, self.lastVisibilityRect)
        ? self.settledVisibilityPasses + 1 : 1;
    self.lastVisibilityRect = frame;
    // 等待两个稳定布局周期，给取消的拖动或转场留出回调时间。
    if (self.settledVisibilityPasses < 2) {
        return;
    }
    if (DY778PreviewPreviewIsMostlyVisible(self.controller)) {
        [self cancelDisappearance];
        [self scheduleRefresh];
    } else {
        [self deactivate];
    }
}

- (void)beginDisappearance {
    if (!self.active) {
        return;
    }
    if (!self.disappearancePending) {
        self.disappearancePending = YES;
        self.disappearanceGeneration += 1;
        self.settledVisibilityPasses = 0;
        self.lastVisibilityRect = CGRectNull;
    }
    self.disappearingScrollView = DY778PreviewPreviewScrollView(self.controller.viewIfLoaded)
        ?: self.disappearingScrollView;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        return;
    }
    __weak DY778PreviewPreviewState *weakSelf = self;
    if (!self.visibilityTimer) {
        self.visibilityTimer = [NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) {
            DY778PreviewPreviewState *state = weakSelf;
            if (!state) {
                [timer invalidate];
                return;
            }
            [state checkVisibilityAfterTransition];
        }];
        [[NSRunLoop mainRunLoop] addTimer:self.visibilityTimer forMode:NSRunLoopCommonModes];
    }
    id<UIViewControllerTransitionCoordinator> coordinator = self.controller.transitionCoordinator;
    if (coordinator.isAnimated && !self.transitionInProgress) {
        self.transitionInProgress = YES;
        NSUInteger generation = self.disappearanceGeneration;
        BOOL registered = [coordinator animateAlongsideTransition:nil
            completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                DY778PreviewPreviewState *state = weakSelf;
                if (!state.active || state.disappearanceGeneration != generation) return;
                state.transitionInProgress = NO;
                if (context.isCancelled) {
                    [state cancelDisappearance];
                    [state scheduleRefresh];
                } else {
                    [state checkVisibilityAfterTransition];
                }
            }];
        if (!registered) self.transitionInProgress = NO;
    }
}

- (void)deactivate {
    self.active = NO;
    [self cancelDisappearance];
    [self stopTimer];
    [self clearContent];
    [self resetViewerCount];
}

- (void)resetViewerCount {
    [self.requestTimeoutTimer invalidate];
    self.requestTimeoutTimer = nil;
    self.viewerRoomID = nil;
    self.requestRoomID = nil;
    self.lastViewerCount = nil;
    self.requestInFlight = NO;
    self.hasNetworkCount = NO; self.roomStart = 0; self.lastRequestAt = 0;
    self.requestGeneration += 1;
    self.roomAPI = nil;
    self.sampleRequested = YES;
}

- (void)clearContent {
    [self resetViewerCount]; self.stableAt = 0;
    [self removeBadge];
    self.statusLabel = nil;
    self.badgeAnchor = CGRectNull;
    self.badgeAnchorBounds = CGRectZero;
    self.badgeAnchorInsets = UIEdgeInsetsZero;
    self.layoutRetriesRemaining = 15;
    self.sampleRequested = YES;
}

- (void)scheduleRefresh {
    if (!self.active || self.refreshScheduled) {
        return;
    }
    self.refreshScheduled = YES;
    __weak DY778PreviewPreviewState *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        DY778PreviewPreviewState *state = weakSelf;
        state.refreshScheduled = NO;
        if (state.active) {
            [state refresh];
        }
    });
}

- (void)startTimer {
    NSTimeInterval interval = DY778Bool(@"liveInfo.cardDuration") ? 1 : DY778LiveRefreshInterval(DY778Number(@"liveInfo.refresh"));
    if (self.timer.isValid && fabs(self.timer.timeInterval - interval) < 0.01) {
        return;
    }
    [self stopTimer];
    self.sampleRequested = YES;
    __weak DY778PreviewPreviewState *weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
        DY778PreviewPreviewState *state = weakSelf;
        if (!state) {
            [timer invalidate];
            return;
        }
        state.sampleRequested = YES;
        [state scheduleRefresh];
    }];
    self.timer.tolerance = 0.25;
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)pauseForApplicationState {
    [self stopTimer];
    [self.visibilityTimer invalidate];
    self.visibilityTimer = nil;
    self.transitionInProgress = NO;
    self.disappearanceGeneration += 1;
    [self.requestTimeoutTimer invalidate];
    self.requestTimeoutTimer = nil;
    self.requestInFlight = NO;
    self.requestGeneration += 1;
    self.requestRoomID = nil;
    self.roomAPI = nil;
    [self removeBadge];
}

- (void)resumeForApplicationState {
    if (self.active) {
        if (self.disappearancePending) [self beginDisappearance];
        self.sampleRequested = YES;
        [self scheduleRefresh];
    }
}

- (void)requestViewerCountForRoomID:(NSString *)roomID {
    if (!self.active || self.requestInFlight || roomID.length == 0 || CACurrentMediaTime()-self.lastRequestAt < DY778LiveRefreshInterval(DY778Number(@"liveInfo.refresh"))) {
        return;
    }
    NSNumber *roomNumber = DY778PreviewOnlineCount(roomID);
    if (roomNumber.longLongValue <= 0) {
        return;
    }
    Class apiClass = NSClassFromString(@"HTSLiveRoomAPI");
    if (!DY778LiveRoomAPIAvailable(apiClass)) {
        return;
    }
    id<DY778PreviewRoomAPI> api = [(id<DY778PreviewRoomAPI>)[apiClass alloc] initWithRoomID:roomNumber];
    if (!api) {
        return;
    }
    self.roomAPI = api; self.lastRequestAt = CACurrentMediaTime();
    self.requestRoomID = roomID;
    self.requestInFlight = YES;
    self.requestGeneration += 1;
    NSUInteger generation = self.requestGeneration;
    NSTimeInterval timeout = MAX(5.0, DY778LiveRefreshInterval(DY778Number(@"liveInfo.refresh")) * 1.5);
    __weak DY778PreviewPreviewState *timeoutState = self;
    self.requestTimeoutTimer = [NSTimer timerWithTimeInterval:timeout repeats:NO block:^(__unused NSTimer *timer) {
        DY778PreviewPreviewState *state = timeoutState;
        if (!state || !state.requestInFlight || state.requestGeneration != generation ||
            ![state.requestRoomID isEqualToString:roomID]) {
            return;
        }
        state.requestInFlight = NO;
        state.requestRoomID = nil;
        state.roomAPI = nil;
        state.requestGeneration += 1;
        state.sampleRequested = YES;
        [state scheduleRefresh];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.requestTimeoutTimer forMode:NSRunLoopCommonModes];
    __weak DY778PreviewPreviewState *weakSelf = self;
    void (^completion)(id, id) = ^(id first, id second) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778PreviewPreviewState *state = weakSelf;
            if (!state) {
                return;
            }
            BOOL sameRequest = state.requestInFlight && state.requestGeneration == generation &&
                [state.requestRoomID isEqualToString:roomID];
            if (sameRequest) {
                NSNumber *count = DY778PreviewNetworkViewerCount(first, roomID, 0) ?: DY778PreviewNetworkViewerCount(second, roomID, 0);
                [state.requestTimeoutTimer invalidate];
                state.requestTimeoutTimer = nil;
                state.requestInFlight = NO;
                state.requestRoomID = nil;
                state.roomAPI = nil;
                double start = DY778LiveRoomStart(first,roomID,0); if (!start) start = DY778LiveRoomStart(second,roomID,0);
                if (start && state.active && [state.viewerRoomID isEqual:roomID]) { state.roomStart = start; [state scheduleRefresh]; }
                if (count && state.active && [state.viewerRoomID isEqualToString:roomID]) {
                    state.lastViewerCount = count;
                    state.hasNetworkCount = YES;
                    [state scheduleRefresh];
                }
            }
        });
    };
    [api fetchRoomInfoWithRoomID:roomNumber completion:completion];
}

- (void)retryInitialLayout {
    if (self.layoutRetryTimer || self.layoutRetriesRemaining == 0) {
        return;
    }
    __weak DY778PreviewPreviewState *weakSelf = self;
    // 初始位置缺失时短暂重试，后续由正常布局回调更新。
    self.layoutRetryTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer *timer) {
        DY778PreviewPreviewState *state = weakSelf;
        if (!state) {
            [timer invalidate];
            return;
        }
        if (!state.active || !state.controller.viewIfLoaded.window ||
            [UIApplication sharedApplication].applicationState != UIApplicationStateActive ||
            state.layoutRetriesRemaining == 0) {
            [state stopLayoutRetry];
            return;
        }
        state.layoutRetriesRemaining -= 1;
        [state scheduleRefresh];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.layoutRetryTimer forMode:NSRunLoopCommonModes];
}

- (void)layoutBadgeInView:(UIView *)root {
    NSMutableArray<DY778LiveCapsule *> *badges = [NSMutableArray array];
    if (self.badge) [badges addObject:self.badge]; if (self.durationBadge) [badges addObject:self.durationBadge];
    CGRect available = CGRectInset(UIEdgeInsetsInsetRect(root.bounds,root.safeAreaInsets),12,8);
    CGFloat firstHeight=self.badge ? self.badge.intrinsicContentSize.height : 0;
    CGFloat secondHeight=self.durationBadge ? self.durationBadge.intrinsicContentSize.height : 0;
    CGFloat total=firstHeight+secondHeight+(firstHeight>0 && secondHeight>0 ? 6 : 0);
    if (!DY778PreviewUsableRect(available) || available.size.width < 60 || available.size.height < total) {
        for (UIView *badge in badges) badge.hidden = YES; [self retryInitialLayout]; return;
    }
    if (!CGRectEqualToRect(root.bounds,self.badgeAnchorBounds) || !UIEdgeInsetsEqualToEdgeInsets(root.safeAreaInsets,self.badgeAnchorInsets)) {
        self.badgeAnchor = CGRectNull; self.badgeAnchorBounds = root.bounds; self.badgeAnchorInsets = root.safeAreaInsets; self.layoutRetriesRemaining = 15;
    }
    CGRect anchor = CGRectNull; UIView *label = self.statusLabel;
    if (label && [label isDescendantOfView:root]) {
        UIView *container = label.superview.superview;
        if (container && container != root && [container isDescendantOfView:root]) {
            CGRect rect = [container convertRect:container.bounds toView:root];
            if (DY778PreviewUsableRect(rect) && rect.size.height <= 100 && CGRectIntersectsRect(rect,available)) anchor = rect;
        }
    }
    if (DY778PreviewUsableRect(anchor)) self.badgeAnchor = anchor; else anchor = self.badgeAnchor;
    if (!DY778PreviewUsableRect(anchor) || !CGRectIntersectsRect(anchor,available)) {
        for (UIView *badge in badges) badge.hidden = YES; [self retryInitialLayout]; return;
    }
    double top=0, secondTop=0;
    if (!DY778LiveCapsuleStack(CGRectGetMinY(available),CGRectGetMaxY(available),CGRectGetMinY(anchor),CGRectGetMaxY(anchor),firstHeight,secondHeight,&top,&secondTop)) {
        for (UIView *badge in badges) badge.hidden=YES; return;
    }
    [self stopLayoutRetry];
    for (DY778LiveCapsule *badge in badges) {
        CGSize size = badge.intrinsicContentSize; size.width = MIN(size.width,available.size.width);
        CGFloat x = MAX(CGRectGetMinX(available),MIN(CGRectGetMidX(anchor)-size.width/2,CGRectGetMaxX(available)-size.width));
        CGFloat y=badge==self.durationBadge ? secondTop : top;
        badge.frame = CGRectMake(round(x),round(y),ceil(size.width),size.height); badge.hidden = NO;
        [root bringSubviewToFront:badge];
    }
}

- (void)refresh {
    UIViewController *controller = self.controller;
    UIView *root = controller.viewIfLoaded;
    if (!self.active || !root.window || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        [self stopTimer];
        [self removeBadge];
        return;
    }
    DY778PreviewDisplayMode mode = DY778PreviewCurrentDisplayMode();
    if (mode == DY778PreviewDisplayModeDisabled && !DY778Bool(@"liveInfo.cardDuration")) {
        [self stopTimer];
        [self removeBadge];
        [self resetViewerCount];
        return;
    }
    if ([DY778PreviewValueForKey(controller, @"roomEntered") boolValue] ||
        [DY778PreviewValueForKey(controller, @"willEnterLiveRoom") boolValue]) {
        [self stopTimer];
        [self removeBadge];
        return;
    }

    [self startTimer];
    id viewModel = DY778PreviewValueForKey(controller, @"viewModel");
    if (!DY778PreviewIsRecommendationPreview(controller) ||
        [DY778PreviewValueForKey(viewModel, @"didEndedLive") boolValue]) {
        [self removeBadge];
        [self resetViewerCount];
        return;
    }
    for (UIView *view = root; view; view = view.superview) {
        if (view.hidden || view.alpha <= 0.01) {
            [self removeBadge];
            return;
        }
    }
    CGRect windowRect = [root convertRect:root.bounds toView:root.window];
    if (!DY778PreviewUsableRect(windowRect) || !CGRectIntersectsRect(windowRect, root.window.bounds)) {
        [self removeBadge];
        return;
    }

    BOOL moving = DY778PreviewScrollIsMoving(DY778PreviewPreviewScrollView(root));
    double now = CACurrentMediaTime();
    if (moving || !DY778PreviewPreviewIsMostlyVisible(controller) || !CGRectEqualToRect(self.stableRect,windowRect)) {
        self.stableRect = windowRect; self.stableAt = now; self.layoutRetriesRemaining = 15;
        self.badge.hidden = YES; self.durationBadge.hidden = YES;
        [self retryInitialLayout]; return;
    }
    if (now-self.stableAt < .20) { self.badge.hidden = YES; self.durationBadge.hidden = YES; [self retryInitialLayout]; return; }
    // 先完成宿主的待处理约束，再读取入口容器坐标。
    [root layoutIfNeeded];
    if (!self.statusLabel || ![self.statusLabel isDescendantOfView:root]) {
        id tipView = DY778PreviewValueForKey(controller, @"getLiveStatusTipView");
        UIView *label = [tipView isKindOfClass:[UIView class]] ? DY778PreviewFindStatusLabel(tipView, 0) : nil;
        self.statusLabel = label && [label isDescendantOfView:root] ? label : DY778PreviewFindStatusLabel(root, 0);
    }
    NSString *roomID = nil;
    NSArray *rooms = DY778PreviewPreviewRooms(controller, self.statusLabel, &roomID);
    if (!roomID || ![self.viewerRoomID isEqualToString:roomID]) {
        [self resetViewerCount];
        self.viewerRoomID = roomID;
    }
    if (DY778Bool(@"liveInfo.cardDuration")) for (id room in rooms) { double start = DY778LiveRoomStart(room,roomID,0); if (start) { self.roomStart = start; break; } }
    if ((mode != DY778PreviewDisplayModeDisabled && (self.sampleRequested || !self.lastViewerCount)) || (DY778Bool(@"liveInfo.cardDuration") && !self.roomStart)) {
        NSNumber *sample = self.hasNetworkCount ? nil : DY778PreviewViewerCount(rooms);
        if (sample) {
            self.lastViewerCount = sample;
        }
        self.sampleRequested = NO;
        [self requestViewerCountForRoomID:roomID];
    }
    NSNumber *count = self.lastViewerCount;
    if (mode != DY778PreviewDisplayModeDisabled && count) {
        if (!self.badge) self.badge = [[DY778LiveCapsule alloc] initWithFrame:CGRectZero];
        if (self.badge.superview != root) [root addSubview:self.badge];
        NSString *text = mode == DY778PreviewDisplayModePrecise ? [DY778PreviewFormatter preciseViewerCount:count.longLongValue] : [DY778PreviewFormatter formatViewerCount:count.longLongValue];
        [self.badge setViewerCountString:text];
    } else { [self.badge removeFromSuperview]; self.badge = nil; }
    NSString *elapsed = DY778Bool(@"liveInfo.cardDuration") ? DY778LiveElapsedDigits(self.roomStart) : nil;
    if (elapsed.length) {
        if (!self.durationBadge) self.durationBadge = [[DY778LiveCapsule alloc] initWithFrame:CGRectZero];
        if (self.durationBadge.superview != root) [root addSubview:self.durationBadge];
        [self.durationBadge setElapsedString:elapsed];
    } else { [self.durationBadge removeFromSuperview]; self.durationBadge = nil; }
    if (self.badge || self.durationBadge) [self layoutBadgeInView:root];

}

@end

static DY778PreviewPreviewState *DY778PreviewStateForController(UIViewController *controller, BOOL create) {
    if (!controller) {
        return nil;
    }
    DY778PreviewPreviewState *state = objc_getAssociatedObject(controller, &DY778PreviewStateKey);
    if (!state && create) {
        state = [[DY778PreviewPreviewState alloc] initWithController:controller];
        objc_setAssociatedObject(controller, &DY778PreviewStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void DY778PreviewStatusLabelDidChange(UIView *label) {
    UIViewController *controller = DY778PreviewPreviewControllerForView(label);
    DY778PreviewPreviewState *state = DY778PreviewStateForController(controller, YES);
    state.statusLabel = label;
    [state scheduleRefresh];
}

static void DY778PreviewActivatePreview(UIViewController *controller) {
    DY778PreviewPreviewState *state = DY778PreviewStateForController(controller, YES);
    [state activate];
}


static NSMutableSet *DY778PreviewInstalled;
static void DY778PreviewHook(NSString *className, NSString *method, char argument, NSInteger mode) {
    Class cls = NSClassFromString(className); SEL selector = NSSelectorFromString(method);
    NSString *key = [className stringByAppendingFormat:@".%@",method]; Method m = class_getInstanceMethod(cls,selector);
    if (!m || [DY778PreviewInstalled containsObject:key]) return;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
    if (sig.methodReturnType[0] != 'v' || sig.numberOfArguments != (argument ? 3u : 2u)) return;
    if (argument && [sig getArgumentTypeAtIndex:2][0] != argument) return;
    __block IMP original = NULL;
    void (^perform)(id,id,BOOL) = ^(id owner,id object,BOOL flag) {
        BOOL label = [className isEqual:@"AWELiveFeedStatusLabel"];
        if (!label && mode == 3) [DY778PreviewStateForController(owner,NO) clearContent];
        if (!label && mode == 4) [DY778PreviewStateForController(owner,NO) deactivate];
        if (argument == '@') ((void (*)(id,SEL,id))original)(owner,selector,object);
        else if (argument == 'B') ((void (*)(id,SEL,BOOL))original)(owner,selector,flag);
        else ((void (*)(id,SEL))original)(owner,selector);
        if (!NSThread.isMainThread) return;
        if (label) DY778PreviewStatusLabelDidChange(owner);
        else if (mode == 1) DY778PreviewActivatePreview(owner);
        else if (mode == 2) [DY778PreviewStateForController(owner,NO) beginDisappearance];
        else if (mode != 4) [DY778PreviewStateForController(owner,NO) scheduleRefresh];
    };
    IMP replacement;
    if (argument == '@') replacement = imp_implementationWithBlock(^(id owner,id object) { perform(owner,object,NO); });
    else if (argument == 'B') replacement = imp_implementationWithBlock(^(id owner,BOOL flag) { perform(owner,nil,flag); });
    else replacement = imp_implementationWithBlock(^(id owner) { perform(owner,nil,NO); });
    if (DY778Hook(cls,selector,replacement,&original)) [DY778PreviewInstalled addObject:key]; else imp_removeBlock(replacement);
}
void DY778InstallPreviewHooks(void) {
    if (!DY778PreviewInstalled) DY778PreviewInstalled = [NSMutableSet set];
    NSString *name = @"AWELiveNewPreStreamViewController";
    for (NSString *method in @[@"configureWithModel:",@"setModel:",@"setViewModel:"]) DY778PreviewHook(name,method,'@',3);
    for (NSString *method in @[@"setRoomEntered:",@"setWillEnterLiveRoom:"]) DY778PreviewHook(name,method,'B',0);
    for (NSString *method in @[@"prepareForDisplay"]) DY778PreviewHook(name,method,0,1);
    for (NSString *method in @[@"pageWillAppear:",@"pageDidAppear:",@"viewWillAppear:",@"viewDidAppear:"]) DY778PreviewHook(name,method,'B',1);
    for (NSString *method in @[@"pageWillDisappear:",@"pageDidDisappear:",@"viewWillDisappear:",@"viewDidDisappear:"]) DY778PreviewHook(name,method,'B',2);
    DY778PreviewHook(name,@"didEndDisplaying",0,2); DY778PreviewHook(name,@"viewDidLayoutSubviews",0,0);
    for (NSString *method in @[@"prepareForReuse",@"reset"]) DY778PreviewHook(name,method,0,4);
    DY778PreviewHook(@"AWELiveFeedStatusLabel",@"setViewModel:",'@',0);
    for (NSString *method in @[@"layoutSubviews",@"didMoveToWindow",@"didMoveToSuperview"]) DY778PreviewHook(@"AWELiveFeedStatusLabel",method,0,0);
}
