#import "DY778RadarApi.h"
@protocol DY778RadarHostListInitializer <NSObject>
- (instancetype)initWithUserID:(NSString *)uid;
@end
static id DY778RadarLikesManager(NSString *uid) {
    id<DY778RadarHostListInitializer> allocated = [NSClassFromString(@"AWEUserLikesDataManager") alloc];
    if (!DY778RadarHasMethod(allocated, @"initWithUserID:", "@", "@")) return nil;
    @try { return [allocated initWithUserID:uid]; } @catch (__unused NSException *exception) { return nil; }
}
static NSString *DY778RadarOrigin(id raw) {
    NSString *value = [raw isKindOfClass:NSURL.class] ? [raw absoluteString] : DY778RadarString(raw);
    if (!value.length || [value hasPrefix:@"/"]) return nil;
    if (![value containsString:@"://"]) value = [@"https://" stringByAppendingString:value];
    NSURLComponents *parts = [NSURLComponents componentsWithString:value];
    if (![parts.scheme isEqualToString:@"https"] || !parts.host.length || parts.user || parts.password) return nil;
    parts.path = @""; parts.query = nil; parts.fragment = nil;
    return parts.string;
}
static NSString *DY778RadarApiURL(NSString *path) {
    Class domain = NSClassFromString(@"NetworkProviderDomain");
    NSString *origin = DY778RadarOrigin(DY778RadarCall(domain, @"apiDomain", @[])) ?: DY778RadarOrigin(DY778RadarCall(domain, @"apiHost", @[]));
    // 宿主未暴露 API 域名时，回退到收藏接口。
    if (!origin) origin = DY778RadarOrigin(DY778RadarCall(DY778RadarLikesManager(DY778RadarCurrentAccount()), @"likeRequestURL", @[]));
    return [(origin ?: @"https://aweme.snssdk.com") stringByAppendingString:path];
}
static NSString *DY778RadarNativeURL(id raw, NSString *fallbackPath) {
    NSString *value = [raw isKindOfClass:NSURL.class] ? [raw absoluteString] : DY778RadarString(raw);
    NSURL *url = [NSURL URLWithString:value];
    if ([url.scheme isEqualToString:@"https"] && url.host.length) return value;
    return DY778RadarApiURL([value hasPrefix:@"/aweme/"] ? value : fallbackPath);
}
static NSDictionary *DY778RadarPayload(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    return [value[@"data"] isKindOfClass:NSDictionary.class] ? value[@"data"] : value;
}
static BOOL DY778RadarHandleMatches(NSDictionary *profile, NSString *handle) {
    NSString *actual = DY778RadarString(profile[@"handle"]);
    return actual.length && [actual caseInsensitiveCompare:handle] == NSOrderedSame;
}
// 搜索结果可能是 userInfo 模型或字典包装。
static void DY778RadarSearchMatches(id object, NSString *handle, NSMutableDictionary *matches, NSUInteger depth, NSUInteger *budget, NSUInteger *recognized) {
    if (!object || depth > 7 || !*budget) return;
    (*budget)--;
    if ([object isKindOfClass:NSArray.class]) {
        for (id item in object) { if (!*budget) break; DY778RadarSearchMatches(item, handle, matches, depth + 1, budget, recognized); }
        return;
    }
    NSDictionary *profile = DY778RadarProfile(object);
    if (profile) (*recognized)++;
    if (profile && DY778RadarHandleMatches(profile, handle)) matches[profile[@"uid"]] = profile;
    for (NSString *key in @[@"user_list", @"users", @"user_info", @"userInfo", @"user", @"data", @"items"]) {
        if (!*budget) break;
        DY778RadarSearchMatches(DY778RadarRead(object, key), handle, matches, depth + 1, budget, recognized);
    }
}
static id DY778RadarContactDatabase(void) {
    Class cls = NSClassFromString(@"AWEIMUserDBManager");
    for (NSString *selector in @[@"sharedInstance", @"defaultManager", @"manager"]) {
        id manager = DY778RadarCall(cls, selector, @[]); if (manager) return manager;
    }
    id center = DY778RadarCall(NSClassFromString(@"HTSServiceCenter"), @"defaultCenter", @[]);
    id manager = cls ? DY778RadarCall(center, @"getService:", @[cls]) : nil;
    if (!manager) { @try { manager = [cls new]; } @catch (__unused NSException *exception) { } }
    return manager;
}
static NSArray *DY778RadarLocalContacts(id database) {
    // 同步的数据库读取在非主线程执行。
    id value = DY778RadarCall(database, @"localContactList", @[]);
    NSArray *empty = [value isKindOfClass:NSArray.class] ? value : nil;
    if (empty.count) return [empty copy];
    if (DY778RadarHasMethod(database, @"localContactListWithReadScene:", "@", "q")) {
        for (NSInteger scene = 0; scene <= 6; scene++) {
            value = DY778RadarCall(database, @"localContactListWithReadScene:", @[@(scene)]);
            if ([value isKindOfClass:NSArray.class]) { empty = value; if (empty.count) return [empty copy]; }
        }
    }
    return empty;
}
static NSArray *DY778RadarFollowedContacts(id database) {
    if (!DY778RadarHasMethod(database, @"fetchFriendAndFollowedUsersWithLimits:readScene:", "@", "qq")) return nil;
    NSArray *empty;
    for (NSNumber *limit in @[@10000, @5000, @2000]) for (NSNumber *scene in @[@0, @1]) {
        id value = DY778RadarCall(database, @"fetchFriendAndFollowedUsersWithLimits:readScene:", @[limit, scene]);
        if ([value isKindOfClass:NSArray.class]) { empty = value; if (empty.count) return [empty copy]; }
    }
    return empty;
}
static NSDictionary *DY778RadarContactPage(NSArray *contacts, NSString *account) {
    NSMutableArray *all = [NSMutableArray array], *friends = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id user in contacts) {
        NSDictionary *profile = DY778RadarProfile(user);
        if (!profile || [profile[@"uid"] isEqual:account] || [seen containsObject:profile[@"uid"]]) continue;
        if ([DY778RadarCount(DY778RadarRead(user, @"blockStatus")) boolValue]) continue;
        [seen addObject:profile[@"uid"]]; [all addObject:profile];
        // 互关要求 followStatus=2 且 followerStatus=1。
        if ([DY778RadarCount(DY778RadarRead(user, @"followStatus")) integerValue] == 2 &&
            [DY778RadarCount(DY778RadarRead(user, @"followerStatus")) integerValue] == 1) [friends addObject:profile];
    }
    return @{@"contacts": all, @"users": friends};
}
static void DY778RadarLoadContacts(NSString *owner, DY778RadarReply completion) {
    [DY778RadarNetwork.shared perform:@"AWEIMUserDBManager.localContactList" owner:owner start:^dispatch_block_t(DY778RadarReply reply, DY778RadarIsCurrent current) {
        id database = DY778RadarContactDatabase();
        if (!database) { reply(nil, DY778RadarError(503, @"当前抖音版本的联系人服务不可用，请复制诊断。")); return nil; }
        NSString *account = DY778RadarCurrentAccount();
        // 联系人回调只接受一个数组参数。
        void (^finishRead)(id) = ^(id raw) {
            NSArray *snapshot = [raw isKindOfClass:NSArray.class] ? [raw copy] : nil;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSArray *contacts = snapshot.count ? snapshot : (DY778RadarFollowedContacts(database) ?: snapshot);
                NSDictionary *page = contacts ? DY778RadarContactPage(contacts, account) : nil;
                reply(page, page ? nil : DY778RadarError(502, @"联系人尚未就绪，可先打开抖音消息页，再返回刷新。"));
            });
        };
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *local = DY778RadarLocalContacts(database);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!current()) { reply(nil, DY778RadarError(-999, @"联系人读取已暂停。")); return; }
                if (local.count) { finishRead(local); return; }
                if (DY778RadarHasMethod(database, @"localContactListWithReadScene:completion:", "v", "q@")) {
                    DY778RadarCall(database, @"localContactListWithReadScene:completion:", @[@0, [^(id contacts) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (!current()) { reply(nil, DY778RadarError(-999, @"联系人读取已暂停。")); return; }
                            finishRead(contacts ?: local);
                        });
                    } copy]]);
                } else finishRead(local);
            });
        });
        // 取消不得影响宿主共享的数据库服务。
        return nil;
    } completion:completion];
}
@implementation DY778RadarApi
+ (void)profile:(NSDictionary *)target owner:(NSString *)owner completion:(DY778RadarReply)completion {
    if (!DY778RadarIdentifier(target[@"uid"])) { completion(nil, DY778RadarError(400, @"账号标识无效，请重新添加。")); return; }
    NSMutableDictionary *params = [@{@"user_id": target[@"uid"], @"source": @"other_profile"} mutableCopy];
    if (DY778RadarString(target[@"secUID"]).length) params[@"sec_user_id"] = target[@"secUID"];
    [DY778RadarNetwork.shared get:DY778RadarApiURL(@"/aweme/v1/user/profile/other/") parameters:params owner:owner completion:^(id value, NSError *error) {
        NSDictionary *profile = error ? nil : DY778RadarProfile(DY778RadarPayload(value));
        if (!error && (!profile || ![profile[@"uid"] isEqual:target[@"uid"]])) error = DY778RadarError(502, @"资料返回不完整，本次数值已忽略。");
        if (!error && !DY778RadarString(profile[@"secUID"]).length && DY778RadarString(target[@"secUID"]).length) {
            NSMutableDictionary *merged = [profile mutableCopy]; merged[@"secUID"] = target[@"secUID"]; profile = merged;
        }
        completion(profile, error);
    }];
}
+ (void)resolveHandle:(NSString *)handle owner:(NSString *)owner completion:(DY778RadarReply)completion {
    NSString *clean = [handle stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([clean hasPrefix:@"@"]) clean = [clean substringFromIndex:1];
    if (!clean.length || clean.length > 64 || [clean rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
        completion(nil, DY778RadarError(400, @"请输入主页显示的完整抖音号，不是昵称。")); return;
    }
    DY778RadarLoadContacts(owner, ^(id page, NSError *error) {
        if (error.code == NSURLErrorCancelled || error.code == 401) { completion(nil, error); return; }
        NSMutableDictionary *matches = [NSMutableDictionary dictionary];
        for (NSDictionary *profile in page[@"contacts"]) if (DY778RadarHandleMatches(profile, clean)) matches[profile[@"uid"]] = profile;
        if (matches.count == 1) { completion(matches.allValues.firstObject, nil); return; }
        id manager;
        @try { manager = [NSClassFromString(@"AWESearchUserManager") new]; } @catch (__unused NSException *exception) { }
        [self searchHandle:clean manager:manager page:0 owner:owner completion:completion];
    });
}
+ (void)searchHandle:(NSString *)handle manager:(id)manager page:(NSUInteger)page owner:(NSString *)owner completion:(DY778RadarReply)completion {
    NSNumber *previousCursor = DY778RadarCount(DY778RadarRead(manager, @"cursor")) ?: @0;
    [DY778RadarNetwork.shared perform:@"AWESearchUserManager.fetchUsersWithKeyword" owner:owner start:^dispatch_block_t(DY778RadarReply reply, DY778RadarIsCurrent current) {
        NSString *selector = @"fetchUsersWithKeyword:cursor:isPullToRefresh:completion:";
        BOOL compatible = DY778RadarHasMethod(manager, selector, "v", "@@B@") || DY778RadarHasMethod(manager, selector, "v", "@@c@");
        if (!compatible) { reply(nil, DY778RadarError(503, @"当前版本的抖音用户搜索入口不可用，请复制诊断。")); return nil; }
        if (!page) {
            DY778RadarSet(manager, @"count", @20); DY778RadarSet(manager, @"cursor", @0);
            DY778RadarSet(manager, @"searchSource", @"normal_search"); DY778RadarSet(manager, @"initialSearchSource", @"normal_search");
        }
        __weak id weakManager = manager;
        // 取数返回 (NSArray *, NSError *)；userArray 里是布局模型。
        void (^ready)(NSArray *, NSError *) = ^(NSArray *users, NSError *error) {
            NSArray *snapshot = [users isKindOfClass:NSArray.class] ? [users copy] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!current()) { reply(nil, DY778RadarError(-999, @"用户搜索已暂停。")); return; }
                if (error) { reply(nil, error); return; }
                if (!snapshot) { reply(nil, DY778RadarError(502, @"抖音搜索返回的用户资料格式不可识别，请复制诊断。")); return; }
                NSMutableDictionary *matches = [NSMutableDictionary dictionary]; NSUInteger budget = 800, recognized = 0;
                DY778RadarSearchMatches(snapshot, handle, matches, 0, &budget, &recognized);
                if (matches.count > 1) { reply(nil, DY778RadarError(409, @"返回多个同号结果，请核对完整抖音号。")); return; }
                NSDictionary *profile = matches.allValues.firstObject;
                id live = weakManager;
                reply(@{@"profile": profile ?: @{}, @"count": @(recognized), @"rawCount": @(snapshot.count),
                    @"more": @([DY778RadarRead(live, @"hasMore") boolValue]), @"cursor": DY778RadarCount(DY778RadarRead(live, @"cursor")) ?: @0}, nil);
            });
        };
        DY778RadarCall(manager, selector, @[handle, previousCursor, @(page == 0), ready]);
        return ^{ DY778RadarCall(DY778RadarRead(manager, @"task"), @"cancel", @[]); };
    } completion:^(id result, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *profile = result[@"profile"];
        if (DY778RadarIdentifier(profile[@"uid"])) { completion(profile, nil); return; }
        if (page < 2 && [result[@"more"] boolValue] && [result[@"cursor"] longLongValue] > previousCursor.longLongValue) {
            [self searchHandle:handle manager:manager page:page + 1 owner:owner completion:completion]; return;
        }
        // 空回调无法区分「无此用户」与「搜索失败」。
        NSError *failure = DY778RadarError([result[@"count"] unsignedIntegerValue] ? 404 : 502,
            [result[@"count"] unsignedIntegerValue] ? @"搜索结果中未匹配到完整抖音号，请从对方主页复制后重试。" :
            @"抖音用户搜索暂未返回可核对的账号，请确认抖音搜索可用后重试。也可以复制诊断反馈。" );
        NSMutableDictionary *info = [failure.userInfo mutableCopy]; info[@"DY778RadarEndpoint"] = @"AWESearchUserManager.fetchUsersWithKeyword.result";
        completion(nil, [NSError errorWithDomain:failure.domain code:failure.code userInfo:info]);
    }];
}
+ (void)friendsForOwner:(NSString *)owner completion:(DY778RadarReply)completion {
    DY778RadarLoadContacts(owner, ^(id page, NSError *error) { completion(error ? nil : page[@"users"], error); });
}
+ (void)likes:(NSDictionary *)target cursor:(NSNumber *)cursor owner:(NSString *)owner completion:(DY778RadarReply)completion {
    if (!DY778RadarIdentifier(target[@"uid"])) { completion(nil, DY778RadarError(400, @"账号标识无效，请重新添加。")); return; }
    id manager = DY778RadarLikesManager(target[@"uid"]);
    DY778RadarSet(manager, @"pageSize", @30); DY778RadarSet(manager, @"count", @30);
    DY778RadarSet(manager, @"maxCursor", cursor); DY778RadarSet(manager, @"minCursor", @0);
    NSString *url = DY778RadarNativeURL(DY778RadarCall(manager, @"likeRequestURL", @[]), @"/aweme/v1/aweme/favorite/");
    id native = DY778RadarCall(manager, @"paramsIsRefresh:", @[@(cursor.longLongValue == 0)]);
    NSMutableDictionary *params = [native isKindOfClass:NSDictionary.class] ? [native mutableCopy] : [NSMutableDictionary dictionary];
    params[@"user_id"] = target[@"uid"]; params[@"count"] = @30; params[@"max_cursor"] = cursor; params[@"min_cursor"] = @0;
    if (DY778RadarString(target[@"secUID"]).length) params[@"sec_user_id"] = target[@"secUID"];
    [DY778RadarNetwork.shared get:url parameters:params owner:owner completion:^(id value, NSError *error) {
        NSDictionary *payload = DY778RadarPayload(value);
        id list = DY778RadarFirst(payload, @[@"aweme_list", @"awemes"]);
        if (error || ![list isKindOfClass:NSArray.class]) { completion(nil, error ?: DY778RadarError(502, @"喜欢列表暂不可读，保留上次记录。")); return; }
        NSMutableArray *videos = [NSMutableArray array]; NSMutableSet *ids = [NSMutableSet set];
        for (id raw in list) {
            NSDictionary *video = DY778RadarVideo(raw);
            if (!video) { completion(nil, DY778RadarError(502, @"喜欢作品资料不完整，保留上次基线。")); return; }
            if (![ids containsObject:video[@"id"]]) { [ids addObject:video[@"id"]]; [videos addObject:video]; }
        }
        NSNumber *next = DY778RadarCount(payload[@"max_cursor"]), *hasMore = DY778RadarCount(payload[@"has_more"]);
        if (!hasMore || (hasMore.boolValue && (!next || [next isEqual:cursor]))) {
            completion(nil, DY778RadarError(502, @"喜欢列表分页暂不可用，保留上次基线。")); return;
        }
        completion(@{@"videos": videos, @"cursor": next ?: cursor, @"more": @(hasMore.boolValue)}, nil);
    }];
}
@end
