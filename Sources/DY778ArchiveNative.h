#import <UIKit/UIKit.h>

FOUNDATION_EXPORT BOOL DY778ArchiveCanLocate(NSDictionary *record);
FOUNDATION_EXPORT NSArray<NSDictionary *> *DY778ArchiveLocalMedia(NSDictionary *record);
FOUNDATION_EXPORT UIImage *DY778ArchivePreviewImage(NSDictionary *record);
FOUNDATION_EXPORT void DY778ArchiveLocateMessage(UIViewController *source, NSDictionary *record);
FOUNDATION_EXPORT void DY778ArchiveCellWillReuse(UITableViewCell *cell);
