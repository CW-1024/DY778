#import "DY778RadarUI.h"
#import <ImageIO/ImageIO.h>
@interface DY778RadarAvatarRequest : NSObject
@property(nonatomic, copy) NSString *url;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, strong) NSMutableDictionary<NSString *, void (^)(UIImage *)> *listeners;
@end
@implementation DY778RadarAvatarRequest
@end
@interface DY778RadarAvatarLoader : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *cache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, DY778RadarAvatarRequest *> *requests;
+ (instancetype)shared;
- (NSString *)load:(NSString *)url reply:(void (^)(UIImage *))reply;
- (void)cancel:(NSString *)token;
@end
@implementation DY778RadarAvatarLoader
+ (instancetype)shared { static id loader; static dispatch_once_t once; dispatch_once(&once, ^{ loader = [self new]; }); return loader; }
- (instancetype)init {
    if ((self = [super init])) {
        _cache = [NSCache new]; _cache.totalCostLimit = 4 * 1024 * 1024; _cache.countLimit = 80;
        _requests = [NSMutableDictionary dictionary];
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.URLCache = nil; config.HTTPCookieStorage = nil; config.HTTPShouldSetCookies = NO;
        config.URLCredentialStorage = nil; config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15;
        config.HTTPMaximumConnectionsPerHost = 3;
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stop) name:UIApplicationWillResignActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(clear) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}
- (void)clear { [self.cache removeAllObjects]; }
- (NSString *)load:(NSString *)text reply:(void (^)(UIImage *))reply {
    NSURL *url = [NSURL URLWithString:text];
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || ![url.scheme isEqual:@"https"] || !url.host.length) { reply(nil); return nil; }
    UIImage *cached = [self.cache objectForKey:text]; if (cached) { reply(cached); return nil; }
    DY778RadarAvatarRequest *r = self.requests[text];
    if (!r) { r = [DY778RadarAvatarRequest new]; r.url = text; r.listeners = [NSMutableDictionary dictionary]; self.requests[text] = r; }
    NSString *token = NSUUID.UUID.UUIDString; r.listeners[token] = [reply copy];
    [self pump]; return token;
}
- (void)pump {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSUInteger active = 0; for (DY778RadarAvatarRequest *r in self.requests.allValues) if (r.task) active++;
    for (DY778RadarAvatarRequest *r in self.requests.allValues) {
        if (active >= 3) break;
        if (r.task || !r.listeners.count) continue;
        r.data = [NSMutableData data]; r.task = [self.session dataTaskWithURL:[NSURL URLWithString:r.url]];
        r.task.taskDescription = r.url; [r.task resume]; active++;
    }
}
- (void)cancel:(NSString *)token {
    if (!token.length) return;
    for (DY778RadarAvatarRequest *r in self.requests.allValues) if (r.listeners[token]) {
        [r.listeners removeObjectForKey:token];
        if (!r.listeners.count) { [r.task cancel]; [self.requests removeObjectForKey:r.url]; [self pump]; }
        break;
    }
}
- (void)finish:(DY778RadarAvatarRequest *)r image:(UIImage *)image {
    if (self.requests[r.url] != r) return;
    NSArray *listeners = r.listeners.allValues; [self.requests removeObjectForKey:r.url];
    if (image) [self.cache setObject:image forKey:r.url cost:128 * 128 * 4];
    for (void (^reply)(UIImage *) in listeners) reply(image);
    [self pump];
}
- (void)stop {
    NSArray *pending = self.requests.allValues; [self.requests removeAllObjects];
    for (DY778RadarAvatarRequest *r in pending) { [r.task cancel]; for (void (^reply)(UIImage *) in r.listeners.allValues) reply(nil); }
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    DY778RadarAvatarRequest *r = self.requests[task.taskDescription];
    BOOL valid = r.task == task && [(NSHTTPURLResponse *)response statusCode] == 200 &&
        [response.MIMEType hasPrefix:@"image/"] && response.expectedContentLength <= 2 * 1024 * 1024;
    completion(valid ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    DY778RadarAvatarRequest *r = self.requests[task.taskDescription]; if (r.task != task) return;
    if (r.data.length + data.length > 2 * 1024 * 1024) { [task cancel]; [self finish:r image:nil]; return; }
    [r.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    DY778RadarAvatarRequest *r = self.requests[task.taskDescription]; if (r.task != task) return;
    if (error || !r.data.length) { [self finish:r image:nil]; return; }
    NSData *data = r.data; r.data = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        CGImageRef thumbnail = source ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
            (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
            (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
            (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @128}) : NULL;
        UIImage *image = thumbnail ? [UIImage imageWithCGImage:thumbnail] : nil;
        if (thumbnail) CGImageRelease(thumbnail); if (source) CFRelease(source);
        dispatch_async(dispatch_get_main_queue(), ^{ [self finish:r image:image]; });
    });
}
@end
@interface DY778RadarAvatarCell : UITableViewCell
@property(nonatomic, copy) NSString *avatarURL;
@property(nonatomic, copy) NSString *loadToken;
@property(nonatomic) BOOL hasAvatar;
- (void)loadAvatar;
@end
@implementation DY778RadarAvatarCell
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(loadAvatar) name:UIApplicationDidBecomeActiveNotification object:nil];
        [self loadAvatar];
    } else { [DY778RadarAvatarLoader.shared cancel:self.loadToken]; self.loadToken = nil; [NSNotificationCenter.defaultCenter removeObserver:self]; }
}
- (void)loadAvatar {
    if (!self.window || self.hasAvatar || self.loadToken || !self.avatarURL.length) return;
    __weak typeof(self) weakSelf = self;
    self.loadToken = [DY778RadarAvatarLoader.shared load:self.avatarURL reply:^(UIImage *image) {
        typeof(self) self = weakSelf; if (!self) return; self.loadToken = nil;
        if (!image || !self.window) return;
        self.hasAvatar = YES;
        UIListContentConfiguration *config = [(UIListContentConfiguration *)self.contentConfiguration copy];
        config.image = image; config.imageProperties.tintColor = nil; self.contentConfiguration = config;
    }];
}
- (void)dealloc { [DY778RadarAvatarLoader.shared cancel:self.loadToken]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
UITableViewCell *DY778RadarPersonCell(NSDictionary *person, NSString *subtitle, BOOL disclosure) {
    DY778RadarAvatarCell *cell = [[DY778RadarAvatarCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UITableViewCell *template = DY778RadarCell(DY778RadarDisplayName(person), subtitle, @"person.crop.circle.fill", disclosure);
    UIListContentConfiguration *config = [(UIListContentConfiguration *)template.contentConfiguration copy];
    config.imageProperties.maximumSize = CGSizeMake(46, 46); config.imageProperties.reservedLayoutSize = CGSizeMake(46, 46);
    config.imageProperties.cornerRadius = 23;
    cell.contentConfiguration = config; cell.backgroundColor = template.backgroundColor;
    cell.accessoryType = template.accessoryType; cell.avatarURL = DY778RadarString(person[@"avatar"]);
    return cell;
}
