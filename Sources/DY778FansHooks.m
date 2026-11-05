#import "DY778FansUI.h"
#import "DY778Enhancements.h"
static char DY778FansProfileButtonKeyStorage;
static const void *DY778FansProfileButtonKey = &DY778FansProfileButtonKeyStorage;
static NSHashTable *DY778FansProfileOwners;
static BOOL DY778FansMatch(Method method, const char *returns, const char *arguments) {
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.methodReturnType[0] != returns[0] || signature.numberOfArguments != strlen(arguments)+2) return NO;
    for (NSUInteger i=0; arguments[i]; i++) if ([signature getArgumentTypeAtIndex:i+2][0] != arguments[i]) return NO;
    return YES;
}
@interface DY778FansProfileButton : UIButton
@property(nonatomic, weak) id owner;
@end
@implementation DY778FansProfileButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setImage:[UIImage systemImageNamed:@"star.circle"] forState:UIControlStateNormal];
        [self setTitle:@" 星牌" forState:UIControlStateNormal]; self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; self.tintColor = UIColor.whiteColor;
        self.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.28]; self.layer.cornerRadius = 18;
        self.accessibilityLabel = @"查询此用户的消费等级与粉丝灯牌";
        [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    } return self;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return CGRectContainsPoint(CGRectInset(self.bounds, 0, -4), point); }
- (void)open {
    if (!DY778FansEnabled(@"DY778FansC.Profile")) return;
    NSDictionary *person = DY778FansPerson(DY778FansCall(self.owner, @"userModel", @[]));
    if (person) DY778FansOpenQuery(person);
}
@end

static void DY778FansUpdateProfile(id owner) {
    UIView *container = DY778FansRead(owner, @"navigationContainerView"); if (![container isKindOfClass:UIView.class]) return;
    DY778FansProfileButton *button = objc_getAssociatedObject(container, DY778FansProfileButtonKey);
    NSDictionary *person = DY778FansPerson(DY778FansCall(owner, @"userModel", @[]));
    if (!DY778FansEnabled(@"DY778FansC.Profile") || !person || container.bounds.size.width < 120) { button.hidden = YES; return; }
    if (!button) {
        button = [DY778FansProfileButton new]; button.owner = owner; [container addSubview:button]; objc_setAssociatedObject(container, DY778FansProfileButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!DY778FansProfileOwners) DY778FansProfileOwners = [NSHashTable weakObjectsHashTable]; [DY778FansProfileOwners addObject:owner];
    }
    CGFloat left = 12, right = container.bounds.size.width - 12, centerY = container.bounds.size.height / 2;
    button.owner = owner;
    button.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.28]; button.tintColor = UIColor.whiteColor;
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    id leftViews = DY778FansCall(owner, @"currentLeftShowViews", @[]), rightViews = DY778FansCall(owner, @"currentRightShowViews", @[]);
    if (![leftViews isKindOfClass:NSArray.class] || ![rightViews isKindOfClass:NSArray.class]) { button.hidden = YES; return; }
    for (id views in @[leftViews ?: @[], rightViews ?: @[]]) {
        if (![views isKindOfClass:NSArray.class]) continue;
        for (UIView *view in views) {
            if (![view isKindOfClass:UIView.class] || view.hidden || view.alpha < 0.05 || ![view isDescendantOfView:container] || view == button) continue;
            CGRect frame = [view convertRect:view.bounds toView:container];
            if (views == leftViews) { left = MAX(left, CGRectGetMaxX(frame) + 8); centerY = CGRectGetMidY(frame); }
            else right = MIN(right, CGRectGetMinX(frame) - 8);
        }
    }
    CGFloat width = DY778FansProfileButtonWidth(right - left);
    button.hidden = width == 0 || container.bounds.size.height < 36;
    [button setTitle:width > 44 ? @" 星牌" : @"" forState:UIControlStateNormal];
    button.frame = CGRectMake(left, MAX(0, MIN(container.bounds.size.height - 36, centerY - 18)), width, 36);
    [container bringSubviewToFront:button];
}
static void DY778FansInstallProfile(void) {
    static BOOL installed[4]; NSArray *selectors = @[@"viewDidLayoutSubviews", @"viewDidAppear", @"reloadData", @"viewDidDisappear"];
    Class cls = NSClassFromString(@"AWEProfileNavigationBaseComponent");
    for (NSUInteger i = 0; i < selectors.count; i++) {
        if (installed[i]) continue; SEL sel = NSSelectorFromString(selectors[i]); Method method = class_getInstanceMethod(cls, sel);
        if (!DY778FansMatch(method, "v", "")) continue;
        IMP original = method_getImplementation(method); BOOL hiding = i == 3;
        IMP replacement = imp_implementationWithBlock(^(id owner) {
            ((void (*)(id, SEL))original)(owner, sel);
            if (hiding) { UIView *view = DY778FansRead(owner, @"navigationContainerView"); UIView *button = objc_getAssociatedObject(view, DY778FansProfileButtonKey); button.hidden = YES; }
            else DY778FansUpdateProfile(owner);
        });
        class_replaceMethod(cls, sel, replacement, method_getTypeEncoding(method)); installed[i] = YES;
    }
    static BOOL hitInstalled; if (hitInstalled) return;
    Class container = NSClassFromString(@"AWEProfileNavigationContainerView"); SEL sel = @selector(hitTest:withEvent:); Method method = class_getInstanceMethod(container, sel);
    if (!method) return;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 4 || signature.methodReturnType[0] != '@' || strcmp([signature getArgumentTypeAtIndex:2], @encode(CGPoint)) != 0 || [signature getArgumentTypeAtIndex:3][0] != '@') return;
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^UIView *(UIView *owner, CGPoint point, UIEvent *event) {
        DY778FansProfileButton *button = objc_getAssociatedObject(owner, DY778FansProfileButtonKey);
        if (DY778FansEnabled(@"DY778FansC.Profile") && owner.userInteractionEnabled && !owner.hidden && owner.alpha > 0.05 && button && !button.hidden && button.alpha > 0.05) {
            CGPoint local = [button convertPoint:point fromView:owner];
            if ([button pointInside:local withEvent:event]) return button;
        }
        return ((UIView *(*)(id, SEL, CGPoint, id))original)(owner, sel, point, event);
    });
    class_replaceMethod(container, sel, replacement, method_getTypeEncoding(method)); hitInstalled = YES;
}
void DY778InstallFansHooks(void) {
    DY778FansInstallProfile();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            for (id owner in DY778FansProfileOwners.allObjects) DY778FansUpdateProfile(owner);
        }];
    });
}
