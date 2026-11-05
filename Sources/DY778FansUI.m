#import "DY778FansUI.h"
#import "DY778RadarUI.h"

@interface DY778FansQueryController : UITableViewController
@property(nonatomic, copy) NSDictionary *person;
@property(nonatomic, copy) NSDictionary *anchor;
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, strong) DY778FansResult *result;
@property(nonatomic, strong) DY778FansService *service;
@property(nonatomic) BOOL busy;
@property(nonatomic) NSUInteger generation;
@end
@implementation DY778FansQueryController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"星牌查询"; self.account = DY778CurrentAccountID();
    self.service = [DY778FansService new]; self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 78;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension; self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    DY778StyleController(self); self.tableView.backgroundColor = DY778Background(); self.tableView.separatorInset = UIEdgeInsetsMake(0,20,0,20);
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 6;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(query)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(preferencesChanged) name:DY778PreferencesChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(preferencesChanged) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pause) name:UIApplicationWillResignActiveNotification object:nil];
    [self query];
}
- (void)dealloc { [self.service cancel]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (BOOL)current { return DY778Bool(@"fans.enabled") && [self.account isEqual:DY778CurrentAccountID()]; }
- (void)pause {
    if (!self.busy) return;
    self.generation++; [self.service cancel]; self.busy=NO; self.status=@"查询已暂停，返回后可点击刷新";
    DY778DismissToast(@"fans"); [self.tableView reloadData];
}
- (void)preferencesChanged {
    DY778StyleController(self);
    if (![self current]) { self.generation++; [self.service cancel]; self.busy = NO; self.result=nil; self.status = @"账号或设置已变化，请返回主页重新查询"; DY778DismissToast(@"fans"); [self.tableView reloadData]; }
}
- (void)query {
    if (self.busy || ![self current]) return;
    self.busy = YES; self.status = @"正在读取可查询的资料…"; self.result = nil;
    NSUInteger generation = ++self.generation; __weak typeof(self) weakSelf = self;
    self.service.progress = ^(NSString *text) { if (weakSelf.generation == generation && [weakSelf current]) { weakSelf.status = text; [weakSelf.tableView reloadData]; } };
    self.service.partialResult = ^(DY778FansResult *result) { if (weakSelf.generation == generation && [weakSelf current]) { weakSelf.result = result; [weakSelf.tableView reloadData]; } };
    DY778ShowToast(@"fans", @"正在查询星牌", YES, NO); [self.tableView reloadData];
    [self.service queryInput:@"" mode:DY778FansInputAutomatic target:self.person anchor:self.anchor completion:^(DY778FansResult *result, NSError *error) {
        DY778FansQueryController *self = weakSelf;
        if (!self || self.generation != generation || ![self current]) return;
        self.busy = NO; if (result) { self.result = result; self.person = result.person; if (result.anchor) self.anchor = result.anchor; }
        self.status = error.localizedDescription ?: (self.anchor ? (result.clubs.count ? @"本次查询已完成" : @"暂未取得可确认的灯牌") : @"资料已更新，选择主播可核对对应灯牌");
        DY778ShowToast(@"fans", self.status, NO, error == nil); [self.tableView reloadData];
    }];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 3 : section == 2 ? MAX((NSUInteger)1,self.result.clubs.count) : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"当前用户", @"查询主播", @"粉丝灯牌", @"本次结果"][(NSUInteger)section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"等级区间仅用于说明等级范围，不代表实际消费金额。";
    if (section == 2) return self.result.notice ?: @"只展示当前可查询且归属匹配的资料。暂未返回不代表没有加入。";
    if (section == 3) return @"结果不保存为本地历史；切换账号或关闭功能会停止当前查询。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) {
        NSDictionary *person = self.result.person ?: self.person;
        if (path.row == 0) return DY778RadarCell(DY778FansPersonName(person), [NSString stringWithFormat:@"抖音号：%@", [person[@"handle"] length] ? person[@"handle"] : @"暂未提供"], @"person.crop.circle", NO);
        if (path.row == 1) {
            NSString *range = self.result.minimum ? [NSString stringWithFormat:@"等级对应钻石区间：%@–%@",self.result.minimum,self.result.maximum ?: @"以上"] : @"暂未返回等级区间";
            return DY778RadarCell(self.result.level ? [NSString stringWithFormat:@"消费等级 Lv.%@",self.result.level] : @"消费等级暂未返回",range,@"diamond",NO);
        }
        return DY778RadarCell(@"个人简介", [person[@"signature"] length] ? person[@"signature"] : @"暂无可展示的简介", @"text.alignleft", NO);
    }
    if (path.section == 1) return DY778RadarCell(self.anchor ? DY778FansPersonName(self.anchor) : @"选择主播", self.anchor ? @"点按切换要核对的主播" : @"选择后查询该用户与主播对应的灯牌", @"person.crop.circle.badge.checkmark", YES);
    if (path.section == 2) {
        if (!self.result.clubs.count) return DY778RadarCell(self.busy ? @"正在查询" : @"暂待确认", self.status ?: @"等待查询", @"star.circle", NO);
        NSDictionary *club = self.result.clubs[(NSUInteger)path.row];
        NSString *title = [club[@"clubName"] length] ? club[@"clubName"] : @"粉丝灯牌";
        NSString *state = [club[@"status"] integerValue] == 1 ? @"已点亮" : [club[@"status"] integerValue] == 2 ? @"未点亮" : @"点亮状态暂未提供";
        NSString *level = club[@"level"] ? [NSString stringWithFormat:@"Lv.%@ · %@",club[@"level"],state] : @"等级暂未提供";
        NSString *name = [club[@"anchorName"] length] ? club[@"anchorName"] : self.anchor ? DY778FansPersonName(self.anchor) : @"主播资料暂未返回";
        return DY778RadarCell(title,[NSString stringWithFormat:@"%@\n%@",level,name],@"star.fill",NO);
    }
    return DY778RadarCell(@"复制查询结果",self.busy ? @"查询完成后可复制" : self.status ?: @"等待查询",@"doc.on.doc",NO);
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if (self.busy || ![self current]) return;
    if (path.section == 1) [self selectAnchor];
    else if (path.section == 3 && self.result) { UIPasteboard.generalPasteboard.string = self.result.shareText; DY778Toast(@"查询结果已复制"); }
    else if (path.section == 0 && path.row == 2 && [self.result.person[@"signature"] length]) { UIPasteboard.generalPasteboard.string = self.result.person[@"signature"]; DY778Toast(@"个人简介已复制"); }
}
- (NSString *)anchorKey { return [@"fans.anchors." stringByAppendingString:self.account ?: @""]; }
- (void)useAnchor:(NSDictionary *)person {
    if (![self current] || !person) return;
    self.anchor = person;
    id stored = [DY778Preferences() objectForKey:self.anchorKey]; NSMutableArray *recent = [NSMutableArray array];
    [recent addObject:person];
    if ([stored isKindOfClass:NSArray.class]) for (NSDictionary *old in stored) if ([old isKindOfClass:NSDictionary.class] && !DY778FansSamePerson(person,old) && recent.count < 8) [recent addObject:old];
    [DY778Preferences() setObject:recent forKey:self.anchorKey]; [self query];
}
- (void)selectAnchor {
    id value = [DY778Preferences() objectForKey:self.anchorKey]; NSArray *recent = [value isKindOfClass:NSArray.class] ? value : @[];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择主播" message:@"核对这位用户在所选主播下的粉丝灯牌。" preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = DY778InterfaceStyle(); sheet.view.tintColor = DY778Accent();
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *person in recent) if ([person isKindOfClass:NSDictionary.class] && DY778FansUID(person[@"uid"]))
        [sheet addAction:[UIAlertAction actionWithTitle:DY778FansPersonName(person) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf useAnchor:person]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"通过抖音号选择主播" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf enterAnchor]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)enterAnchor {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择主播" message:@"输入主播的完整抖音号，查询后核对身份。" preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778InterfaceStyle(); alert.view.tintColor = DY778Accent();
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"主播抖音号"; field.autocorrectionType = UITextAutocorrectionTypeNo; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self; __weak UIAlertController *weakAlert=alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"查询主播" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        DY778FansQueryController *self = weakSelf; if (![self current]) return;
        self.busy = YES; NSUInteger generation = ++self.generation; DY778ShowToast(@"fans",@"正在查找主播",YES,NO);
        [self.service resolveInput:weakAlert.textFields.firstObject.text mode:DY778FansInputHandle completion:^(id person,NSError *error) {
            if (![weakSelf current] || weakSelf.generation != generation) return;
            weakSelf.busy = NO; DY778DismissToast(@"fans");
            NSArray *candidates = error.userInfo[@"DY778FansCandidates"];
            if ([candidates isKindOfClass:NSArray.class] && candidates.count) { [weakSelf chooseCandidate:candidates]; return; }
            if (!person || error) { DY778Toast(error.localizedDescription ?: @"暂未找到该主播"); return; }
            [weakSelf chooseCandidate:@[person]];
        }];
    }]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)chooseCandidate:(NSArray *)people {
    if (![self current]) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"核对主播身份" message:@"请选择正确的主播。" preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.overrideUserInterfaceStyle = DY778InterfaceStyle(); sheet.view.tintColor = DY778Accent(); __weak typeof(self) weakSelf = self;
    for (NSDictionary *person in people) [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ · %@",DY778FansPersonName(person),person[@"handle"] ?: @""] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf useAnchor:person]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) { self.generation++; [self.service cancel]; DY778DismissToast(@"fans"); }
}
@end
void DY778FansOpenQuery(NSDictionary *person) {
    if (!DY778Bool(@"fans.enabled") || !person) return;
    DY778FansQueryController *controller = [DY778FansQueryController new]; controller.person = person;
    DY778PresentController(DY778TopController(),controller);
}
