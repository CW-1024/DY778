#import "DY778Core.h"
#import "DY778EditHistory.h"
#import "DY778Recall.h"
#import "DY778LuckyBag.h"
#import "DY778MessageUI.h"
#import "DY778RecallNotifications.h"
#import "DY778Playback.h"
#import "DY778CacheCleaner.h"
#import "DY778FeedFilter.h"

static void DY778InstallModules(void) {
    DY778InstallCoreHooks();
    DY778InstallSettingsHook();
    DY778InstallEditHistory();
    DY778InstallRecallHooks();
    DY778InstallRecallNotifications();
    DY778InstallMessageUIHooks();
    DY778InstallLuckyBagHooks();
    DY778InstallPlaybackHooks();
    DY778InstallDefaultPlaybackHooks();
    DY778InstallFeedFilterHooks();
    DY778InstallCacheCleanerHooks();
}
__attribute__((constructor)) static void DY778Start(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.ss.iphone.ugc.Aweme"]) return;
        DY778RegisterDefaults();
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778InstallModules();
            for (NSNumber *delay in @[@1, @3, @10]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ DY778InstallModules(); });
            }
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) { DY778InstallModules(); }];
            [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                    NSString *key = notification.userInfo[@"key"];
                    if (!key.length || [key hasPrefix:@"lucky."] || [key isEqualToString:@"appearance"] || [key isEqualToString:@"accent"]) DY778LuckyPreferencesChanged();
                    if (!key.length || [@[@"recall.enabled", @"recall.retentionDays", @"recall.maxRecords"] containsObject:key]) DY778RecallMaintenance();
                }];
        });
    }
}
