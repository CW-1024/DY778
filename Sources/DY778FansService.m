#import "DY778FansService.h"
#import "DY778FansPolicy.h"
#import "DY778FansWeb.h"
#import "DY778FansPrivate.h"
#import <UIKit/UIKit.h>

static NSString *DY778FansDiagnosticSnapshot;
NSString *DY778FansLastDiagnostic(void) { return DY778FansDiagnosticSnapshot ?: @"尚无查询记录"; }

static NSString *DY778FansAPIOrigin(void) {
    Class provider = NSClassFromString(@"NetworkProviderDomain");
    for (NSString *selector in @[@"apiDomain", @"apiHost"]) {
        id raw = DY778FansCall(provider, selector, @[]);
        NSString *text = [raw isKindOfClass:NSURL.class] ? [raw absoluteString] : DY778FansString(raw);
        if (!text.length) continue;
        if (![text containsString:@"://"]) text = [@"https://" stringByAppendingString:text];
        NSURLComponents *parts = [NSURLComponents componentsWithString:text];
        if (![parts.scheme.lowercaseString isEqual:@"https"] || !parts.host.length || parts.user.length || parts.password.length) continue;
        parts.path = @""; parts.query = nil; parts.fragment = nil; return parts.string;
    }
    return DY778FansPrivate(DY778FansAppOrigin);
}

static NSMutableDictionary *DY778FansProfiles;
static NSString *DY778FansProfilesAccount;
static NSMutableDictionary *DY778FansProfileStore(void) {
    NSString *account = DY778FansAccount() ?: @"";
    if (!DY778FansProfiles || ![account isEqual:DY778FansProfilesAccount]) { DY778FansProfiles = [NSMutableDictionary dictionary]; DY778FansProfilesAccount = account; }
    return DY778FansProfiles;
}
static NSDictionary *DY778FansCachedProfile(NSDictionary *person) {
    NSDictionary *cached = DY778FansProfileStore()[DY778FansString(person[@"uid"])] ?: DY778FansProfileStore()[DY778FansString(person[@"secUID"])];
    return cached && NSDate.date.timeIntervalSince1970 - [cached[@"time"] doubleValue] < 120 && DY778FansSamePerson(person,cached[@"person"]) ? cached[@"person"] : nil;
}
static void DY778FansCacheProfile(NSDictionary *person) {
    NSMutableDictionary *store = DY778FansProfileStore(); if (store.count >= 160) [store removeAllObjects];
    NSDictionary *record = @{@"person":person,@"time":@(NSDate.date.timeIntervalSince1970)};
    if (DY778FansUID(person[@"uid"])) store[person[@"uid"]] = record;
    if (DY778FansSecUID(person[@"secUID"])) store[person[@"secUID"]] = record;
}

@interface DY778FansRedirector : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, copy) DY778FansReply completion;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic) NSUInteger redirects;
- (void)open:(NSURL *)url completion:(DY778FansReply)completion;
- (void)cancel;
@end
@implementation DY778FansRedirector
- (void)open:(NSURL *)url completion:(DY778FansReply)completion {
    self.completion = completion;
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 18;
    config.HTTPCookieStorage = nil; config.URLCache = nil;
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148" forHTTPHeaderField:@"User-Agent"];
    self.task = [self.session dataTaskWithRequest:request]; [self.task resume];
}
- (void)finish:(NSURL *)url error:(NSError *)error {
    DY778FansReply callback = self.completion; self.completion = nil;
    [self.session invalidateAndCancel]; self.session = nil; self.task = nil;
    if (callback) callback(url, error);
}
- (void)cancel { self.completion = nil; [self.session invalidateAndCancel]; self.session = nil; self.task = nil; }
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if (!DY778FansShareURL(request.URL) || ++self.redirects > 8) {
        completionHandler(nil); [self finish:nil error:DY778FansError(400, @"分享链接跳转异常，请重新复制链接。")]; return;
    }
    NSDictionary *parsed = DY778FansParseInput(request.URL.absoluteString, DY778FansInputAutomatic, nil);
    if (parsed && ![parsed[@"kind"] isEqual:@"url"]) { completionHandler(nil); [self finish:request.URL error:nil]; return; }
    completionHandler(request);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    completionHandler(NSURLSessionResponseCancel);
    NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
    if (code >= 400) [self finish:nil error:DY778FansError(code, @"分享链接暂不可用，请检查链接后重试。")];
    else [self finish:response.URL error:nil];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (self.completion) [self finish:nil error:error ?: DY778FansError(502, @"无法展开分享链接。")];
}
@end

@interface DY778FansService ()
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) DY778FansReply terminal;
@property(nonatomic, strong) id task;
@property(nonatomic, strong) id native;
@property(nonatomic, strong) id search;
@property(nonatomic, strong) NSMutableDictionary *searchCandidates;
@property(nonatomic, strong) NSTimer *deadline;
@property(nonatomic, strong) DY778FansRedirector *redirector;
@property(nonatomic, strong) DY778FansWebClient *web;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger operation;
@end

@implementation DY778FansService
- (instancetype)init {
    if ((self = [super init])) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];
    return self;
}
- (void)dealloc { [self.web cancel]; [self.deadline invalidate]; [self.redirector cancel]; DY778FansCall(self.task, @"cancel", @[]); }
- (void)background { if (self.terminal) [self finish:nil error:DY778FansError(-999, @"查询已暂停，返回后可重新查询。")]; }
- (void)cancel {
    self.generation++; self.operation++; [self.web cancel]; self.web = nil;
    [self.deadline invalidate]; self.deadline = nil; [self.redirector cancel]; self.redirector = nil;
    DY778FansCall(self.task, @"cancel", @[]); self.task = nil;
    DY778FansCall(DY778FansRead(self.search, @"task"), @"cancel", @[]); self.search = nil; self.searchCandidates = nil;
    id pool = DY778FansRead(self.native, @"requestPool");
    if ([pool isKindOfClass:NSDictionary.class]) for (id request in [pool allValues]) { DY778FansCall(request, @"cancel", @[]); DY778FansCall(DY778FansRead(request, @"task"), @"cancel", @[]); }
    self.native = nil; self.terminal = nil;
}
- (void)finish:(id)value error:(NSError *)error {
    if ([value isKindOfClass:DY778FansResult.class]) DY778FansDiagnosticSnapshot = [((DY778FansResult *)value).diagnostic copy];
    else if (error) DY778FansDiagnosticSnapshot = [NSString stringWithFormat:@"%@ / %ld%@", error.domain, (long)error.code, error.userInfo[@"DY778FansDiagnostic"] ? [@"; " stringByAppendingString:error.userInfo[@"DY778FansDiagnostic"]] : @""];
    DY778FansReply completion = self.terminal;
    [self cancel];
    if (completion) completion(value, error);
}
- (BOOL)prepare:(DY778FansReply)completion {
    [self cancel]; self.terminal = completion; self.account = DY778FansAccount();
    if (!DY778FansEnabled(@"DY778FansC.Enabled")) { [self finish:nil error:DY778FansError(403, @"请先在 DY778 设置中开启星牌查询。")]; return NO; }
    if (!DY778FansUID(self.account)) { [self finish:nil error:DY778FansError(401, @"请先登录抖音，再进行查询。")]; return NO; }
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { [self background]; return NO; }
    return YES;
}
- (void)stage:(NSString *)name start:(void (^)(DY778FansReply))start reply:(DY778FansReply)reply {
    NSUInteger generation = self.generation, operation = ++self.operation;
    [self.deadline invalidate]; self.deadline = nil;
    if (self.progress) self.progress(name);
    __weak typeof(self) weakSelf = self;
    DY778FansReply receive = ^(id value, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778FansService *self = weakSelf;
            if (!self || !DY778FansCallbackCurrent(generation, self.generation, operation, self.operation, self.terminal != nil)) return;
            self.operation++; [self.deadline invalidate]; self.deadline = nil; self.task = nil; self.native = nil;
            if (![self.account isEqual:DY778FansAccount()] || !DY778FansEnabled(@"DY778FansC.Enabled")) { [self finish:nil error:DY778FansError(-999, @"账号或设置已变化，请重新查询。")]; return; }
            reply(value, error);
        });
    };
    self.deadline = [NSTimer scheduledTimerWithTimeInterval:18 repeats:NO block:^(NSTimer *timer) {
        DY778FansService *self = weakSelf;
        DY778FansCall(self.task, @"cancel", @[]); [self.redirector cancel]; [self.web cancel];
        receive(nil, DY778FansError(408, @"请求超时，请稍后重试。"));
    }];
    @try { start(receive); }
    @catch (__unused NSException *exception) { receive(nil, DY778FansError(503, @"当前版本的数据服务暂不可用。")); }
}
- (void)get:(NSString *)path params:(NSDictionary *)params reply:(DY778FansReply)reply {
    [self getURL:[DY778FansAPIOrigin() stringByAppendingString:path] params:params progress:@"正在读取用户资料…" reply:reply];
}
- (void)getURL:(NSString *)url params:(NSDictionary *)params progress:(NSString *)progress reply:(DY778FansReply)reply {
    [self stage:progress start:^(DY778FansReply receive) {
        Class network = NSClassFromString(@"AWENetworkService");
        if (!DY778FansHas(network, @"getWithURLString:params:timeout:completion:", "@", "@@d@")) { receive(nil, DY778FansError(503, @"当前抖音版本不支持资料查询。")); return; }
        void (^callback)(id, NSError *) = ^(id value, NSError *error) {
            if (!error) {
                NSNumber *status = DY778FansInteger(DY778FansFirst(value, @[@"status_code", @"statusCode"]));
                if (status.longLongValue != 0) error = DY778FansError(status.integerValue, @"抖音暂未返回可用资料，请稍后重试。");
                if (!value || value == NSNull.null) error = DY778FansError(502, @"抖音返回了空数据。");
            }
            receive(value, error);
        };
        self.task = DY778FansCall(network, @"getWithURLString:params:timeout:completion:", @[url, params, @14.0, callback]);
    } reply:reply];
}
- (void)resolveParsed:(NSDictionary *)parsed completion:(DY778FansReply)completion {
    NSString *kind = parsed[@"kind"], *value = parsed[@"value"];
    if ([kind isEqual:@"url"]) {
        [self stage:@"正在展开分享链接…" start:^(DY778FansReply receive) {
            self.redirector = [DY778FansRedirector new]; [self.redirector open:[NSURL URLWithString:value] completion:receive];
        } reply:^(NSURL *url, NSError *error) {
            self.redirector = nil;
            NSDictionary *next = url ? DY778FansParseInput(url.absoluteString, DY778FansInputAutomatic, nil) : nil;
            if (error || !next || [next[@"kind"] isEqual:@"url"]) { completion(nil, error ?: DY778FansError(404, @"链接中没有可识别的作者或作品，请重新复制分享链接。")); return; }
            [self resolveParsed:next completion:completion];
        }]; return;
    }
    if ([kind isEqual:@"handle"]) {
        self.searchCandidates = [NSMutableDictionary dictionary];
        [self web:@"lookup" params:@{@"unique_id":value} reply:^(id response,NSError *error) {
            if (!error && [self acceptSearch:response handle:value completion:completion]) return;
            self.search = [NSClassFromString(@"AWESearchUserManager") new];
            if (!DY778FansHas(self.search, @"fetchUsersWithKeyword:cursor:isPullToRefresh:completion:", "v", "@@B@")) { [self searchWeb:value route:0 cursor:@0 page:0 completion:completion]; return; }
            DY778FansSet(self.search,@"count",@30); DY778FansSet(self.search,@"cursor",@0); DY778FansSet(self.search,@"searchSource",@"normal_search"); DY778FansSet(self.search,@"initialSearchSource",@"normal_search");
            [self searchHandle:value cursor:@0 page:0 completion:completion];
        }]; return;
    }
    if ([kind isEqual:@"video"]) {
        [self get:DY778FansPrivate(DY778FansVideoPath) params:@{@"aweme_id": value} reply:^(id response, NSError *error) {
            id video = DY778FansFirst(response, @[@"aweme_detail", @"awemeDetail"]);
            NSDictionary *person = DY778FansPerson(DY778FansRead(video, @"author"));
            completion(person, error ?: (person ? nil : DY778FansError(404, @"作品不可用或未返回作者信息。")));
        }]; return;
    }
    NSDictionary *expected = @{[kind isEqual:@"uid"] ? @"uid" : @"secUID":value};
    [self loadAnchor:expected completion:completion];
}
- (BOOL)acceptSearch:(id)value handle:(NSString *)handle completion:(DY778FansReply)completion {
    NSMutableDictionary *matches = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in DY778FansSearchPeople(value)) {
        NSDictionary *person = entry[@"person"]; NSString *key = [person[@"uid"] length] ? person[@"uid"] : person[@"secUID"];
        if (!key.length) continue;
        if (self.searchCandidates.count < 60 || self.searchCandidates[key]) self.searchCandidates[key] = person;
        if (DY778FansHandleMatches(entry[@"raw"],handle)) matches[key] = person;
    }
    if (matches.count == 1) { [self loadAnchor:matches.allValues.firstObject completion:completion]; return YES; }
    if (matches.count > 1) { completion(nil,[NSError errorWithDomain:@"DY778Fans" code:300 userInfo:@{NSLocalizedDescriptionKey:@"请选择要查询的账号。",@"DY778FansCandidates":matches.allValues}]); return YES; }
    return NO;
}
- (void)finishSearch:(DY778FansReply)completion error:(NSError *)error {
    if (self.searchCandidates.count) {
        NSArray *people = [self.searchCandidates.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) { return [DY778FansPersonName(a) compare:DY778FansPersonName(b)]; }];
        completion(nil,[NSError errorWithDomain:@"DY778Fans" code:300 userInfo:@{NSLocalizedDescriptionKey:@"请选择对应账号，确认头像与抖音号后继续。",@"DY778FansCandidates":people}]);
    } else completion(nil,error ?: DY778FansError(404,@"未匹配到该抖音号，请核对后重试；数字 UID 请使用 UID 模式。"));
}
- (void)searchHandle:(NSString *)handle cursor:(id)cursor page:(NSUInteger)page completion:(DY778FansReply)completion {
    [self stage:@"正在匹配抖音号…" start:^(DY778FansReply receive) {
        void (^callback)(id,NSError *) = ^(id users,NSError *error) { receive(users,error); };
        DY778FansCall(self.search,@"fetchUsersWithKeyword:cursor:isPullToRefresh:completion:",@[handle,cursor,@(page == 0),callback]);
    } reply:^(id value,NSError *error) {
        if (!error && [self acceptSearch:value handle:handle completion:completion]) return;
        id data = DY778FansRead(value,@"data");
        id next = DY778FansRead(value,@"cursor") ?: DY778FansRead(data,@"cursor") ?: DY778FansRead(self.search,@"cursor");
        id more = DY778FansRead(value,@"has_more") ?: DY778FansRead(data,@"has_more") ?: DY778FansRead(self.search,@"hasMore");
        if (!error && page < 2 && [more boolValue] && [DY778FansInteger(next) longLongValue] > [DY778FansInteger(cursor) longLongValue]) {
            [self searchHandle:handle cursor:next page:page + 1 completion:completion]; return;
        }
        [self searchWeb:handle route:0 cursor:@0 page:0 completion:completion];
    }];
}
- (void)searchWeb:(NSString *)handle route:(NSUInteger)route cursor:(NSNumber *)cursor page:(NSUInteger)page completion:(DY778FansReply)completion {
    if (route >= 2) { [self finishSearch:completion error:nil]; return; }
    NSDictionary *params = @{@"keyword":handle,@"search_id":[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""],@"search_channel":route == 0 ? @"aweme_user" : @"aweme_user_web",@"search_type":@"1",@"offset":cursor.stringValue,@"count":@"20",@"sort_type":@"0",@"publish_time":@"0",@"search_source":@"normal_search",@"query_correct_type":@"1",@"is_filter_search":@"0",@"pc_search_type":@"1",@"from_group_id":@"",@"need_filter_settings":@"1",@"list_type":@"single"};
    [self web:route == 0 ? @"search" : @"discover" params:params reply:^(id value,NSError *error) {
        if (!error && [self acceptSearch:value handle:handle completion:completion]) return;
        if (error.code == 401 || error.code == 403 || error.code == 429) { [self finishSearch:completion error:error]; return; }
        id data = DY778FansRead(value,@"data"); NSNumber *next = DY778FansInteger(DY778FansRead(value,@"cursor") ?: DY778FansRead(data,@"cursor"));
        BOOL more = [(DY778FansRead(value,@"has_more") ?: DY778FansRead(data,@"has_more")) boolValue];
        if (!error && page < 2 && more && next.longLongValue > cursor.longLongValue) { [self searchWeb:handle route:route cursor:next page:page+1 completion:completion]; return; }
        if (route == 1) { [self finishSearch:completion error:error]; return; }
        [self searchWeb:handle route:route+1 cursor:@0 page:0 completion:completion];
    }];
}
- (void)resolveInput:(NSString *)input mode:(DY778FansInputMode)mode completion:(DY778FansReply)completion {
    if (![self prepare:completion]) return;
    NSError *error; NSDictionary *parsed = DY778FansParseInput(input, mode, &error);
    if (!parsed) { [self finish:nil error:error]; return; }
    [self resolveParsed:parsed completion:^(id person,NSError *failure) { if (failure) [self finish:nil error:failure]; else [self loadAnchor:person completion:^(id complete,NSError *error) { [self finish:complete error:error]; }]; }];
}
- (void)queryInput:(NSString *)input mode:(DY778FansInputMode)mode target:(NSDictionary *)target anchor:(NSDictionary *)anchor completion:(void (^)(DY778FansResult *, NSError *))completion {
    if (![self prepare:^(id value, NSError *error) { completion(value, error); }]) return;
    DY778FansReply resolved = ^(NSDictionary *person, NSError *error) {
        if (error || !person) { [self finish:nil error:error ?: DY778FansError(404, @"未找到作者。")]; return; }
        if (anchor) {
            [self loadAnchor:anchor completion:^(NSDictionary *resolvedAnchor, NSError *failure) {
                if (failure) { [self finish:nil error:failure]; return; }
                [self fetchLive:person anchor:resolvedAnchor];
            }];
        } else [self fetchLive:person anchor:nil];
    };
    if (target && DY778FansUID(target[@"uid"])) [self loadAnchor:target completion:resolved];
    else {
        NSError *error; NSDictionary *parsed = target && DY778FansSecUID(target[@"secUID"]) ? @{@"kind": @"secUID", @"value": target[@"secUID"]} : DY778FansParseInput(input, mode, &error);
        if (!parsed) { [self finish:nil error:error]; return; }
        [self resolveParsed:parsed completion:^(NSDictionary *person,NSError *failure) { if (failure) resolved(nil,failure); else [self loadAnchor:person completion:resolved]; }];
    }
}
- (void)refreshPerson:(NSDictionary *)person completion:(DY778FansReply)completion {
    if (![self prepare:completion]) return;
    [self loadAnchor:person force:YES completion:^(id value,NSError *error) { [self finish:value error:error]; }];
}
- (void)loadAnchor:(NSDictionary *)anchor completion:(DY778FansReply)completion { [self loadAnchor:anchor force:NO completion:completion]; }
- (void)loadAnchor:(NSDictionary *)anchor force:(BOOL)force completion:(DY778FansReply)completion {
    NSDictionary *cached = force ? nil : DY778FansCachedProfile(anchor); if (cached) { completion(cached,nil); return; }
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (DY778FansUID(anchor[@"uid"])) params[@"user_id"] = anchor[@"uid"];
    if (DY778FansSecUID(anchor[@"secUID"])) params[@"sec_user_id"] = anchor[@"secUID"];
    if (!params.count) { completion(nil,DY778FansError(400,@"账号标识无效，请重新复制主页链接。")); return; }
    DY778FansReply accept = ^(id response,NSError *error) {
        NSDictionary *profile = DY778FansPerson(DY778FansRead(response,@"user") ?: DY778FansRead(DY778FansRead(response,@"data"),@"user") ?: response);
        if (error || !DY778FansSamePerson(anchor,profile)) { completion(nil,error ?: DY778FansError(409,@"返回资料与账号不一致，请重新选择。")); return; }
        NSMutableDictionary *complete = [anchor mutableCopy];
        for (NSString *key in profile) if ((![key isEqual:@"uid"] && ![key isEqual:@"secUID"]) || [profile[key] length]) complete[key] = profile[key];
        DY778FansCacheProfile(complete); completion(complete,nil);
    };
    [self get:DY778FansPrivate(DY778FansNativeProfilePath) params:params reply:^(id response,NSError *error) {
        NSDictionary *profile = DY778FansPerson(DY778FansRead(response,@"user") ?: response);
        if (!error && DY778FansSamePerson(anchor,profile)) { accept(response,nil); return; }
        NSMutableDictionary *webParams = [params mutableCopy]; webParams[@"publish_video_strategy_type"] = @"2";
        [self web:@"profile" params:webParams reply:accept];
    }];
}
- (DY778FansResult *)emptyResult:(NSDictionary *)person anchor:(NSDictionary *)anchor {
    DY778FansResult *result = [DY778FansResult new]; result.person = person; result.anchor = anchor; result.clubs = @[]; result.date = NSDate.date; result.diagnostic = @"query=DY778-1.0-3"; return result;
}
- (BOOL)hasBadge:(DY778FansResult *)result anchor:(NSDictionary *)anchor {
    if (!anchor) return result.clubs.count > 0;
    for (NSDictionary *club in result.clubs) if ([club[@"anchorUID"] isEqual:anchor[@"uid"]] && [club[@"level"] integerValue] > 0) return YES;
    return NO;
}
- (void)merge:(DY778FansResult *)extra into:(DY778FansResult *)result {
    if (!extra || !DY778FansSamePerson(result.person,extra.person)) return;
    if (extra.level) { result.level = extra.level; result.minimum = extra.minimum; result.maximum = extra.maximum; }
    NSMutableDictionary *person = [result.person mutableCopy];
    for (NSString *key in extra.person) if (DY778FansString(extra.person[key]).length) person[key] = extra.person[key];
    result.person = person;
    NSMutableDictionary *clubs = [NSMutableDictionary dictionary];
    for (NSDictionary *club in [result.clubs arrayByAddingObjectsFromArray:extra.clubs ?: @[]]) {
        NSString *key = [club[@"anchorUID"] length] ? club[@"anchorUID"] : [@"name:" stringByAppendingString:club[@"clubName"]]; clubs[key] = club;
    }
    result.clubs = clubs.allValues;
}
- (void)web:(NSString *)route params:(NSDictionary *)params reply:(DY778FansReply)reply {
    BOOL profile = [@[@"lookup",@"profile",@"search",@"discover"] containsObject:route];
    [self stage:profile ? @"正在查找账号资料…" : @"正在查询灯牌资料…" start:^(DY778FansReply receive) {
        self.web = [DY778FansWebClient new]; [self.web get:route params:params completion:receive];
    } reply:reply];
}
- (NSDictionary *)cardParams:(NSDictionary *)person anchor:(NSDictionary *)anchor {
    NSString *room=DY778FansString(anchor[@"roomID"]);
    if (!room.length || !DY778FansUID(room)) room=@"0";
    return @{@"target_uid":person[@"uid"] ?: @"0",@"sec_target_uid":person[@"secUID"] ?: @"",@"anchor_id":anchor[@"uid"] ?: @"0",@"sec_anchor_id":anchor[@"secUID"] ?: @"",@"current_room_id":room};
}
- (void)fetchLive:(NSDictionary *)person anchor:(NSDictionary *)anchor {
    DY778FansResult *result = [self emptyResult:person anchor:anchor];
    if (anchor && DY778FansWebConnected()) {
        [self web:anchor ? @"card" : @"user" params:[self cardParams:person anchor:anchor] reply:^(id response,NSError *error) {
            DY778FansResult *card = !error ? [DY778FansResult fromProfileResponse:response target:person anchor:anchor error:nil] : nil;
            [self merge:card into:result];
            result.diagnostic = [result.diagnostic stringByAppendingFormat:@"; web_card=%@",card ? @"valid" : @"unavailable"];
            if ([self hasBadge:result anchor:anchor]) [self completeBadge:result anchor:anchor];
            else [self nativeUser:person anchor:anchor result:result triedWeb:YES];
        }];
    } else [self nativeUser:person anchor:anchor result:result triedWeb:NO];
}
- (void)nativeUser:(NSDictionary *)person anchor:(NSDictionary *)anchor result:(DY778FansResult *)result triedWeb:(BOOL)triedWeb {
    [self stage:@"正在读取消费等级…" start:^(DY778FansReply receive) {
        self.native = [NSClassFromString(@"HTSLiveUserAPI") new];
        if (!DY778FansHas(self.native,@"fetchUserInfoWithParams:tintTags:finished:","v","@@@")) { receive(nil,DY778FansError(503,@"暂时无法读取资料。")); return; }
        NSMutableDictionary *params = [[self cardParams:person anchor:anchor] mutableCopy];
        [params addEntriesFromDictionary:@{@"room_id":params[@"current_room_id"],@"packed_level":@2,@"with_host_info":@1,@"source":@0,@"request_from":@"",@"target_display_role":@0}];
        void (^callback)(id,NSError *) = ^(id value,NSError *error) { receive(value,error); };
        DY778FansCall(self.native,@"fetchUserInfoWithParams:tintTags:finished:",@[params,@{},callback]);
    } reply:^(id user,NSError *error) {
        DY778FansResult *extra = !error ? [DY778FansResult fromUser:user target:person anchor:anchor error:nil] : nil;
        [self merge:extra into:result]; result.diagnostic = [result.diagnostic stringByAppendingFormat:@"; native_user=%@",extra ? @"valid" : @"unavailable"];
        if (!anchor && self.partialResult && result.level) self.partialResult(result);
        if ([self hasBadge:result anchor:anchor] || (!anchor && result.level)) { [self completeBadge:result anchor:anchor]; return; }
        if (!triedWeb && DY778FansWebConnected()) {
            [self web:anchor ? @"card" : @"user" params:[self cardParams:person anchor:anchor] reply:^(id response,NSError *failure) {
                DY778FansResult *card = !failure ? (anchor ? [DY778FansResult fromProfileResponse:response target:person anchor:anchor error:nil] : [DY778FansResult fromUser:DY778FansRead(response,@"data") target:person error:nil]) : nil;
                [self merge:card into:result];
                if ([self hasBadge:result anchor:anchor] || (!anchor && result.level)) [self completeBadge:result anchor:anchor];
                else [self nativeCard:person anchor:anchor result:result];
            }];
        } else [self nativeCard:person anchor:anchor result:result];
    }];
}
- (void)nativeCard:(NSDictionary *)person anchor:(NSDictionary *)anchor result:(DY778FansResult *)result {
    id request = [NSClassFromString(@"HTSLiveApiRequest") new]; id api = [NSClassFromString(@"HTSLiveApi") new];
    DY778FansSet(request,@"path",@"/user/profile/");
    NSString *url = DY778FansString(DY778FansCall(api,@"urlWithRequest:",request ? @[request] : @[]));
    if (!url.length || ![[NSURL URLWithString:url].path isEqual:DY778FansPrivate(DY778FansCardPath)]) url = [DY778FansPrivate(DY778FansNativeOrigin) stringByAppendingString:DY778FansPrivate(DY778FansCardPath)];
    NSMutableDictionary *params = [[self cardParams:person anchor:anchor] mutableCopy]; [params addEntriesFromDictionary:@{@"packed_level":@2,@"scene":@0,@"request_from":@""}];
    [self getURL:url params:params progress:@"正在查询主播灯牌…" reply:^(id response,NSError *error) {
        DY778FansResult *card = !error ? [DY778FansResult fromProfileResponse:response target:person anchor:anchor error:nil] : nil;
        [self merge:card into:result]; result.diagnostic = [result.diagnostic stringByAppendingFormat:@"; native_card=%@",card ? @"valid" : @"unavailable"];
        if ([self hasBadge:result anchor:anchor] || !anchor || !DY778FansWebConnected()) [self completeBadge:result anchor:anchor];
        else [self members:result anchor:anchor offset:0 page:0 previous:@""];
    }];
}
- (void)members:(DY778FansResult *)result anchor:(NSDictionary *)anchor offset:(NSUInteger)offset page:(NSUInteger)page previous:(NSString *)previous {
    NSDictionary *params = @{@"anchor_id":anchor[@"uid"],@"sec_anchor_id":anchor[@"secUID"] ?: @"",@"source":@"1",@"type":@"1",@"offset":@(offset),@"count":@20};
    [self web:@"members" params:params reply:^(id response,NSError *error) {
        id data = DY778FansRead(response,@"data"); id rows = DY778FansFirst(data,@[@"club_user_list",@"user_list",@"members"]);
        if (error || ![rows isKindOfClass:NSArray.class]) { [self completeBadge:result anchor:anchor]; return; }
        NSMutableArray *fingerprints = [NSMutableArray array]; NSUInteger readable = 0, visited = 0;
        for (id row in rows) {
            if (++visited > 100) break;
            id raw = DY778FansFirst(row,@[@"user_info",@"user"] ) ?: row; NSDictionary *person = DY778FansPerson(raw);
            if (!person) continue; readable++; [fingerprints addObject:person[@"uid"] ?: person[@"secUID"]];
            if (!DY778FansSamePerson(result.person,person)) continue;
            id info = DY778FansFirst(row,@[@"user_fansclub_info",@"user_fans_club_info",@"fans_club"]) ?: DY778FansRead(raw,@"fans_club") ?: row;
            id inner = DY778FansRead(info,@"data"); if ([inner isKindOfClass:NSDictionary.class]) info = inner;
            if (![info isKindOfClass:NSDictionary.class]) continue;
            NSMutableDictionary *badge = [info mutableCopy]; NSString *owner = DY778FansString(DY778FansFirst(info,@[@"anchor_id",@"anchor_uid"]));
            if (DY778FansUID(owner) && ![owner isEqual:anchor[@"uid"]]) continue;
            badge[@"anchor_id"] = anchor[@"uid"];
            if (!DY778FansString(badge[@"club_name"]).length) badge[@"club_name"] = DY778FansString(DY778FansFirst(DY778FansRead(data,@"club_info"),@[@"name",@"club_name"]));
            DY778FansResult *match = [DY778FansResult fromUser:@{@"uid":person[@"uid"],@"secUID":person[@"secUID"],@"fans_club":@{@"data":badge}} target:result.person anchor:anchor error:nil];
            [self merge:match into:result];
            if ([self hasBadge:result anchor:anchor]) { [self completeBadge:result anchor:anchor]; return; }
        }
        NSString *fingerprint = [fingerprints componentsJoinedByString:@"|"];
        id more = DY778FansFirst(data,@[@"has_more",@"hasMore"]); NSNumber *cursor = DY778FansInteger(DY778FansFirst(data,@[@"next_offset",@"offset",@"cursor"]));
        NSUInteger next = cursor ? cursor.unsignedIntegerValue : offset + [rows count];
        if (!readable || ![rows count] || [fingerprint isEqual:previous] || (more && ![more boolValue]) || next <= offset || page >= 2) { [self completeBadge:result anchor:anchor]; return; }
        NSUInteger generation = self.generation;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.65*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            if (self.terminal && self.generation == generation) [self members:result anchor:anchor offset:next page:page+1 previous:fingerprint];
        });
    }];
}
- (void)completeBadge:(DY778FansResult *)result anchor:(NSDictionary *)anchor {
    if (anchor) {
        NSMutableArray *clubs = [NSMutableArray array];
        for (NSDictionary *club in result.clubs) if ([club[@"anchorUID"] isEqual:anchor[@"uid"]] && [club[@"level"] integerValue] > 0) {
            NSMutableDictionary *copy = [club mutableCopy]; copy[@"anchorName"] = DY778FansPersonName(anchor); copy[@"avatarURL"] = anchor[@"avatarURL"] ?: @""; copy[@"profile"] = anchor; [clubs addObject:copy];
        }
        result.clubs = clubs; result.anchor = anchor;
        if (clubs.count && ![clubs.firstObject[@"clubName"] length] && DY778FansWebConnected()) {
            [self web:@"members" params:@{@"anchor_id":anchor[@"uid"],@"sec_anchor_id":anchor[@"secUID"] ?: @"",@"source":@"1",@"type":@"1",@"offset":@0,@"count":@1} reply:^(id response,NSError *error) {
                NSString *name = DY778FansString(DY778FansFirst(DY778FansRead(DY778FansRead(response,@"data"),@"club_info"),@[@"name",@"club_name"]));
                if (!error && name.length) { NSMutableDictionary *updated = [result.clubs.firstObject mutableCopy]; updated[@"clubName"] = name; result.clubs = @[updated]; }
                [self finishLiveResult:result anchor:anchor];
            }]; return;
        }
    }
    [self finishLiveResult:result anchor:anchor];
}
- (void)finishLiveResult:(DY778FansResult *)result anchor:(NSDictionary *)anchor {
    result.date = NSDate.date;
    result.notice = anchor ? (result.clubs.count ? @"已查到指定主播的灯牌。" : @"暂未取得可确认的灯牌，不代表未加入。") : @"选择主播后，可以查询对应的粉丝灯牌。";
    if (!result.level && !result.clubs.count && !anchor) { [self finish:nil error:DY778FansError(424,@"暂未取得可确认的资料，请稍后重试。")]; return; }
    [self finish:result error:nil];
}
@end
