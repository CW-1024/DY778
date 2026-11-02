#import "DY778Core.h"
#import "DY778Recall.h"
#import "DY778EditHistory.h"
#import "DY778LuckyBag.h"
#import "DY778MessageUI.h"
#import "DY778Avatar.h"
#import "DY778Help.h"
#import "DY778RecallNotifications.h"
#import "DY778CacheCleaner.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static UIImage *DY778EntryIcon(void);
static NSString *DY778BuildTimeLabel(void) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:8 * 60 * 60];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    NSDate *date = [formatter dateFromString:DY778BuildTime];
    if (!date) return DY778BuildTime;
    formatter.dateFormat = @"yyyy年M月d日 HH:mm";
    return [[formatter stringFromDate:date] stringByAppendingString:@"（UTC+8）"];
}

static NSDictionary *DY778Row(NSString *title, NSString *subtitle, NSString *kind, NSString *key, NSString *icon) {
    return @{@"title": title ?: @"", @"subtitle": subtitle ?: @"", @"kind": kind, @"key": key, @"icon": icon ?: @"circle"};
}
static NSDictionary *DY778Options(NSString *title, NSString *key, NSArray *labels, NSArray *values) {
    NSMutableDictionary *row = [DY778Row(title, @"", @"choice", key, @"slider.horizontal.3") mutableCopy];
    row[@"labels"] = labels; row[@"values"] = values; return row;
}
static NSDictionary *DY778Range(NSString *title, NSString *key, double low, double high, NSString *unit) {
    NSMutableDictionary *row = [DY778Row(title, @"", @"slider", key, @"slider.horizontal.3") mutableCopy];
    row[@"min"] = @(low); row[@"max"] = @(high); row[@"unit"] = unit; return row;
}
static NSDictionary *DY778Section(NSString *title, NSString *footer, NSArray *rows) {
    return @{@"title": title, @"footer": footer ?: @"", @"rows": rows};
}
@interface DY778SliderCell : UITableViewCell
@property(nonatomic, strong) UILabel *name;
@property(nonatomic, strong) UILabel *valueLabel;
@property(nonatomic, strong) UISlider *slider;
@property(nonatomic, copy) NSString *preferenceKey;
@property(nonatomic, copy) NSString *unit;
@end
@implementation DY778SliderCell
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])) {
        self.backgroundColor = DY778CardBackground(); self.selectionStyle = UITableViewCellSelectionStyleNone;
        _name = [UILabel new]; _name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _name.adjustsFontForContentSizeCategory = YES; _name.numberOfLines = 0; _name.textColor = UIColor.labelColor;
        _valueLabel = [UILabel new]; _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
        _valueLabel.textColor = DY778Accent();
        [_valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[_name, _valueLabel]]; top.spacing = 12;
        _slider = [UISlider new]; _slider.minimumTrackTintColor = DY778Accent();
        [_slider addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[top, _slider]];
        stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 7; stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:15],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
            [_slider.heightAnchor constraintGreaterThanOrEqualToConstant:36]
        ]];
    }
    return self;
}
- (void)updateValue {
    if ([self.unit isEqualToString:@"%"])
        self.valueLabel.text = [NSString stringWithFormat:@"%.0f%%", self.slider.value * 100];
    else if ([self.unit isEqualToString:@"pt"])
        self.valueLabel.text = [NSString stringWithFormat:@"%.0f pt", self.slider.value];
    else self.valueLabel.text = [NSString stringWithFormat:@"%.1f 秒", self.slider.value];
    self.slider.accessibilityValue = self.valueLabel.text;
}
- (void)changed:(UISlider *)slider {
    float value = [self.unit isEqualToString:@"pt"] ? roundf(slider.value) : roundf(slider.value * 100) / 100;
    slider.value = value; [self updateValue]; DY778Set(self.preferenceKey, @(value));
}
@end

@interface DY778SettingsViewController : UITableViewController <UIColorPickerViewControllerDelegate>
@property(nonatomic, copy) NSString *page;
@property(nonatomic, strong) NSArray *sections;
@property(nonatomic, copy) NSString *colorKey;
@property(nonatomic, strong) UIStackView *headerStack;
@property(nonatomic, strong) UIView *preview;
@property(nonatomic, strong) UIImageView *aboutAvatar;
@property(nonatomic, weak) UIAlertController *formatAlert;
@property(nonatomic, weak) UIAlertController *numberAlert;
@property(nonatomic, copy) NSString *numberKey;
@property(nonatomic, weak) UIAlertController *rateAlert;
@property(nonatomic, copy) NSString *rateKey;
@property(nonatomic) BOOL cacheStatisticsPending;
@property(nonatomic, strong) NSDictionary *cacheStatistics;
@property(nonatomic) BOOL needsRefresh;
@property(nonatomic) BOOL resizingHeader;
@end
@implementation DY778SettingsViewController
- (instancetype)initWithPage:(NSString *)page {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.page = page;
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.cacheStatistics = DY778CachedCacheStatistics();
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 72;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.opaque = YES; self.tableView.clipsToBounds = YES;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 20, 0, 20);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 6;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(preferencesChanged:) name:DY778PreferencesChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(environmentChanged:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(environmentChanged:) name:UIContentSizeCategoryDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(archiveChanged:) name:DY778RecallChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cacheStatisticsChanged:) name:DY778CacheStatisticsChangedNotification object:nil];
    if ([self.page isEqualToString:@"cache"]) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshCacheUsage)];
        self.navigationItem.rightBarButtonItem.accessibilityLabel = @"重新统计缓存";
        self.refreshControl = [UIRefreshControl new]; self.refreshControl.tintColor = DY778Accent();
        [self.refreshControl addTarget:self action:@selector(refreshCacheUsage) forControlEvents:UIControlEventValueChanged];
    }
    [self refresh];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.aboutAvatar) DY778LoadCurrentAccountAvatar(self.aboutAvatar);
    if ([self.page isEqualToString:@"cache"] || [self.page isEqualToString:@"home"]) [self loadCacheUsage:NO];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (self.needsRefresh) [self refresh]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (UIStatusBarStyle)preferredStatusBarStyle { return DY778InterfaceStyle() == UIUserInterfaceStyleDark ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent; }
- (BOOL)isCurrentPage { return self.isViewLoaded && self.view.window && self.navigationController.topViewController == self; }
- (void)environmentChanged:(NSNotification *)notification {
    self.needsRefresh = YES;
    if ([self isCurrentPage]) { [self refresh]; if ([self.page isEqualToString:@"cache"] || [self.page isEqualToString:@"home"]) [self loadCacheUsage:NO]; }
}
- (void)archiveChanged:(NSNotification *)notification {
    if (![self.page isEqualToString:@"recall"]) return;
    if (![self isCurrentPage]) { self.needsRefresh = YES; return; }
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
        if (![[self rowAt:path][@"key"] isEqualToString:@"archive"]) continue;
        [self.tableView cellForRowAtIndexPath:path].detailTextLabel.text = [NSString stringWithFormat:@"%lu 条已撤回记录 · 点击查看", (unsigned long)DY778RecallCount()];
    }
}
- (void)preferencesChanged:(NSNotification *)notification {
    NSString *key = notification.userInfo[@"key"];
    BOOL theme = !key.length || [key isEqualToString:@"appearance"] || [key isEqualToString:@"accent"];
    BOOL preview = [key hasPrefix:@"time."] || [key hasPrefix:@"edit."] || [@[@"recall.enabled", @"recall.badge", @"recall.badgeText", @"recall.position", @"recall.tintBubble", @"recall.plainBubbleOnSkin", @"recall.bubbleColor"] containsObject:key];
    BOOL relevant = theme || [self.page isEqualToString:@"home"] || [self.page isEqualToString:@"about"] ||
        [key hasPrefix:[self.page stringByAppendingString:@"."]];
    if (!relevant) return;
    if (![self isCurrentPage]) { self.needsRefresh = YES; return; }
    if ([key isEqualToString:@"time.fontSize"] || [key isEqualToString:@"time.opacity"] ||
        [key isEqualToString:@"time.color"] || [key isEqualToString:@"recall.bubbleColor"] || [key isEqualToString:@"edit.bubbleColor"]) {
        [UIView performWithoutAnimation:^{ [self updatePreview]; }]; return;
    }
    if ([key isEqualToString:@"lucky.delay"]) return;
    [self refresh];
    if (preview && !theme) [UIView performWithoutAnimation:^{ [self updatePreview]; }];
}
- (void)refresh {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; }); return; }
    CGPoint offset = self.tableView.contentOffset;
    BOOL first = self.sections == nil;
    self.needsRefresh = NO;
    [UIView performWithoutAnimation:^{
        DY778StyleController(self); self.tableView.backgroundColor = DY778Background(); self.tableView.separatorColor = UIColor.separatorColor;
        [self buildSections];
        if (!self.tableView.tableHeaderView) [self buildHeader];
        [self updatePreview];
        [self.tableView reloadData];
        if (!first) [self.tableView setContentOffset:offset animated:NO];
    }];
}
- (void)buildSections {
    if ([self.page isEqualToString:@"home"]) {
        self.title = @"DY778";
        self.sections = @[
            DY778Section(@"消息", @"", @[
                DY778Row(@"消息留存", @"防撤回、会话记录与作品预览", @"nav", @"recall", @"tray.full.fill"),
                DY778Row(@"编辑历史", @"查看对方消息的原文、编辑版本和时间", @"nav", @"edit", @"pencil.circle"),
                DY778Row(@"时间标签", @"格式、位置与颜色", @"nav", @"time", @"clock.fill")]),
            DY778Section(@"直播与播放", @"", @[
                DY778Row(@"福袋助手", @"参与条件、开奖提醒与参与记录", @"nav", @"lucky", @"gift.fill"),
                DY778Row(@"视频播放", @"默认倍速、播完暂停与长按倍速", @"nav", @"playback", @"play.rectangle.fill")]),
            DY778Section(@"测试功能", @"仅处理推荐页的视频和图文。综合原生广告标记、软广信息、交易信息与促销文案判断，不因品牌名直接跳过。保护已关注、点赞或收藏的作品；下滑可回看，近期已跳过的作品不会再次跳过。", @[
                DY778Row(@"跳过疑似广告", @"谨慎识别 · 不确定时保留", @"switch", @"experimental.skipAds", @"line.3.horizontal.decrease.circle")]),
            DY778Section(@"设置", @"DY778 1.0-1 · 设置即时生效", @[
                DY778Row(@"缓存管理", @"查看占用、手动清理与自动整理", @"nav", @"cache", @"internaldrive.fill"),
                DY778Row(@"外观", @"主题与点缀色", @"nav", @"appearance", @"paintpalette.fill"),
                DY778Row(@"关于 DY778", @"版本信息、开源项目与频道", @"nav", @"about", @"info.circle")])
        ];
    } else if ([self.page isEqualToString:@"edit"]) {
        self.title = @"编辑历史";
        self.sections = @[
            DY778Section(@"记录对方的编辑", @"与消息防撤回独立开关。开启后记录本机实际收到的消息版本；聊天信息页可单独管理每个会话。", @[
                DY778Row(@"记录编辑历史", @"保留原文和收到的编辑版本", @"switch", @"edit.enabled", @"pencil.circle"),
                DY778Row(@"编辑历史标记", @"消息旁显示入口，点按直达该条历史", @"switch", @"edit.badge", @"text.badge.plus"),
                DY778Row(@"标记文字", @"自定义文字或表情，后方显示已留存编辑次数", @"action", @"edit.badgeText", @"character.cursor.ibeam"),
                DY778Options(@"标记位置", @"edit.position", @[@"紧贴消息右侧", @"消息下方", @"消息上方"], @[@"right", @"below", @"above"]),
                DY778Row(@"聊天信息页入口", @"查看当前会话的全部编辑记录", @"switch", @"edit.archiveEntry", @"clock.arrow.circlepath")]),
            DY778Section(@"查看历史", @"按会话、消息和版本整理，区分原消息发送时间、编辑时间和本机接收时间。首次接收时已编辑的消息会注明原文未取得。", @[
                DY778Row(@"查看编辑历史", @"原文、各次编辑、最近变化与会话统计", @"action", @"editArchive", @"clock.arrow.circlepath")]),
            DY778Section(@"编辑消息外观", @"底色开关默认关闭，关闭时保持原来的气泡颜色。仅调整原本有背景的气泡；透明表情、图片和视频画面保持原样。同一条消息也已撤回时，已开启的撤回底色优先。", @[
                DY778Row(@"自定义编辑气泡底色", @"独立控制，不影响撤回气泡设置", @"switch", @"edit.tintBubble", @"paintbrush.pointed"),
                DY778Row(@"编辑气泡颜色", @"上方预览实时显示样式", @"color", @"edit.bubbleColor", @"eyedropper")]),
            DY778Section(@"编辑提醒", @"默认关闭。仅提醒本机已留存消息的新编辑版本，首次加载时已编辑的旧消息不提醒。前台显示卡片，后台实际收到事件时发送本地通知；点按直达该条历史。", @[
                DY778Row(@"对方编辑时提醒", @"仅对已开启编辑历史的会话生效", @"switch", @"edit.notifications", @"bell.badge"),
                DY778Row(@"提醒显示消息摘要", @"默认不显示正文，开启后显示最新留存内容", @"switch", @"edit.notificationPreview", @"text.bubble"),
                DY778Row(@"通知状态", @"检查系统权限与后台提醒说明", @"action", @"notificationStatus", @"bell")]),
            DY778Section(@"记录保留", @"0 表示不限。版本仅保存在本机；应用离线、挂起或未启用期间的版本无法补回。", @[
                DY778Row(@"历史保存天数", @"按最近编辑或留存时间计算", @"number", @"edit.retentionDays", @"calendar"),
                DY778Row(@"消息数量上限", @"每条消息的多个版本一起保留", @"number", @"edit.maxRecords", @"list.number")]),
            DY778Section(@"管理记录", DY778EditHistoryStatus(), @[
                DY778Row(@"清空编辑历史", @"仅清空当前账号，可在历史内按会话删除", @"danger", @"clearEdits", @"trash")])];
    } else if ([self.page isEqualToString:@"recall"]) {
        self.title = @"消息留存";
        self.sections = @[
            DY778Section(@"按会话留存", @"开启总开关后，所有会话默认启用。聊天右上角 ··· → 本会话防撤回，可以单独关闭或开启，修改立即生效。", @[
                DY778Row(@"消息防撤回", @"保留本机已接收到的对方消息", @"switch", @"recall.enabled", @"arrow.uturn.backward.circle.fill"),
                DY778Row(@"撤回标记", @"显示已撤回状态，点按查看记录", @"switch", @"recall.badge", @"text.badge.checkmark"),
                DY778Row(@"标记文字", @"默认为已撤回，可自定义文字或表情", @"action", @"recall.badgeText", @"character.cursor.ibeam"),
                DY778Options(@"标记位置", @"recall.position", @[@"紧贴消息右侧", @"消息下方", @"消息上方"], @[@"right", @"below", @"above"]),
                DY778Row(@"聊天信息页记录入口", @"在会话设置中查看对应的撤回记录", @"switch", @"recall.archiveEntry", @"tray.full")]),
            DY778Section(@"查看留存", @"按联系人和群聊整理，作品卡片直接打开对应原作品。", @[
                DY778Row(@"已撤回的消息", @"按会话查看文字、图片、表情与作品", @"action", @"archive", @"person.2")]),
            DY778Section(@"撤回提醒", @"仅提醒已开启防撤回的会话。前台显示消息卡片；后台收到事件时发送系统通知。抖音被系统挂起或关闭时，插件不能独立接收新消息。", @[
                DY778Row(@"对方撤回时提醒", @"前台提醒卡片 · 后台系统通知", @"switch", @"recall.notifications", @"bell.badge"),
                DY778Row(@"提醒显示消息摘要", @"允许在通知中显示已保存的文字或作品标题", @"switch", @"recall.notificationPreview", @"text.bubble"),
                DY778Row(@"通知状态", @"检查系统权限与后台提醒说明", @"action", @"notificationStatus", @"bell")]),
            DY778Section(@"撤回消息外观", @"默认保留原气泡皮肤。开启普通气泡后，只替换文字消息的皮肤装饰；自定义撤回颜色开启时优先使用该颜色。表情、图片和视频保持原样。右侧同时显示时间与标记时，自动上下排列。", @[
                DY778Row(@"撤回后使用普通气泡", @"默认保留皮肤；开启后恢复纯色气泡", @"switch", @"recall.plainBubbleOnSkin", @"circle.lefthalf.filled"),
                DY778Row(@"自定义撤回气泡底色", @"让保留的消息更容易辨认", @"switch", @"recall.tintBubble", @"paintbrush.pointed"),
                DY778Row(@"撤回气泡颜色", @"选择适合当前聊天背景的颜色", @"color", @"recall.bubbleColor", @"eyedropper")]),
            DY778Section(@"记录保留", @"保存消息正文及分享评论首次收到的文字和作者。默认天数和数量均为 0，不自动删除；手动清理或主动设置限制仍会删除记录。作品及媒体能否打开取决于原内容。", @[
                DY778Row(@"记录保存天数", @"0 表示永久保存，直到手动清理", @"number", @"recall.retentionDays", @"calendar"),
                DY778Row(@"记录数量上限", @"0 表示不限制条数", @"number", @"recall.maxRecords", @"list.number")]),
            DY778Section(@"管理本机空间", @"也可以在联系人记录中只清理一个会话。以下操作仅影响当前账号，清理前会再次确认。", @[
                DY778Row(@"记录统计", @"查看当前账号的撤回记录和会话数量", @"action", @"storageStats", @"externaldrive"),
                DY778Row(@"清空当前账号记录", @"删除全部本地消息记录", @"danger", @"clearArchive", @"trash")])
        ];
    } else if ([self.page isEqualToString:@"time"]) {
        self.title = @"时间标签";
        self.sections = @[
            DY778Section(@"显示", @"右侧紧贴实际气泡或分享卡片边缘。与撤回标记同处右侧时上下排列，空间不足自动避让，不遮挡消息。", @[
                DY778Row(@"显示消息时间", @"每条消息的时间清楚可见", @"switch", @"time.enabled", @"clock"),
                DY778Row(@"隐藏原生时间提示", @"自定义时间开启时生效", @"switch", @"time.hideOfficial", @"eye.slash"),
                DY778Options(@"标签位置", @"time.position", @[@"紧贴消息右侧", @"气泡下方", @"气泡上方"], @[@"right", @"below", @"above"])]),
            DY778Section(@"时间格式", @"智能日期会区分今天、昨天和更早日期。自定义格式使用 Apple 日期格式，例如 HH:mm:ss、MM-dd HH:mm。", @[
                DY778Options(@"时间样式", @"time.format", @[@"14:26", @"14:26:08", @"10-30 14:26", @"2026-10-30 14:26:08"], @[@"HH:mm", @"HH:mm:ss", @"MM-dd HH:mm", @"yyyy-MM-dd HH:mm:ss"]),
                DY778Row(@"自定义格式", @"编辑并实时预览效果", @"action", @"customFormat", @"character.cursor.ibeam"),
                DY778Row(@"智能日期", @"让不同时段一眼可辨", @"switch", @"time.smartDate", @"calendar")]),
            DY778Section(@"标签外观", @"上方预览会随设置更新。颜色在不同背景下会调整可读性。", @[
                DY778Range(@"文字大小", @"time.fontSize", 9, 17, @"pt"),
                DY778Row(@"文字颜色", @"选择自定义文字颜色", @"color", @"time.color", @"eyedropper"),
                DY778Row(@"胶囊背景", @"增强复杂聊天背景下的辨识度", @"switch", @"time.background", @"capsule"),
                DY778Range(@"标签不透明度", @"time.opacity", .35, 1, @"%")])
        ];
    } else if ([self.page isEqualToString:@"lucky"]) {
        self.title = @"福袋助手";
        self.sections = @[
            DY778Section(@"进入直播后开始", @"仅处理普通免费福袋。确认模式先展示本场信息；自动模式静默发送所需评论并报名。成功后简短提示，灯牌条件不符时提示跳过。", @[
                DY778Row(@"启用福袋助手", @"只处理你当前正在观看的直播间", @"switch", @"lucky.enabled", @"gift"),
                DY778Options(@"参与方式", @"lucky.mode", @[@"确认后参与", @"自动参与"], @[@"confirm", @"auto"]),
                DY778Row(@"发现福袋时弹窗", @"确认后参与模式下显示；自动模式不弹窗", @"switch", @"lucky.prompt", @"rectangle.on.rectangle"),
                DY778Range(@"操作等待时间", @"lucky.delay", .5, 5, @"秒")]),
            DY778Section(@"直播里的提示", @"已有本主播有效灯牌且等级达标时继续报名；未达标时提醒跳过，资格查询失败会单独说明。同场不重复提醒，详细结果可在记录中查看。", @[
                DY778Row(@"直播悬浮入口", @"小型入口可拖动，点按查看本场福袋", @"switch", @"lucky.showStatus", @"waveform.path"),
                DY778Row(@"收起悬浮入口", @"收起时只显示图标，长按切换展开状态", @"switch", @"lucky.compact", @"rectangle.compress.vertical"),
                DY778Row(@"轻触反馈", @"需要处理或参与确认时提供触感", @"switch", @"lucky.haptics", @"hand.tap")]),
            DY778Section(@"离开直播后", @"历史只记录已经发生的操作与结果，退出房间后不会继续执行旧任务。", @[
                DY778Row(@"最近参与记录", @"查看房间、奖品、时间与参与状态", @"action", @"luckyHistory", @"clock.arrow.circlepath")])
        ];
    } else if ([self.page isEqualToString:@"playback"]) {
        self.title = @"视频播放";
        self.sections = @[
            DY778Section(@"播放结束", @"暂停后可手动重播或切换下一条。", @[
                DY778Row(@"看完视频作品自动暂停", @"视频播放结束时暂停", @"switch", @"playback.stopAtEnd", @"pause.circle")]),
            DY778Section(@"默认播放速度", @"仅对视频作品生效，直播和图文不调整。长按加速优先，松手后恢复正常播放速度。", @[
                DY778Row(@"视频作品默认倍速", @"首次关闭，开启后使用所选倍速", @"switch", @"playback.defaultEnabled", @"play.circle"),
                DY778Options(@"默认倍速", @"playback.defaultRate", @[@"1.25×", @"2×", @"2.5×", @"3×"], @[@1.25, @2, @2.5, @3]),
                DY778Row(@"自定义默认倍速", @"支持 1×–3×，最多两位小数", @"action", @"customDefaultPlaybackRate", @"speedometer")]),
            DY778Section(@"长按倍速", @"只在长按加速期间使用所选速度，松手或取消手势后恢复。", @[
                DY778Row(@"自定义长按倍速", @"使用抖音原有的长按加速手势", @"switch", @"playback.longPressEnabled", @"hand.point.up.left"),
                DY778Options(@"长按速度", @"playback.longPressRate", @[@"1×", @"1.25×", @"1.5×", @"2×", @"2.5×", @"3×"], @[@1, @1.25, @1.5, @2, @2.5, @3]),
                DY778Row(@"自定义速度", @"支持 1×–3×，最多两位小数，默认 2×", @"action", @"customPlaybackRate", @"speedometer")])
        ];
    } else if ([self.page isEqualToString:@"cache"]) {
        self.title = @"缓存管理";
        self.sections = @[
            DY778Section(@"本机缓存", @"清空应用缓存、临时文件、页面资源、投屏缓存和日志，仅保留识别到的插件配置。下拉刷新用量。", @[
                DY778Row(@"缓存用量", @"正在统计…", @"info", @"hostCacheUsage", @"internaldrive"),
                DY778Row(@"清理全部缓存", @"清空缓存目录，保留插件配置", @"action", @"cleanHostCache", @"sparkles"),
                DY778Row(@"最近清理", @"尚未清理", @"info", @"lastCacheClean", @"clock.arrow.circlepath")]),
            DY778Section(@"打开时清理", @"两个开关独立生效，每次触发都会清空上述缓存，顶部显示本次清理量。与下方容量、时间规则无关。", @[
                DY778Row(@"启动抖音时清理", @"抖音重新启动后执行一次", @"switch", @"cache.onLaunch", @"power"),
                DY778Row(@"从后台返回时清理", @"从其他应用返回抖音后执行一次", @"switch", @"cache.onReturn", @"arrow.clockwise.circle")]),
            DY778Section(@"自动整理", @"上限针对上述目录中的缓存，插件配置不计入。超限时先清理最旧文件；手动清空无需开启此项。", @[
                DY778Row(@"按规则自动清理", @"按容量与时间整理，最旧文件优先", @"switch", @"cache.enabled", @"arrow.triangle.2.circlepath"),
                DY778Row(@"可管理缓存上限", @"单位 MB，0 表示不限制", @"number", @"cache.maxMB", @"internaldrive")]),
            DY778Section(@"文件存放时间", @"时间与容量分别生效。“从不”只关闭按时间清理，容量超限仍会整理。使用抖音时新产生的缓存会计入下一次检查。", @[
                DY778Options(@"超过多久清理", @"cache.maxAgeHours", @[@"从不", @"1 天", @"1 周", @"1 个月（30 天）"], @[@0, @24, @168, @720]),
                DY778Row(@"自定义小时数", @"按文件存放时间计算，0 表示从不", @"action", @"customCacheHours", @"clock.badge.checkmark")])
        ];
    } else if ([self.page isEqualToString:@"appearance"]) {
        self.title = @"外观";
        self.sections = @[
            DY778Section(@"主题", @"跟随抖音时，插件页面会同步抖音的深浅色设置。独立主题仅作用于 DY778 界面。", @[
                DY778Options(@"背景主题", @"appearance", @[@"跟随抖音", @"浅色", @"深色"], @[@"system", @"light", @"dark"]),
                DY778Row(@"点缀色", @"按钮、图标与卡片的统一色彩", @"color", @"accent", @"paintpalette")])
        ];
    } else {
        self.title = @"关于 DY778";
        self.sections = @[
            DY778Section(@"版本信息", @"", @[
                DY778Row(@"插件名称", @"DY778", @"info", @"pluginName", @"app.badge"),
                DY778Row(@"版本号", DY778Version, @"info", @"pluginVersion", @"number.circle"),
                DY778Row(@"构建时间", DY778BuildTimeLabel(), @"info", @"buildTime", @"clock")]),
            DY778Section(@"项目与频道", @"", @[
                DY778Row(@"开源项目", @"https://github.com/jijiang2333/DY778", @"link", @"https://github.com/jijiang2333/DY778", @"chevron.left.forwardslash.chevron.right"),
                DY778Row(@"TG 频道", @"https://t.me/JiJiang_778", @"link", @"https://t.me/JiJiang_778", @"paperplane")]),
            DY778Section(@"使用指南", @"仅在抖音 39.9.0 测试，其他版本请自行测试。", @[
                DY778Row(@"使用说明", @"消息留存、编辑历史与常用设置", @"action", @"help", @"book.closed")]),
            DY778Section(@"偏好管理", @"重置仅恢复 DY778 设置，不删除已保存的消息。", @[
                DY778Row(@"恢复默认设置", @"保留消息记录，关闭福袋自动参与", @"danger", @"reset", @"arrow.counterclockwise")])
        ];
    }
}
- (void)buildHeader {
    BOOL showsPreview = [@[@"time", @"recall", @"edit"] containsObject:self.page];
    BOOL about = [self.page isEqual:@"about"];
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, showsPreview ? 160 : .01)];
    container.backgroundColor = DY778Background(); container.opaque = YES; container.clipsToBounds = YES;
    self.tableView.tableHeaderView = container;
    if (!showsPreview && !about) return;
    self.headerStack = [UIStackView new]; self.headerStack.axis = UILayoutConstraintAxisVertical;
    self.headerStack.translatesAutoresizingMaskIntoConstraints = NO; [container addSubview:self.headerStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.headerStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [self.headerStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20],
        [self.headerStack.topAnchor constraintEqualToAnchor:container.topAnchor constant:about ? 24 : 8],
        [self.headerStack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:about ? -24 : -8]
    ]];
    if (about) {
        self.headerStack.alignment = UIStackViewAlignmentCenter;
        self.aboutAvatar = [UIImageView new];
        self.aboutAvatar.contentMode = UIViewContentModeScaleAspectFill;
        self.aboutAvatar.layer.cornerRadius = 44; self.aboutAvatar.clipsToBounds = YES;
        self.aboutAvatar.isAccessibilityElement = YES; self.aboutAvatar.accessibilityLabel = @"当前账号头像";
        [NSLayoutConstraint activateConstraints:@[[self.aboutAvatar.widthAnchor constraintEqualToConstant:88], [self.aboutAvatar.heightAnchor constraintEqualToConstant:88]]];
        [self.headerStack addArrangedSubview:self.aboutAvatar];
        DY778LoadCurrentAccountAvatar(self.aboutAvatar);
        [self sizeHeader]; return;
    }
    [self updatePreview];
}
- (void)updatePreview {
    self.tableView.tableHeaderView.backgroundColor = DY778Background();
    if (!self.headerStack) return;
    if ([self.page isEqual:@"about"]) { DY778LoadCurrentAccountAvatar(self.aboutAvatar); [self sizeHeader]; return; }
    if (!self.preview) {
        self.preview = [self.page isEqualToString:@"edit"] ? DY778CreateEditPreview() : DY778CreateTimePreview();
        if (self.preview) {
            self.preview.clipsToBounds = YES; [self.headerStack addArrangedSubview:self.preview];
            [self.preview.heightAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
        }
    }
    [self.preview setNeedsLayout]; [self sizeHeader];
}
- (void)sizeHeader {
    UIView *header = self.tableView.tableHeaderView; if (self.resizingHeader || !self.headerStack || !header || self.tableView.bounds.size.width < 1) return;
    self.resizingHeader = YES;
    CGFloat width = self.tableView.bounds.size.width;
    CGSize fitted = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                       withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(header.frame.size.height - fitted.height) > .5 || fabs(header.frame.size.width - width) > .5) {
        [UIView performWithoutAnimation:^{ header.frame = CGRectMake(0, 0, width, fitted.height); self.tableView.tableHeaderView = header; }];
    }
    self.resizingHeader = NO;
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self sizeHeader]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { NSString *footer = self.sections[section][@"footer"]; return footer.length ? footer : nil; }
- (NSDictionary *)rowAt:(NSIndexPath *)path { return self.sections[path.section][@"rows"][path.row]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *row = [self rowAt:path]; NSString *kind = row[@"kind"], *key = row[@"key"];
    if ([kind isEqualToString:@"slider"]) {
        DY778SliderCell *cell = [DY778SliderCell new]; cell.name.text = row[@"title"]; cell.preferenceKey = key; cell.unit = row[@"unit"];
        cell.slider.minimumValue = [row[@"min"] floatValue]; cell.slider.maximumValue = [row[@"max"] floatValue];
        cell.slider.value = DY778Number(key); cell.slider.accessibilityLabel = row[@"title"]; [cell updateValue]; return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = DY778CardBackground(); cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0; cell.textLabel.text = row[@"title"];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0; cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.text = row[@"subtitle"]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = [UIImage systemImageNamed:row[@"icon"] withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightMedium]];
    cell.imageView.tintColor = DY778Accent();
    cell.contentView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(17, 20, 17, 16);
    if ([kind isEqualToString:@"switch"]) {
        UISwitch *toggle = [UISwitch new]; toggle.on = DY778Bool(key); toggle.onTintColor = DY778Accent();
        toggle.accessibilityLabel = row[@"title"]; toggle.accessibilityHint = row[@"subtitle"];
        objc_setAssociatedObject(toggle, @selector(toggleChanged:), key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([kind isEqualToString:@"choice"]) {
        id value = [DY778Preferences() objectForKey:key]; NSUInteger index = [row[@"values"] indexOfObject:value];
        cell.detailTextLabel.text = index != NSNotFound ? row[@"labels"][index] : [NSString stringWithFormat:@"自定义 · %@", value ?: @""];
    } else if ([kind isEqualToString:@"number"]) {
        long long value = (long long)DY778Number(key);
        NSString *unit = [key hasSuffix:@"MB"] ? @"MB" : ([key hasSuffix:@"retentionDays"] ? @"天" : @"条");
        cell.detailTextLabel.text = value == 0 ? @"不限制 · 点击自定义" : [NSString stringWithFormat:@"%lld %@ · 点击修改", value, unit];
    } else if ([kind isEqualToString:@"color"]) {
        cell.detailTextLabel.text = [DY778String(key) uppercaseString];
        UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
        swatch.backgroundColor = DY778ColorFromHex(DY778String(key), DY778Accent()); swatch.layer.cornerRadius = 14;
        swatch.layer.borderWidth = 1; swatch.layer.borderColor = [UIColor.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        cell.accessoryView = swatch;
    } else if ([kind isEqualToString:@"danger"]) { cell.textLabel.textColor = UIColor.systemRedColor; cell.imageView.tintColor = UIColor.systemRedColor; }
    if ([key isEqualToString:@"recall.badgeText"]) cell.detailTextLabel.text = DY778RecallMarkerText();
    if ([key isEqualToString:@"edit.badgeText"]) cell.detailTextLabel.text = DY778EditMarkerText();
    if ([key isEqualToString:@"customPlaybackRate"]) cell.detailTextLabel.text = [NSString stringWithFormat:@"当前 %g× · 点击输入", DY778Number(@"playback.longPressRate")];
    if ([key isEqualToString:@"customDefaultPlaybackRate"]) cell.detailTextLabel.text = [NSString stringWithFormat:@"当前 %g× · 点击输入", DY778Number(@"playback.defaultRate")];
    if ([key isEqualToString:@"customCacheHours"]) cell.detailTextLabel.text = DY778Number(@"cache.maxAgeHours") > 0 ? [NSString stringWithFormat:@"当前 %.0f 小时 · 点击修改", DY778Number(@"cache.maxAgeHours")] : @"从不按时间清理 · 点击输入";
    if ([key isEqualToString:@"archive"]) cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 条已撤回记录 · 点击查看", (unsigned long)DY778RecallCount()];
    if ([kind isEqualToString:@"nav"] && ![key isEqualToString:@"appearance"] && ![key isEqualToString:@"about"]) {
        NSString *enabledKey = [key stringByAppendingString:@".enabled"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", ([key isEqualToString:@"playback"] ? (DY778Bool(@"playback.stopAtEnd") || DY778Bool(@"playback.longPressEnabled") || DY778Bool(@"playback.defaultEnabled")) : DY778Bool(enabledKey)) ? @"已开启" : @"未开启", row[@"subtitle"]];
    }
    if ([kind isEqualToString:@"info"]) { cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; }
    if ([kind isEqualToString:@"link"]) { cell.accessibilityTraits |= UIAccessibilityTraitLink; cell.detailTextLabel.textColor = DY778Accent(); }
    [self configureCacheCell:cell key:key];
    return cell;
}
- (void)toggleChanged:(UISwitch *)toggle {
    NSString *key = objc_getAssociatedObject(toggle, @selector(toggleChanged:));
    if (toggle.on && [key isEqualToString:@"lucky.enabled"] && !DY778Bool(@"lucky.enableNoticeShown")) {
        [toggle setOn:NO animated:YES];
        __weak typeof(self) weakSelf = self;
        DY778ConfirmDelayed(self, @"福袋助手 · 参与范围", @"仅自动处理普通免费福袋，按本场要求发送评论并完成报名。\n\n需要新点亮粉丝灯牌、提升灯牌等级，或存在送礼、付费等额外条件时，会自动跳过。\n\n已持有本主播的有效灯牌且等级满足要求时，可以继续发送评论并报名。条件不明时不自动操作。\n\n自动模式不展示报名过程。参与成功或因灯牌资格跳过时简短提示，同场不重复提醒。", 2, ^{
            [DY778Preferences() setBool:YES forKey:@"lucky.enableNoticeShown"];
            DY778Set(@"lucky.enabled", @YES); [weakSelf.tableView reloadData];
        });
        return;
    }
    DY778Set(key, @(toggle.on));
    if (toggle.on && [key isEqualToString:@"recall.enabled"] && !DY778Bool(@"recall.enableNoticeShown")) {
        [DY778Preferences() setBool:YES forKey:@"recall.enableNoticeShown"];
        DY778ShowNotice(self, @"消息留存已开启", @"全部会话默认启用。打开聊天右上角 ··· → 本会话防撤回，可以单独关闭或重新开启。\n\n从现在起保存本机收到的消息。撤回提醒可以在本页单独开启。");
    }
    if (toggle.on && [key isEqualToString:@"recall.notifications"]) DY778RequestRecallNotificationPermission(self);
    if (toggle.on && [key isEqualToString:@"edit.notifications"]) DY778RequestEditNotificationPermission(self);
}
- (void)editNumber:(NSDictionary *)row {
    NSString *key = row[@"key"]; self.numberKey = key;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:row[@"title"]
        message:@"输入 0 表示不限制。" preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778InterfaceStyle(); alert.view.tintColor = DY778Accent(); self.numberAlert = alert;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [NSString stringWithFormat:@"%.0f", DY778Number(key)]; field.keyboardType = UIKeyboardTypeNumberPad;
        field.clearButtonMode = UITextFieldViewModeWhileEditing; field.accessibilityLabel = row[@"title"];
        [field addTarget:self action:@selector(numberChanged:) forControlEvents:UIControlEventEditingChanged];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        long long value = weakSelf.numberAlert.textFields.firstObject.text.longLongValue;
        double previous = DY778Number(key);
        if (([key hasPrefix:@"recall."] || [key hasPrefix:@"edit."]) && value > 0 && (previous == 0 || value < previous)) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSString *message = @"超出限制的旧记录将被清理，此操作无法恢复。";
                DY778Confirm(weakSelf, @"应用新的保存限制？", message, @"应用限制", YES, ^{ DY778Set(key, @(value)); });
            });
        } else DY778Set(key, @(value));
    }]];
    [self numberChanged:alert.textFields.firstObject]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)numberChanged:(UITextField *)field {
    NSString *text = field.text ?: @"";
    NSUInteger maximum = [self.numberKey hasSuffix:@"MB"] ? 1048576 : ([self.numberKey isEqualToString:@"cache.maxAgeHours"] ? 876000 : ([self.numberKey hasSuffix:@"retentionDays"] ? 36500 : 10000000));
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    BOOL valid = text.length > 0 && text.length <= 8 && [text rangeOfCharacterFromSet:invalid].location == NSNotFound && text.longLongValue <= (long long)maximum;
    self.numberAlert.actions.lastObject.enabled = valid;
    self.numberAlert.message = valid ? ([self.numberKey isEqualToString:@"cache.maxAgeHours"] ? @"输入小时数。0 表示从不按时间清理，容量限制仍独立生效。" : @"输入 0 表示不限制。清理会优先处理较旧的内容。") : [NSString stringWithFormat:@"请输入 0–%lu 的整数，0 表示不限制。", (unsigned long)maximum];
    if (valid && [self.numberKey isEqualToString:@"cache.maxMB"]) self.numberAlert.message = [NSString stringWithFormat:@"单位 MB · 当前 %@\n0 表示不限容量，插件配置不计入。", text.longLongValue ? DY778CacheFormatBytes(text.longLongValue * 1048576ULL) : @"不限制"];
}
- (void)editMarker:(NSString *)key {
    BOOL edit = [key isEqual:@"edit.badgeText"];
    NSString *fallback = edit ? @"编辑历史" : @"已撤回";
    NSString *title = edit ? @"编辑标记文字" : @"撤回标记文字";
    NSString *message = [NSString stringWithFormat:@"支持文字与表情，最多 12 个字符。换行自动合并，留空恢复“%@”；较长文字会自动省略以避让消息。%@", fallback, edit ? @"后方保留编辑次数。" : @""];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778InterfaceStyle(); alert.view.tintColor = DY778Accent();
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = edit ? DY778EditMarkerText() : DY778RecallMarkerText(); field.placeholder = fallback;
        field.clearButtonMode = UITextFieldViewModeWhileEditing; field.accessibilityLabel = title;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { DY778Set(key, weakAlert.textFields.firstObject.text); }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)editPlaybackRate:(NSString *)key {
    self.rateKey = key;
    BOOL normal = [key isEqualToString:@"playback.defaultRate"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:normal ? @"视频默认倍速" : @"长按播放速度" message:@"输入 1–3 之间的倍数，最多两位小数，例如 1.25 或 2.50。" preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778InterfaceStyle(); alert.view.tintColor = DY778Accent(); self.rateAlert = alert;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [NSString stringWithFormat:@"%g", DY778Number(key)];
        field.keyboardType = UIKeyboardTypeDecimalPad; field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.accessibilityLabel = normal ? @"默认播放倍数" : @"长按速度倍数";
        [field addTarget:self action:@selector(rateChanged:) forControlEvents:UIControlEventEditingChanged];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *value = [weakSelf.rateAlert.textFields.firstObject.text stringByReplacingOccurrencesOfString:@"," withString:@"."];
        DY778Set(key, @(value.doubleValue));
    }]];
    [self rateChanged:alert.textFields.firstObject]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)rateChanged:(UITextField *)field {
    NSString *text = [field.text stringByReplacingOccurrencesOfString:@"," withString:@"."] ?: @"";
    NSScanner *scanner = [NSScanner scannerWithString:text]; scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double rate = 0;
    BOOL valid = text.length > 0 && text.length <= 8 && [scanner scanDouble:&rate] && scanner.isAtEnd && isfinite(rate) && rate >= 1 && rate <= 3 && fabs(rate * 100 - round(rate * 100)) < .000001;
    self.rateAlert.actions.lastObject.enabled = valid;
    self.rateAlert.message = valid ? ([self.rateKey isEqualToString:@"playback.defaultRate"] ? [NSString stringWithFormat:@"开启默认倍速后，视频作品以 %g× 播放。", rate] : [NSString stringWithFormat:@"长按时使用 %g×，松手后恢复原速度。", rate]) : @"请输入 1–3 之间的倍数，最多两位小数，例如 1.25 或 2.50。";
}
- (void)configureCacheCell:(UITableViewCell *)cell key:(NSString *)key {
    NSDictionary *statistics = self.cacheStatistics;
    BOOL busy = [statistics[@"busy"] boolValue], manual = [statistics[@"manual"] boolValue];
    uint64_t available = [statistics[@"bytes"] unsignedLongLongValue];
    if ([key isEqualToString:@"cache"] && statistics) {
        if ([statistics[@"phase"] isEqualToString:@"scanning"] && ![statistics[@"bytes"] unsignedLongLongValue]) { cell.detailTextLabel.text = @"正在统计缓存用量…"; return; }
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 自动清理%@", DY778CacheFormatBytes([statistics[@"bytes"] unsignedLongLongValue]), (DY778Bool(@"cache.enabled") || (DY778Bool(@"cache.onLaunch") || DY778Bool(@"cache.onReturn"))) ? @"已开启" : @"已关闭"];
    } else if ([key isEqualToString:@"cleanHostCache"]) {
        BOOL enabled = busy ? manual : statistics && available > 0 && !self.cacheStatisticsPending;
        cell.textLabel.text = busy && manual ? @"停止本次清理" : @"清理全部缓存";
        cell.detailTextLabel.text = busy ? (manual ? @"随时停止，已清理的空间不会回退" : @"正在检查缓存，请稍候") :
            (statistics ? (available ? @"清空缓存目录，仅保留插件配置" : @"暂无缓存") : @"统计完成后即可清理");
        cell.textLabel.textColor = enabled ? (busy ? UIColor.systemRedColor : DY778Accent()) : UIColor.tertiaryLabelColor;
        cell.imageView.tintColor = cell.textLabel.textColor;
        cell.imageView.image = [UIImage systemImageNamed:busy && manual ? @"stop.circle" : @"sparkles"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessibilityTraits = enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled;
    } else if ([key isEqualToString:@"hostCacheUsage"]) {
        BOOL initial = !statistics || ([statistics[@"phase"] isEqualToString:@"scanning"] && !available);
        cell.textLabel.text = initial ? @"缓存用量" : [NSString stringWithFormat:@"缓存用量  %@", DY778CacheFormatBytes(available)];
        cell.detailTextLabel.text = statistics[@"status"] ?: @"正在统计…";
    } else if ([key isEqualToString:@"lastCacheClean"]) {
        NSDictionary *last = statistics[@"lastCleanup"];
        NSDate *date = last[@"date"];
        if ([date isKindOfClass:NSDate.class]) {
            NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateFormat = @"MM-dd HH:mm";
            NSString *summary = [last[@"deletedCount"] unsignedLongLongValue] ? [NSString stringWithFormat:@"释放 %@ · %@ 个文件", DY778CacheFormatBytes([last[@"deletedBytes"] unsignedLongLongValue]), last[@"deletedCount"]] :
                [last[@"cancelled"] boolValue] ? @"本次已停止" : [last[@"partial"] boolValue] ? @"未释放空间 · 部分文件未能清理" : @"无需清理 · 未发现可清理缓存";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [formatter stringFromDate:date], summary];
        } else cell.detailTextLabel.text = @"尚未完成过清理";
    } else if ([key isEqualToString:@"cache.maxMB"]) {
        double mb = DY778Number(key);
        cell.detailTextLabel.text = mb > 0 ? [NSString stringWithFormat:@"%@ · 点击修改", DY778CacheFormatBytes((uint64_t)(mb * 1048576))] : @"不限制 · 点击自定义";
    }
}
- (void)updateCacheUsage {
    if (![self.page isEqualToString:@"cache"] && ![self.page isEqualToString:@"home"]) return;
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) [self configureCacheCell:[self.tableView cellForRowAtIndexPath:path] key:[self rowAt:path][@"key"]];
    if ([self.page isEqualToString:@"cache"]) self.navigationItem.rightBarButtonItem.enabled = !self.cacheStatisticsPending && ![self.cacheStatistics[@"busy"] boolValue];
}
- (void)cacheStatisticsChanged:(NSNotification *)notification {
    if (![self.page isEqualToString:@"cache"] && ![self.page isEqualToString:@"home"]) return;
    self.cacheStatistics = notification.userInfo;
    if ([self isCurrentPage]) {
        [self updateCacheUsage];
        if (![self.cacheStatistics[@"busy"] boolValue] && !self.tableView.dragging && !self.tableView.decelerating)
            [UIView performWithoutAnimation:^{ [self.tableView beginUpdates]; [self.tableView endUpdates]; }];
    }
}
- (void)loadCacheUsage:(BOOL)refresh {
    if (self.cacheStatisticsPending) { [self.refreshControl endRefreshing]; return; }
    self.cacheStatisticsPending = YES; [self updateCacheUsage];
    __weak typeof(self) weakSelf = self;
    void (^completion)(NSDictionary *) = ^(NSDictionary *statistics) {
        DY778SettingsViewController *self = weakSelf; if (!self) return;
        self.cacheStatistics = statistics; self.cacheStatisticsPending = NO;
        [self.refreshControl endRefreshing]; [self updateCacheUsage];
    };
    if (refresh) DY778RefreshCacheStatistics(completion); else DY778CacheStatistics(completion);
}
- (void)refreshCacheUsage { [self loadCacheUsage:YES]; }
- (void)cleanHostCache {
    if ([self.cacheStatistics[@"busy"] boolValue]) {
        if ([self.cacheStatistics[@"manual"] boolValue]) { DY778CancelHostCacheCleanup(); DY778Toast(@"正在停止本次清理"); }
        return;
    }
    uint64_t available = [self.cacheStatistics[@"bytes"] unsignedLongLongValue];
    if (self.cacheStatisticsPending || !available) return;
    NSString *message = [NSString stringWithFormat:@"当前用量 %@。将清空应用缓存、临时文件、页面资源、投屏缓存和日志，仅保留识别到的插件配置。清理后会重新统计，继续使用时可能产生新缓存。", DY778CacheFormatBytes(available)];
    __weak typeof(self) weakSelf = self;
    DY778Confirm(self, @"清空全部缓存？", message, @"开始清理", NO, ^{
        DY778SettingsViewController *self = weakSelf; if (!self || [self.cacheStatistics[@"busy"] boolValue]) return;
        NSMutableDictionary *pending = [self.cacheStatistics mutableCopy]; pending[@"busy"] = @YES; pending[@"manual"] = @YES;
        pending[@"status"] = @"正在重新检查可清理文件"; self.cacheStatistics = pending; [self updateCacheUsage];
        DY778ShowToast(@"cache.manual", @"正在清理缓存", YES, NO);
        DY778CleanHostCache(^(NSDictionary *result) {
            DY778SettingsViewController *self = weakSelf;
            self.cacheStatistics = result; [self updateCacheUsage];
            BOOL cancelled = [result[@"cancelled"] boolValue];
            NSString *message = [NSString stringWithFormat:@"%@ · 本次已清理 %@", cancelled ? @"已停止" : @"清理完成", DY778CacheFormatBytes([result[@"deletedBytes"] unsignedLongLongValue])];
            if (!cancelled && ![result[@"deletedCount"] unsignedLongLongValue]) message = @"缓存已检查 · 暂无需要清理的内容";
            if (!cancelled && [result[@"partial"] boolValue]) message = [NSString stringWithFormat:@"已清理 %@ · 部分文件暂未删除", DY778CacheFormatBytes([result[@"deletedBytes"] unsignedLongLongValue])];
            DY778ShowToast(@"cache.manual", message, NO, !cancelled);
        });
    });
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; NSDictionary *row = [self rowAt:path];
    NSString *kind = row[@"kind"], *key = row[@"key"];
    if ([kind isEqual:@"link"]) {
        NSURL *url = [NSURL URLWithString:key];
        if (![@[@"https://github.com/jijiang2333/DY778", @"https://t.me/JiJiang_778"] containsObject:key]) return;
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL opened) {
            if (!opened) dispatch_async(dispatch_get_main_queue(), ^{ DY778Toast(@"暂时无法打开链接，请稍后重试"); });
        }]; return;
    }
    if ([kind isEqualToString:@"nav"]) { DY778PresentController(self, [[DY778SettingsViewController alloc] initWithPage:key]); return; }
    if ([kind isEqualToString:@"number"]) { [self editNumber:row]; return; }
    if ([kind isEqualToString:@"choice"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row[@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        sheet.overrideUserInterfaceStyle = DY778InterfaceStyle(); sheet.view.tintColor = DY778Accent();
        NSArray *values = row[@"values"], *labels = row[@"labels"];
        for (NSUInteger i = 0; i < values.count; i++) {
            NSString *title = [[DY778Preferences() objectForKey:key] isEqual:values[i]] ? [labels[i] stringByAppendingString:@"  ✓"] : labels[i];
            [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { DY778Set(key, values[i]); }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:path];
        sheet.popoverPresentationController.sourceRect = [tableView cellForRowAtIndexPath:path].bounds;
        [self presentViewController:sheet animated:YES completion:nil]; return;
    }
    if ([kind isEqualToString:@"color"]) {
        self.colorKey = key; UIColorPickerViewController *picker = [UIColorPickerViewController new];
        picker.supportsAlpha = NO; picker.selectedColor = DY778ColorFromHex(DY778String(key), DY778Accent()); picker.delegate = self;
        picker.title = row[@"title"]; picker.overrideUserInterfaceStyle = DY778InterfaceStyle();
        [self presentViewController:picker animated:YES completion:nil]; return;
    }
    if ([key isEqualToString:@"editArchive"]) { DY778PresentEditHistory(self, nil, nil); return; }
    if ([key isEqualToString:@"clearEdits"]) { DY778Confirm(self, @"清空当前账号的编辑历史？", @"将删除原文和全部已留存编辑版本，无法恢复。", @"清空历史", YES, ^{ DY778ClearEditHistory(); }); return; }
    if ([key isEqualToString:@"archive"]) { DY778PresentRecallArchive(self, nil); return; }
    if ([@[@"recall.badgeText", @"edit.badgeText"] containsObject:key]) { [self editMarker:key]; return; }
    if ([key isEqualToString:@"customPlaybackRate"]) { [self editPlaybackRate:@"playback.longPressRate"]; return; }
    if ([key isEqualToString:@"customDefaultPlaybackRate"]) { [self editPlaybackRate:@"playback.defaultRate"]; return; }
    if ([key isEqualToString:@"customCacheHours"]) { [self editNumber:DY778Row(@"自定义小时数", @"", @"number", @"cache.maxAgeHours", @"clock")]; return; }
    if ([key isEqualToString:@"cleanHostCache"]) { [self cleanHostCache]; return; }
    if ([key isEqualToString:@"luckyHistory"]) { DY778PresentLuckyHistory(self); return; }
    if ([key isEqualToString:@"notificationStatus"]) { DY778ShowRecallNotificationStatus(self); return; }
    if ([key isEqualToString:@"storageStats"]) {
        __weak typeof(self) weakSelf = self;
        DY778RecallStorageStatistics(^(NSDictionary *statistics) {
            if (!weakSelf.view.window) return;
            if (![statistics[@"account"] isEqual:DY778CurrentAccountID()]) return;
            DY778ShowNotice(weakSelf, @"当前账号的撤回记录", [NSString stringWithFormat:@"已撤回记录：%@ 条\n涉及会话：%@ 个", statistics[@"records"], statistics[@"conversations"]]);
        }); return;
    }
    if ([key isEqualToString:@"clearArchive"]) {
        DY778Confirm(self, @"清空当前账号的消息记录？", @"已保存的撤回记录将被删除。其他账号的记录不会受到影响。此操作无法恢复。", @"清空记录", YES, ^{
            DY778ClearRecallArchive(); [self refresh];
        }); return;
    }
    if ([key isEqualToString:@"customFormat"]) { [self editFormat]; return; }
    if ([key isEqualToString:@"help"]) { DY778PresentHelp(self); return; }
    if ([key isEqualToString:@"reset"]) DY778Confirm(self, @"恢复默认设置？", @"所有功能都会关闭，样式恢复默认。已保存的撤回记录和编辑历史继续保留。", @"恢复默认", YES, ^{
        DY778ResetSettings(); DY778Toast(@"已恢复默认设置，所有功能均已关闭");
    });
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    CGFloat r, g, b, a;
    if (![viewController.selectedColor getRed:&r green:&g blue:&b alpha:&a]) return;
    NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X", (int)round(r*255), (int)round(g*255), (int)round(b*255)];
    DY778Set(self.colorKey, hex);
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController { [self refresh]; }
- (void)editFormat {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"自定义时间格式" message:@"" preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778InterfaceStyle(); alert.view.tintColor = DY778Accent(); self.formatAlert = alert;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = DY778String(@"time.format"); field.placeholder = @"HH:mm:ss"; field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.accessibilityLabel = @"时间格式";
        [field addTarget:self action:@selector(formatChanged:) forControlEvents:UIControlEventEditingChanged];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *format = weakSelf.formatAlert.textFields.firstObject.text;
        if (format.length && format.length <= 64) DY778Set(@"time.format", format);
    }]];
    [self formatChanged:alert.textFields.firstObject];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)formatChanged:(UITextField *)field {
    NSString *format = field.text ?: @""; BOOL valid = format.length > 0 && format.length <= 64;
    NSString *sample = @"请输入 1–64 个字符";
    if (valid) {
        @try {
            NSDateFormatter *formatter = [NSDateFormatter new]; formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
            formatter.dateFormat = format; sample = [formatter stringFromDate:NSDate.date] ?: @""; valid = sample.length > 0 && sample.length < 160;
        } @catch (__unused NSException *exception) { valid = NO; sample = @"暂不支持这个格式"; }
    }
    self.formatAlert.message = [NSString stringWithFormat:@"预览：%@\nHH = 小时 · mm = 分钟 · ss = 秒\nMM = 月份 · dd = 日期", sample];
    self.formatAlert.actions.lastObject.enabled = valid;
}
@end
UIViewController *DY778SettingsController(void) { return [[DY778SettingsViewController alloc] initWithPage:@"home"]; }

static UIImage *DY778EntryIcon(void) {
    static UIImage *icon; static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 24)];
        icon = [[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
            [UIColor.blackColor setStroke];
            UIBezierPath *outline = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, 2, 20, 20) cornerRadius:5]; outline.lineWidth = 1.6; [outline stroke];
            for (NSUInteger i = 0; i < 3; i++) {
                CGFloat y = 7 + i * 5, x = i == 1 ? 15 : 9;
                UIBezierPath *line = [UIBezierPath bezierPath]; line.lineWidth = 1.5; line.lineCapStyle = kCGLineCapRound;
                [line moveToPoint:CGPointMake(6, y)]; [line addLineToPoint:CGPointMake(x - 2, y)];
                [line moveToPoint:CGPointMake(x + 2, y)]; [line addLineToPoint:CGPointMake(18, y)]; [line stroke];
                UIBezierPath *knob = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(x - 2, y - 2, 4, 4)]; knob.lineWidth = 1.5; [knob stroke];
            }
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }); return icon;
}
static void (*DY778OriginalSettingIconUpdate)(id, SEL);
static void DY778SettingIconUpdate(id cell, SEL selector) {
    DY778OriginalSettingIconUpdate(cell, selector);
    if (![DY778Read(DY778Read(cell, @"itemModel"), @"identifier") isEqual:@"DY778.Settings"]) return;
    UIImageView *view = DY778Read(cell, @"iconImageView");
    if ([view isKindOfClass:UIImageView.class]) {
        view.image = DY778EntryIcon(); view.hidden = NO; view.alpha = 1; view.contentMode = UIViewContentModeScaleAspectFit;
        UILabel *title = DY778Read(cell, @"titleLabel");
        UITraitCollection *traits = [cell traitCollection];
        UIColor *textColor = [title isKindOfClass:UILabel.class] ? [title.textColor resolvedColorWithTraitCollection:traits] : [UIColor.labelColor resolvedColorWithTraitCollection:traits];
        CGFloat r=0,g=0,b=0,a=1; [textColor getRed:&r green:&g blue:&b alpha:&a];
        view.tintColor = r * .2126 + g * .7152 + b * .0722 > .5 ? UIColor.whiteColor : UIColor.blackColor;
    }
}
static IMP DY778OriginalSections;
static id DY778SettingsSections(id owner, SEL selector) {
    id value = ((id (*)(id, SEL))DY778OriginalSections)(owner, selector);
    if (![value isKindOfClass:NSArray.class]) return value;
    Class settings = NSClassFromString(@"AWESettingsTableViewController");
    id controller = DY778Read(owner, @"controllerDelegate");
    if (!settings || ![controller isKindOfClass:settings] || [DY778Read(controller, @"onSearchStatus") boolValue]) return value;
    for (id section in value) {
        id items = DY778Read(section, @"itemArray"); if (![items isKindOfClass:NSArray.class]) continue;
        for (id item in items) if ([DY778Read(item, @"identifier") isEqual:@"DY778.Settings"]) return value;
    }
    Class itemClass = NSClassFromString(@"AWESettingItemModel"), sectionClass = NSClassFromString(@"AWESettingSectionModel");
    if (!itemClass || !sectionClass) return value;
    id item = [itemClass new]; __weak UIViewController *source = controller;
    BOOL valid = DY778Write(item, @"identifier", @"DY778.Settings");
    valid &= DY778Write(item, @"title", @"DY778"); valid &= DY778Write(item, @"detail", DY778Version);
    valid &= DY778Write(item, @"cellType", @26); valid &= DY778Write(item, @"isEnable", @YES);
    valid &= DY778Write(item, @"cellTappedBlock", ^{
        UIViewController *top = DY778TopController();
        if ([top isKindOfClass:DY778SettingsViewController.class]) return;
        DY778PresentController(source, DY778SettingsController());
    });
    DY778Write(item, @"type", @0); DY778Write(item, @"colorStyle", @2);
    UIImage *entryIcon = DY778EntryIcon();
    if (entryIcon) { DY778Write(item, @"specificIconImage", entryIcon); DY778Write(item, @"svgIconImageName", nil); }
    id section = [sectionClass new]; valid &= DY778Write(section, @"itemArray", @[item]);
    DY778Write(section, @"sectionHeaderHeight", @16); DY778Write(section, @"type", @0);
    if (!valid) return value;
    NSMutableArray *result = [value mutableCopy]; [result insertObject:section atIndex:0]; return result;
}
void DY778InstallSettingsHook(void) {
    if (!DY778OriginalSettingIconUpdate) {
        Class cell = NSClassFromString(@"AWESettingsTableViewCell"); SEL update = NSSelectorFromString(@"updateSubviews");
        Method method = class_getInstanceMethod(cell, update); char result[8] = {0}; if (method) method_getReturnType(method, result, sizeof(result));
        DY778RecordHook(@"设置页 · 黑白入口图标", method && method_getNumberOfArguments(method) == 2 && result[0] == 'v' && DY778Hook(cell, update, (IMP)DY778SettingIconUpdate, (IMP *)&DY778OriginalSettingIconUpdate));
    }
    static BOOL installed; if (installed) return;
    Class cls = NSClassFromString(@"AWESettingsViewModel"); SEL selector = NSSelectorFromString(@"sectionDataArray");
    Method method = class_getInstanceMethod(cls, selector);
    if (method) {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.numberOfArguments == 2 && signature.methodReturnType[0] == '@')
            installed = DY778Hook(cls, selector, (IMP)DY778SettingsSections, &DY778OriginalSections);
    }
    DY778RecordHook(@"设置页 · DY778入口", installed);
}
