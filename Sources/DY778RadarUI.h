#import <UIKit/UIKit.h>
#import "DY778RadarMonitor.h"
UIWindow *DY778RadarActiveWindow(void);
UIViewController *DY778RadarTopController(UIViewController *controller);
UIUserInterfaceStyle DY778RadarStyle(void);
UIColor *DY778RadarAccent(void);
UIColor *DY778RadarButtonColor(void);
UILabel *DY778RadarLabel(NSString *text, CGFloat size, UIFontWeight weight);
UITableViewCell *DY778RadarCell(NSString *title, NSString *subtitle, NSString *symbol, BOOL disclosure);
UITableViewCell *DY778RadarPersonCell(NSDictionary *person, NSString *subtitle, BOOL disclosure);
void DY778RadarToast(UIViewController *presenter, NSString *message);
void DY778RadarMessage(UIViewController *presenter, NSString *title, NSString *message);
void DY778RadarConfirm(UIViewController *presenter, NSString *title, NSString *message, NSString *button, dispatch_block_t action);
void DY778RadarSheet(UIViewController *presenter, NSString *title, NSArray<NSString *> *options, void (^chosen)(NSUInteger index));
void DY778RadarCopy(UIViewController *presenter, NSString *text);
void DY778RadarCopySignature(UIViewController *presenter, id signature);
void DY778RadarOpenVideo(UIViewController *presenter, NSString *videoID);
void DY778RadarOpenSettings(void);
@interface DY778RadarTableController : UITableViewController
- (void)refresh;
- (void)updateTheme;
- (BOOL)checkAccount:(NSString *)account;
@end
@interface DY778RadarSettingsController : DY778RadarTableController
@end
@interface DY778RadarPeoplePicker : DY778RadarTableController
@end
@interface DY778RadarHistoryController : DY778RadarTableController
@property(nonatomic, copy) NSString *personID;
@end
@interface DY778RadarPersonController : DY778RadarTableController
@property(nonatomic, copy) NSString *personID;
@end
@interface DY778RadarRecordController : DY778RadarTableController
@property(nonatomic, copy) NSDictionary *record;
@end
void DY778RadarShowNotice(NSArray<NSDictionary *> *events);
void DY778RadarDismissNotice(void);
