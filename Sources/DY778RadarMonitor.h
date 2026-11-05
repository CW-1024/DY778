#import "DY778RadarStore.h"
NS_ASSUME_NONNULL_BEGIN
extern NSNotificationName const DY778RadarMonitorStatusChanged;
extern NSNotificationName const DY778RadarMonitorAlert;
@interface DY778RadarMonitor : NSObject
+ (instancetype)shared;
@property(nonatomic, readonly) BOOL busy;
@property(nonatomic, readonly, copy) NSString *status;
- (void)start;
- (void)synchronizeAccount;
- (void)checkNow;
- (void)invalidateTarget:(NSString *)uid;
@end
NS_ASSUME_NONNULL_END
