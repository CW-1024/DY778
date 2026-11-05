#import "DY778RadarNetwork.h"
@interface DY778RadarRequest : NSObject
@property(nonatomic, copy) NSString *url;
@property(nonatomic, copy) NSDictionary *params;
@property(nonatomic, copy) NSString *owner;
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) DY778RadarReply completion;
@property(nonatomic, strong) id task;
@property(nonatomic, copy) DY778RadarStartOperation start;
@property(nonatomic, copy) dispatch_block_t cancellation;
@property(nonatomic, strong) NSTimer *deadline;
@property(nonatomic) BOOL finished;
@end
@implementation DY778RadarRequest
@end
@interface DY778RadarNetwork ()
@property(nonatomic, strong) NSMutableArray<DY778RadarRequest *> *queue;
@property(nonatomic, strong) DY778RadarRequest *active;
@property(nonatomic, strong) NSTimer *pumpTimer;
@property(nonatomic) NSTimeInterval lastStarted;
@end
NSString *DY778RadarCurrentAccount(void) {
    id service = DY778RadarCall(NSClassFromString(@"AWEUserService"), @"sharedService", @[]);
    NSString *uid = DY778RadarString(DY778RadarCall(service, @"userID", @[]));
    if (!DY778RadarIdentifier(uid) || [uid isEqual:@"0"]) return @"";
    return uid;
}
NSString *DY778RadarDiagnosticText(NSError *error) {
    // 不含账号 ID、请求参数、Cookie 或响应体。
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    Class database = NSClassFromString(@"AWEIMUserDBManager");
    Class search = NSClassFromString(@"AWESearchUserManager");
    SEL local = NSSelectorFromString(@"localContactListWithReadScene:completion:");
    SEL query = NSSelectorFromString(@"fetchUsersWithKeyword:cursor:isPullToRefresh:completion:");
    return [NSString stringWithFormat:@"特别关注 %@\n抖音 %@ (%@)\n阶段：%@\n错误：%@ / %ld\n联系人入口：%@ / 异步 %@\n用户搜索入口：%@",
        DY778RadarVersion, DY778RadarString(info[@"CFBundleShortVersionString"]), DY778RadarString(info[@"CFBundleVersion"]),
        DY778RadarString(error.userInfo[@"DY778RadarEndpoint"]), error.domain, (long)error.code,
        database ? @"存在" : @"缺失", [database instancesRespondToSelector:local] ? @"存在" : @"缺失",
        [search instancesRespondToSelector:query] ? @"存在" : @"缺失"];
}
@implementation DY778RadarNetwork
+ (instancetype)shared {
    static DY778RadarNetwork *network; static dispatch_once_t once;
    dispatch_once(&once, ^{ network = [self new]; }); return network;
}
- (instancetype)init {
    if ((self = [super init])) {
        _queue = [NSMutableArray array];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cancelAll) name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}
- (void)get:(NSString *)url parameters:(NSDictionary *)parameters owner:(NSString *)owner completion:(DY778RadarReply)completion {
    DY778RadarRequest *r = [DY778RadarRequest new]; r.url = url; r.params = parameters; r.owner = owner; r.completion = completion;
    [self enqueue:r];
}
- (void)perform:(NSString *)stage owner:(NSString *)owner start:(DY778RadarStartOperation)start completion:(DY778RadarReply)completion {
    DY778RadarRequest *r = [DY778RadarRequest new]; r.url = stage; r.owner = owner; r.start = start; r.completion = completion;
    [self enqueue:r];
}
- (void)cancelRequest:(DY778RadarRequest *)request {
    dispatch_block_t cancel = request.cancellation; request.cancellation = nil;
    if (cancel) cancel();
    DY778RadarCall(request.task, @"cancel", @[]);
}
- (void)enqueue:(DY778RadarRequest *)request {
    NSAssert(NSThread.isMainThread, @"Network broker is confined to main thread");
    request.account = DY778RadarCurrentAccount();
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || !request.account.length) {
        request.completion(nil, DY778RadarError(401, @"请保持抖音在前台，并先登录账号。")); return;
    }
    [self.queue addObject:request]; [self pump];
}
- (void)pump {
    if (self.active || self.pumpTimer || !self.queue.count) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { [self cancelAll]; return; }
    NSTimeInterval wait = MAX(0, self.lastStarted + 2.0 - NSProcessInfo.processInfo.systemUptime);
    __weak typeof(self) weakSelf = self;
    self.pumpTimer = [NSTimer timerWithTimeInterval:MAX(wait, 0.01) repeats:NO block:^(NSTimer *timer) {
        weakSelf.pumpTimer = nil; [weakSelf beginNext];
    }];
    self.pumpTimer.tolerance = 0.15;
    [NSRunLoop.mainRunLoop addTimer:self.pumpTimer forMode:NSRunLoopCommonModes];
}
- (void)beginNext {
    if (self.active || !self.queue.count) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { [self cancelAll]; return; }
    DY778RadarRequest *r = self.queue.firstObject; [self.queue removeObjectAtIndex:0]; self.active = r;
    if (![r.account isEqual:DY778RadarCurrentAccount()]) { [self finish:r value:nil error:DY778RadarError(-999, @"账号已切换，请重新操作。")]; return; }
    self.lastStarted = NSProcessInfo.processInfo.systemUptime;
    __weak typeof(self) weakSelf = self; __weak DY778RadarRequest *weakRequest = r;
    r.deadline = [NSTimer timerWithTimeInterval:15 repeats:NO block:^(NSTimer *timer) {
        DY778RadarRequest *request = weakRequest;
        if (request && !request.finished) {
            [weakSelf cancelRequest:request];
            [weakSelf finish:request value:nil error:DY778RadarError(408, @"请求超时，稍后会自动重试。")];
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:r.deadline forMode:NSRunLoopCommonModes];
    if (r.start) {
        DY778RadarReply reply = ^(id value, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                DY778RadarRequest *request = weakRequest;
                if (request && !request.finished) [weakSelf finish:request value:value error:error];
            });
        };
        DY778RadarIsCurrent current = ^BOOL {
            DY778RadarRequest *request = weakRequest;
            return request && !request.finished && UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
                [request.account isEqual:DY778RadarCurrentAccount()];
        };
        @try { r.cancellation = r.start(reply, current); }
        @catch (__unused NSException *exception) { reply(nil, DY778RadarError(502, @"抖音数据服务未能完成操作，请重试或复制诊断。")); }
        r.start = nil;
        return;
    }
    // 原始 AWENetwork 完成回调传两个对象；两种 error 顺序都接受。
    id callback = [^(id first, id second) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778RadarRequest *request = weakRequest; if (!request || request.finished) return;
            NSError *error = [first isKindOfClass:NSError.class] ? first : [second isKindOfClass:NSError.class] ? second : nil;
            id value = first && first != NSNull.null && ![first isKindOfClass:NSError.class] ? first : second;
            if ([value isKindOfClass:NSError.class] || value == NSNull.null) value = nil;
            for (id envelope in @[value ?: @{}, DY778RadarRead(value, @"data") ?: @{}]) {
                id rawStatus = DY778RadarFirst(envelope, @[@"status_code", @"statusCode"]);
                NSNumber *status = [rawStatus isKindOfClass:NSNumber.class] ? rawStatus : DY778RadarCount(rawStatus);
                if (!error && rawStatus && !status) error = DY778RadarError(502, @"响应状态不可识别，本次结果已忽略。");
                if (!error && status.longLongValue != 0) error = DY778RadarError(status.integerValue,
                    DY778RadarString(DY778RadarFirst(envelope, @[@"status_msg", @"statusMsg"])).length ? DY778RadarString(DY778RadarFirst(envelope, @[@"status_msg", @"statusMsg"])) : @"抖音暂时未返回数据。");
            }
            if (!error && !value) error = DY778RadarError(502, @"请求返回了空数据。");
            [weakSelf finish:request value:value error:error];
        });
    } copy];
    // 宿主 GET 提供登录上下文与公共参数；TTNet 需要绝对 URL。
    NSURL *url = [NSURL URLWithString:r.url];
    if (![url.scheme isEqualToString:@"https"] || !url.host.length) {
        [self finish:r value:nil error:DY778RadarError(400, @"请求地址不完整，请重新打开页面。")]; return;
    }
    Class service = NSClassFromString(@"AWENetworkService");
    if (DY778RadarHasMethod(service, @"getWithURLString:params:timeout:completion:", "@", "@@d@")) {
        r.task = DY778RadarCall(service, @"getWithURLString:params:timeout:completion:", @[r.url, r.params, @12.0, callback]);
    } else if (DY778RadarHasMethod(service, @"getWithURLString:params:completion:", "@", "@@@")) {
        r.task = DY778RadarCall(service, @"getWithURLString:params:completion:", @[r.url, r.params, callback]);
    } else {
        [self finish:r value:nil error:DY778RadarError(503, @"当前抖音版本的网络入口不可用。")]; return;
    }
    if (r.finished) { DY778RadarCall(r.task, @"cancel", @[]); r.task = nil; }
    // 任务为 nil 时仍可能同步完成；缺失回调交给看门狗处理。
}
- (void)finish:(DY778RadarRequest *)request value:(id)value error:(NSError *)error {
    if (request.finished) return;
    request.finished = YES; [request.deadline invalidate]; request.deadline = nil; request.task = nil;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || ![request.account isEqual:DY778RadarCurrentAccount()]) {
        value = nil; error = DY778RadarError(-999, @"已暂停请求。");
    }
    if (error) {
        NSMutableDictionary *info = [error.userInfo mutableCopy];
        NSString *message = error.localizedDescription;
        if ([error.domain isEqual:NSURLErrorDomain]) {
            if (error.code == NSURLErrorCancelled) message = @"请求已暂停。";
            else if (error.code == NSURLErrorTimedOut) message = @"连接超时，请稍后重试。";
            else if (error.code == NSURLErrorNotConnectedToInternet) message = @"网络未连接，请检查抖音联网后重试。";
        }
        // 宿主业务错误（如 code 5）不一定是网络错误。
        if (![error.domain isEqual:@"DY778Radar"]) {
            info[NSUnderlyingErrorKey] = error;
            message = [NSString stringWithFormat:@"%@（%@ / %ld）", message, error.domain, (long)error.code];
        }
        info[NSLocalizedDescriptionKey] = message;
        info[@"DY778RadarEndpoint"] = [request.url hasPrefix:@"https://"] ? ([NSURL URLWithString:request.url].path ?: @"") : request.url;
        error = [NSError errorWithDomain:error.domain code:error.code userInfo:info];
    }
    request.cancellation = nil; request.start = nil;
    DY778RadarReply completion = request.completion; request.completion = nil;
    if (self.active == request) self.active = nil;
    if (completion) completion(value, error);
    [self pump];
}
- (void)cancelOwner:(NSString *)owner {
    NSMutableArray *cancelled = [NSMutableArray array];
    for (DY778RadarRequest *r in self.queue.copy) if ([r.owner isEqual:owner]) { [self.queue removeObject:r]; [cancelled addObject:r]; }
    if ([self.active.owner isEqual:owner]) { [self cancelRequest:self.active]; [cancelled addObject:self.active]; }
    for (DY778RadarRequest *r in cancelled) [self finish:r value:nil error:DY778RadarError(-999, @"请求已取消。")];
    if (!self.queue.count) { [self.pumpTimer invalidate]; self.pumpTimer = nil; }
}
- (void)cancelAll {
    [self.pumpTimer invalidate]; self.pumpTimer = nil;
    NSArray *queued = self.queue.copy; [self.queue removeAllObjects];
    DY778RadarRequest *active = self.active; [self cancelRequest:active];
    if (active) [self finish:active value:nil error:DY778RadarError(-999, @"已暂停请求。")];
    for (DY778RadarRequest *r in queued) [self finish:r value:nil error:DY778RadarError(-999, @"已暂停请求。")];
}
@end
