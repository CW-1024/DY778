#import "DY778CacheCleaner.h"
#import "DY778Core.h"
#import "DY778CachePolicy.h"
#import <stdatomic.h>
#import <mach-o/dyld.h>

NSNotificationName const DY778CacheStatisticsChangedNotification = @"com.dy778.cache-statistics";
static dispatch_queue_t DY778CacheQueue;
static atomic_bool DY778CacheEnabled, DY778CacheOnLaunch, DY778CacheOnReturn, DY778CacheForeground, DY778CachePending, DY778CacheManualPending, DY778CacheCancelled;
static DY778CacheLifecycle DY778CacheLifecycleState;
static int DY778CacheCurrentEvent;
static _Atomic(NSUInteger) DY778CacheOpenGeneration;
static _Atomic(double) DY778CacheMaxMB, DY778CacheMaxAge;
static NSDictionary *DY778LastCacheStatistics, *DY778LastCacheResult, *DY778VisibleCacheStatistics, *DY778LastCompleteCacheStatistics;
static CFAbsoluteTime DY778CacheLastScan;
static dispatch_source_t DY778CacheTimer;

@interface DY778CacheRoot : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic) int descriptor;
@property(nonatomic) int scope;
@property(nonatomic) uint64_t bytes;
@property(nonatomic) uint64_t reclaimable;
@end
@implementation DY778CacheRoot
- (instancetype)init { if ((self = [super init])) _descriptor = -1; return self; }
- (void)dealloc { if (_descriptor >= 0) close(_descriptor); }
@end
@interface DY778CacheFile : NSObject
@property(nonatomic, strong) DY778CacheRoot *root;
@property(nonatomic, copy) NSString *relative;
@property(nonatomic) struct stat snapshot;
@property(nonatomic) double newestWrite;
@property(nonatomic) int kind;
@end
@implementation DY778CacheFile @end

@interface DY778CacheJob : NSObject { @public DY778CacheWalker walker; }
@property(nonatomic, strong) NSArray<DY778CacheRoot *> *roots;
@property(nonatomic, strong) NSMutableArray<DY778CacheFile *> *oldest;
@property(nonatomic, strong) NSMutableArray *completions;
@property(nonatomic, strong) NSMutableSet<NSString *> *skippedFiles;
@property(nonatomic) NSUInteger rootIndex;
@property(nonatomic) NSUInteger count;
@property(nonatomic) uint64_t bytes;
@property(nonatomic) uint64_t managedBytes;
@property(nonatomic) uint64_t reclaimableBytes;
@property(nonatomic) uint64_t deletedBytes;
@property(nonatomic) NSUInteger deletedCount;
@property(nonatomic) NSUInteger passDeleted;
@property(nonatomic) NSUInteger passSkipped;
@property(nonatomic) NSUInteger deleteIndex;
@property(nonatomic) NSUInteger skipped;
@property(nonatomic) BOOL remove;
@property(nonatomic) BOOL manual;
@property(nonatomic) BOOL byRules;
@property(nonatomic) int activationEvent;
@property(nonatomic) NSUInteger activationGeneration;
@property(nonatomic) BOOL incomplete;
@property(nonatomic) BOOL overflow;
@property(nonatomic) BOOL cancelled;
@property(nonatomic) BOOL scanFinished;
@property(nonatomic) BOOL needsSafetyScan;
@property(nonatomic) BOOL verifying;
@property(nonatomic, copy) NSArray<NSString *> *pluginNames;
@property(nonatomic) CFAbsoluteTime started;
@property(nonatomic) CFAbsoluteTime published;
@end
@implementation DY778CacheJob
- (instancetype)init { if ((self = [super init])) { _oldest = [NSMutableArray array]; _completions = [NSMutableArray array]; _skippedFiles = [NSMutableSet set]; _started = CFAbsoluteTimeGetCurrent(); } return self; }
- (void)dealloc { DY778CacheWalkClose(&walker); }
@end
static DY778CacheJob *DY778ActiveCacheJob;

NSDictionary *DY778CachedCacheStatistics(void) { return NSThread.isMainThread ? DY778VisibleCacheStatistics : nil; }
NSString *DY778CacheFormatBytes(uint64_t bytes) {
    if (!bytes) return @"0 MB";
    if (bytes < 104858) return @"<0.1 MB";
    if (bytes < 1073741824ULL) return [NSString stringWithFormat:@"%.1f MB", (double)bytes / 1048576.0];
    return [NSString stringWithFormat:@"%.2f GB", (double)bytes / 1073741824.0];
}
static NSArray<NSString *> *DY778CachePluginNames(void) {
    NSMutableSet *names = [NSMutableSet set];
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *raw = _dyld_get_image_name(i); if (!raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw];
        BOOL bundled = [path hasPrefix:[NSBundle.mainBundle.bundlePath stringByAppendingString:@"/"]] &&
            [path.pathExtension.lowercaseString isEqual:@"dylib"];
        if (![path containsString:@"/DynamicLibraries/"] && ![path containsString:@"/TweakInject/"] &&
            ![path containsString:@"/tweaksupport/"] && !bundled) continue;
        NSString *name = path.lastPathComponent.stringByDeletingPathExtension.lowercaseString;
        if (name.length >= 3) [names addObject:name];
        if ([name hasPrefix:@"lib"] && name.length > 5) [names addObject:[name substringFromIndex:3]];
    }
    NSString *preferences = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:preferences error:nil]) {
        NSString *name = file.stringByDeletingPathExtension.lowercaseString;
        if (![file.pathExtension.lowercaseString isEqual:@"plist"] || [name hasPrefix:@"com.apple."] ||
            [name hasPrefix:@"com.ss."] || [name hasPrefix:@"com.bytedance."]) continue;
        if (name.length >= 3) [names addObject:name];
    }
    return names.allObjects;
}
static BOOL DY778CacheIsPluginConfiguration(NSString *relative, NSArray<NSString *> *names) {
    const char *plugins[names.count ?: 1];
    for (NSUInteger index = 0; index < names.count; index++) plugins[index] = names[index].UTF8String;
    return DY778CachePluginConfiguration(relative.UTF8String, plugins, names.count);
}
static NSString *DY778CacheIdentity(struct stat st) { return [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)st.st_dev, (unsigned long long)st.st_ino]; }
static NSArray<DY778CacheRoot *> *DY778CacheRoots(BOOL *incomplete) {
    NSString *home = NSHomeDirectory().stringByResolvingSymlinksInPath;
    int container = open(home.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (container < 0) { *incomplete = YES; return @[]; }
    NSMutableArray *roots = [NSMutableArray array];
    for (NSString *relative in @[@"Library/Caches", @"tmp", @"Library/Application Support/gurd_cache", @"Library/BDByteCast", @"Library/kitelog"]) {
        int scope = DY778CacheRootScope(relative.UTF8String); if (!scope) continue;
        char leaf[256]; NSString *anchor = [relative stringByAppendingPathComponent:@".dy778-check"];
        int descriptor = DY778CacheOpenParent(container, anchor.fileSystemRepresentation, leaf);
        if (descriptor < 0) { if (errno != ENOENT) *incomplete = YES; continue; }
        DY778CacheRoot *root = [DY778CacheRoot new]; root.descriptor = descriptor; root.scope = scope;
        root.path = [home stringByAppendingPathComponent:relative];
        [roots addObject:root];
    }
    close(container); return roots;
}
static BOOL DY778CacheOpenAllowed(DY778CacheJob *job) {
    return job.activationGeneration == atomic_load_explicit(&DY778CacheOpenGeneration, memory_order_relaxed) && DY778CacheEventEnabled(job.activationEvent, atomic_load_explicit(&DY778CacheOnLaunch, memory_order_relaxed), atomic_load_explicit(&DY778CacheOnReturn, memory_order_relaxed)) && atomic_load_explicit(&DY778CacheForeground, memory_order_relaxed);
}
static BOOL DY778CacheJobCanRemove(DY778CacheJob *job) {
    return job.remove && (job.manual ? !atomic_load_explicit(&DY778CacheCancelled, memory_order_acquire) : DY778CacheOpenAllowed(job) || (job.byRules && atomic_load_explicit(&DY778CacheEnabled, memory_order_relaxed)));
}
static BOOL DY778CacheFileAllowed(DY778CacheFile *file, DY778CacheJob *job) {
    return DY778CacheJobCanRemove(job) && DY778CacheDeletionAllowed(job.manual || DY778CacheOpenAllowed(job), atomic_load_explicit(&DY778CacheEnabled, memory_order_relaxed),
        (job.manual && atomic_load_explicit(&DY778CacheCancelled, memory_order_acquire)), file.root.scope, job.managedBytes,
        DY778CacheByteLimit(atomic_load_explicit(&DY778CacheMaxMB, memory_order_relaxed)), file.newestWrite,
        NSDate.date.timeIntervalSince1970, atomic_load_explicit(&DY778CacheMaxAge, memory_order_relaxed));
}
static BOOL DY778CacheRemoveFile(DY778CacheFile *file, DY778CacheJob *job, uint64_t *bytes) {
    if (DY778CacheIsPluginConfiguration(file.relative, job.pluginNames) || !DY778CacheFileAllowed(file, job)) return NO;
    struct stat expected = file.snapshot;
    if (job.manual || DY778CacheOpenAllowed(job))
        return DY778CacheUnlinkCurrent(file.root.descriptor, file.relative.fileSystemRepresentation, &expected, bytes);
    return DY778CacheUnlinkVerified(file.root.descriptor, file.relative.fileSystemRepresentation, &expected);
}
static NSDictionary *DY778CacheSnapshot(DY778CacheJob *job, NSString *phase) {
    NSMutableArray *categories = [NSMutableArray array];
    NSArray *names = @[@"", @"应用缓存", @"临时文件", @"页面资源", @"投屏缓存", @"诊断日志"];
    NSArray *keys = @[@"", @"media", @"temporary", @"resources", @"cast", @"logs"];
    for (DY778CacheRoot *root in job.roots) [categories addObject:@{@"key": keys[root.scope], @"title": names[root.scope], @"bytes": @(root.bytes), @"reclaimableBytes": @(root.reclaimable)}];
    BOOL busy = ![phase isEqualToString:@"idle"];
    NSString *status = @"用量已更新，清理范围内仅保留插件配置";
    if ([phase isEqualToString:@"scanning"]) status = [NSString stringWithFormat:@"正在统计 · 已检查 %lu 个文件", (unsigned long)job.count];
    else if ([phase isEqualToString:@"cleaning"]) status = [NSString stringWithFormat:@"正在清理 · 已释放 %@", DY778CacheFormatBytes(job.deletedBytes)];
    else if (job.cancelled) status = job.scanFinished ? @"本次清理已停止，已释放的空间会保留" : @"已停止，当前仅为已统计用量，可下拉刷新";
    else if (!job.roots.count) status = @"暂时无法读取缓存目录，可稍后刷新";
    else if (job.incomplete) status = @"部分目录不可读取，以下仅为已统计用量";
    else if (job.remove && job.skipped) status = [NSString stringWithFormat:@"已清理 %@ · %lu 个文件暂未删除", DY778CacheFormatBytes(job.deletedBytes), (unsigned long)job.skipped];
    else if (job.manual && job.overflow && job.reclaimableBytes) status = [NSString stringWithFormat:@"已释放 %@，仍有缓存未清理", DY778CacheFormatBytes(job.deletedBytes)];
    else if (job.remove) status = job.deletedCount ? [NSString stringWithFormat:@"已释放 %@ · %lu 个文件", DY778CacheFormatBytes(job.deletedBytes), (unsigned long)job.deletedCount] : @"没有待清理缓存，插件配置已保留";
    NSMutableDictionary *result = [@{@"bytes": @(job.bytes), @"managedBytes": @(job.managedBytes), @"count": @(job.count),
        @"reclaimableBytes": @(job.reclaimableBytes), @"protectedBytes": @(job.bytes >= job.reclaimableBytes ? job.bytes - job.reclaimableBytes : 0),
        @"rootCount": @(job.roots.count), @"categories": categories, @"deletedBytes": @(job.deletedBytes), @"deletedCount": @(job.deletedCount),
        @"skippedActive": @(job.skipped), @"partial": @(job.incomplete || !job.scanFinished || job.skipped > 0), @"busy": @(busy), @"manual": @(job.manual),
        @"cancelled": @(job.cancelled), @"phase": phase, @"status": status, @"scannedCount": @(job.count), @"scanDate": NSDate.date} mutableCopy];
    if (DY778LastCacheResult) result[@"lastCleanup"] = DY778LastCacheResult;
    if ([phase isEqualToString:@"scanning"] && DY778LastCompleteCacheStatistics) {
        for (NSString *key in @[@"bytes", @"managedBytes", @"reclaimableBytes", @"protectedBytes", @"categories", @"scanDate"])
            if (!job.deletedCount && DY778LastCompleteCacheStatistics[key]) result[key] = DY778LastCompleteCacheStatistics[key];
    }
    return result;
}
static void DY778CachePublish(DY778CacheJob *job, NSString *phase, BOOL force) {
    if (!force && CFAbsoluteTimeGetCurrent() - job.published < .35) return;
    job.published = CFAbsoluteTimeGetCurrent();
    NSDictionary *snapshot = DY778CacheSnapshot(job, phase); DY778LastCacheStatistics = snapshot;
    dispatch_async(dispatch_get_main_queue(), ^{
        DY778VisibleCacheStatistics = snapshot;
        [NSNotificationCenter.defaultCenter postNotificationName:DY778CacheStatisticsChangedNotification object:nil userInfo:snapshot];
    });
}
static void DY778CacheFinish(DY778CacheJob *job) {
    DY778CacheWalkClose(&job->walker);
    if (DY778CacheRecordCleanup(job.remove, job.manual || job.activationEvent != DY778CacheEventNone,
        job.deletedCount, job.incomplete || job.skipped || job.cancelled)) {
        DY778LastCacheResult = @{@"date": NSDate.date, @"deletedBytes": @(job.deletedBytes),
            @"deletedCount": @(job.deletedCount), @"partial": @(job.incomplete || job.skipped > 0 || !job.scanFinished),
            @"cancelled": @(job.cancelled), @"skipped": @(job.skipped)};
        [DY778Preferences() setObject:DY778LastCacheResult forKey:@"cache.lastCleanup"];
    }
    DY778CachePublish(job, @"idle", YES);
    NSDictionary *statistics = DY778LastCacheStatistics;
    if (job.scanFinished) DY778LastCompleteCacheStatistics = statistics;
    DY778CacheLastScan = job.scanFinished ? CFAbsoluteTimeGetCurrent() : 0;
    NSArray *callbacks = job.completions.copy; DY778ActiveCacheJob = nil;
    atomic_store_explicit(&DY778CachePending, false, memory_order_release);
    atomic_store_explicit(&DY778CacheManualPending, false, memory_order_release);
    dispatch_async(dispatch_get_main_queue(), ^{ for (void (^completion)(NSDictionary *) in callbacks) completion(statistics); });
}
static void DY778CacheStep(DY778CacheJob *job);
static void DY778CacheDeleteStep(DY778CacheJob *job) {
    @autoreleasepool {
        CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + .04; NSUInteger examined = 0;
        while (job.deleteIndex < job.oldest.count && examined++ < 256 && CFAbsoluteTimeGetCurrent() < deadline) {
            if (!DY778CacheJobCanRemove(job)) { job.cancelled = job.manual; DY778CacheFinish(job); return; }
            DY778CacheFile *file = job.oldest[job.deleteIndex++];
            if (!DY778CacheFileAllowed(file, job)) continue;
            uint64_t size = (uint64_t)file.snapshot.st_size;
            job.reclaimableBytes -= MIN(job.reclaimableBytes, size); file.root.reclaimable -= MIN(file.root.reclaimable, size);
            if (!DY778CacheRemoveFile(file, job, &size)) {
                [job.skippedFiles addObject:DY778CacheIdentity(file.snapshot)]; job.skipped++; job.passSkipped++; continue;
            }
            job.bytes -= MIN(job.bytes, size); file.root.bytes -= MIN(file.root.bytes, size);
            job.managedBytes -= MIN(job.managedBytes, size); job.count--;
            job.deletedBytes = DY778CacheAddBytes(job.deletedBytes, size); job.deletedCount++; job.passDeleted++;
        }
        DY778CachePublish(job, @"cleaning", NO);
        if (job.deleteIndex >= job.oldest.count) {
            if (job.overflow && (job.passDeleted || job.passSkipped) && DY778CacheJobCanRemove(job)) {
                job.rootIndex = 0; job.bytes = 0; job.count = 0; job.managedBytes = 0; job.reclaimableBytes = 0;
                job.passDeleted = 0; job.passSkipped = 0; job.deleteIndex = 0; job.overflow = NO; job.scanFinished = NO; [job.oldest removeAllObjects];
                for (DY778CacheRoot *root in job.roots) { root.bytes = 0; root.reclaimable = 0; }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), DY778CacheQueue, ^{ DY778CacheStep(job); }); return;
            }
            job.verifying = YES; job.rootIndex = 0; job.bytes = 0; job.count = 0;
            job.managedBytes = 0; job.reclaimableBytes = 0; job.scanFinished = NO;
            [job.oldest removeAllObjects];
            for (DY778CacheRoot *root in job.roots) { root.bytes = 0; root.reclaimable = 0; }
            dispatch_async(DY778CacheQueue, ^{ DY778CacheStep(job); }); return;
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC), DY778CacheQueue, ^{ DY778CacheDeleteStep(job); });
}
static void DY778CacheStep(DY778CacheJob *job) {
    @autoreleasepool {
        if (job.manual && atomic_load_explicit(&DY778CacheCancelled, memory_order_acquire)) { job.cancelled = YES; DY778CacheFinish(job); return; }
        CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + (job.remove ? .04 : .06); NSUInteger entries = 0;
        while (job.rootIndex < job.roots.count && entries++ < (job.remove ? 1000 : 12000) && CFAbsoluteTimeGetCurrent() < deadline) {
            DY778CacheRoot *root = job.roots[job.rootIndex];
            if (!job->walker.frames && !DY778CacheWalkStart(&job->walker, root.descriptor)) { job.incomplete = YES; job.rootIndex++; continue; }
            job->walker.pruneEmpty = job.verifying && DY778CacheJobCanRemove(job);
            char path[4096]; struct stat st; int parent = -1;
            int result = DY778CacheWalkNext(&job->walker, NULL, NULL, path, &st, &parent);
            if (!result) { job.incomplete |= job->walker.incomplete; DY778CacheWalkClose(&job->walker); job.rootIndex++; continue; }
            if (result != 1 || st.st_size < 0) continue;
            uint64_t size = (uint64_t)st.st_size; job.bytes = DY778CacheAddBytes(job.bytes, size); root.bytes = DY778CacheAddBytes(root.bytes, size); job.count++;
            if (!job.remove || job.needsSafetyScan) continue;
            NSString *relative = [NSString stringWithUTF8String:path]; if (!relative || DY778CacheIsPluginConfiguration(relative, job.pluginNames)) continue;
            int kind = DY778CacheFileKind(root.scope, path); if (!kind) continue;
            if (!job.verifying && [job.skippedFiles containsObject:DY778CacheIdentity(st)]) continue;
            job.managedBytes = DY778CacheAddBytes(job.managedBytes, size);
            DY778CacheFile *file = [DY778CacheFile new]; file.root = root; file.relative = relative; file.snapshot = st; file.kind = kind;
            file.newestWrite = MAX((double)st.st_mtime, (double)st.st_ctime);
            if (!DY778CacheIdle(root.scope, file.newestWrite, NSDate.date.timeIntervalSince1970)) continue;
            job.reclaimableBytes = DY778CacheAddBytes(job.reclaimableBytes, size); root.reclaimable = DY778CacheAddBytes(root.reclaimable, size);
            if (job.verifying) continue;
            if (job.manual || DY778CacheOpenAllowed(job)) {
                uint64_t deleted = size;
                if (DY778CacheRemoveFile(file, job, &deleted)) {
                    job.bytes -= MIN(job.bytes, size); root.bytes -= MIN(root.bytes, size);
                    job.managedBytes -= MIN(job.managedBytes, size); job.count--;
                    job.reclaimableBytes -= MIN(job.reclaimableBytes, size); root.reclaimable -= MIN(root.reclaimable, size);
                    job.deletedBytes = DY778CacheAddBytes(job.deletedBytes, deleted); job.deletedCount++;
                } else {
                    job.skipped++; [job.skippedFiles addObject:DY778CacheIdentity(st)];
                }
                continue;
            }
            NSUInteger position = [job.oldest indexOfObject:file inSortedRange:NSMakeRange(0, job.oldest.count) options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(DY778CacheFile *a, DY778CacheFile *b) {
                if (a.newestWrite != b.newestWrite) return a.newestWrite < b.newestWrite ? NSOrderedAscending : NSOrderedDescending;
                return [a.relative compare:b.relative];
            }];
            if (position < 4096) [job.oldest insertObject:file atIndex:position]; else job.overflow = YES;
            if (job.oldest.count > 4096) { [job.oldest removeLastObject]; job.overflow = YES; }
        }
        if (job.rootIndex >= job.roots.count) {
            job.scanFinished = YES;
            if (job.needsSafetyScan) {
                DY778CachePublish(job, @"scanning", YES);
                BOOL incomplete = NO; job.roots = DY778CacheRoots(&incomplete);
                job.incomplete = incomplete; job.needsSafetyScan = NO;
                job.rootIndex = 0; job.bytes = 0; job.count = 0; job.managedBytes = 0; job.reclaimableBytes = 0;
                job.scanFinished = NO;
                dispatch_async(DY778CacheQueue, ^{ DY778CacheStep(job); }); return;
            }
            if (!job.remove || job.verifying) { DY778CacheFinish(job); return; }
            DY778CachePublish(job, @"cleaning", YES); DY778CacheDeleteStep(job); return;
        }
        DY778CachePublish(job, job.deletedCount ? @"cleaning" : @"scanning", NO);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (job.remove ? 10 : 1) * NSEC_PER_MSEC), DY778CacheQueue, ^{ DY778CacheStep(job); });
}
static void DY778CacheStart(int mode, NSUInteger generation, NSArray<NSString *> *plugins, void (^completion)(NSDictionary *)) {
    if (DY778ActiveCacheJob) {
        if (plugins.count) {
            NSMutableSet *names = [NSMutableSet setWithArray:DY778ActiveCacheJob.pluginNames ?: @[]];
            [names addObjectsFromArray:plugins]; DY778ActiveCacheJob.pluginNames = names.allObjects;
        }
        if (mode > 0 && !DY778ActiveCacheJob.remove) { DY778ActiveCacheJob.needsSafetyScan = YES; }
        DY778ActiveCacheJob.remove |= mode > 0; DY778ActiveCacheJob.manual |= mode == 2; DY778ActiveCacheJob.byRules |= mode == 1; if (mode >= DY778CacheEventLaunch) { DY778ActiveCacheJob.activationEvent = mode; DY778ActiveCacheJob.activationGeneration = generation; }
        if (completion) [DY778ActiveCacheJob.completions addObject:[completion copy]];
        DY778CachePublish(DY778ActiveCacheJob, DY778ActiveCacheJob.scanFinished ? @"cleaning" : @"scanning", YES); return;
    }
    DY778CacheJob *job = [DY778CacheJob new]; BOOL incomplete = NO; job.roots = DY778CacheRoots(&incomplete);
    job.incomplete = incomplete; job.remove = mode > 0; job.manual = mode == 2; job.byRules = mode == 1; job.activationEvent = mode >= DY778CacheEventLaunch ? mode : DY778CacheEventNone; job.activationGeneration = generation;
    if (completion) [job.completions addObject:[completion copy]];
    job.pluginNames = plugins;
    DY778ActiveCacheJob = job; DY778CachePublish(job, @"scanning", YES); DY778CacheStep(job);
}
static void DY778CacheRequest(int mode, BOOL refresh, void (^completion)(NSDictionary *)) {
    NSUInteger generation = atomic_load_explicit(&DY778CacheOpenGeneration, memory_order_relaxed);
    dispatch_async(dispatch_get_main_queue(), ^{
        DY778InstallCacheCleanerHooks();
        NSArray *plugins = mode ? DY778CachePluginNames() : @[];
        dispatch_async(DY778CacheQueue, ^{
            if (!mode && !refresh && !DY778ActiveCacheJob && DY778LastCacheStatistics && CFAbsoluteTimeGetCurrent() - DY778CacheLastScan < 30) {
                NSDictionary *snapshot = DY778LastCacheStatistics;
                if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(snapshot); });
                return;
            }
            DY778CacheStart(mode, generation, plugins, completion);
        });
    });
}
void DY778RunCacheMaintenance(void) {
    if (!atomic_load_explicit(&DY778CacheEnabled, memory_order_relaxed) ||
        (atomic_load_explicit(&DY778CacheMaxMB, memory_order_relaxed) <= 0 && atomic_load_explicit(&DY778CacheMaxAge, memory_order_relaxed) <= 0)) return;
    if (atomic_exchange_explicit(&DY778CachePending, true, memory_order_acq_rel)) return;
    DY778CacheRequest(1, YES, nil);
}
void DY778CacheStatistics(void (^completion)(NSDictionary *)) { if (completion) DY778CacheRequest(0, NO, completion); }
void DY778RefreshCacheStatistics(void (^completion)(NSDictionary *)) { if (completion) DY778CacheRequest(0, YES, completion); }
void DY778CleanHostCache(void (^completion)(NSDictionary *)) {
    if (!atomic_exchange_explicit(&DY778CacheManualPending, true, memory_order_acq_rel)) atomic_store_explicit(&DY778CacheCancelled, false, memory_order_release);
    DY778CacheRequest(2, YES, completion);
}
void DY778CancelHostCacheCleanup(void) { atomic_store_explicit(&DY778CacheCancelled, true, memory_order_release); }
static void DY778CacheOpened(void) {
    atomic_store_explicit(&DY778CacheForeground, true, memory_order_relaxed);
    int event = DY778CacheActivationEvent(&DY778CacheLifecycleState); if (!event) return;
    DY778CacheCurrentEvent = event;
    NSUInteger generation = ++DY778CacheOpenGeneration;
    NSString *key = event == DY778CacheEventLaunch ? @"cache.onLaunch" : @"cache.onReturn";
    if (!DY778Bool(key)) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation != DY778CacheOpenGeneration || !DY778Bool(key) || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        DY778ShowToast(@"cache", @"正在自动清理缓存", YES, NO);
        DY778CacheRequest(event, YES, ^(NSDictionary *result) {
            if (generation != DY778CacheOpenGeneration || !DY778Bool(key) || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            NSString *message = [NSString stringWithFormat:@"自动清理完成 · 本次已清理 %@", DY778CacheFormatBytes([result[@"deletedBytes"] unsignedLongLongValue])];
            if (![result[@"deletedCount"] unsignedLongLongValue]) message = @"缓存已检查 · 暂无需要清理的内容";
            if ([result[@"partial"] boolValue]) message = [NSString stringWithFormat:@"本次已清理 %@ · 部分文件已跳过", DY778CacheFormatBytes([result[@"deletedBytes"] unsignedLongLongValue])];
            DY778ShowToast(@"cache", message, NO, YES);
        });
    });
}
static void DY778CacheReload(void) {
    double mb = DY778Number(@"cache.maxMB"), age = DY778Number(@"cache.maxAgeHours");
    atomic_store_explicit(&DY778CacheMaxMB, isfinite(mb) && mb > 0 ? mb : 0, memory_order_relaxed);
    atomic_store_explicit(&DY778CacheMaxAge, isfinite(age) && age > 0 ? age : 0, memory_order_relaxed);
    atomic_store_explicit(&DY778CacheEnabled, DY778Bool(@"cache.enabled"), memory_order_relaxed);
    atomic_store_explicit(&DY778CacheOnLaunch, DY778Bool(@"cache.onLaunch"), memory_order_relaxed);
    atomic_store_explicit(&DY778CacheOnReturn, DY778Bool(@"cache.onReturn"), memory_order_relaxed);
    if (DY778CacheCurrentEvent && !DY778CacheEventEnabled(DY778CacheCurrentEvent, DY778Bool(@"cache.onLaunch"), DY778Bool(@"cache.onReturn"))) { DY778CacheOpenGeneration++; DY778DismissToast(@"cache"); }
    DY778RunCacheMaintenance();
}
void DY778InstallCacheCleanerHooks(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallCacheCleanerHooks(); }); return; }
    static dispatch_once_t once; dispatch_once(&once, ^{
        DY778CacheQueue = dispatch_queue_create("com.dy778.cache-maintenance", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        NSDictionary *stored = [DY778Preferences() dictionaryForKey:@"cache.lastCleanup"];
        if ([stored[@"date"] isKindOfClass:NSDate.class] && [stored[@"deletedBytes"] isKindOfClass:NSNumber.class] &&
            [stored[@"deletedCount"] isKindOfClass:NSNumber.class]) DY778LastCacheResult = stored;
        DY778CacheReload();
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) DY778CacheOpened();
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSString *key = note.userInfo[@"key"]; if (!key.length || [key hasPrefix:@"cache."]) DY778CacheReload();
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { DY778CacheLifecycleState.backgrounded = 1; DY778CacheOpenGeneration++; atomic_store_explicit(&DY778CacheForeground, false, memory_order_relaxed); DY778DismissToast(@"cache"); DY778RunCacheMaintenance(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { DY778CacheOpened(); dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DY778RunCacheMaintenance(); }); }];
        DY778CacheTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(DY778CacheTimer, dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_SEC), 300 * NSEC_PER_SEC, 30 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(DY778CacheTimer, ^{ DY778RunCacheMaintenance(); }); dispatch_resume(DY778CacheTimer);
    });
}
