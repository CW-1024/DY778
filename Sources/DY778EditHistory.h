#import "DY778Core.h"
FOUNDATION_EXPORT NSNotificationName const DY778EditHistoryChangedNotification;
FOUNDATION_EXPORT NSNotificationName const DY778EditDetectedNotification;
FOUNDATION_EXPORT void DY778InstallEditHistory(void);
FOUNDATION_EXPORT void DY778ObserveEditedMessage(id message, NSDictionary *content, NSDictionary *editInfo);
FOUNDATION_EXPORT void DY778ObserveEditContext(id viewModel);
FOUNDATION_EXPORT NSDictionary *DY778EditInfoSnapshot(id info);
FOUNDATION_EXPORT NSDictionary *DY778EditRecordForMessage(id message);
FOUNDATION_EXPORT BOOL DY778EditEnabledForConversation(NSString *conversation);
FOUNDATION_EXPORT void DY778SetConversationEditEnabled(NSString *conversation, BOOL enabled);
FOUNDATION_EXPORT void DY778PresentEditHistory(UIViewController *source, NSString *conversation, NSString *messageKey);
FOUNDATION_EXPORT void DY778ClearEditHistory(void);
FOUNDATION_EXPORT void DY778EditHistoryMaintenance(void);
FOUNDATION_EXPORT NSString *DY778EditHistoryStatus(void);
FOUNDATION_EXPORT BOOL DY778EditCaptureEnabled(void);
