#import <UIKit/UIKit.h>
@interface DY778RecallMediaView : UIView
@property(nonatomic, copy) void (^openMedia)(NSDictionary *media);
@property(nonatomic, copy) dispatch_block_t openOriginal;
@property(nonatomic, copy) dispatch_block_t openMessage;
- (void)cancel;
- (void)configureRecord:(NSDictionary *)record;
@end

@interface DY778RecallCoverView : UIImageView
- (void)configureRecord:(NSDictionary *)record;
- (void)cancel;
@end
