#import "DY778FansModel.h"

typedef void (^DY778FansReply)(id value, NSError *error);
NSString *DY778FansLastDiagnostic(void);
@interface DY778FansService : NSObject
@property(nonatomic, copy) void (^progress)(NSString *text);
@property(nonatomic, copy) void (^partialResult)(DY778FansResult *result);
- (void)queryInput:(NSString *)input mode:(DY778FansInputMode)mode target:(NSDictionary *)target anchor:(NSDictionary *)anchor completion:(void (^)(DY778FansResult *, NSError *))completion;
- (void)resolveInput:(NSString *)input mode:(DY778FansInputMode)mode completion:(DY778FansReply)completion;
- (void)refreshPerson:(NSDictionary *)person completion:(DY778FansReply)completion;
- (void)cancel;
@end
