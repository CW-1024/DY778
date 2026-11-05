#import "DY778Enhancements.h"
#import "DY778LiveInfoPolicy.h"
FOUNDATION_EXPORT NSString *DY778LiveRoomIdentifier(id room);
FOUNDATION_EXPORT double DY778LiveRoomStart(id room, NSString *roomID, NSUInteger depth);
FOUNDATION_EXPORT NSString *DY778LiveElapsedText(double start);
FOUNDATION_EXPORT NSString *DY778LiveElapsedDigits(double start);
FOUNDATION_EXPORT void DY778InstallPreviewHooks(void);
FOUNDATION_EXPORT BOOL DY778LiveRoomAPIAvailable(Class cls);
@interface DY778LiveCapsule : UIView
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) UIImageView *symbol;
@property(nonatomic) BOOL clock;
- (void)setViewerCountString:(NSString *)text;
- (void)setElapsedString:(NSString *)text;
@end
