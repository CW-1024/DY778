#import "DY778Enhancements.h"
#import "DY778RadarUI.h"

@protocol DY778RadarChatItem <NSObject>
- (instancetype)initWithIdentifier:(NSString *)identifier;
@end

static NSDictionary *DY778RadarChatPerson(id provider) {
    id context = DY778Read(provider, @"context");
    id conversation = DY778Read(context, @"conversation") ?: DY778Read(context, @"con");
    if ([DY778Read(conversation, @"isGroupChat") boolValue] || [DY778Read(conversation, @"isGroup") boolValue]) return nil;
    NSDictionary *person = DY778RadarProfile(DY778Read(context, @"peerUser"));
    return [person[@"uid"] isEqual:DY778CurrentAccountID()] ? nil : person;
}
void DY778RadarAppendChatItem(id provider, NSMutableArray *items) {
    [DY778RadarMonitor.shared synchronizeAccount];
    NSDictionary *person = DY778RadarChatPerson(provider);
    NSString *uid = person[@"uid"], *account = DY778RadarStore.shared.accountID;
    if (!uid.length || !account.length) return;
    Class cls = NSClassFromString(@"IESIMChatSettingsItemSwitchViewModel");
    Method initializer = class_getInstanceMethod(cls, @selector(initWithIdentifier:));
    if (!initializer || method_getNumberOfArguments(initializer) != 3) return;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(initializer)];
    if (signature.methodReturnType[0] != '@' || [signature getArgumentTypeAtIndex:2][0] != '@') return;
    id toggle = [(id<DY778RadarChatItem>)[cls alloc] initWithIdentifier:@"com.dy778.radar-switch"];
    NSDictionary *target = [DY778RadarStore.shared target:uid];
    BOOL master = [DY778RadarStore.shared.options[@"enabled"] boolValue];
    DY778Write(toggle, @"title", @"对此人特别关注");
    DY778Write(toggle, @"describe", master ? @"前台检测可见数据变化，记录新发现的喜欢作品" : @"先在 DY778 → 特别关注开启总开关");
    DY778Write(toggle, @"isOn", @(master && target && ![target[@"paused"] boolValue]));
    __weak id weakProvider = provider, weakToggle = toggle;
    void (^changed)(BOOL) = ^(BOOL on) {
        [DY778RadarMonitor.shared synchronizeAccount];
        if (![account isEqual:DY778RadarStore.shared.accountID] || ![uid isEqual:DY778RadarChatPerson(weakProvider)[@"uid"]]) return;
        if (![DY778RadarStore.shared.options[@"enabled"] boolValue]) {
            DY778Write(weakToggle, @"isOn", @NO);
            DY778Toast(@"请先在 DY778 → 特别关注开启总开关"); return;
        }
        NSError *error = nil;
        if (on && ![DY778RadarStore.shared target:uid] && ![DY778RadarStore.shared addProfiles:@[person] error:&error]) {
            DY778Write(weakToggle, @"isOn", @NO); DY778Toast(error.localizedDescription ?: @"暂时无法添加此人"); return;
        }
        [DY778RadarStore.shared updateTarget:uid values:@{@"paused": @(!on)}];
        DY778Write(weakToggle, @"isOn", @(on));
        DY778Toast(on ? @"已开启对此人的特别关注" : @"已暂停对此人的特别关注");
    };
    if (toggle && DY778Write(toggle, @"manualSwitchChanged", changed)) [items addObject:toggle];
}
void DY778InstallRadar(void) {
    [DY778RadarMonitor.shared start];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:DY778RadarMonitorAlert object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            DY778RadarShowNotice(note.object);
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            [NSNotificationCenter.defaultCenter postNotificationName:DY778RadarThemeChanged object:nil];
        }];
    });
}
void DY778ResetEnhancementSettings(void) {
    [DY778RadarMonitor.shared synchronizeAccount];
    for (NSString *key in @[@"enabled", @"alerts", @"interval", @"retentionDays", @"recordLimit"]) {
        NSDictionary *defaults = @{@"enabled": @NO, @"alerts": @YES, @"interval": @300, @"retentionDays": @7, @"recordLimit": @500};
        [DY778RadarStore.shared setOption:key value:defaults[key]];
    }
    DY778RadarDismissNotice();
    DY778ResetLiveClockPosition();
}
