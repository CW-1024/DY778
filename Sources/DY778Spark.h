#import "DY778Core.h"

FOUNDATION_EXPORT void DY778InstallSpark(void);
FOUNDATION_EXPORT void DY778SparkAppendChatItem(id provider, NSMutableArray *items);
FOUNDATION_EXPORT void DY778ResetSpark(void);
FOUNDATION_EXPORT UIViewController *DY778SparkSettingsController(void);
FOUNDATION_EXPORT BOOL DY778SparkHasCustomizationsForAccount(NSString *account);
FOUNDATION_EXPORT void DY778RestoreSparkForAccount(NSString *account);
FOUNDATION_EXPORT void DY778InstallSparkMenu(void);
