#import "DY778FansWeb.h"
#import "DY778FansPrivate.h"
#import "DY778FansSigner.h"
#import <JavaScriptCore/JavaScriptCore.h>

static NSString *const DY778FansWebUA = @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36";
static NSString *DY778FansWebCookie(void) {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    // 仅使用宿主应用的抖音会话 Cookie，不读磁盘或无关存储。
    for (NSString *origin in @[[DY778FansPrivate(DY778FansNativeOrigin) stringByAppendingString:@"/"], [DY778FansPrivate(DY778FansAppOrigin) stringByAppendingString:@"/"], [DY778FansPrivate(DY778FansWebOrigin) stringByAppendingString:@"/"], [DY778FansPrivate(DY778FansLiveOrigin) stringByAppendingString:@"/"]]) {
        for (NSHTTPCookie *cookie in [NSHTTPCookieStorage.sharedHTTPCookieStorage cookiesForURL:[NSURL URLWithString:origin]]) {
            if (cookie.expiresDate && [cookie.expiresDate timeIntervalSinceNow] <= 0) continue;
            values[cookie.name] = cookie.value;
        }
    }
    if (![values[@"sessionid"] length] && ![values[@"sessionid_ss"] length]) return @"";
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *name in [values.allKeys sortedArrayUsingSelector:@selector(compare:)]) [pairs addObject:[NSString stringWithFormat:@"%@=%@",name,values[name]]];
    return [pairs componentsJoinedByString:@"; "];
}
BOOL DY778FansWebConnected(void) { return DY778FansWebCookie().length > 0; }
static NSString *DY778FansEncode(NSString *text) {
    return [[text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._"]] stringByReplacingOccurrencesOfString:@"%20" withString:@"+"];
}
@interface DY778FansWebClient () <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, copy) DY778FansWebReply completion;
@property(nonatomic) NSUInteger generation;
@end
@implementation DY778FansWebClient
- (void)cancel {
    self.generation++; self.completion = nil; [self.session invalidateAndCancel]; self.session = nil; self.task = nil; self.data = nil;
}
- (void)finish:(id)value error:(NSError *)error {
    DY778FansWebReply completion = self.completion; [self cancel]; if (completion) completion(value,error);
}
- (void)requestURL:(NSString *)url origin:(NSString *)origin cookie:(NSString *)cookie quick:(BOOL)quick {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil; config.URLCache = nil; config.timeoutIntervalForRequest = quick ? 6 : 12; config.timeoutIntervalForResource = quick ? 8 : 15;
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    if (cookie.length) [request setValue:cookie forHTTPHeaderField:@"Cookie"];
    [request setValue:DY778FansWebUA forHTTPHeaderField:@"User-Agent"]; [request setValue:[origin stringByAppendingString:@"/"] forHTTPHeaderField:@"Referer"];
    [request setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"]; [request setValue:@"zh-CN,zh;q=0.9" forHTTPHeaderField:@"Accept-Language"];
    self.data = [NSMutableData data]; self.task = [self.session dataTaskWithRequest:request]; [self.task resume];
}
- (void)get:(NSString *)route params:(NSDictionary *)params completion:(DY778FansWebReply)completion {
    [self cancel]; NSString *cookie = DY778FansWebCookie();
    BOOL live = [@[@"card",@"members",@"user"] containsObject:route], lookup = [route isEqual:@"lookup"];
    if (live && !cookie.length) { completion(nil,DY778FansError(401,@"当前登录状态暂未返回可查询的数据，请稍后重试。")); return; }
    NSDictionary *routes = @{@"card":DY778FansPrivate(DY778FansCardPath),@"members":DY778FansPrivate(DY778FansMembersPath),@"user":DY778FansPrivate(DY778FansLiveUserPath),@"lookup":DY778FansPrivate(DY778FansLookupPath),@"profile":DY778FansPrivate(DY778FansProfilePath),@"search":DY778FansPrivate(DY778FansSearchPath),@"discover":DY778FansPrivate(DY778FansDiscoverPath)};
    NSString *path = routes[route], *origin = live ? DY778FansPrivate(DY778FansLiveOrigin) : DY778FansPrivate(DY778FansWebOrigin);
    if (!path) { completion(nil,DY778FansError(400,@"不支持的查询。")); return; }
    self.completion = completion; NSUInteger generation = self.generation;
    NSMutableDictionary *query = [@{@"aid":@"6383",@"app_name":@"douyin_web",@"live_id":@"1",@"device_platform":@"web",@"language":@"zh"} mutableCopy];
    if (!live) [query removeAllObjects];
    if ([route isEqual:@"card"] || (!live && !lookup)) [query addEntriesFromDictionary:@{@"channel":@"channel_pc_web",@"pc_client_type":@"1",@"update_version_code":@"170400",@"version_code":@"170400",@"version_name":@"17.4.0",@"cookie_enabled":@"true",@"screen_width":@"1920",@"screen_height":@"1080",@"browser_language":@"zh-CN",@"browser_platform":@"Win32",@"browser_name":@"Chrome",@"browser_version":@"135.0.0.0",@"browser_online":@"true",@"engine_name":@"Blink",@"engine_version":@"135.0.0.0",@"os_name":@"Windows",@"os_version":@"10",@"cpu_core_num":@"8",@"device_memory":@"8",@"platform":@"PC",@"downlink":@"10",@"effective_type":@"4g",@"round_trip_time":@"50"}];
    if ([route isEqual:@"card"]) [query addEntriesFromDictionary:@{@"click_source":@"pc_audience_list",@"width":@"394",@"height":@"853"}];
    if (!live && !lookup) [query addEntriesFromDictionary:@{@"device_platform":@"webapp",@"aid":@"6383"}];
    if ([route isEqual:@"user"]) [query addEntriesFromDictionary:@{@"room_id":@"0",@"packed_level":@"2",@"with_host_info":@"1",@"source":@"0",@"request_from":@"",@"target_display_role":@"0"}];
    [query addEntriesFromDictionary:params];
    if (!lookup) {
        NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789="; NSMutableString *token = [NSMutableString string];
        for (NSUInteger i=0;i<107;i++) [token appendFormat:@"%C",[alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)]];
        query[@"msToken"] = token;
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in [query.allKeys sortedArrayUsingSelector:@selector(compare:)]) [parts addObject:[NSString stringWithFormat:@"%@=%@",DY778FansEncode(key),DY778FansEncode(DY778FansString(query[key]))]];
    NSString *unsignedQuery = [parts componentsJoinedByString:@"&"];
    if (lookup) { [self requestURL:[NSString stringWithFormat:@"%@%@?%@",origin,path,unsignedQuery] origin:origin cookie:cookie quick:YES]; return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            JSContext *context = [JSContext new]; [context evaluateScript:DY778FansSignerSource()];
            JSValue *value = [context[DY778FansPrivate(DY778FansSignatureFunction)] callWithArguments:@[unsignedQuery,DY778FansWebUA]];
            NSString *signature = !context.exception && value.isString ? value.toString : nil;
            dispatch_async(dispatch_get_main_queue(),^{
                if (self.generation != generation || !self.completion) return;
                if (!signature.length) { [self finish:nil error:DY778FansError(503,@"查询准备失败，请重试。")]; return; }
                NSString *url = [NSString stringWithFormat:DY778FansPrivate(DY778FansSignedURLFormat),origin,path,unsignedQuery,DY778FansEncode(signature)];
                [self requestURL:url origin:origin cookie:cookie quick:NO];
            });
        }
    });
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil); if (session == self.session) [self finish:nil error:DY778FansError(403,@"当前登录暂未取得可查询资料，请稍后重试。")];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
    BOOL valid = session == self.session && code == 200 && response.expectedContentLength <= 2000000;
    completionHandler(valid ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
    if (session == self.session && !valid) [self finish:nil error:DY778FansError(code,@"暂时无法查询，请稍后重试。")];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (session != self.session) return;
    if (self.data.length + data.length > 2000000) { [self finish:nil error:DY778FansError(413,@"资料过多，请缩小查询范围。")]; return; }
    [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (session != self.session) return;
    if (error) { [self finish:nil error:DY778FansError(error.code == NSURLErrorTimedOut ? 408 : 502,@"连接暂不可用，请稍后重试。")]; return; }
    id value = self.data.length ? [NSJSONSerialization JSONObjectWithData:self.data options:0 error:&error] : nil;
    if (![value isKindOfClass:NSDictionary.class]) { [self finish:nil error:DY778FansError(502,@"暂时无法取得资料，请稍后重试。")]; return; }
    NSNumber *status = DY778FansInteger(value[@"status_code"]);
    if ([value[@"status_code"] isEqual:@20003] || [value[@"status_code"] isEqual:@8] || [value[@"status_code"] isEqual:@1001]) { [self finish:nil error:DY778FansError(401,@"当前查询未获通过，请确认抖音登录状态后重试。")]; return; }
    if (!status || status.integerValue != 0) { [self finish:nil error:DY778FansError(502,@"查询未完成，请稍后重试。")]; return; }
    [self finish:value error:nil];
}
@end
