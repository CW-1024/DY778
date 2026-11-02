#import "DY778ArchiveStorage.h"

static NSString *const DY778LegacyDirectory = @"ChengGuang";
static NSString *const DY778LegacyPreferences = @"com.chengguang.douyin";

NSURL *DY778PrepareArchiveDirectory(NSURL *support, NSString *component, NSError **error) {
    if (!support.isFileURL || ![@[@"Recall", @"EditHistory"] containsObject:component]) return nil;
    NSFileManager *manager = NSFileManager.defaultManager;
    NSDictionary *protection = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    NSURL *root = [support URLByAppendingPathComponent:@"DY778" isDirectory:YES];
    NSURL *target = [root URLByAppendingPathComponent:component isDirectory:YES];
    NSURL *legacy = [[support URLByAppendingPathComponent:DY778LegacyDirectory isDirectory:YES] URLByAppendingPathComponent:component isDirectory:YES];
    if (![manager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:protection error:error]) return nil;
    if (![manager fileExistsAtPath:target.path] && [manager fileExistsAtPath:legacy.path]) {
        // 在打开 SQLite 前整体移动目录，保留 WAL 和 SHM。
        if (![manager moveItemAtURL:legacy toURL:target error:error]) return nil;
    }
    if (![manager createDirectoryAtURL:target withIntermediateDirectories:YES attributes:protection error:error]) return nil;
    [target setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    return target;
}
NSURL *DY778ArchiveDirectory(NSString *component) {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return DY778PrepareArchiveDirectory(support, component, nil);
}
NSString *DY778ArchiveMediaPath(NSString *path) {
    if (![path isKindOfClass:NSString.class] || !path.length) return nil;
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *prefix = [[[support URLByAppendingPathComponent:DY778LegacyDirectory] path] stringByAppendingString:@"/"];
    if ([path hasPrefix:prefix]) return [[[support URLByAppendingPathComponent:@"DY778"] path] stringByAppendingPathComponent:[path substringFromIndex:prefix.length]];
    return path;
}
NSUserDefaults *DY778MigratedPreferences(void) {
    NSString *domain = @"com.dy778.douyin";
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:domain];
    if (![preferences boolForKey:@"data.preferencesMigrated"]) {
        NSMutableDictionary *merged = [[preferences persistentDomainForName:DY778LegacyPreferences] mutableCopy] ?: [NSMutableDictionary dictionary];
        [merged addEntriesFromDictionary:[preferences persistentDomainForName:domain] ?: @{}];
        merged[@"data.preferencesMigrated"] = @YES;
        [preferences setPersistentDomain:merged forName:domain];
    }
    return preferences;
}
BOOL DY778IsLegacyRecallNotification(NSString *identifier) { return [identifier hasPrefix:@"ChengGuang.Recall."]; }
