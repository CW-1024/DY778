#import "DY778RecallNotifications.h"
#import "DY778Recall.h"
#import "DY778EditHistory.h"
#import <UserNotifications/UserNotifications.h>
#import <CommonCrypto/CommonDigest.h>
#import <QuartzCore/QuartzCore.h>

static BOOL DY778NoticeAccountTransition;
static NSString *const DY778RecallRequestPrefix = @"DY778.Recall.";
static NSString *const DY778EditRequestPrefix = @"DY778.Edit.";
static BOOL DY778NoticeIsEdit(NSDictionary *record) { return [record[@"noticeKind"] isEqual:@"edit"]; }
static NSString *DY778NoticeKind(NSDictionary *record) { return DY778NoticeIsEdit(record) ? @"edit" : @"recall"; }
static NSString *DY778NoticePrefix(NSDictionary *record) { return DY778NoticeIsEdit(record) ? DY778EditRequestPrefix : DY778RecallRequestPrefix; }
static NSString *DY778NoticeDigest(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding]; unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest); NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [text appendFormat:@"%02x", digest[i]];
    return text;
}
static NSString *DY778NoticeString(NSDictionary *record, NSString *key) {
    return [record[key] isKindOfClass:NSString.class] ? record[key] : @"";
}
static NSString *DY778MessageNoticeTitle(NSDictionary *record) {
    NSString *name = DY778NoticeString(record, @"senderName");
    if (!name.length) name = DY778NoticeString(record, @"conversationName");
    if (!name.length) name = @"对方";
    if (name.length > 40) name = [[name substringToIndex:40] stringByAppendingString:@"…"];
    return [name stringByAppendingString:DY778NoticeIsEdit(record) ? @" 编辑了一条消息" : @" 撤回了一条消息"];
}
static NSString *DY778MessageNoticeBody(NSDictionary *record) {
    BOOL edit = DY778NoticeIsEdit(record);
    if (!edit && ![record[@"available"] boolValue]) return @"已记录撤回事件，未取得原始内容。";
    NSString *summary = DY778NoticeString(record, @"summary");
    if (!DY778Bool(edit ? @"edit.notificationPreview" : @"recall.notificationPreview") || !summary.length) return edit ? @"新的编辑版本已留存，点按查看该条消息的历史。" : @"消息内容已留存，点按查看。";
    return summary.length > 180 ? [[summary substringToIndex:180] stringByAppendingString:@"…"] : summary;
}
static BOOL DY778MessageNoticeAllowed(NSDictionary *record) {
    NSString *account = DY778NoticeString(record, @"account"), *conversation = DY778NoticeString(record, @"conversation");
    BOOL edit = DY778NoticeIsEdit(record);
    return !DY778NoticeAccountTransition && DY778Bool(edit ? @"edit.notifications" : @"recall.notifications") && account.length && [account isEqual:DY778CurrentAccountID()] &&
        conversation.length && (edit ? DY778EditEnabledForConversation(conversation) : DY778RecallEnabledForConversation(conversation));
}
static void DY778OpenMessageNoticeWhenReady(NSDictionary *record, NSUInteger attempts) {
    if (attempts && (DY778NoticeAccountTransition || UIApplication.sharedApplication.applicationState != UIApplicationStateActive || !DY778TopController() || !DY778CurrentAccountID().length)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DY778OpenMessageNoticeWhenReady(record, attempts - 1); });
        return;
    }
    if (DY778NoticeAccountTransition || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (![DY778NoticeString(record, @"account") isEqual:DY778CurrentAccountID()]) {
        DY778Toast(@"这条提醒属于另一个账号，请切换后查看"); return;
    }
    NSString *conversation = DY778NoticeString(record, @"conversation");
    if (!conversation.length) return;
    if (DY778NoticeIsEdit(record)) DY778PresentEditHistory(DY778TopController(), conversation, DY778NoticeString(record, @"key"));
    else DY778PresentRecallArchive(DY778TopController(), conversation);
}
static void DY778OpenMessageNotice(NSDictionary *record) { DY778OpenMessageNoticeWhenReady(record, 10); }

@interface DY778NoticeDeliveryLease : NSObject
@property(nonatomic) UIBackgroundTaskIdentifier identifier;
- (void)finish;
@end
@implementation DY778NoticeDeliveryLease
- (instancetype)init {
    if ((self = [super init])) {
        _identifier = UIBackgroundTaskInvalid;
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
            __weak typeof(self) weakSelf = self;
            _identifier = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"DY778.RecallNotice" expirationHandler:^{ [weakSelf finish]; }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [weakSelf finish]; });
        }
    }
    return self;
}
- (void)finish {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self finish]; }); return; }
    UIBackgroundTaskIdentifier identifier = self.identifier; self.identifier = UIBackgroundTaskInvalid;
    if (identifier != UIBackgroundTaskInvalid) [UIApplication.sharedApplication endBackgroundTask:identifier];
}
- (void)dealloc {
    UIBackgroundTaskIdentifier identifier = _identifier;
    if (identifier != UIBackgroundTaskInvalid) dispatch_async(dispatch_get_main_queue(), ^{ [UIApplication.sharedApplication endBackgroundTask:identifier]; });
}
@end

@interface DY778MessageBanner : UIControl <UIGestureRecognizerDelegate>
@property(nonatomic, copy) NSDictionary *record;
@property(nonatomic, strong) NSURLSessionDataTask *avatarTask;
@property(nonatomic, strong) UIImageView *portrait;
- (instancetype)initWithRecord:(NSDictionary *)record;
- (void)close;
@end
@implementation DY778MessageBanner
- (instancetype)initWithRecord:(NSDictionary *)record {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.record = record; self.overrideUserInterfaceStyle = DY778InterfaceStyle();
        self.translatesAutoresizingMaskIntoConstraints = NO; self.backgroundColor = DY778CardBackground();
        self.layer.cornerRadius = 21; self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = UIColor.blackColor.CGColor; self.layer.shadowOpacity = .2;
        self.layer.shadowRadius = 18; self.layer.shadowOffset = CGSizeMake(0, 5);
        self.layer.borderWidth = .75; self.layer.borderColor = [DY778Accent() resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        self.accessibilityIdentifier = DY778NoticeIsEdit(record) ? @"DY778.EditBanner" : @"DY778.RecallBanner";
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)];
        tap.delegate = self; tap.cancelsTouchesInView = NO; [self addGestureRecognizer:tap];
        _portrait = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:DY778NoticeIsEdit(record) ? @"pencil.circle.fill" : @"arrow.uturn.backward.circle.fill"]];
        _portrait.tintColor = DY778Accent(); _portrait.contentMode = UIViewContentModeScaleAspectFill;
        _portrait.backgroundColor = [DY778Accent() colorWithAlphaComponent:.1]; _portrait.layer.cornerRadius = 23; _portrait.clipsToBounds = YES;
        [_portrait.widthAnchor constraintEqualToConstant:46].active = YES; [_portrait.heightAnchor constraintEqualToConstant:46].active = YES;
        UILabel *eyebrow = [UILabel new]; eyebrow.text = DY778NoticeIsEdit(record) ? @"DY778 · 编辑提醒" : @"DY778 · 撤回提醒"; eyebrow.textColor = DY778Accent();
        eyebrow.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2]; eyebrow.adjustsFontForContentSizeCategory = YES;
        UILabel *title = [UILabel new]; title.text = DY778MessageNoticeTitle(record); title.numberOfLines = 2;
        title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; title.adjustsFontForContentSizeCategory = YES; title.textColor = UIColor.labelColor;
        UILabel *body = [UILabel new]; body.text = DY778MessageNoticeBody(record); body.numberOfLines = 2;
        body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; body.adjustsFontForContentSizeCategory = YES; body.textColor = UIColor.secondaryLabelColor;
        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[eyebrow, title, body]]; text.axis = UILayoutConstraintAxisVertical; text.spacing = 4; text.userInteractionEnabled = NO;
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        close.tintColor = UIColor.tertiaryLabelColor; close.accessibilityLabel = @"关闭消息提醒";
        [close.widthAnchor constraintEqualToConstant:36].active = YES; [close.heightAnchor constraintEqualToConstant:44].active = YES;
        [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_portrait, text, close]];
        row.spacing = 12; row.alignment = UIStackViewAlignmentCenter; row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:15],
            [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-7],
            [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
            [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14]
        ]];
        self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", title.text, body.text]; self.accessibilityHint = DY778NoticeIsEdit(record) ? @"查看该条消息的编辑历史" : @"查看此会话的撤回记录";
        self.accessibilityTraits = UIAccessibilityTraitButton;
        NSString *avatar = DY778NoticeString(record, @"senderAvatar"); if (!avatar.length) avatar = DY778NoticeString(record, @"conversationAvatar");
        NSURL *url = [NSURL URLWithString:avatar];
        if ([@[@"https", @"http"] containsObject:url.scheme.lowercaseString] && url.host.length) {
            __weak typeof(self) weakSelf = self;
            NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:5];
            self.avatarTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (error || data.length > 2 * 1024 * 1024 || !data.length) return;
                UIImage *image = [UIImage imageWithData:data]; if (!image) return;
                dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.portrait.image = image; });
            }]; [self.avatarTask resume];
        }
    }
    return self;
}
- (void)dealloc { [self.avatarTask cancel]; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view && view != self; view = view.superview) if ([view isKindOfClass:UIControl.class]) return NO;
    return YES;
}
- (BOOL)accessibilityActivate { [self open]; return YES; }
- (void)open { NSDictionary *record = self.record; [self close]; DY778OpenMessageNotice(record); }
- (void)close {
    [self.avatarTask cancel];
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : .18 animations:^{ self.alpha = 0; }
        completion:^(__unused BOOL finished) { [self removeFromSuperview]; }];
}
@end

static __weak DY778MessageBanner *DY778VisibleMessageBanner;
static void DY778ShowMessageBanner(NSDictionary *record) {
    if (!DY778MessageNoticeAllowed(record) || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIWindow *window = DY778ActiveWindow(); if (!window) return;
    [DY778VisibleMessageBanner removeFromSuperview];
    DY778MessageBanner *banner = [[DY778MessageBanner alloc] initWithRecord:record]; DY778VisibleMessageBanner = banner;
    [window addSubview:banner]; NSLayoutConstraint *width = [banner.widthAnchor constraintEqualToConstant:460]; width.priority = 750;
    [NSLayoutConstraint activateConstraints:@[width,
        [banner.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [banner.leadingAnchor constraintGreaterThanOrEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:12],
        [banner.trailingAnchor constraintLessThanOrEqualToAnchor:window.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [banner.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:9]
    ]];
    banner.alpha = 0; banner.transform = UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, -12);
    [UIView animateWithDuration:.22 animations:^{ banner.alpha = 1; banner.transform = CGAffineTransformIdentity; }];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, banner.accessibilityLabel);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (UIAccessibilityIsVoiceOverRunning() ? 10 : 6) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [banner close]; });
}
static BOOL DY778IsMessageRequest(UNNotificationRequest *request) {
    return [request.identifier hasPrefix:DY778RecallRequestPrefix] || [request.identifier hasPrefix:DY778EditRequestPrefix];
}
static BOOL DY778IsMessageNotification(UNNotification *notification) { return DY778IsMessageRequest(notification.request); }
static NSDictionary *DY778RecordFromRequest(UNNotificationRequest *request) {
    NSDictionary *info = request.content.userInfo;
    return @{@"account": DY778NoticeString(info, @"DY778Account"), @"conversation": DY778NoticeString(info, @"DY778Conversation"),
        @"key": DY778NoticeString(info, @"DY778Key"), @"noticeKind": [request.identifier hasPrefix:DY778EditRequestPrefix] ? @"edit" : @"recall"};
}
static NSDictionary *DY778RecordFromNotification(UNNotification *notification) { return DY778RecordFromRequest(notification.request); }
static void DY778InstallNotificationDelegateHooks(id delegate) {
    if (!delegate || object_getClass(delegate) == NSObject.class) return;
    static NSMutableSet *installed; static dispatch_once_t once; dispatch_once(&once, ^{ installed = [NSMutableSet set]; });
    @synchronized (installed) {
        Class cls = object_getClass(delegate);
        NSArray *selectors = @[@"userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:", @"userNotificationCenter:willPresentNotification:withCompletionHandler:"];
        for (NSUInteger index = 0; index < selectors.count; index++) {
            NSString *identity = [NSStringFromClass(cls) stringByAppendingString:selectors[index]]; if ([installed containsObject:identity]) continue;
            SEL selector = NSSelectorFromString(selectors[index]); Method method = class_getInstanceMethod(cls, selector); IMP original = NULL;
            if (!method && [delegate respondsToSelector:selector]) continue;
            if (method) {
                NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
                if (signature.numberOfArguments != 5 || signature.methodReturnType[0] != 'v' ||
                    [signature getArgumentTypeAtIndex:2][0] != '@' || [signature getArgumentTypeAtIndex:3][0] != '@' ||
                    strcmp([signature getArgumentTypeAtIndex:4], "@?") != 0) continue;
                original = method_getImplementation(method);
            }
            IMP replacement;
            if (index == 0) replacement = imp_implementationWithBlock(^(id owner, UNUserNotificationCenter *center, UNNotificationResponse *response, void (^completion)(void)) {
                if (DY778IsMessageNotification(response.notification)) {
                    if ([response.actionIdentifier isEqual:UNNotificationDefaultActionIdentifier]) {
                        NSDictionary *record = DY778RecordFromNotification(response.notification);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DY778OpenMessageNotice(record); });
                        });
                    }
                    if (completion) completion(); return;
                }
                if (original) ((void (*)(id, SEL, id, id, void (^)(void)))original)(owner, selector, center, response, completion);
                else if (completion) completion();
            });
            else replacement = imp_implementationWithBlock(^(id owner, UNUserNotificationCenter *center, UNNotification *notification, void (^completion)(UNNotificationPresentationOptions)) {
                if (DY778IsMessageNotification(notification)) {
                    NSDictionary *record = DY778RecordFromNotification(notification);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        BOOL allowed = DY778MessageNoticeAllowed(record);
                        if (completion) completion(allowed ? (UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound) : 0);
                    }); return;
                }
                if (original) ((void (*)(id, SEL, id, id, void (^)(UNNotificationPresentationOptions)))original)(owner, selector, center, notification, completion);
                else if (completion) completion(0);
            });
            IMP previous = NULL;
            BOOL success = method ? DY778Hook(cls, selector, replacement, &previous) : class_addMethod(cls, selector, replacement, "v@:@@@?");
            if (success) [installed addObject:identity]; else imp_removeBlock(replacement);
        }
    }
}
static void DY778HandleMessageEvent(NSDictionary *record) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778HandleMessageEvent(record); }); return; }
    if (![record isKindOfClass:NSDictionary.class] || !DY778MessageNoticeAllowed(record)) return;
    NSString *messageKey = DY778NoticeString(record, @"key"); if (!messageKey.length) return;
    NSString *version = DY778NoticeIsEdit(record) ? DY778NoticeString(record, @"noticeVersion") : @"";
    if (DY778NoticeIsEdit(record) && !version.length) return;
    NSData *identity = [NSJSONSerialization dataWithJSONObject:@[DY778NoticeKind(record), record[@"account"], record[@"conversation"], messageKey, version] options:0 error:nil];
    NSString *key = [[NSString alloc] initWithData:identity encoding:NSUTF8StringEncoding];
    if (!key.length) return;
    static NSMutableOrderedSet *recent; if (!recent) recent = [NSMutableOrderedSet orderedSet];
    if ([recent containsObject:key]) return; [recent addObject:key]; if (recent.count > 512) [recent removeObjectAtIndex:0];
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) { DY778ShowMessageBanner(record); return; }
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    DY778InstallNotificationDelegateHooks(center.delegate);
    DY778NoticeDeliveryLease *lease = [DY778NoticeDeliveryLease new];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusAuthorized && settings.authorizationStatus != UNAuthorizationStatusProvisional && settings.authorizationStatus != UNAuthorizationStatusEphemeral) { [lease finish]; return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!DY778MessageNoticeAllowed(record)) { [lease finish]; return; }
            if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) { DY778ShowMessageBanner(record); [lease finish]; return; }
            UNMutableNotificationContent *content = [UNMutableNotificationContent new];
            content.title = DY778MessageNoticeTitle(record); content.body = DY778MessageNoticeBody(record);
            NSString *name = DY778NoticeString(record, @"conversationName"); content.subtitle = name.length ? [@"DY778 · " stringByAppendingString:name] : (DY778NoticeIsEdit(record) ? @"DY778 · 编辑提醒" : @"DY778 · 撤回提醒");
            content.sound = UNNotificationSound.defaultSound;
            content.threadIdentifier = [DY778NoticePrefix(record) stringByAppendingString:DY778NoticeDigest([NSString stringWithFormat:@"%@|%@", record[@"account"], record[@"conversation"]])];
            content.userInfo = @{@"DY778Account": record[@"account"], @"DY778Conversation": record[@"conversation"], @"DY778Key": messageKey};
            NSString *identifier = [DY778NoticePrefix(record) stringByAppendingString:DY778NoticeDigest(key)];
            [center addNotificationRequest:[UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil] withCompletionHandler:^(__unused NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!DY778MessageNoticeAllowed(record)) {
                        [UNUserNotificationCenter.currentNotificationCenter removePendingNotificationRequestsWithIdentifiers:@[identifier]];
                        [UNUserNotificationCenter.currentNotificationCenter removeDeliveredNotificationsWithIdentifiers:@[identifier]];
                    }
                    [lease finish];
                });
            }];
        });
    }];
}
static void DY778ClearMessageNotifications(BOOL removeAll, NSString *onlyKind) {
    if (DY778VisibleMessageBanner && (!onlyKind || [onlyKind isEqual:DY778NoticeKind(DY778VisibleMessageBanner.record)]) && (removeAll || !DY778MessageNoticeAllowed(DY778VisibleMessageBanner.record))) [DY778VisibleMessageBanner close];
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *requests) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray *ids = [NSMutableArray array];
            for (UNNotificationRequest *request in requests) {
                if (!DY778IsMessageRequest(request)) continue;
                NSDictionary *record = DY778RecordFromRequest(request);
                if ((!onlyKind || [onlyKind isEqual:DY778NoticeKind(record)]) && (removeAll || !DY778MessageNoticeAllowed(record))) [ids addObject:request.identifier];
            }
            if (ids.count) [center removePendingNotificationRequestsWithIdentifiers:ids];
        });
    }];
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray *ids = [NSMutableArray array];
            for (UNNotification *item in notifications) {
                NSDictionary *record = DY778RecordFromNotification(item);
                if (DY778IsMessageNotification(item) && (!onlyKind || [onlyKind isEqual:DY778NoticeKind(record)]) && (removeAll || !DY778MessageNoticeAllowed(record))) [ids addObject:item.request.identifier];
            }
            if (ids.count) [center removeDeliveredNotificationsWithIdentifiers:ids];
        });
    }];
}
static void DY778InstallRecallAccountHook(void) {
    static BOOL installed; if (installed) return;
    Class cls = NSClassFromString(@"AWEUserService"); SEL selector = NSSelectorFromString(@"updateIsSwitchingAccount:");
    Method method = class_getInstanceMethod(cls, selector); if (!method) return;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 3 || signature.methodReturnType[0] != 'v' || !strchr("Bc", [signature getArgumentTypeAtIndex:2][0])) return;
    IMP original = method_getImplementation(method), previous = NULL;
    IMP replacement = imp_implementationWithBlock(^(id owner, BOOL switching) {
        ((void (*)(id, SEL, BOOL))original)(owner, selector, switching);
        dispatch_async(dispatch_get_main_queue(), ^{ DY778NoticeAccountTransition = switching; DY778ClearMessageNotifications(switching, nil); });
    });
    installed = DY778Hook(cls, selector, replacement, &previous); if (!installed) imp_removeBlock(replacement);
}
void DY778InstallRecallNotifications(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:DY778RecallDetectedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) { DY778HandleMessageEvent(notification.userInfo[@"record"]); }];
        [NSNotificationCenter.defaultCenter addObserverForName:DY778EditDetectedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) { DY778HandleMessageEvent(notification.userInfo[@"record"]); }];
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
            NSString *key = notification.userInfo[@"key"];
            if ([@[@"recall.notificationPreview", @"edit.notificationPreview"] containsObject:key] && !DY778Bool(key)) DY778ClearMessageNotifications(YES, [key hasPrefix:@"edit."] ? @"edit" : @"recall");
            else if (!key.length || [@[@"recall.enabled", @"recall.notifications", @"recall.disabledConversations", @"edit.enabled", @"edit.notifications", @"edit.disabledConversations"] containsObject:key]) DY778ClearMessageNotifications(NO, nil);
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) { [DY778VisibleMessageBanner close]; }];
        Class cls = UNUserNotificationCenter.class; SEL selector = @selector(setDelegate:); Method method = class_getInstanceMethod(cls, selector);
        if (method) {
            IMP original = method_getImplementation(method), previous = NULL;
            IMP replacement = imp_implementationWithBlock(^(UNUserNotificationCenter *center, id delegate) {
                DY778InstallNotificationDelegateHooks(delegate);
                ((void (*)(id, SEL, id))original)(center, selector, delegate);
            });
            if (!DY778Hook(cls, selector, replacement, &previous)) imp_removeBlock(replacement);
        }
    });
    DY778InstallNotificationDelegateHooks(UNUserNotificationCenter.currentNotificationCenter.delegate);
    DY778InstallRecallAccountHook();
    DY778ClearMessageNotifications(NO, nil);
}
static void DY778RequestMessageNotificationPermission(UIViewController *source, BOOL edit) {
    __weak UIViewController *weakSource = source;
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
            [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError *error) {
                DY778Toast(granted && !error ? (edit ? @"编辑提醒已开启，后台通知已允许" : @"撤回提醒已开启，后台通知已允许") : @"前台提醒已开启，后台通知需允许系统通知");
            }];
        } else if (settings.authorizationStatus == UNAuthorizationStatusDenied) {
            DY778ShowNotice(weakSource, @"前台提醒已开启", @"后台系统通知尚未获准。你可以到 iOS 设置 → 通知 → 抖音，允许通知。\n\n抖音被挂起或关闭后，插件无法独立收取消息。已接收的消息快照会继续保存在本机。");
        } else DY778Toast(edit ? @"编辑提醒已开启，仅对启用编辑历史的会话生效" : @"撤回提醒已开启，仅对启用防撤回的会话生效");
    }];
}
void DY778RequestRecallNotificationPermission(UIViewController *source) { DY778RequestMessageNotificationPermission(source, NO); }
void DY778RequestEditNotificationPermission(UIViewController *source) { DY778RequestMessageNotificationPermission(source, YES); }
void DY778ShowRecallNotificationStatus(UIViewController *source) {
    __weak UIViewController *weakSource = source;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        NSString *status = @"尚未申请";
        if (settings.authorizationStatus == UNAuthorizationStatusDenied) status = @"未允许";
        else if (settings.authorizationStatus == UNAuthorizationStatusProvisional) status = @"静默通知";
        else if (settings.authorizationStatus == UNAuthorizationStatusAuthorized || settings.authorizationStatus == UNAuthorizationStatusEphemeral) status = @"已允许";
        NSString *text = [NSString stringWithFormat:@"系统通知：%@\n\n前台：收到撤回或新的编辑版本后显示提醒卡片。撤回卡片打开会话记录，编辑卡片打开对应消息的历史。\n\n后台：只有抖音仍在运行并实际收到撤回或编辑事件时，才能保存内容并发出本地通知。声音、锁屏预览和专注模式遵循 iOS 设置。\n\n被挂起或关闭：插件不能独立接收远程推送，也不能无限延长后台运行。再次进入时，会在消息重新加载后核对之前保存的内容。", status];
        DY778ShowNotice(weakSource, @"消息提醒与后台运行", text);
    }];
}
