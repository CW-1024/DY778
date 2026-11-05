#import "DY778RadarModel.h"
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^DY778RadarReply)(id _Nullable value, NSError * _Nullable error);
typedef BOOL (^DY778RadarIsCurrent)(void);
// 在主线程启动；返回的取消只作用于本次操作（绝非宿主共享服务）。
typedef dispatch_block_t _Nullable (^DY778RadarStartOperation)(DY778RadarReply reply, DY778RadarIsCurrent isCurrent);
NSString *DY778RadarCurrentAccount(void);
NSString *DY778RadarDiagnosticText(NSError *error);
@interface DY778RadarNetwork : NSObject
+ (instancetype)shared;
- (void)get:(NSString *)url parameters:(NSDictionary *)parameters owner:(NSString *)owner completion:(DY778RadarReply)completion;
- (void)perform:(NSString *)stage owner:(NSString *)owner start:(DY778RadarStartOperation)start completion:(DY778RadarReply)completion;
- (void)cancelOwner:(NSString *)owner;
- (void)cancelAll;
@end
NS_ASSUME_NONNULL_END
