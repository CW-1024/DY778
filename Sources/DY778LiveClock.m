#import "DY778LiveInfo.h"
#import <QuartzCore/QuartzCore.h>

static char DY778LiveClockStateKey;
static NSHashTable *DY778LiveClockOwners;
static NSMutableSet *DY778LiveClockHooks;
@protocol DY778LiveClockAPI <NSObject>
- (instancetype)initWithRoomID:(id)room;
- (void)fetchRoomInfoWithRoomID:(id)room completion:(id)completion;
@end
static id DY778ClockRoom(id owner, NSUInteger depth) {
    if (!owner || depth > 4) return nil;
    for (NSString *key in @[@"roomModel",@"room",@"currentRoom",@"rawRoom",@"rawHTSLiveRoomModel"]) {
        id child=DY778Read(owner,key); if (child && child != owner) { id room=DY778ClockRoom(child,depth+1); if (room) return room; }
    }
    return DY778LiveRoomIdentifier(owner).length ? owner : nil;
}
@interface DY778LiveClockState : NSObject
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic, strong) DY778LiveCapsule *capsule;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) id request;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic) double start, lastRequest;
@property(nonatomic) NSUInteger generation, attempts;
@property(nonatomic) BOOL active, dragging;
@property(nonatomic) CGPoint dragOrigin;
@property(nonatomic) CGSize dragBounds;
- (void)refresh;
- (void)stop;
@end
@implementation DY778LiveClockState
- (void)dealloc { [_timer invalidate]; [_capsule removeFromSuperview]; }
- (void)stop { self.generation++; [self.timer invalidate]; self.timer=nil; self.request=nil; self.dragging=NO; [self.capsule removeFromSuperview]; self.capsule=nil; }
- (NSString *)positionPrefix { return CGRectGetWidth(self.owner.view.bounds)>CGRectGetHeight(self.owner.view.bounds) ? @"liveInfo.landscape" : @"liveInfo.portrait"; }
- (CGRect)available {
    UIView *root=self.owner.viewIfLoaded; CGRect bounds=UIEdgeInsetsInsetRect(root.bounds,root.safeAreaInsets);
    return CGRectInset(bounds,12,12);
}
- (void)place {
    UIView *root=self.owner.viewIfLoaded; if (!root || !self.capsule || self.dragging) return;
    CGRect available=self.available; CGSize size=self.capsule.intrinsicContentSize;
    size.width=MIN(size.width,available.size.width); if (size.width<60 || available.size.height<size.height) { self.capsule.hidden=YES; return; }
    self.capsule.hidden=NO;
    NSString *prefix=self.positionPrefix;
    NSNumber *x=[DY778Preferences() objectForKey:[prefix stringByAppendingString:@".x"]], *y=[DY778Preferences() objectForKey:[prefix stringByAppendingString:@".y"]];
    CGFloat px=CGRectGetMidX(available)-size.width/2, py=CGRectGetMinY(available)+([prefix hasSuffix:@"portrait"] ? 64 : 12);
    if ([x isKindOfClass:NSNumber.class] && [y isKindOfClass:NSNumber.class]) {
        px=available.origin.x+DY778LivePosition(x.doubleValue)*MAX(0,available.size.width-size.width);
        py=available.origin.y+DY778LivePosition(y.doubleValue)*MAX(0,available.size.height-size.height);
    } else if ([prefix hasSuffix:@"portrait"]) {
        UIView *player=DY778Read(self.owner,@"playerView") ?: DY778Read(self.owner,@"livePlayerView");
        if ([player isKindOfClass:UIView.class] && [player isDescendantOfView:root]) {
            CGRect video=[player convertRect:player.bounds toView:root];
            if (CGRectGetMinY(video)>CGRectGetMinY(available)+80) py=CGRectGetMinY(video)-size.height-8;
        }
    }
    py=MAX(CGRectGetMinY(available),MIN(py,CGRectGetMaxY(available)-size.height));
    self.capsule.frame=CGRectMake(round(px),round(py),ceil(size.width),ceil(size.height)); [root bringSubviewToFront:self.capsule];
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    UIView *root=self.owner.viewIfLoaded; CGRect available=self.available;
    if (pan.state==UIGestureRecognizerStateBegan) { self.dragging=YES; self.dragOrigin=self.capsule.frame.origin; self.dragBounds=root.bounds.size; }
    if (!CGSizeEqualToSize(self.dragBounds,root.bounds.size)) { self.dragging=NO; [self place]; return; }
    CGPoint translation=[pan translationInView:root]; CGSize size=self.capsule.bounds.size;
    self.capsule.frame=CGRectMake(MAX(available.origin.x,MIN(self.dragOrigin.x+translation.x,CGRectGetMaxX(available)-size.width)),MAX(available.origin.y,MIN(self.dragOrigin.y+translation.y,CGRectGetMaxY(available)-size.height)),size.width,size.height);
    if (pan.state==UIGestureRecognizerStateEnded) {
        NSString *prefix=self.positionPrefix;
        [DY778Preferences() setDouble:DY778LivePosition((self.capsule.frame.origin.x-available.origin.x)/MAX(1,available.size.width-size.width)) forKey:[prefix stringByAppendingString:@".x"]];
        [DY778Preferences() setDouble:DY778LivePosition((self.capsule.frame.origin.y-available.origin.y)/MAX(1,available.size.height-size.height)) forKey:[prefix stringByAppendingString:@".y"]];
        self.dragging=NO; [self place];
    } else if (pan.state==UIGestureRecognizerStateCancelled || pan.state==UIGestureRecognizerStateFailed) { self.dragging=NO; [self place]; }
}
- (void)fetchStart {
    if (self.request || self.attempts>=3 || !self.roomID.length || (self.lastRequest>0 && CACurrentMediaTime()-self.lastRequest<10)) return;
    Class cls=NSClassFromString(@"HTSLiveRoomAPI");
    if (!DY778LiveRoomAPIAvailable(cls)) return;
    NSNumber *room=@(self.roomID.longLongValue); if (room.longLongValue<=0) return;
    id<DY778LiveClockAPI> api=[(id<DY778LiveClockAPI>)[cls alloc] initWithRoomID:room]; if (!api) return;
    self.request=api; self.attempts++; self.lastRequest=CACurrentMediaTime();
    NSUInteger generation=self.generation; NSString *identifier=self.roomID; __weak typeof(self) weakSelf=self; __weak id weakAPI=api;
    [api fetchRoomInfoWithRoomID:room completion:^(id first,id second) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778LiveClockState *self=weakSelf;
            if (!self || !weakAPI || self.request!=weakAPI || self.generation!=generation || ![self.roomID isEqual:identifier] ||
                ![DY778LiveRoomIdentifier(DY778ClockRoom(self.owner,0)) isEqual:identifier] || !self.active) return;
            self.request=nil; double start=DY778LiveRoomStart(first,identifier,0); if (!start) start=DY778LiveRoomStart(second,identifier,0);
            if (start) self.start=start; [self refresh];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
        DY778LiveClockState *self=weakSelf; if (self.generation==generation && weakAPI && self.request==weakAPI) { self.request=nil; [self refresh]; }
    });
}
- (void)refresh {
    UIView *root=self.owner.viewIfLoaded;
    BOOL visible=root.window && !root.hidden && root.alpha>.01;
    if (visible) {
        CGRect frame=[root convertRect:root.bounds toView:root.window]; CGRect intersection=CGRectIntersection(frame,root.window.bounds);
        visible=!CGRectIsNull(intersection) && intersection.size.width*intersection.size.height >= frame.size.width*frame.size.height*.6;
        for (UIView *parent=root.superview; visible && parent; parent=parent.superview) visible=!parent.hidden && parent.alpha>.01;
    }
    if (!self.active || !DY778Bool(@"liveInfo.duration") || !visible || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) { [self stop]; return; }
    id room=DY778ClockRoom(self.owner,0); NSString *identifier=DY778LiveRoomIdentifier(room);
    if (![identifier isEqual:self.roomID]) { [self stop]; self.roomID=identifier; self.start=0; self.attempts=0; self.lastRequest=0; }
    if (!identifier.length) return;
    double start=DY778LiveRoomStart(room,identifier,0); if (start) self.start=start;
    NSString *text=DY778LiveElapsedText(self.start);
    if (!self.timer && (text.length || self.attempts<3 || self.request)) {
        __weak typeof(self) weakSelf=self;
        self.timer=[NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { if (weakSelf) [weakSelf refresh]; else [timer invalidate]; }]; self.timer.tolerance=.1;
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
    if (!text.length) {
        self.capsule.hidden=YES; [self fetchStart];
        if (self.attempts>=3 && !self.request) { [self.timer invalidate]; self.timer=nil; }
        return;
    }
    if (!self.capsule) {
        self.capsule=[[DY778LiveCapsule alloc] initWithFrame:CGRectZero]; self.capsule.userInteractionEnabled=YES;
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]; pan.maximumNumberOfTouches=1; [self.capsule addGestureRecognizer:pan]; [root addSubview:self.capsule];
        self.capsule.accessibilityHint=@"可拖动调整位置";
    }
    self.capsule.label.font=[UIFont monospacedDigitSystemFontOfSize:MAX(11,MIN(19,DY778Number(@"liveInfo.fontSize"))) weight:UIFontWeightMedium];
    self.capsule.label.textColor=DY778ColorFromHex(DY778String(@"liveInfo.textColor"),UIColor.whiteColor);
    self.capsule.symbol.tintColor=self.capsule.label.textColor;
    self.capsule.backgroundColor=[DY778ColorFromHex(DY778String(@"liveInfo.backgroundColor"),UIColor.blackColor) colorWithAlphaComponent:MAX(.15,MIN(1,DY778Number(@"liveInfo.opacity")))];
    [self.capsule setElapsedString:text]; [self place];
}
@end
static DY778LiveClockState *DY778ClockState(UIViewController *owner, BOOL create) {
    DY778LiveClockState *state=objc_getAssociatedObject(owner,&DY778LiveClockStateKey);
    if (!state && create) { state=[DY778LiveClockState new]; state.owner=owner; objc_setAssociatedObject(owner,&DY778LiveClockStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [DY778LiveClockOwners addObject:owner]; }
    return state;
}
static void DY778ClockHook(NSString *method, const char *arguments, NSInteger transition) {
    Class cls=NSClassFromString(@"IESLiveAudienceViewController"); SEL selector=NSSelectorFromString(method); Method m=class_getInstanceMethod(cls,selector);
    if (!m || [DY778LiveClockHooks containsObject:method]) return;
    NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
    if (sig.methodReturnType[0]!='v' || sig.numberOfArguments!=strlen(arguments)+2) return;
    for (NSUInteger i=0;arguments[i];i++) if ([sig getArgumentTypeAtIndex:i+2][0]!=arguments[i]) return;
    __block IMP original=NULL;
    void (^perform)(UIViewController *,id,BOOL,unsigned long long)=^(UIViewController *owner,id object,BOOL flag,unsigned long long type) {
        DY778LiveClockState *state=DY778ClockState(owner,transition>0);
        if (transition<0) { state.active=NO; [state stop]; }
        if (!strcmp(arguments,"B")) ((void (*)(id,SEL,BOOL))original)(owner,selector,flag);
        else if (!strcmp(arguments,"@Q")) ((void (*)(id,SEL,id,unsigned long long))original)(owner,selector,object,type);
        else if (!strcmp(arguments,"@")) ((void (*)(id,SEL,id))original)(owner,selector,object);
        else ((void (*)(id,SEL))original)(owner,selector);
        if (transition>=0 && NSThread.isMainThread) { if (transition>0) state.active=YES; [state refresh]; }
    };
    IMP replacement;
    if (!strcmp(arguments,"B")) replacement=imp_implementationWithBlock(^(UIViewController *owner,BOOL flag){perform(owner,nil,flag,0);});
    else if (!strcmp(arguments,"@Q")) replacement=imp_implementationWithBlock(^(UIViewController *owner,id object,unsigned long long type){perform(owner,object,NO,type);});
    else if (!strcmp(arguments,"@")) replacement=imp_implementationWithBlock(^(UIViewController *owner,id object){perform(owner,object,NO,0);});
    else replacement=imp_implementationWithBlock(^(UIViewController *owner){perform(owner,nil,NO,0);});
    if (DY778Hook(cls,selector,replacement,&original)) [DY778LiveClockHooks addObject:method]; else imp_removeBlock(replacement);
}
void DY778ResetLiveClockPosition(void) {
    for (NSString *orientation in @[@"portrait",@"landscape"]) for (NSString *axis in @[@"x",@"y"]) [DY778Preferences() removeObjectForKey:[NSString stringWithFormat:@"liveInfo.%@.%@",orientation,axis]];
    for (id owner in DY778LiveClockOwners.allObjects) [DY778ClockState(owner,NO) refresh];
}
void DY778InstallLiveInfoHooks(void) {
    DY778InstallPreviewHooks();
    static dispatch_once_t once; dispatch_once(&once,^{
        DY778LiveClockOwners=[NSHashTable weakObjectsHashTable]; DY778LiveClockHooks=[NSMutableSet set];
        for (NSString *name in @[DY778PreferencesChangedNotification,UIApplicationDidBecomeActiveNotification,UIApplicationWillResignActiveNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                for (id owner in DY778LiveClockOwners.allObjects) { DY778LiveClockState *state=DY778ClockState(owner,NO); if ([note.name isEqual:UIApplicationWillResignActiveNotification]) [state stop]; else [state refresh]; }
            }];
    });
    DY778ClockHook(@"viewDidAppear:","B",1); DY778ClockHook(@"viewDidLayoutSubviews","",0);
    DY778ClockHook(@"roomDidBecomeActive:","@",1); DY778ClockHook(@"roomWillEnterForeground:","@",1);
    DY778ClockHook(@"roomDidEnterBackground:","@",-1);
    DY778ClockHook(@"didEnterRoom:","@",1); DY778ClockHook(@"viewWillDisappear:","B",-1);
    DY778ClockHook(@"roomWillResignActive:","@",-1); DY778ClockHook(@"onStartLeaveRoomAnimation","",-1); DY778ClockHook(@"didCloseRoom:closeType:","@Q",-1);
}
