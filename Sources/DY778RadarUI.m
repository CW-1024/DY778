#import "DY778Core.h"
#import "DY778RadarUI.h"
#import "DY778RadarNetwork.h"
#import <objc/message.h>
UIWindow *DY778RadarActiveWindow(void) {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return nil;
    UIWindow *fallback;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha < 0.01 || window.windowLevel != UIWindowLevelNormal || !window.rootViewController) continue;
            if (window.isKeyWindow) return window; fallback = window;
        }
    }
    if (!fallback) for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        if (!window.hidden && window.windowLevel == UIWindowLevelNormal && window.rootViewController) { if (window.isKeyWindow) return window; fallback = window; }
    }
    return fallback;
}
UIViewController *DY778RadarTopController(UIViewController *controller) {
    if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) return DY778RadarTopController(controller.presentedViewController);
    if ([controller isKindOfClass:UINavigationController.class]) return DY778RadarTopController(((UINavigationController *)controller).visibleViewController);
    if ([controller isKindOfClass:UITabBarController.class]) return DY778RadarTopController(((UITabBarController *)controller).selectedViewController);
    return controller;
}
UIUserInterfaceStyle DY778RadarStyle(void) { return DY778InterfaceStyle(); }
UIColor *DY778RadarAccent(void) { return DY778Accent(); }
UIColor *DY778RadarButtonColor(void) { return DY778Accent(); }
UILabel *DY778RadarLabel(NSString *text, CGFloat size, UIFontWeight weight) {
    UILabel *label = [UILabel new]; label.text = text; label.textColor = UIColor.labelColor; label.numberOfLines = 0;
    label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight] maximumPointSize:36];
    label.adjustsFontForContentSizeCategory = YES; return label;
}
UITableViewCell *DY778RadarCell(NSString *title, NSString *subtitle, NSString *symbol, BOOL disclosure) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = DY778CardBackground();
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.text = title; config.secondaryText = subtitle;
    config.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; config.textProperties.color = UIColor.labelColor;
    config.textProperties.numberOfLines = 0; config.secondaryTextProperties.numberOfLines = 0;
    config.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    config.textToSecondaryTextVerticalPadding = 5;
    config.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(14, 20, 14, 20);
    if (symbol.length) {
        config.image = DY778MenuIcon(symbol); config.imageProperties.tintColor = DY778RadarAccent();
        config.imageProperties.maximumSize = CGSizeMake(28, 28); config.imageProperties.reservedLayoutSize = CGSizeMake(28, 28); config.imageToTextPadding = 14;
    }
    cell.contentConfiguration = config;
    cell.accessoryType = disclosure ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}
void DY778RadarMessage(UIViewController *presenter, NSString *title, NSString *message) {
    if (!presenter.view.window) return;
    UIViewController *presented = presenter.presentedViewController;
    if (presented) {
        if ([presented isKindOfClass:UIAlertController.class])
            [presented dismissViewControllerAnimated:YES completion:^{ DY778RadarMessage(presenter, title, message); }];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778RadarStyle(); alert.view.tintColor = DY778RadarAccent();
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
void DY778RadarConfirm(UIViewController *presenter, NSString *title, NSString *message, NSString *button, dispatch_block_t action) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778RadarStyle(); alert.view.tintColor = DY778RadarAccent();
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:button style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { if (action) action(); }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
void DY778RadarSheet(UIViewController *presenter, NSString *title, NSArray<NSString *> *options, void (^chosen)(NSUInteger)) {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = DY778RadarStyle(); sheet.view.tintColor = DY778RadarAccent();
    for (NSUInteger i = 0; i < options.count; i++) [sheet addAction:[UIAlertAction actionWithTitle:options[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { chosen(i); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = presenter.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(presenter.view.bounds.size.width / 2, presenter.view.bounds.size.height / 2, 1, 1);
    sheet.popoverPresentationController.permittedArrowDirections = 0;
    [presenter presentViewController:sheet animated:YES completion:nil];
}
void DY778RadarToast(UIViewController *presenter, NSString *message) { DY778ShowToast(@"radar", message, NO, NO); }
void DY778RadarCopy(UIViewController *presenter, NSString *text) {
    if (!text.length) return;
    UIPasteboard.generalPasteboard.string = text; DY778RadarToast(presenter, @"已复制到剪贴板");
}
void DY778RadarCopySignature(UIViewController *presenter, id signature) {
    if (![signature isKindOfClass:NSString.class]) {
        DY778RadarMessage(presenter, @"暂无可复制的简介", @"尚未成功读取个人简介，请等待下一次资料检测。"); return;
    }
    UIPasteboard.generalPasteboard.string = signature;
    DY778RadarToast(presenter, [signature length] ? @"个人简介已复制" : @"简介为空，已清空剪贴板");
}
void DY778RadarOpenVideo(UIViewController *presenter, NSString *videoID) {
    if (!DY778RadarIdentifier(videoID)) return;
    NSString *route = [@"aweme://aweme/detail/" stringByAppendingString:videoID];
    NSString *web = [@"https://www.douyin.com/video/" stringByAppendingString:videoID];
    dispatch_block_t open = ^{
        Class router = NSClassFromString(@"AWERouter");
        if (DY778RadarHasMethod(router, @"transferToURLString:", "B", "@") && [DY778RadarCall(router, @"transferToURLString:", @[route]) boolValue]) return;
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:web] options:@{} completionHandler:nil];
    };
    open();
}
// 在插件的导航栈内共用一份外观快照。
@interface DY778RadarNavigationState : NSObject
@property(nonatomic) BOOL hidden;
@property(nonatomic, strong) UIColor *tint;
@end
@implementation DY778RadarNavigationState
@end
@interface DY778RadarTableController ()
@property(nonatomic, strong) DY778RadarNavigationState *navigationState;
@property(nonatomic) CGPoint savedOffset;
@property(nonatomic) BOOL restoresOffset;
@property(nonatomic) BOOL hasAppeared;
@end
@implementation DY778RadarTableController
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.hidesBottomBarWhenPushed = YES;
    return self;
}
- (void)applyNavigation:(BOOL)animated {
    UINavigationController *nav = self.navigationController;
    if (!nav) return;
    if (!self.navigationState) {
        for (UIViewController *page in nav.viewControllers) {
            if ([page isKindOfClass:DY778RadarTableController.class] && ((DY778RadarTableController *)page).navigationState) {
                self.navigationState = ((DY778RadarTableController *)page).navigationState; break;
            }
        }
        if (!self.navigationState) {
            self.navigationState = [DY778RadarNavigationState new];
            self.navigationState.hidden = nav.navigationBarHidden; self.navigationState.tint = nav.navigationBar.tintColor;
        }
    }
    [nav setNavigationBarHidden:NO animated:animated];
    nav.navigationBar.tintColor = [DY778RadarAccent() resolvedColorWithTraitCollection:self.traitCollection];
}
- (void)restoreNavigation:(BOOL)animated {
    if (!self.navigationState) return;
    [self.navigationController setNavigationBarHidden:self.navigationState.hidden animated:animated];
    self.navigationController.navigationBar.tintColor = self.navigationState.tint;
}
- (void)restoreTableOffset:(CGPoint)offset {
    [self.tableView layoutIfNeeded];
    CGFloat low = -self.tableView.adjustedContentInset.top;
    CGFloat high = MAX(low, self.tableView.contentSize.height - self.tableView.bounds.size.height + self.tableView.adjustedContentInset.bottom);
    [self.tableView setContentOffset:CGPointMake(offset.x, MIN(high, MAX(low, offset.y))) animated:NO];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.tintColor = DY778RadarAccent(); self.tableView.backgroundColor = DY778Background();
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 70;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension; self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.backButtonTitle = @"返回";
    self.clearsSelectionOnViewWillAppear = NO;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateTheme) name:DY778RadarThemeChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateTheme) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self updateTheme];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; [DY778RadarMonitor.shared synchronizeAccount];
    [self updateTheme]; [self applyNavigation:animated]; [self refresh];
    if (self.restoresOffset) [self restoreTableOffset:self.savedOffset];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; self.hasAppeared = YES; [self applyNavigation:NO];
    if (self.restoresOffset) { [self restoreTableOffset:self.savedOffset]; self.restoresOffset = NO; }
}
- (void)viewWillDisappear:(BOOL)animated {
    self.savedOffset = self.tableView.contentOffset; self.restoresOffset = YES;
    [super viewWillDisappear:animated];
    UIViewController *to = [self.transitionCoordinator viewControllerForKey:UITransitionContextToViewControllerKey];
    BOOL leaving = (to && ![to isKindOfClass:DY778RadarTableController.class]) ||
        (self.isMovingFromParentViewController && ![self.navigationController.topViewController isKindOfClass:DY778RadarTableController.class]);
    if (leaving) {
        [self restoreNavigation:animated];
        __weak typeof(self) weakSelf = self;
        [self.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            if (context.isCancelled) [weakSelf applyNavigation:NO];
        }];
    }
}
- (void)refresh {
    CGPoint offset = self.tableView.contentOffset;
    [self.tableView reloadData];
    if (self.hasAppeared) [self restoreTableOffset:offset];
}
- (void)updateTheme {
    UIUserInterfaceStyle style = DY778RadarStyle();
    if (self.overrideUserInterfaceStyle != style) self.overrideUserInterfaceStyle = style;
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new]; [appearance configureWithOpaqueBackground];
    UITraitCollection *traits = [UITraitCollection traitCollectionWithUserInterfaceStyle:style];
    appearance.backgroundColor = [DY778Background() resolvedColorWithTraitCollection:traits];
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor.labelColor resolvedColorWithTraitCollection:traits]};
    UIColor *accent = [DY778RadarAccent() resolvedColorWithTraitCollection:traits];
    appearance.buttonAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: accent};
    appearance.doneButtonAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: accent};
    appearance.backButtonAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: accent};
    self.navigationItem.standardAppearance = appearance; self.navigationItem.scrollEdgeAppearance = appearance; self.navigationItem.compactAppearance = appearance;
    if (self.view.window && self.navigationController.topViewController == self) self.navigationController.navigationBar.tintColor = accent;
    [self setNeedsStatusBarAppearanceUpdate];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; if (self.isViewLoaded) [self updateTheme]; }
- (UIStatusBarStyle)preferredStatusBarStyle { return DY778RadarStyle() == UIUserInterfaceStyleDark ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView; if (!header) return;
    CGFloat width = self.tableView.bounds.size.width;
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat height = ceil(size.height);
    if (height > 0 && (fabs(header.frame.size.height - height) > 0.5 || fabs(header.frame.size.width - width) > 0.5)) {
        header.frame = CGRectMake(0, 0, width, height); self.tableView.tableHeaderView = header;
    }
}
- (BOOL)checkAccount:(NSString *)account {
    [DY778RadarMonitor.shared synchronizeAccount];
    if ([account isEqual:DY778RadarStore.shared.accountID] && account.length) return YES;
    DY778RadarMessage(self, @"账号已切换", @"已停止本次操作，请返回重新打开页面。"); return NO;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
void DY778RadarOpenSettings(void) {
    [DY778RadarMonitor.shared synchronizeAccount];
    DY778PresentController(DY778TopController(), [DY778RadarSettingsController new]);
}
