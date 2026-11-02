#import "DY778FeedFilter.h"
#import "DY778Core.h"
#import "DY778FeedFilterPolicy.h"
#import "DY778PlaybackPolicy.h"

static BOOL DY778FeedEnabled;
static NSMutableSet *DY778FeedHooks;
static NSMutableOrderedSet *DY778FeedSeen;
static NSHashTable *DY778FeedOwners;
static NSHashTable *DY778FeedAdTags;
static NSTimeInterval DY778FeedLastSkip;
static unsigned DY778FeedRecentSkips;
static char DY778FeedStateKey;
static _Thread_local DY778PlaybackFrame *DY778FeedStack;

@interface DY778FeedFilterState : NSObject
@property(nonatomic) NSUInteger generation;
@end
@implementation DY778FeedFilterState @end

static NSString *DY778FeedText(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static BOOL DY778FeedBool(id object, NSString *key) {
    id value = DY778Read(object,key);
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}
static BOOL DY778FeedPositive(id object, NSString *key) {
    id value = DY778Read(object,key);
    return [value respondsToSelector:@selector(longLongValue)] && [value longLongValue] > 0;
}
static BOOL DY778FeedSignature(Class cls, SEL selector, const char *arguments) {
    Method method = class_getInstanceMethod(cls,selector);
    if (!method || method_getNumberOfArguments(method) != strlen(arguments)+2) return NO;
    char type[64]; method_getReturnType(method,type,sizeof(type)); if (type[0] != 'v') return NO;
    for (unsigned i=0; arguments[i]; i++) {
        method_getArgumentType(method,i+2,type,sizeof(type));
        if (arguments[i]=='B' ? (type[0]!='B' && type[0]!='c') : type[0]!=arguments[i]) return NO;
    }
    return YES;
}
static BOOL DY778FeedSameModel(id left, id right) {
    if (!left || !right) return NO;
    if (left == right) return YES;
    NSString *identifier = DY778FeedText(DY778Read(left,@"itemID"));
    return identifier.length && [identifier isEqual:DY778FeedText(DY778Read(right,@"itemID"))];
}
static BOOL DY778FeedViewVisible(UIView *view, UIView *root) {
    if (![view isKindOfClass:UIView.class] || !view.window || view.window != root.window || ![view isDescendantOfView:root]) return NO;
    CGRect visible = CGRectIntersection([view convertRect:view.bounds toView:view.window],view.window.bounds);
    visible = CGRectIntersection(visible,[root convertRect:root.bounds toView:view.window]);
    if (CGRectIsEmpty(visible) || CGRectIsNull(visible)) return NO;
    CGFloat opacity = 1;
    for (UIView *parent=view; parent; parent=parent.superview) {
        opacity *= parent.alpha;
        if (parent.hidden || opacity < 0.02) return NO;
        if (parent.clipsToBounds) visible = CGRectIntersection(visible,[parent convertRect:parent.bounds toView:view.window]);
        if (CGRectIsEmpty(visible) || CGRectIsNull(visible)) return NO;
    }
    return YES;
}
static BOOL DY778FeedVisibleAdTag(UIViewController *controller, id model) {
    for (id component in DY778FeedAdTags.allObjects) {
        if (!DY778FeedSameModel(DY778Read(component,@"model"),model)) continue;
        UIImageView *image = DY778Read(component,@"adTagImageView");
        if ([image isKindOfClass:UIImageView.class] && image.image && DY778FeedViewVisible(image,controller.view)) return YES;
    }
    Class tagClass = NSClassFromString(@"AWEAdTagView");
    if (!tagClass) return NO;
    NSMutableArray<UIView *> *pending = [NSMutableArray array];
    UIView *cell = DY778Read(controller,@"currentCell");
    if ([cell isKindOfClass:UITableViewCell.class] && DY778FeedViewVisible(cell,controller.view)) [pending addObject:cell];
    UIViewController *interaction = DY778Read(controller,@"currentInteractionController");
    if ([interaction isKindOfClass:UIViewController.class] && interaction.isViewLoaded &&
        DY778FeedSameModel(DY778Read(interaction,@"model"),model) && DY778FeedViewVisible(interaction.view,controller.view) &&
        (!pending.count || ![interaction.view isDescendantOfView:cell])) [pending addObject:interaction.view];
    for (unsigned scanned=0; pending.count && scanned<256; scanned++) {
        UIView *view = pending.lastObject; [pending removeLastObject];
        if (view.hidden || view.alpha < 0.02) continue;
        if ([view isKindOfClass:tagClass] && [view isKindOfClass:UILabel.class] && DY778FeedViewVisible(view,controller.view)) {
            NSString *label = ((UILabel *)view).text ?: ((UILabel *)view).attributedText.string;
            if (label.length && label.length <= 16 && ([label containsString:@"广告"] || [label containsString:@"推广"] || [label containsString:@"赞助"])) return YES;
        }
        for (UIView *child in view.subviews) { if (pending.count >= 256) break; [pending addObject:child]; }
    }
    return NO;
}
static BOOL DY778FeedCommerceAnchor(id anchor) {
    return DY778FeedBool(anchor,@"isCommerceIntention") || DY778FeedBool(anchor,@"isAdLifePromote");
}
static NSString *DY778FeedDescription(id model) {
    NSString *text = DY778FeedText(DY778Read(model,@"descriptionString"));
    if (!text.length) text = DY778FeedText(DY778Read(model,@"optimizeTitleDescriptionString"));
    if (text.length > 4096) return @"";
    text = [text stringByFoldingWithOptions:NSWidthInsensitiveSearch locale:nil];
    return [[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
}
static int DY778FeedReason(UIViewController *controller, id model) {
    Class cls = NSClassFromString(@"AWEAwemeModel");
    if (!cls || ![model isKindOfClass:cls] || DY778Read(model,@"liveStreamURL")) return DY778FeedKeep;
    id author = DY778Read(model,@"author"); NSString *userID = DY778FeedText(DY778Read(author,@"userID"));
    BOOL protectedPost = DY778FeedPositive(author,@"followStatus") || DY778FeedPositive(author,@"cacheFollowStatus") ||
        DY778FeedBool(model,@"userDigged") || DY778FeedPositive(model,@"collectStatus") ||
        (userID.length && [userID isEqual:DY778CurrentAccountID()]);
    if (protectedPost) return DY778FeedKeep;
    BOOL official = NO;
    for (NSString *key in @[@"isAds",@"checkIsAd",@"isHardAdModel",@"isHardAd",@"isDouPlusSoftAdVideo",@"isDouPlusGD",@"isDouPlusVideoConcernHardAd"])
        if (DY778FeedBool(model,key)) { official = YES; break; }
    id ad = DY778Read(model,@"adInfo");
    official = official || DY778FeedBool(DY778Read(model,@"originAdInfo"),@"showAdLabel") ||
        (DY778FeedPositive(ad,@"adID") && DY778FeedPositive(ad,@"creativeID")) || DY778FeedVisibleAdTag(controller,model);
    if (official) return DY778FeedOfficialAd;
    if (!userID.length) return DY778FeedKeep;
    BOOL commerce = DY778FeedBool(model,@"hasGoodsStrictly") || DY778FeedPositive(model,@"starAtlasOrderID") ||
        DY778FeedBool(model,@"isStarAtlasVideo") || DY778FeedCommerceAnchor(DY778Read(model,@"anchorInfo"));
    id anchors = DY778Read(DY778Read(model,@"anchorList"),@"anchorsInfo");
    if (!commerce && [anchors isKindOfClass:NSArray.class]) {
        for (NSUInteger i=0; i<MIN((NSUInteger)32,[anchors count]); i++) if (DY778FeedCommerceAnchor(anchors[i])) { commerce = YES; break; }
    }
    return DY778FeedPromotionReason(DY778FeedDescription(model).UTF8String,NO,commerce,protectedPost);
}
static BOOL DY778FeedContext(UIViewController *controller) {
    if (!controller.isViewLoaded || !controller.view.window || controller.isBeingDismissed ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    if (!DY778FeedBool(controller,@"currentVCIsActive")) return NO;
    id interaction = DY778Read(controller,@"currentInteractionController");
    if (DY778FeedBool(interaction,@"isInteracting") || DY778FeedBool(interaction,@"isCommerceInteracting") ||
        DY778FeedBool(interaction,@"isLongPressPanelShowing") || DY778FeedBool(DY778Read(controller,@"currentVideoController"),@"isPausedByUserClick")) return NO;
    for (UIViewController *parent=controller; parent; parent=parent.parentViewController) if (parent.presentedViewController) return NO;
    for (NSString *key in @[@"isCommentPanelShowing",@"isLikeUserPanelShowing",@"isRelatedVideoPanelShowing",@"isVideoRelatedPanelShowing",@"isAITextPanelShowing"])
        if (DY778FeedBool(controller,key)) return NO;
    return YES;
}
static void DY778FeedCheckLater(UIViewController *owner, DY778FeedFilterState *state, NSUInteger generation,
                               id model, NSString *account, NSString *identifier, unsigned attempt) {
    static const unsigned delays[] = {300,500,700};
    if (attempt >= sizeof(delays)/sizeof(*delays)) return;
    __weak UIViewController *weakOwner = owner;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,delays[attempt]*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        UIViewController *controller = weakOwner;
        if (!DY778FeedEnabled || !controller || state.generation != generation ||
            ![account isEqual:(DY778CurrentAccountID() ?: @"")] || DY778Read(controller,@"currentAweme") != model) return;
        NSString *scene = DY778FeedText(DY778Read(controller,@"currentReferString"));
        if (!scene.length) scene = DY778FeedText(DY778Read(controller,@"referString"));
        UIScrollView *scroll = DY778Read(controller,@"tableView");
        BOOL interacting = ![scroll isKindOfClass:UIScrollView.class] || scroll.dragging || scroll.decelerating || scroll.tracking || DY778FeedBool(controller,@"isDragging");
        id indexValue = DY778Read(controller,@"currentIndex"), countValue = DY778Read(controller,@"dataSourceCount");
        BOOL hasNext = [indexValue isKindOfClass:NSNumber.class] && [countValue isKindOfClass:NSNumber.class] &&
            [indexValue longLongValue] >= 0 && [indexValue longLongValue] < [countValue longLongValue]-1;
        NSString *key = [NSString stringWithFormat:@"%@/%@",account,identifier];
        NSTimeInterval now = CACurrentMediaTime();
        if (now-DY778FeedLastSkip > 12) DY778FeedRecentSkips = 0;
        if (!DY778FeedCanSkip(DY778FeedEnabled,[scene isEqual:@"homepage_hot"],DY778FeedContext(controller),interacting,hasNext,[DY778FeedSeen containsObject:key],DY778FeedRecentSkips)) return;
        int reason = DY778FeedReason(controller,model);
        if (!reason) { DY778FeedCheckLater(controller,state,generation,model,account,identifier,attempt+1); return; }
        SEL next = NSSelectorFromString(@"scrollToNextVideo");
        if (!DY778FeedSignature(controller.class,next,"")) return;
        [DY778FeedSeen addObject:key]; if (DY778FeedSeen.count > 512) [DY778FeedSeen removeObjectAtIndex:0];
        DY778FeedRecentSkips++; DY778FeedLastSkip = now;
        @try { ((void (*)(id,SEL))objc_msgSend)(controller,next); } @catch (__unused NSException *exception) { return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            UIViewController *current = weakOwner;
            if (!DY778FeedEnabled || !current || ![account isEqual:(DY778CurrentAccountID() ?: @"")] || !DY778FeedContext(current)) return;
            NSString *currentID = DY778FeedText(DY778Read(DY778Read(current,@"currentAweme"),@"itemID"));
            if (currentID.length && ![currentID isEqual:identifier]) DY778ShowToast(@"feed-filter",reason == DY778FeedOfficialAd ? @"已跳过广告 · 下滑可返回" : @"已跳过疑似推广 · 下滑可返回",NO,YES);
        });
    });
}
static void DY778FeedSchedule(id owner) {
    if (!NSThread.isMainThread || ![owner isKindOfClass:UIViewController.class]) return;
    [DY778FeedOwners addObject:owner];
    DY778FeedFilterState *state = objc_getAssociatedObject(owner,&DY778FeedStateKey);
    if (!state) { state = [DY778FeedFilterState new]; objc_setAssociatedObject(owner,&DY778FeedStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NSUInteger generation = ++state.generation;
    if (!DY778FeedEnabled) return;
    id model = DY778Read(owner,@"currentAweme"); NSString *identifier = DY778FeedText(DY778Read(model,@"itemID"));
    if (identifier.length) DY778FeedCheckLater(owner,state,generation,model,DY778CurrentAccountID() ?: @"",identifier,0);
}
static void DY778FeedTrackTag(id component) {
    if (!component) return;
    if (!NSThread.isMainThread) {
        __weak id weakComponent = component;
        dispatch_async(dispatch_get_main_queue(),^{ id current = weakComponent; if (current) DY778FeedTrackTag(current); });
        return;
    }
    [DY778FeedAdTags addObject:component];
    if (!DY778FeedEnabled) return;
    id model = DY778Read(component,@"model");
    for (id owner in DY778FeedOwners.allObjects) if (DY778FeedSameModel(DY778Read(owner,@"currentAweme"),model)) DY778FeedSchedule(owner);
}
static void DY778FeedInstall(NSString *className, NSString *name, NSString *arguments, void (^after)(id)) {
    Class cls = NSClassFromString(className); SEL selector = NSSelectorFromString(name);
    NSString *hookName = [NSString stringWithFormat:@"%@/%@",className,name];
    if ([DY778FeedHooks containsObject:hookName] || !DY778FeedSignature(cls,selector,arguments.UTF8String)) return;
    __block IMP original = NULL;
    void (^perform)(id,id,id,id,BOOL) = ^(id owner,id a,id b,id c,BOOL flag) {
        const void *hook = (__bridge const void *)hookName;
        if (DY778PlaybackFrameContains(DY778FeedStack,(__bridge const void *)owner,hook)) return;
        DY778PlaybackFrame frame = {(__bridge const void *)owner,hook,DY778FeedStack}; DY778FeedStack = &frame;
        @try {
            if ([arguments isEqual:@"@@@"]) ((void (*)(id,SEL,id,id,id))original)(owner,selector,a,b,c);
            else if ([arguments isEqual:@"@B"]) ((void (*)(id,SEL,id,BOOL))original)(owner,selector,a,flag);
            else if ([arguments isEqual:@"B"]) ((void (*)(id,SEL,BOOL))original)(owner,selector,flag);
            else ((void (*)(id,SEL,id))original)(owner,selector,a);
        } @finally { DY778FeedStack = frame.previous; }
        if (![arguments isEqual:@"@B"] || !flag) after(owner);
    };
    IMP replacement;
    if ([arguments isEqual:@"@@@"]) replacement=imp_implementationWithBlock(^(id owner,id a,id b,id c){ perform(owner,a,b,c,NO); });
    else if ([arguments isEqual:@"@B"]) replacement=imp_implementationWithBlock(^(id owner,id a,BOOL flag){ perform(owner,a,nil,nil,flag); });
    else if ([arguments isEqual:@"B"]) replacement=imp_implementationWithBlock(^(id owner,BOOL flag){ perform(owner,nil,nil,nil,flag); });
    else replacement=imp_implementationWithBlock(^(id owner,id a){ perform(owner,a,nil,nil,NO); });
    BOOL installed=DY778Hook(cls,selector,replacement,&original);
    if (installed) [DY778FeedHooks addObject:hookName]; else imp_removeBlock(replacement);
    DY778RecordHook([@"DY778 测试过滤 / " stringByAppendingString:hookName],installed);
}
void DY778InstallFeedFilterHooks(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ DY778InstallFeedFilterHooks(); }); return; }
    static dispatch_once_t once; dispatch_once(&once,^{
        DY778FeedHooks=[NSMutableSet set]; DY778FeedSeen=[NSMutableOrderedSet orderedSet]; DY778FeedOwners=[NSHashTable weakObjectsHashTable];
        DY778FeedAdTags=[NSHashTable weakObjectsHashTable];
        DY778FeedEnabled=DY778Bool(@"experimental.skipAds");
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
            NSString *key=note.userInfo[@"key"]; if (key.length && ![key isEqual:@"experimental.skipAds"]) return;
            DY778FeedEnabled=DY778Bool(@"experimental.skipAds");
            for (id owner in DY778FeedOwners.allObjects) DY778FeedSchedule(owner);
        }];
    });
    void (^schedule)(id) = ^(id owner){ DY778FeedSchedule(owner); };
    DY778FeedInstall(@"AWEFeedTableViewController",@"viewDidAppear:",@"B",schedule);
    DY778FeedInstall(@"AWEFeedTableViewController",@"tableView:didDisplayCell:forRowAtIndexPath:",@"@@@",schedule);
    DY778FeedInstall(@"AWEFeedTableViewController",@"scrollViewDidEndDecelerating:",@"@",schedule);
    DY778FeedInstall(@"AWEFeedTableViewController",@"scrollViewDidEndScrollingAnimation:",@"@",schedule);
    DY778FeedInstall(@"AWEFeedTableViewController",@"scrollViewDidEndDragging:willDecelerate:",@"@B",schedule);
    DY778FeedInstall(@"AWEAdTagComponent",@"updateWithModel:",@"@",^(id component){ DY778FeedTrackTag(component); });
}
