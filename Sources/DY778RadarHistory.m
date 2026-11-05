#import "DY778Core.h"
#import "DY778RadarUI.h"
static NSDictionary *DY778RadarRecordPerson(NSDictionary *record) {
    return [DY778RadarStore.shared target:record[@"person"][@"uid"]] ?: record[@"person"];
}
static NSString *DY778RadarChangeText(NSArray *changes) {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *change in changes) {
        long long delta = [change[@"delta"] longLongValue];
        [lines addObject:[NSString stringWithFormat:@"%@  %@ → %@（%@%lld）", DY778RadarMetricName(change[@"key"]), change[@"before"], change[@"after"], delta > 0 ? @"+" : @"", delta]];
    }
    return [lines componentsJoinedByString:@"\n"];
}
@interface DY778RadarHistoryController () <UISearchResultsUpdating>
@property(nonatomic, copy) NSString *account;
@property(nonatomic, strong) UISegmentedControl *filter;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@end
@implementation DY778RadarHistoryController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"动态档案"; self.account = DY778RadarStore.shared.accountID;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
    self.filter = [[UISegmentedControl alloc] initWithItems:@[@"全部", @"喜欢作品", @"数值变化", @"简介变化"]]; self.filter.selectedSegmentIndex = 0;
    self.filter.selectedSegmentTintColor = DY778RadarButtonColor();
    [self.filter setTitleTextAttributes:@{NSForegroundColorAttributeName: DY778AccentForeground()} forState:UIControlStateSelected];
    [self.filter addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 360, 64)];
    self.filter.translatesAutoresizingMaskIntoConstraints = NO; [header addSubview:self.filter];
    [NSLayoutConstraint activateConstraints:@[[self.filter.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20], [self.filter.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20], [self.filter.topAnchor constraintEqualToAnchor:header.topAnchor constant:12], [self.filter.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12], [self.filter.heightAnchor constraintGreaterThanOrEqualToConstant:36]]];
    self.tableView.tableHeaderView = header;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil]; self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO; self.search.searchBar.placeholder = @"搜索对象、作品或简介内容";
    self.navigationItem.searchController = self.search; self.definesPresentationContext = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:DY778RadarStoreChanged object:nil];
}
- (void)refresh {
    if (!self.isViewLoaded) return;
    NSString *query = self.search.searchBar.text ?: @"";
    NSMutableArray *items = [NSMutableArray array];
    if ([self.account isEqual:DY778RadarStore.shared.accountID]) for (NSDictionary *record in DY778RadarStore.shared.records) {
        if (self.personID.length && ![record[@"person"][@"uid"] isEqual:self.personID]) continue;
        if (self.filter.selectedSegmentIndex == 1 && ![record[@"kind"] isEqual:@"like"]) continue;
        if (self.filter.selectedSegmentIndex == 2 && ![record[@"kind"] isEqual:@"counts"]) continue;
        if (self.filter.selectedSegmentIndex == 3 && ![record[@"kind"] isEqual:@"signature"]) continue;
        NSString *searchable = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", DY778RadarPersonSearchText(DY778RadarRecordPerson(record)), DY778RadarPersonSearchText(record[@"person"]), record[@"video"][@"author"] ?: @"", record[@"video"][@"text"] ?: @"", record[@"before"] ?: @"", record[@"after"] ?: @""];
        if (query.length && ![searchable localizedCaseInsensitiveContainsString:query]) continue;
        [items addObject:record];
    }
    self.items = items; [super refresh];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self refresh]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX(1, self.items.count); }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"记录时间为发现时间。左滑可单独删除，点击查看完整内容并复制。简介支持搜索修改前后原文。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (!self.items.count) return DY778RadarCell(@"这里还没有动态", @"检测到变化后会显示在这里；首次检测仅建立基线。", @"tray", NO);
    NSDictionary *r = self.items[(NSUInteger)path.row]; BOOL like = [r[@"kind"] isEqual:@"like"];
    BOOL signature = [r[@"kind"] isEqual:@"signature"];
    NSString *title = [NSString stringWithFormat:@"%@ · %@", DY778RadarDisplayName(DY778RadarRecordPerson(r)), like ? @"喜欢列表新发现" : signature ? @"简介变化" : @"数值变化"];
    NSString *body = like ? [NSString stringWithFormat:@"%@\n%@", DY778RadarString(r[@"video"][@"author"]).length ? [@"@" stringByAppendingString:r[@"video"][@"author"]] : @"作者未提供", DY778RadarString(r[@"video"][@"text"]).length ? r[@"video"][@"text"] : @"无作品文案"] : DY778RadarChangeText(r[@"changes"]);
    if (signature) body = [NSString stringWithFormat:@"修改前：%@\n修改后：%@", DY778RadarSignatureText(r[@"before"]), DY778RadarSignatureText(r[@"after"])];
    if (body.length > 150) body = [[body substringWithRange:[body rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 150)]] stringByAppendingString:@"…"];
    NSMutableDictionary *identity = [DY778RadarRecordPerson(r) mutableCopy];
    identity[@"name"] = title; [identity removeObjectsForKeys:@[@"remark", @"note"]];
    return DY778RadarPersonCell(identity, [NSString stringWithFormat:@"%@\n%@", DY778RadarDateText([r[@"timestamp"] doubleValue]), body], YES);
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if (!self.items.count || ![self checkAccount:self.account]) return;
    DY778RadarRecordController *detail = [DY778RadarRecordController new]; detail.record = self.items[(NSUInteger)path.row];
    [self.navigationController pushViewController:detail animated:YES];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (!self.items.count) return nil;
    NSString *recordID = self.items[(NSUInteger)path.row][@"id"];
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        if (![self checkAccount:self.account]) { completion(NO); return; }
        [DY778RadarStore.shared deleteRecord:recordID]; completion(YES);
    }];
    remove.image = [UIImage systemImageNamed:@"trash"]; return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}
- (void)clear {
    if (![self checkAccount:self.account]) return;
    DY778RadarConfirm(self, @"清空全部动态档案？", @"当前账号的所有记录都会被删除，包括筛选结果之外的记录。监控基线保留。", @"全部清空", ^{ if ([self checkAccount:self.account]) [DY778RadarStore.shared clearRecords]; });
}
@end

@interface DY778RadarRecordController ()
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSArray<NSDictionary *> *fields;
@end
@implementation DY778RadarRecordController
- (void)viewDidLoad {
    [super viewDidLoad]; self.account = DY778RadarStore.shared.accountID;
    BOOL signature = [self.record[@"kind"] isEqual:@"signature"];
    self.title = [self.record[@"kind"] isEqual:@"like"] ? @"作品详情" : signature ? @"简介变化详情" : @"变化详情";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"删除" style:UIBarButtonItemStylePlain target:self action:@selector(deleteRecord)];
    NSMutableArray *fields = [NSMutableArray array];
    NSDictionary *person = DY778RadarRecordPerson(self.record), *video = self.record[@"video"];
    [fields addObject:@{@"title": @"关注对象", @"value": DY778RadarDisplayName(person)}];
    [fields addObject:@{@"title": @"对象抖音号", @"value": DY778RadarString(person[@"handle"])}];
    [fields addObject:@{@"title": @"发现时间", @"value": DY778RadarDateText([self.record[@"timestamp"] doubleValue])}];
    if (video) {
        for (NSArray *pair in @[@[@"作者", @"author"], @[@"作者抖音号", @"authorHandle"], @[@"作品文案", @"text"], @[@"作品链接", @"url"], @[@"作品 ID", @"id"]])
            [fields addObject:@{@"title": pair[0], @"value": DY778RadarString(video[pair[1]])}];
        if ([video[@"publishedAt"] doubleValue] > 0) [fields addObject:@{@"title": @"作品发布时间", @"value": DY778RadarDateText([video[@"publishedAt"] doubleValue])}];
    } else if (signature) {
        [fields addObject:@{@"title": @"修改前的简介", @"value": self.record[@"before"], @"signature": @YES}];
        [fields addObject:@{@"title": @"修改后的简介", @"value": self.record[@"after"], @"signature": @YES}];
    } else [fields addObject:@{@"title": @"数值变化", @"value": DY778RadarChangeText(self.record[@"changes"])}];
    self.fields = fields;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.fields.count : self.record[@"video"] ? 2 : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 1) return @"点击任意字段复制其内容。";
    if ([self.record[@"kind"] isEqual:@"signature"]) return @"发现时间不等于实际修改时间。空简介表示对方清空了内容，点击会清空剪贴板；复制全部用（空简介）标明。接口未返回简介不会记为清空。";
    if (!self.record[@"video"]) return @"关注、粉丝或获赞变化可能来自多种原因，以抖音实际展示为准。";
    return [self.record[@"uncertain"] boolValue] ? @"两次检测间列表跨度较大，此条记录表示新发现的作品，无法确认实际点赞时间。作品若已删除或变为私密，链接可能无法打开。" : @"发现时间不等于点赞时间。作品删除、取消喜欢或权限变化后，历史资料仍会保留到清理时。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) {
        NSDictionary *field = self.fields[(NSUInteger)path.row];
        if ([field[@"title"] isEqual:@"关注对象"]) return DY778RadarPersonCell(DY778RadarRecordPerson(self.record), @"关注对象 · 点击复制名称", NO);
        if ([field[@"title"] isEqual:@"作者"]) return DY778RadarPersonCell(@{@"name": DY778RadarString(field[@"value"]), @"avatar": DY778RadarString(self.record[@"video"][@"authorAvatar"])}, @"作品作者 · 点击复制名称", NO);
        if ([field[@"signature"] boolValue]) return DY778RadarCell(field[@"title"], DY778RadarSignatureText(field[@"value"]), @"doc.on.doc", NO);
        return DY778RadarCell(field[@"title"], DY778RadarString(field[@"value"]).length ? field[@"value"] : @"未提供", @"doc.on.doc", NO);
    }
    if (self.record[@"video"] && path.row == 0) return DY778RadarCell(@"在抖音打开作品", @"视频 / 图文按原作品展示", @"play.circle.fill", YES);
    return DY778RadarCell(@"复制全部资料", nil, @"square.on.square", NO);
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if (![self checkAccount:self.account]) return;
    if (path.section == 0) {
        NSDictionary *field = self.fields[(NSUInteger)path.row];
        if ([field[@"signature"] boolValue]) DY778RadarCopySignature(self, field[@"value"]);
        else DY778RadarCopy(self, field[@"value"]);
        return;
    }
    if (self.record[@"video"] && path.row == 0) { DY778RadarOpenVideo(self, self.record[@"video"][@"id"]); return; }
    NSMutableArray *lines = [NSMutableArray array]; for (NSDictionary *field in self.fields) [lines addObject:[NSString stringWithFormat:@"%@：%@", field[@"title"], [field[@"signature"] boolValue] ? DY778RadarSignatureText(field[@"value"]) : field[@"value"]]];
    DY778RadarCopy(self, [lines componentsJoinedByString:@"\n"]);
}
- (void)deleteRecord {
    if (![self checkAccount:self.account]) return;
    DY778RadarConfirm(self, @"删除这条记录？", @"不会影响对此人的后续检测。", @"删除", ^{
        if (![self checkAccount:self.account]) return;
        [DY778RadarStore.shared deleteRecord:self.record[@"id"]]; [self.navigationController popViewControllerAnimated:YES];
    });
}
@end
