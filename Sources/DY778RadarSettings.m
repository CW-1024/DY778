#import "DY778RadarUI.h"
#import "DY778RadarNetwork.h"
#import "DY778RadarPolicy.h"
@interface DY778RadarSettingsController ()
@property(nonatomic, copy) NSArray *people;
@end
@implementation DY778RadarSettingsController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = DY778RadarName;
    if (self.navigationController.viewControllers.firstObject == self)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:DY778RadarStoreChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateStatus) name:DY778RadarMonitorStatusChanged object:nil];
}
- (void)close { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
- (void)refresh { self.people = DY778RadarStore.shared.targets; [super refresh]; [self updateStatus]; }
- (void)updateStatus {
    if (self.isViewLoaded && self.view.window) [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 3 : section == 1 ? 1 : section == 2 ? MAX(1, self.people.count) : section == 3 ? 5 : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"检测与提醒", @"添加关注对象", [NSString stringWithFormat:@"关注对象 · %lu / 20", (unsigned long)self.people.count], @"动态档案"][(NSUInteger)section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return [NSString stringWithFormat:@"%@\n只在抖音前台检测；默认 300 秒，支持 30–300 秒。多人检测会依次排队；网络异常时自动减慢，不会补发后台期间的请求。", DY778RadarStore.shared.storageError.length ? DY778RadarStore.shared.storageError : DY778RadarMonitor.shared.status];
    if (section == 1) return @"可多选互关好友，也可输入未互关用户的抖音号，核对后添加。";
    if (section == 2) return @"获赞指对方收到的赞；喜欢指对方点赞的作品。四项数量和个人简介变化均会记录并提醒；首次成功读取仅建立基线。";
    if (section == 3) return @"仅保存文字和作品链接，不下载视频。自动清理在抖音前台执行；清空档案不会重置检测基线。";
    return @"适配抖音 39.9.0 接口 · iOS 14 及以上";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *options = DY778RadarStore.shared.options;
    if (path.section == 0) {
        if (path.row == 2) return DY778RadarCell(@"刷新间隔", [NSString stringWithFormat:@"每 %.0f 秒 · 点击自定义", DY778RadarInterval([options[@"interval"] doubleValue])], @"timer", YES);
        UITableViewCell *cell = DY778RadarCell(path.row == 0 ? @"特别关注" : @"动态提醒", path.row == 0 ? @"退到后台即暂停" : @"关闭弹窗仍会保存动态", path.row == 0 ? @"waveform.path.ecg" : @"bell.badge", NO);
        UISwitch *toggle = [UISwitch new]; toggle.onTintColor = DY778RadarAccent(); toggle.tag = path.row;
        toggle.on = [options[path.row == 0 ? @"enabled" : @"alerts"] boolValue];
        toggle.accessibilityLabel = path.row == 0 ? @"特别关注" : @"动态提醒";
        [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell;
    }
    if (path.section == 1) return DY778RadarCell(@"添加关注对象", @"单选、多选，确认后开始检测", @"person.crop.circle.badge.plus", YES);
    if (path.section == 2) {
        if (!self.people.count) return DY778RadarCell(@"还没有关注对象", @"从上方添加一位你想留意的人", @"person.2", NO);
        NSDictionary *person = self.people[(NSUInteger)path.row];
        NSDictionary *counts = person[@"counts"] ?: @{};
        NSString *(^number)(NSString *) = ^NSString *(NSString *key) { return [counts[key] stringValue] ?: @"—"; };
        NSString *detail = [NSString stringWithFormat:@"获赞 %@ · 关注 %@\n粉丝 %@ · 喜欢 %@\n%@ · %@", number(@"received"), number(@"following"), number(@"followers"), number(@"likes"),
            [person[@"paused"] boolValue] ? @"已暂停" : DY778RadarString(person[@"status"]), DY778RadarDateText([person[@"checkedAt"] doubleValue])];
        return DY778RadarPersonCell(person, detail, YES);
    }
    if (path.section == 3) {
        if (path.row == 0) return DY778RadarCell(@"查看动态档案", [NSString stringWithFormat:@"%lu 条 · 作品、数值与简介变化", (unsigned long)DY778RadarStore.shared.records.count], @"clock.arrow.circlepath", YES);
        if (path.row == 1) return DY778RadarCell(@"自动清理", [options[@"retentionDays"] integerValue] ? [NSString stringWithFormat:@"保留最近 %@ 天", options[@"retentionDays"]] : @"不按时间清理，仍受条数上限约束", @"calendar.badge.clock", YES);
        if (path.row == 2) return DY778RadarCell(@"记录上限", [NSString stringWithFormat:@"最多 %@ 条，超出自动移除最早记录", options[@"recordLimit"]], @"tray.full", YES);
        if (path.row == 3) return DY778RadarCell(@"一键清空档案", [NSString stringWithFormat:@"当前资料约 %@", [NSByteCountFormatter stringFromByteCount:(long long)DY778RadarStore.shared.storageBytes countStyle:NSByteCountFormatterCountStyleFile]], @"trash", NO);
        return DY778RadarCell(@"检查到期对象", @"仍遵守 30 秒最短间隔", @"arrow.clockwise", NO);
    }
    return DY778RadarCell(@"当前状态", DY778RadarMonitor.shared.status, @"info.circle", NO);
}
- (void)toggle:(UISwitch *)toggle {
    [DY778RadarStore.shared setOption:toggle.tag == 0 ? @"enabled" : @"alerts" value:@(toggle.on)];
    if (!toggle.on && toggle.tag == 1) DY778RadarDismissNotice();
}
- (void)editInterval {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"刷新间隔" message:@"输入 30–300 秒的整数。对象较多时，实际周期会包含排队时间。" preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778RadarStyle(); alert.view.tintColor = DY778RadarAccent();
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.keyboardType = UIKeyboardTypeNumberPad; field.text = [DY778RadarStore.shared.options[@"interval"] stringValue]; field.placeholder = @"默认 300 秒"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSNumber *value = DY778RadarCount(weakAlert.textFields.firstObject.text);
        if (!value || value.integerValue < 30 || value.integerValue > 300) { dispatch_async(dispatch_get_main_queue(), ^{ DY778RadarMessage(self, @"间隔不合适", @"请输入 30 到 300 之间的整数秒数。原设置已保留。"); }); return; }
        [DY778RadarStore.shared setOption:@"interval" value:value];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0 && path.row == 2) { [self editInterval]; return; }
    if (path.section == 1) {
        [DY778RadarMonitor.shared synchronizeAccount];
        if (!DY778RadarStore.shared.accountID.length) { DY778RadarMessage(self, @"请先登录", @"登录抖音后即可选择好友或输入抖音号。"); return; }
        [self.navigationController pushViewController:[DY778RadarPeoplePicker new] animated:YES]; return;
    }
    if (path.section == 2 && self.people.count) {
        DY778RadarPersonController *person = [DY778RadarPersonController new]; person.personID = self.people[(NSUInteger)path.row][@"uid"];
        [self.navigationController pushViewController:person animated:YES]; return;
    }
    if (path.section == 3) {
        if (path.row == 0) [self.navigationController pushViewController:[DY778RadarHistoryController new] animated:YES];
        if (path.row == 1) DY778RadarSheet(self, @"自动清理", @[@"保留 1 天", @"保留 7 天（默认）", @"保留 30 天", @"不按时间清理"], ^(NSUInteger index) { [DY778RadarStore.shared setOption:@"retentionDays" value:@[@1, @7, @30, @0][index]]; });
        if (path.row == 2) DY778RadarSheet(self, @"记录条数上限", @[@"100 条", @"500 条（默认）", @"1,000 条"], ^(NSUInteger index) { [DY778RadarStore.shared setOption:@"recordLimit" value:@[@100, @500, @1000][index]]; });
        if (path.row == 3) DY778RadarConfirm(self, @"清空动态档案？", @"这会删除当前账号的所有档案。关注对象和检测基线会保留。", @"全部清空", ^{ [DY778RadarStore.shared clearRecords]; });
        if (path.row == 4) { [DY778RadarMonitor.shared checkNow]; DY778RadarMessage(self, @"已安排检测", @"到期对象会依次检查；尚未到期的对象按原间隔执行。"); }
        return;
    }

}
@end

@interface DY778RadarPersonController ()
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSDictionary *person;
@end
@implementation DY778RadarPersonController
- (void)viewDidLoad {
    [super viewDidLoad]; self.account = DY778RadarStore.shared.accountID;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:DY778RadarStoreChanged object:nil];
}
- (void)refresh {
    self.person = [self.account isEqual:DY778RadarStore.shared.accountID] ? [DY778RadarStore.shared target:self.personID] : nil;
    self.title = DY778RadarDisplayName(self.person); [super refresh];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 3 : section == 1 ? 4 : 3; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"个人资料", @"最新可见数据", @"检测状态", @"管理"][(NSUInteger)section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"优先显示插件备注，其次抖音备注，最后昵称。点击个人简介复制原文（保留换行）；空简介会清空剪贴板。未返回简介时保留上次内容，不记为清空。";
    if (section == 1) return @"数值以最近成功读取为准。开启提醒后，四项可见数量变化均会提示；— 表示未提供，不按 0 处理。";
    return section == 3 ? @"重建后首次读取数值、简介和喜欢只建立基线；移除对象后已有档案保留。" : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) {
        if (path.row == 0) return DY778RadarPersonCell(self.person, [NSString stringWithFormat:@"昵称：%@\n抖音号：%@", DY778RadarString(self.person[@"name"]), DY778RadarString(self.person[@"handle"])], NO);
        if (path.row == 2) {
            NSString *title = @"个人简介 · 点击复制";
            NSString *detail = DY778RadarSignatureText(self.person[@"signature"]);
            if (self.person[@"signatureAvailable"] && ![self.person[@"signatureAvailable"] boolValue])
                title = self.person[@"signature"] ? @"上次读取的简介 · 本次未返回" : @"个人简介 · 暂未读取";
            if ([self.person[@"signatureCheckedAt"] doubleValue] > 0)
                detail = [detail stringByAppendingFormat:@"\n\n读取于 %@", DY778RadarDateText([self.person[@"signatureCheckedAt"] doubleValue])];
            else if (self.person[@"signature"]) detail = [detail stringByAppendingString:@"\n\n添加时的资料，等待首次检测"];
            if ([self.person[@"signatureChangedAt"] doubleValue] > 0)
                detail = [detail stringByAppendingFormat:@"\n最近变化 %@", DY778RadarDateText([self.person[@"signatureChangedAt"] doubleValue])];
            return DY778RadarCell(title, detail, @"text.alignleft", NO);
        }
        return DY778RadarCell(@"备注名", DY778RadarString(self.person[@"note"]).length ? self.person[@"note"] : DY778RadarString(self.person[@"remark"]).length ? [@"抖音备注：" stringByAppendingString:self.person[@"remark"]] : @"设置一个好记的名字", @"pencil", YES);
    }
    if (path.section == 1) {
        NSString *key = @[@"received", @"following", @"followers", @"likes"][(NSUInteger)path.row];
        NSString *number = [self.person[@"counts"][key] stringValue] ?: @"—";
        NSString *detail = [NSString stringWithFormat:@"最近可见 %@", number];
        for (NSDictionary *change in self.person[@"lastChanges"]) if ([change[@"key"] isEqual:key]) {
            long long delta = [change[@"delta"] longLongValue];
            detail = [detail stringByAppendingFormat:@"\n最近变化 %@%lld（%@ → %@）", delta > 0 ? @"+" : @"", delta, change[@"before"], change[@"after"]];
            if ([change[@"timestamp"] doubleValue] > 0) detail = [detail stringByAppendingFormat:@"\n%@", DY778RadarDateText([change[@"timestamp"] doubleValue])];
            break;
        }
        return DY778RadarCell(DY778RadarMetricName(key), detail, @[@"hand.thumbsup", @"person.badge.plus", @"person.2", @"heart"][(NSUInteger)path.row], NO);
    }
    if (path.section == 2) {
        if (path.row == 0) return DY778RadarCell(@"资料检测", [NSString stringWithFormat:@"%@\n%@", DY778RadarDateText([self.person[@"checkedAt"] doubleValue]), self.person[@"status"] ?: @"对象已移除或账号已切换"], @"clock", NO);
        if (path.row == 1) return DY778RadarCell(@"喜欢列表", [NSString stringWithFormat:@"%@\n%@", self.person[@"likesStatus"] ?: @"等待首次读取", DY778RadarDateText([self.person[@"likesCheckedAt"] doubleValue])], @"heart", NO);
        return DY778RadarCell(@"此人的动态档案", @"查看作品、数值和简介变化", @"clock.arrow.circlepath", YES);
    }
    if (path.row == 0) return DY778RadarCell([self.person[@"paused"] boolValue] ? @"继续检测" : @"暂停此人检测", nil, @"pause.circle", NO);
    if (path.row == 1) return DY778RadarCell(@"重建检测基线", @"下一轮只保存初始状态", @"arrow.triangle.2.circlepath", NO);
    return DY778RadarCell(@"移除关注对象", nil, @"person.crop.circle.badge.minus", NO);
}
- (void)editNote {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置备注" message:@"仅用于特别关注，搜索和提醒也会优先显示。留空恢复抖音备注或昵称。" preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778RadarStyle(); alert.view.tintColor = DY778RadarAccent();
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = DY778RadarString(self.person[@"note"]); field.placeholder = DY778RadarDisplayName(self.person); field.clearButtonMode = UITextFieldViewModeWhileEditing; }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (![self checkAccount:self.account]) return;
        NSString *note = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if (note.length > 40) { dispatch_async(dispatch_get_main_queue(), ^{ DY778RadarMessage(self, @"备注太长", @"请使用 40 个字以内的备注。"); }); return; }
        [DY778RadarStore.shared updateTarget:self.personID values:@{@"note": note}]; [DY778RadarStore.shared save]; DY778RadarToast(self, @"备注已保存");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if (![self checkAccount:self.account] || !self.person) return;
    if (path.section == 0) {
        if (path.row == 1) [self editNote];
        else if (path.row == 2) DY778RadarCopySignature(self, self.person[@"signature"]);
        else DY778RadarCopy(self, DY778RadarString(self.person[@"handle"]));
        return;
    }
    if (path.section == 2 && path.row == 2) { DY778RadarHistoryController *history = [DY778RadarHistoryController new]; history.personID = self.personID; [self.navigationController pushViewController:history animated:YES]; return; }
    if (path.section != 3) return;
    if (path.row == 0) [DY778RadarStore.shared updateTarget:self.personID values:@{@"paused": @(![self.person[@"paused"] boolValue])}];
    if (path.row == 1) DY778RadarConfirm(self, @"重建基线？", @"下次检测会作为新的起点，已有档案不会删除。", @"重建基线", ^{ if (![self checkAccount:self.account]) return; [DY778RadarMonitor.shared invalidateTarget:self.personID]; [DY778RadarStore.shared resetBaseline:self.personID]; });
    if (path.row == 2) DY778RadarConfirm(self, @"移除此人？", @"停止检测此人的动态，已保存的档案仍可查看。", @"移除", ^{ if (![self checkAccount:self.account]) return; [DY778RadarStore.shared removeTarget:self.personID]; [self.navigationController popViewControllerAnimated:YES]; });
}
@end
