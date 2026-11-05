#import "DY778Core.h"
#import <Foundation/Foundation.h>

extern NSString * const DY778FansName;
extern NSString * const DY778FansVersion;
extern NSString * const DY778FansPreferencesChanged;

id DY778FansRead(id object, NSString *key);
id DY778FansFirst(id object, NSArray<NSString *> *keys);
BOOL DY778FansSet(id object, NSString *key, id value);
BOOL DY778FansHas(id object, NSString *selector, const char *returns, const char *arguments);
id DY778FansCall(id object, NSString *selector, NSArray *arguments);
NSString *DY778FansString(id value);
NSNumber *DY778FansInteger(id value);
BOOL DY778FansUID(NSString *text);
BOOL DY778FansSecUID(NSString *text);
BOOL DY778FansEnabled(NSString *key);
NSError *DY778FansError(NSInteger code, NSString *message);
NSString *DY778FansAccount(void);
