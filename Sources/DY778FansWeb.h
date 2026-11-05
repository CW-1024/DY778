#import "DY778FansModel.h"

typedef void (^DY778FansWebReply)(id response, NSError *error);
BOOL DY778FansWebConnected(void);
@interface DY778FansWebClient : NSObject
- (void)get:(NSString *)route params:(NSDictionary *)params completion:(DY778FansWebReply)completion;
- (void)cancel;
@end
