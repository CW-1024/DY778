#import "DY778Core.h"
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, DY778ConfirmActionType) {
    DY778ConfirmActionLike,
    DY778ConfirmActionFavorite,
    DY778ConfirmActionFollow,
    DY778ConfirmActionCommentLike,
    DY778ConfirmActionCommentDislike,
    DY778ConfirmActionCount,
};

typedef NS_ENUM(NSUInteger, DY778ConfirmIntent) {
    DY778ConfirmIntentToggle,
    DY778ConfirmIntentAdd,
    DY778ConfirmIntentRemove,
};

FOUNDATION_EXPORT NSString *const DY778ConfirmLikeEnabledKey;
FOUNDATION_EXPORT NSString *const DY778ConfirmFavoriteEnabledKey;
FOUNDATION_EXPORT NSString *const DY778ConfirmFollowEnabledKey;
FOUNDATION_EXPORT NSString *const DY778ConfirmCommentLikeEnabledKey;
FOUNDATION_EXPORT NSString *const DY778ConfirmCommentDislikeEnabledKey;
FOUNDATION_EXPORT NSNotificationName const DY778ConfirmThemeDidChangeNotification;

FOUNDATION_EXPORT void DY778ConfirmEnsureDefaults(void);
FOUNDATION_EXPORT BOOL DY778ConfirmEnabled(DY778ConfirmActionType action);
FOUNDATION_EXPORT BOOL DY778ConfirmIsReplaying(DY778ConfirmActionType action);
FOUNDATION_EXPORT id DY778ConfirmRead(id object, NSString *key);
FOUNDATION_EXPORT UIWindow *DY778ConfirmActiveWindow(void);
FOUNDATION_EXPORT UIColor *DY778ConfirmAccent(DY778ConfirmActionType action);
FOUNDATION_EXPORT UIUserInterfaceStyle DY778ConfirmUserInterfaceStyle(void);

FOUNDATION_EXPORT void DY778ConfirmGuard(DY778ConfirmActionType action, DY778ConfirmIntent intent,
                                  id owner, id subject, dispatch_block_t operation,
                                  dispatch_block_t cancellation, dispatch_block_t confirmedUnfollow);
