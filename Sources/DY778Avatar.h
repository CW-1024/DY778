#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString *DY778AvatarURL(id value);
FOUNDATION_EXPORT void DY778LoadAvatar(UIImageView *view, NSString *url, NSString *identity);
FOUNDATION_EXPORT void DY778LoadCurrentAccountAvatar(UIImageView *view);
FOUNDATION_EXPORT void DY778GetCurrentAccountProfile(void (^completion)(NSDictionary *profile));
FOUNDATION_EXPORT NSDictionary *DY778ProfileFromUser(id user);
FOUNDATION_EXPORT void DY778GetLocalUserProfile(NSString *account, NSString *uid, void (^completion)(NSDictionary *profile));

FOUNDATION_EXPORT NSArray *DY778AvatarURLs(id value);
FOUNDATION_EXPORT void DY778LoadAvatarURLs(UIImageView *view, NSArray *urls, NSString *identity);
