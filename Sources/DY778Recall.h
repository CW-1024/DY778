#import "DY778Core.h"

FOUNDATION_EXPORT void DY778InstallRecallHooks(void);
FOUNDATION_EXPORT void DY778ObserveMessage(id message);
FOUNDATION_EXPORT BOOL DY778MessageWasRecalled(id message);
FOUNDATION_EXPORT NSDictionary *DY778RecallRecordForMessage(id message);
FOUNDATION_EXPORT void DY778PresentRecallArchive(UIViewController *source, NSString *conversationID);
FOUNDATION_EXPORT BOOL DY778RestoreRecallPresentation(id viewModel, id message);
FOUNDATION_EXPORT void DY778ClearRecallArchive(void);
FOUNDATION_EXPORT NSUInteger DY778RecallCount(void);
FOUNDATION_EXPORT void DY778RecallMaintenance(void);
FOUNDATION_EXPORT NSString *DY778RecallStorageStatus(void);
FOUNDATION_EXPORT BOOL DY778RecallEnabledForMessage(id message);
FOUNDATION_EXPORT BOOL DY778RecallEnabledForConversation(NSString *conversationID);
FOUNDATION_EXPORT void DY778SetConversationRecallEnabled(NSString *conversationID, BOOL enabled);
FOUNDATION_EXPORT void DY778ObserveMessageContext(id viewModel);
FOUNDATION_EXPORT void DY778ClearConversationRecallArchive(NSString *conversationID);
FOUNDATION_EXPORT void DY778RecallStorageStatistics(void (^completion)(NSDictionary *statistics));

FOUNDATION_EXPORT NSDictionary *DY778MessageIdentity(id message);
FOUNDATION_EXPORT NSTimeInterval DY778MessageTimestamp(id value);
