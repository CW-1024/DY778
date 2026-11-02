#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *DY778RecallMessageKind(NSString *className);

FOUNDATION_EXPORT NSDictionary *DY778RecallEnrichRecord(NSDictionary *record);
FOUNDATION_EXPORT NSArray *DY778RecallMediaFromContent(id content);
FOUNDATION_EXPORT NSString *DY778RecallSummary(NSDictionary *record);
FOUNDATION_EXPORT BOOL DY778RecallContentIsNotice(id content);
FOUNDATION_EXPORT NSDictionary *DY778RecallCommentFromContent(id content);
FOUNDATION_EXPORT NSDictionary *DY778MergeCapturedComment(NSDictionary *previous, NSDictionary *candidate);
// A validated work identifier for the native detail route; never an arbitrary URL.
FOUNDATION_EXPORT NSString *DY778RecallWorkIdentifier(NSDictionary *record);

FOUNDATION_EXPORT BOOL DY778RecallRecordShouldHide(NSDictionary *record);
FOUNDATION_EXPORT NSArray *DY778RecallPreviewCandidates(NSDictionary *record);
FOUNDATION_EXPORT NSDictionary *DY778RecallPrimaryMedia(NSDictionary *record);
