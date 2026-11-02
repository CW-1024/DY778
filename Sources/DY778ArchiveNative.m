#import "DY778ArchiveNative.h"
#import "DY778Core.h"
#import "DY778RecallContent.h"
#import "DY778ArchivePolicy.h"
#import <ImageIO/ImageIO.h>

static id DY778NativeInvoke(id target, NSString *name, NSArray *arguments) {
    SEL selector = NSSelectorFromString(name);
    if (![target respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != arguments.count + 2) return nil;
    const char result = signature.methodReturnType[0];
    if (!strchr("@vBcqQ", result)) return nil;
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target; invocation.selector = selector;
    for (NSUInteger index = 0; index < arguments.count; index++) {
        id value = arguments[index] == NSNull.null ? nil : arguments[index];
        const char type = [signature getArgumentTypeAtIndex:index + 2][0];
        if (type == '@' || type == '#') [invocation setArgument:&value atIndex:index + 2];
        else if (type == 'Q' || type == 'q' || type == 'B' || type == 'c') { long long number = [value longLongValue]; [invocation setArgument:&number atIndex:index + 2]; }
        else return nil;
    }
    @try {
        [invocation invoke];
        if (result == 'v') return @YES;
        if (result == '@') { __unsafe_unretained id value = nil; [invocation getReturnValue:&value]; return value; }
        if (result == 'B' || result == 'c') { BOOL value = NO; [invocation getReturnValue:&value]; return @(value); }
        long long value = 0; [invocation getReturnValue:&value]; return @(value);
    } @catch (__unused NSException *exception) { return nil; }
}
static id DY778IMService(void) {
    id center = DY778NativeInvoke(NSClassFromString(@"HTSServiceCenter"), @"defaultCenter", @[]);
    Class cls = NSClassFromString(@"AWEIMModuleService");
    id service = cls ? DY778NativeInvoke(center, @"getService:", @[cls]) : nil;
    Protocol *protocol = NSProtocolFromString(@"AWEIMModuleService");
    return service ?: (protocol ? DY778NativeInvoke(center, @"getProtocolService:", @[protocol]) : nil);
}
static NSString *DY778NativeString(id object, NSArray *fields) {
    for (NSString *field in fields) {
        NSString *value = DY778Identifier(DY778Read(object, field));
        if (value.length && ![value isEqual:@"0"]) return value;
    }
    return @"";
}
BOOL DY778ArchiveCanLocate(NSDictionary *record) {
    return [record[@"account"] length] && [record[@"conversation"] length] &&
        (DY778NativeString(record, @[@"messageID", @"serverID"]).length > 0);
}
static BOOL DY778NativeMatches(id message, NSDictionary *record) {
    if (!message || ![record[@"account"] isEqual:DY778CurrentAccountID()]) return NO;
    NSString *conversation = DY778NativeString(message, @[@"belongingConversationIdentifier", @"conversationID"]);
    if (![conversation isEqual:record[@"conversation"]]) return NO;
    NSString *client = DY778NativeString(message, @[@"identifier", @"messageID"]);
    NSString *server = DY778NativeString(message, @[@"serverMessageID"]);
    return DY778ArchiveIdentityMatches([record[@"account"] UTF8String], DY778CurrentAccountID().UTF8String,
        [record[@"conversation"] UTF8String], conversation.UTF8String, [DY778Identifier(record[@"messageID"]) UTF8String], client.UTF8String,
        [DY778Identifier(record[@"serverID"]) UTF8String], server.UTF8String);
}
static id DY778NativeVM(UITableViewCell *cell) {
    return DY778Read(DY778Read(cell, @"currentContext"), @"messageViewModel") ?: DY778Read(cell, @"viewModel");
}
static BOOL DY778NativeVMMatches(id vm, NSDictionary *record) {
    return DY778NativeMatches(DY778Read(vm, @"iesMessage"), record) || DY778NativeMatches(DY778Read(vm, @"message"), record);
}
static UIViewController *DY778NativeList(UIViewController *controller, NSString *conversation, NSUInteger depth) {
    if (!controller || depth > 14) return nil;
    if ([controller isKindOfClass:NSClassFromString(@"AWEIMMessageListViewController")] &&
        [DY778NativeString(DY778Read(controller, @"conversation"), @[@"conversationID"]) isEqual:conversation]) return controller;
    for (UIViewController *child in controller.childViewControllers.reverseObjectEnumerator) {
        UIViewController *found = DY778NativeList(child, conversation, depth + 1); if (found) return found;
    }
    return DY778NativeList(controller.presentedViewController, conversation, depth + 1);
}
static id DY778NativeMessage(NSDictionary *record, id *model) {
    if (!DY778ArchiveCanLocate(record) || ![record[@"account"] isEqual:DY778CurrentAccountID()]) return nil;
    UIViewController *list = DY778NativeList(DY778ActiveWindow().rootViewController, record[@"conversation"], 0);
    UITableView *table = DY778Read(list, @"tableView");
    if ([table isKindOfClass:UITableView.class]) for (UITableViewCell *cell in table.visibleCells) {
        id vm = DY778NativeVM(cell);
        if (DY778NativeVMMatches(vm, record)) { if (model) *model = vm; return DY778Read(vm, @"message"); }
    }
    id listModel = DY778Read(list, @"listViewModel");
    for (NSString *identifier in @[DY778NativeString(record, @[@"messageID"]), DY778NativeString(record, @[@"serverID"])]) {
        if (!identifier.length) continue;
        id index = DY778NativeInvoke(listModel, @"indexPathOfMsgWithMsgID:", @[identifier]);
        if (![index isKindOfClass:NSIndexPath.class]) continue;
        id vm = DY778NativeInvoke(listModel, @"messageViewModelAtIndexPath:", @[index]);
        if (DY778NativeVMMatches(vm, record)) { if (model) *model = vm; return DY778Read(vm, @"message"); }
    }
    return nil;
}
static NSString *DY778NativePath(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length]) return nil;
    NSString *path = value;
    if ([path hasPrefix:@"file://"]) path = [NSURL URLWithString:path].path;
    if (!path.isAbsolutePath) path = [NSHomeDirectory() stringByAppendingPathComponent:path];
    path = path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    if (![path hasPrefix:[NSHomeDirectory().stringByResolvingSymlinksInPath stringByAppendingString:@"/"]]) return nil;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    return [attributes[NSFileType] isEqual:NSFileTypeRegular] && [attributes fileSize] > 0 &&
        [NSFileManager.defaultManager isReadableFileAtPath:path] ? path : nil;
}
static void DY778NativeAddMedia(NSMutableArray *media, id value, NSString *kind) {
    if (!kind.length) return;
    NSString *path = DY778NativePath(value); if (!path) return;
    for (NSDictionary *item in media) if ([item[@"sourcePath"] isEqual:path]) return;
    CGImageSourceRef image = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    BOOL isImage = image && CGImageSourceGetCount(image) > 0; if (image) CFRelease(image);
    if ([kind isEqual:@"image"] && !isImage) return;
    NSString *actualKind = isImage ? @"image" : kind;
    [media addObject:@{@"kind": actualKind, @"sourcePath": path, @"quality": @1000, @"native": @YES,
        @"cover": @([kind isEqual:@"video"] && isImage), @"name": isImage ? @"本地图片" : @"本地媒体"}];
}
NSArray<NSDictionary *> *DY778ArchiveLocalMedia(NSDictionary *record) {
    if (!NSThread.isMainThread || ![record[@"account"] isEqual:DY778CurrentAccountID()]) return @[];
    NSString *kind = DY778RecallEnrichRecord(record)[@"card"][@"kind"];
    if (![@[@"image", @"video", @"audio"] containsObject:kind ?: @""]) return @[];
    id vm = nil, message = DY778NativeMessage(record, &vm); if (!message) return @[];
    NSMutableArray *media = [NSMutableArray array];
    DY778NativeAddMedia(media, DY778Read(message, @"filePath"), kind);
    id paths = DY778Read(message, @"awe_filePathDictionary");
    if ([paths isKindOfClass:NSDictionary.class] && [paths count] <= 24)
        for (id value in [paths allValues]) DY778NativeAddMedia(media, value, kind);
    if ([kind isEqual:@"image"]) for (NSString *field in @[@"cachedImageAttachmentFileAbsolutePath", @"imageAttachmentFileAbsolutePath"])
        DY778NativeAddMedia(media, DY778Read(vm, field), kind);
    id download = DY778Read(vm, [kind isEqual:@"image"] ? @"imageDownloadVM" : @"downloadVM");
    if (DY778NativeMatches(download, record)) DY778NativeAddMedia(media, DY778Read(download, @"localFilePath"), kind);
    return [record[@"account"] isEqual:DY778CurrentAccountID()] ? media : @[];
}
UIImage *DY778ArchivePreviewImage(NSDictionary *record) {
    if (!NSThread.isMainThread || ![record[@"account"] isEqual:DY778CurrentAccountID()]) return nil;
    NSString *kind = DY778RecallEnrichRecord(record)[@"card"][@"kind"];
    if (![@[@"image", @"video"] containsObject:kind ?: @""]) return nil;
    id vm = nil, message = DY778NativeMessage(record, &vm);
    for (id image in @[DY778Read(vm, @"cachedImage") ?: NSNull.null, DY778Read(message, @"forwardPreviewImage") ?: NSNull.null])
        if ([image isKindOfClass:UIImage.class]) return image;
    return nil;
}

@interface DY778ArchiveLocator : NSObject
@property(nonatomic, copy) NSDictionary *record;
@property(nonatomic, weak) UIViewController *list;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) UIView *highlight;
@property(nonatomic, weak) UITableViewCell *highlightedCell;
@property(nonatomic) NSTimeInterval deadline;
@property(nonatomic) NSUInteger scrollAttempts;
@property(nonatomic) NSTimeInterval lastScrollRequest;
@property(nonatomic) BOOL centered;
@property(nonatomic) BOOL arrived;
@property(nonatomic) NSTimeInterval settleAfter;
- (void)beginFrom:(UIViewController *)source;
- (void)finish:(NSString *)message;
@end
static DY778ArchiveLocator *DY778ActiveLocator;
@implementation DY778ArchiveLocator
- (void)finish:(NSString *)message {
    [self.timer invalidate]; self.timer = nil; [self.highlight.layer removeAllAnimations]; [self.highlight removeFromSuperview]; self.highlight = nil;
    DY778DismissToast(@"archive-location"); if (message.length) DY778Toast(message);
    if (DY778ActiveLocator == self) DY778ActiveLocator = nil;
}
- (void)beginFrom:(UIViewController *)source {
    [source.view endEditing:YES];
    UINavigationController *navigation = source.navigationController;
    __weak typeof(self) weakSelf = self;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backgrounded) name:UIApplicationDidEnterBackgroundNotification object:nil];
    dispatch_block_t navigate = ^{
        typeof(self) self = weakSelf; if (!self || self != DY778ActiveLocator) return;
        if (![self.record[@"account"] isEqual:DY778CurrentAccountID()]) { [self finish:@"账号已切换，请重新打开记录"]; return; }
        UIViewController *top = DY778TopController();
        UIViewController *list = DY778NativeList(top, self.record[@"conversation"], 0);
        if (!list) {
            id service = DY778IMService();
            id conversation = DY778NativeInvoke(service, @"imMessageConversationWithConversationID:", @[self.record[@"conversation"]]);
            id type = DY778Read(conversation, @"type");
            if (!top || !type || ![DY778NativeString(conversation, @[@"conversationID"]) isEqual:self.record[@"conversation"]] ||
                !DY778NativeInvoke(service, @"transferToMessageVCWithConversationID:conversationType:fromVC:extension:completion:",
                    @[self.record[@"conversation"], type, top, @{}, ^{}])) {
                [self finish:@"暂时无法打开原会话，记录仍然保留"]; return;
            }
        }
        self.deadline = NSDate.timeIntervalSinceReferenceDate + 10;
        self.settleAfter = NSDate.timeIntervalSinceReferenceDate + .5;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
        DY778ShowToast(@"archive-location", @"正在定位原消息…", YES, NO);
        [self tick:self.timer];
    };
    if ([navigation isKindOfClass:NSClassFromString(@"DY778NavigationController")]) {
        if (navigation.presentingViewController) [navigation dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:navigate];
        else navigate();
    } else if (source.presentingViewController) [source dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:navigate];
    else navigate();
}
- (void)tick:(NSTimer *)timer {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { [self finish:nil]; return; }
    if (![self.record[@"account"] isEqual:DY778CurrentAccountID()]) { [self finish:@"账号已切换，已停止定位"]; return; }
    UIViewController *list = DY778NativeList(DY778TopController(), self.record[@"conversation"], 0);
    if (self.arrived && self.list != list) { [self finish:nil]; return; }
    if (list) { self.list = list; self.arrived = YES; }
    UITableView *table = DY778Read(list, @"tableView");
    if ([table isKindOfClass:UITableView.class] && (table.dragging || table.tracking)) { [self finish:nil]; return; }
    if (self.highlight) {
        if (!self.highlightedCell.window || !DY778NativeVMMatches(DY778NativeVM(self.highlightedCell), self.record)) [self finish:nil];
        return;
    }
    if (NSDate.timeIntervalSinceReferenceDate >= self.deadline) { [self finish:@"未能定位原消息，它可能已从本机聊天记录中移除"]; return; }
    if (!list || ![table isKindOfClass:UITableView.class] || !list.view.window || list.transitionCoordinator || NSDate.timeIntervalSinceReferenceDate < self.settleAfter) return;
    id model = DY778Read(list, @"listViewModel");
    NSArray *identifiers = @[DY778NativeString(self.record, @[@"messageID"]), DY778NativeString(self.record, @[@"serverID"])];
    NSIndexPath *index = nil;
    for (NSString *candidate in identifiers) {
        if (!candidate.length) continue;
        NSIndexPath *found = DY778NativeInvoke(model, @"indexPathOfMsgWithMsgID:", @[candidate]);
        if (![found isKindOfClass:NSIndexPath.class]) continue;
        id targetVM = DY778NativeInvoke(model, @"messageViewModelAtIndexPath:", @[found]);
        if (DY778NativeVMMatches(targetVM, self.record) && found.section < table.numberOfSections && found.row < [table numberOfRowsInSection:found.section]) {
            index = found; break;
        }
    }
    if (index) {
        if (!self.centered) {
            self.centered = YES; self.settleAfter = NSDate.timeIntervalSinceReferenceDate + .45;
            [table scrollToRowAtIndexPath:index atScrollPosition:UITableViewScrollPositionMiddle animated:!UIAccessibilityIsReduceMotionEnabled()]; return;
        }
    } else if (self.scrollAttempts < 2 && NSDate.timeIntervalSinceReferenceDate - self.lastScrollRequest > 2.5) {
        self.lastScrollRequest = NSDate.timeIntervalSinceReferenceDate;
        NSString *identifier = identifiers[self.scrollAttempts++];
        if (!identifier.length) identifier = DY778NativeString(self.record, @[@"messageID", @"serverID"]);
        id data = DY778Read(list, @"listDataService");
        if (![data respondsToSelector:NSSelectorFromString(@"scrollToMessageLocationIfNeedWithMessageID:completion:")]) {
            id components = DY778Read(DY778Read(list, @"componentCenter"), @"components");
            if ([components isKindOfClass:NSArray.class]) for (id component in components)
                if ([component isKindOfClass:NSClassFromString(@"AWEIMMessageListDataComponent")]) { data = component; break; }
        }
        BOOL requested = DY778NativeInvoke(data, @"scrollToMessageLocationIfNeedWithMessageID:completion:", @[identifier, ^{}]) != nil;
        if (!requested) {
            id conversation = DY778Read(list, @"conversation");
            if (conversation) DY778NativeInvoke(DY778IMService(), @"scrollToMessageID:inConversation:completion:", @[identifier, conversation, ^{}]);
        }
    }
    if (table.decelerating || [DY778Read(list, @"scrollInProcess") boolValue] || NSDate.timeIntervalSinceReferenceDate < self.settleAfter) return;
    for (UITableViewCell *cell in table.visibleCells) {
        if (!DY778NativeVMMatches(DY778NativeVM(cell), self.record)) continue;
        if (!self.centered) {
            NSIndexPath *visibleIndex = [table indexPathForCell:cell];
            if (!visibleIndex) continue;
            self.centered = YES; self.settleAfter = NSDate.timeIntervalSinceReferenceDate + .45;
            [table scrollToRowAtIndexPath:visibleIndex atScrollPosition:UITableViewScrollPositionMiddle animated:!UIAccessibilityIsReduceMotionEnabled()]; return;
        }
        [self highlightCell:cell]; return;
    }
}
- (void)backgrounded { [self finish:nil]; }
- (void)highlightCell:(UITableViewCell *)cell {
    DY778DismissToast(@"archive-location");
    UIView *highlight = [[UIView alloc] initWithFrame:cell.bounds]; highlight.userInteractionEnabled = NO;
    highlight.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    highlight.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:.13]; highlight.alpha = 0;
    [cell addSubview:highlight]; self.highlight = highlight; self.highlightedCell = cell;
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"已定位到撤回的原消息");
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : .18 animations:^{ highlight.alpha = 1; } completion:^(BOOL finished) {
        if (weakSelf.highlight != highlight) return;
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : .55 delay:1.6 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{ highlight.alpha = 0; } completion:^(BOOL ended) { [weakSelf finish:nil]; }];
    }];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; [self.timer invalidate]; [self.highlight removeFromSuperview]; }
@end
void DY778ArchiveCellWillReuse(UITableViewCell *cell) {
    if (DY778ActiveLocator.highlightedCell == cell) [DY778ActiveLocator finish:nil];
}
void DY778ArchiveLocateMessage(UIViewController *source, NSDictionary *record) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778ArchiveLocateMessage(source, record); }); return; }
    if (!DY778ArchiveCanLocate(record)) { DY778Toast(@"这条旧记录缺少原消息编号，无法准确定位"); return; }
    if (![record[@"account"] isEqual:DY778CurrentAccountID()]) { DY778Toast(@"账号已切换，请重新打开记录"); return; }
    if (DY778ActiveLocator && [DY778ActiveLocator.record isEqual:record]) return;
    [DY778ActiveLocator finish:nil];
    DY778ActiveLocator = [DY778ArchiveLocator new]; DY778ActiveLocator.record = record;
    [DY778ActiveLocator beginFrom:source ?: DY778TopController()];
}
