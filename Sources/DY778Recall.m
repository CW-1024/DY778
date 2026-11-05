#import "DY778Enhancements.h"
#import "DY778Recall.h"
#import "DY778EditHistory.h"
#import "DY778RecallPolicy.h"
#import "DY778ArchiveStorage.h"
#import <sqlite3.h>
#import <CommonCrypto/CommonDigest.h>
#import <AVKit/AVKit.h>
#import <QuickLook/QuickLook.h>
#import <stdatomic.h>
#import <os/lock.h>
#import <math.h>
#import "DY778RecallReentry.h"
#import "DY778RecallContent.h"
#import "DY778RecallMediaView.h"
#import "DY778ArchiveNative.h"
#import "DY778Avatar.h"

static char kDY778MessageSnapshot, kDY778MessageRecalled, kDY778MessageAccount, kDY778MessageGuard, kDY778HydrationRequested, kDY778ExtraMessage, kDY778LiveRecall, kDY778ObservedContent, kDY778SuppressLive, kDY778SystemNotice;
static id (*DY778OriginalContent)(id, SEL);
static void (*DY778OriginalSetContent)(id, SEL, id);
static void (*DY778OriginalSetRecalled)(id, SEL, BOOL);
static BOOL (*DY778OriginalRecalled)(id, SEL);
static void (*DY778OriginalApply)(id, SEL, id);
static void (*DY778OriginalApplyV2)(id, SEL, id);
static void (*DY778OriginalSetRecalledContent)(id, SEL, id);
static id (*DY778OriginalChatSections)(id, SEL);
static const void *DY778StoreQueueKey = &DY778StoreQueueKey;
static atomic_bool DY778RecallSwitch;
static _Thread_local unsigned int DY778ObservationDepth;
static _Thread_local DY778RecallFrame *DY778RecallFrames;
static _Thread_local BOOL DY778NativeRestoreInProgress;
static char kDY778VMRestoredState, kDY778CanonicalMessageKey;
static char kDY778FastState;
@interface DY778RecallFastState : NSObject {
@public atomic_bool queued;
@public atomic_uint nativeMutations;
}
@property(atomic) BOOL allowed;
@property(atomic) BOOL invalidated;
@property(atomic) BOOL recalled;
@property(atomic) BOOL rawRecalled;
@property(atomic, copy) NSDictionary *snapshot;
@property(atomic, copy) NSDictionary *capturedContent;
@property(atomic, copy) NSDictionary *rawContent;
@property(atomic, copy) NSDictionary *editInfo;
@property(atomic, copy) NSString *account;
@property(atomic, copy) NSString *conversation;
@property(atomic, copy) NSString *key;
@property(atomic, weak) id message;
@property(atomic, copy) NSString *serverID;
@property(atomic) NSUInteger displayRevision;
@property(atomic) BOOL profileRequested;
@end
@implementation DY778RecallFastState
@end
@interface DY778VMRestoredState : NSObject
@property(nonatomic, weak) id message;
@property(nonatomic) NSUInteger revision;
@property(nonatomic) NSUInteger attempts;
@property(nonatomic) BOOL succeeded;
@property(nonatomic) BOOL waitingForBuild;
@property(nonatomic) NSTimeInterval nextAttempt;
@end
@implementation DY778VMRestoredState @end
static void DY778PublishRecallSnapshot(DY778RecallFastState *state, NSDictionary *record) {
    NSDictionary *old = state.snapshot;
    BOOL changed = [old[@"available"] boolValue] != [record[@"available"] boolValue] || [old[@"recalled"] boolValue] != [record[@"recalled"] boolValue] || ![old[@"content"] isEqual:record[@"content"]];
    state.snapshot = record;
    if (changed || !state.displayRevision) state.displayRevision++;
}
static dispatch_queue_t DY778ObservationQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.dy778.message-observation", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
static NSHashTable *DY778KnownMessageStates(void) {
    static NSHashTable *states; static dispatch_once_t once;
    dispatch_once(&once, ^{ states = [NSHashTable weakObjectsHashTable]; });
    return states; // 仅在 DY778ObservationQueue 上访问。
}
static DY778RecallFastState *DY778FastState(id message, BOOL create) {
    static os_unfair_lock creationLock = OS_UNFAIR_LOCK_INIT;
    DY778RecallFastState *state = objc_getAssociatedObject(message, &kDY778FastState);
    if (!state && create && message) {
        os_unfair_lock_lock(&creationLock);
        state = objc_getAssociatedObject(message, &kDY778FastState);
        if (!state) { state = [DY778RecallFastState new]; objc_setAssociatedObject(message, &kDY778FastState, state, OBJC_ASSOCIATION_RETAIN); }
        os_unfair_lock_unlock(&creationLock);
    }
    return state;
}
static BOOL DY778FastAllowed(DY778RecallFastState *state) {
    return atomic_load_explicit(&DY778RecallSwitch, memory_order_relaxed) && state.allowed;
}
static void DY778RefreshRecallPolicy(void);
static void DY778ObserveMessageNow(id message);
static void DY778ScheduleRecallNotification(void);
static void DY778InvalidateRecallSnapshots(NSSet<NSString *> *keys) {
    if (!keys.count) return;
    dispatch_async(DY778ObservationQueue(), ^{
        BOOL changed = NO;
        for (DY778RecallFastState *state in DY778KnownMessageStates().allObjects) if ([keys containsObject:state.key]) {
            state.allowed = NO; state.snapshot = nil; state.invalidated = YES; changed = YES;
        }
        if (changed) DY778ScheduleRecallNotification();
    });
}
// 同一条消息的每个存活 SDK 实例都必须看到已持久化的撤回标记。
static void DY778PublishPersistedRecall(NSDictionary *record) {
    if (![record[@"recalled"] boolValue] || [record[@"systemRecallNotice"] boolValue]) return;
    dispatch_async(DY778ObservationQueue(), ^{
        BOOL changed = NO;
        for (DY778RecallFastState *state in DY778KnownMessageStates().allObjects) {
            if (![state.account isEqual:record[@"account"]] || ![state.conversation isEqual:record[@"conversation"]]) continue;
            if (![state.key isEqual:record[@"key"]] && !(state.serverID.length && ![state.serverID isEqual:@"0"] && [state.serverID isEqual:record[@"serverID"]])) continue;
            if (state.invalidated || !DY778FastAllowed(state)) continue;
            BOOL edge = !state.recalled || ![state.snapshot[@"recalled"] boolValue];
            NSMutableDictionary *merged = [([state.snapshot[@"available"] boolValue] ? state.snapshot : record) mutableCopy];
            merged[@"key"] = state.key; merged[@"recalled"] = @YES; merged[@"recalledAt"] = record[@"recalledAt"] ?: @0;
            state.recalled = YES; DY778PublishRecallSnapshot(state, merged);
            id message = state.message;
            if (message) { objc_setAssociatedObject(message, &kDY778MessageRecalled, @YES, OBJC_ASSOCIATION_RETAIN); objc_setAssociatedObject(message, &kDY778MessageSnapshot, merged, OBJC_ASSOCIATION_RETAIN); }
            changed |= edge;
        }
        if (changed) DY778ScheduleRecallNotification();
    });
}
static BOOL DY778RecallNotificationScheduled;
static void DY778ScheduleRecallNotification(void) {
    @synchronized (DY778Preferences()) {
        if (DY778RecallNotificationScheduled) return;
        DY778RecallNotificationScheduled = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (DY778Preferences()) { DY778RecallNotificationScheduled = NO; }
        [NSNotificationCenter.defaultCenter postNotificationName:DY778RecallChangedNotification object:nil];
    });
}
@interface DY778RecallSaveLease : NSObject
@property(nonatomic) UIBackgroundTaskIdentifier identifier;
@property(nonatomic) BOOL ended;
- (void)begin;
- (void)finish;
@end
@implementation DY778RecallSaveLease
- (instancetype)init { if ((self = [super init])) _identifier = UIBackgroundTaskInvalid; return self; }
- (void)begin {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.ended || UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) return;
        __weak typeof(self) weakSelf = self;
        self.identifier = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"DY778.SaveRecall" expirationHandler:^{ [weakSelf finish]; }];
    });
}
- (void)finish {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.ended = YES;
        if (self.identifier != UIBackgroundTaskInvalid) { [UIApplication.sharedApplication endBackgroundTask:self.identifier]; self.identifier = UIBackgroundTaskInvalid; }
    });
}
@end
@protocol DY778ChatSettingsInitializable <NSObject>
- (instancetype)initWithIdentifier:(NSString *)identifier;
@end
static NSString *const DY778ChatItemIdentifier = @"com.dy778.recalled-messages";

static NSString *DY778Hash(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *value = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [value appendFormat:@"%02x", digest[i]];
    return value;
}

static id DY778JSONValue(id value, NSUInteger depth) {
    if (!value || value == NSNull.null) return NSNull.null;
    if (depth > 32) return @{@"_unavailable": @"Nesting exceeds 32 levels"};
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return value;
    if ([value isKindOfClass:NSDate.class]) return @([(NSDate *)value timeIntervalSince1970]);
    if ([value isKindOfClass:NSURL.class]) return [value absoluteString] ?: @"";
    if ([value isKindOfClass:NSData.class]) return @{@"_encoding": @"base64", @"data": [value base64EncodedStringWithOptions:0]};
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id item in value) [result addObject:DY778JSONValue(item, depth + 1)];
        return result;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (id key in value) {
            NSString *name = [key isKindOfClass:NSString.class] ? key : [key description];
            if (name) result[name] = DY778JSONValue(value[key], depth + 1);
        }
        return result;
    }
    return @{@"_class": NSStringFromClass([value class]), @"_description": [value description] ?: @""};
}

static NSDictionary *DY778ImmutableDictionary(id dictionary) {
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
    @try { return [DY778JSONValue(dictionary, 0) copy]; } @catch (__unused NSException *exception) { return nil; }
}

static BOOL DY778ContentAvailable(id content) {
    if (![content isKindOfClass:NSDictionary.class] || ![content count]) return NO;
    NSString *text = [content[@"text"] isKindOfClass:NSString.class] ? content[@"text"] : nil;
    return ![text isEqualToString:@"Recall Content Hided"];
}

static NSString *DY778MessageAccountID(id message) {
    NSString *bound = objc_getAssociatedObject(message, &kDY778MessageAccount);
    if (bound.length) return bound;
    Ivar rootIvar = class_getInstanceVariable(NSClassFromString(@"TIMXOModel"), "_r");
    const char *encoding = rootIvar ? ivar_getTypeEncoding(rootIvar) : NULL;
    id root = encoding && encoding[0] == '@' && [message isKindOfClass:NSClassFromString(@"TIMXOModel")] ? object_getIvar(message, rootIvar) : nil;
    NSString *account = DY778Identifier(DY778Read(DY778Read(root, @"config"), @"uid"));
    if (!account.length || [account isEqualToString:@"0"]) {
        if (root) return nil; // 没有 UID 的 SDK 实例不得继承另一个前台账号。
        account = DY778CurrentAccountID();
    }
    if (!account.length || [account isEqualToString:@"0"]) return nil;
    return account;
}

static NSString *DY778ConversationPreferenceKey(NSString *account, NSString *conversation) {
    if (!account.length || !conversation.length) return nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[account, conversation] options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
static BOOL DY778RecallEnabledForAccountConversation(NSString *account, NSString *conversation) {
    if (!DY778Bool(@"recall.enabled")) return NO;
    NSString *key = DY778ConversationPreferenceKey(account, conversation);
    if (!key) return NO;
    id disabled = [DY778Preferences() objectForKey:@"recall.disabledConversations"];
    return !([disabled isKindOfClass:NSDictionary.class] && [disabled[key] boolValue]);
}
BOOL DY778RecallEnabledForConversation(NSString *conversationID) {
    return DY778RecallEnabledForAccountConversation(DY778CurrentAccountID(), conversationID);
}
BOOL DY778RecallEnabledForMessage(id message) {
    return DY778FastAllowed(DY778FastState(message, NO));
}
// 本函数仅限观察队列调用；绝不从 SDK hook 里调用。
static BOOL DY778EvaluateMessagePolicy(id message) {
    NSString *conversation = DY778Identifier(DY778Read(message, @"belongingConversationIdentifier"));
    if (!conversation.length) conversation = DY778Identifier(DY778Read(message, @"conversationID"));
    return message && DY778RecallEnabledForAccountConversation(DY778MessageAccountID(message), conversation);
}
void DY778SetConversationRecallEnabled(NSString *conversationID, BOOL enabled) {
    NSString *key = DY778ConversationPreferenceKey(DY778CurrentAccountID(), conversationID);
    if (!key.length) return;
    @synchronized (DY778Preferences()) {
        id value = [DY778Preferences() objectForKey:@"recall.disabledConversations"];
        NSMutableDictionary *disabled = [value isKindOfClass:NSDictionary.class] ? [value mutableCopy] : [NSMutableDictionary dictionary];
        if (enabled) [disabled removeObjectForKey:key]; else disabled[key] = @YES;
        DY778Set(@"recall.disabledConversations", disabled);
    }
    DY778ScheduleRecallNotification();
}
static NSString *DY778RecordKey(NSString *account, NSString *conversation, NSString *message) {
    if (!account.length || !conversation.length || !message.length) return nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[account, conversation, message] options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSString *DY778KeyForMessage(id message) {
    NSString *account = DY778MessageAccountID(message);
    NSString *conversation = DY778Identifier(DY778Read(message, @"belongingConversationIdentifier")) ?: DY778Identifier(DY778Read(message, @"conversationID"));
    NSDictionary *resolved = objc_getAssociatedObject(message, &kDY778CanonicalMessageKey);
    if ([resolved[@"account"] isEqual:account] && [resolved[@"conversation"] isEqual:conversation]) return resolved[@"key"];
    NSString *identifier = DY778Identifier(DY778Read(message, @"serverMessageID"));
    if (!identifier.length || [identifier isEqual:@"0"]) identifier = DY778Identifier(DY778Read(message, @"identifier"));
    return DY778RecordKey(account, conversation, identifier);
}

static BOOL DY778IncomingMessage(id message) {
    NSString *account = DY778MessageAccountID(message);
    NSString *sender = DY778Identifier(DY778Read(message, @"sender"));
    return account.length && sender.length && ![sender isEqualToString:@"0"] && ![sender isEqualToString:account];
}

static BOOL DY778RawRecalled(id message) {
    return [DY778Read(message, @"recalled") boolValue];
}
static NSString *DY778SafeLocalPath(id value) {
    NSString *path = [value isKindOfClass:NSURL.class] ? ([value isFileURL] ? [value path] : nil) : ([value isKindOfClass:NSString.class] ? value : nil);
    if ([path hasPrefix:@"file://"]) path = [NSURL URLWithString:path].path;
    if (!path.length || ![path isAbsolutePath]) return nil;
    NSString *standard = path.stringByStandardizingPath;
    return [standard hasPrefix:[NSHomeDirectory().stringByStandardizingPath stringByAppendingString:@"/"]] ? standard : nil;
}
static NSString *DY778ResolvedMediaPath(id value) {
    NSString *path = DY778SafeLocalPath(value); if (!path) return nil;
    NSString *resolved = path.stringByResolvingSymlinksInPath;
    NSString *home = NSHomeDirectory().stringByResolvingSymlinksInPath;
    return [resolved hasPrefix:[home stringByAppendingString:@"/"]] ? resolved : nil;
}
static NSString *DY778MediaKind(NSString *mime, NSString *extension, NSString *hint) {
    NSString *value = [[NSString stringWithFormat:@"%@ %@ %@", mime ?: @"", extension ?: @"", hint ?: @""] lowercaseString];
    for (NSString *word in @[@"image", @"photo", @"jpg", @"jpeg", @"png", @"webp", @"gif", @"heic"])
        if ([value containsString:word]) return @"image";
    for (NSString *word in @[@"audio", @"voice", @"mp3", @"m4a", @"aac", @"wav", @"amr", @"opus"])
        if ([value containsString:word]) return @"audio";
    for (NSString *word in @[@"video", @"mp4", @"mov", @"m3u8"])
        if ([value containsString:word]) return @"video";
    return @"file";
}

static NSArray *DY778MessageMedia(id message, NSDictionary *content) {
    NSMutableArray *media = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *property in @[@"fileAttachments", @"messageBodyFiles"]) {
        id attachments = DY778Read(message, property);
        if (![attachments isKindOfClass:NSArray.class]) continue;
        for (id attachment in attachments) {
            if (media.count >= 24) break;
            NSString *path = DY778SafeLocalPath(DY778Read(attachment, @"localFileURL"));
            NSString *remote = DY778Identifier(DY778Read(attachment, @"remotePath"));
            NSURL *url = [NSURL URLWithString:remote ?: @""];
            if (![@[@"http", @"https"] containsObject:url.scheme.lowercaseString]) remote = nil;
            NSString *identity = path ?: remote;
            if (!identity.length || [seen containsObject:identity]) continue;
            [seen addObject:identity];
            NSString *extension = DY778Identifier(DY778Read(attachment, @"fileExtension")) ?: path.pathExtension;
            NSString *mime = DY778Identifier(DY778Read(attachment, @"mimeType")) ?: @"";
            NSString *kind = DY778MediaKind(mime, extension, DY778Identifier(DY778Read(attachment, @"displayType")));
            NSMutableDictionary *item = [@{@"kind": kind, @"mime": mime, @"extension": extension ?: @"",
                @"name": path.lastPathComponent ?: url.lastPathComponent ?: @"消息附件"} mutableCopy];
            if (path) item[@"sourcePath"] = path;
            if (remote) item[@"remoteURL"] = remote;
            if ([DY778Identifier(DY778Read(attachment, @"algorithm")) length]) item[@"encrypted"] = @YES;
            [media addObject:item];
        }
    }
    // 排除头像、引用内容和音乐封面。
    for (NSDictionary *item in DY778RecallMediaFromContent(content)) {
        NSString *identity = item[@"remoteURL"];
        if (![seen containsObject:identity]) { [seen addObject:identity]; [media addObject:item]; }
    }
    return media;
}

static NSString *DY778RecordSummary(NSDictionary *record) {
    return DY778RecallSummary(record);
}
@interface DY778RecallStore : NSObject
@property(nonatomic) sqlite3 *database;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) NSURL *root;
@property(nonatomic, strong) NSCache<NSString *, NSDictionary *> *cache;
@property(nonatomic, strong) NSMutableSet<NSString *> *recalledKeys;
@property(nonatomic, strong) NSMutableSet<NSString *> *archivedKeys;
@property(nonatomic, copy) NSString *status;
@property(nonatomic) NSTimeInterval lastMaintenance;
@property(nonatomic, strong) NSMutableSet<NSString *> *forgottenKeys;
@property(nonatomic, strong) NSMutableSet<NSString *> *clearingAccounts;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *pendingRecords;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *profiles;
@property(nonatomic, strong) NSMutableSet<NSString *> *notifiedKeys;
+ (instancetype)shared;
- (void)save:(NSDictionary *)record key:(NSString *)key recalled:(BOOL)recalled;
- (NSDictionary *)cachedRecord:(NSString *)key;
- (void)loadRecordForKey:(NSString *)key account:(NSString *)account conversation:(NSString *)conversation server:(NSString *)server legacyKey:(NSString *)legacyKey completion:(void (^)(NSDictionary *))completion;
- (BOOL)isForgotten:(NSString *)key;
- (BOOL)isRecalled:(NSString *)key;
- (void)removeForAccount:(NSString *)account key:(NSString *)key completion:(dispatch_block_t)completion;
- (void)maintenance;
- (void)linkRecallForRecord:(NSDictionary *)record;
- (void)updateProfile:(NSDictionary *)profile account:(NSString *)account conversation:(NSString *)conversation;
- (NSDictionary *)profileForAccount:(NSString *)account conversation:(NSString *)conversation;
- (void)conversationSummaries:(NSString *)account completion:(void (^)(NSArray *))completion;
- (void)recordsForAccount:(NSString *)account conversation:(NSString *)conversation offset:(NSUInteger)offset completion:(void (^)(NSArray *))completion;
- (void)removeConversation:(NSString *)conversation account:(NSString *)account completion:(dispatch_block_t)completion;
@end

static void DY778Bind(sqlite3_stmt *statement, int position, NSString *string) {
    sqlite3_bind_text(statement, position, (string ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
}

static NSDictionary *DY778DecodeRow(sqlite3_stmt *statement) {
    const void *bytes = sqlite3_column_blob(statement, 0);
    int length = sqlite3_column_bytes(statement, 0);
    if (!bytes || length <= 0) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:(NSUInteger)length] options:NSJSONReadingMutableContainers error:nil];
    if (![object isKindOfClass:NSMutableDictionary.class]) return nil;
    object[@"recalled"] = @(sqlite3_column_int(statement, 1));
    object[@"recalledAt"] = @(sqlite3_column_double(statement, 2));
    return DY778RecallEnrichRecord(object);
}

@implementation DY778RecallStore
+ (instancetype)shared {
    static DY778RecallStore *store; static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [self new]; });
    return store;
}
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.dy778.recall-store", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_queue, DY778StoreQueueKey, (void *)DY778StoreQueueKey, NULL);
        _cache = [NSCache new]; _cache.countLimit = 256;
        _recalledKeys = [NSMutableSet set]; _archivedKeys = [NSMutableSet set]; _forgottenKeys = [NSMutableSet set];
        _clearingAccounts = [NSMutableSet set]; _pendingRecords = [NSMutableDictionary dictionary]; _profiles = [NSMutableDictionary dictionary]; _notifiedKeys = [NSMutableSet set]; _status = @"正在准备本地记录";
        dispatch_async(_queue, ^{ [self openDatabase]; });
    }
    return self;
}
- (void)openDatabase {
    NSFileManager *manager = NSFileManager.defaultManager;
    self.root = DY778ArchiveDirectory(@"Recall");
    if (!self.root) {
        @synchronized (self) { self.status = @"本地记录目录不可写"; } return;
    }
    NSString *databasePath = [[self.root URLByAppendingPathComponent:@"messages.sqlite"] path];
    sqlite3 *database = NULL;
    if (sqlite3_open_v2(databasePath.UTF8String, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        @synchronized (self) { self.status = @"本地记录数据库暂不可用"; } return;
    }
    self.database = database;
    sqlite3_busy_timeout(database, 1500);
    const char *schema = "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA secure_delete=ON;"
        "CREATE TABLE IF NOT EXISTS messages (key TEXT PRIMARY KEY, account TEXT NOT NULL, conversation TEXT NOT NULL,"
        "message TEXT NOT NULL, created REAL NOT NULL, seen REAL NOT NULL, recalled INTEGER NOT NULL DEFAULT 0,"
        "recalled_at REAL NOT NULL DEFAULT 0, available INTEGER NOT NULL DEFAULT 0, payload BLOB NOT NULL);"
        "CREATE INDEX IF NOT EXISTS account_recall ON messages(account,recalled,recalled_at);"
        "CREATE INDEX IF NOT EXISTS account_conversation ON messages(account,conversation,recalled);"
        "CREATE TABLE IF NOT EXISTS forgotten (key TEXT PRIMARY KEY, account TEXT NOT NULL, deleted REAL NOT NULL);"
        "CREATE TABLE IF NOT EXISTS recall_targets (account TEXT NOT NULL, conversation TEXT NOT NULL, message TEXT NOT NULL, recalled_at REAL NOT NULL, PRIMARY KEY(account,conversation,message));"
        "CREATE TABLE IF NOT EXISTS profiles (key TEXT PRIMARY KEY, account TEXT NOT NULL, conversation TEXT NOT NULL, payload BLOB NOT NULL);"
        "CREATE TRIGGER IF NOT EXISTS reject_forgotten_message BEFORE INSERT ON messages "
        "WHEN EXISTS(SELECT 1 FROM forgotten WHERE key=NEW.key) BEGIN SELECT RAISE(IGNORE); END;";
    if (sqlite3_exec(database, schema, NULL, NULL, NULL) != SQLITE_OK) {
        sqlite3_close(database); self.database = NULL;
        @synchronized (self) { self.status = @"本地记录初始化失败"; } return;
    }
    NSMutableSet *columns = [NSMutableSet set]; sqlite3_stmt *columnQuery = NULL;
    if (sqlite3_prepare_v2(database, "PRAGMA table_info(messages)", -1, &columnQuery, NULL) == SQLITE_OK)
        while (sqlite3_step(columnQuery) == SQLITE_ROW) [columns addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(columnQuery, 1)]];
    sqlite3_finalize(columnQuery);
    if (![columns containsObject:@"server_id"]) sqlite3_exec(database, "ALTER TABLE messages ADD COLUMN server_id TEXT NOT NULL DEFAULT ''", NULL, NULL, NULL);
    sqlite3_exec(database, "CREATE INDEX IF NOT EXISTS message_server_id ON messages(account,conversation,server_id)", NULL, NULL, NULL);
    BOOL deriveArchiveIndex = YES; // 用当前内容解析器重新归类旧的占位行。
    if (![columns containsObject:@"hidden_notice"]) sqlite3_exec(database, "ALTER TABLE messages ADD COLUMN hidden_notice INTEGER NOT NULL DEFAULT 0", NULL, NULL, NULL);
    if (![columns containsObject:@"has_media"]) sqlite3_exec(database, "ALTER TABLE messages ADD COLUMN has_media INTEGER NOT NULL DEFAULT 0", NULL, NULL, NULL);
    if (deriveArchiveIndex) {
        sqlite3_stmt *rows = NULL, *index = NULL;
        if (sqlite3_prepare_v2(database, "SELECT payload,recalled,recalled_at,key FROM messages", -1, &rows, NULL) == SQLITE_OK && sqlite3_prepare_v2(database, "UPDATE messages SET hidden_notice=?,has_media=?,server_id=? WHERE key=?", -1, &index, NULL) == SQLITE_OK) {
            while (sqlite3_step(rows) == SQLITE_ROW) {
                NSDictionary *record = DY778DecodeRow(rows);
                sqlite3_reset(index); sqlite3_clear_bindings(index); sqlite3_bind_int(index, 1, DY778RecallRecordShouldHide(record)); sqlite3_bind_int(index, 2, 0);
                DY778Bind(index, 3, record[@"serverID"]);
                sqlite3_bind_text(index, 4, (const char *)sqlite3_column_text(rows, 3), -1, SQLITE_TRANSIENT); sqlite3_step(index);
            }
        }
        sqlite3_finalize(rows); sqlite3_finalize(index);
    }
    [manager setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
        ofItemAtPath:databasePath error:nil];
    sqlite3_stmt *forgotten = NULL;
    if (sqlite3_prepare_v2(database, "SELECT key FROM forgotten", -1, &forgotten, NULL) == SQLITE_OK)
        while (sqlite3_step(forgotten) == SQLITE_ROW) {
            NSString *key = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(forgotten, 0)];
            @synchronized (self) { [self.forgottenKeys addObject:key]; }
        }
    sqlite3_finalize(forgotten);
    sqlite3_stmt *profiles = NULL;
    if (sqlite3_prepare_v2(database, "SELECT key,payload FROM profiles", -1, &profiles, NULL) == SQLITE_OK)
        while (sqlite3_step(profiles) == SQLITE_ROW) {
            NSString *key = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(profiles, 0)];
            NSData *data = [NSData dataWithBytes:sqlite3_column_blob(profiles, 1) length:sqlite3_column_bytes(profiles, 1)];
            id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([value isKindOfClass:NSDictionary.class]) @synchronized(self) { self.profiles[key] = value; }
        }
    sqlite3_finalize(profiles);
    sqlite3_stmt *notices = NULL; NSMutableArray *oldNotices = [NSMutableArray array];
    if (sqlite3_prepare_v2(database, "SELECT payload,recalled,recalled_at FROM messages WHERE hidden_notice=1", -1, &notices, NULL) == SQLITE_OK)
        while (sqlite3_step(notices) == SQLITE_ROW) { NSDictionary *notice = DY778DecodeRow(notices); if ([notice[@"recallTargetID"] length]) [oldNotices addObject:notice]; }
    sqlite3_finalize(notices); for (NSDictionary *notice in oldNotices) [self linkRecallForRecord:notice];
    [self maintenance];
    [self reloadKeys];
    @synchronized (self) { self.status = @"本机保存 · 已开启数据保护"; }
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:DY778RecallChangedNotification object:nil]; });
}
- (void)reloadKeys {
    if (!self.database) return;
    sqlite3_stmt *statement = NULL;
    NSMutableSet *keys = [NSMutableSet set];
    NSMutableSet *archived = [NSMutableSet set];
    if (sqlite3_prepare_v2(self.database, "SELECT key,hidden_notice FROM messages WHERE recalled=1", -1, &statement, NULL) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const unsigned char *key = sqlite3_column_text(statement, 0);
            if (key) { NSString *value = [NSString stringWithUTF8String:(const char *)key]; [keys addObject:value]; if (!sqlite3_column_int(statement, 1)) [archived addObject:value]; }
        }
    }
    sqlite3_finalize(statement);
    @synchronized (self) {
        for (NSString *key in self.pendingRecords) if ([self.pendingRecords[key][@"recalled"] boolValue]) [keys addObject:key];
        for (NSString *key in self.pendingRecords) if ([self.pendingRecords[key][@"recalled"] boolValue] && !DY778RecallRecordShouldHide(self.pendingRecords[key])) [archived addObject:key];
        [keys minusSet:self.forgottenKeys]; [archived minusSet:self.forgottenKeys]; self.recalledKeys = keys; self.archivedKeys = archived;
    }
}
- (BOOL)isRecalled:(NSString *)key {
    if (!key) return NO;
    @synchronized (self) { return [self.recalledKeys containsObject:key]; }
}
- (BOOL)isForgotten:(NSString *)key {
    if (!key.length) return NO;
    @synchronized (self) {
        if ([self.forgottenKeys containsObject:key]) return YES;
        if (!self.clearingAccounts.count) return NO;
        NSArray *identity = [NSJSONSerialization JSONObjectWithData:[key dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        return [identity isKindOfClass:NSArray.class] && identity.count == 3 && [self.clearingAccounts containsObject:identity.firstObject];
    }
}
- (NSDictionary *)databaseRecordForKey:(NSString *)key {
    if (!self.database || !key.length) return nil;
    sqlite3_stmt *statement = NULL;
    NSDictionary *record = nil;
    if (sqlite3_prepare_v2(self.database, "SELECT payload,recalled,recalled_at FROM messages WHERE key=?", -1, &statement, NULL) == SQLITE_OK) {
        DY778Bind(statement, 1, key);
        if (sqlite3_step(statement) == SQLITE_ROW) record = DY778DecodeRow(statement);
    }
    sqlite3_finalize(statement);
    return record;
}
- (NSDictionary *)cachedRecord:(NSString *)key {
    if (!key.length) return nil;
    @synchronized (self) {
        if ([self isForgotten:key]) return nil;
        return self.pendingRecords[key] ?: [self.cache objectForKey:key];
    }
}
- (void)loadRecordForKey:(NSString *)key account:(NSString *)account conversation:(NSString *)conversation server:(NSString *)server legacyKey:(NSString *)legacyKey completion:(void (^)(NSDictionary *))completion {
    if (!key.length) return;
    dispatch_async(self.queue, ^{
        NSDictionary *record = [self databaseRecordForKey:key];
        if (!record && self.database) {
            sqlite3_stmt *statement = NULL;
            const char *lookup = "SELECT payload,recalled,recalled_at FROM messages WHERE account=? AND conversation=? AND (key=? OR (server_id<>'' AND server_id<>'0' AND server_id=?)) ORDER BY recalled DESC,available DESC,seen DESC LIMIT 1";
            if (sqlite3_prepare_v2(self.database, lookup, -1, &statement, NULL) == SQLITE_OK) {
                DY778Bind(statement, 1, account); DY778Bind(statement, 2, conversation); DY778Bind(statement, 3, legacyKey); DY778Bind(statement, 4, server);
                if (sqlite3_step(statement) == SQLITE_ROW) record = DY778DecodeRow(statement);
            }
            sqlite3_finalize(statement);
        }
        @synchronized (self) {
            if ([self isForgotten:key] || [self isForgotten:legacyKey] || [self isForgotten:record[@"key"]]) record = nil;
            else {
                NSDictionary *pending = self.pendingRecords[key];
                if (pending && !([record[@"available"] boolValue] && ![pending[@"available"] boolValue])) record = pending;
                if (record) [self.cache setObject:record forKey:key];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(record); });
    });
}
- (void)save:(NSDictionary *)record key:(NSString *)key recalled:(BOOL)recalled {
    if (!record || !key) return;
    @synchronized (self) {
        if ([self isForgotten:key] || !DY778RecallEnabledForAccountConversation(record[@"account"], record[@"conversation"])) return;
        NSDictionary *cached = self.pendingRecords[key] ?: [self.cache objectForKey:key];
        NSMutableDictionary *snapshot = [record mutableCopy];
        if ([cached[@"recalled"] boolValue] && [cached[@"available"] boolValue]) snapshot[@"content"] = cached[@"content"];
        NSDictionary *comment = DY778MergeCapturedComment(cached[@"comment"], snapshot[@"comment"]);
        if (comment) snapshot[@"comment"] = comment;
        snapshot[@"key"] = key;
        BOOL wasRecalled = recalled || [cached[@"recalled"] boolValue] || [snapshot[@"recalled"] boolValue];
        snapshot[@"recalled"] = @(wasRecalled);
        if (wasRecalled) {
            NSTimeInterval first = [cached[@"recalledAt"] doubleValue];
            if (first <= 0) first = [snapshot[@"recalledAt"] doubleValue];
            snapshot[@"recalledAt"] = @(first > 0 ? first : NSDate.date.timeIntervalSince1970);
            [self.recalledKeys addObject:key];
            if (!DY778RecallRecordShouldHide(snapshot)) [self.archivedKeys addObject:key]; else [self.archivedKeys removeObject:key];
        }
        BOOL shouldNotify = !DY778RecallRecordShouldHide(snapshot) && [snapshot[@"_liveRecall"] boolValue] && wasRecalled && ![self.notifiedKeys containsObject:key];
        [snapshot removeObjectForKey:@"_liveRecall"];
        DY778RecallSaveLease *lease = shouldNotify ? [DY778RecallSaveLease new] : nil; [lease begin];
        NSDictionary *captured = [snapshot copy];
        self.pendingRecords[key] = captured;
        dispatch_async(self.queue, ^{
            if (!self.database || [self isForgotten:key] || !DY778RecallEnabledForAccountConversation(captured[@"account"], captured[@"conversation"])) {
                @synchronized (self) { if (self.pendingRecords[key] == captured) [self.pendingRecords removeObjectForKey:key]; }
                [lease finish]; return;
            }
            NSMutableDictionary *enriched = [captured mutableCopy];
            NSDictionary *existing = [self databaseRecordForKey:key];
            NSDictionary *comment = DY778MergeCapturedComment(existing[@"comment"], enriched[@"comment"]);
            if (comment) enriched[@"comment"] = comment;
            if (([existing[@"recalled"] boolValue] || [captured[@"recalled"] boolValue]) && [existing[@"available"] boolValue]) { enriched[@"content"] = existing[@"content"]; enriched[@"available"] = @YES; }
            if ([existing[@"recalled"] boolValue] && [existing[@"identityCaptured"] boolValue]) {
                for (NSString *field in @[@"senderName", @"senderAvatar", @"senderRemark", @"conversationName", @"conversationAvatar"]) if ([existing[field] length]) enriched[field] = existing[field];
                enriched[@"identityCaptured"] = @YES;
            }
            if ([existing[@"content"] isEqual:enriched[@"content"]]) {
                NSMutableArray *mergedMedia = [NSMutableArray arrayWithArray:enriched[@"media"] ?: @[]];
                [mergedMedia addObjectsFromArray:existing[@"media"] ?: @[]]; enriched[@"media"] = mergedMedia;
                for (NSString *field in @[@"share", @"quote"]) if (!enriched[field] && existing[field]) enriched[field] = existing[field];
                NSMutableDictionary *card = [existing[@"card"] mutableCopy] ?: [NSMutableDictionary dictionary];
                [card addEntriesFromDictionary:enriched[@"card"] ?: @{}]; enriched[@"card"] = card;
                if ((![(NSString *)enriched[@"presentationClass"] length] || [enriched[@"presentationClass"] isEqual:@"AWEIMRecallMessage"]) && [existing[@"presentationClass"] length]) enriched[@"presentationClass"] = existing[@"presentationClass"];
            }
            [enriched removeObjectForKey:@"presentationVersion"];
            enriched = [DY778RecallEnrichRecord(enriched) mutableCopy];
            enriched[@"summary"] = DY778RecordSummary(enriched);
            NSDictionary *stored = enriched;
            NSData *payload = [NSJSONSerialization dataWithJSONObject:stored options:0 error:nil];
            BOOL saved = NO;
            sqlite3_stmt *statement = NULL;
            const char *sql = "INSERT INTO messages(key,account,conversation,message,created,seen,recalled,recalled_at,available,payload)"
                " VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(key) DO UPDATE SET seen=excluded.seen,"
                " recalled=MAX(messages.recalled,excluded.recalled), recalled_at=CASE WHEN messages.recalled_at>0 THEN messages.recalled_at ELSE excluded.recalled_at END,"
                " available=MAX(messages.available,excluded.available), payload=CASE WHEN (messages.recalled=1 OR excluded.recalled=1) AND messages.available=1 THEN messages.payload"
                " WHEN excluded.available=0 AND messages.available=1 THEN messages.payload ELSE excluded.payload END";
            if (payload && sqlite3_prepare_v2(self.database, sql, -1, &statement, NULL) == SQLITE_OK) {
                DY778Bind(statement, 1, key); DY778Bind(statement, 2, stored[@"account"]); DY778Bind(statement, 3, stored[@"conversation"]); DY778Bind(statement, 4, stored[@"messageID"]);
                sqlite3_bind_double(statement, 5, [stored[@"createdAt"] doubleValue]);
                sqlite3_bind_double(statement, 6, NSDate.date.timeIntervalSince1970);
                sqlite3_bind_int(statement, 7, [stored[@"recalled"] boolValue]);
                sqlite3_bind_double(statement, 8, [stored[@"recalledAt"] doubleValue]);
                sqlite3_bind_int(statement, 9, [stored[@"available"] boolValue]);
                sqlite3_bind_blob(statement, 10, payload.bytes, (int)payload.length, SQLITE_TRANSIENT);
                saved = sqlite3_step(statement) == SQLITE_DONE;
            }
            sqlite3_finalize(statement);
            if (saved) {
                sqlite3_stmt *flags = NULL;
                if (sqlite3_prepare_v2(self.database, "UPDATE messages SET hidden_notice=?,has_media=?,server_id=? WHERE key=?", -1, &flags, NULL) == SQLITE_OK) {
                    sqlite3_bind_int(flags, 1, DY778RecallRecordShouldHide(stored)); sqlite3_bind_int(flags, 2, 0); DY778Bind(flags, 3, stored[@"serverID"]); DY778Bind(flags, 4, key); sqlite3_step(flags);
                }
                sqlite3_finalize(flags);
                [self linkRecallForRecord:stored];
            }
            if (saved && ([existing[@"recalled"] boolValue] || [captured[@"recalled"] boolValue]) && [existing[@"available"] boolValue]) {
                sqlite3_stmt *metadata = NULL;
                if (sqlite3_prepare_v2(self.database, "UPDATE messages SET payload=? WHERE key=?", -1, &metadata, NULL) == SQLITE_OK) {
                    sqlite3_bind_blob(metadata, 1, payload.bytes, (int)payload.length, SQLITE_TRANSIENT); DY778Bind(metadata, 2, key); sqlite3_step(metadata);
                }
                sqlite3_finalize(metadata);
            }
            NSDictionary *persisted = saved ? [self databaseRecordForKey:key] : nil;
            if (persisted) DY778PublishPersistedRecall(persisted);
            @synchronized (self) {
                // 已完成的旧写入绝不能覆盖更新的、挂起的撤回。
                if (self.pendingRecords[key] == captured) {
                    [self.pendingRecords removeObjectForKey:key];
                    if (![self isForgotten:key]) [self.cache setObject:persisted ?: captured forKey:key];
                }
                if (!saved) self.status = @"本地存储失败，请检查剩余空间";
            }
            BOOL deliver = NO;
            @synchronized(self) {
                if (saved && shouldNotify && ![existing[@"recalled"] boolValue] && ![self.notifiedKeys containsObject:key] && ![self isForgotten:key]) { [self.notifiedKeys addObject:key]; deliver = YES; }
            }
            if (deliver) dispatch_async(dispatch_get_main_queue(), ^{
                if (DY778RecallEnabledForAccountConversation(stored[@"account"], stored[@"conversation"]) && [stored[@"account"] isEqual:DY778CurrentAccountID()]) [NSNotificationCenter.defaultCenter postNotificationName:DY778RecallDetectedNotification object:nil userInfo:@{@"record": persisted ?: stored}];
            });
            [lease finish];
            if (NSDate.date.timeIntervalSince1970 - self.lastMaintenance > 60) [self maintenance];

        });
    }
}
- (void)linkRecallForRecord:(NSDictionary *)record {
    NSString *account = record[@"account"], *conversation = record[@"conversation"];
    NSString *target = record[@"recallTargetID"];
    sqlite3_stmt *statement = NULL;
    if ([record[@"systemRecallNotice"] boolValue] && target.length) {
        if (sqlite3_prepare_v2(self.database, "INSERT INTO recall_targets(account,conversation,message,recalled_at) VALUES(?,?,?,?) ON CONFLICT(account,conversation,message) DO UPDATE SET recalled_at=MIN(recall_targets.recalled_at,excluded.recalled_at)", -1, &statement, NULL) == SQLITE_OK) {
            DY778Bind(statement, 1, account); DY778Bind(statement, 2, conversation); DY778Bind(statement, 3, target);
            NSTimeInterval time = [record[@"createdAt"] doubleValue]; if (time <= 0) time = [record[@"recalledAt"] doubleValue];
            sqlite3_bind_double(statement, 4, time > 0 ? time : NSDate.date.timeIntervalSince1970); sqlite3_step(statement);
        }
        sqlite3_finalize(statement); statement = NULL;
    }
    const char *sql = "SELECT m.payload,m.recalled,m.recalled_at,m.key,t.recalled_at FROM messages m JOIN recall_targets t ON m.account=t.account AND m.conversation=t.conversation AND (m.message=t.message OR (m.server_id<>'' AND m.server_id=t.message)) WHERE m.account=? AND m.conversation=? AND m.recalled=0 AND m.hidden_notice=0";
    NSMutableArray *matches = [NSMutableArray array];
    if (sqlite3_prepare_v2(self.database, sql, -1, &statement, NULL) == SQLITE_OK) {
        DY778Bind(statement, 1, account); DY778Bind(statement, 2, conversation);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            NSMutableDictionary *linked = [DY778DecodeRow(statement) mutableCopy];
            if (linked) { linked[@"recalled"] = @YES; linked[@"recalledAt"] = @(sqlite3_column_double(statement, 4)); [matches addObject:linked]; }
        }
    }
    sqlite3_finalize(statement);
    for (NSDictionary *linked in matches) {
        statement = NULL;
        if (sqlite3_prepare_v2(self.database, "UPDATE messages SET recalled=1,recalled_at=? WHERE key=? AND recalled=0", -1, &statement, NULL) == SQLITE_OK) {
            sqlite3_bind_double(statement, 1, [linked[@"recalledAt"] doubleValue]); DY778Bind(statement, 2, linked[@"key"]);
            if (sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(self.database) > 0) {
                @synchronized(self) { [self.cache removeObjectForKey:linked[@"key"]]; [self.recalledKeys addObject:linked[@"key"]]; [self.archivedKeys addObject:linked[@"key"]]; }
                DY778PublishPersistedRecall(linked); DY778ScheduleRecallNotification();
            }
        }
        sqlite3_finalize(statement);
    }
}
- (void)removeForAccount:(NSString *)account key:(NSString *)key completion:(dispatch_block_t)completion {
    if (!account.length) { if (completion) dispatch_async(dispatch_get_main_queue(), completion); return; }
    @synchronized (self) {
        NSMutableSet *requested = [NSMutableSet set];
        if (key.length) [requested addObject:key]; else [self.clearingAccounts addObject:account];
        for (NSString *pendingKey in self.pendingRecords) {
            NSDictionary *pending = self.pendingRecords[pendingKey];
            if ([pending[@"account"] isEqual:account] && (!key.length || [pendingKey isEqual:key])) [requested addObject:pendingKey];
        }
        [self.forgottenKeys unionSet:requested];
        for (NSString *pendingKey in requested) [self.pendingRecords removeObjectForKey:pendingKey];
        dispatch_async(self.queue, ^{
            BOOL removed = NO;
            NSMutableSet *keysToForget = [requested mutableCopy];
            if (self.database && sqlite3_exec(self.database, "BEGIN IMMEDIATE", NULL, NULL, NULL) == SQLITE_OK) {
                sqlite3_stmt *keys = NULL;
                BOOL valid = sqlite3_prepare_v2(self.database, "SELECT key FROM messages WHERE account=?", -1, &keys, NULL) == SQLITE_OK;
                if (valid) {
                    DY778Bind(keys, 1, account); int result;
                    while ((result = sqlite3_step(keys)) == SQLITE_ROW) {
                        NSString *storedKey = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(keys, 0)];
                        if (!key.length || [storedKey isEqual:key]) [keysToForget addObject:storedKey];
                    }
                    valid = result == SQLITE_DONE;
                }
                sqlite3_finalize(keys);
                sqlite3_stmt *tombstone = NULL;
                const char *forgetSQL = "INSERT OR REPLACE INTO forgotten(key,account,deleted) VALUES(?,?,?)";
                valid = valid && sqlite3_prepare_v2(self.database, forgetSQL, -1, &tombstone, NULL) == SQLITE_OK;
                if (valid) for (NSString *forgottenKey in keysToForget) {
                    sqlite3_reset(tombstone); sqlite3_clear_bindings(tombstone);
                    DY778Bind(tombstone, 1, forgottenKey); DY778Bind(tombstone, 2, account);
                    sqlite3_bind_double(tombstone, 3, NSDate.date.timeIntervalSince1970);
                    if (sqlite3_step(tombstone) != SQLITE_DONE) { valid = NO; break; }
                }
                sqlite3_finalize(tombstone);
                sqlite3_stmt *statement = NULL;
                const char *sql = key.length ? "DELETE FROM messages WHERE account=? AND key=?" : "DELETE FROM messages WHERE account=?";
                valid = valid && sqlite3_prepare_v2(self.database, sql, -1, &statement, NULL) == SQLITE_OK;
                if (valid) { DY778Bind(statement, 1, account); if (key.length) DY778Bind(statement, 2, key); valid = sqlite3_step(statement) == SQLITE_DONE; }
                sqlite3_finalize(statement);
                if (valid) removed = sqlite3_exec(self.database, "COMMIT", NULL, NULL, NULL) == SQLITE_OK;
                if (!removed) sqlite3_exec(self.database, "ROLLBACK", NULL, NULL, NULL);
            }
            @synchronized (self) {
                [self.clearingAccounts removeObject:account];
                if (removed) [self.forgottenKeys unionSet:keysToForget];
                if (!removed) { [self.forgottenKeys minusSet:requested]; self.status = @"删除未完成，请检查存储空间后重试"; }
                [self.cache removeAllObjects];
            }
            [self reloadKeys];
            if (removed) { [self pruneMedia]; sqlite3_exec(self.database, "PRAGMA wal_checkpoint(TRUNCATE)", NULL, NULL, NULL); }
            dispatch_async(dispatch_get_main_queue(), ^{
                DY778ScheduleRecallNotification();
                if (removed) { if (completion) completion(); }
                else DY778Toast(@"删除未完成，请稍后重试");
            });
        });
    }
}
- (NSDictionary *)profileForAccount:(NSString *)account conversation:(NSString *)conversation {
    NSString *key = DY778ConversationPreferenceKey(account, conversation);
    @synchronized(self) { return key ? self.profiles[key] : nil; }
}
- (void)updateProfile:(NSDictionary *)profile account:(NSString *)account conversation:(NSString *)conversation {
    NSString *key = DY778ConversationPreferenceKey(account, conversation); if (!key || !profile.count) return;
    @synchronized(self) {
        NSMutableDictionary *merged = [self.profiles[key] mutableCopy] ?: [NSMutableDictionary dictionary];
        for (NSString *field in profile) if ([profile[field] respondsToSelector:@selector(length)] ? [profile[field] length] > 0 : YES) merged[field] = profile[field];
        if ([merged isEqual:self.profiles[key]]) return;
        self.profiles[key] = [merged copy];
        dispatch_async(self.queue, ^{
            NSData *data = [NSJSONSerialization dataWithJSONObject:merged options:0 error:nil]; sqlite3_stmt *statement = NULL;
            if (self.database && data && sqlite3_prepare_v2(self.database, "INSERT INTO profiles(key,account,conversation,payload) VALUES(?,?,?,?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload", -1, &statement, NULL) == SQLITE_OK) {
                DY778Bind(statement, 1, key); DY778Bind(statement, 2, account); DY778Bind(statement, 3, conversation);
                sqlite3_bind_blob(statement, 4, data.bytes, (int)data.length, SQLITE_TRANSIENT); sqlite3_step(statement);
            }
            sqlite3_finalize(statement);
        });
    }
}
- (void)conversationSummaries:(NSString *)account completion:(void (^)(NSArray *))completion {
    dispatch_async(self.queue, ^{
        NSMutableArray *result = [NSMutableArray array]; sqlite3_stmt *statement = NULL;
        const char *sql = "SELECT conversation,COUNT(*),MAX(recalled_at),payload FROM messages WHERE account=? AND recalled=1 AND hidden_notice=0 GROUP BY conversation ORDER BY MAX(recalled_at) DESC";
        if (self.database && account.length && sqlite3_prepare_v2(self.database, sql, -1, &statement, NULL) == SQLITE_OK) {
            DY778Bind(statement, 1, account);
            while (sqlite3_step(statement) == SQLITE_ROW) {
                NSString *conversation = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)];
                NSData *data = [NSData dataWithBytes:sqlite3_column_blob(statement, 3) length:sqlite3_column_bytes(statement, 3)];
                NSDictionary *record = DY778RecallEnrichRecord([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
                NSDictionary *profile = [self profileForAccount:account conversation:conversation] ?: @{};
                NSString *name = [record[@"conversationName"] length] ? record[@"conversationName"] : ([record[@"senderName"] length] ? record[@"senderName"] : profile[@"name"]);
                BOOL hasName = name.length > 0;
                if (!name.length) name = [NSString stringWithFormat:@"%@ · %@", [profile[@"group"] boolValue] ? @"群聊" : @"联系人", [record[@"sender"] length] ? record[@"sender"] : conversation];
                NSString *avatar = [record[@"conversationAvatar"] length] ? record[@"conversationAvatar"] : ([record[@"senderAvatar"] length] ? record[@"senderAvatar"] : profile[@"avatar"]);
                [result addObject:@{@"conversation": conversation, @"account": account, @"sender": record[@"sender"] ?: @"", @"hasName": @(hasName), @"name": name, @"avatar": avatar ?: @"",
                    @"group": profile[@"group"] ?: @NO, @"count": @(sqlite3_column_int64(statement, 1)), @"time": @(sqlite3_column_double(statement, 2)), @"summary": DY778RecordSummary(record ?: @{})}];
            }
        }
        sqlite3_finalize(statement); dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(result); });
    });
}
- (void)recordsForAccount:(NSString *)account conversation:(NSString *)conversation offset:(NSUInteger)offset completion:(void (^)(NSArray *))completion {
    dispatch_async(self.queue, ^{
        NSMutableArray *records = [NSMutableArray array]; sqlite3_stmt *statement = NULL;
        const char *sql = "SELECT payload,recalled,recalled_at FROM messages WHERE account=? AND conversation=? AND recalled=1 AND hidden_notice=0 ORDER BY recalled_at DESC,key DESC LIMIT 100 OFFSET ?";
        if (self.database && account.length && conversation.length && sqlite3_prepare_v2(self.database, sql, -1, &statement, NULL) == SQLITE_OK) {
            DY778Bind(statement, 1, account); DY778Bind(statement, 2, conversation); sqlite3_bind_int64(statement, 3, (sqlite3_int64)offset);
            while (sqlite3_step(statement) == SQLITE_ROW) { NSDictionary *record = DY778DecodeRow(statement); if (record) [records addObject:record]; }
        }
        sqlite3_finalize(statement); dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(records); });
    });
}
- (void)removeConversation:(NSString *)conversation account:(NSString *)account completion:(dispatch_block_t)completion {
    if (!conversation.length || !account.length) return;
    dispatch_async(self.queue, ^{
        NSMutableSet *keys = [NSMutableSet set]; sqlite3_stmt *statement = NULL;
        if (self.database && sqlite3_prepare_v2(self.database, "SELECT key FROM messages WHERE account=? AND conversation=?", -1, &statement, NULL) == SQLITE_OK) {
            DY778Bind(statement, 1, account); DY778Bind(statement, 2, conversation);
            while (sqlite3_step(statement) == SQLITE_ROW) [keys addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)]];
        }
        sqlite3_finalize(statement);
        @synchronized(self) {
            for (NSString *key in self.pendingRecords) if ([self.pendingRecords[key][@"account"] isEqual:account] && [self.pendingRecords[key][@"conversation"] isEqual:conversation]) [keys addObject:key];
            [self.forgottenKeys unionSet:keys];
            for (NSString *key in keys) [self.pendingRecords removeObjectForKey:key];
        }
        BOOL valid = self.database && sqlite3_exec(self.database, "BEGIN IMMEDIATE", NULL, NULL, NULL) == SQLITE_OK;
        if (valid) {
            sqlite3_stmt *forget = NULL;
            valid = sqlite3_prepare_v2(self.database, "INSERT OR REPLACE INTO forgotten(key,account,deleted) VALUES(?,?,?)", -1, &forget, NULL) == SQLITE_OK;
            if (valid) for (NSString *key in keys) {
                sqlite3_reset(forget); sqlite3_clear_bindings(forget); DY778Bind(forget, 1, key); DY778Bind(forget, 2, account); sqlite3_bind_double(forget, 3, NSDate.date.timeIntervalSince1970);
                if (sqlite3_step(forget) != SQLITE_DONE) { valid = NO; break; }
            }
            sqlite3_finalize(forget); statement = NULL;
            if (valid) valid = sqlite3_prepare_v2(self.database, "DELETE FROM messages WHERE account=? AND conversation=?", -1, &statement, NULL) == SQLITE_OK;
            if (valid) { DY778Bind(statement, 1, account); DY778Bind(statement, 2, conversation); valid = sqlite3_step(statement) == SQLITE_DONE; }
            sqlite3_finalize(statement);
            if (valid) valid = sqlite3_exec(self.database, "COMMIT", NULL, NULL, NULL) == SQLITE_OK;
            if (!valid) sqlite3_exec(self.database, "ROLLBACK", NULL, NULL, NULL);
        }
        @synchronized(self) { if (!valid) [self.forgottenKeys minusSet:keys]; [self.cache removeAllObjects]; }
        [self reloadKeys]; if (valid) [self pruneMedia];
        dispatch_async(dispatch_get_main_queue(), ^{ DY778ScheduleRecallNotification(); if (valid) { if (completion) completion(); } else DY778Toast(@"删除未完成，请重试"); });
    });
}
- (void)pruneMedia {
    if (!self.database || !self.root) return;
    NSMutableSet *live = [NSMutableSet set];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(self.database, "SELECT key FROM messages", -1, &statement, NULL) == SQLITE_OK)
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const unsigned char *key = sqlite3_column_text(statement, 0);
            if (key) [live addObject:DY778Hash([NSString stringWithUTF8String:(const char *)key])];
        }
    sqlite3_finalize(statement);
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *mediaRoot = [self.root URLByAppendingPathComponent:@"Media" isDirectory:YES];
    NSArray *folders = [manager contentsOfDirectoryAtURL:mediaRoot includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil];
    for (NSURL *folder in folders) if (![live containsObject:folder.lastPathComponent]) [manager removeItemAtURL:folder error:nil];

}
- (void)maintenance {
    if (!dispatch_get_specific(DY778StoreQueueKey)) { dispatch_async(self.queue, ^{ [self maintenance]; }); return; }
    if (!self.database) return;
    self.lastMaintenance = NSDate.date.timeIntervalSince1970;
    double days = MAX(0, DY778Number(@"recall.retentionDays"));
    int limit = (int)MAX(0, DY778Number(@"recall.maxRecords"));
    sqlite3_stmt *statement = NULL;
    NSMutableSet *expired = [NSMutableSet set];
    if (days > 0 && sqlite3_prepare_v2(self.database, "SELECT key FROM messages WHERE CASE WHEN recalled=1 THEN recalled_at ELSE seen END<?", -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_double(statement, 1, NSDate.date.timeIntervalSince1970 - days * 86400);
        while (sqlite3_step(statement) == SQLITE_ROW) [expired addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)]];
    }
    sqlite3_finalize(statement); statement = NULL;
    if (days > 0 && sqlite3_prepare_v2(self.database, "DELETE FROM messages WHERE CASE WHEN recalled=1 THEN recalled_at ELSE seen END<?", -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_double(statement, 1, NSDate.date.timeIntervalSince1970 - days * 86400); sqlite3_step(statement);
    }
    sqlite3_finalize(statement);
    statement = NULL;
    if (limit > 0 && sqlite3_prepare_v2(self.database, "SELECT key FROM (SELECT key,ROW_NUMBER() OVER(PARTITION BY account ORDER BY recalled DESC,seen DESC) AS rn FROM messages) WHERE rn>?", -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_int(statement, 1, limit);
        while (sqlite3_step(statement) == SQLITE_ROW) [expired addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)]];
    }
    sqlite3_finalize(statement); statement = NULL;
    const char *prune = "DELETE FROM messages WHERE key IN (SELECT key FROM (SELECT key,ROW_NUMBER() OVER(PARTITION BY account ORDER BY recalled DESC,seen DESC) AS rn FROM messages) WHERE rn>?)";
    if (limit > 0 && sqlite3_prepare_v2(self.database, prune, -1, &statement, NULL) == SQLITE_OK) { sqlite3_bind_int(statement, 1, limit); sqlite3_step(statement); }
    sqlite3_finalize(statement);
    for (NSString *key in [expired copy]) if ([self databaseRecordForKey:key]) [expired removeObject:key];
    DY778InvalidateRecallSnapshots([expired copy]);
    [self.cache removeAllObjects]; [self reloadKeys]; [self pruneMedia];
}
@end
static void DY778RefreshRecallPolicy(void) {
    atomic_store_explicit(&DY778RecallSwitch, DY778Bool(@"recall.enabled"), memory_order_relaxed);
    dispatch_async(DY778ObservationQueue(), ^{
        NSString *activeAccount = DY778CurrentAccountID(); BOOL changed = NO;
        for (DY778RecallFastState *state in DY778KnownMessageStates().allObjects) {
            BOOL allowed = !state.invalidated && [state.account isEqual:activeAccount] && DY778RecallEnabledForAccountConversation(state.account, state.conversation)
                && ![[DY778RecallStore shared] isForgotten:state.key];
            if (state.allowed != allowed) { state.allowed = allowed; changed = YES; }
        }
        if (changed) DY778ScheduleRecallNotification();
    });
}
static NSString *DY778FirstString(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) { NSString *value = DY778Identifier(DY778Read(object, key)); if (value.length && ![value isEqual:@"0"]) return value; }
    return @"";
}
static NSString *DY778RemoteURL(id value, NSUInteger depth) { return DY778AvatarURL(value); }
static NSDictionary *DY778Person(id person) {
    return person ? DY778ProfileFromUser(person) : @{};
}
static void DY778RememberConversation(id conversation, id peer, NSString *account) {
    NSString *identifier = DY778FirstString(conversation, @[@"conversationID", @"identifier"]); if (!identifier.length || !account.length) return;
    if (!peer) peer = DY778Read(conversation, @"peerUser");
    NSDictionary *person = DY778Person(peer); BOOL group = ![person[@"uid"] length] && !DY778FirstString(conversation, @[@"peerUserID"]).length;
    NSString *name = group ? DY778FirstString(conversation, @[@"name", @"alias"]) : person[@"name"];
    if (!name.length) name = DY778FirstString(conversation, @[@"alias", @"name"]);
    NSString *avatar = group ? DY778RemoteURL(DY778Read(conversation, @"avatar") ?: DY778Read(conversation, @"icon"), 0) : person[@"avatar"];
    [[DY778RecallStore shared] updateProfile:@{@"name": name ?: @"", @"avatar": avatar ?: @"", @"group": @(group)} account:account conversation:identifier];
}
static void DY778AddSharedURL(NSMutableArray *media, id value, NSString *kind, NSString *name) {
    for (NSString *url in DY778AvatarURLs(value)) {
        BOOL found = NO; for (NSDictionary *item in media) if ([item[@"remoteURL"] isEqual:url]) { found = YES; break; }
        if (found) continue;
        BOOL cover = [name containsString:@"封面"];
        [media addObject:@{@"kind": kind, @"name": name, @"remoteURL": url, @"shared": @YES, @"cover": @(cover), @"role": cover ? @"cover" : kind,
            @"quality": @([name containsString:@"原始"] ? 700 : (cover ? 550 : 400))}];
    }
}
static void DY778AddMessageURL(NSMutableArray *media, id value, NSString *kind, NSString *name, BOOL sticker) {
    for (NSString *url in DY778AvatarURLs(value)) {
        BOOL found = NO; for (NSDictionary *item in media) if ([item[@"remoteURL"] isEqual:url]) { found = YES; break; }
        if (!found) [media addObject:@{@"kind": kind, @"name": name, @"remoteURL": url, @"sticker": @(sticker)}];
    }
}
static void DY778AddNativeMedia(NSMutableArray *media, id value, NSString *kind, NSString *field, BOOL encrypted, NSInteger quality) {
    for (NSString *url in DY778AvatarURLs(value)) [media addObject:@{@"kind": kind, @"name": [kind isEqual:@"audio"] ? @"语音" : @"图片", @"remoteURL": url,
        @"encrypted": @(encrypted), @"quality": @(quality), @"field": field, @"native": @YES}];
}
static void DY778AddLocalMedia(NSMutableArray *media, id value, NSString *kind) {
    NSString *path = DY778ResolvedMediaPath(value);
    if (!path.length || ![NSFileManager.defaultManager isReadableFileAtPath:path]) return;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (![attributes[NSFileType] isEqual:NSFileTypeRegular] || ![attributes[NSFileSize] unsignedLongLongValue]) return;
    for (NSDictionary *item in media) if ([item[@"sourcePath"] isEqual:path]) return;
    [media addObject:@{@"kind": kind, @"name": [kind isEqual:@"audio"] ? @"语音" : ([kind isEqual:@"video"] ? @"视频" : @"图片"), @"sourcePath": path, @"quality": @800, @"native": @YES}];
}
static NSString *DY778DownloadedPath(id download, id message) {
    NSString *identifier = DY778Identifier(DY778Read(download, @"messageID"));
    if (identifier.length) {
        BOOL matched = NO;
        for (NSString *field in @[@"identifier", @"messageID", @"serverMessageID"]) if ([identifier isEqual:DY778Identifier(DY778Read(message, field))]) { matched = YES; break; }
        if (!matched) return nil;
    }
    NSString *conversation = DY778Identifier(DY778Read(download, @"conversationID"));
    NSString *expected = DY778Identifier(DY778Read(message, @"belongingConversationIdentifier")) ?: DY778Identifier(DY778Read(message, @"conversationID"));
    if (conversation.length && ![conversation isEqual:expected]) return nil;
    return DY778Read(download, @"localFilePath");
}
static id DY778CachedAweme(NSString *identifier) {
    Class cls = NSClassFromString(@"AWEIMFeedVideoCachePool"); SEL selector = NSSelectorFromString(@"getItemFromCacheWith:");
    Method method = class_getClassMethod(cls, selector); if (!method || method_getNumberOfArguments(method) != 3) return nil;
    char returned[16]={0}, argument[16]={0}; method_getReturnType(method, returned, sizeof(returned)); method_getArgumentType(method, 2, argument, sizeof(argument));
    if (returned[0] != '@' || argument[0] != '@') return nil;
    @try { return ((id (*)(id, SEL, id))objc_msgSend)(cls, selector, identifier); } @catch (__unused NSException *exception) { return nil; }
}
static void DY778ObserveMessageContextNow(id viewModel) {
    id message = DY778Read(viewModel, @"iesMessage"); id presentation = DY778Read(viewModel, @"message");
    if (!message || !DY778EvaluateMessagePolicy(message)) return;
    NSString *account = DY778MessageAccountID(message); id conversation = DY778Read(viewModel, @"conversation");
    DY778RememberConversation(conversation, nil, account);
    NSDictionary *sender = DY778Person(DY778Read(presentation, @"fromUser"));
    if ([sender[@"uid"] length] && ![sender[@"uid"] isEqual:DY778Identifier(DY778Read(message, @"sender"))]) sender = @{};
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    if ([sender[@"name"] length]) extra[@"senderName"] = sender[@"name"];
    if ([sender[@"avatar"] length]) { extra[@"senderAvatar"] = sender[@"avatar"]; extra[@"senderAvatarURLs"] = sender[@"avatarURLs"] ?: @[]; }
    if ([sender[@"remark"] length]) extra[@"senderRemark"] = sender[@"remark"];
    if ([sender[@"remark"] length]) extra[@"identityCaptured"] = @YES;
    NSMutableDictionary *share = [NSMutableDictionary dictionary]; NSMutableArray *media = [NSMutableArray array];
    NSMutableDictionary *card = [NSMutableDictionary dictionary];
    BOOL recallPresentation = [presentation isKindOfClass:NSClassFromString(@"AWEIMRecallMessage")];
    if (presentation) extra[@"presentationClass"] = NSStringFromClass([presentation class]);
    NSDictionary *existing = DY778FastState(message, NO).snapshot;
    if (recallPresentation && [DY778Read(message, @"messageType") longLongValue] == 40001 && ![existing[@"presentationClass"] length]) {
        objc_setAssociatedObject(message, &kDY778SystemNotice, @YES, OBJC_ASSOCIATION_RETAIN);
        id origin = DY778Read(presentation, @"recalledMsg");
        NSString *target = DY778FirstString(origin, @[@"messageID", @"serverMessageID"]);
        if (target.length) extra[@"recallTargetID"] = target;
    }
    if (recallPresentation && ![existing[@"available"] boolValue]) {
        id recalledOriginal = DY778Read(presentation, @"recalledMsg");
        id originalContent = DY778Read(recalledOriginal, @"getContentDict");
        if (DY778ContentAvailable(originalContent) && !DY778RecallContentIsNotice(originalContent)) {
            DY778FastState(message, YES).capturedContent = originalContent;
        } else if (DY778RecallContentIsNotice(DY778Read(message, @"content"))) objc_setAssociatedObject(message, &kDY778SystemNotice, @YES, OBJC_ASSOCIATION_RETAIN);
    }
    if (recallPresentation) {
        id original = DY778Read(presentation, @"recalledMsg");
        if (original && ![original isKindOfClass:NSClassFromString(@"AWEIMRecallMessage")]) presentation = original;
        if ([existing[@"presentationClass"] length]) extra[@"presentationClass"] = existing[@"presentationClass"];
        else if (presentation && presentation != DY778Read(viewModel, @"message")) extra[@"presentationClass"] = NSStringFromClass([presentation class]);
    }
    id nativeBody = DY778Read(presentation, @"getContentDict");
    if (!recallPresentation && [nativeBody isKindOfClass:NSDictionary.class]) {
        [media addObjectsFromArray:DY778RecallMediaFromContent(nativeBody)];
        NSDictionary *parsed = DY778RecallEnrichRecord(@{@"content": nativeBody, @"presentationClass": extra[@"presentationClass"] ?: @""});
        if ([parsed[@"card"] count]) [card addEntriesFromDictionary:parsed[@"card"]];
    }
    NSString *className = NSStringFromClass([presentation class]);
    BOOL sticker = [className containsString:@"Giphy"] || [className containsString:@"ShanMeng"];
    if (sticker) {
        card[@"kind"] = @"sticker"; card[@"title"] = DY778FirstString(presentation, @[@"giphyName", @"hintContent"]);
        DY778AddMessageURL(media, DY778Read(presentation, @"animateURL"), @"image", @"动态表情", YES);
        DY778AddMessageURL(media, DY778Read(presentation, @"giphyURL"), @"image", @"表情", YES);
        DY778AddMessageURL(media, DY778Read(presentation, @"displayIconURL"), @"image", @"表情预览", YES);
        DY778AddMessageURL(media, DY778Read(presentation, @"audioUrl"), @"audio", @"表情声音", YES);
        id results = DY778Read(presentation, @"randomInteractiveEmojiResultInfos");
        if ([results isKindOfClass:NSArray.class]) for (id result in results) {
            NSString *name = DY778FirstString(result, @[@"displayName"]);
            if (name.length) card[@"detail"] = name;
            DY778AddMessageURL(media, DY778Read(result, @"imageUrl"), @"image", name.length ? name : @"互动表情结果", YES);
        }
    }
    if ([presentation isKindOfClass:NSClassFromString(@"AWEIMShareGoodsMessage")]) {
        card[@"kind"] = @"goods"; card[@"title"] = DY778FirstString(presentation, @[@"title"]);
        card[@"detail"] = DY778FirstString(presentation, @[@"priceDesc"]);
        DY778AddSharedURL(media, DY778Read(presentation, @"iconURLModel"), @"image", @"商品图片");
    } else if ([presentation isKindOfClass:NSClassFromString(@"AWEIMShareLiveMessage")]) {
        card[@"kind"] = @"live"; card[@"title"] = DY778FirstString(presentation, @[@"roomDescription", @"pushDetail"]);
        card[@"author"] = DY778FirstString(presentation, @[@"roomOwnerName"]); card[@"id"] = DY778FirstString(presentation, @[@"roomID"]);
        DY778AddSharedURL(media, DY778Read(presentation, @"roomCoverURL"), @"image", @"直播封面");
    }
    id nativeContent = DY778Read(presentation, @"content");
    NSString *nativeKind = DY778RecallMessageKind(className);
    BOOL nativeEncrypted = [className containsString:@"Encrypt"] || DY778FirstString(nativeContent, @[@"resSecretKey", @"skey", @"tkey"]).length > 0;
    if (nativeKind.length) card[@"kind"] = nativeKind;
    if ([nativeKind isEqual:@"image"]) {
        NSArray *fields = @[@"resOriginUrlList", @"largeResourceUrl", @"resLargeUrlList", @"longResourceUrl", @"resLongUrlList", @"mediumResourceUrl", @"resMediumUrlList", @"resourceUrl", @"resThumbUrlList"];
        for (NSUInteger i = 0; i < fields.count; i++) DY778AddNativeMedia(media, DY778Read(nativeContent, fields[i]), @"image", fields[i], nativeEncrypted, 750 - (NSInteger)i * 50);
        for (NSString *field in @[@"cachedImageAttachmentFileAbsolutePath", @"imageAttachmentFileAbsolutePath"])
            DY778AddLocalMedia(media, DY778Read(viewModel, field), @"image");
        DY778AddLocalMedia(media, DY778DownloadedPath(DY778Read(viewModel, @"imageDownloadVM"), message), @"image");
    } else if ([nativeKind isEqual:@"audio"]) {
        DY778AddNativeMedia(media, DY778Read(nativeContent, @"resourceUrl"), @"audio", @"resourceUrl", nativeEncrypted, 600);
        DY778AddLocalMedia(media, DY778DownloadedPath(DY778Read(viewModel, @"downloadVM"), message), @"audio");
        NSString *transcript = DY778FirstString(presentation, @[@"audioText"]);
        if (transcript.length) card[@"transcript"] = transcript;
    }
    if ([nativeKind isEqual:@"video"]) {
        DY778AddLocalMedia(media, DY778DownloadedPath(DY778Read(viewModel, @"downloadVM"), message), @"video");
        id video = DY778Read(presentation, @"videoContent");
        BOOL encryptedCover = DY778FirstString(video, @[@"posterSKey"]).length > 0;
        DY778AddNativeMedia(media, DY778Read(video, @"posterResourceUrl"), @"image", @"posterResourceUrl", encryptedCover, 700);
    }
    NSString *itemID = DY778FirstString(presentation, @[@"itemId", @"awemeID", @"itemIDUsedForContentAvailableRefresh"]);
    NSString *title = DY778FirstString(presentation, @[@"contentTitle", @"awemeTitle", @"displayTitle"]);
    if (itemID.length && ![itemID isEqual:@"0"] && !nativeKind.length && ![@[@"goods", @"live", @"sticker"] containsObject:card[@"kind"] ?: @""]) {
        share[@"id"] = itemID; if (title.length) share[@"title"] = title;
        for (NSString *field in @[@"coverURL", @"videoCover", @"originCover"]) DY778AddSharedURL(media, DY778Read(presentation, field), @"image", [field isEqual:@"originCover"] ? @"作品原始封面" : @"作品封面");
        id aweme = DY778CachedAweme(itemID);
        if (aweme && [DY778FirstString(aweme, @[@"itemID", @"awemeID", @"aweme_id"]) isEqual:itemID]) {
            NSString *detail = DY778FirstString(aweme, @[@"descriptionString", @"desc"]); if (detail.length) share[@"title"] = detail;
            NSDictionary *author = DY778Person(DY778Read(aweme, @"author")); if ([author[@"name"] length]) share[@"author"] = author[@"name"];
            if ([author[@"uid"] length]) { share[@"authorID"] = author[@"uid"]; share[@"authorAvatarURLs"] = author[@"avatarURLs"] ?: @[]; }
            id video = DY778Read(aweme, @"video");
            DY778AddSharedURL(media, DY778Read(video, @"originCover"), @"image", @"作品原始封面");
            DY778AddSharedURL(media, DY778Read(video, @"coverURL"), @"image", @"作品封面");
            id images = DY778Read(aweme, @"images");
            if ([images isKindOfClass:NSArray.class]) { NSUInteger n=0; for (id image in images) DY778AddSharedURL(media, image, @"image", [NSString stringWithFormat:@"图集 · 第 %lu 张", (unsigned long)++n]); }
        }
        extra[@"share"] = share;
    }
    if (!recallPresentation) {
        NSString *comment = DY778FirstString(presentation, @[@"comment"]);
        id copyText = DY778Read(presentation, @"commentCopyText");
        if (!comment.length && [copyText isKindOfClass:NSAttributedString.class]) comment = [copyText string];
        BOOL transcript = NO;
        if (!comment.length && ([className containsString:@"Comment"] || DY778FirstString(presentation, @[@"commentID"]).length)) {
            comment = DY778FirstString(presentation, @[@"audioText"]); transcript = comment.length > 0;
        }
        NSDictionary *candidate = comment.length ? @{@"text": comment, @"author": DY778FirstString(presentation, @[@"commentUserName"]),
            @"id": DY778FirstString(presentation, @[@"commentID"]), @"authorID": DY778FirstString(presentation, @[@"commentSecUid"]), @"transcript": @(transcript)} : nil;
        NSDictionary *capturedComment = DY778MergeCapturedComment(DY778RecallCommentFromContent(DY778Read(message, @"content")), candidate);
        capturedComment = DY778MergeCapturedComment(capturedComment, DY778RecallCommentFromContent(nativeBody));
        if (capturedComment) extra[@"comment"] = capturedComment;
    }
    id quote = DY778Read(presentation, @"quoteReplyOriginMessage");
    NSString *quoteHint = DY778FirstString(presentation, @[@"quoteReplyMessageHint"]);
    id quoteBody = DY778Read(quote, @"getContentDict");
    if (quoteHint.length || [quoteBody isKindOfClass:NSDictionary.class]) extra[@"quote"] = @{@"text": quoteHint, @"content": [quoteBody isKindOfClass:NSDictionary.class] ? DY778ImmutableDictionary(quoteBody) : @{}, @"sender": DY778FirstString(presentation, @[@"quoteReplySenderUid", @"tempQuoteNickname"])};
    if (media.count) extra[@"media"] = media;
    if (card.count) extra[@"card"] = card;
    NSDictionary *previousExtra = objc_getAssociatedObject(message, &kDY778ExtraMessage);
    if (extra.count && ![extra isEqual:previousExtra]) {
        objc_setAssociatedObject(message, &kDY778ExtraMessage, [extra copy], OBJC_ASSOCIATION_RETAIN);
        objc_setAssociatedObject(message, &kDY778ObservedContent, nil, OBJC_ASSOCIATION_RETAIN);
    }
    DY778ObserveMessageNow(message);
}
void DY778ObserveMessageContext(id viewModel) {
    DY778ObserveEditContext(viewModel);
    if (!viewModel || !atomic_load_explicit(&DY778RecallSwitch, memory_order_relaxed)) return;
    DY778RecallFastState *state = DY778FastState(viewModel, YES);
    if (atomic_exchange_explicit(&state->queued, true, memory_order_acq_rel)) return;
    dispatch_async(DY778ObservationQueue(), ^{
        atomic_store_explicit(&state->queued, false, memory_order_release);
        DY778ObservationDepth++;
        @try { DY778ObserveMessageContextNow(viewModel); }
        @finally { DY778ObservationDepth--; }
    });
}
NSTimeInterval DY778MessageTimestamp(id value) {
    double time = [value isKindOfClass:NSDate.class] ? [value timeIntervalSince1970] : ([value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0);
    if (time > 100000000000000.0) time /= 1000000.0; else if (time > 100000000000.0) time /= 1000.0;
    return isfinite(time) && time > 0 && time < 4133980800.0 ? time : 0;
}
NSDictionary *DY778MessageIdentity(id message) {
    NSString *account = DY778MessageAccountID(message), *conversation = DY778Identifier(DY778Read(message, @"belongingConversationIdentifier"));
    if (!conversation.length) conversation = DY778Identifier(DY778Read(message, @"conversationID"));
    NSString *identifier = DY778Identifier(DY778Read(message, @"identifier")), *server = DY778Identifier(DY778Read(message, @"serverMessageID"));
    if (!identifier.length) identifier = server;
    NSString *key = DY778RecordKey(account, conversation, identifier); if (!key) return nil;
    return @{@"key": key, @"account": account, @"conversation": conversation, @"messageID": identifier, @"serverID": server ?: @"",
        @"sender": DY778Identifier(DY778Read(message, @"sender")) ?: @"", @"createdAt": @(DY778MessageTimestamp(DY778Read(message, @"serverCreatedAt") ?: DY778Read(message, @"createdAt")))};
}
static NSDictionary *DY778BuildSnapshot(id message, NSDictionary *content, BOOL recalled) {
    NSString *account = DY778MessageAccountID(message);
    NSString *conversation = DY778Identifier(DY778Read(message, @"belongingConversationIdentifier"));
    NSString *identifier = DY778Identifier(DY778Read(message, @"identifier"));
    if (!identifier.length) identifier = DY778Identifier(DY778Read(message, @"serverMessageID"));
    NSString *key = DY778KeyForMessage(message);
    if (!key || [[DY778RecallStore shared] isForgotten:key]) return nil;
    NSDictionary *old = objc_getAssociatedObject(message, &kDY778MessageSnapshot);
    if (![old[@"key"] isEqual:key]) old = nil;
    if (!old) old = [[DY778RecallStore shared] cachedRecord:key];
    if ([old[@"recalled"] boolValue] && [old[@"available"] boolValue]) content = old[@"content"];
    if (!DY778ContentAvailable(content) && [old[@"available"] boolValue]) content = old[@"content"];
    if (!DY778ContentAvailable(content)) {
        NSDictionary *stored = [[DY778RecallStore shared] cachedRecord:key];
        if ([stored[@"available"] boolValue]) { old = stored; content = stored[@"content"]; }
    }
    BOOL available = DY778ContentAvailable(content);
    NSDictionary *immutable = available ? DY778ImmutableDictionary(content) : @{};
    NSDate *created = DY778Read(message, @"serverCreatedAt") ?: DY778Read(message, @"createdAt");
    NSTimeInterval timestamp = DY778MessageTimestamp(created); if (timestamp <= 0) timestamp = [old[@"createdAt"] doubleValue];
    NSMutableDictionary *record = [@{@"key": key, @"account": account, @"conversation": conversation, @"messageID": identifier,
        @"serverID": DY778Identifier(DY778Read(message, @"serverMessageID")) ?: @"", @"sender": DY778Identifier(DY778Read(message, @"sender")) ?: @"",
        @"senderName": DY778Identifier(DY778Read(DY778Read(message, @"senderProfile"), @"senderNickName")) ?: @"",
        @"type": DY778Read(message, @"messageType") ?: @0, @"createdAt": @(timestamp), @"available": @(available && immutable != nil),
        @"content": immutable ?: @{}, @"recalled": @(recalled || [old[@"recalled"] boolValue]),
        @"recalledAt": [old[@"recalledAt"] doubleValue] > 0 ? old[@"recalledAt"] : (recalled ? @(NSDate.date.timeIntervalSince1970) : @0), @"media": DY778MessageMedia(message, content ?: @{})} mutableCopy];
    if (![record[@"media"] count] && [old[@"media"] count]) record[@"media"] = old[@"media"];
    NSDictionary *extra = objc_getAssociatedObject(message, &kDY778ExtraMessage);
    for (NSString *field in @[@"senderName", @"senderAvatar", @"senderAvatarURLs", @"senderRemark", @"identityCaptured", @"share", @"quote", @"comment", @"card", @"presentationClass", @"recallTargetID"]) if (extra[field] ?: old[field]) record[field] = extra[field] ?: old[field];
    NSDictionary *capturedComment = DY778MergeCapturedComment(DY778RecallCommentFromContent(content), extra[@"comment"]);
    capturedComment = DY778MergeCapturedComment(old[@"comment"], capturedComment);
    if (capturedComment) {
        NSMutableDictionary *savedComment = [capturedComment mutableCopy];
        if (![old[@"comment"][@"text"] length] && ![savedComment[@"capturedAt"] doubleValue]) savedComment[@"capturedAt"] = @(NSDate.date.timeIntervalSince1970);
        record[@"comment"] = savedComment;
    }
    if ([old[@"available"] boolValue] && [old[@"presentationClass"] length] && ![old[@"presentationClass"] isEqual:@"AWEIMRecallMessage"]) record[@"presentationClass"] = old[@"presentationClass"];
    NSDictionary *profile = [[DY778RecallStore shared] profileForAccount:account conversation:conversation];
    record[@"conversationName"] = profile[@"name"] ?: old[@"conversationName"] ?: @"";
    record[@"conversationAvatar"] = profile[@"avatar"] ?: old[@"conversationAvatar"] ?: @"";
    if ([old[@"recalled"] boolValue] && [old[@"identityCaptured"] boolValue]) for (NSString *field in @[@"senderName", @"senderAvatar", @"senderRemark", @"conversationName", @"conversationAvatar"]) if ([old[field] length]) record[field] = old[field];
    if (![record[@"senderAvatar"] length]) record[@"senderAvatar"] = DY778AvatarURL(DY778Read(DY778Read(message, @"senderProfile"), @"senderPortrait"));
    NSMutableArray *combinedMedia = [record[@"media"] mutableCopy];
    if ([old[@"recalled"] boolValue] || [old[@"content"] isEqual:record[@"content"]]) [combinedMedia addObjectsFromArray:old[@"media"] ?: @[]];
    [combinedMedia addObjectsFromArray:extra[@"media"] ?: @[]];
    record[@"media"] = combinedMedia;
    if ([objc_getAssociatedObject(message, &kDY778SystemNotice) boolValue]) record[@"systemRecallNotice"] = @YES;
    record = [DY778RecallEnrichRecord(record) mutableCopy];
    record[@"summary"] = DY778RecordSummary(record);
    return record;
}

static BOOL DY778RecordEquivalent(NSDictionary *old, NSDictionary *record) {
    if (!old || !record) return NO;
    for (NSString *field in @[@"key", @"content", @"available", @"recalled", @"senderName", @"senderAvatar", @"conversationName", @"conversationAvatar", @"share", @"quote", @"comment", @"card", @"systemRecallNotice"]) {
        id a = old[field], b = record[field]; if (a != b && ![a isEqual:b]) return NO;
    }
    NSArray *a = old[@"media"] ?: @[], *b = record[@"media"] ?: @[];
    if (a.count != b.count) return NO;
    for (NSUInteger i = 0; i < a.count; i++) for (NSString *field in @[@"sourcePath", @"remoteURL", @"kind", @"encrypted", @"cover", @"quality"])
        if (a[i][field] != b[i][field] && ![a[i][field] isEqual:b[i][field]]) return NO;
    return YES;
}
static void DY778RememberMessage(id message, NSDictionary *content, BOOL recalled) {
    if (!message || !DY778RecallEnabledForMessage(message) || !DY778IncomingMessage(message)) return;
    NSDictionary *record = DY778BuildSnapshot(message, content, recalled);
    if (!record) return;
    NSDictionary *old = objc_getAssociatedObject(message, &kDY778MessageSnapshot) ?: [[DY778RecallStore shared] cachedRecord:record[@"key"]];
    BOOL initialSnapshot = !DY778FastState(message, NO).snapshot;
    DY778RecallDecision decision = DY778RecallDecide(YES, old != nil, DY778RecordEquivalent(old, record),
        [old[@"recalled"] boolValue], [record[@"recalled"] boolValue], [old[@"available"] boolValue], [record[@"available"] boolValue]);
    objc_setAssociatedObject(message, &kDY778MessageSnapshot, record, OBJC_ASSOCIATION_RETAIN);
    DY778RecallFastState *state = DY778FastState(message, YES); DY778PublishRecallSnapshot(state, record);
    if ([record[@"recalled"] boolValue]) state.recalled = YES;
    if (!state.profileRequested && ![record[@"identityCaptured"] boolValue] && [record[@"sender"] length]) {
        state.profileRequested = YES; __weak id weakMessage = message; NSString *key = record[@"key"];
        DY778GetLocalUserProfile(record[@"account"], record[@"sender"], ^(NSDictionary *profile) {
            if (![profile[@"name"] length] && ![profile[@"avatar"] length]) return;
            dispatch_async(DY778ObservationQueue(), ^{
                id live = weakMessage; DY778RecallFastState *current = DY778FastState(live, NO);
                if (!live || !DY778FastAllowed(current) || ![key isEqual:current.key] || [[DY778RecallStore shared] isForgotten:key]) return;
                NSDictionary *prior = current.snapshot;
                if ([prior[@"recalled"] boolValue] && [prior[@"identityCaptured"] boolValue]) return;
                NSMutableDictionary *updated = [prior mutableCopy]; if (!updated) return;
                if ([profile[@"name"] length]) updated[@"senderName"] = profile[@"name"];
                if ([profile[@"avatar"] length]) { updated[@"senderAvatar"] = profile[@"avatar"]; updated[@"senderAvatarURLs"] = profile[@"avatarURLs"] ?: @[]; }
                if ([profile[@"remark"] length]) updated[@"senderRemark"] = profile[@"remark"];
                updated[@"identityCaptured"] = @YES;
                NSDictionary *conversation = [[DY778RecallStore shared] profileForAccount:prior[@"account"] conversation:prior[@"conversation"]];
                if (conversation && ![conversation[@"group"] boolValue]) {
                    if ([profile[@"name"] length]) updated[@"conversationName"] = profile[@"name"];
                    if ([profile[@"avatar"] length]) updated[@"conversationAvatar"] = profile[@"avatar"];
                    [[DY778RecallStore shared] updateProfile:profile account:prior[@"account"] conversation:prior[@"conversation"]];
                }
                objc_setAssociatedObject(live, &kDY778MessageSnapshot, updated, OBJC_ASSOCIATION_RETAIN); DY778PublishRecallSnapshot(current, updated);
                [[DY778RecallStore shared] save:updated key:key recalled:[updated[@"recalled"] boolValue]]; DY778ScheduleRecallNotification();
            });
        });
    }
    if (!decision.persist) { if (initialSnapshot) DY778ScheduleRecallNotification(); return; }
    NSMutableDictionary *toSave = [record mutableCopy];
    if ([objc_getAssociatedObject(message, &kDY778LiveRecall) boolValue] && recalled) { toSave[@"_liveRecall"] = @YES; objc_setAssociatedObject(message, &kDY778LiveRecall, nil, OBJC_ASSOCIATION_RETAIN); }
    [[DY778RecallStore shared] save:toSave key:record[@"key"] recalled:recalled];
    if (decision.notify || initialSnapshot || ([record[@"recalled"] boolValue] && !DY778RecordEquivalent(old, record))) DY778ScheduleRecallNotification();
}
static void DY778ObserveMessageNow(id message) {
    if (!message || [objc_getAssociatedObject(message, &kDY778MessageGuard) boolValue]) return;
    DY778RecallFastState *current = DY778FastState(message, NO);
    if (current && atomic_load_explicit(&current->nativeMutations, memory_order_acquire)) return;
    objc_setAssociatedObject(message, &kDY778MessageGuard, @YES, OBJC_ASSOCIATION_RETAIN);
    @try {
        DY778RecallFastState *state = DY778FastState(message, YES);
        BOOL previouslyAllowed = state.allowed;
        state.allowed = !state.invalidated && DY778EvaluateMessagePolicy(message) && DY778IncomingMessage(message);
        if (!state.allowed) { if (previouslyAllowed) DY778ScheduleRecallNotification(); return; }
        NSString *key = DY778KeyForMessage(message); state.key = key; state.message = message; state.serverID = DY778Identifier(DY778Read(message, @"serverMessageID"));
        state.account = DY778MessageAccountID(message);
        state.conversation = DY778Identifier(DY778Read(message, @"belongingConversationIdentifier")) ?: DY778Identifier(DY778Read(message, @"conversationID"));
        [DY778KnownMessageStates() addObject:state];
        if ([[DY778RecallStore shared] isForgotten:key]) { state.allowed = NO; return; }
        NSDictionary *rawContent = DY778Read(message, @"content");
        NSDictionary *content = state.capturedContent ?: rawContent;
        BOOL rawRecalled = DY778RawRecalled(message); state.rawRecalled = rawRecalled;
        if (rawContent) state.rawContent = rawContent;
        BOOL recalled = [objc_getAssociatedObject(message, &kDY778MessageRecalled) boolValue] || rawRecalled || [[DY778RecallStore shared] isRecalled:key];
        if (recalled) state.recalled = YES;
        if (recalled && !DY778ContentAvailable(content)) content = DY778Read(message, @"recalledContent");
        NSNumber *hydration = objc_getAssociatedObject(message, &kDY778HydrationRequested);
        if (!key.length || (hydration && !hydration.boolValue)) return;
        if (!hydration) {
            // 写入前先等存档身份解析完成。同一条服务端消息的多个
            // SDK 对象在重启后不得各自创建独立的存档行。
            objc_setAssociatedObject(message, &kDY778HydrationRequested, @NO, OBJC_ASSOCIATION_RETAIN);
            NSDictionary *provisional = DY778BuildSnapshot(message, content, recalled);
            if (provisional) { DY778PublishRecallSnapshot(state, provisional); if (recalled) DY778ScheduleRecallNotification(); }
            NSString *legacyKey = DY778RecordKey(state.account, state.conversation, DY778Identifier(DY778Read(message, @"identifier")));
            __weak id weakMessage = message;
            [[DY778RecallStore shared] loadRecordForKey:key account:state.account conversation:state.conversation server:state.serverID legacyKey:legacyKey completion:^(NSDictionary *stored) {
                dispatch_async(DY778ObservationQueue(), ^{
                    id live = weakMessage; DY778RecallFastState *currentState = DY778FastState(live, NO);
                    if (!live || ![key isEqual:currentState.key]) return;
                    objc_setAssociatedObject(live, &kDY778HydrationRequested, @YES, OBJC_ASSOCIATION_RETAIN);
                    if ([[DY778RecallStore shared] isForgotten:key] || [[DY778RecallStore shared] isForgotten:legacyKey]) { currentState.allowed = NO; return; }
                    NSString *resolvedKey = stored[@"key"] ?: key;
                    objc_setAssociatedObject(live, &kDY778CanonicalMessageKey, @{@"account": currentState.account, @"conversation": currentState.conversation, @"key": resolvedKey}, OBJC_ASSOCIATION_RETAIN);
                    currentState.key = resolvedKey;
                    NSDictionary *current = currentState.snapshot;
                    if (stored && DY778RecallShouldHydrate([stored[@"available"] boolValue], [current[@"available"] boolValue], [stored[@"recalled"] boolValue], currentState.recalled)) {
                        NSMutableDictionary *restored = [stored mutableCopy];
                        BOOL wasRecalled = currentState.recalled || [stored[@"recalled"] boolValue]; restored[@"recalled"] = @(wasRecalled);
                        if ([restored[@"recalledAt"] doubleValue] <= 0 && [current[@"recalledAt"] doubleValue] > 0) restored[@"recalledAt"] = current[@"recalledAt"];
                        for (NSString *field in @[@"senderName", @"senderAvatar", @"conversationName", @"conversationAvatar"]) if (![restored[field] length] && [current[field] length]) restored[field] = current[field];
                        objc_setAssociatedObject(live, &kDY778MessageSnapshot, restored, OBJC_ASSOCIATION_RETAIN);
                        if (wasRecalled) currentState.capturedContent = restored[@"content"];
                        DY778PublishRecallSnapshot(currentState, restored);
                        if (wasRecalled) { currentState.recalled = YES; objc_setAssociatedObject(live, &kDY778MessageRecalled, @YES, OBJC_ASSOCIATION_RETAIN); }
                        DY778ScheduleRecallNotification();
                    }
                    objc_setAssociatedObject(live, &kDY778ObservedContent, nil, OBJC_ASSOCIATION_RETAIN);
                    DY778ObserveMessage(live);
                });
            }];
            return;
        }
        NSDictionary *previous = objc_getAssociatedObject(message, &kDY778MessageSnapshot);
        id seenContent = objc_getAssociatedObject(message, &kDY778ObservedContent);
        if (content && seenContent == content && [previous[@"recalled"] boolValue] == recalled && [previous[@"key"] isEqual:key]) return;
        if (content) objc_setAssociatedObject(message, &kDY778ObservedContent, content, OBJC_ASSOCIATION_RETAIN);
        DY778RememberMessage(message, content, recalled);
    } @finally { objc_setAssociatedObject(message, &kDY778MessageGuard, nil, OBJC_ASSOCIATION_RETAIN); }
}
void DY778ObserveMessage(id message) {
    DY778RecallFastState *editState = DY778FastState(message, NO);
    if (editState && atomic_load_explicit(&editState->nativeMutations, memory_order_acquire)) return;
    DY778ObserveEditedMessage(message, editState.rawContent, editState.editInfo);
    if (!message || !atomic_load_explicit(&DY778RecallSwitch, memory_order_relaxed)) return;
    DY778RecallFastState *state = DY778FastState(message, YES);
    if (atomic_exchange_explicit(&state->queued, true, memory_order_acq_rel)) return;
    dispatch_async(DY778ObservationQueue(), ^{
        atomic_store_explicit(&state->queued, false, memory_order_release);
        if (atomic_load_explicit(&state->nativeMutations, memory_order_acquire)) return;
        DY778ObservationDepth++;
        @try { DY778ObserveMessageNow(message); }
        @finally { DY778ObservationDepth--; }
    });
}
BOOL DY778MessageWasRecalled(id message) {
    DY778RecallFastState *state = DY778FastState(message, NO);
    return DY778FastAllowed(state) && ![state.snapshot[@"systemRecallNotice"] boolValue] && (state.recalled || [state.snapshot[@"recalled"] boolValue]);
}
NSDictionary *DY778RecallRecordForMessage(id message) {
    DY778RecallFastState *state = DY778FastState(message, NO);
    return DY778FastAllowed(state) ? state.snapshot : nil;
}
static void (*DY778OriginalSetEditInfo)(id, SEL, id);
static void DY778SetEditInfoHook(id message, SEL selector, id info) {
    if (DY778RecallFrameContains(DY778RecallFrames, (__bridge const void *)message, DY778RecallWriteEdit)) return;
    DY778RecallFrame frame = {(__bridge const void *)message, DY778RecallWriteEdit, DY778RecallFrames}; DY778RecallFrames = &frame;
    DY778RecallFastState *state = DY778FastState(message, DY778EditCaptureEnabled());
    if (state) atomic_fetch_add_explicit(&state->nativeMutations, 1, memory_order_acq_rel);
    @try { if (state) state.editInfo = DY778EditInfoSnapshot(info) ?: @{}; DY778OriginalSetEditInfo(message, selector, info); }
    @finally { if (state) atomic_fetch_sub_explicit(&state->nativeMutations, 1, memory_order_release); DY778RecallFrames = frame.previous; }
    DY778ObserveMessage(message);
}
static void DY778SetContentHook(id message, SEL selector, id content) {
    if (DY778RecallFrameContains(DY778RecallFrames, (__bridge const void *)message, DY778RecallWriteContent)) return;
    DY778RecallFrame frame = {(__bridge const void *)message, DY778RecallWriteContent, DY778RecallFrames}; DY778RecallFrames = &frame;
    DY778RecallFastState *mutation = DY778FastState(message, atomic_load_explicit(&DY778RecallSwitch, memory_order_relaxed) || DY778EditCaptureEnabled());
    if (mutation) atomic_fetch_add_explicit(&mutation->nativeMutations, 1, memory_order_acq_rel);
    @try {
        DY778RecallFastState *state = DY778FastState(message, atomic_load_explicit(&DY778RecallSwitch, memory_order_relaxed) || DY778EditCaptureEnabled());
        if (state) {
            state.rawContent = [content isKindOfClass:NSDictionary.class] ? content : nil;
            if (DY778ContentAvailable(content)) state.capturedContent = content;
            else if ([content isKindOfClass:NSDictionary.class] && [content[@"text"] isEqual:@"Recall Content Hided"]) {
                NSDictionary *prior = state.snapshot;
                if (state.allowed && ![objc_getAssociatedObject(message, &kDY778SuppressLive) boolValue] && prior && !state.recalled && [prior[@"available"] boolValue]) objc_setAssociatedObject(message, &kDY778LiveRecall, @YES, OBJC_ASSOCIATION_RETAIN);
                state.recalled = YES;
                objc_setAssociatedObject(message, &kDY778MessageRecalled, @YES, OBJC_ASSOCIATION_RETAIN);
            }
        }
        DY778OriginalSetContent(message, selector, content);
    } @finally { if (mutation) atomic_fetch_sub_explicit(&mutation->nativeMutations, 1, memory_order_release); DY778RecallFrames = frame.previous; }
    DY778ObserveMessage(message);
}
static id DY778ContentHook(id message, SEL selector) {
    DY778RecallFastState *state = DY778FastState(message, NO);
    if (state && DY778RecallFrameIsMutating(DY778RecallFrames, (__bridge const void *)message)) return state.rawContent;
    if (DY778RecallFrameContains(DY778RecallFrames, (__bridge const void *)message, DY778RecallReadContent)) return state.rawContent;
    DY778RecallFrame frame = {(__bridge const void *)message, DY778RecallReadContent, DY778RecallFrames}; DY778RecallFrames = &frame;
    @try {
        NSDictionary *record = state.snapshot;
        if (!DY778ObservationDepth && DY778FastAllowed(state) && state.recalled && [record[@"available"] boolValue]) return record[@"content"];
        return DY778OriginalContent(message, selector);
    } @finally { DY778RecallFrames = frame.previous; }
}
static void DY778SetRecalledHook(id message, SEL selector, BOOL recalled) {
    if (DY778RecallFrameContains(DY778RecallFrames, (__bridge const void *)message, DY778RecallWriteFlag)) return;
    DY778RecallFrame frame = {(__bridge const void *)message, DY778RecallWriteFlag, DY778RecallFrames}; DY778RecallFrames = &frame;
    DY778RecallFastState *mutation = DY778FastState(message, atomic_load_explicit(&DY778RecallSwitch, memory_order_relaxed) || DY778EditCaptureEnabled());
    if (mutation) atomic_fetch_add_explicit(&mutation->nativeMutations, 1, memory_order_acq_rel);
    @try {
        DY778RecallFastState *state = DY778FastState(message, atomic_load_explicit(&DY778RecallSwitch, memory_order_relaxed) || DY778EditCaptureEnabled());
        state.rawRecalled = recalled;
        if (recalled && state) {
            NSDictionary *prior = state.snapshot;
            if (state.allowed && ![objc_getAssociatedObject(message, &kDY778SuppressLive) boolValue] && prior && !state.recalled && ![prior[@"recalled"] boolValue]) objc_setAssociatedObject(message, &kDY778LiveRecall, @YES, OBJC_ASSOCIATION_RETAIN);
            state.recalled = YES; objc_setAssociatedObject(message, &kDY778MessageRecalled, @YES, OBJC_ASSOCIATION_RETAIN);
        }
        DY778OriginalSetRecalled(message, selector, recalled);
    } @finally { if (mutation) atomic_fetch_sub_explicit(&mutation->nativeMutations, 1, memory_order_release); DY778RecallFrames = frame.previous; }
    DY778ObserveMessage(message);
}
static BOOL DY778RecalledHook(id message, SEL selector) {
    DY778RecallFastState *state = DY778FastState(message, NO);
    if (state && DY778RecallFrameIsMutating(DY778RecallFrames, (__bridge const void *)message)) return state.rawRecalled;
    if (DY778RecallFrameContains(DY778RecallFrames, (__bridge const void *)message, DY778RecallReadFlag)) return state.rawRecalled;
    DY778RecallFrame frame = {(__bridge const void *)message, DY778RecallReadFlag, DY778RecallFrames}; DY778RecallFrames = &frame;
    @try {
        if (!DY778ObservationDepth && DY778FastAllowed(state) && state.recalled && [state.snapshot[@"available"] boolValue]) return NO;
        return DY778OriginalRecalled(message, selector);
    } @finally { DY778RecallFrames = frame.previous; }
}
static void DY778RecalledContentHook(id message, SEL selector, id content) {
    if (DY778RecallFrameContains(DY778RecallFrames, (__bridge const void *)message, DY778RecallWriteOriginal)) return;
    DY778RecallFrame frame = {(__bridge const void *)message, DY778RecallWriteOriginal, DY778RecallFrames}; DY778RecallFrames = &frame;
    DY778RecallFastState *mutation = DY778FastState(message, atomic_load_explicit(&DY778RecallSwitch, memory_order_relaxed) || DY778EditCaptureEnabled());
    if (mutation) atomic_fetch_add_explicit(&mutation->nativeMutations, 1, memory_order_acq_rel);
    @try {
        DY778RecallFastState *state = DY778FastState(message, atomic_load_explicit(&DY778RecallSwitch, memory_order_relaxed) || DY778EditCaptureEnabled());
        if (state && DY778ContentAvailable(content)) { state.capturedContent = content; state.recalled = YES; objc_setAssociatedObject(message, &kDY778MessageRecalled, @YES, OBJC_ASSOCIATION_RETAIN); }
        DY778OriginalSetRecalledContent(message, selector, content);
    } @finally { if (mutation) atomic_fetch_sub_explicit(&mutation->nativeMutations, 1, memory_order_release); DY778RecallFrames = frame.previous; }
    DY778ObserveMessage(message);
}
static void DY778ApplyMessage(id message, SEL selector, id model, void (*original)(id,SEL,id)) {
    unsigned int operation = original == DY778OriginalApplyV2 ? DY778RecallApplyV2 : DY778RecallApply;
    if (DY778RecallFrameContains(DY778RecallFrames, (__bridge const void *)message, operation)) return;
    DY778RecallFrame frame = {(__bridge const void *)message, operation, DY778RecallFrames}; DY778RecallFrames = &frame;
    DY778RecallFastState *mutation = DY778FastState(message, atomic_load_explicit(&DY778RecallSwitch, memory_order_relaxed) || DY778EditCaptureEnabled());
    if (mutation) atomic_fetch_add_explicit(&mutation->nativeMutations, 1, memory_order_acq_rel);
    id suppression = objc_getAssociatedObject(message, &kDY778SuppressLive);
    if (!objc_getAssociatedObject(message, &kDY778MessageSnapshot)) objc_setAssociatedObject(message, &kDY778SuppressLive, @YES, OBJC_ASSOCIATION_RETAIN);
    @try { original(message, selector, model); }
    @finally { if (mutation) atomic_fetch_sub_explicit(&mutation->nativeMutations, 1, memory_order_release); objc_setAssociatedObject(message, &kDY778SuppressLive, suppression, OBJC_ASSOCIATION_RETAIN); DY778RecallFrames = frame.previous; }
    DY778ObserveMessage(message);
}
static void DY778ApplyHook(id message, SEL selector, id model) { DY778ApplyMessage(message, selector, model, DY778OriginalApply); }
static void DY778ApplyV2Hook(id message, SEL selector, id model) { DY778ApplyMessage(message, selector, model, DY778OriginalApplyV2); }
void DY778ClearRecallArchive(void) {
    NSString *account = DY778CurrentAccountID();
    [[DY778RecallStore shared] removeForAccount:account key:nil completion:nil];
}
void DY778ClearConversationRecallArchive(NSString *conversationID) {
    [[DY778RecallStore shared] removeConversation:conversationID account:DY778CurrentAccountID() completion:nil];
}
void DY778RecallStorageStatistics(void (^completion)(NSDictionary *)) {
    NSString *account = DY778CurrentAccountID(); DY778RecallStore *store = [DY778RecallStore shared];
    dispatch_async(store.queue, ^{
        unsigned long long bytes = 0; NSUInteger count = 0; NSMutableSet *conversations = [NSMutableSet set]; sqlite3_stmt *statement = NULL;
        if (store.database && account.length && sqlite3_prepare_v2(store.database, "SELECT key,conversation,recalled FROM messages WHERE account=? AND hidden_notice=0", -1, &statement, NULL) == SQLITE_OK) {
            DY778Bind(statement, 1, account);
            while (sqlite3_step(statement) == SQLITE_ROW) {
                NSString *key = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)];
                if (sqlite3_column_int(statement, 2)) { count++; [conversations addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 1)]]; }
                NSURL *folder = [store.root URLByAppendingPathComponent:[@"Media/" stringByAppendingString:DY778Hash(key)] isDirectory:YES];
                for (NSURL *file in [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:@[NSURLFileSizeKey] options:0 error:nil]) bytes += [[[file resourceValuesForKeys:@[NSURLFileSizeKey] error:nil] objectForKey:NSURLFileSizeKey] unsignedLongLongValue];
            }
        }
        sqlite3_finalize(statement);
        NSDictionary *stats = @{@"bytes": @(bytes), @"records": @(count), @"conversations": @(conversations.count), @"account": account ?: @""};
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(stats); });
    });
}
void DY778RecallMaintenance(void) { [[DY778RecallStore shared] maintenance]; }
NSString *DY778RecallStorageStatus(void) {
    DY778RecallStore *store = [DY778RecallStore shared];
    @synchronized (store) { return store.status; }
}
NSUInteger DY778RecallCount(void) {
    NSString *account = DY778CurrentAccountID();
    if (!account.length) return 0;
    DY778RecallStore *store = [DY778RecallStore shared];
    NSUInteger count = 0;
    @synchronized (store) {
        if ([store.clearingAccounts containsObject:account]) return 0;
        for (NSString *key in store.archivedKeys) {
            if ([store.forgottenKeys containsObject:key]) continue;
            NSArray *parts = [NSJSONSerialization JSONObjectWithData:[key dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if ([parts isKindOfClass:NSArray.class] && [parts.firstObject isEqual:account]) count++;
        }
    }
    return count;
}

#pragma mark - Archive presentation

static NSString *DY778DateText(NSTimeInterval timestamp) {
    if (timestamp <= 0) return @"时间未知";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}
static NSString *DY778MediaTitle(NSDictionary *media) {
    return @{@"image": @"图片", @"audio": @"语音", @"video": @"视频", @"file": @"文件"}[media[@"kind"]] ?: @"附件";
}
static NSString *DY778MediaSymbol(NSDictionary *media) {
    return @{@"image": @"photo", @"audio": @"waveform", @"video": @"play.rectangle", @"file": @"doc"}[media[@"kind"]] ?: @"doc";
}
static NSString *DY778PlayablePath(NSDictionary *media) {
    for (NSString *key in @[@"cachedPath", @"sourcePath"]) {
        NSString *path = DY778ResolvedMediaPath(media[key]);
        if (path && [NSFileManager.defaultManager isReadableFileAtPath:path]) return path;
    }
    return nil;
}
static UITableViewCell *DY778ArchiveCell(NSString *title, NSString *detail, NSString *symbol) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = DY778CardBackground();
    cell.textLabel.text = title; cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.numberOfLines = 2; cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.text = detail; cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.detailTextLabel.numberOfLines = 3; cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.imageView.image = DY778MenuIcon(symbol); cell.imageView.tintColor = DY778Accent();
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

@interface DY778RawMessageController : UIViewController
@property(nonatomic, copy) NSDictionary *record;
@end
@implementation DY778RawMessageController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"完整消息数据"; DY778StyleController(self);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(checkAccount) name:UIApplicationDidBecomeActiveNotification object:nil];
    UITextView *text = [[UITextView alloc] initWithFrame:self.view.bounds];
    text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    text.editable = NO; text.backgroundColor = DY778Background(); text.textColor = UIColor.labelColor;
    text.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    text.textContainerInset = UIEdgeInsetsMake(20, 16, 24, 16);
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.record ?: @{} options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    text.text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self.view addSubview:text];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"复制" style:UIBarButtonItemStylePlain target:self action:@selector(copyData)];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self checkAccount]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)checkAccount {
    if ([self.record[@"account"] isEqual:DY778CurrentAccountID()]) return;
    self.record = @{};
    for (UIView *view in self.view.subviews) if ([view isKindOfClass:UITextView.class]) ((UITextView *)view).text = @"";
    [self.navigationController popViewControllerAnimated:NO];
}
- (void)copyData {
    if (![self.record[@"account"] isEqual:DY778CurrentAccountID()]) { [self checkAccount]; return; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.record ?: @{} options:NSJSONWritingPrettyPrinted error:nil];
    UIPasteboard.generalPasteboard.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]; DY778Toast(@"消息数据已复制");
}
@end

@interface DY778ArchiveDownload : NSObject <NSURLSessionDownloadDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionDownloadTask *task;
@property(nonatomic, copy) void (^completion)(NSURL *, NSError *);
@property(nonatomic) BOOL delivered;
@property(nonatomic, strong) NSError *failure;
- (void)start:(NSURL *)url completion:(void (^)(NSURL *, NSError *))completion;
- (void)cancel;
@end
@implementation DY778ArchiveDownload
- (void)start:(NSURL *)url completion:(void (^)(NSURL *, NSError *))completion {
    self.completion = completion;
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 90;
    configuration.HTTPMaximumConnectionsPerHost = 1; configuration.URLCache = nil;
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    self.task = [self.session downloadTaskWithURL:url]; [self.task resume];
}
- (void)cancel { [self.task cancel]; [self.session invalidateAndCancel]; }
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    double limit = 32 * 1024 * 1024; // 有上限的临时预览，仅此用途。
    if (limit > 0 && (totalBytesWritten > limit || totalBytesExpectedToWrite > limit)) {
        self.failure = [NSError errorWithDomain:@"DY778Media" code:2 userInfo:@{NSLocalizedDescriptionKey: @"附件超过单次预览大小限制，本次加载已停止"}];
        [task cancel];
    }
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    if (![task.response isKindOfClass:NSHTTPURLResponse.class]) return;
    NSDictionary *downloadAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:location.path error:nil];
    double limit = 32 * 1024 * 1024; // 有上限的临时预览，仅此用途。
    if (limit > 0 && [downloadAttributes fileSize] > limit) {
        self.failure = [NSError errorWithDomain:@"DY778Media" code:2 userInfo:@{NSLocalizedDescriptionKey: @"附件超过单次预览大小限制，本次加载已停止"}];
        return;
    }
    NSInteger status = [(NSHTTPURLResponse *)task.response statusCode];
    if (status < 200 || status >= 300) return;
    NSString *extension = task.response.suggestedFilename.pathExtension;
    if (!extension.length || extension.length > 8 || [extension rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet.invertedSet].location != NSNotFound) extension = @"bin";
    NSURL *target = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"DY778Preview-%@.%@", NSUUID.UUID.UUIDString, extension]]];
    NSError *error = nil;
    if (![NSFileManager.defaultManager copyItemAtURL:location toURL:target error:&error]) target = nil;
    if (target) [NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:target.path error:nil];
    self.delivered = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.completion) self.completion(target, error); self.completion = nil; });
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!self.delivered) {
        NSError *resolved = self.failure ?: error ?: [NSError errorWithDomain:@"DY778Media" code:1 userInfo:@{NSLocalizedDescriptionKey: @"媒体地址已失效或服务器拒绝访问"}];
        dispatch_async(dispatch_get_main_queue(), ^{ if (self.completion) self.completion(nil, resolved); self.completion = nil; });
    }
    [session finishTasksAndInvalidate]; self.session = nil; self.task = nil;
}
@end

static void DY778OpenArchivedWork(UIViewController *source, NSDictionary *record) {
    NSString *identifier = DY778RecallWorkIdentifier(record);
    if (!identifier.length || ![record[@"account"] isEqual:DY778CurrentAccountID()]) return;
    Class router = NSClassFromString(@"AWERouter"); SEL selector = NSSelectorFromString(@"transferToURLString:");
    Method method = class_getClassMethod(router, selector); char result[16] = {0}, argument[16] = {0};
    if (method) { method_getReturnType(method, result, sizeof(result)); method_getArgumentType(method, 2, argument, sizeof(argument)); }
    if (!method || method_getNumberOfArguments(method) != 3 || !strchr("Bc", result[0]) || argument[0] != '@') {
        DY778ShowNotice(source, @"暂时无法打开作品", @"当前作品入口不可用，请稍后重试。"); return;
    }
    UINavigationController *navigation = source.navigationController;
    BOOL pluginNavigation = [navigation isKindOfClass:NSClassFromString(@"DY778NavigationController")];
    UIViewController *presenter = pluginNavigation ? navigation.presentingViewController : nil;
    dispatch_block_t open = ^{
        if (![record[@"account"] isEqual:DY778CurrentAccountID()]) return;
        BOOL accepted = NO;
        @try { accepted = ((BOOL (*)(id, SEL, id))objc_msgSend)(router, selector, [@"aweme://aweme/detail/" stringByAppendingString:identifier]); }
        @catch (__unused NSException *exception) {}
        if (!accepted) {
            if (presenter && !presenter.presentedViewController) [presenter presentViewController:navigation animated:NO completion:^{ DY778Toast(@"作品入口未打开，请稍后重试"); }];
            else DY778Toast(@"作品入口未打开，请稍后重试");
        }
    };
    if (presenter && !navigation.isBeingDismissed) [navigation dismissViewControllerAnimated:YES completion:open];
    else if (!navigation.isBeingDismissed) open();
}

@interface DY778ArchiveBubbleCell : UITableViewCell
@property(nonatomic, strong) UIImageView *portrait;
@property(nonatomic, strong) UILabel *senderLabel;
@property(nonatomic, strong) UILabel *bodyLabel;
@property(nonatomic, strong) UILabel *timeLabel;
@property(nonatomic, strong) UIView *bubble;
@property(nonatomic, strong) DY778RecallMediaView *mediaView;
@property(nonatomic, copy) void (^openMedia)(NSDictionary *media);
@property(nonatomic, copy) dispatch_block_t openOriginal;
@property(nonatomic, copy) dispatch_block_t openMessage;
@property(nonatomic, copy) NSString *recordKey;
- (void)configureRecord:(NSDictionary *)record full:(BOOL)full;
@end
@implementation DY778ArchiveBubbleCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor = UIColor.clearColor; self.selectionStyle = UITableViewCellSelectionStyleNone;
        _portrait = [UIImageView new]; _portrait.translatesAutoresizingMaskIntoConstraints = NO; _portrait.layer.cornerRadius = 19; _portrait.clipsToBounds = YES; _portrait.contentMode = UIViewContentModeScaleAspectFill; _portrait.backgroundColor = [DY778Accent() colorWithAlphaComponent:.15]; _portrait.tintColor = DY778Accent();
        _senderLabel = [UILabel new]; _senderLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; _senderLabel.textColor = UIColor.secondaryLabelColor; _senderLabel.numberOfLines = 1;
        _bodyLabel = [UILabel new]; _bodyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; _bodyLabel.textColor = UIColor.labelColor; _bodyLabel.numberOfLines = 4; _bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _bubble = [UIView new]; _bubble.backgroundColor = DY778CardBackground(); _bubble.layer.cornerRadius = 17; _bubble.layer.cornerCurve = kCACornerCurveContinuous; [_bubble addSubview:_bodyLabel];
        _timeLabel = [UILabel new]; _timeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2]; _timeLabel.textColor = UIColor.systemOrangeColor; _timeLabel.numberOfLines = 0;
        _mediaView = [DY778RecallMediaView new]; _mediaView.hidden = YES;
        __weak typeof(self) weakSelf = self; _mediaView.openMedia = ^(NSDictionary *media) { if (weakSelf.openMedia) weakSelf.openMedia(media); };
        _mediaView.openOriginal = ^{ if (weakSelf.openOriginal) weakSelf.openOriginal(); };
        _mediaView.openMessage = ^{ if (weakSelf.openMessage) weakSelf.openMessage(); };
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_senderLabel, _bubble, _mediaView, _timeLabel]]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 7; stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_portrait]; [self.contentView addSubview:stack];
        NSLayoutConstraint *bodyBottom = [_bodyLabel.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-12]; bodyBottom.priority = 999;
        [NSLayoutConstraint activateConstraints:@[[_portrait.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4], [_portrait.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12], [_portrait.widthAnchor constraintEqualToConstant:38], [_portrait.heightAnchor constraintEqualToConstant:38], [stack.leadingAnchor constraintEqualToAnchor:_portrait.trailingAnchor constant:10], [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10], [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12], [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12], [_bodyLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:14], [_bodyLabel.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-14], [_bodyLabel.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:12], bodyBottom]];
    } return self;
}
- (void)prepareForReuse { [super prepareForReuse]; self.recordKey = nil; self.openMedia = nil; self.openOriginal = nil; self.openMessage = nil; [self.mediaView cancel]; self.mediaView.hidden = YES; }
- (void)configureRecord:(NSDictionary *)record full:(BOOL)full {
    record = DY778RecallEnrichRecord(record);
    self.recordKey = record[@"key"];
    self.senderLabel.text = [record[@"senderName"] length] ? record[@"senderName"] : ([record[@"conversationName"] length] ? record[@"conversationName"] : @"对方");
    self.bodyLabel.text = DY778RecordSummary(record); self.bodyLabel.numberOfLines = 0;
    self.mediaView.hidden = full || (![record[@"media"] count] && !DY778RecallWorkIdentifier(record).length && ![@[@"image", @"audio", @"video"] containsObject:record[@"card"][@"kind"] ?: @""]);
    NSString *comment = record[@"comment"][@"text"];
    if (!full && comment.length) {
        NSString *author = record[@"comment"][@"author"];
        self.bodyLabel.text = [NSString stringWithFormat:@"分享评论%@\n%@", author.length ? [@" · " stringByAppendingString:author] : @"", comment];
    }
    self.bubble.hidden = !self.mediaView.hidden && !comment.length;
    if (!self.mediaView.hidden) [self.mediaView configureRecord:record];
    self.timeLabel.text = [NSString stringWithFormat:@"%@ · %@\n%@", [record[@"systemRecallNotice"] boolValue] ? @"撤回提示" : @"对方已撤回", [record[@"available"] boolValue] ? @"内容已保留" : @"未取得原文", DY778DateText([record[@"createdAt"] doubleValue])];
    NSString *avatar = [record[@"senderAvatar"] length] ? record[@"senderAvatar"] : record[@"conversationAvatar"];
    NSString *identity = [NSString stringWithFormat:@"%@/%@", record[@"account"] ?: @"", record[@"sender"] ?: @""];
    DY778LoadAvatarURLs(self.portrait, [record[@"senderAvatarURLs"] count] ? record[@"senderAvatarURLs"] : @[avatar ?: @""], identity);
    // 从确切的本地发送方资料刷新备用 CDN 地址。
    __weak typeof(self) weakSelf = self;
    DY778GetLocalUserProfile(record[@"account"], record[@"sender"], ^(NSDictionary *profile) {
        typeof(self) self = weakSelf; if (!self || ![self.recordKey isEqual:record[@"key"]]) return;
        if (![record[@"senderName"] length] && [profile[@"name"] length]) self.senderLabel.text = profile[@"name"];
        if ([profile[@"avatarURLs"] count]) DY778LoadAvatarURLs(self.portrait, profile[@"avatarURLs"], identity);
    });
}
@end
@interface DY778ArchivePlayerController : AVPlayerViewController
@property(nonatomic, copy) dispatch_block_t openMessage;
@property(nonatomic) BOOL observing;
@end
static char kDY778ArchivePlayerStatus;
@implementation DY778ArchivePlayerController
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.observing && self.player.currentItem) {
        self.observing = YES;
        [self.player.currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:&kDY778ArchivePlayerStatus];
    }
}
- (void)stopObserving {
    if (self.observing) { [self.player.currentItem removeObserver:self forKeyPath:@"status" context:&kDY778ArchivePlayerStatus]; self.observing = NO; }
}
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; [self stopObserving]; [self.player pause]; }
- (void)dealloc { [self stopObserving]; }
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kDY778ArchivePlayerStatus) { [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; return; }
    if (self.player.currentItem.status != AVPlayerItemStatusFailed) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.observing || !self.presentingViewController || self.isBeingDismissed) return;
        [self stopObserving]; [self.player pause];
        dispatch_block_t action = self.openMessage; self.openMessage = nil;
        [self dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:action];
    });
}
@end
@interface DY778RecallDetailController : UITableViewController <QLPreviewControllerDataSource>
@property(nonatomic, copy) NSDictionary *record;
@property(nonatomic, strong) NSURL *previewURL;
@property(nonatomic, strong) NSMutableArray<NSURL *> *temporaryFiles;
@property(nonatomic, strong) DY778ArchiveDownload *download;
@property(nonatomic, weak) UIViewController *mediaSource;
@property(nonatomic, strong) AVURLAsset *pendingAsset;
@property(nonatomic) NSUInteger mediaGeneration;
@property(nonatomic, copy) NSString *activeMediaKey;
- (void)openMedia:(NSDictionary *)media;
@end
@implementation DY778RecallDetailController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"撤回消息"; DY778StyleController(self); self.record = DY778RecallEnrichRecord(self.record);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(checkAccount) name:UIApplicationDidBecomeActiveNotification object:nil];
    self.tableView.backgroundColor = DY778Background(); self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64; self.temporaryFiles = [NSMutableArray array];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(deleteRecord)];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self checkAccount]; }
- (void)checkAccount {
    if ([self.record[@"account"] isEqual:DY778CurrentAccountID()]) return;
    [self.download cancel]; self.download = nil; [self.pendingAsset cancelLoading]; self.pendingAsset = nil; ++self.mediaGeneration; self.record = @{}; [self.tableView reloadData];
    [self.navigationController popViewControllerAnimated:NO];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.download cancel];
    [self.pendingAsset cancelLoading];
    for (NSURL *url in self.temporaryFiles) [NSFileManager.defaultManager removeItemAtURL:url error:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 6; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return [self.record[@"media"] count] || [self.record[@"card"][@"kind"] length] ? 1 : 0;
    if (section == 2) return [self.record[@"media"] count];
    if (section == 4) return 3 + (DY778ArchiveCanLocate(self.record) ? 1 : 0);
    if (section == 3) return ([self.record[@"share"] count] ? 1 : 0) + ([self.record[@"comment"] count] ? 1 : 0) + ([self.record[@"quote"] count] ? 1 : 0);
    return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"对方已撤回", @"内容预览", @"消息附件", @"分享与上下文", @"记录信息", @"完整内容"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0 && ![self.record[@"available"] boolValue]) return @"DY778没有接收到这条消息的原始内容，无法从撤回提示中重建正文。";
    if (section == 2) return @"优先使用抖音现有的本地媒体；无法预览时定位到原消息，并短暂高亮整行。";
    if (section == 5) return @"未知消息类型也保留原始字段；卡片展示以保存时的数据为准。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        DY778ArchiveBubbleCell *cell = [[DY778ArchiveBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; [cell configureRecord:self.record full:YES]; return cell;
    }
    if (indexPath.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.backgroundColor = UIColor.clearColor; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        DY778RecallMediaView *mediaView = [DY778RecallMediaView new]; mediaView.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:mediaView];
        [NSLayoutConstraint activateConstraints:@[[mediaView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor], [mediaView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor], [mediaView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor], [mediaView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor]]];
        __weak typeof(self) weakSelf = self; mediaView.openMedia = ^(NSDictionary *media) { [weakSelf openMedia:media]; }; mediaView.openOriginal = ^{ DY778OpenArchivedWork(weakSelf, weakSelf.record); };
        mediaView.openMessage = ^{ DY778ArchiveLocateMessage(weakSelf, weakSelf.record); }; [mediaView configureRecord:self.record]; return cell;
    }
    if (indexPath.section == 2) {
        NSDictionary *media = self.record[@"media"][indexPath.row]; NSString *path = DY778PlayablePath(media);
        NSString *status = path ? @"原文件可用" : @"点按尝试预览，或定位原消息";
        return DY778ArchiveCell(DY778MediaTitle(media), [NSString stringWithFormat:@"%@\n%@", media[@"name"] ?: @"", status], DY778MediaSymbol(media));
    }
    if (indexPath.section == 4) {
        if (DY778ArchiveCanLocate(self.record) && indexPath.row == 3) return DY778ArchiveCell(@"在聊天中查看", @"定位原消息并高亮整行", @"text.bubble");
        NSArray *titles = @[@"发送时间", @"撤回时间", @"发送者 · 会话"];
        NSString *senderName = [self.record[@"senderName"] length] ? self.record[@"senderName"] : self.record[@"sender"];
        NSArray *values = @[DY778DateText([self.record[@"createdAt"] doubleValue]), DY778DateText([self.record[@"recalledAt"] doubleValue]),
            [NSString stringWithFormat:@"%@\n%@", senderName ?: @"未知", self.record[@"conversation"] ?: @""]];
        UITableViewCell *cell = DY778ArchiveCell(titles[indexPath.row], values[indexPath.row], nil); cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell;
    }
    if (indexPath.section == 3) {
        NSMutableArray *items = [NSMutableArray array];
        if ([self.record[@"share"] count]) [items addObject:@[@"分享作品", self.record[@"share"][@"title"] ?: @"作品信息已保存", @"play.rectangle"]];
        if ([self.record[@"comment"] count]) {
            NSDictionary *comment = self.record[@"comment"];
            NSMutableString *text = [NSMutableString stringWithString:comment[@"text"] ?: @""];
            if ([comment[@"author"] length]) [text appendFormat:@"\n作者：%@", comment[@"author"]];
            if ([comment[@"capturedAt"] doubleValue] > 0) [text appendFormat:@"\n本机留存：%@", DY778DateText([comment[@"capturedAt"] doubleValue])];
            [text appendString:@"\n已保留收到时的文字，不依赖评论现在是否可见。"];
            [items addObject:@[[comment[@"transcript"] boolValue] ? @"分享评论 · 语音转写" : @"分享评论", text, @"text.bubble"]];
        }
        if ([self.record[@"quote"] count]) {
            NSDictionary *quote = self.record[@"quote"]; NSString *text = [quote[@"text"] length] ? quote[@"text"] : DY778RecordSummary(@{@"content": quote[@"content"] ?: @{}, @"available": @YES});
            [items addObject:@[@"引用的消息", text ?: @"", @"quote.bubble"]];
        }
        NSArray *item = items[indexPath.row]; UITableViewCell *cell = DY778ArchiveCell(item[0], item[1], item[2]); cell.detailTextLabel.numberOfLines = 0; cell.accessoryType = UITableViewCellAccessoryNone; return cell;
    }    return DY778ArchiveCell(@"查看完整消息数据", [NSString stringWithFormat:@"消息类型 %@ · 原始内容与附件信息", self.record[@"type"] ?: @"未知"], @"curlybraces");
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (indexPath.section != 0) return nil;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested) {
        UIAction *copy = [UIAction actionWithTitle:@"复制消息内容" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__unused UIAction *action) {
            UIPasteboard.generalPasteboard.string = DY778RecordSummary(self.record); DY778Toast(@"消息内容已复制");
        }];
        return [UIMenu menuWithTitle:@"" children:@[copy]];
    }];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 4 && indexPath.row == 3 && DY778ArchiveCanLocate(self.record)) { DY778ArchiveLocateMessage(self, self.record); return; }
    if (indexPath.section == 5) { DY778RawMessageController *raw = [DY778RawMessageController new]; raw.record = self.record; DY778PresentController(self, raw); }
    if (indexPath.section != 2) return;
    [self openMedia:self.record[@"media"][indexPath.row]];
}
- (void)openMedia:(NSDictionary *)media {
    if (![self.record[@"account"] isEqual:DY778CurrentAccountID()]) { DY778Toast(@"账号已切换，请重新打开记录"); return; }
    NSString *mediaKey = [NSString stringWithFormat:@"%@|%@|%@", self.record[@"key"] ?: @"", media[@"kind"] ?: @"", media[@"sourcePath"] ?: media[@"cachedPath"] ?: media[@"remoteURL"] ?: @""];
    BOOL cancelPending = (self.pendingAsset || self.download) && [self.activeMediaKey isEqual:mediaKey];
    [self.pendingAsset cancelLoading]; self.pendingAsset = nil; ++self.mediaGeneration;
    [self.download cancel]; self.download = nil; self.activeMediaKey = mediaKey;
    if (cancelPending) { DY778Toast(@"已取消媒体加载"); return; }
    if (!self.temporaryFiles) self.temporaryFiles = [NSMutableArray array];
    UIViewController *source = self.mediaSource ?: self;
    NSString *path = DY778PlayablePath(media);
    if (!path) for (NSDictionary *candidate in DY778ArchiveLocalMedia(self.record)) {
        if ([candidate[@"kind"] isEqual:media[@"kind"]] && ![candidate[@"cover"] boolValue]) { media = candidate; path = DY778PlayablePath(candidate); if (path) break; }
    }
    if (path) { [self preview:[NSURL fileURLWithPath:path] media:media]; return; }
    if ([media[@"encrypted"] boolValue]) { DY778ArchiveLocateMessage(source, self.record); return; }
    NSURL *url = [NSURL URLWithString:media[@"remoteURL"] ?: @""];
    if (![@[@"https", @"http"] containsObject:url.scheme.lowercaseString] || !url.host.length) { DY778ArchiveLocateMessage(source, self.record); return; }
    if ([@[@"video", @"audio"] containsObject:media[@"kind"]]) {
        [self.download cancel]; self.download = nil;
        [self preview:url media:media]; return;
    }
    DY778Toast(@"正在加载附件 · 再次点按可取消");
    self.download = [DY778ArchiveDownload new];
    NSUInteger generation = self.mediaGeneration; NSDictionary *record = self.record;
    __weak typeof(self) weakSelf = self;
    [self.download start:url completion:^(NSURL *result, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self || self.mediaGeneration != generation || ![record[@"account"] isEqual:DY778CurrentAccountID()] || ![self.record[@"key"] isEqual:record[@"key"]]) { if (result) [NSFileManager.defaultManager removeItemAtURL:result error:nil]; return; }
        self.download = nil;
        if (error) { if (error.code != NSURLErrorCancelled && (self.mediaSource ?: self).view.window && !(self.mediaSource ?: self).presentedViewController) DY778ArchiveLocateMessage(self.mediaSource ?: self, record); return; }
        [self.temporaryFiles addObject:result]; [self preview:result media:media];
    }];
}
- (void)preview:(NSURL *)url media:(NSDictionary *)media {
    if (![self.record[@"account"] isEqual:DY778CurrentAccountID()]) return;
    [self.download cancel]; self.download = nil;
    UIViewController *source = self.mediaSource ?: self; NSDictionary *record = self.record;
    if ([media[@"kind"] isEqual:@"audio"] || [media[@"kind"] isEqual:@"video"]) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil]; self.pendingAsset = asset;
        NSUInteger generation = self.mediaGeneration; __weak typeof(self) weakSelf = self;
        DY778Toast(@"正在准备媒体 · 再次点按可取消");
        [asset loadValuesAsynchronouslyForKeys:@[@"playable", @"tracks"] completionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) self = weakSelf;
                if (!self || self.mediaGeneration != generation || self.pendingAsset != asset || ![record[@"account"] isEqual:DY778CurrentAccountID()] || ![record[@"key"] isEqual:self.record[@"key"]]) return;
                self.pendingAsset = nil;
                NSString *trackType = [media[@"kind"] isEqual:@"video"] ? AVMediaTypeVideo : AVMediaTypeAudio;
                if (!source.view.window || source.presentedViewController) return;
                if ([asset statusOfValueForKey:@"playable" error:nil] != AVKeyValueStatusLoaded || [asset statusOfValueForKey:@"tracks" error:nil] != AVKeyValueStatusLoaded || !asset.playable || ![asset tracksWithMediaType:trackType].count) { DY778ArchiveLocateMessage(source, record); return; }
                DY778ArchivePlayerController *player = [DY778ArchivePlayerController new]; player.player = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:asset]];
                __weak UIViewController *weakSource = source; player.openMessage = ^{ DY778ArchiveLocateMessage(weakSource, record); };
                [source presentViewController:player animated:!UIAccessibilityIsReduceMotionEnabled() completion:^{ [player.player play]; }];
            });
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self || self.mediaGeneration != generation || self.pendingAsset != asset) return;
            [asset cancelLoading]; self.pendingAsset = nil;
            if ([record[@"key"] isEqual:self.record[@"key"]] && [record[@"account"] isEqual:DY778CurrentAccountID()] && source.view.window && !source.presentedViewController) DY778ArchiveLocateMessage(source, record);
        });
    } else {
        if (!source.view.window || source.presentedViewController) return;
        if (![QLPreviewController canPreviewItem:url]) { DY778ArchiveLocateMessage(source, record); return; }
        self.previewURL = url; QLPreviewController *preview = [QLPreviewController new]; preview.dataSource = self;
        [self.mediaSource ?: self presentViewController:preview animated:YES completion:nil];
    }
}
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller { return self.previewURL ? 1 : 0; }
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index { return self.previewURL; }
- (void)deleteRecord {
    __weak typeof(self) weakSelf = self;
    DY778Confirm(self, @"删除这条记录？", @"仅删除DY778保存的本地消息记录，删除后无法恢复。", @"删除记录", YES, ^{
        typeof(self) self = weakSelf; if (!self) return;
        [[DY778RecallStore shared] removeForAccount:self.record[@"account"] key:self.record[@"key"] completion:^{
            [self.navigationController popViewControllerAnimated:YES]; DY778Toast(@"记录已删除");
        }];
    });
}
@end
@interface DY778ArchivePersonCell : UITableViewCell
@property(nonatomic, strong) UIImageView *portrait;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *messageLabel;
@property(nonatomic, strong) UILabel *countLabel;
@property(nonatomic, copy) NSString *conversationIdentity;
- (void)configure:(NSDictionary *)person;
@end
@implementation DY778ArchivePersonCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor = DY778CardBackground(); self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        _portrait = [UIImageView new]; _portrait.translatesAutoresizingMaskIntoConstraints = NO; _portrait.layer.cornerRadius = 24; _portrait.clipsToBounds = YES; _portrait.contentMode = UIViewContentModeScaleAspectFill;
        _portrait.backgroundColor = [DY778Accent() colorWithAlphaComponent:.12]; _portrait.tintColor = DY778Accent();
        _nameLabel = [UILabel new]; _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; _nameLabel.textColor = UIColor.labelColor; _nameLabel.adjustsFontForContentSizeCategory = YES;
        _messageLabel = [UILabel new]; _messageLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; _messageLabel.textColor = UIColor.secondaryLabelColor; _messageLabel.numberOfLines = 2;
        _countLabel = [UILabel new]; _countLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; _countLabel.textColor = DY778Accent();
        UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _messageLabel, _countLabel]]; labels.axis = UILayoutConstraintAxisVertical; labels.spacing = 5; labels.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_portrait]; [self.contentView addSubview:labels];
        [NSLayoutConstraint activateConstraints:@[[_portrait.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16], [_portrait.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor], [_portrait.widthAnchor constraintEqualToConstant:48], [_portrait.heightAnchor constraintEqualToConstant:48], [labels.leadingAnchor constraintEqualToAnchor:_portrait.trailingAnchor constant:13], [labels.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12], [labels.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16], [labels.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16]]];
    }
    return self;
}
- (void)prepareForReuse { [super prepareForReuse]; self.conversationIdentity = nil; }
- (void)configure:(NSDictionary *)person {
    self.nameLabel.text = person[@"name"]; self.messageLabel.text = person[@"summary"];
    self.countLabel.text = [NSString stringWithFormat:@"%@ 条撤回记录 · %@", person[@"count"] ?: @0, DY778DateText([person[@"time"] doubleValue])];
    NSString *identity = [NSString stringWithFormat:@"%@/%@", person[@"account"] ?: @"", person[@"conversation"] ?: @""]; self.conversationIdentity = identity;
    DY778LoadAvatar(self.portrait, person[@"avatar"], identity);
    if ([person[@"group"] boolValue] || ([person[@"hasName"] boolValue] && [person[@"avatar"] length])) return;
    __weak typeof(self) weakSelf = self;
    DY778GetLocalUserProfile(person[@"account"], person[@"sender"], ^(NSDictionary *profile) {
        typeof(self) self = weakSelf; if (!self || ![self.conversationIdentity isEqual:identity]) return;
        if (![person[@"hasName"] boolValue] && [profile[@"name"] length]) self.nameLabel.text = profile[@"name"];
        if (![person[@"avatar"] length]) DY778LoadAvatar(self.portrait, profile[@"avatar"], identity);
    });
}
@end

@interface DY778RecallArchiveController : UITableViewController <UISearchBarDelegate>
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *conversationID;
@property(nonatomic, copy) NSArray<NSDictionary *> *records;
@property(nonatomic, copy) NSArray<NSDictionary *> *filtered;
@property(nonatomic, strong) DY778RecallDetailController *mediaPresenter;
@property(nonatomic, strong) UISearchBar *search;
@property(nonatomic) NSUInteger loadGeneration;
@property(nonatomic) BOOL loading;
@property(nonatomic) BOOL more;
@end
@implementation DY778RecallArchiveController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; DY778StyleController(self);
    self.title = self.conversationID.length ? @"撤回记录" : @"撤回记录 · 联系人";
    self.tableView.backgroundColor = DY778Background(); self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 96;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag; self.tableView.showsVerticalScrollIndicator = NO;
    [self.tableView registerClass:DY778ArchivePersonCell.class forCellReuseIdentifier:@"person"];
    [self.tableView registerClass:DY778ArchiveBubbleCell.class forCellReuseIdentifier:@"message"];
    self.mediaPresenter = [DY778RecallDetailController new]; self.mediaPresenter.mediaSource = self;
    self.search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 58)];
    self.search.delegate = self; self.search.searchBarStyle = UISearchBarStyleMinimal;
    self.search.placeholder = self.conversationID.length ? @"搜索已加载的消息" : @"搜索联系人、群名";
    self.search.backgroundColor = DY778Background(); self.search.tintColor = DY778Accent();
    self.tableView.tableHeaderView = self.search;
    if (self.conversationID.length) self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(manageConversation)];
    self.refreshControl = [UIRefreshControl new]; self.refreshControl.tintColor = DY778Accent(); [self.refreshControl addTarget:self action:@selector(reloadRecords) forControlEvents:UIControlEventValueChanged];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadRecords) name:DY778RecallChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadRecords) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; DY778StyleController(self); [self reloadRecords]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)reloadRecords {
    NSString *current = DY778CurrentAccountID();
    if (![(self.account ?: @"") isEqual:(current ?: @"")]) { self.account = current; self.records = @[]; self.filtered = @[]; [self.tableView reloadData]; }
    self.loading = NO; self.more = NO;
    if (self.conversationID.length) { self.records = @[]; [self loadMore]; return; }
    NSUInteger generation = ++self.loadGeneration; __weak typeof(self) weakSelf = self;
    [[DY778RecallStore shared] conversationSummaries:self.account completion:^(NSArray *records) {
        typeof(self) self = weakSelf; if (!self || generation != self.loadGeneration || ![self.account isEqual:DY778CurrentAccountID()]) return;
        self.records = records; [self.refreshControl endRefreshing]; [self applySearch];
    }];
}
- (void)loadMore {
    if (self.loading || !self.conversationID.length) return;
    self.loading = YES; NSUInteger offset = self.records.count, generation = ++self.loadGeneration; NSString *account = self.account;
    __weak typeof(self) weakSelf = self;
    [[DY778RecallStore shared] recordsForAccount:account conversation:self.conversationID offset:offset completion:^(NSArray *records) {
        typeof(self) self = weakSelf; if (!self || generation != self.loadGeneration || ![account isEqual:DY778CurrentAccountID()]) return;
        self.loading = NO; self.more = records.count == 100; self.records = [self.records ?: @[] arrayByAddingObjectsFromArray:records];
        [self.refreshControl endRefreshing];
        NSDictionary *profile = [[DY778RecallStore shared] profileForAccount:account conversation:self.conversationID];
        if ([profile[@"name"] length]) self.title = profile[@"name"];
        [self applySearch];
    }];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { [self applySearch]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }
- (void)applySearch {
    NSString *query = [self.search.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *record in self.records) {
        NSString *text = self.conversationID.length ? [NSString stringWithFormat:@"%@ %@", DY778RecordSummary(record), record[@"senderName"] ?: @""] : [NSString stringWithFormat:@"%@ %@", record[@"name"] ?: @"", record[@"summary"] ?: @""];
        if (!query.length || [text localizedCaseInsensitiveContainsString:query]) [filtered addObject:record];
    }
    self.filtered = filtered;
    if (!filtered.count && !self.loading) {
        UILabel *empty = [UILabel new]; empty.textAlignment = NSTextAlignmentCenter; empty.numberOfLines = 0; empty.textColor = UIColor.secondaryLabelColor; empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        empty.text = query.length ? @"没有找到匹配内容\n可以更换关键词" : @"暂无撤回记录\n已收到的消息会在对方撤回后保存在这里"; self.tableView.backgroundView = empty;
    } else self.tableView.backgroundView = nil;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filtered.count + (self.more ? 1 : 0); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return [NSString stringWithFormat:self.conversationID.length ? @"已加载 %lu 条记录" : @"%lu 个联系人 / 群聊", (unsigned long)self.filtered.count]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return self.conversationID.length ? @"文字与分享信息保存在本机；作品通过抖音打开，媒体是否可用取决于原文件和链接。" : @"按联系人和群聊整理，仅显示当前账号的本地记录。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row >= self.filtered.count) return DY778ArchiveCell(self.loading ? @"正在加载…" : @"加载更早记录", @"每次加载 100 条，不截断历史记录", @"arrow.down.circle");
    NSDictionary *record = self.filtered[indexPath.row];
    if (!self.conversationID.length) { DY778ArchivePersonCell *cell = [tableView dequeueReusableCellWithIdentifier:@"person" forIndexPath:indexPath]; [cell configure:record]; return cell; }
    DY778ArchiveBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"message" forIndexPath:indexPath];
    __weak typeof(self) weakSelf = self; cell.openMedia = ^(NSDictionary *media) { weakSelf.mediaPresenter.record = record; [weakSelf.mediaPresenter openMedia:media]; };
    cell.openOriginal = ^{ DY778OpenArchivedWork(weakSelf, record); };
    cell.openMessage = ^{ DY778ArchiveLocateMessage(weakSelf, record); };
    [cell configureRecord:record full:NO]; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; if (![self.account isEqual:DY778CurrentAccountID()]) { [self reloadRecords]; return; }
    if ((NSUInteger)indexPath.row >= self.filtered.count) { [self loadMore]; return; }
    NSDictionary *record = self.filtered[indexPath.row];
    if (!self.conversationID.length) { DY778PresentRecallArchive(self, record[@"conversation"]); return; }
    if (DY778RecallWorkIdentifier(record).length) { DY778OpenArchivedWork(self, record); return; }
    DY778RecallDetailController *detail = [DY778RecallDetailController new]; detail.record = record; DY778PresentController(self, detail);
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (!self.conversationID.length || (NSUInteger)indexPath.row >= self.filtered.count) return nil;
    NSDictionary *record = self.filtered[indexPath.row];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested) {
        UIAction *detail = [UIAction actionWithTitle:@"查看撤回记录" image:[UIImage systemImageNamed:@"doc.text.magnifyingglass"] identifier:nil handler:^(__unused UIAction *action) {
            if (![record[@"account"] isEqual:DY778CurrentAccountID()]) return;
            DY778RecallDetailController *controller = [DY778RecallDetailController new]; controller.record = record; DY778PresentController(self, controller);
        }];
        UIAction *locate = [UIAction actionWithTitle:@"在聊天中查看" image:[UIImage systemImageNamed:@"text.bubble"] identifier:nil handler:^(__unused UIAction *action) { DY778ArchiveLocateMessage(self, record); }];
        return [UIMenu menuWithTitle:@"" children:DY778ArchiveCanLocate(record) ? @[detail, locate] : @[detail]];
    }];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row >= self.filtered.count) return nil;
    NSDictionary *record = self.filtered[indexPath.row]; __weak typeof(self) weakSelf = self;
    NSString *account = self.account; BOOL single = self.conversationID.length > 0;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        completion(NO); if (![account isEqual:DY778CurrentAccountID()] || ![weakSelf.account isEqual:account]) return;
        DY778Confirm(weakSelf, single ? @"删除这条记录？" : @"删除此会话全部记录？", @"将删除当前账号的本地消息记录。", @"删除", YES, ^{
            if (![account isEqual:DY778CurrentAccountID()] || ![weakSelf.account isEqual:account]) return;
            if (single) [[DY778RecallStore shared] removeForAccount:account key:record[@"key"] completion:^{ [weakSelf reloadRecords]; }];
            else [[DY778RecallStore shared] removeConversation:record[@"conversation"] account:account completion:^{ [weakSelf reloadRecords]; }];
        });
    }]; UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[remove]]; configuration.performsFirstActionWithFullSwipe = NO; return configuration;
}
- (void)manageConversation {
    NSString *account = self.account, *conversation = self.conversationID;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"此会话的记录" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除此会话全部记录" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { DY778Confirm(self, @"删除此会话全部记录？", @"将删除本地消息记录，其他联系人不受影响。", @"删除全部", YES, ^{ if ([account isEqual:DY778CurrentAccountID()]) DY778ClearConversationRecallArchive(conversation); }); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem; [self presentViewController:sheet animated:YES completion:nil];
}
@end
void DY778PresentRecallArchive(UIViewController *source, NSString *conversationID) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778PresentRecallArchive(source, conversationID); }); return; }
    DY778RecallArchiveController *controller = [DY778RecallArchiveController new]; controller.account = DY778CurrentAccountID(); controller.conversationID = conversationID; DY778PresentController(source ?: DY778TopController(), controller);
}
static NSString *DY778ChatConversationID(id provider) {
    id context = DY778Read(provider, @"context");
    NSString *identifier = DY778Identifier(DY778Read(DY778Read(context, @"conversation"), @"conversationID"));
    if (!identifier.length) identifier = DY778Identifier(DY778Read(DY778Read(context, @"con"), @"identifier"));
    return identifier;
}

static id DY778NewChatItem(Class itemClass, NSString *identifier) {
    SEL initializer = NSSelectorFromString(@"initWithIdentifier:"); Method method = class_getInstanceMethod(itemClass, initializer);
    if (!method || method_getNumberOfArguments(method) != 3) return nil;
    char returned[16]={0}, argument[16]={0}; method_getReturnType(method, returned, sizeof(returned)); method_getArgumentType(method, 2, argument, sizeof(argument));
    if (returned[0] != '@' || argument[0] != '@') return nil;
    return [(id<DY778ChatSettingsInitializable>)[itemClass alloc] initWithIdentifier:identifier];
}
static id DY778ChatGroupedSection(Class sectionClass, NSArray *items, id templateSection) {
    if (!items.count) return nil;
    id section = [sectionClass new];
    if (!DY778Write(section, @"itemViewModels", items)) return nil;
    // 39.9.0 原生位置：单条=0，首条=1，中间=2，末条=3。
    // 原生 cell 自行套用圆角遮罩、分隔线与主题。
    for (NSUInteger index = 0; index < items.count; index++) {
        NSInteger position = items.count == 1 ? 0 : index == 0 ? 1 : index == items.count - 1 ? 3 : 2;
        DY778Write(items[index], @"internalPosition", @(position));
    }
    id inset = DY778Read(templateSection, @"sectionInset");
    if ([inset isKindOfClass:NSValue.class]) DY778Write(section, @"sectionInset", inset);
    NSNumber *spacing = DY778Read(templateSection, @"sectionSpace");
    double gap = [spacing respondsToSelector:@selector(doubleValue)] ? spacing.doubleValue : 0;
    DY778Write(section, @"sectionSpace", @(isfinite(gap) && gap >= 8 && gap <= 32 ? gap : 12));
    return section;
}
static id DY778ChatSectionsHook(id provider, SEL selector) {
    id original = DY778OriginalChatSections(provider, selector); if (![original isKindOfClass:NSArray.class]) return original;
    NSString *conversation = DY778ChatConversationID(provider); if (!conversation.length) return original;
    id context = DY778Read(provider, @"context"); NSString *account = DY778CurrentAccountID();
    if (DY778RecallEnabledForConversation(conversation)) DY778RememberConversation(DY778Read(context, @"conversation") ?: DY778Read(context, @"con"), DY778Read(context, @"peerUser"), account);
    for (id section in original) {
        id items = DY778Read(section, @"itemViewModels"); if (![items isKindOfClass:NSArray.class]) continue;
        for (id item in items) if ([DY778Read(item, @"identifier") isEqual:@"com.dy778.recall-switch"]) return original;
    }
    Class sectionClass = NSClassFromString(@"IESIMChatSettingsSectionViewModel"); if (!sectionClass) return original;
    NSMutableArray *items = [NSMutableArray array]; __weak id weakProvider = provider;
    id toggle = DY778NewChatItem(NSClassFromString(@"IESIMChatSettingsItemSwitchViewModel"), @"com.dy778.recall-switch");
    if (toggle) {
        DY778Write(toggle, @"title", @"此聊天防撤回"); DY778Write(toggle, @"describe", DY778Bool(@"recall.enabled") ? @"DY778 · 单独管理此聊天" : @"先在DY778设置开启防撤回总开关"); DY778Write(toggle, @"isOn", @(DY778RecallEnabledForConversation(conversation)));
        __weak id weakToggle = toggle;
        void (^changed)(BOOL) = ^(BOOL on) {
            id activeProvider = weakProvider; if (![account isEqual:DY778CurrentAccountID()] || ![conversation isEqual:DY778ChatConversationID(activeProvider)]) return;
            UIViewController *source = DY778Read(DY778Read(activeProvider, @"context"), @"hostViewController");
            if (!DY778Bool(@"recall.enabled")) { DY778Write(weakToggle, @"isOn", @NO); DY778ShowNotice(source ?: DY778TopController(), @"先开启防撤回", @"请到抖音设置 → DY778 → 消息防撤回开启总开关。首次开启后，所有聊天默认生效，也可以在这里单独关闭。"); return; }
            DY778SetConversationRecallEnabled(conversation, on); DY778Write(weakToggle, @"isOn", @(on)); DY778Toast(on ? @"此聊天已开启防撤回" : @"此聊天已关闭防撤回");
        };
        if (DY778Write(toggle, @"manualSwitchChanged", changed)) [items addObject:toggle];
    }
    if (DY778Bool(@"recall.archiveEntry")) {
        id item = DY778NewChatItem(NSClassFromString(@"IESIMChatSettingsItemInfoViewModel"), DY778ChatItemIdentifier);
        void (^open)(void) = ^{
            id active = weakProvider; NSString *current = DY778ChatConversationID(active);
            if (![account isEqual:DY778CurrentAccountID()] || ![current isEqual:conversation]) return;
            id source = DY778Read(DY778Read(active, @"context"), @"hostViewController"); DY778PresentRecallArchive([source isKindOfClass:UIViewController.class] ? source : DY778TopController(), current);
        };
        if (item && DY778Write(item, @"title", @"已撤回的消息") && DY778Write(item, @"subtitle", @"查看撤回记录") && DY778Write(item, @"onClicked", open)) { DY778Write(item, @"disableArrow", @NO); [items addObject:item]; }
    }
    id editToggle = DY778NewChatItem(NSClassFromString(@"IESIMChatSettingsItemSwitchViewModel"), @"com.dy778.edit-switch");
    if (editToggle) {
        DY778Write(editToggle, @"title", @"此聊天编辑历史"); DY778Write(editToggle, @"describe", DY778Bool(@"edit.enabled") ? @"记录对方消息的编辑版本" : @"先在 DY778 → 编辑历史开启总开关");
        DY778Write(editToggle, @"isOn", @(DY778EditEnabledForConversation(conversation))); __weak id weakToggle = editToggle;
        void (^changed)(BOOL) = ^(BOOL on) {
            if (![account isEqual:DY778CurrentAccountID()] || ![conversation isEqual:DY778ChatConversationID(weakProvider)]) return;
            if (!DY778Bool(@"edit.enabled")) { DY778Write(weakToggle, @"isOn", @NO); DY778ShowNotice(DY778TopController(), @"先开启编辑历史", @"在 DY778 → 编辑历史开启记录总开关后，可按会话单独设置。"); return; }
            DY778SetConversationEditEnabled(conversation, on); DY778Write(weakToggle, @"isOn", @(on));
        };
        if (DY778Write(editToggle, @"manualSwitchChanged", changed)) [items addObject:editToggle];
    }
    if (DY778Bool(@"edit.archiveEntry")) {
        id item = DY778NewChatItem(NSClassFromString(@"IESIMChatSettingsItemInfoViewModel"), @"com.dy778.edit-history");
        dispatch_block_t open = ^{
            if (![account isEqual:DY778CurrentAccountID()] || ![conversation isEqual:DY778ChatConversationID(weakProvider)]) return;
            id source = DY778Read(DY778Read(weakProvider, @"context"), @"hostViewController");
            DY778PresentEditHistory([source isKindOfClass:UIViewController.class] ? source : DY778TopController(), conversation, nil);
        };
        if (item && DY778Write(item, @"title", @"查看编辑历史") && DY778Write(item, @"subtitle", @"原文、编辑版本与时间") && DY778Write(item, @"onClicked", open)) { DY778Write(item, @"disableArrow", @NO); [items addObject:item]; }
    }
    DY778RadarAppendChatItem(provider, items);
    DY778SparkAppendChatItem(provider, items);
    NSMutableArray *recallItems = [NSMutableArray array], *editItems = [NSMutableArray array], *otherItems = [NSMutableArray array];
    for (id item in items) {
        NSString *identifier = DY778Read(item, @"identifier");
        if ([identifier isEqual:@"com.dy778.recall-switch"] || [identifier isEqual:DY778ChatItemIdentifier]) [recallItems addObject:item];
        else if ([identifier isEqual:@"com.dy778.edit-switch"] || [identifier isEqual:@"com.dy778.edit-history"]) [editItems addObject:item];
        else [otherItems addObject:item];
    }
    id templateSection = [original count] > 1 ? original[1] : [original firstObject];
    NSMutableArray *sections = [original mutableCopy]; NSUInteger insertion = MIN((NSUInteger)1, sections.count);
    for (NSArray *group in @[recallItems, editItems, otherItems]) {
        id section = DY778ChatGroupedSection(sectionClass, group, templateSection);
        if (section) [sections insertObject:section atIndex:insertion++];
    }
    return sections;
}
static void (*DY778OriginalVMSetup)(id, SEL, id);
static void (*DY778OriginalVMConversation)(id, SEL, id);
static void DY778VMSetupHook(id vm, SEL selector, id message) {
    DY778OriginalVMSetup(vm, selector, message);
    if (!DY778NativeRestoreInProgress) DY778ObserveMessageContext(vm);
}
static void DY778VMConversationHook(id vm, SEL selector, id conversation) { DY778OriginalVMConversation(vm, selector, conversation); DY778ObserveMessageContext(vm); }
static BOOL DY778RestoreSignature(id target, SEL selector, char result, const char *arguments) {
    Method method = class_getInstanceMethod(object_getClass(target), selector);
    if (!method || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char type[32]; method_getReturnType(method, type, sizeof(type)); if (type[0] != result) return NO;
    for (unsigned index = 0; arguments[index]; index++) {
        method_getArgumentType(method, index + 2, type, sizeof(type));
        if (arguments[index] == 'B' ? !strchr("Bc", type[0]) : type[0] != arguments[index]) return NO;
    }
    return YES;
}
BOOL DY778RestoreRecallPresentation(id viewModel, id message) {
    if (!NSThread.isMainThread || !viewModel || !message || DY778NativeRestoreInProgress) return NO;
    DY778RecallFastState *state = DY778FastState(message, NO); if (!state) return NO;
    NSDictionary *record = state.snapshot;
    DY778VMRestoredState *rendered = objc_getAssociatedObject(viewModel, &kDY778VMRestoredState);
    if (!DY778RecallShouldRestore(DY778FastAllowed(state), state.recalled, [record[@"available"] boolValue], [record[@"systemRecallNotice"] boolValue], atomic_load_explicit(&state->nativeMutations, memory_order_acquire) > 0, rendered.message == message && rendered.succeeded, state.displayRevision, rendered.revision)) return NO;
    if (DY778Read(viewModel, @"iesMessage") != message) return NO;
    id currentPresentation = DY778Read(viewModel, @"message");
    if (currentPresentation && ![currentPresentation isKindOfClass:NSClassFromString(@"AWEIMRecallMessage")]) return NO;
    BOOL sameAttempt = rendered.message == message && rendered.revision == state.displayRevision;
    DY778VMRestoredState *attempt = sameAttempt ? rendered : [DY778VMRestoredState new];
    attempt.message = message; attempt.revision = state.displayRevision;
    objc_setAssociatedObject(viewModel, &kDY778VMRestoredState, attempt, OBJC_ASSOCIATION_RETAIN);
    id componentContext = DY778Read(viewModel, @"componentContext");
    if ([DY778Read(componentContext, @"isAsyncBuilding") boolValue]) {
        SEL wait = NSSelectorFromString(@"invokeAfterFirstBuild:");
        if (!attempt.waitingForBuild && DY778RestoreSignature(viewModel, wait, 'v', "@")) {
            attempt.waitingForBuild = YES;
            __weak id weakModel = viewModel; __weak id weakMessage = message; __weak DY778VMRestoredState *weakAttempt = attempt;
            void (^finished)(void) = ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    DY778VMRestoredState *current = weakAttempt; id model = weakModel;
                    if (!current || !model || objc_getAssociatedObject(model, &kDY778VMRestoredState) != current) return;
                    current.waitingForBuild = NO;
                    if (DY778Read(model, @"iesMessage") == weakMessage) DY778ScheduleRecallNotification();
                });
            };
            ((void (*)(id, SEL, id))objc_msgSend)(viewModel, wait, finished);
        }
        return NO;
    }
    if (attempt.attempts >= 3 || attempt.nextAttempt > NSDate.date.timeIntervalSince1970) return NO;
    attempt.attempts++; attempt.nextAttempt = NSDate.date.timeIntervalSince1970 + .3;
    if (attempt.attempts < 3) {
        __weak DY778VMRestoredState *weakAttempt = attempt;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (weakAttempt && !weakAttempt.succeeded) DY778ScheduleRecallNotification(); });
    }
    Class converter = NSClassFromString(@"AWEIMMessageConventor"), messageClass = NSClassFromString(@"AWEIMMessage");
    SEL convert = NSSelectorFromString(@"convertMessageFromTIMOMessage:chatModelType:");
    SEL setup = NSSelectorFromString(@"setupWithMessageViewModel:conversation:");
    SEL rebuild = NSSelectorFromString(@"reBuildComponentWithConfigCell:");
    if (!DY778RestoreSignature(converter, convert, '@', "@q") || !DY778RestoreSignature(componentContext, setup, 'v', "@@") || !DY778RestoreSignature(viewModel, rebuild, 'v', "B")) return NO;
    id oldPresentation = DY778Read(viewModel, @"message");
    long long chatModelType = [DY778Read(oldPresentation, @"chatModelType") longLongValue];
    DY778NativeRestoreInProgress = YES;
    BOOL replaced = NO;
    @try {
        id presentation = ((id (*)(id, SEL, id, long long))objc_msgSend)(converter, convert, message, chatModelType);
        if (![presentation isKindOfClass:messageClass] || [presentation isKindOfClass:NSClassFromString(@"AWEIMRecallMessage")] || [DY778Read(presentation, @"isSliverLoadingFakeMessage") boolValue]) return NO;
        if (DY778Read(viewModel, @"iesMessage") != message || !DY778FastAllowed(state)) return NO;
        if (!DY778Write(viewModel, @"message", presentation)) return NO;
        replaced = YES;
        ((void (*)(id, SEL, id, id))objc_msgSend)(componentContext, setup, viewModel, DY778Read(viewModel, @"conversation"));
        ((void (*)(id, SEL, BOOL))objc_msgSend)(viewModel, rebuild, YES);
        if (DY778Read(viewModel, @"message") != presentation || DY778Read(componentContext, @"message") != presentation) return NO;
        attempt.succeeded = YES; return YES;
    } @catch (__unused NSException *exception) { return NO; }
    @finally {
        if (replaced && !attempt.succeeded && DY778Read(viewModel, @"iesMessage") == message) {
            @try {
                DY778Write(viewModel, @"message", oldPresentation);
                ((void (*)(id, SEL, id, id))objc_msgSend)(componentContext, setup, viewModel, DY778Read(viewModel, @"conversation"));
            } @catch (__unused NSException *exception) {}
        }
        DY778NativeRestoreInProgress = NO;
    }
}
static BOOL DY778RecallHookChecked(Class cls, NSString *selectorName, IMP replacement, IMP *original, unsigned int arguments, char resultType, char parameterType) {
    if (*original) return YES;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != arguments) return NO;
    char *result = method_copyReturnType(method);
    BOOL compatible = result && (result[0] == resultType || (resultType == 'B' && result[0] == 'c')); free(result);
    if (compatible && arguments > 2 && parameterType) {
        char *parameter = method_copyArgumentType(method, 2);
        compatible = parameter && (parameter[0] == parameterType || (parameterType == 'B' && parameter[0] == 'c'));
        free(parameter);
    }
    return compatible && DY778Hook(cls, selector, replacement, original);
}

void DY778InstallRecallHooks(void) {
    [DY778RecallStore shared];
    DY778RefreshRecallPolicy();
    static dispatch_once_t observerOnce; dispatch_once(&observerOnce, ^{
        for (NSNotificationName name in @[DY778PreferencesChangedNotification, DY778RecallChangedNotification, UIApplicationDidBecomeActiveNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(__unused NSNotification *note) { DY778RefreshRecallPolicy(); }];
    });
    DY778RecordHook(@"撤回记录 · 消息身份", DY778RecallHookChecked(NSClassFromString(@"AWEIMMessageViewModel"), @"setupWithMessage:", (IMP)DY778VMSetupHook, (IMP *)&DY778OriginalVMSetup, 3, 'v', '@'));
    DY778RecordHook(@"撤回记录 · 会话身份", DY778RecallHookChecked(NSClassFromString(@"AWEIMMessageViewModel"), @"setConversation:", (IMP)DY778VMConversationHook, (IMP *)&DY778OriginalVMConversation, 3, 'v', '@'));
    Class message = NSClassFromString(@"TIMXOMessage");
    DY778RecordHook(@"编辑历史 · 编辑版本", DY778RecallHookChecked(message, @"setEditInfo:", (IMP)DY778SetEditInfoHook, (IMP *)&DY778OriginalSetEditInfo, 3, 'v', '@'));
    DY778RecordHook(@"防撤回 · 原始内容", DY778RecallHookChecked(message, @"content", (IMP)DY778ContentHook, (IMP *)&DY778OriginalContent, 2, '@', 0));
    DY778RecordHook(@"防撤回 · 内容更新", DY778RecallHookChecked(message, @"setContent:", (IMP)DY778SetContentHook, (IMP *)&DY778OriginalSetContent, 3, 'v', '@'));
    DY778RecordHook(@"防撤回 · 状态读取", DY778RecallHookChecked(message, @"recalled", (IMP)DY778RecalledHook, (IMP *)&DY778OriginalRecalled, 2, 'B', 0));
    DY778RecordHook(@"防撤回 · 撤回状态", DY778RecallHookChecked(message, @"setRecalled:", (IMP)DY778SetRecalledHook, (IMP *)&DY778OriginalSetRecalled, 3, 'v', 'B'));
    DY778RecordHook(@"防撤回 · 召回正文", DY778RecallHookChecked(message, @"setRecalledContent:", (IMP)DY778RecalledContentHook, (IMP *)&DY778OriginalSetRecalledContent, 3, 'v', '@'));
    DY778RecordHook(@"防撤回 · 模型快照", DY778RecallHookChecked(message, @"applyAttributesFromModel:", (IMP)DY778ApplyHook, (IMP *)&DY778OriginalApply, 3, 'v', '@'));
    DY778RecordHook(@"防撤回 · V2 模型快照", DY778RecallHookChecked(message, @"applyAttributesFromModelV2:", (IMP)DY778ApplyV2Hook, (IMP *)&DY778OriginalApplyV2, 3, 'v', '@'));
    DY778RecordHook(@"聊天信息 · 撤回记录入口", DY778RecallHookChecked(NSClassFromString(@"IESIMChatSettingsListViewModelProviderComponent"), @"createSectionViewModels", (IMP)DY778ChatSectionsHook, (IMP *)&DY778OriginalChatSections, 2, '@', 0));
}
