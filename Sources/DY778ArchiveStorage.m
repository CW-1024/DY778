#import "DY778ArchiveStorage.h"

NSURL *DY778PrepareArchiveDirectory(NSURL *support, NSString *component, NSError **error) {
    if (!support.isFileURL || ![@[@"Recall", @"EditHistory"] containsObject:component]) return nil;
    NSFileManager *manager = NSFileManager.defaultManager;
    NSDictionary *protection = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    NSURL *root = [support URLByAppendingPathComponent:@"DY778" isDirectory:YES];
    NSURL *target = [root URLByAppendingPathComponent:component isDirectory:YES];
    if (![manager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:protection error:error]) return nil;
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
    return path;
}
NSUserDefaults *DY778CreatePreferences(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:@"com.dy778.douyin"];
}
