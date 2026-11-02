#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

FOUNDATION_EXPORT NSString *const DY778Version;
FOUNDATION_EXPORT NSString *const DY778BuildTime;
FOUNDATION_EXPORT NSNotificationName const DY778PreferencesChangedNotification;
FOUNDATION_EXPORT NSNotificationName const DY778RecallChangedNotification;
FOUNDATION_EXPORT NSNotificationName const DY778RecallDetectedNotification;
FOUNDATION_EXPORT void DY778RegisterDefaults(void);
FOUNDATION_EXPORT void DY778ResetSettings(void);
FOUNDATION_EXPORT NSUserDefaults *DY778Preferences(void);
FOUNDATION_EXPORT BOOL DY778Bool(NSString *key);
FOUNDATION_EXPORT double DY778Number(NSString *key);
FOUNDATION_EXPORT NSString *DY778String(NSString *key);
FOUNDATION_EXPORT NSString *DY778RecallMarkerText(void);
FOUNDATION_EXPORT NSString *DY778EditMarkerText(void);
FOUNDATION_EXPORT void DY778Set(NSString *key, id value);
FOUNDATION_EXPORT id DY778Read(id object, NSString *key);
FOUNDATION_EXPORT BOOL DY778Write(id object, NSString *key, id value);
FOUNDATION_EXPORT NSString *DY778Identifier(id value);
FOUNDATION_EXPORT NSString *DY778CurrentAccountID(void);
FOUNDATION_EXPORT BOOL DY778Hook(Class cls, SEL selector, IMP replacement, IMP *original);
FOUNDATION_EXPORT void DY778RecordHook(NSString *name, BOOL installed);
FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> *DY778HookReport(void);
FOUNDATION_EXPORT UIWindow *DY778ActiveWindow(void);
FOUNDATION_EXPORT UIViewController *DY778TopController(void);
FOUNDATION_EXPORT UIUserInterfaceStyle DY778InterfaceStyle(void);
FOUNDATION_EXPORT UIColor *DY778Accent(void);
FOUNDATION_EXPORT UIColor *DY778Background(void);
FOUNDATION_EXPORT UIColor *DY778CardBackground(void);
FOUNDATION_EXPORT UIColor *DY778ColorFromHex(NSString *hex, UIColor *fallback);
FOUNDATION_EXPORT void DY778StyleController(UIViewController *controller);
FOUNDATION_EXPORT void DY778PresentController(UIViewController *source, UIViewController *controller);
FOUNDATION_EXPORT void DY778Toast(NSString *message);
FOUNDATION_EXPORT void DY778ShowToast(NSString *channel, NSString *message, BOOL loading, BOOL success);
FOUNDATION_EXPORT void DY778DismissToast(NSString *channel);
FOUNDATION_EXPORT void DY778ShowSpeedToast(NSString *token, double rate);
FOUNDATION_EXPORT void DY778DismissSpeedToast(NSString *token);
FOUNDATION_EXPORT void DY778ShowNotice(UIViewController *source, NSString *title, NSString *message);
FOUNDATION_EXPORT void DY778Confirm(UIViewController *source, NSString *title, NSString *message,
                                  NSString *confirmTitle, BOOL destructive, dispatch_block_t action);
FOUNDATION_EXPORT void DY778ConfirmDelayed(UIViewController *source, NSString *title, NSString *message,
                                         NSTimeInterval delay, dispatch_block_t action);
FOUNDATION_EXPORT void DY778InstallCoreHooks(void);
FOUNDATION_EXPORT void DY778InstallSettingsHook(void);
FOUNDATION_EXPORT UIViewController *DY778SettingsController(void);
