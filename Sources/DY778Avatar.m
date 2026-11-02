#import "DY778Avatar.h"
#import "DY778Core.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>

static id DY778AvatarCall(id object, NSString *selectorName, id argument, BOOL hasArgument) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != (hasArgument ? 3u : 2u) || signature.methodReturnType[0] != '@' || (hasArgument && [signature getArgumentTypeAtIndex:2][0] != '@')) return nil;
    @try { return hasArgument ? ((id (*)(id, SEL, id))objc_msgSend)(object, selector, argument) : ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}
static void DY778CollectAvatarURLs(id value, NSUInteger depth, NSMutableOrderedSet *urls) {
    if (!value || depth > 6 || urls.count >= 16) return;
    if ([value isKindOfClass:NSURL.class]) value = [value absoluteString];
    if ([value isKindOfClass:NSString.class]) {
        NSURL *url = [NSURL URLWithString:value];
        if ([@[@"https", @"http"] containsObject:url.scheme.lowercaseString] && url.host.length) [urls addObject:value];
        return;
    }
    if ([value isKindOfClass:NSArray.class]) { for (id item in value) DY778CollectAvatarURLs(item, depth + 1, urls); return; }
    for (NSString *key in @[@"originURLList", @"URLList", @"urlList", @"url_list", @"URLListArray", @"url", @"URL", @"downloadURLList"])
        DY778CollectAvatarURLs(DY778Read(value, key), depth + 1, urls);
}
NSArray *DY778AvatarURLs(id value) { NSMutableOrderedSet *urls = [NSMutableOrderedSet orderedSet]; DY778CollectAvatarURLs(value, 0, urls); return urls.array; }
NSString *DY778AvatarURL(id value) { return DY778AvatarURLs(value).firstObject ?: @""; }
static NSString *DY778ProfileString(id user, NSArray *keys) {
    for (NSString *key in keys) { NSString *value = DY778Identifier(DY778Read(user, key)); if (value.length) return value; } return @"";
}
NSDictionary *DY778ProfileFromUser(id user) {
    NSString *uid = DY778ProfileString(user, @[@"uid", @"userID"]);
    NSString *nickname = DY778ProfileString(user, @[@"nickname", @"name", @"senderNickName"]);
    NSString *remark = DY778ProfileString(user, @[@"alias", @"remark_name", @"remark"]), *avatar = @"";
    NSMutableOrderedSet *urls = [NSMutableOrderedSet orderedSet];
    for (NSString *key in @[@"avatarLarger", @"avatar_larger", @"avatarMedium", @"avatar_medium", @"avatarURLList", @"avatarStrUrls", @"avatarURL", @"avatar", @"senderPortrait", @"avatarThumb", @"avatar_thumb", @"avatarSmallStrUrl", @"avatarURLSmall"])
        [urls addObjectsFromArray:DY778AvatarURLs(DY778Read(user, key))];
    avatar = urls.firstObject ?: @"";
    return @{@"uid": uid, @"name": remark.length ? remark : nickname, @"nickname": nickname, @"remark": remark, @"avatar": avatar, @"avatarURLs": urls.array};
}
static dispatch_queue_t DY778ProfileQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once; dispatch_once(&once, ^{ queue = dispatch_queue_create("com.dy778.profile-cache", DISPATCH_QUEUE_SERIAL); }); return queue;
}
static id DY778ContactDatabase(void) {
    Class cls = NSClassFromString(@"AWEIMUserDBManager");
    id center = DY778AvatarCall(NSClassFromString(@"HTSServiceCenter"), @"defaultCenter", nil, NO);
    id manager = DY778AvatarCall(center, @"getService:", cls, YES);
    if (!manager) manager = DY778AvatarCall(cls, @"sharedInstance", nil, NO);
    return manager;
}
static id DY778LocalUser(NSString *account, NSString *uid) {
    id database = DY778ContactDatabase();
    NSString *owner = DY778Identifier(DY778Read(database, @"currentDataBaseUid"));
    if (!database || (owner.length && ![owner isEqual:account]) || ![account isEqual:DY778CurrentAccountID()]) return nil;
    SEL selector = NSSelectorFromString(@"userWithId:readScene:");
    NSMethodSignature *signature = [database methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 4 || signature.methodReturnType[0] != '@' || [signature getArgumentTypeAtIndex:2][0] != '@' || !strchr("qQ", [signature getArgumentTypeAtIndex:3][0])) return nil;
    id user = nil;
    @try { user = ((id (*)(id, SEL, id, long long))objc_msgSend)(database, selector, uid, 0); }
    @catch (__unused NSException *exception) {}
    NSDictionary *primary = DY778ProfileFromUser(user);
    if (![uid isEqual:account] || ([primary[@"uid"] isEqual:uid] && [primary[@"avatar"] length])) return user;
    if (![account isEqual:DY778CurrentAccountID()]) return nil;
    selector = NSSelectorFromString(@"userWithId:readScene:readUserOnlyFromIMDB:");
    signature = [database methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 5 || signature.methodReturnType[0] != '@' ||
        [signature getArgumentTypeAtIndex:2][0] != '@' || !strchr("qQ", [signature getArgumentTypeAtIndex:3][0]) ||
        !strchr("Bc", [signature getArgumentTypeAtIndex:4][0])) return user;
    @try {
        id stored = ((id (*)(id, SEL, id, long long, BOOL))objc_msgSend)(database, selector, uid, 0, YES);
        NSDictionary *profile = DY778ProfileFromUser(stored);
        if ([profile[@"uid"] isEqual:account] && [profile[@"avatar"] length]) return stored;
    } @catch (__unused NSException *exception) {}
    return user;
}
void DY778GetLocalUserProfile(NSString *account, NSString *uid, void (^completion)(NSDictionary *)) {
    if (!completion) return;
    if (!account.length || !uid.length) { dispatch_async(dispatch_get_main_queue(), ^{ completion(@{}); }); return; }
    dispatch_async(DY778ProfileQueue(), ^{
        static NSMutableDictionary *cache; static NSMutableDictionary *fetchedAt;
        if (!cache) { cache = [NSMutableDictionary dictionary]; fetchedAt = [NSMutableDictionary dictionary]; }
        NSString *key = [@[account, uid] componentsJoinedByString:@"/"];
        NSDictionary *profile = cache[key]; NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        if (!profile || now - [fetchedAt[key] doubleValue] > 120) {
            NSDictionary *fresh = DY778ProfileFromUser(DY778LocalUser(account, uid));
            if ((! [fresh[@"uid"] length] || [fresh[@"uid"] isEqual:uid]) && ([fresh[@"name"] length] || [fresh[@"avatar"] length])) profile = fresh;
            cache[key] = profile ?: @{}; fetchedAt[key] = @(now);
        }
        NSDictionary *resolved = profile ?: @{};
        dispatch_async(dispatch_get_main_queue(), ^{ completion([account isEqual:DY778CurrentAccountID()] ? resolved : @{}); });
    });
}
void DY778GetCurrentAccountProfile(void (^completion)(NSDictionary *)) {
    if (!completion) return;
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778GetCurrentAccountProfile(completion); }); return; }
    NSString *account = DY778CurrentAccountID();
    id service = DY778AvatarCall(NSClassFromString(@"AWEUserService"), @"sharedService", nil, NO);
    NSDictionary *current = DY778ProfileFromUser(DY778Read(service, @"currentLoginUser"));
    if (!account.length || ![current[@"uid"] isEqual:account]) current = @{};
    dispatch_async(DY778ProfileQueue(), ^{
        static NSMutableDictionary *cache; static NSMutableDictionary *fetchedAt; if (!cache) { cache = [NSMutableDictionary dictionary]; fetchedAt = [NSMutableDictionary dictionary]; }
        NSDictionary *profile = cache[account ?: @""];
        NSTimeInterval age = NSDate.date.timeIntervalSince1970 - [fetchedAt[account ?: @""] doubleValue];
        BOOL complete = [profile[@"name"] length] && [profile[@"avatar"] length];
        BOOL changed = [current[@"avatar"] length] && ![current[@"avatar"] isEqual:profile[@"avatar"]];
        if (!profile || changed || age > (complete ? 300 : 5)) {
            NSMutableDictionary *found = [current mutableCopy];
            if (account.length && (![found[@"avatar"] length] || ![found[@"name"] length])) {
                NSDictionary *local = DY778ProfileFromUser(DY778LocalUser(account, account));
                for (NSString *key in @[@"avatar", @"name", @"nickname"]) if ([local[@"uid"] isEqual:account] && ![found[key] length] && [local[key] length]) found[key] = local[key];
                if ([local[@"uid"] isEqual:account] && ![found[@"avatarURLs"] count]) found[@"avatarURLs"] = local[@"avatarURLs"] ?: @[];
            }
            for (NSString *key in @[@"avatar", @"name", @"nickname"])
                if (![found[key] length] && [profile[@"uid"] isEqual:account] && [profile[key] length]) found[key] = profile[key];
            if (![found[@"avatarURLs"] count] && [profile[@"uid"] isEqual:account]) found[@"avatarURLs"] = profile[@"avatarURLs"] ?: @[];
            found[@"uid"] = account ?: @""; profile = [found copy]; if (account.length) { cache[account] = profile; fetchedAt[account] = @(NSDate.date.timeIntervalSince1970); }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion([(account ?: @"") isEqual:(DY778CurrentAccountID() ?: @"")] ? profile : @{}); });
    });
}
static NSString *DY778AvatarDigest(NSString *url) {
    NSData *data = [url dataUsingEncoding:NSUTF8StringEncoding]; unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *value = [NSMutableString string]; for (NSUInteger i = 0; i < sizeof(digest); i++) [value appendFormat:@"%02x", digest[i]]; return value;
}
static UIImage *DY778AvatarDecode(NSData *data) {
    if (!data.length || data.length > 4 * 1024 * 1024) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL); if (!source) return nil;
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES, (id)kCGImageSourceThumbnailMaxPixelSize: @320, (id)kCGImageSourceCreateThumbnailWithTransform: @YES});
    UIImage *image = thumbnail ? [UIImage imageWithCGImage:thumbnail scale:2 orientation:UIImageOrientationUp] : nil;
    if (thumbnail) CGImageRelease(thumbnail); CFRelease(source); return image;
}
@interface DY778AvatarRequest : NSObject
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, copy) NSString *url;
@property(nonatomic, strong) NSMutableArray *callbacks;
@end
@implementation DY778AvatarRequest @end
@interface DY778AvatarCache : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSCache *images;
@property(nonatomic, strong) NSMutableDictionary *requests;
@property(nonatomic, strong) NSMutableDictionary *tasks;
@property(nonatomic, strong) NSMutableDictionary *failed;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) dispatch_queue_t io;
@property(nonatomic, strong) NSURL *root;
+ (instancetype)shared;
- (void)load:(NSString *)url completion:(void (^)(UIImage *))completion;
@end
@implementation DY778AvatarCache
+ (instancetype)shared { static DY778AvatarCache *cache; static dispatch_once_t once; dispatch_once(&once, ^{ cache = [self new]; }); return cache; }
- (instancetype)init {
    if ((self = [super init])) {
        _images = [NSCache new]; _images.totalCostLimit = 16 * 1024 * 1024; _requests = [NSMutableDictionary dictionary]; _tasks = [NSMutableDictionary dictionary]; _failed = [NSMutableDictionary dictionary];
        _io = dispatch_queue_create("com.dy778.avatar-files", DISPATCH_QUEUE_SERIAL);
        _root = [[[NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject] URLByAppendingPathComponent:@"DY778/Avatars" isDirectory:YES];
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration; configuration.URLCache = nil; configuration.HTTPShouldSetCookies = NO; configuration.HTTPMaximumConnectionsPerHost = 3; configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:NSOperationQueue.mainQueue];
        dispatch_async(_io, ^{ [NSFileManager.defaultManager createDirectoryAtURL:self.root withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil]; });
    } return self;
}
- (void)complete:(DY778AvatarRequest *)request image:(UIImage *)image {
    if (image) [self.images setObject:image forKey:request.url cost:(NSUInteger)(image.size.width * image.size.height * image.scale * image.scale * 4)];
    else self.failed[request.url] = @(NSDate.date.timeIntervalSince1970);
    NSArray *callbacks = [request.callbacks copy]; [self.requests removeObjectForKey:request.url];
    for (void (^callback)(UIImage *) in callbacks) callback(image);
}
- (void)load:(NSString *)url completion:(void (^)(UIImage *))completion {
    UIImage *image = [self.images objectForKey:url]; if (image) { completion(image); return; }
    NSNumber *failedAt = self.failed[url];
    if (failedAt && NSDate.date.timeIntervalSince1970 - failedAt.doubleValue < 30) { completion(nil); return; }
    [self.failed removeObjectForKey:url];
    DY778AvatarRequest *existing = self.requests[url]; if (existing) { [existing.callbacks addObject:[completion copy]]; return; }
    DY778AvatarRequest *request = [DY778AvatarRequest new]; request.url = url; request.callbacks = [NSMutableArray arrayWithObject:[completion copy]]; self.requests[url] = request;
    NSURL *path = [self.root URLByAppendingPathComponent:DY778AvatarDigest(url)];
    dispatch_async(self.io, ^{
        UIImage *local = DY778AvatarDecode([NSData dataWithContentsOfURL:path options:NSDataReadingMappedIfSafe error:nil]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (local) { [self complete:request image:local]; return; }
            request.data = [NSMutableData data]; NSURLSessionDataTask *task = [self.session dataTaskWithURL:[NSURL URLWithString:url]]; self.tasks[@(task.taskIdentifier)] = request; [task resume];
        });
    });
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    BOOL ok = [response isKindOfClass:NSHTTPURLResponse.class] && [(NSHTTPURLResponse *)response statusCode] / 100 == 2;
    completion(ok && response.expectedContentLength <= 4 * 1024 * 1024 ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    DY778AvatarRequest *request = self.tasks[@(task.taskIdentifier)]; if (request.data.length + data.length > 4 * 1024 * 1024) { [task cancel]; return; } [request.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    DY778AvatarRequest *request = self.tasks[@(task.taskIdentifier)]; [self.tasks removeObjectForKey:@(task.taskIdentifier)]; if (!request) return;
    NSData *data = request.data; request.data = nil;
    dispatch_async(self.io, ^{
        UIImage *image = error ? nil : DY778AvatarDecode(data);
        if (image) [UIImageJPEGRepresentation(image, .88) writeToURL:[self.root URLByAppendingPathComponent:DY778AvatarDigest(request.url)] options:NSDataWritingAtomic error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ [self complete:request image:image]; });
    });
}
@end
@interface DY778AvatarBindingState : NSObject
@property(nonatomic, copy) NSString *binding;
@property(nonatomic) BOOL loaded;
@property(nonatomic) BOOL loading;
@property(nonatomic) NSTimeInterval nextAttempt;
@property(nonatomic) NSUInteger attempts;
@end
@implementation DY778AvatarBindingState @end
static char kDY778AvatarBinding, kDY778CurrentAvatarBinding, kDY778CurrentAvatarRetries;
static UIImage *DY778AvatarPlaceholder(UIImageView *view) {
    if (!objc_getAssociatedObject(view, &kDY778CurrentAvatarBinding)) return [UIImage systemImageNamed:@"person.crop.circle.fill"];
    static UIImage *image; static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 48)];
        image = [[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
            NSString *text = @"🤡"; NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:36]};
            CGSize size = [text sizeWithAttributes:attributes];
            [text drawAtPoint:CGPointMake((48 - size.width) / 2, (48 - size.height) / 2) withAttributes:attributes];
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    });
    return image;
}
static void DY778TryAvatar(UIImageView *view, NSArray *urls, NSUInteger index, DY778AvatarBindingState *state) {
    if (!view || objc_getAssociatedObject(view, &kDY778AvatarBinding) != state) return;
    if (index >= urls.count) { state.loading = NO; state.nextAttempt = NSDate.date.timeIntervalSince1970 + 30; return; }
    __weak UIImageView *weakView = view;
    [[DY778AvatarCache shared] load:urls[index] completion:^(UIImage *image) {
        UIImageView *live = weakView;
        if (!live || objc_getAssociatedObject(live, &kDY778AvatarBinding) != state) return;
        if (image) { live.image = image; state.loaded = YES; state.loading = NO; }
        else DY778TryAvatar(live, urls, index + 1, state);
    }];
}
void DY778LoadAvatarURLs(UIImageView *view, NSArray *candidates, NSString *identity) {
    if (!view) return;
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778LoadAvatarURLs(view, candidates, identity); }); return; }
    NSArray *urls = DY778AvatarURLs(candidates);
    NSString *binding = [NSString stringWithFormat:@"%@|%@", identity ?: @"", [urls componentsJoinedByString:@"|"]];
    DY778AvatarBindingState *state = objc_getAssociatedObject(view, &kDY778AvatarBinding);
    if ([state.binding isEqual:binding] && (state.loaded || state.loading || state.nextAttempt > NSDate.date.timeIntervalSince1970)) return;
    if (![state.binding isEqual:binding]) {
        BOOL samePerson = [state.binding hasPrefix:[(identity ?: @"") stringByAppendingString:@"|"]];
        state = [DY778AvatarBindingState new]; state.binding = binding;
        objc_setAssociatedObject(view, &kDY778AvatarBinding, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!samePerson) view.image = DY778AvatarPlaceholder(view);
    }
    if (!urls.count) return;
    state.loading = YES; DY778TryAvatar(view, urls, 0, state);
}
void DY778LoadAvatar(UIImageView *view, NSString *url, NSString *identity) { DY778LoadAvatarURLs(view, url.length ? @[url] : @[], identity); }
void DY778LoadCurrentAccountAvatar(UIImageView *view) {
    if (!view) return;
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778LoadCurrentAccountAvatar(view); }); return; }
    NSString *account = DY778CurrentAccountID() ?: @"";
    NSString *previous = objc_getAssociatedObject(view, &kDY778CurrentAvatarBinding);
    if (previous && ![previous isEqual:account]) objc_setAssociatedObject(view, &kDY778CurrentAvatarRetries, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDY778CurrentAvatarBinding, account, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!previous || ![previous isEqual:account]) DY778LoadAvatar(view, nil, account);
    __weak UIImageView *weakView = view;
    DY778GetCurrentAccountProfile(^(NSDictionary *profile) {
        UIImageView *live = weakView; if (!live || ![objc_getAssociatedObject(live, &kDY778CurrentAvatarBinding) isEqual:account]) return;
        DY778LoadAvatarURLs(live, profile[@"avatarURLs"] ?: @[profile[@"avatar"] ?: @""], account);
        NSUInteger retries = [objc_getAssociatedObject(live, &kDY778CurrentAvatarRetries) unsignedIntegerValue];
        if (![profile[@"avatar"] length] && retries < 2) {
            objc_setAssociatedObject(live, &kDY778CurrentAvatarRetries, @(retries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIImageView *retryView = weakView; if (retryView && retryView.window && [objc_getAssociatedObject(retryView, &kDY778CurrentAvatarBinding) isEqual:account]) DY778LoadCurrentAccountAvatar(retryView);
            });
        }
    });
}
