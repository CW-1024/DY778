#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSURL *DY778ArchiveDirectory(NSString *component);
FOUNDATION_EXPORT NSURL *DY778PrepareArchiveDirectory(NSURL *support, NSString *component, NSError **error);
FOUNDATION_EXPORT NSString *DY778ArchiveMediaPath(NSString *path);
FOUNDATION_EXPORT NSUserDefaults *DY778MigratedPreferences(void);
FOUNDATION_EXPORT BOOL DY778IsLegacyRecallNotification(NSString *identifier);
