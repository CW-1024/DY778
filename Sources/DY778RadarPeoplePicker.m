#import "DY778Core.h"
#import "DY778RadarUI.h"
#import "DY778RadarApi.h"
@interface DY778RadarPeoplePicker () <UISearchResultsUpdating, UISearchControllerDelegate>
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *requestOwner;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *friends;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *selected;
@property(nonatomic, strong) UISegmentedControl *mode;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic) BOOL closing;
@property(nonatomic) BOOL loading;
@property(nonatomic) BOOL resolving;
@property(nonatomic) BOOL loaded;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, copy) NSString *loadError;
@property(nonatomic, strong) NSError *lastLoadError;
@property(nonatomic, strong) NSDictionary *resolved;
@property(nonatomic, strong) UIBarButtonItem *doneButton;
@end
@implementation DY778RadarPeoplePicker
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"选择关注对象"; self.account = DY778RadarStore.shared.accountID;
    self.requestOwner = [@"DY778Radar.Picker." stringByAppendingString:NSUUID.UUID.UUIDString];
    self.friends = [NSMutableArray array]; self.selected = [NSMutableDictionary dictionary];
    self.doneButton = [[UIBarButtonItem alloc] initWithTitle:@"确定" style:UIBarButtonItemStyleDone target:self action:@selector(confirm)];
    self.navigationItem.rightBarButtonItem = self.doneButton;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.hidesNavigationBarDuringPresentation = NO; self.search.delegate = self;
    self.search.obscuresBackgroundDuringPresentation = NO; self.search.searchResultsUpdater = self;
    self.search.searchBar.placeholder = @"搜索备注 / 昵称 / 抖音号";
    self.navigationItem.searchController = self.search; self.definesPresentationContext = YES;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.mode = [[UISegmentedControl alloc] initWithItems:@[@"多选", @"单选"]]; self.mode.selectedSegmentIndex = 0;
    [self.mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    self.mode.selectedSegmentTintColor = DY778RadarButtonColor();
    [self.mode setTitleTextAttributes:@{NSForegroundColorAttributeName: DY778AccentForeground()} forState:UIControlStateSelected];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 360, 130)];
    UILabel *hint = DY778RadarLabel(@"点选即可确认添加；也可继续多选后批量添加。支持搜索备注、昵称和抖音号。", 14, UIFontWeightRegular);
    hint.textColor = UIColor.secondaryLabelColor;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.mode, hint]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = NO; [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20], [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20], [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:12], [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12], [self.mode.heightAnchor constraintGreaterThanOrEqualToConstant:36]]];
    self.tableView.tableHeaderView = header;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; self.spinner.color = DY778RadarAccent();
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted) name:UIApplicationWillResignActiveNotification object:nil];
    [self loadFriends]; [self selectionChanged];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) [self interrupted];
}
- (void)interrupted {
    self.generation++; self.loading = NO; self.resolving = NO; [self.spinner stopAnimating];
    [DY778RadarNetwork.shared cancelOwner:self.requestOwner];
    if (!self.loaded) self.loadError = @"加载已暂停，点击继续";
    [self.tableView reloadData];
}
- (void)refresh { if (self.isViewLoaded) [self selectionChanged]; }
- (void)selectionChanged {
    self.doneButton.title = [NSString stringWithFormat:@"确定 (%lu)", (unsigned long)self.selected.count];
    self.doneButton.enabled = self.selected.count > 0; [self.tableView reloadData];
}
- (NSArray *)visibleFriends {
    NSString *query = [self.search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) return self.friends;
    return [self.friends filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *user, NSDictionary *bindings) {
        return [DY778RadarPersonSearchText(user) localizedCaseInsensitiveContainsString:query];
    }]];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self.tableView reloadData]; }
- (void)modeChanged {
    if (self.mode.selectedSegmentIndex == 1 && self.selected.count > 1) {
        NSString *first = [self.selected.allKeys sortedArrayUsingSelector:@selector(compare:)].firstObject;
        NSDictionary *keep = self.selected[first]; [self.selected removeAllObjects]; self.selected[first] = keep;
    }
    [self selectionChanged];
}
- (void)loadFriends {
    if (self.loading || ![self checkAccount:self.account]) return;
    self.loading = YES; self.loadError = nil; self.lastLoadError = nil;
    [self.spinner startAnimating]; [self.tableView reloadData];
    NSUInteger generation = self.generation; __weak typeof(self) weakSelf = self;
    [DY778RadarApi friendsForOwner:self.requestOwner completion:^(id users, NSError *error) {
        typeof(self) self = weakSelf; if (!self || self.generation != generation) return;
        self.loading = NO; [self.spinner stopAnimating];
        if (![self.account isEqual:DY778RadarStore.shared.accountID]) { self.loadError = @"账号已切换，请返回重试"; [self.tableView reloadData]; return; }
        if (error) { self.loadError = error.localizedDescription; self.lastLoadError = error; [self.tableView reloadData]; return; }
        self.loaded = YES;
        self.friends = [users mutableCopy];
        for (NSUInteger i = 0; i < self.friends.count; i++) {
            NSDictionary *profile = self.friends[i], *saved = [DY778RadarStore.shared target:profile[@"uid"]];
            if (saved[@"note"]) { NSMutableDictionary *copy = [profile mutableCopy]; copy[@"note"] = saved[@"note"]; self.friends[i] = copy; }
            if (saved) {
                NSMutableDictionary *identity = [NSMutableDictionary dictionary];
                for (NSString *key in @[@"remark", @"name", @"handle", @"avatar"]) if (profile[key] && (![key isEqual:@"avatar"] || DY778RadarString(profile[key]).length)) identity[key] = profile[key];
                [DY778RadarStore.shared updateTarget:profile[@"uid"] values:identity];
            }
        }
        [self.tableView reloadData];
    }];
}
- (void)showFailure:(NSError *)error retryFriends:(BOOL)retry {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:retry ? @"好友加载未完成" : @"查找未完成"
        message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778RadarStyle(); alert.view.tintColor = DY778RadarAccent();
    [alert addAction:[UIAlertAction actionWithTitle:@"复制诊断" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        DY778RadarCopy(self, DY778RadarDiagnosticText(error));
    }]];
    if (retry) [alert addAction:[UIAlertAction actionWithTitle:@"重新加载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self loadFriends]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [DY778RadarTopController(self) presentViewController:alert animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return section == 1 && !self.resolved ? 0.01 : UITableViewAutomaticDimension; }
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { return section == 1 && !self.resolved ? 0.01 : UITableViewAutomaticDimension; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : section == 1 ? (self.resolved ? 1 : 0) : self.visibleFriends.count + 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"非互关也可以添加";
    if (section == 1) return self.resolved ? @"抖音号查找结果" : nil;
    return self.search.searchBar.text.length ? [NSString stringWithFormat:@"匹配 %lu 人 · 已加载 %lu 人", (unsigned long)self.visibleFriends.count, (unsigned long)self.friends.count] :
        [NSString stringWithFormat:@"互关好友 · 已加载 %lu 人", (unsigned long)self.friends.count];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 2 ? @"读取抖音本地联系人中的互关关系。列表未更新时，可先打开抖音消息页，再返回点击刷新；已选内容会保留。" : nil;
}
- (UITableViewCell *)profileCell:(NSDictionary *)profile {
    BOOL existing = [DY778RadarStore.shared target:profile[@"uid"]] != nil;
    BOOL chosen = self.selected[profile[@"uid"]] != nil;
    NSString *detail = [NSString stringWithFormat:@"抖音号：%@%@", DY778RadarString(profile[@"handle"]).length ? profile[@"handle"] : @"未提供", existing ? @" · 已添加" : @""];
    if (![DY778RadarDisplayName(profile) isEqual:profile[@"name"]] && DY778RadarString(profile[@"name"]).length)
        detail = [NSString stringWithFormat:@"昵称：%@\n%@", profile[@"name"], detail];
    UITableViewCell *cell = DY778RadarPersonCell(profile, detail, NO);
    cell.accessoryType = chosen || existing ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = DY778RadarAccent(); cell.contentView.alpha = existing ? 0.5 : 1;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (chosen ? UIAccessibilityTraitSelected : 0);
    return cell;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) {
        UITableViewCell *cell = DY778RadarCell(self.resolving ? @"正在查找抖音号…" : @"输入抖音号", @"按完整抖音号查找，确认昵称后勾选", @"magnifyingglass", !self.resolving);
        if (self.resolving) {
            UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            indicator.color = DY778RadarAccent(); [indicator startAnimating]; cell.accessoryView = indicator;
        }
        return cell;
    }
    if (path.section == 1) return [self profileCell:self.resolved];
    NSArray *visible = self.visibleFriends;
    if ((NSUInteger)path.row < visible.count) return [self profileCell:visible[(NSUInteger)path.row]];
    NSString *title = self.loading ? @"正在加载好友…" : self.loadError.length ? @"加载未完成，查看详情" : self.friends.count ? @"刷新互关好友" : @"暂未读取到好友，点此刷新";
    UITableViewCell *cell = DY778RadarCell(title, self.loadError, self.loading ? nil : @"person.2", NO);
    if (self.loading) cell.accessoryView = self.spinner;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if (![self checkAccount:self.account]) return;
    if (path.section == 0) { if (!self.resolving) [self inputHandle]; return; }
    NSArray *visible = self.visibleFriends;
    if (path.section == 2 && (NSUInteger)path.row >= visible.count) { if (self.lastLoadError) [self showFailure:self.lastLoadError retryFriends:YES]; else [self loadFriends]; return; }
    NSDictionary *profile = path.section == 1 ? self.resolved : visible[(NSUInteger)path.row];
    NSString *uid = profile[@"uid"]; if ([DY778RadarStore.shared target:uid]) return;
    NSDictionary *previous = self.selected.copy;
    BOOL adding = self.selected[uid] == nil;
    if (!adding) [self.selected removeObjectForKey:uid];
    else {
        if (self.mode.selectedSegmentIndex == 1) [self.selected removeAllObjects];
        if (self.selected.count + DY778RadarStore.shared.targets.count >= 20) { DY778RadarMessage(DY778RadarTopController(self), @"已到数量上限", @"最多留意 20 人，请先取消部分选择或移除已有对象。"); return; }
        self.selected[uid] = profile;
    }
    [self selectionChanged];
    if (adding) [self confirmSelectionPrompt:previous];
}
- (void)confirmSelectionPrompt:(NSDictionary *)previous {
    [self.view endEditing:YES];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *uid in [self.selected.allKeys sortedArrayUsingSelector:@selector(compare:)]) [names addObject:DY778RadarDisplayName(self.selected[uid])];
    NSString *who = names.count > 4 ? [NSString stringWithFormat:@"%@ 等 %lu 人", [[names subarrayWithRange:NSMakeRange(0, 4)] componentsJoinedByString:@"、"], (unsigned long)names.count] : [names componentsJoinedByString:@"、"];
    NSString *message = [NSString stringWithFormat:@"将留意 %@ 的获赞、关注、粉丝和喜欢变化。仅在你使用抖音时检测，首次读取建立基线。", who];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:names.count > 1 ? @"添加这些关注对象？" : @"特别关注此人？" message:message preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778RadarStyle(); alert.view.tintColor = DY778RadarAccent();
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:names.count > 1 ? @"全部添加" : @"添加关注对象" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakAlert dismissViewControllerAnimated:YES completion:^{ [self confirm]; }];
    }]];
    if (self.mode.selectedSegmentIndex == 0) [alert addAction:[UIAlertAction actionWithTitle:@"继续多选" style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消选择" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { self.selected = [previous mutableCopy]; [self selectionChanged]; }]];
    UIViewController *presenter = DY778RadarTopController(self);
    [presenter presentViewController:alert animated:YES completion:nil];
}
- (void)inputHandle {
    [self.view endEditing:YES];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"通过抖音号添加" message:@"请输入主页中显示的抖音号，不是昵称。" preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778RadarStyle(); alert.view.tintColor = DY778RadarAccent();
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"输入完整抖音号"; field.autocorrectionType = UITextAutocorrectionTypeNo; field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.clearButtonMode = UITextFieldViewModeWhileEditing; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"查找" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *handle = weakAlert.textFields.firstObject.text ?: @"";
        [weakAlert dismissViewControllerAnimated:YES completion:^{ [self resolveInput:handle]; }];
    }]];
    [DY778RadarTopController(self) presentViewController:alert animated:YES completion:nil];
}
- (void)resolveInput:(NSString *)handle {
    if (![self checkAccount:self.account] || self.closing) return;
    self.resolving = YES; self.resolved = nil; [self.tableView reloadData]; NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    [DY778RadarApi resolveHandle:handle owner:self.requestOwner completion:^(id profile, NSError *error) {
        typeof(self) self = weakSelf; if (!self || generation != self.generation) return;
        self.resolving = NO;
        if (error) { [self.tableView reloadData]; if (error.code != NSURLErrorCancelled) [self showFailure:error retryFriends:NO]; return; }
        self.resolved = profile; [self.tableView reloadData];
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }];
}
- (void)confirm {
    if (self.closing || ![self checkAccount:self.account] || !self.selected.count) return;
    NSError *error;
    if (![DY778RadarStore.shared addProfiles:self.selected.allValues error:&error]) { DY778RadarMessage(DY778RadarTopController(self), @"无法添加", error.localizedDescription); return; }
    self.closing = YES; [self interrupted];
    // 返回前先收起搜索，避免在上一页残留浮层。
    if (self.search.active) self.search.active = NO;
    else if (!self.search.isBeingDismissed) [self finishClosing];
}
- (void)didDismissSearchController:(UISearchController *)searchController { if (self.closing) [self finishClosing]; }
- (void)finishClosing {
    if (self.navigationController.topViewController == self) [self.navigationController popViewControllerAnimated:YES];
}

@end
