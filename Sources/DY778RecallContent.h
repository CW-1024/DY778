#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *DY778RecallMessageKind(NSString *className);

FOUNDATION_EXPORT NSDictionary *DY778RecallEnrichRecord(NSDictionary *record);
FOUNDATION_EXPORT NSArray *DY778RecallMediaFromContent(id content);
FOUNDATION_EXPORT NSString *DY778RecallSummary(NSDictionary *record);
FOUNDATION_EXPORT BOOL DY778RecallContentIsNotice(id content);
FOUNDATION_EXPORT NSDictionary *DY778RecallCommentFromContent(id content);
FOUNDATION_EXPORT NSDictionary *DY778MergeCapturedComment(NSDictionary *previous, NSDictionary *candidate);
// 经校验的作品标识，用于原生详情路由，绝非任意 URL。
FOUNDATION_EXPORT NSString *DY778RecallWorkIdentifier(NSDictionary *record);

FOUNDATION_EXPORT BOOL DY778RecallRecordShouldHide(NSDictionary *record);
FOUNDATION_EXPORT NSArray *DY778RecallPreviewCandidates(NSDictionary *record);
FOUNDATION_EXPORT NSDictionary *DY778RecallPrimaryMedia(NSDictionary *record);
