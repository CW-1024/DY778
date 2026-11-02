#import "DY778RecallMediaView.h"
#import "DY778RecallContent.h"
#import "DY778Core.h"
#import "DY778ArchiveNative.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>

static UIImage *DY778DecodePreview(NSData *data) {
    if (!data.length || data.length > 12 * 1024 * 1024) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL); if (!source) return nil;
    NSUInteger count = CGImageSourceGetCount(source); NSUInteger samples = MIN(count, (NSUInteger)40);
    NSMutableArray *frames = [NSMutableArray array]; double duration = 0;
    NSDictionary *options = @{(NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(count > 1 ? 320 : 1000),
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES};
    for (NSUInteger i = 0; i < samples; i++) {
        NSUInteger index = i * count / MAX(samples, 1u);
        CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, index, (__bridge CFDictionaryRef)options);
        if (!image) continue; [frames addObject:[UIImage imageWithCGImage:image]]; CGImageRelease(image);
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
        NSDictionary *gif = properties[(NSString *)kCGImagePropertyGIFDictionary];
        double delay = [gif[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] doubleValue];
        if (delay <= 0) delay = [gif[(NSString *)kCGImagePropertyGIFDelayTime] doubleValue];
        duration += MAX(.06, delay > 0 ? delay : .10) * count / MAX(samples, 1u);
    }
    CFRelease(source);
    return frames.count > 1 ? [UIImage animatedImageWithImages:frames duration:MAX(.1, duration)] : frames.firstObject;
}

@interface DY778PreviewLoader : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, copy) void (^completion)(UIImage *);
- (void)load:(NSURL *)url completion:(void (^)(UIImage *))completion;
- (void)cancel;
@end
@implementation DY778PreviewLoader
- (void)load:(NSURL *)url completion:(void (^)(UIImage *))completion {
    self.completion = completion; self.data = [NSMutableData data];
    if (url.isFileURL) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
            UIImage *image = [attributes fileSize] <= 12 * 1024 * 1024 ? DY778DecodePreview([NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil]) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{ if (self.completion) self.completion(image); self.completion = nil; });
        }); return;
    }
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 25;
    configuration.URLCache = nil; configuration.HTTPShouldSetCookies = NO;
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    self.task = [self.session dataTaskWithURL:url]; [self.task resume];
}
- (void)cancel { self.completion = nil; [self.task cancel]; [self.session invalidateAndCancel]; self.task = nil; self.session = nil; }
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    BOOL valid = ![response isKindOfClass:NSHTTPURLResponse.class] || ((NSHTTPURLResponse *)response).statusCode / 100 == 2;
    completion(valid && response.expectedContentLength <= 12 * 1024 * 1024 ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (self.data.length + data.length > 12 * 1024 * 1024) { [task cancel]; return; } [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    UIImage *image = error ? nil : DY778DecodePreview(self.data); self.data = nil;
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.completion) self.completion(image); self.completion = nil; });
    [session finishTasksAndInvalidate]; self.session = nil; self.task = nil;
}
@end

@interface DY778RecallMediaView ()
@property(nonatomic, strong) UIImageView *preview;
@property(nonatomic, strong) UIImageView *placeholder;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *detailLabel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *openButton;
@property(nonatomic, strong) UIButton *messageButton;
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) UIStackView *textStack;
@property(nonatomic, strong) NSLayoutConstraint *previewHeight;
@property(nonatomic, strong) NSLayoutConstraint *previewWidth;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) DY778PreviewLoader *loader;
@property(nonatomic, copy) NSDictionary *record;
@property(nonatomic, copy) NSDictionary *selectedMedia;
@property(nonatomic) BOOL originalAvailable;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, copy) NSArray<NSURL *> *previewURLs;
@property(nonatomic, copy) NSDictionary *displaySnapshot;
@property(nonatomic) BOOL messageFallback;
@property(nonatomic, strong) AVAssetImageGenerator *videoPreview;
@end
@implementation DY778RecallMediaView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = DY778CardBackground(); self.layer.cornerRadius = 16; self.layer.cornerCurve = kCACornerCurveContinuous; self.clipsToBounds = YES;
        _preview = [UIImageView new]; _preview.contentMode = UIViewContentModeScaleAspectFit; _preview.backgroundColor = [UIColor.secondarySystemFillColor colorWithAlphaComponent:.5]; _preview.tintColor = DY778Accent(); _preview.clipsToBounds = YES;
        _previewHeight = [_preview.heightAnchor constraintEqualToConstant:192]; _previewHeight.priority = 999; _previewHeight.active = YES;
        _previewWidth = [_preview.widthAnchor constraintEqualToConstant:94]; _previewWidth.priority = 999;
        _placeholder = [UIImageView new]; _placeholder.contentMode = UIViewContentModeScaleAspectFit; _placeholder.tintColor = DY778Accent(); _placeholder.translatesAutoresizingMaskIntoConstraints = NO; [_preview addSubview:_placeholder];
        [NSLayoutConstraint activateConstraints:@[[_placeholder.centerXAnchor constraintEqualToAnchor:_preview.centerXAnchor], [_placeholder.centerYAnchor constraintEqualToAnchor:_preview.centerYAnchor], [_placeholder.widthAnchor constraintEqualToConstant:32], [_placeholder.heightAnchor constraintEqualToConstant:32]]];
        _preview.userInteractionEnabled = YES; [_preview addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)]];
        _titleLabel = [UILabel new]; _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; _titleLabel.textColor = UIColor.labelColor; _titleLabel.numberOfLines = 3;
        _detailLabel = [UILabel new]; _detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; _detailLabel.textColor = UIColor.secondaryLabelColor; _detailLabel.numberOfLines = 2;
        _statusLabel = [UILabel new]; _statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; _statusLabel.textColor = UIColor.secondaryLabelColor; _statusLabel.numberOfLines = 0;
        _openButton = [UIButton buttonWithType:UIButtonTypeSystem]; _openButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; _openButton.tintColor = DY778Accent(); _openButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft; [_openButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES; [_openButton addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
        _openButton.titleLabel.numberOfLines = 2;
        _messageButton = [UIButton buttonWithType:UIButtonTypeSystem]; _messageButton.tintColor = DY778Accent();
        _messageButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft; _messageButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        [_messageButton setTitle:@"在聊天中查看 ›" forState:UIControlStateNormal]; [_messageButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [_messageButton addTarget:self action:@selector(openChat) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _detailLabel, _statusLabel, _openButton, _messageButton]]; _textStack = text; text.axis = UILayoutConstraintAxisVertical; text.spacing = 5; text.layoutMargins = UIEdgeInsetsMake(12, 14, 10, 14); text.layoutMarginsRelativeArrangement = YES;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_preview, text]]; _stack = stack; stack.axis = UILayoutConstraintAxisVertical; stack.translatesAutoresizingMaskIntoConstraints = NO; stack.layoutMarginsRelativeArrangement = YES; [self addSubview:stack];
        NSLayoutConstraint *bottom = [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]; bottom.priority = 999;
        [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor], [stack.topAnchor constraintEqualToAnchor:self.topAnchor], bottom]];
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; _spinner.translatesAutoresizingMaskIntoConstraints = NO; [_preview addSubview:_spinner];
        [NSLayoutConstraint activateConstraints:@[[_spinner.centerXAnchor constraintEqualToAnchor:_preview.centerXAnchor], [_spinner.centerYAnchor constraintEqualToAnchor:_preview.centerYAnchor]]];
    } return self;
}
- (void)dealloc { [self.loader cancel]; [self.videoPreview cancelAllCGImageGeneration]; }
- (void)cancel {
    [self.loader cancel]; self.loader = nil; [self.videoPreview cancelAllCGImageGeneration]; self.videoPreview = nil;
    ++self.generation; self.displaySnapshot = nil; self.record = nil; self.selectedMedia = nil; self.preview.image = nil; [self.spinner stopAnimating];
}
- (void)configureRecord:(NSDictionary *)record {
    NSMutableDictionary *enriched = [DY778RecallEnrichRecord(record) mutableCopy];
    NSArray *local = DY778ArchiveLocalMedia(enriched);
    if (local.count) enriched[@"media"] = [local arrayByAddingObjectsFromArray:enriched[@"media"] ?: @[]];
    self.record = enriched;
    NSDictionary *presentation = @{@"key": enriched[@"key"] ?: @"", @"media": enriched[@"media"] ?: @[], @"card": enriched[@"card"] ?: @{}, @"share": enriched[@"share"] ?: @{}, @"summary": DY778RecallSummary(enriched)};
    if ([self.displaySnapshot isEqual:presentation]) return;
    [self.loader cancel]; self.loader = nil; [self.videoPreview cancelAllCGImageGeneration]; self.videoPreview = nil; [self.spinner stopAnimating]; ++self.generation;
    NSData *snapshot = [NSJSONSerialization dataWithJSONObject:presentation options:0 error:nil];
    self.displaySnapshot = snapshot ? [NSJSONSerialization JSONObjectWithData:snapshot options:0 error:nil] : presentation;
    self.record = enriched; NSDictionary *card = self.record[@"card"];
    self.originalAvailable = DY778RecallWorkIdentifier(enriched).length > 0;
    BOOL work = self.originalAvailable || [card[@"kind"] isEqual:@"work"];
    self.stack.axis = work ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    self.stack.alignment = work ? UIStackViewAlignmentCenter : UIStackViewAlignmentFill;
    self.stack.spacing = work ? 12 : 0; self.stack.layoutMargins = work ? UIEdgeInsetsMake(12, 12, 12, 12) : UIEdgeInsetsZero;
    self.textStack.layoutMargins = work ? UIEdgeInsetsZero : UIEdgeInsetsMake(12, 14, 10, 14);
    self.previewWidth.active = work; self.previewHeight.constant = work ? 126 : 192;
    self.preview.layer.cornerRadius = work ? 10 : 0; self.preview.contentMode = work ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    NSString *title = self.record[@"share"][@"title"] ?: card[@"title"];
    self.titleLabel.text = work ? (title.length ? title : @"分享的作品") : DY778RecallSummary(self.record);
    NSString *author = [card[@"author"] length] ? card[@"author"] : self.record[@"share"][@"author"];
    self.detailLabel.text = [card[@"detail"] length] ? card[@"detail"] : author; self.detailLabel.hidden = !self.detailLabel.text.length;
    NSArray *candidates = DY778RecallPreviewCandidates(self.record);
    self.selectedMedia = DY778RecallPrimaryMedia(self.record);
    NSString *kind = [@[@"image", @"video", @"audio"] containsObject:card[@"kind"] ?: @""] ? card[@"kind"] : (self.selectedMedia[@"kind"] ?: card[@"kind"]);
    BOOL canLocate = DY778ArchiveCanLocate(self.record) && !work;
    BOOL availableLocal = NO;
    for (NSString *key in @[@"sourcePath", @"cachedPath"]) {
        NSString *path = self.selectedMedia[key];
        if ([path isKindOfClass:NSString.class] && [NSFileManager.defaultManager isReadableFileAtPath:path]) availableLocal = YES;
    }
    self.messageFallback = !work && (!self.selectedMedia || ([self.selectedMedia[@"encrypted"] boolValue] && !availableLocal));
    self.messageButton.hidden = !canLocate || self.messageFallback;
    NSString *symbol = [kind isEqual:@"audio"] ? @"waveform" : ([kind isEqual:@"video"] ? @"play.rectangle" : @"photo");
    self.preview.image = nil; self.placeholder.image = [UIImage systemImageNamed:work ? @"play.rectangle" : symbol]; self.placeholder.hidden = NO; self.preview.hidden = !work && !self.selectedMedia && !canLocate;
    [self.openButton setTitle:self.originalAvailable ? @"在抖音打开原作品 ›" : ([kind isEqual:@"video"] ? @"播放视频" : ([kind isEqual:@"audio"] ? @"播放语音" : ([kind isEqual:@"image"] ? @"查看图片" : @"查看附件"))) forState:UIControlStateNormal];
    if (self.messageFallback) [self.openButton setTitle:@"在聊天中查看 ›" forState:UIControlStateNormal];
    self.openButton.hidden = !self.originalAvailable && !self.selectedMedia && !canLocate;
    self.statusLabel.text = self.originalAvailable ? @"保留分享时的信息" : (work ? @"未取得原作品编号" : (self.selectedMedia ? @"" : @"已保留卡片信息"));
    if ([kind isEqual:@"audio"] && !work) {
        self.previewHeight.constant = 56; self.preview.hidden = NO; self.previewURLs = @[];
        NSString *path = self.selectedMedia[@"sourcePath"] ?: self.selectedMedia[@"cachedPath"];
        BOOL local = [path isKindOfClass:NSString.class] && [NSFileManager.defaultManager isReadableFileAtPath:path];
        self.statusLabel.text = local ? @"可播放抖音现有的本地音频" : (self.messageFallback ? @"点击定位原消息，在聊天中播放" : @"播放使用当前有效的音频地址");
        return;
    }
    NSMutableOrderedSet *urls = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *candidate in candidates) {
        for (NSString *key in @[@"sourcePath", @"cachedPath"]) {
            NSString *path = candidate[key]; NSString *resolved = [path isKindOfClass:NSString.class] ? path.stringByResolvingSymlinksInPath : nil;
            if ([resolved hasPrefix:[NSHomeDirectory().stringByResolvingSymlinksInPath stringByAppendingString:@"/"]] && [NSFileManager.defaultManager isReadableFileAtPath:resolved]) [urls addObject:[NSURL fileURLWithPath:resolved]];
        }
        NSURL *remote = [NSURL URLWithString:candidate[@"remoteURL"] ?: @""];
        if (![candidate[@"encrypted"] boolValue] && [@[@"https", @"http"] containsObject:remote.scheme.lowercaseString] && remote.host.length) [urls addObject:remote];
    }
    self.previewURLs = urls.array;
    if ([kind isEqual:@"video"] && availableLocal) {
        NSString *path = self.selectedMedia[@"sourcePath"] ?: self.selectedMedia[@"cachedPath"];
        self.videoPreview = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil]];
        self.videoPreview.appliesPreferredTrackTransform = YES; self.videoPreview.maximumSize = CGSizeMake(1000, 1000);
        NSUInteger generation = self.generation; __weak typeof(self) weakSelf = self;
        [self.spinner startAnimating]; self.placeholder.hidden = YES;
        [self.videoPreview generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:kCMTimeZero]] completionHandler:^(CMTime requested, CGImageRef image, CMTime actual, AVAssetImageGeneratorResult result, NSError *error) {
            UIImage *preview = image ? [UIImage imageWithCGImage:image] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) self = weakSelf; if (!self || self.generation != generation || ![self.record[@"account"] isEqual:DY778CurrentAccountID()]) return;
                self.videoPreview = nil;
                if (!preview) { [self loadPreviewAtIndex:0 generation:generation]; return; }
                self.preview.image = preview; self.placeholder.hidden = YES; [self.spinner stopAnimating]; self.statusLabel.text = @"视频预览 · 点按播放";
            });
        }];
    } else [self loadPreviewAtIndex:0 generation:self.generation];
}
- (void)loadPreviewAtIndex:(NSUInteger)index generation:(NSUInteger)generation {
    if (self.generation != generation) return;
    if (index >= self.previewURLs.count || index >= 12) {
        [self.spinner stopAnimating]; self.placeholder.hidden = NO;
        UIImage *nativeImage = DY778ArchivePreviewImage(self.record);
        if (nativeImage) { self.preview.image = nativeImage; self.placeholder.hidden = YES; self.statusLabel.text = @"聊天中的媒体预览"; return; }
        self.statusLabel.text = self.originalAvailable ? @"封面暂不可用 · 可打开原作品" : @"预览暂不可用 · 可在聊天中查看";
        if (!self.originalAvailable && [@[@"image", @"video"] containsObject:self.record[@"card"][@"kind"] ?: @""] && DY778ArchiveCanLocate(self.record)) {
            self.messageFallback = YES; self.messageButton.hidden = YES; [self.openButton setTitle:@"在聊天中查看 ›" forState:UIControlStateNormal];
        }
        return;
    }
    NSURL *url = self.previewURLs[index];
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@", self.record[@"account"] ?: @"", url.absoluteString];
    static NSCache *images; static dispatch_once_t once; dispatch_once(&once, ^{ images = [NSCache new]; images.totalCostLimit = 24 * 1024 * 1024; });
    UIImage *cached = [images objectForKey:cacheKey];
    if (cached) { self.preview.image = cached; self.placeholder.hidden = YES; [self.spinner stopAnimating]; self.statusLabel.text = self.originalAvailable ? @"保留分享时的信息" : @"已加载预览"; return; }
    [self.spinner startAnimating]; self.placeholder.hidden = YES;
    self.statusLabel.text = self.originalAvailable ? @"正在加载封面…" : @"正在加载预览…";
    self.loader = [DY778PreviewLoader new]; __weak typeof(self) weakSelf = self;
    [self.loader load:url completion:^(UIImage *loaded) {
        typeof(self) self = weakSelf; if (!self || self.generation != generation || ![self.record[@"account"] isEqual:DY778CurrentAccountID()]) return;
        if (!loaded) { [self loadPreviewAtIndex:index + 1 generation:generation]; return; }
        [images setObject:loaded forKey:cacheKey cost:(NSUInteger)(loaded.size.width * loaded.size.height * loaded.scale * loaded.scale * 4 * MAX(1, loaded.images.count))];
        [self.spinner stopAnimating]; self.preview.image = loaded; self.placeholder.hidden = YES;
        self.statusLabel.text = self.originalAvailable ? @"保留分享时的信息" : @"已加载预览";
    }];
}

- (void)openChat { if (self.openMessage) self.openMessage(); }
- (void)open {
    if (![self.record[@"account"] isEqual:DY778CurrentAccountID()]) { DY778Toast(@"账号已切换，请重新打开记录"); return; }
    if (self.originalAvailable && self.openOriginal) self.openOriginal();
    else if (self.messageFallback) [self openChat];
    else if (self.openMedia && self.selectedMedia) self.openMedia(self.selectedMedia);
}
@end

// 封面回退不修改宿主模型或播放器。
@interface DY778RecallCoverView ()
@property(nonatomic, strong) DY778PreviewLoader *loader;
@property(nonatomic, copy) NSArray *candidates;
@property(nonatomic, copy) NSString *recordKey;
@property(nonatomic) NSUInteger generation;
@end
@implementation DY778RecallCoverView
- (void)dealloc { [self.loader cancel]; }
- (void)cancel { [self.loader cancel]; self.loader = nil; self.generation++; self.recordKey = nil; self.candidates = nil; self.image = nil; }
- (void)configureRecord:(NSDictionary *)record {
    NSArray *candidates = DY778RecallPreviewCandidates(record);
    if ([self.recordKey isEqual:record[@"key"]] && [self.candidates isEqual:candidates]) return;
    [self cancel]; self.recordKey = record[@"key"]; self.candidates = candidates;
    self.contentMode = UIViewContentModeScaleAspectFill; self.clipsToBounds = YES; self.userInteractionEnabled = NO;
    [self loadCandidate:0 generation:self.generation];
}
- (void)loadCandidate:(NSUInteger)index generation:(NSUInteger)generation {
    if (generation != self.generation || index >= self.candidates.count || index >= 12) return;
    NSDictionary *candidate = self.candidates[index]; NSURL *url = nil;
    for (NSString *key in @[@"sourcePath", @"cachedPath"]) {
        NSString *path = candidate[key]; NSString *resolved = [path isKindOfClass:NSString.class] ? path.stringByResolvingSymlinksInPath : nil;
        if ([resolved hasPrefix:[NSHomeDirectory().stringByResolvingSymlinksInPath stringByAppendingString:@"/"]] && [NSFileManager.defaultManager isReadableFileAtPath:resolved]) { url = [NSURL fileURLWithPath:resolved]; break; }
    }
    if (!url && ![candidate[@"encrypted"] boolValue]) { NSURL *remote = [NSURL URLWithString:candidate[@"remoteURL"] ?: @""]; if ([@[@"https", @"http"] containsObject:remote.scheme.lowercaseString] && remote.host.length) url = remote; }
    if (!url) { [self loadCandidate:index + 1 generation:generation]; return; }
    self.loader = [DY778PreviewLoader new]; __weak typeof(self) weakSelf = self;
    [self.loader load:url completion:^(UIImage *image) {
        typeof(self) self = weakSelf; if (!self || self.generation != generation || !self.superview) return;
        if (image) self.image = image; else [self loadCandidate:index + 1 generation:generation];
    }];
}
@end
