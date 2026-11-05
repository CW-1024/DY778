#import "DY778ListClear.h"
#import "DY778ListClearPolicy.h"
#import "DY778Core.h"

static NSString *const DY778ListClearEnabledKey = @"listClear.enabled";
static NSString *const DY778ListClearScopeKey = @"DY778.ListClear.Receipt";
static const char DY778ListClearGestureKey;
static BOOL DY778ListClearGetReady, DY778ListClearPostReady, DY778ListClearCellReady, DY778ListClearLegacyReady, DY778ListClearReloadReady;
typedef NS_ENUM(NSUInteger, DY778ListKind) { DY778ListRecommendations, DY778ListCollections, DY778ListLikes };

@interface NSObject (DY778ListClearNativeInitialization)
- (instancetype)initWithUserID:(NSString *)userID;
- (instancetype)initWithSecUserID:(NSString *)secUserID;
@end

static NSString *DY778ListClearName(DY778ListKind kind) { return @[@"推荐", @"收藏", @"喜欢"][kind]; }
static NSString *DY778ListClearResponseClass(DY778ListKind kind) {
    return @[@"AWEFamiliarRecommendBatchDeleteResponseModel", @"AWEFavoriteCancelMultiFavoriteResponseModel", @"AWEUserLikesCancelMultiLikeResponseModel"][kind];
}
static BOOL DY778ListClearMethod(id object, SEL selector, char result, NSUInteger arguments) {
    if (!object || !selector) return NO;
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != arguments) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    return signature && signature.methodReturnType[0] == result;
}
static BOOL DY778ListClearObjectArguments(id object, SEL selector, NSUInteger arguments) {
    if (!DY778ListClearMethod(object, selector, 'v', arguments)) return NO;
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (!signature) return NO;
    for (NSUInteger index = 2; index < arguments; index++) if ([signature getArgumentTypeAtIndex:index][0] != '@') return NO;
    return YES;
}
static void DY778ListClearCallVoid(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!DY778ListClearMethod(object, selector, 'v', 2)) return;
    @try { ((void (*)(id, SEL))objc_msgSend)(object, selector); } @catch (__unused NSException *exception) {}
}
static void DY778ListClearCancel(id object) {
    SEL selector = NSSelectorFromString(@"cancel");
    if (DY778ListClearMethod(object, selector, 'v', 2)) DY778ListClearCallVoid(object, @"cancel");
}
static NSString *DY778ListClearID(id value) {
    NSString *identifier = DY778Identifier(value);
    if (!identifier.length || [identifier isEqualToString:@"0"]) return nil;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    return [identifier rangeOfCharacterFromSet:invalid].location == NSNotFound ? identifier : nil;
}
static NSSet<NSString *> *DY778ListClearIDs(id value, BOOL allowDelimited) {
    if (allowDelimited && [value isKindOfClass:NSString.class]) {
        NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
        id decoded = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        value = [decoded isKindOfClass:NSArray.class] ? decoded : [value componentsSeparatedByString:@","];
    }
    if (![value isKindOfClass:NSArray.class]) return nil;
    NSMutableSet *result = [NSMutableSet set];
    for (id element in value) {
        if (allowDelimited && [element isKindOfClass:NSString.class] && ![element length]) continue;
        NSString *identifier = DY778ListClearID(element);
        if (!identifier || [result containsObject:identifier]) return nil;
        [result addObject:identifier];
    }
    return result;
}

@interface DY778ListClearReceipt : NSObject
@property(nonatomic) DY778ListKind kind;
@property(nonatomic, copy) NSSet<NSString *> *expectedIDs;
@property(nonatomic, copy) NSSet<NSString *> *failedIDs;
@property(nonatomic, copy) BOOL (^current)(void);
@property(nonatomic, strong) id task;
@property(nonatomic) BOOL intercepted, submitted, received, verified;
@property(nonatomic, copy) NSString *failureReason;
@end
@implementation DY778ListClearReceipt
@end

typedef id (*DY778ListClearNetworkIMP)(id, SEL, id, id, Class, id);
static DY778ListClearNetworkIMP DY778ListClearOriginalGet, DY778ListClearOriginalPost;
static id DY778ListClearNetwork(DY778ListClearNetworkIMP original, id object, SEL command,
                               id URL, id parameters, Class modelClass, id completion) {
    DY778ListClearReceipt *receipt = NSThread.currentThread.threadDictionary[DY778ListClearScopeKey];
    if (![receipt isKindOfClass:DY778ListClearReceipt.class]) return original(object, command, URL, parameters, modelClass, completion);
    // 该作用域只围绕我们的原生批量方法存在；绝不让
    // 未经校验的改动从普通透传分支漏出。
    if (receipt.intercepted) return nil;
    receipt.intercepted = YES;
    if (!completion) { receipt.failureReason = @"取消回调不可用，尚未提交"; return nil; }
    NSString *urlText = [URL isKindOfClass:NSString.class] ? URL : ([URL isKindOfClass:NSURL.class] ? [URL absoluteString] : nil);
    NSString *path = urlText ? [NSURLComponents componentsWithString:urlText].percentEncodedPath : nil;
    BOOL methodMatches = command == NSSelectorFromString(receipt.kind == DY778ListRecommendations ?
        @"postWithURLString:params:modelClass:completion:" : @"getWithURLString:params:modelClass:completion:");
    BOOL routeMatches = DY778ListClearMatchesPath(path.UTF8String, (unsigned int)receipt.kind);
    BOOL modelMatches = modelClass && modelClass == NSClassFromString(DY778ListClearResponseClass(receipt.kind));
    NSString *idsKey = receipt.kind == DY778ListRecommendations ? @"item_id_list" : @"aweme_ids";
    NSSet *requestIDs = [parameters isKindOfClass:NSDictionary.class] ? DY778ListClearIDs(parameters[idsKey], YES) : nil;
    BOOL requestMatches = methodMatches && routeMatches && modelMatches && [requestIDs isEqualToSet:receipt.expectedIDs];
    void (^hostCompletion)(id, NSError *) = [completion copy];
    void (^wrapped)(id, NSError *) = ^(id response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (receipt.received || !receipt.current || !receipt.current()) return;
            receipt.received = YES; receipt.task = nil;
            NSString *failedKey = receipt.kind == DY778ListRecommendations ? @"failItemIds" : @"fatalIds";
            id status = DY778Read(response, @"statusCode");
            id failed = DY778Read(response, failedKey);
            BOOL schema = modelMatches && response && [response isKindOfClass:modelClass] &&
                [response respondsToSelector:NSSelectorFromString(failedKey)];
            NSSet *failedIDs = failed ? DY778ListClearIDs(failed, NO) : [NSSet set];
            receipt.verified = DY778ListClearVerifiedReceipt(receipt.submitted, requestMatches, schema,
                [status isKindOfClass:NSNumber.class], [status respondsToSelector:@selector(longLongValue)] ? [status longLongValue] : -1,
                error != nil, failedIDs != nil, [failedIDs isSubsetOfSet:receipt.expectedIDs]);
            receipt.failedIDs = failedIDs ?: [NSSet set];
            @try { hostCompletion(response, error); } @catch (__unused NSException *exception) {}
        });
    };
    if (!requestMatches || !receipt.current || !receipt.current()) {
        receipt.failureReason = @"请求核对未通过，尚未提交本批";
        wrapped(nil, [NSError errorWithDomain:@"DY778.ListClear" code:1 userInfo:nil]); return nil;
    }
    receipt.submitted = YES;
    id task = original(object, command, URL, parameters, modelClass, wrapped);
    receipt.task = task; return task;
}
static id DY778ListClearGet(id object, SEL command, id URL, id parameters, Class modelClass, id completion) {
    return DY778ListClearNetwork(DY778ListClearOriginalGet, object, command, URL, parameters, modelClass, completion);
}
static id DY778ListClearPost(id object, SEL command, id URL, id parameters, Class modelClass, id completion) {
    return DY778ListClearNetwork(DY778ListClearOriginalPost, object, command, URL, parameters, modelClass, completion);
}

@interface DY778ListClearJob : NSObject <UIGestureRecognizerDelegate> {
    DY778ListClearState _state;
}
@property(nonatomic, readonly) BOOL active;
@property(nonatomic) DY778ListKind kind;
@property(nonatomic, copy) NSString *account;
@property(nonatomic, strong) id user;
@property(nonatomic, strong) id dataController;
@property(nonatomic, strong) NSMutableArray *snapshot;
@property(nonatomic, strong) NSMutableSet<NSString *> *seenIDs;
@property(nonatomic, strong) NSMutableSet<NSString *> *seenCursors;
@property(nonatomic, strong) DY778ListClearReceipt *receipt;
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic, copy) NSString *toastToken;
@property(nonatomic, strong) NSTimer *monitor;
@property(nonatomic) BOOL hasUnavailableItems;
+ (instancetype)shared;
- (void)longPress:(UILongPressGestureRecognizer *)gesture;
- (void)startKind:(DY778ListKind)kind user:(id)user owner:(UIViewController *)owner;
- (void)stop:(NSString *)reason;
- (void)updateProgress;
- (void)updateProgressBeginning:(BOOL)beginning;
- (void)settingsChanged;
@end

static BOOL DY778ListClearHostClass(id object, NSString *name) {
    Class cls = NSClassFromString(name); return object && cls && [object isKindOfClass:cls];
}
static BOOL DY778ListClearOwnProfile(UIViewController *owner, NSString *account, id *userOut) {
    if (!owner || !account.length) return NO;
    BOOL home = DY778ListClearHostClass(owner, @"AWEUserHomeViewControllerV2");
    BOOL detail = DY778ListClearHostClass(owner, @"AWEUserDetailViewControllerV2");
    if (!home && !detail) return NO;
    id user = DY778Read(owner, @"userForTabVC") ?: DY778Read(owner, @"userModel") ?: DY778Read(owner, @"user");
    BOOL sameAccount = [DY778Identifier(DY778Read(user, @"userID")) isEqualToString:account];
    // 「我」页用的是 isCurrentUserProfilePage，不是详情控制器的 isCurrentUser。
    if (!DY778ListClearEligibleProfile(home, detail, [DY778Read(owner, @"isCurrentUserProfilePage") boolValue],
                                      [DY778Read(owner, @"isCurrentUser") boolValue], sameAccount)) return NO;
    if (userOut) *userOut = user;
    return YES;
}
static BOOL DY778ListClearProfileVisible(UIViewController *owner) {
    if (!owner.isViewLoaded || !owner.view.window || owner.view.window != DY778ActiveWindow()) return NO;
    id appeared = DY778Read(owner, @"isViewDidAppear");
    if ([appeared isKindOfClass:NSNumber.class] && ![appeared boolValue]) return NO;
    UIView *view = owner.view;
    for (NSUInteger depth = 0; view && depth < 48; depth++, view = view.superview)
        if (view.hidden || view.alpha < .01) return NO;
    UIViewController *parent = owner;
    for (NSUInteger depth = 0; parent && depth < 24; depth++, parent = parent.parentViewController) {
        if (parent.isBeingDismissed || parent.isMovingFromParentViewController) return NO;
        UIViewController *presented = parent.presentedViewController;
        if (presented && !presented.isBeingDismissed) return NO;
        if ([parent isKindOfClass:UINavigationController.class]) {
            UIViewController *visible = ((UINavigationController *)parent).visibleViewController;
            if (visible && visible != owner && ![owner.view isDescendantOfView:visible.view]) return NO;
        }
    }
    return YES;
}
static void DY778ListClearRefreshProfile(UIViewController *owner, DY778ListKind kind, NSString *account) {
    if (![account isEqualToString:DY778CurrentAccountID()] || !DY778ListClearOwnProfile(owner, account, NULL) ||
        !DY778ListClearProfileVisible(owner) || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    // 「我」页容器与详情容器暴露的头部刷新接口不同。
    DY778ListClearCallVoid(owner, DY778ListClearHostClass(owner, @"AWEUserHomeViewControllerV2") ? @"refreshData" : @"refreshUserData");
    SEL tabSelector = NSSelectorFromString(@"tabVCForType:");
    if (!DY778ListClearMethod(owner, tabSelector, '@', 3)) return;
    NSMethodSignature *signature = [owner methodSignatureForSelector:tabSelector];
    if (!signature || [signature getArgumentTypeAtIndex:2][0] != 'q') return;
    id root = nil;
    @try { root = ((id (*)(id, SEL, long long))objc_msgSend)(owner, tabSelector, (long long[]){33, 16, 2}[kind]); }
    @catch (__unused NSException *exception) { return; }
    if (![root isKindOfClass:UIViewController.class]) return;
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithObject:root];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    NSString *expectedClass = @[@"AWEFamiliarRecommendWorkViewController", @"AWEFavoriteViewController", @"AWELikeWorkViewController"][kind];
    for (NSUInteger index = 0; index < queue.count && index < 32; index++) {
        UIViewController *controller = queue[index];
        if ([seen containsObject:controller]) continue;
        [seen addObject:controller];
        if (controller.isViewLoaded && DY778ListClearHostClass(controller, expectedClass))
            DY778ListClearCallVoid(controller, kind == DY778ListRecommendations ? @"refreshDataIfNeed" : @"refreshData");
        for (UIViewController *child in controller.childViewControllers) if (queue.count < 32) [queue addObject:child];
    }
}
static BOOL DY778ListClearProfileLink(id object) {
    return [object isKindOfClass:UIViewController.class] ||
        DY778ListClearHostClass(object, @"AWEUserHomeBaseComponent") ||
        DY778ListClearHostClass(object, @"AWEUserDetailBaseComponent") ||
        DY778ListClearHostClass(object, @"AWEProfileBaseHeaderSectionController");
}
static UIViewController *DY778ListClearProfileForView(UIView *view) {
    NSMutableArray *queue = [NSMutableArray array]; UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 40; depth++, responder = responder.nextResponder)
        if ([responder isKindOfClass:UIViewController.class]) [queue addObject:responder];
    // 只顺着原生主页组件/控制器的关联走，绝不借用 window 或当前选中标签。
    UIView *ancestor = view;
    for (NSUInteger depth = 0; ancestor && depth < 20; depth++, ancestor = ancestor.superview) {
        if (!DY778ListClearHostClass(ancestor, @"AWEProfileBaseHeaderCell")) continue;
        id delegate = DY778Read(ancestor, @"delegate"); if (DY778ListClearProfileLink(delegate)) [queue addObject:delegate]; break;
    }
    NSHashTable *visited = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    NSString *account = DY778CurrentAccountID();
    for (NSUInteger index = 0; index < queue.count && index < 48; index++) {
        id object = queue[index]; if ([visited containsObject:object]) continue; [visited addObject:object];
        if ([object isKindOfClass:UIViewController.class] && DY778ListClearOwnProfile(object, account, NULL)) return object;
        for (NSString *key in @[@"parentViewController", @"delegate", @"dataSource", @"container", @"baseVC", @"viewController"]) {
            id linked = DY778Read(object, key);
            if (DY778ListClearProfileLink(linked) && ![visited containsObject:linked]) [queue addObject:linked];
        }
    }
    return nil;
}
static BOOL DY778ListClearTargetForView(UIView *view, UIViewController **ownerOut, DY778ListKind *kindOut, id *userOut) {
    if (!view) return NO;
    UIViewController *owner = DY778ListClearProfileForView(view); id user = nil;
    if (!DY778ListClearOwnProfile(owner, DY778CurrentAccountID(), &user)) return NO;
    id mainContainer = DY778Read(owner, @"tabListViewController") ?: DY778Read(owner, @"tabListVC");
    id helper = DY778Read(owner, @"tabHelper");
    NSArray *profileModels = DY778Read(helper, @"tabArray");
    if (![profileModels isKindOfClass:NSArray.class] || !profileModels.count) return NO;
    UIView *host = view.superview;
    for (NSUInteger depth = 0; host && depth < 20; depth++, host = host.superview) {
        if (DY778ListClearHostClass(host, @"AWERLSegmentView") || DY778ListClearHostClass(host, @"AWEProfileBaseHeaderCell")) break;
    }
    NSUInteger index = NSNotFound, viewCount = 0; BOOL primary = NO;
    if (DY778ListClearHostClass(host, @"AWERLSegmentView")) {
        if (!DY778ListClearHostClass(view, @"AWERLSegmentItemView")) return NO;
        id primarySegment = DY778Read(mainContainer, @"segmentView");
        id homeSegment = DY778Read(DY778Read(owner, @"segmentHomeComponent"), @"segmentView");
        id orchestratedSegment = DY778Read(DY778Read(owner, @"uiComponent"), @"segmentView");
        primary = host == primarySegment || host == homeSegment || host == orchestratedSegment;
        NSArray *views = DY778Read(host, @"itemViews"); NSArray *models = DY778Read(host, @"itemModels");
        id nativeIndex = DY778Read(view, @"data");
        if (![views isKindOfClass:NSArray.class] || ![models isKindOfClass:NSArray.class] ||
            ![nativeIndex isKindOfClass:NSNumber.class] || [nativeIndex longLongValue] < 0) return NO;
        // __updateItemSelectAction: 会把原生点击所用的同一下标放进 item.data。
        index = [nativeIndex unsignedIntegerValue]; viewCount = views.count;
        if (index >= views.count || index >= models.count || views[index] != view) return NO;
    } else if (DY778ListClearHostClass(host, @"AWEProfileBaseHeaderCell")) {
        if (![view isKindOfClass:UICollectionViewCell.class] || !DY778ListClearHostClass(mainContainer, @"AWEProfileTabContainerViewController")) return NO;
        id header = DY778Read(DY778Read(DY778Read(mainContainer, @"baseVC"), @"headerSectionController"), @"currentCell");
        primary = header == host;
        UICollectionView *collection = DY778Read(host, @"collectionView");
        if (![collection isKindOfClass:UICollectionView.class]) return NO;
        NSIndexPath *path = [collection indexPathForCell:(UICollectionViewCell *)view];
        NSArray *models = DY778Read(DY778Read(host, @"context"), @"tabItemsArray");
        if (!path || path.section != 0 || ![models isKindOfClass:NSArray.class]) return NO;
        index = (NSUInteger)path.item; viewCount = models.count;
    }
    if (!DY778ListClearPrimaryTabIndex(primary, index, viewCount, profileModels.count)) return NO;
    id type = DY778Read(profileModels[index], @"profileTabType");
    if (![type isKindOfClass:NSNumber.class]) return NO;
    SEL typeSelector = NSSelectorFromString(@"tabTypeAtIndex:");
    if (!DY778ListClearMethod(helper, typeSelector, 'q', 3)) return NO;
    NSMethodSignature *signature = [helper methodSignatureForSelector:typeSelector];
    if (!signature || [signature getArgumentTypeAtIndex:2][0] != 'q') return NO;
    long long nativeType;
    @try { nativeType = ((long long (*)(id, SEL, long long))objc_msgSend)(helper, typeSelector, (long long)index); }
    @catch (__unused NSException *exception) { return NO; }
    if (nativeType != [type longLongValue]) return NO;
    int kind = DY778ListClearKindForProfileTab(nativeType); if (kind < 0) return NO;
    if (ownerOut) *ownerOut = owner; if (kindOut) *kindOut = (DY778ListKind)kind; if (userOut) *userOut = user;
    return YES;
}
@implementation DY778ListClearJob
+ (instancetype)shared {
    static DY778ListClearJob *job; static dispatch_once_t once;
    dispatch_once(&once, ^{
        job = [DY778ListClearJob new];
        [NSNotificationCenter.defaultCenter addObserver:job selector:@selector(settingsChanged) name:DY778PreferencesChangedNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:job selector:@selector(background) name:UIApplicationWillResignActiveNotification object:nil];
    }); return job;
}
- (BOOL)active { return _state.active; }
- (void)background { [self stop:@"已切到后台，清理已停止"]; }
- (void)settingsChanged {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self settingsChanged]; }); return; }
    if (!DY778Bool(DY778ListClearEnabledKey)) [self stop:@"功能已关闭，清理已停止"];
}
- (BOOL)current {
    if (!_state.active) return NO;
    if (!DY778Bool(DY778ListClearEnabledKey)) { [self stop:@"功能已关闭，清理已停止"]; return NO; }
    if (![self.account isEqualToString:DY778CurrentAccountID()] || !DY778ListClearOwnProfile(self.owner, self.account, NULL)) {
        [self stop:@"账号已变化，清理已停止"]; return NO;
    }
    if (!DY778ListClearProfileVisible(self.owner)) { [self stop:@"已离开本人主页，清理已停止"]; return NO; }
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { [self background]; return NO; }
    return YES;
}
- (void)updateProgress {
    [self updateProgressBeginning:NO];
}
- (void)updateProgressBeginning:(BOOL)beginning {
    if (!_state.active || !self.toastToken.length) return;
    NSString *name = DY778ListClearName(self.kind);
    NSString *text = _state.removing ? [NSString stringWithFormat:@"取消%@中 %lu/%lu", name, (unsigned long)_state.confirmed, (unsigned long)_state.total] :
        [NSString stringWithFormat:@"读取%@中 · %lu 项", name, (unsigned long)_state.total];
    NSString *token = self.toastToken; uint64_t generation = _state.generation;
    __weak typeof(self) weakSelf = self;
    dispatch_block_t stopAction = ^{
        DY778ListClearJob *job = weakSelf;
        if (job && job->_state.active && job->_state.generation == generation && [job.toastToken isEqualToString:token])
            [job stop:@"已停止后续清理"];
    };
    if (beginning) DY778BeginProgressToast(@"listClear", token, text, stopAction);
    else DY778ShowProgressToast(@"listClear", token, text, stopAction);
}
- (void)finish:(NSString *)message success:(BOOL)success uncertain:(BOOL)uncertain {
    if (!_state.active) return;
    BOOL shouldRefresh = _state.confirmed || self.receipt.submitted || uncertain;
    NSString *token = self.toastToken;
    DY778ListClearStop(&_state);
    [self.monitor invalidate]; self.monitor = nil;
    DY778ListClearCancel(self.receipt.task);
    SEL cancel = NSSelectorFromString(@"cancelCurrentRequest");
    if (DY778ListClearMethod(self.dataController, cancel, 'B', 2)) {
        @try { ((BOOL (*)(id, SEL))objc_msgSend)(self.dataController, cancel); } @catch (__unused NSException *exception) {}
    }
    self.receipt.current = nil; self.receipt = nil; self.dataController = nil;
    self.snapshot = nil; self.seenIDs = nil; self.seenCursors = nil;
    NSString *text = success ? message : [NSString stringWithFormat:@"%@\n已确认取消 %lu 项%@", message,
        (unsigned long)_state.confirmed, uncertain ? @"，请刷新核对" : @""];
    DY778FinishProgressToast(@"listClear", token, text, success);
    self.toastToken = nil; self.user = nil;
    if (shouldRefresh) {
        uint64_t generation = _state.generation; NSString *account = self.account; DY778ListKind kind = self.kind;
        __weak typeof(self) weakSelf = self; __weak UIViewController *owner = self.owner;
        // 刷新前先退出原生删除的同步回执作用域。
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778ListClearJob *job = weakSelf;
            if (job && !job->_state.active && job->_state.generation == generation)
                DY778ListClearRefreshProfile(owner, kind, account);
        });
    }
}
- (void)stop:(NSString *)reason {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self stop:reason]; }); return; }
    [self finish:reason success:NO uncertain:_state.removing && _state.waiting && self.receipt.submitted && !self.receipt.received];
}
- (void)armTimeout:(uint64_t)ticket generation:(uint64_t)generation {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DY778ListClearJob *job = weakSelf;
        if (job && DY778ListClearIsCurrent(&job->_state, generation, ticket)) [job stop:@"等待抖音返回结果超时，已停止后续处理"];
    });
}
- (NSString *)cursor {
    id value = DY778Read(self.dataController, self.kind == DY778ListCollections ? @"cursor" : @"maxCursor");
    return DY778Identifier(value) ?: @"";
}
- (void)readPage:(BOOL)first {
    if (![self current]) return;
    uint64_t ticket = DY778ListClearIssue(&_state), generation = _state.generation;
    if (!ticket) return;
    SEL selector = NSSelectorFromString(first ? @"refreshWithCompletion:" : @"loadMoreWithCompletion:");
    if (!DY778ListClearObjectArguments(self.dataController, selector, 3)) { [self stop:@"当前版本的列表读取接口不可用，尚未执行取消"]; return; }
    [self armTimeout:ticket generation:generation];
    __weak typeof(self) weakSelf = self;
    void (^completion)(NSArray *, NSError *) = ^(NSArray *items, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778ListClearJob *job = weakSelf;
            if (!job || !DY778ListClearIsCurrent(&job->_state, generation, ticket) ||
                ![job current] || !DY778ListClearConsume(&job->_state, generation, ticket)) return;
            if (error || ![items isKindOfClass:NSArray.class]) { [job stop:@"未能完整读取列表，尚未执行任何取消，请稍后重试"]; return; }
            NSUInteger before = job.snapshot.count;
            Class awemeClass = NSClassFromString(@"AWEAwemeModel");
            for (id model in items) {
                NSString *identifier = DY778ListClearID(DY778Read(model, @"itemID"));
                if (!identifier || !awemeClass || ![model isKindOfClass:awemeClass]) { job.hasUnavailableItems = YES; continue; }
                if ([job.seenIDs containsObject:identifier]) continue;
                [job.seenIDs addObject:identifier]; [job.snapshot addObject:model];
            }
            id moreValue = DY778Read(job.dataController, @"loadmoreHasMore");
            if (![moreValue isKindOfClass:NSNumber.class]) { [job stop:@"未能确认列表是否读取完整，尚未执行任何取消"]; return; }
            BOOL more = [moreValue boolValue]; NSString *cursor = [job cursor];
            BOOL advanced = cursor.length && ![job.seenCursors containsObject:cursor];
            if (cursor.length) [job.seenCursors addObject:cursor];
            DY778ListClearDecision decision = DY778ListClearPage(&job->_state, job.snapshot.count - before, more, advanced);
            [job updateProgress];
            if (decision == DY778ListClearLimit) { [job stop:@"列表较大，本次未能完整读取；尚未执行取消，请先在抖音内分批整理"]; return; }
            if (decision == DY778ListClearNoProgress || decision == DY778ListClearInvalid) { [job stop:@"列表分页未能继续，尚未执行任何取消，请刷新后重试"]; return; }
            if (decision == DY778ListClearComplete) {
                if (!job.snapshot.count) {
                    [job finish:job.hasUnavailableItems ? @"部分作品无法读取，请手动核对" : @"当前没有可清理的作品" success:!job.hasUnavailableItems uncertain:NO]; return;
                }
                job->_state.removing = YES; [job updateProgress];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (job->_state.active && job->_state.generation == generation) [job removeNextBatch];
                }); return;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (job->_state.active && job->_state.generation == generation) [job readPage:NO];
            });
        });
    };
    @try { ((void (*)(id, SEL, id))objc_msgSend)(self.dataController, selector, completion); }
    @catch (__unused NSException *exception) { [self stop:@"列表读取未能完成，尚未执行任何取消"]; }
}
- (void)removeNextBatch {
    if (![self current]) return;
    NSUInteger offset = _state.confirmed;
    if (offset >= self.snapshot.count) { [self stop:@"列表状态已变化，请返回原列表核对"]; return; }
    NSUInteger count = MIN((NSUInteger)DY778_LIST_CLEAR_BATCH, self.snapshot.count - offset);
    NSArray *models = [self.snapshot subarrayWithRange:NSMakeRange(offset, count)];
    NSMutableSet *ids = [NSMutableSet set]; NSMutableArray *paths = [NSMutableArray array];
    for (NSUInteger index = 0; index < models.count; index++) {
        NSString *identifier = DY778ListClearID(DY778Read(models[index], @"itemID"));
        if (!identifier || [ids containsObject:identifier]) { [self stop:@"作品标识已变化，已停止后续处理"]; return; }
        [ids addObject:identifier]; [paths addObject:[NSIndexPath indexPathForItem:(NSInteger)index inSection:0]];
    }
    if (!DY778Write(self.dataController, @"dataSource", [models mutableCopy])) { [self stop:@"当前版本无法准备取消操作，已停止后续处理"]; return; }
    uint64_t ticket = DY778ListClearIssue(&_state), generation = _state.generation;
    if (!ticket) return;
    DY778ListClearReceipt *receipt = [DY778ListClearReceipt new]; receipt.kind = self.kind; receipt.expectedIDs = ids; self.receipt = receipt;
    __weak typeof(self) weakSelf = self;
    receipt.current = ^BOOL {
        DY778ListClearJob *job = weakSelf;
        return job && DY778ListClearIsCurrent(&job->_state, generation, ticket) && [job current];
    };
    [self armTimeout:ticket generation:generation];
    [self updateProgress];
    void (^completion)(BOOL) = ^(__unused BOOL nativeSuccess) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778ListClearJob *job = weakSelf;
            if (!job || !DY778ListClearIsCurrent(&job->_state, generation, ticket) ||
                ![job current] || !DY778ListClearConsume(&job->_state, generation, ticket)) return;
            // 原生 BOOL 不体现单项失败；以校验过的服务端回执为准。
            BOOL verified = receipt.intercepted && receipt.received && receipt.verified;
            DY778ListClearDecision result = DY778ListClearBatchResult(&job->_state, count, receipt.failedIDs.count, verified);
            receipt.current = nil;
            if (result == DY778ListClearInvalid) {
                [job finish:receipt.failureReason ?: @"本批结果未能确认，已停止" success:NO uncertain:receipt.submitted]; return;
            }
            if (result == DY778ListClearPartial) {
                [job finish:[NSString stringWithFormat:@"本批 %lu 项未能取消，已停止", (unsigned long)receipt.failedIDs.count] success:NO uncertain:NO]; return;
            }
            [job updateProgress];
            if (result == DY778ListClearComplete) {
                NSString *message = [NSString stringWithFormat:@"已取消%@ %lu 项%@", DY778ListClearName(job.kind), (unsigned long)job->_state.confirmed,
                    job.hasUnavailableItems ? @"\n部分条目需手动核对" : @""];
                [job finish:message success:YES uncertain:NO]; return;
            }
            job.receipt = nil;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (job->_state.active && job->_state.generation == generation) [job removeNextBatch];
            });
        });
    };
    NSMutableDictionary *threadState = NSThread.currentThread.threadDictionary;
    id previous = threadState[DY778ListClearScopeKey]; threadState[DY778ListClearScopeKey] = receipt;
    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)(self.dataController, NSSelectorFromString(@"removeItemsAtIndexPaths:completion:"), paths, completion);
    } @catch (__unused NSException *exception) { [self stop:@"取消操作未能正常完成，已停止后续处理"]; }
    @finally {
        if (previous) threadState[DY778ListClearScopeKey] = previous; else [threadState removeObjectForKey:DY778ListClearScopeKey];
    }
    if (_state.active && _state.generation == generation) {
        if (!receipt.intercepted) [self finish:@"未捕获本批请求，已停止" success:NO uncertain:YES];
        else if (!receipt.submitted && receipt.failureReason.length) [self stop:receipt.failureReason];
    }
}
- (void)startKind:(DY778ListKind)kind user:(id)user owner:(UIViewController *)owner {
    if (_state.active) { DY778Toast(@"已有一项清空操作正在进行"); return; }
    self.kind = kind; self.account = DY778CurrentAccountID(); self.user = user; self.owner = owner;
    self.hasUnavailableItems = NO; self.toastToken = NSUUID.UUID.UUIDString;
    DY778ListClearBegin(&_state); [self updateProgressBeginning:YES];
    if (![self current] || ![DY778Identifier(DY778Read(user, @"userID")) isEqualToString:self.account]) { [self stop:@"账号资料已变化，请返回自己的主页重试"]; return; }
    if ((kind == DY778ListRecommendations && !DY778ListClearPostReady) || (kind != DY778ListRecommendations && !DY778ListClearGetReady)) {
        [self stop:@"当前版本的结果校验接口不可用，尚未执行取消"]; return;
    }
    NSString *className = @[@"AWEFamiliarRecommendWorkDataController", @"AWEFavoriteAwemeDataController", @"AWEUserLikesDataManager"][kind];
    Class cls = NSClassFromString(className);
    @try {
        if (kind == DY778ListRecommendations) {
            NSString *secID = DY778Identifier(DY778Read(user, @"secUserID"));
            if (!secID.length || ![cls instancesRespondToSelector:@selector(initWithSecUserID:)]) { [self stop:@"未能读取当前账号的完整资料，尚未执行取消"]; return; }
            self.dataController = [[cls alloc] initWithSecUserID:secID];
        } else if (kind == DY778ListLikes) {
            if (![cls instancesRespondToSelector:@selector(initWithUserID:)]) { [self stop:@"当前版本的喜欢列表接口不可用"]; return; }
            self.dataController = [[cls alloc] initWithUserID:self.account];
        } else { self.dataController = [[cls alloc] init]; }
    } @catch (__unused NSException *exception) { [self stop:@"列表准备失败，尚未执行取消"]; return; }
    BOOL configured = kind == DY778ListCollections ? DY778Write(self.dataController, @"user", user) : DY778Write(self.dataController, @"isCurrentUser", @YES);
    if (!configured || !DY778ListClearObjectArguments(self.dataController, NSSelectorFromString(@"removeItemsAtIndexPaths:completion:"), 4)) {
        [self stop:@"当前版本的批量取消接口不可用，尚未执行取消"]; return;
    }
    self.snapshot = [NSMutableArray array]; self.seenIDs = [NSMutableSet set]; self.seenCursors = [NSMutableSet set];
    __weak typeof(self) weakSelf = self;
    self.monitor = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf current]; }];
    [NSRunLoop.mainRunLoop addTimer:self.monitor forMode:NSRunLoopCommonModes];
    [self readPage:YES];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    return DY778Bool(DY778ListClearEnabledKey) && DY778ListClearTargetForView(gesture.view, NULL, NULL, NULL);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }
- (void)longPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || !DY778Bool(DY778ListClearEnabledKey)) return;
    UIViewController *owner = nil; id user = nil; DY778ListKind kind;
    if (!DY778ListClearTargetForView(gesture.view, &owner, &kind, &user)) return;
    if (_state.active) { [self updateProgress]; return; }
    NSString *name = DY778ListClearName(kind);
    NSString *scope = @[@"逐一取消当前账号推荐过的作品", @"逐一取消当前账号收藏的作品，不处理音乐、地点等其他收藏分类", @"逐一取消当前账号喜欢的作品"][kind];
    NSString *message = [NSString stringWithFormat:@"将%@。这会实际修改账号记录，不会删除作品，且无法一键撤销。\n\n确认后在当前页面处理，可点进度提示中的“停止”。离开本人主页或退到后台会停止后续操作；已完成的取消会保留，已提交的请求可能继续完成。", scope];
    NSString *account = DY778CurrentAccountID(); __weak UIViewController *weakOwner = owner;
    DY778Confirm(owner, [NSString stringWithFormat:@"清空%@作品？", name], message, [NSString stringWithFormat:@"取消全部%@", name], YES, ^{
        if (!DY778Bool(DY778ListClearEnabledKey) || ![account isEqualToString:DY778CurrentAccountID()] || !DY778ListClearOwnProfile(weakOwner, account, NULL)) { DY778Toast(@"账号或页面已变化，请重新操作"); return; }
        [self startKind:kind user:user owner:weakOwner];
    });
}
@end

@interface DY778ListClearSettingsViewController : UITableViewController
@end
@implementation DY778ListClearSettingsViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"列表清理"; self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 72;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension; self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 20, 0, 20);
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 6;
    if (self.navigationController.viewControllers.firstObject == self)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:DY778PreferencesChangedNotification object:nil]; [self refresh];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)close { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
- (void)refresh { DY778StyleController(self); self.tableView.backgroundColor = DY778Background(); [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : 3; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"长按清理" : @"支持的列表"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"开启后，在“我”页长按“推荐”“收藏”或“喜欢”标签，确认后留在当前页面处理。顶部提示显示进度，可点“停止”结束后续操作。普通点击仍保持原来的用法。";
    return @"这会实际取消当前账号的推荐、收藏或喜欢，不会删除作品，无法一键撤销。仅处理抖音本次返回且可取消的作品；失效、不可见内容及其他收藏分类可能需要手动处理。\n\n请停留在本人主页并保持抖音在前台；离开主页、切换账号、退到后台或关闭开关会停止后续操作。已发出的请求可能继续完成，请以刷新后的列表为准。频繁操作可能受到抖音限制；遇到异常会停止，不会自动反复重试。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = DY778CardBackground(); cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12]; cell.detailTextLabel.textColor = UIColor.secondaryLabelColor; cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (path.section == 0) {
        cell.textLabel.text = @"长按清空列表"; cell.detailTextLabel.text = @"仅在自己的主页生效，每次都需确认";
        cell.imageView.image = DY778MenuIcon(@"hand.tap"); cell.imageView.tintColor = DY778Accent();
        UISwitch *toggle = [UISwitch new]; toggle.on = DY778Bool(DY778ListClearEnabledKey); toggle.onTintColor = DY778Accent();
        toggle.accessibilityLabel = cell.textLabel.text; [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else {
        cell.textLabel.text = @[@"取消推荐", @"取消收藏作品", @"取消喜欢"][path.row];
        cell.detailTextLabel.text = @[@"移除自己对作品的推荐记录", @"不涉及音乐、地点等其他收藏分类", @"取消自己给作品点过的赞"][path.row];
        cell.imageView.image = DY778MenuIcon(@[@"arrowshape.turn.up.right", @"bookmark", @"heart"][path.row]); cell.imageView.tintColor = DY778Accent();
    }
    return cell;
}
- (void)toggle:(UISwitch *)toggle { DY778Set(DY778ListClearEnabledKey, @(toggle.on)); }
@end

static void (*DY778ListClearOriginalRefresh)(id, SEL, id);
static void (*DY778ListClearOriginalTitle)(id, SEL, id, UIControlState);
static void (*DY778ListClearOriginalReload)(id, SEL);
static void DY778ListClearAttach(id cell) {
    if (![cell isKindOfClass:UIView.class]) return;
    if (objc_getAssociatedObject(cell, &DY778ListClearGestureKey)) return;
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:DY778ListClearJob.shared action:@selector(longPress:)];
    gesture.minimumPressDuration = .65; gesture.allowableMovement = 12; gesture.cancelsTouchesInView = NO; gesture.delegate = DY778ListClearJob.shared;
    [(UIView *)cell addGestureRecognizer:gesture]; objc_setAssociatedObject(cell, &DY778ListClearGestureKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void DY778ListClearRefresh(id cell, SEL command, id config) {
    DY778ListClearOriginalRefresh(cell, command, config);
    DY778ListClearAttach(cell);
}
static void DY778ListClearTitle(id item, SEL command, id title, UIControlState state) {
    DY778ListClearOriginalTitle(item, command, title, state);
    DY778ListClearAttach(item);
}
static void DY778ListClearReload(id segment, SEL command) {
    DY778ListClearOriginalReload(segment, command);
    NSArray *items = DY778Read(segment, @"itemViews");
    if (![items isKindOfClass:NSArray.class] || items.count > 64) return;
    for (id item in items) if (DY778ListClearHostClass(item, @"AWERLSegmentItemView")) DY778ListClearAttach(item);
}
static BOOL DY778ListClearInstallNetwork(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getClassMethod(cls, selector); if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 6 || signature.methodReturnType[0] != '@' ||
        [signature getArgumentTypeAtIndex:2][0] != '@' || [signature getArgumentTypeAtIndex:3][0] != '@' ||
        [signature getArgumentTypeAtIndex:4][0] != '#' || [signature getArgumentTypeAtIndex:5][0] != '@') return NO;
    return DY778Hook(object_getClass(cls), selector, replacement, original);
}
void DY778InstallListClear(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallListClear(); }); return; }
    (void)DY778ListClearJob.shared;
    Class service = NSClassFromString(@"AWENetworkService");
    if (!DY778ListClearGetReady)
        DY778ListClearGetReady = DY778ListClearInstallNetwork(service, NSSelectorFromString(@"getWithURLString:params:modelClass:completion:"), (IMP)DY778ListClearGet, (IMP *)&DY778ListClearOriginalGet);
    if (!DY778ListClearPostReady)
        DY778ListClearPostReady = DY778ListClearInstallNetwork(service, NSSelectorFromString(@"postWithURLString:params:modelClass:completion:"), (IMP)DY778ListClearPost, (IMP *)&DY778ListClearOriginalPost);
    if (!DY778ListClearCellReady) {
        Class cellClass = NSClassFromString(@"AWEProfileBaseHeaderSegmentCell"); SEL refresh = NSSelectorFromString(@"refreshWithConfig:");
        Method method = class_getInstanceMethod(cellClass, refresh);
        if (method) {
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if (signature.numberOfArguments == 3 && signature.methodReturnType[0] == 'v' && [signature getArgumentTypeAtIndex:2][0] == '@')
                DY778ListClearCellReady = DY778Hook(cellClass, refresh, (IMP)DY778ListClearRefresh, (IMP *)&DY778ListClearOriginalRefresh);
        }
    }
    if (!DY778ListClearLegacyReady) {
        Class legacyClass = NSClassFromString(@"AWERLSegmentItemView"); SEL titleSelector = @selector(setTitle:forState:);
        Method titleMethod = class_getInstanceMethod(legacyClass, titleSelector);
        if (titleMethod) {
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(titleMethod)];
            if (signature.numberOfArguments == 4 && signature.methodReturnType[0] == 'v' &&
                [signature getArgumentTypeAtIndex:2][0] == '@' && [signature getArgumentTypeAtIndex:3][0] == 'Q')
                DY778ListClearLegacyReady = DY778Hook(legacyClass, titleSelector, (IMP)DY778ListClearTitle, (IMP *)&DY778ListClearOriginalTitle);
        }
    }
    if (!DY778ListClearReloadReady) {
        Class segmentClass = NSClassFromString(@"AWERLSegmentView"); SEL reload = NSSelectorFromString(@"__reloadData");
        Method method = class_getInstanceMethod(segmentClass, reload);
        if (method) {
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if (signature.numberOfArguments == 2 && signature.methodReturnType[0] == 'v')
                DY778ListClearReloadReady = DY778Hook(segmentClass, reload, (IMP)DY778ListClearReload, (IMP *)&DY778ListClearOriginalReload);
        }
    }
    DY778RecordHook(@"列表清理 · 主页长按", DY778ListClearCellReady);
    DY778RecordHook(@"列表清理 · 另一主页布局", DY778ListClearLegacyReady);
    DY778RecordHook(@"列表清理 · 主标签刷新", DY778ListClearReloadReady);
    DY778RecordHook(@"列表清理 · 喜欢与收藏回执", DY778ListClearGetReady);
    DY778RecordHook(@"列表清理 · 推荐回执", DY778ListClearPostReady);
}
UIViewController *DY778ListClearSettingsController(void) { return [DY778ListClearSettingsViewController new]; }
void DY778ResetListClear(void) {
    DY778Set(DY778ListClearEnabledKey, @NO);
    [DY778ListClearJob.shared stop:@"已恢复默认设置，后续操作已停止"];
}
