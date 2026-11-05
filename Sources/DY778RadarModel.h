#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
extern NSString *const DY778RadarVersion;
extern NSString *const DY778RadarName;
extern NSNotificationName const DY778RadarStoreChanged;
extern NSNotificationName const DY778RadarThemeChanged;
id _Nullable DY778RadarRead(id _Nullable object, NSString *key);
id _Nullable DY778RadarFirst(id _Nullable object, NSArray<NSString *> *keys);
NSString *DY778RadarString(id _Nullable value);
NSNumber * _Nullable DY778RadarCount(id _Nullable value);
BOOL DY778RadarIdentifier(id _Nullable value);
BOOL DY778RadarSet(id _Nullable object, NSString *key, id _Nullable value);
BOOL DY778RadarHasMethod(id _Nullable receiver, NSString *selector, const char *returns, const char *arguments);
id _Nullable DY778RadarCall(id _Nullable receiver, NSString *selector, NSArray *arguments);
NSDictionary * _Nullable DY778RadarProfile(id _Nullable value);
extern NSUInteger const DY778RadarSignatureLimit;
NSString *DY778RadarSignatureText(id _Nullable value);
NSDictionary * _Nullable DY778RadarVideo(id _Nullable value);
NSArray<NSDictionary *> *DY778RadarChanges(NSDictionary *previous, NSDictionary *current);
NSDictionary *DY778RadarCompareLikes(NSDictionary * _Nullable previous, NSArray<NSDictionary *> *videos, BOOL complete);
NSString *DY778RadarMetricName(NSString *key);
NSString *DY778RadarDisplayName(NSDictionary *person);
NSString *DY778RadarPersonSearchText(NSDictionary *person);
NSString *DY778RadarDateText(NSTimeInterval timestamp);
NSError *DY778RadarError(NSInteger code, NSString *message);
NS_ASSUME_NONNULL_END
