#import "DY778Core.h"
#import <QuartzCore/QuartzCore.h>
#import "DY778ArchiveStorage.h"
#import <math.h>

NSString *const DY778Version = @"1.0-1";
#ifndef DY778_BUILD_TIME
#define DY778_BUILD_TIME "未记录"
#endif
NSString *const DY778BuildTime = @DY778_BUILD_TIME;
NSNotificationName const DY778PreferencesChangedNotification = @"DY778PreferencesChanged";
NSNotificationName const DY778RecallChangedNotification = @"DY778RecallChanged";
NSNotificationName const DY778RecallDetectedNotification = @"DY778RecallDetected";

NSUserDefaults *DY778Preferences(void) {
    static NSUserDefaults *preferences;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ preferences = DY778MigratedPreferences(); });
    return preferences;
}
static NSDictionary *DY778DefaultValues(void) {
    return @{
        @"recall.enabled": @NO, @"recall.badge": @YES, @"recall.badgeText": @"已撤回", @"recall.archiveEntry": @YES,
        @"recall.retentionDays": @0, @"recall.maxRecords": @0,
        @"recall.notifications": @NO, @"recall.notificationPreview": @NO,
        @"recall.tintBubble": @NO, @"recall.plainBubbleOnSkin": @NO, @"recall.bubbleColor": @"#4A3038", @"recall.position": @"right",
        @"edit.enabled": @NO, @"edit.badge": @YES, @"edit.badgeText": @"编辑历史", @"edit.position": @"right", @"edit.archiveEntry": @YES,
        @"edit.tintBubble": @NO, @"edit.bubbleColor": @"#3A6558",
        @"edit.notifications": @NO, @"edit.notificationPreview": @NO,
        @"edit.retentionDays": @0, @"edit.maxRecords": @0,
        @"time.enabled": @NO, @"time.format": @"HH:mm:ss", @"time.smartDate": @YES,
        @"time.fontSize": @11, @"time.color": @"#66D8C5", @"time.background": @YES,
        @"time.opacity": @0.94, @"time.position": @"right", @"time.hideOfficial": @NO,
        @"lucky.enabled": @NO, @"lucky.mode": @"confirm",
        @"lucky.autoPhrase": @NO, @"lucky.autoJoin": @YES, @"lucky.delay": @1.2,
        @"lucky.prompt": @YES, @"lucky.haptics": @NO, @"lucky.showStatus": @YES,
        @"lucky.compact": @YES,
        @"playback.stopAtEnd": @NO, @"playback.longPressEnabled": @NO, @"playback.longPressRate": @2,
        @"playback.defaultEnabled": @NO, @"playback.defaultRate": @1.25, @"experimental.skipAds": @NO,
        @"cache.enabled": @NO, @"cache.onLaunch": @NO, @"cache.onReturn": @NO, @"cache.maxMB": @0, @"cache.maxAgeHours": @0,
        @"appearance": @"system", @"accent": @"#55CDB9"
    };
}
void DY778RegisterDefaults(void) { [DY778Preferences() registerDefaults:DY778DefaultValues()]; }
void DY778ResetSettings(void) {
    for (NSString *key in DY778DefaultValues()) [DY778Preferences() removeObjectForKey:key];
    for (NSString *key in @[@"edit.disabledConversations", @"recall.disabledConversations", @"recall.enableNoticeShown", @"lucky.cardX", @"lucky.cardY"])
        [DY778Preferences() removeObjectForKey:key];
    DY778RegisterDefaults();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:DY778PreferencesChangedNotification object:nil];
    });
}
BOOL DY778Bool(NSString *key) { return [DY778Preferences() boolForKey:key]; }
double DY778Number(NSString *key) { return [DY778Preferences() doubleForKey:key]; }
NSString *DY778String(NSString *key) {
    id value = [DY778Preferences() objectForKey:key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}
static NSString *DY778NormalizeMarker(NSString *value, NSString *fallback) {
    if (![value isKindOfClass:NSString.class]) return fallback;
    NSArray *parts = [value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *singleLine = [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
    NSMutableString *text = [NSMutableString string]; __block NSUInteger count = 0;
    [singleLine enumerateSubstringsInRange:NSMakeRange(0, singleLine.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *part, NSRange range, NSRange enclosing, BOOL *stop) {
        if (count++ == 12) { *stop = YES; return; }
        [text appendString:part];
    }];
    return text.length ? text : fallback;
}
NSString *DY778RecallMarkerText(void) { return DY778NormalizeMarker(DY778String(@"recall.badgeText"), @"已撤回"); }
NSString *DY778EditMarkerText(void) { return DY778NormalizeMarker(DY778String(@"edit.badgeText"), @"编辑历史"); }
void DY778Set(NSString *key, id value) {
    if (!key.length) return;
    NSDictionary *ranges = @{@"time.fontSize": @[@9, @17], @"time.opacity": @[@0.35, @1],
        @"lucky.delay": @[@0.5, @5], @"recall.retentionDays": @[@0, @36500],
        @"recall.maxRecords": @[@0, @10000000], @"edit.retentionDays": @[@0, @36500], @"edit.maxRecords": @[@0, @10000000],
        @"playback.longPressRate": @[@1, @3], @"playback.defaultRate": @[@1, @3], @"cache.maxMB": @[@0, @1048576], @"cache.maxAgeHours": @[@0, @876000]};
    NSArray *range = ranges[key];
    if (range && [value respondsToSelector:@selector(doubleValue)]) {
        double number = [value doubleValue];
        if (!isfinite(number)) return;
        value = @(MIN([range[1] doubleValue], MAX([range[0] doubleValue], number)));
    }
    if ([key isEqual:@"playback.longPressRate"] || [key isEqual:@"playback.defaultRate"]) value = @(round([value doubleValue] * 100) / 100);
    if ([key isEqual:@"recall.badgeText"]) value = DY778NormalizeMarker(value, @"已撤回");
    if ([key isEqual:@"edit.badgeText"]) value = DY778NormalizeMarker(value, @"编辑历史");
    if (value) [DY778Preferences() setObject:value forKey:key];
    else [DY778Preferences() removeObjectForKey:key];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:DY778PreferencesChangedNotification
                                                        object:nil userInfo:@{@"key": key}];
    });
}
id DY778Read(id object, NSString *key) {
    if (!object || object == NSNull.null || !key.length) return nil;
    if ([object isKindOfClass:NSDictionary.class]) return object[key] == NSNull.null ? nil : object[key];
    // KVC boxes scalar accessors correctly. Do not dereference arbitrary object ivars.
    SEL selector = NSSelectorFromString(key);
    NSString *getter = [@"is" stringByAppendingString:[key stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                                                   withString:[[key substringToIndex:1] uppercaseString]]];
    if (![object respondsToSelector:selector] && ![object respondsToSelector:NSSelectorFromString(getter)]) return nil;
    @try { id result = [object valueForKey:key]; return result == NSNull.null ? nil : result; }
    @catch (__unused NSException *exception) { return nil; }
}
BOOL DY778Write(id object, NSString *key, id value) {
    if (!object || !key.length) return NO;
    @try { [object setValue:value forKey:key]; return YES; }
    @catch (__unused NSException *exception) { return NO; }
}
NSString *DY778Identifier(id value) {
    if ([value isKindOfClass:NSString.class]) return [value length] ? value : nil;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}
NSString *DY778CurrentAccountID(void) {
    Class cls = NSClassFromString(@"AWEUserService");
    SEL selector = NSSelectorFromString(@"sharedService");
    Method method = class_getClassMethod(cls, selector);
    if (!method) return @"";
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return @"";
    @try {
        id service = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
        NSString *userID = DY778Identifier(DY778Read(service, @"userID"));
        return userID.length && ![userID isEqualToString:@"0"] ? userID : @"";
    } @catch (__unused NSException *exception) { return @""; }
}
BOOL DY778Hook(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || !selector || !replacement || !original) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    IMP previous = method_getImplementation(method);
    if (previous == replacement) return YES;
    *original = previous;
    // Add on the subclass first: replacing an inherited Method would mutate its superclass.
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)))
        method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
    return YES;
}
static NSMutableDictionary *DY778HookResults(void) {
    static NSMutableDictionary *results; static dispatch_once_t once;
    dispatch_once(&once, ^{ results = [NSMutableDictionary new]; });
    return results;
}
void DY778RecordHook(NSString *name, BOOL installed) {
    if (!name) return;
    @synchronized (DY778HookResults()) { DY778HookResults()[name] = @(installed); }
}
NSDictionary *DY778HookReport(void) {
    @synchronized (DY778HookResults()) { return [DY778HookResults() copy]; }
}
UIWindow *DY778ActiveWindow(void) {
    UIWindow *candidate = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha < .01 || window.windowLevel != UIWindowLevelNormal || !window.rootViewController) continue;
            if (window.isKeyWindow) return window;
            candidate = window;
        }
    }
    return candidate;
}
static UIViewController *DY778FrontController(UIViewController *controller) {
    for (NSUInteger depth = 0; controller && depth < 20; depth++) {
        UIViewController *next;
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
            next = controller.presentedViewController;
        else if ([controller isKindOfClass:UINavigationController.class]) next = ((UINavigationController *)controller).visibleViewController;
        else if ([controller isKindOfClass:UITabBarController.class]) next = ((UITabBarController *)controller).selectedViewController;
        else break;
        if (!next || next == controller) break;
        controller = next;
    }
    return controller;
}
UIViewController *DY778TopController(void) { return DY778FrontController(DY778ActiveWindow().rootViewController); }
UIUserInterfaceStyle DY778InterfaceStyle(void) {
    NSString *choice = DY778String(@"appearance");
    if ([choice isEqualToString:@"light"]) return UIUserInterfaceStyleLight;
    if ([choice isEqualToString:@"dark"]) return UIUserInterfaceStyleDark;
    Class cls = NSClassFromString(@"AWEUIThemeManager");
    SEL selector = NSSelectorFromString(@"isLightTheme");
    Method method = class_getClassMethod(cls, selector);
    if (method) {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.numberOfArguments == 2 && strchr("Bc", signature.methodReturnType[0]))
            return ((BOOL (*)(id, SEL))objc_msgSend)(cls, selector) ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    }
    return DY778ActiveWindow().traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
}
UIColor *DY778ColorFromHex(NSString *hex, UIColor *fallback) {
    if (![hex isKindOfClass:NSString.class]) return fallback;
    NSString *clean = [hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex;
    if (clean.length != 6) return fallback;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
    if ([clean rangeOfCharacterFromSet:invalid].location != NSNotFound) return fallback;
    unsigned int value = 0; if (![[NSScanner scannerWithString:clean] scanHexInt:&value]) return fallback;
    return [UIColor colorWithRed:((value >> 16) & 255) / 255. green:((value >> 8) & 255) / 255. blue:(value & 255) / 255. alpha:1];
}
UIColor *DY778Accent(void) {
    UIColor *base = DY778ColorFromHex(DY778String(@"accent"), UIColor.systemTealColor);
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        CGFloat r, g, b, a; [base getRed:&r green:&g blue:&b alpha:&a];
        if (trait.userInterfaceStyle != UIUserInterfaceStyleDark && (.2126*r + .7152*g + .0722*b) > .5) {
            r *= .58; g *= .58; b *= .58;
        }
        return [UIColor colorWithRed:r green:g blue:b alpha:1];
    }];
}
UIColor *DY778Background(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return trait.userInterfaceStyle == UIUserInterfaceStyleDark ?
            [UIColor colorWithRed:.055 green:.064 blue:.075 alpha:1] :
            [UIColor colorWithRed:.951 green:.965 blue:.966 alpha:1];
    }];
}
UIColor *DY778CardBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return trait.userInterfaceStyle == UIUserInterfaceStyleDark ?
            [UIColor colorWithRed:.105 green:.119 blue:.13 alpha:1] : UIColor.whiteColor;
    }];
}
void DY778StyleController(UIViewController *controller) {
    controller.overrideUserInterfaceStyle = DY778InterfaceStyle();
    controller.edgesForExtendedLayout = UIRectEdgeNone;
    controller.extendedLayoutIncludesOpaqueBars = NO;
    controller.navigationItem.backButtonTitle = @"返回";
    controller.view.backgroundColor = DY778Background();
    controller.view.opaque = YES; controller.view.clipsToBounds = YES;
    controller.view.tintColor = DY778Accent();
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = DY778Background();
    appearance.shadowColor = UIColor.clearColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.labelColor};
    appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.labelColor};
    controller.navigationItem.standardAppearance = appearance;
    controller.navigationItem.scrollEdgeAppearance = appearance;
    controller.navigationItem.compactAppearance = appearance;
    controller.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [controller setNeedsStatusBarAppearanceUpdate];
}
@interface DY778ReturnTransition : NSObject <UIViewControllerAnimatedTransitioning>
@end
@implementation DY778ReturnTransition
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
    return UIAccessibilityIsReduceMotionEnabled() ? .18 : .35;
}
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    UIViewController *from = [context viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *to = [context viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *container = context.containerView;
    UIView *outgoing = [context viewForKey:UITransitionContextFromViewKey] ?: from.view;
    UIView *incoming = [context viewForKey:UITransitionContextToViewKey] ?: to.view;
    CGRect destination = [context finalFrameForViewController:to];
    if (CGRectIsEmpty(destination)) destination = container.bounds;
    CGAffineTransform savedIncoming = incoming.transform, savedOutgoing = outgoing.transform;
    incoming.frame = destination;
    [container insertSubview:incoming belowSubview:outgoing];
    CGFloat width = CGRectGetWidth(container.bounds);
    incoming.transform = CGAffineTransformTranslate(savedIncoming, -width * .25, 0);
    UIView *shade = [[UIView alloc] initWithFrame:container.bounds];
    shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    shade.backgroundColor = UIColor.blackColor; shade.alpha = .12;
    shade.userInteractionEnabled = NO; [container insertSubview:shade belowSubview:outgoing];
    [UIView animateWithDuration:[self transitionDuration:context] delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        incoming.transform = savedIncoming;
        outgoing.transform = CGAffineTransformTranslate(savedOutgoing, width, 0);
        shade.alpha = 0;
    } completion:^(__unused BOOL finished) {
        BOOL cancelled = context.transitionWasCancelled;
        [shade removeFromSuperview];
        incoming.transform = savedIncoming; outgoing.transform = savedOutgoing;
        [context completeTransition:!cancelled];
    }];
}
@end

@interface DY778NavigationController : UINavigationController <UINavigationControllerDelegate, UIGestureRecognizerDelegate, UIViewControllerTransitioningDelegate>
@property(nonatomic) BOOL changingPage;
@property(nonatomic, strong) UIPanGestureRecognizer *rootBackGesture;
@property(nonatomic, strong) UIPercentDrivenInteractiveTransition *returnInteraction;
- (void)cgn_prepareController:(UIViewController *)controller;
- (void)cgn_back;
@end
@implementation DY778NavigationController
- (void)viewDidLoad {
    [super viewDidLoad]; self.delegate = self;
    self.navigationBarHidden = NO; self.navigationBar.translucent = NO; self.navigationBar.tintColor = DY778Accent();
    self.view.backgroundColor = DY778Background(); self.view.opaque = YES; self.view.clipsToBounds = YES;
    self.navigationBar.backgroundColor = DY778Background(); self.navigationBar.prefersLargeTitles = NO;
    self.interactivePopGestureRecognizer.enabled = NO;
    self.transitioningDelegate = self;
    self.rootBackGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(cgn_rootBack:)];
    self.rootBackGesture.maximumNumberOfTouches = 1; self.rootBackGesture.delegate = self;
    [self.view addGestureRecognizer:self.rootBackGesture];
}
- (UIViewController *)childViewControllerForStatusBarStyle { return self.topViewController; }
- (void)cgn_prepareController:(UIViewController *)controller {
    controller.overrideUserInterfaceStyle = DY778InterfaceStyle();
    [controller loadViewIfNeeded]; DY778StyleController(controller);
    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    [back setTitle:@"返回" forState:UIControlStateNormal];
    [back setImage:[UIImage systemImageNamed:@"chevron.backward" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    back.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    back.titleLabel.adjustsFontForContentSizeCategory = YES; back.tintColor = DY778Accent();
    back.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    back.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 12); back.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
    back.accessibilityLabel = @"返回上一层";
    [back addTarget:self action:@selector(cgn_back) forControlEvents:UIControlEventTouchUpInside];
    CGFloat width = MAX(74, ceil([@"返回" sizeWithAttributes:@{NSFontAttributeName:back.titleLabel.font}].width) + 36);
    back.frame = CGRectMake(0, 0, width, 44);
    controller.navigationItem.hidesBackButton = YES;
    controller.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:back];
}
- (void)cgn_back {
    if (self.changingPage || self.transitionCoordinator) return;
    [self.view endEditing:YES];
    if (self.viewControllers.count > 1) [self popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (self.changingPage || self.transitionCoordinator || self.presentedViewController) return NO;
    if (gestureRecognizer == self.rootBackGesture) {
        CGPoint velocity = [self.rootBackGesture velocityInView:self.view];
        return (self.viewControllers.count > 1 || self.presentingViewController != nil) && velocity.x > 0 && fabs(velocity.x) > fabs(velocity.y);
    }
    return self.viewControllers.count > 1;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (gesture != self.rootBackGesture) return YES;
    for (UIView *view = touch.view; view && view != self.view; view = view.superview) {
        if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UITextView.class]) return NO;
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *scroll = (UIScrollView *)view;
            if (scroll.contentSize.width > scroll.bounds.size.width - scroll.adjustedContentInset.left - scroll.adjustedContentInset.right + 1 || scroll.isZooming) return NO;
        }
    }
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    if (gesture != self.rootBackGesture || ![other.view isKindOfClass:UIScrollView.class]) return NO;
    UIScrollView *scroll = (UIScrollView *)other.view;
    return other == scroll.panGestureRecognizer && [scroll isDescendantOfView:self.view] &&
        scroll.contentSize.width <= scroll.bounds.size.width - scroll.adjustedContentInset.left - scroll.adjustedContentInset.right + 1;
}
- (void)cgn_rootBack:(UIPanGestureRecognizer *)gesture {
    CGFloat width = MAX(1, CGRectGetWidth(self.view.bounds));
    CGFloat progress = MIN(1, MAX(0, [gesture translationInView:self.view].x / width));
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self.view endEditing:YES];
        self.returnInteraction = [UIPercentDrivenInteractiveTransition new];
        self.returnInteraction.completionCurve = UIViewAnimationCurveEaseOut;
        if (self.viewControllers.count > 1) [self popViewControllerAnimated:YES];
        else [self dismissViewControllerAnimated:YES completion:nil];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        [self.returnInteraction updateInteractiveTransition:progress];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        CGFloat velocity = [gesture velocityInView:self.view].x;
        CGFloat projected = progress + velocity / width * .20;
        self.returnInteraction.completionSpeed = MIN(1.4, MAX(.7, fabs(velocity) / width));
        if (gesture.state == UIGestureRecognizerStateEnded && velocity > -120 && projected > .45)
            [self.returnInteraction finishInteractiveTransition];
        else [self.returnInteraction cancelInteractiveTransition];
        self.returnInteraction = nil;
    }
}
- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)from toViewController:(UIViewController *)to {
    return operation == UINavigationControllerOperationPop ? [DY778ReturnTransition new] : nil;
}
- (id<UIViewControllerInteractiveTransitioning>)navigationController:(UINavigationController *)navigationController interactionControllerForAnimationController:(id<UIViewControllerAnimatedTransitioning>)animator {
    return self.returnInteraction;
}
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    return [DY778ReturnTransition new];
}
- (id<UIViewControllerInteractiveTransitioning>)interactionControllerForDismissal:(id<UIViewControllerAnimatedTransitioning>)animator {
    return self.returnInteraction;
}
- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)controller animated:(BOOL)animated {
    self.changingPage = YES;
    [self setNavigationBarHidden:NO animated:NO]; [self cgn_prepareController:controller];
}
- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)controller animated:(BOOL)animated {
    self.changingPage = NO;
}
@end
void DY778PresentController(UIViewController *source, UIViewController *controller) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DY778PresentController(source, controller); }); return;
    }
    UIViewController *top = DY778FrontController(source ?: DY778TopController());
    if (!top || !controller || top.isBeingDismissed || top.isBeingPresented) return;
    controller.overrideUserInterfaceStyle = DY778InterfaceStyle();
    if ([top.navigationController isKindOfClass:DY778NavigationController.class] && ![top isKindOfClass:UIAlertController.class]) {
        DY778NavigationController *navigation = (DY778NavigationController *)top.navigationController;
        if (navigation.changingPage || navigation.transitionCoordinator || navigation.topViewController != top) return;
        [top.view endEditing:YES];
        [navigation cgn_prepareController:controller];
        [navigation pushViewController:controller animated:!UIAccessibilityIsReduceMotionEnabled()];
    } else {
        DY778NavigationController *navigation = [[DY778NavigationController alloc] initWithRootViewController:controller];
        navigation.overrideUserInterfaceStyle = DY778InterfaceStyle();
        navigation.modalPresentationStyle = UIModalPresentationFullScreen;
        [navigation loadViewIfNeeded]; [navigation cgn_prepareController:controller];
        [top presentViewController:navigation animated:NO completion:nil];
    }
}

@interface DY778NoticeController : UIViewController
@property(nonatomic, copy) NSString *noticeTitle;
@property(nonatomic, copy) NSString *noticeMessage;
@property(nonatomic, copy) NSString *confirmTitle;
@property(nonatomic, copy) dispatch_block_t confirmAction;
@property(nonatomic) BOOL destructive;
@property(nonatomic, strong) UIView *card;
@property(nonatomic, strong) UITextView *messageView;
@property(nonatomic, strong) NSLayoutConstraint *messageHeight;
@property(nonatomic, strong) UIButton *confirmButton;
@property(nonatomic, strong) NSTimer *countdownTimer;
@property(nonatomic) NSTimeInterval confirmDelay;
@property(nonatomic) NSTimeInterval confirmAfter;
@property(nonatomic) BOOL compact;
@end
@implementation DY778NoticeController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = DY778InterfaceStyle();
    self.view.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:.48];
    UIControl *backdrop = [[UIControl alloc] initWithFrame:self.view.bounds];
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [backdrop addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    backdrop.accessibilityLabel = @"关闭提示";
    [self.view addSubview:backdrop];
    UIView *card = [UIView new]; self.card = card;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = DY778CardBackground(); card.layer.cornerRadius = 26;
    card.layer.cornerCurve = kCACornerCurveContinuous; card.clipsToBounds = YES;
    card.accessibilityViewIsModal = YES;
    [self.view addSubview:card];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.destructive ? @"trash.circle.fill" : @"sparkles"]];
    icon.tintColor = self.destructive ? UIColor.systemRedColor : DY778Accent();
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *heading = [UILabel new]; heading.text = self.noticeTitle; heading.textColor = UIColor.labelColor;
    heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2]; heading.adjustsFontForContentSizeCategory = YES;
    heading.numberOfLines = 0; heading.textAlignment = NSTextAlignmentCenter;
    UITextView *body = [UITextView new]; self.messageView = body; body.text = self.noticeMessage; body.editable = NO; body.selectable = YES;
    body.backgroundColor = UIColor.clearColor; body.textColor = UIColor.secondaryLabelColor;
    body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; body.adjustsFontForContentSizeCategory = YES;
    body.textAlignment = NSTextAlignmentNatural; body.alwaysBounceVertical = NO; body.showsVerticalScrollIndicator = YES; body.textContainer.lineFragmentPadding = 0; body.textContainerInset = UIEdgeInsetsMake(0, 0, 0, 0);
    UIButton *confirm = [UIButton buttonWithType:UIButtonTypeSystem];
    self.confirmButton = confirm;
    [confirm setTitle:self.confirmTitle ?: @"知道了" forState:UIControlStateNormal];
    confirm.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    confirm.titleLabel.adjustsFontForContentSizeCategory = YES;
    confirm.backgroundColor = self.destructive ? UIColor.systemRedColor : DY778Accent();
    [confirm setTitleColor:DY778InterfaceStyle() == UIUserInterfaceStyleDark && !self.destructive ? UIColor.blackColor : UIColor.whiteColor
                 forState:UIControlStateNormal];
    confirm.layer.cornerRadius = 15;
    [confirm addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"暂不操作" forState:UIControlStateNormal]; cancel.tintColor = UIColor.secondaryLabelColor;
    cancel.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [cancel addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, heading, body, confirm]];
    if (self.confirmAction && !self.compact) [stack addArrangedSubview:cancel];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = self.compact ? 12 : 16; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    CGFloat readableHeight = 160;
    NSLayoutConstraint *bodyHeight = [body.heightAnchor constraintEqualToConstant:readableHeight]; bodyHeight.priority = 750; self.messageHeight = bodyHeight;
    NSLayoutConstraint *cardWidth = [card.widthAnchor constraintEqualToConstant:self.compact ? 312 : 460]; cardWidth.priority = 750;
    if (self.compact) {
        heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        body.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[UIFont systemFontOfSize:14] maximumPointSize:20];
        [card.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor].active = YES;
    }
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], cardWidth,
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:18],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-18],
        self.compact ? [card.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-14] : [card.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-14],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],
        [icon.heightAnchor constraintEqualToConstant:36], bodyHeight,
        [body.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [confirm.heightAnchor constraintGreaterThanOrEqualToConstant:50]
    ]];
    if (self.confirmAction && !self.compact) [cancel.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    if (self.confirmDelay > 0) { confirm.enabled = NO; confirm.alpha = .45; [confirm setTitle:[NSString stringWithFormat:@"确定（%.0f）", ceil(self.confirmDelay)] forState:UIControlStateNormal]; }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.messageView.bounds);
    if (width <= 0) return;
    CGFloat safeHeight = self.view.bounds.size.height - self.view.safeAreaInsets.top - self.view.safeAreaInsets.bottom;
    CGFloat measured = ceil([self.messageView sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
    CGFloat nonBodyHeight = MAX(0, self.card.bounds.size.height - self.messageView.bounds.size.height);
    CGFloat maximum = MAX(44, MIN(safeHeight * .55, safeHeight - nonBodyHeight - 28));
    CGFloat height = MIN(maximum, MAX(52, measured));
    if (fabs(self.messageHeight.constant - height) > 1) self.messageHeight.constant = height;
    self.messageView.scrollEnabled = measured > self.messageView.bounds.size.height + 1;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.card);
    if (self.confirmDelay > 0) {
        if (!self.confirmAfter) self.confirmAfter = CACurrentMediaTime() + self.confirmDelay;
        [self.countdownTimer invalidate];
        __weak typeof(self) weakSelf = self;
        self.countdownTimer = [NSTimer timerWithTimeInterval:.1 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf updateCountdown]; }];
        [NSRunLoop.mainRunLoop addTimer:self.countdownTimer forMode:NSRunLoopCommonModes];
        [self updateCountdown];
    }
}
- (void)updateCountdown {
    NSInteger remaining = MAX(0, (NSInteger)ceil(self.confirmAfter - CACurrentMediaTime()));
    self.confirmButton.enabled = remaining == 0; self.confirmButton.alpha = remaining ? .45 : 1;
    [self.confirmButton setTitle:remaining ? [NSString stringWithFormat:@"确定（%ld）", (long)remaining] : (self.confirmTitle ?: @"确定") forState:UIControlStateNormal];
    if (!remaining) { [self.countdownTimer invalidate]; self.countdownTimer = nil; }
}
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; [self.countdownTimer invalidate]; self.countdownTimer = nil; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)confirm {
    if (self.confirmDelay > 0 && (!self.confirmAfter || CACurrentMediaTime() < self.confirmAfter)) return;
    dispatch_block_t action = self.confirmAction;
    self.confirmAction = nil;
    [self dismissViewControllerAnimated:YES completion:action];
}
@end
void DY778ConfirmDelayed(UIViewController *source, NSString *title, NSString *message, NSTimeInterval delay, dispatch_block_t action) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = DY778FrontController(source ?: DY778TopController());
        if (!top || [top isKindOfClass:DY778NoticeController.class]) return;
        DY778NoticeController *notice = [DY778NoticeController new];
        notice.noticeTitle = title; notice.noticeMessage = message; notice.confirmTitle = @"确定";
        notice.confirmAction = action; notice.confirmDelay = MAX(0, delay); notice.compact = YES;
        notice.modalPresentationStyle = UIModalPresentationOverFullScreen;
        notice.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        [top presentViewController:notice animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
    });
}
void DY778Confirm(UIViewController *source, NSString *title, NSString *message, NSString *confirmTitle, BOOL destructive, dispatch_block_t action) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = DY778FrontController(source ?: DY778TopController());
        if (!top || [top isKindOfClass:DY778NoticeController.class]) return;
        DY778NoticeController *notice = [DY778NoticeController new];
        notice.noticeTitle = title; notice.noticeMessage = message; notice.confirmTitle = confirmTitle;
        notice.destructive = destructive; notice.confirmAction = action;
        notice.modalPresentationStyle = UIModalPresentationOverFullScreen;
        notice.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        [top presentViewController:notice animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
    });
}
void DY778ShowNotice(UIViewController *source, NSString *title, NSString *message) {
    DY778Confirm(source, title, message, @"知道了", NO, nil);
}
static void DY778ThemeChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:DY778PreferencesChangedNotification object:nil userInfo:@{@"key": @"appearance"}];
    });
}
void DY778InstallCoreHooks(void) {
    static BOOL installed[3];
    NSArray *selectors = @[@"changeThemeStyleLightModeEnable:", @"setLightMode:", @"setThemeStyle:"];
    for (NSUInteger i = 0; i < selectors.count; i++) {
        if (installed[i]) continue;
        Class cls = NSClassFromString(i == 2 ? @"AWEThemeManager" : @"AWESettingThemeManager");
        if (i == 2) cls = object_getClass(cls);
        SEL selector = NSSelectorFromString(selectors[i]);
        Method method = class_getInstanceMethod(cls, selector); if (!method) continue;
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.numberOfArguments != 3 || signature.methodReturnType[0] != 'v' ||
            !strchr(i == 2 ? "Qq" : "Bc", [signature getArgumentTypeAtIndex:2][0])) continue;
        IMP original = method_getImplementation(method);
        IMP replacement;
        if (i == 2) replacement = imp_implementationWithBlock(^(id owner, unsigned long long style) {
            ((void (*)(id, SEL, unsigned long long))original)(owner, selector, style); DY778ThemeChanged();
        });
        else replacement = imp_implementationWithBlock(^(id owner, BOOL light) {
            ((void (*)(id, SEL, BOOL))original)(owner, selector, light); DY778ThemeChanged();
        });
        IMP previous = NULL;
        installed[i] = DY778Hook(cls, selector, replacement, &previous);
        if (!installed[i]) imp_removeBlock(replacement);
    }
}
