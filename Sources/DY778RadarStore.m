#import "DY778RadarStore.h"
#import "DY778RadarPolicy.h"
#import <TargetConditionals.h>
@interface DY778RadarStore ()
@property(nonatomic, copy) NSString *accountID;
@property(nonatomic, copy) NSString *storageError;
@property(nonatomic, strong) NSURL *directory;
@property(nonatomic, strong) NSMutableArray<NSMutableDictionary *> *people;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *history;
@property(nonatomic, strong) NSMutableDictionary *preferences;
@property(nonatomic, strong) dispatch_queue_t writer;
@property(nonatomic) NSUInteger saveGeneration;
@property(nonatomic) BOOL writeScheduled;
@property(nonatomic) BOOL dirty;
@property(nonatomic) NSTimeInterval writeDue;
@end

static BOOL DY778RadarStringArray(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSArray.class] || [value count] > limit) return NO;
    for (id item in value) if (![item isKindOfClass:NSString.class] || [item length] > 80) return NO;
    return YES;
}
static BOOL DY778RadarOptionalFields(id object, NSArray *strings, NSArray *numbers) {
    for (NSString *key in strings) if (object[key] && (![object[key] isKindOfClass:NSString.class] || [object[key] length] > 8192)) return NO;
    for (NSString *key in numbers) if (object[key] && ![object[key] isKindOfClass:NSNumber.class]) return NO;
    return YES;
}
static BOOL DY778RadarValidSignature(id value) {
    return [value isKindOfClass:NSString.class] && [value length] <= DY778RadarSignatureLimit;
}
static BOOL DY778RadarValidTarget(id value) {
    if (![value isKindOfClass:NSDictionary.class] || !DY778RadarProfile(value)) return NO;
    if (!DY778RadarOptionalFields(value, @[@"uid", @"secUID", @"handle", @"name", @"remark", @"note", @"avatar", @"status", @"likesStatus"],
        @[@"paused", @"checkedAt", @"likesCheckedAt", @"lastAttempt", @"likesVisible", @"signatureAvailable", @"signatureCheckedAt", @"signatureChangedAt"])) return NO;
    for (NSString *key in @[@"signature", @"signatureBaseline"])
        if (value[key] && !DY778RadarValidSignature(value[key])) return NO;
    for (NSString *key in @[@"counts", @"countsBaseline"]) {
        id counts = value[key]; if (counts && ![counts isKindOfClass:NSDictionary.class]) return NO;
        for (id number in [counts allValues]) if (!DY778RadarCount(number)) return NO;
    }
    if (value[@"hiddenMetrics"]) {
        if (!DY778RadarStringArray(value[@"hiddenMetrics"], 4)) return NO;
        for (NSString *key in value[@"hiddenMetrics"]) if (![@[@"received", @"following", @"followers", @"likes"] containsObject:key]) return NO;
    }
    id recent = value[@"lastChanges"];
    if (recent) {
        if (![recent isKindOfClass:NSArray.class] || [recent count] > 4) return NO;
        for (id c in recent) if (![c isKindOfClass:NSDictionary.class] || ![c[@"key"] isKindOfClass:NSString.class] ||
            !DY778RadarCount(c[@"before"]) || !DY778RadarCount(c[@"after"]) || ![c[@"delta"] isKindOfClass:NSNumber.class] ||
            (c[@"timestamp"] && ![c[@"timestamp"] isKindOfClass:NSNumber.class])) return NO;
    }
    id baseline = value[@"likesBaseline"];
    if (baseline) {
        if (![baseline isKindOfClass:NSDictionary.class]) return NO;
        if (!DY778RadarOptionalFields(baseline, @[], @[@"complete", @"valid"])) return NO;
        for (NSString *key in @[@"head", @"seen"]) if (baseline[key] && !DY778RadarStringArray(baseline[key], 300)) return NO;
    }
    return YES;
}
static BOOL DY778RadarValidRecord(id value) {
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"id"] isKindOfClass:NSString.class] ||
        ![value[@"timestamp"] isKindOfClass:NSNumber.class] || !DY778RadarValidTarget(value[@"person"])) return NO;
    if ([value[@"kind"] isEqual:@"signature"])
        return DY778RadarValidSignature(value[@"before"]) && DY778RadarValidSignature(value[@"after"]);
    if ([value[@"kind"] isEqual:@"like"]) {
        id video = value[@"video"];
        return [video isKindOfClass:NSDictionary.class] && [video[@"id"] isKindOfClass:NSString.class] &&
            DY778RadarOptionalFields(video, @[@"id", @"text", @"author", @"authorAvatar", @"authorHandle", @"authorUID", @"authorSecUID", @"url", @"cover"], @[@"type", @"publishedAt"]) &&
            DY778RadarOptionalFields(value, @[], @[@"uncertain"]);
    }
    if (![value[@"kind"] isEqual:@"counts"] || ![value[@"changes"] isKindOfClass:NSArray.class] || [value[@"changes"] count] > 4) return NO;
    for (id change in value[@"changes"]) if (![change isKindOfClass:NSDictionary.class] || ![change[@"key"] isKindOfClass:NSString.class] ||
        !DY778RadarCount(change[@"before"]) || !DY778RadarCount(change[@"after"]) || ![change[@"delta"] isKindOfClass:NSNumber.class]) return NO;
    return YES;
}

@implementation DY778RadarStore
+ (instancetype)shared {
    static DY778RadarStore *store; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        store = [[self alloc] initWithDirectory:[base URLByAppendingPathComponent:@"DY778Radar" isDirectory:YES]];
    });
    return store;
}
- (instancetype)initWithDirectory:(NSURL *)directory {
    if ((self = [super init])) {
        _directory = directory; _accountID = @""; _storageError = @"";
        _writer = dispatch_queue_create("com.dy778.radar.storage", DISPATCH_QUEUE_SERIAL);
        [self resetMemory];
    }
    return self;
}
- (void)resetMemory {
    self.people = [NSMutableArray array]; self.history = [NSMutableArray array]; self.dirty = NO;
    self.preferences = [@{@"enabled": @NO, @"alerts": @YES, @"interval": @300, @"retentionDays": @7, @"recordLimit": @500} mutableCopy];
}
- (NSURL *)fileURL {
    return [self.directory URLByAppendingPathComponent:[NSString stringWithFormat:@"account-%@.json", self.accountID]];
}
- (void)activateAccount:(NSString *)accountID {
    NSAssert(NSThread.isMainThread, @"Store is confined to the main thread");
    if ([self.accountID isEqual:accountID]) return;
    if (accountID.length && !DY778RadarIdentifier(accountID)) accountID = @"";
    [self flush];
    // 加载另一个账号前，先完成挂起的写入。
    dispatch_sync(self.writer, ^{});
    self.accountID = accountID; self.storageError = @""; [self resetMemory];
    if (accountID.length) {
        NSURL *file = self.fileURL;
        NSNumber *size; [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        NSData *data = size.unsignedLongLongValue <= 16 * 1024 * 1024 ? [NSData dataWithContentsOfURL:file] : nil;
        id object = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:file.path];
        BOOL valid = [object isKindOfClass:NSDictionary.class] && [DY778RadarCount(object[@"schema"]) integerValue] == 1 &&
            [object[@"account"] isEqual:accountID] && [object[@"targets"] isKindOfClass:NSArray.class] &&
            [object[@"records"] isKindOfClass:NSArray.class] && [object[@"options"] isKindOfClass:NSDictionary.class];
        if (valid) {
            if ([object[@"targets"] count] > 20 || [object[@"records"] count] > 1000) valid = NO;
            for (id target in object[@"targets"]) {
                if (!DY778RadarValidTarget(target)) { valid = NO; break; }
                [self.people addObject:[target mutableCopy]];
            }
            for (id record in object[@"records"]) {
                if (!DY778RadarValidRecord(record)) { valid = NO; break; }
                [self.history addObject:record];
            }
            for (NSString *key in self.preferences.allKeys) {
                if ([object[@"options"][key] isKindOfClass:NSNumber.class]) self.preferences[key] = object[@"options"][key];
            }
        }
        if (exists && !valid) {
            [self resetMemory];
            NSURL *backup = [file URLByAppendingPathExtension:[NSString stringWithFormat:@"damaged-%.0f", NSDate.date.timeIntervalSince1970]];
            NSError *error;
            if (![NSFileManager.defaultManager moveItemAtURL:file toURL:backup error:&error]) {
                self.storageError = @"记录文件无法读取或备份，已停止写入；请检查存储空间。";
            } else self.storageError = @"原记录文件损坏，已保留备份并建立空记录。";
            self.preferences[@"enabled"] = @NO;
        }
        self.preferences[@"interval"] = @(DY778RadarInterval([self.preferences[@"interval"] doubleValue]));
        if (![@[@0, @1, @7, @30] containsObject:self.preferences[@"retentionDays"]]) self.preferences[@"retentionDays"] = @7;
        if (![@[@100, @500, @1000] containsObject:self.preferences[@"recordLimit"]]) self.preferences[@"recordLimit"] = @500;
        [self prune];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:DY778RadarStoreChanged object:self];
}
- (NSArray *)targets { return [[NSArray alloc] initWithArray:self.people copyItems:YES]; }
- (NSArray *)records { return [self.history copy]; }
- (NSDictionary *)options { return [self.preferences copy]; }
- (NSDictionary *)target:(NSString *)uid {
    for (NSDictionary *target in self.people) if ([target[@"uid"] isEqual:uid]) return [target copy];
    return nil;
}
- (void)setOption:(NSString *)key value:(id)value {
    if (!self.preferences[key] || ![value isKindOfClass:NSNumber.class]) return;
    if ([key isEqual:@"interval"]) value = @(DY778RadarInterval([value doubleValue]));
    if ([key isEqual:@"retentionDays"] && ![@[@0, @1, @7, @30] containsObject:value]) return;
    if ([key isEqual:@"recordLimit"] && ![@[@100, @500, @1000] containsObject:value]) return;
    self.preferences[key] = value; [self prune]; [self save];
}
- (BOOL)addProfiles:(NSArray<NSDictionary *> *)profiles error:(NSError **)error {
    if (!self.accountID.length) { if (error) *error = DY778RadarError(401, @"请先登录抖音，再添加关注对象。"); return NO; }
    NSMutableArray *newPeople = [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet setWithArray:[self.people valueForKey:@"uid"]];
    for (NSDictionary *profile in profiles) {
        NSString *uid = profile[@"uid"];
        if (!uid.length || [ids containsObject:uid]) continue;
        [ids addObject:uid];
        NSMutableDictionary *person = [profile mutableCopy];
        person[@"paused"] = @NO; person[@"status"] = @"等待首次检测";
        [newPeople addObject:person];
    }
    if (self.people.count + newPeople.count > 20) { if (error) *error = DY778RadarError(20, @"最多添加 20 人，请减少本次选择，或先移除部分对象。"); return NO; }
    [self.people addObjectsFromArray:newPeople]; [self save]; return YES;
}
- (void)updateTarget:(NSString *)uid values:(NSDictionary *)values {
    for (NSMutableDictionary *target in self.people) if ([target[@"uid"] isEqual:uid]) {
        BOOL changed = NO;
        for (NSString *key in values) if (![target[key] isEqual:values[key]]) { changed = YES; break; }
        if (changed) { [target addEntriesFromDictionary:values]; [self persistAfter:values[@"paused"] ? 0.5 : 30]; }
        return;
    }
}
- (void)removeTarget:(NSString *)uid {
    NSIndexSet *indices = [self.people indexesOfObjectsPassingTest:^BOOL(NSDictionary *target, NSUInteger index, BOOL *stop) { return [target[@"uid"] isEqual:uid]; }];
    [self.people removeObjectsAtIndexes:indices]; [self save];
}
- (void)resetBaseline:(NSString *)uid {
    for (NSMutableDictionary *target in self.people) if ([target[@"uid"] isEqual:uid]) {
        [target removeObjectsForKeys:@[@"countsBaseline", @"likesBaseline", @"signatureBaseline", @"checkedAt", @"likesCheckedAt", @"lastChanges", @"signatureChangedAt"]];
        target[@"status"] = @"等待重新建立基线"; [self save]; return;
    }
}
- (NSDictionary *)recordFor:(NSDictionary *)person kind:(NSString *)kind {
    NSMutableDictionary *identity = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"uid", @"name", @"remark", @"note", @"handle", @"avatar"]) identity[key] = DY778RadarString(person[key]);
    return @{@"id": NSUUID.UUID.UUIDString, @"timestamp": @(NSDate.date.timeIntervalSince1970), @"kind": kind, @"person": identity};
}
- (void)addRecords:(NSArray *)records {
    for (NSDictionary *record in records.reverseObjectEnumerator) [self.history insertObject:record atIndex:0];
    [self prune];
}
- (NSArray *)applyProfile:(NSDictionary *)profile forUID:(NSString *)uid {
    NSDictionary *target = [self target:uid];
    if (!target || ![profile[@"uid"] isEqual:uid]) return @[];
    NSDictionary *counts = profile[@"counts"] ?: @{};
    NSArray *changes = DY778RadarChanges(target[@"countsBaseline"] ?: @{}, counts);
    NSMutableDictionary *identity = [target mutableCopy]; [identity addEntriesFromDictionary:profile];
    if (!DY778RadarString(profile[@"avatar"]).length) identity[@"avatar"] = target[@"avatar"] ?: @"";
    NSMutableArray *records = [NSMutableArray array];
    if (changes.count) {
        NSMutableDictionary *record = [[self recordFor:identity kind:@"counts"] mutableCopy];
        record[@"changes"] = changes; [records addObject:record];
    }
    NSString *signature = DY778RadarValidSignature(profile[@"signature"]) ? profile[@"signature"] : nil;
    NSString *previousSignature = target[@"signatureBaseline"];
    BOOL signatureChanged = signature && previousSignature && ![signature isEqualToString:previousSignature];
    if (signatureChanged) {
        NSMutableDictionary *record = [[self recordFor:identity kind:@"signature"] mutableCopy];
        record[@"before"] = previousSignature; record[@"after"] = signature;
        [records addObject:record];
    }
    [self addRecords:records];
    NSMutableDictionary *values = [profile mutableCopy];
    if (!DY778RadarString(profile[@"avatar"]).length) [values removeObjectForKey:@"avatar"];
    if (!signature) [values removeObjectForKey:@"signature"];
    // 跨部分响应保留基线；当前计数单独展示。
    NSMutableDictionary *baseline = [target[@"countsBaseline"] mutableCopy] ?: [NSMutableDictionary dictionary];
    [baseline addEntriesFromDictionary:counts];
    [baseline removeObjectsForKeys:[profile[@"hiddenMetrics"] isKindOfClass:NSArray.class] ? profile[@"hiddenMetrics"] : @[]];
    values[@"countsBaseline"] = baseline;
    values[@"checkedAt"] = @(NSDate.date.timeIntervalSince1970);
    values[@"signatureAvailable"] = @(signature != nil);
    if (signature) {
        values[@"signatureBaseline"] = signature;
        values[@"signatureCheckedAt"] = values[@"checkedAt"];
    }
    if (signatureChanged) values[@"signatureChangedAt"] = values[@"checkedAt"];
    if (changes.count) {
        NSMutableDictionary *recent = [NSMutableDictionary dictionary];
        for (NSDictionary *change in target[@"lastChanges"]) recent[change[@"key"]] = change;
        for (NSDictionary *change in changes) {
            NSMutableDictionary *dated = [change mutableCopy]; dated[@"timestamp"] = values[@"checkedAt"]; recent[change[@"key"]] = dated;
        }
        NSMutableArray *ordered = [NSMutableArray array];
        for (NSString *key in @[@"received", @"following", @"followers", @"likes"]) if (recent[key]) [ordered addObject:recent[key]];
        values[@"lastChanges"] = ordered;
    }
    [self updateTarget:uid values:values];
    if (records.count) [self save];
    return records;
}
- (NSArray *)applyLikes:(NSArray<NSDictionary *> *)videos complete:(BOOL)complete forUID:(NSString *)uid {
    NSDictionary *person = [self target:uid]; if (!person) return @[];
    NSDictionary *diff = DY778RadarCompareLikes(person[@"likesBaseline"], videos, complete);
    if (!diff[@"snapshot"]) return @[];
    NSMutableArray *records = [NSMutableArray array];
    for (NSDictionary *video in diff[@"new"]) {
        NSMutableDictionary *record = [[self recordFor:person kind:@"like"] mutableCopy];
        record[@"video"] = video; record[@"uncertain"] = diff[@"gap"];
        [records addObject:record];
    }
    [self addRecords:records];
    [self updateTarget:uid values:@{@"likesBaseline": diff[@"snapshot"], @"likesCheckedAt": @(NSDate.date.timeIntervalSince1970),
        @"likesStatus": [diff[@"gap"] boolValue] ? @"列表跨度较大，记录为新发现作品" : @"已读取最近可见的喜欢"}];
    if (records.count) [self save];
    return records;
}
- (void)markLikesUnavailable:(NSString *)uid {
    NSDictionary *person = [self target:uid]; if (!person) return;
    NSMutableDictionary *baseline = [person[@"likesBaseline"] mutableCopy] ?: [NSMutableDictionary dictionary];
    baseline[@"valid"] = @NO;
    [self updateTarget:uid values:@{@"likesBaseline": baseline, @"likesStatus": @"喜欢列表不可见；数值仍按可见数据检测"}];
}
- (void)deleteRecord:(NSString *)recordID {
    NSIndexSet *indices = [self.history indexesOfObjectsPassingTest:^BOOL(NSDictionary *r, NSUInteger i, BOOL *stop) { return [r[@"id"] isEqual:recordID]; }];
    [self.history removeObjectsAtIndexes:indices]; [self save];
}
- (void)clearRecords { [self.history removeAllObjects]; [self save]; }
- (void)prune {
    NSInteger days = [self.preferences[@"retentionDays"] integerValue];
    if (days > 0) {
        NSTimeInterval cutoff = NSDate.date.timeIntervalSince1970 - days * 86400.0;
        NSIndexSet *old = [self.history indexesOfObjectsPassingTest:^BOOL(NSDictionary *r, NSUInteger i, BOOL *stop) { return [r[@"timestamp"] doubleValue] < cutoff; }];
        [self.history removeObjectsAtIndexes:old];
    }
    NSUInteger limit = MAX(100, MIN(1000, [self.preferences[@"recordLimit"] unsignedIntegerValue]));
    if (self.history.count > limit) [self.history removeObjectsInRange:NSMakeRange(limit, self.history.count - limit)];
}
- (NSDictionary *)document {
    return @{@"schema": @1, @"account": self.accountID, @"options": self.preferences.copy, @"targets": self.targets, @"records": self.records};
}
- (NSUInteger)storageBytes {
    return [NSJSONSerialization dataWithJSONObject:self.document options:0 error:nil].length;
}
- (void)save { [self persistAfter:0.5]; }
- (void)persistAfter:(NSTimeInterval)delay {
    NSAssert(NSThread.isMainThread, @"Store is confined to the main thread");
    self.dirty = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:DY778RadarStoreChanged object:self];
    NSTimeInterval due = NSProcessInfo.processInfo.systemUptime + delay;
    if (self.writeScheduled && self.writeDue <= due) return;
    self.writeScheduled = YES; self.writeDue = due;
    NSUInteger generation = ++self.saveGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.saveGeneration == generation) [self flush];
    });
}
- (void)flush {
    self.saveGeneration++; self.writeScheduled = NO;
    if (!self.dirty) return;
    if (!self.accountID.length || [self.storageError containsString:@"停止写入"]) return;
    // 在派发写入前先取快照。
    NSDictionary *snapshot = self.document; self.dirty = NO;
    NSURL *file = self.fileURL, *directory = self.directory;
    NSString *account = self.accountID;
    dispatch_async(self.writer, ^{
        NSError *error;
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&error];
        if (!error) [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error];
        if (!error) [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        if (!error) {
            NSDataWritingOptions options = NSDataWritingAtomic;
#if TARGET_OS_IPHONE
            options |= NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
            [data writeToURL:file options:options error:&error];
        }
        if (error) dispatch_async(dispatch_get_main_queue(), ^{
            if (![self.accountID isEqual:account]) return;
            self.storageError = @"记录暂时无法写入，请检查设备剩余空间。";
            [NSNotificationCenter.defaultCenter postNotificationName:DY778RadarStoreChanged object:self];
        });
    });
}
@end
