#import "DY778RadarNetwork.h"
NS_ASSUME_NONNULL_BEGIN
@interface DY778RadarApi : NSObject
+ (void)profile:(NSDictionary *)target owner:(NSString *)owner completion:(DY778RadarReply)completion;
+ (void)resolveHandle:(NSString *)handle owner:(NSString *)owner completion:(DY778RadarReply)completion;
+ (void)friendsForOwner:(NSString *)owner completion:(DY778RadarReply)completion;
+ (void)likes:(NSDictionary *)target cursor:(NSNumber *)cursor owner:(NSString *)owner completion:(DY778RadarReply)completion;
@end
NS_ASSUME_NONNULL_END
