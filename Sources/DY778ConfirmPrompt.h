#import "DY778ConfirmCore.h"

@interface DY778ConfirmPrompt : UIView
+ (void)presentForAction:(DY778ConfirmActionType)action intent:(DY778ConfirmIntent)intent
                    name:(NSString *)name isComment:(BOOL)isComment
                decision:(void (^)(BOOL confirmed))decision;
+ (void)showStaleNotice;
@end
