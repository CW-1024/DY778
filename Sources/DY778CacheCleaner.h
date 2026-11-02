#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSNotificationName const DY778CacheStatisticsChangedNotification;
FOUNDATION_EXPORT void DY778InstallCacheCleanerHooks(void);
FOUNDATION_EXPORT void DY778RunCacheMaintenance(void);
FOUNDATION_EXPORT NSDictionary *DY778CachedCacheStatistics(void);
FOUNDATION_EXPORT void DY778CacheStatistics(void (^completion)(NSDictionary *statistics));
FOUNDATION_EXPORT void DY778RefreshCacheStatistics(void (^completion)(NSDictionary *statistics));
FOUNDATION_EXPORT void DY778CleanHostCache(void (^completion)(NSDictionary *statistics));
FOUNDATION_EXPORT void DY778CancelHostCacheCleanup(void);
FOUNDATION_EXPORT NSString *DY778CacheFormatBytes(uint64_t bytes);
