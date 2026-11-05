#import "DY778EditHistory.h"
#import "DY778EditContent.h"
#import "DY778ArchiveStorage.h"
#import "DY778EditPolicy.h"
#import "DY778Recall.h"
#import "DY778RecallContent.h"
#import "DY778Avatar.h"
#import <sqlite3.h>
#import <stdatomic.h>

NSNotificationName const DY778EditHistoryChangedNotification = @"DY778EditHistoryChanged";
NSNotificationName const DY778EditDetectedNotification = @"DY778EditDetected";
static atomic_bool DY778EditSwitch;
static char kDY778EditState, kDY778EditContext;
@interface DY778EditBinding : NSObject
@property(atomic, copy) NSDictionary *record;
@property(atomic, copy) NSDictionary *identity;
@end
@implementation DY778EditBinding @end
static DY778EditBinding *DY778EditBindingFor(id message) {
    if (!message) return nil;
    @synchronized(message) {
        DY778EditBinding *state = objc_getAssociatedObject(message, &kDY778EditState);
        if (!state) { state = [DY778EditBinding new]; objc_setAssociatedObject(message, &kDY778EditState, state, OBJC_ASSOCIATION_RETAIN); }
        return state;
    }
}
BOOL DY778EditCaptureEnabled(void) { return atomic_load_explicit(&DY778EditSwitch, memory_order_relaxed); }
static NSString *DY778EditScope(NSString *account, NSString *conversation) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[account ?: @"", conversation ?: @""] options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
static BOOL DY778EditAllowed(NSString *account, NSString *conversation) {
    if (!DY778EditCaptureEnabled() || !account.length || !conversation.length) return NO;
    id disabled = [DY778Preferences() objectForKey:@"edit.disabledConversations"];
    return !([disabled isKindOfClass:NSDictionary.class] && [disabled[DY778EditScope(account, conversation)] boolValue]);
}
BOOL DY778EditEnabledForConversation(NSString *conversation) { return DY778EditAllowed(DY778CurrentAccountID(), conversation); }
void DY778SetConversationEditEnabled(NSString *conversation, BOOL enabled) {
    NSString *account = DY778CurrentAccountID(); if (!account.length || !conversation.length) return;
    @synchronized(DY778Preferences()) {
        id old = [DY778Preferences() objectForKey:@"edit.disabledConversations"];
        NSMutableDictionary *disabled = [old isKindOfClass:NSDictionary.class] ? [old mutableCopy] : [NSMutableDictionary dictionary];
        NSString *key = DY778EditScope(account, conversation); if (enabled) [disabled removeObjectForKey:key]; else disabled[key] = @YES;
        DY778Set(@"edit.disabledConversations", disabled);
    }
}
NSDictionary *DY778EditInfoSnapshot(id info) {
    if (!info) return nil;
    return @{@"edited": @([DY778Read(info, @"isEdited") boolValue] || [DY778Read(info, @"content_is_edited") boolValue]),
        @"editTime": @(DY778MessageTimestamp(DY778Read(info, @"editTime") ?: DY778Read(info, @"content_edit_time"))),
        @"editCount": DY778Read(info, @"editCount") ?: DY778Read(info, @"content_edit_count") ?: @0,
        @"editor": DY778Identifier(DY778Read(info, @"editUid") ?: DY778Read(info, @"content_editor")) ?: @""};
}
static NSDictionary *DY778EditImmutable(id value) {
    if (![value isKindOfClass:NSDictionary.class] || ![NSJSONSerialization isValidJSONObject:value]) return nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (data.length > 1024 * 1024) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}
static void DY778EditBind(sqlite3_stmt *statement, int index, NSString *value) { sqlite3_bind_text(statement, index, (value ?: @"").UTF8String, -1, SQLITE_TRANSIENT); }
static NSDictionary *DY778EditDecode(sqlite3_stmt *statement, int index) {
    const void *bytes = sqlite3_column_blob(statement, index); int size = sqlite3_column_bytes(statement, index);
    if (!bytes || size <= 0) return nil;
    id result = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:(NSUInteger)size] options:0 error:nil];
    return [result isKindOfClass:NSDictionary.class] ? result : nil;
}
static void DY778EditNotify(void) {
    static BOOL queued;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (queued) return; queued = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            queued = NO; [NSNotificationCenter.defaultCenter postNotificationName:DY778EditHistoryChangedNotification object:nil];
        });
    });
}
@interface DY778EditStore : NSObject
@property(nonatomic) sqlite3 *database;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) NSHashTable<DY778EditBinding *> *bindings;
@property(atomic, copy) NSString *status;
@property(nonatomic) NSTimeInterval lastMaintenance;
+ (instancetype)shared;
- (void)observe:(id)message content:(NSDictionary *)content info:(NSDictionary *)info observedAt:(NSTimeInterval)observedAt account:(NSString *)eventAccount recalled:(BOOL)recalled;
- (NSDictionary *)recordForKey:(NSString *)key account:(NSString *)account;
- (void)remove:(NSString *)account conversation:(NSString *)conversation key:(NSString *)key;
- (void)maintenance;
@end
@implementation DY778EditStore
+ (instancetype)shared { static DY778EditStore *store; static dispatch_once_t once; dispatch_once(&once, ^{ store = [self new]; }); return store; }
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.dy778.edit-history", DISPATCH_QUEUE_SERIAL); _bindings = [NSHashTable weakObjectsHashTable];
        _status = @"正在准备编辑历史"; dispatch_async(_queue, ^{ [self open]; });
    } return self;
}
- (void)open {
    NSURL *root = DY778ArchiveDirectory(@"EditHistory");
    if (!root) { self.status = @"编辑历史目录不可写"; return; }
    NSString *path = [root URLByAppendingPathComponent:@"history.sqlite"].path;
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(path.UTF8String, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) { if (db) sqlite3_close(db); self.status = @"编辑历史数据库暂不可用"; return; }
    sqlite3_busy_timeout(db, 1500);
    const char *schema = "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA secure_delete=ON;"
        "CREATE TABLE IF NOT EXISTS edits(key TEXT PRIMARY KEY,account TEXT NOT NULL,conversation TEXT NOT NULL,server_id TEXT NOT NULL,created REAL NOT NULL,seen REAL NOT NULL,edited_at REAL NOT NULL,changes INTEGER NOT NULL,payload BLOB NOT NULL);"
        "CREATE INDEX IF NOT EXISTS edit_conversation ON edits(account,conversation,edited_at);"
        "CREATE INDEX IF NOT EXISTS edit_server ON edits(account,conversation,server_id);"
        "CREATE TABLE IF NOT EXISTS forgotten(key TEXT PRIMARY KEY,account TEXT NOT NULL);"
        "CREATE TRIGGER IF NOT EXISTS reject_deleted_edit BEFORE INSERT ON edits WHEN EXISTS(SELECT 1 FROM forgotten WHERE key=NEW.key) BEGIN SELECT RAISE(IGNORE); END;";
    if (sqlite3_exec(db, schema, NULL, NULL, NULL) != SQLITE_OK) { sqlite3_close(db); self.status = @"编辑历史初始化失败"; return; }
    self.database = db;
    [NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:path error:nil];
    self.status = @"本机保存 · 按账号与会话隔离"; [self maintenance];
}
- (NSDictionary *)recordForKey:(NSString *)key account:(NSString *)account {
    sqlite3_stmt *statement = NULL; NSDictionary *record = nil;
    if (self.database && key.length && sqlite3_prepare_v2(self.database, "SELECT payload FROM edits WHERE key=? AND account=?", -1, &statement, NULL) == SQLITE_OK) {
        DY778EditBind(statement, 1, key); DY778EditBind(statement, 2, account);
        if (sqlite3_step(statement) == SQLITE_ROW) record = DY778EditDecode(statement, 0);
    }
    sqlite3_finalize(statement); return record;
}
- (void)publish:(NSDictionary *)record identity:(NSDictionary *)identity {
    for (DY778EditBinding *binding in self.bindings.allObjects) {
        NSDictionary *bound = binding.identity;
        if (![bound[@"account"] isEqual:identity[@"account"]] || ![bound[@"conversation"] isEqual:identity[@"conversation"]]) continue;
        if ([bound[@"key"] isEqual:identity[@"key"]] || ([bound[@"serverID"] length] && ![bound[@"serverID"] isEqual:@"0"] && [bound[@"serverID"] isEqual:identity[@"serverID"]])) binding.record = record;
    }
}
- (void)observe:(id)message content:(NSDictionary *)content info:(NSDictionary *)info observedAt:(NSTimeInterval)observedAt account:(NSString *)eventAccount recalled:(BOOL)recalled {
    if (!self.database || !DY778EditCaptureEnabled()) return;
    BOOL capturedEvent = info != nil && content != nil;
    DY778EditBinding *binding = DY778EditBindingFor(message);
    NSDictionary *identity = DY778MessageIdentity(message); if (!identity) return;
    NSString *account = identity[@"account"], *conversation = identity[@"conversation"], *sender = identity[@"sender"];
    if ((eventAccount.length && ![eventAccount isEqual:account]) || ![account isEqual:DY778CurrentAccountID()] || !DY778EditAllowed(account, conversation) || !sender.length || [sender isEqual:@"0"] || [sender isEqual:account]) return;
    binding.identity = identity; [self.bindings addObject:binding];
    NSString *key = identity[@"key"];
    NSDictionary *prior = [self recordForKey:key account:account];
    sqlite3_stmt *statement = NULL;
    if (!prior && [identity[@"serverID"] length] && ![identity[@"serverID"] isEqual:@"0"] && sqlite3_prepare_v2(self.database, "SELECT payload FROM edits WHERE account=? AND conversation=? AND server_id=? LIMIT 1", -1, &statement, NULL) == SQLITE_OK) {
        DY778EditBind(statement, 1, account); DY778EditBind(statement, 2, conversation); DY778EditBind(statement, 3, identity[@"serverID"]);
        if (sqlite3_step(statement) == SQLITE_ROW) prior = DY778EditDecode(statement, 0);
    }
    sqlite3_finalize(statement); statement = NULL;
    if (prior) key = prior[@"key"];
    BOOL forgotten = NO;
    if (sqlite3_prepare_v2(self.database, "SELECT 1 FROM forgotten WHERE key=? AND account=?", -1, &statement, NULL) == SQLITE_OK) {
        DY778EditBind(statement, 1, key); DY778EditBind(statement, 2, account); forgotten = sqlite3_step(statement) == SQLITE_ROW;
    }
    sqlite3_finalize(statement); if (forgotten) { binding.record = nil; return; }
    BOOL newlyBound = !binding.record && [prior[@"changes"] unsignedIntegerValue] > 0;
    binding.record = prior;
    // 没有取到编辑元数据时，这是首次填充而非一次版本
    // 事件。正文与元数据一起读取；绝不把旧正文配上更晚的元数据。
    if (!info) {
        content = DY778EditImmutable(DY778Read(message, @"content"));
        info = DY778EditInfoSnapshot(DY778Read(message, @"editInfo"));
    } else if (!content) {
        if (newlyBound) DY778EditNotify(); return;
    }
    if (!info) {
        id synced = DY778Read(message, @"syncedExt");
        id encoded = [synced isKindOfClass:NSDictionary.class] ? synced[@"s:edit_info"] : nil;
        if ([encoded isKindOfClass:NSString.class]) encoded = [NSJSONSerialization JSONObjectWithData:[encoded dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        info = DY778EditInfoSnapshot(encoded);
    }
    NSMutableDictionary *event = [identity mutableCopy]; event[@"key"] = key;
    [event addEntriesFromDictionary:info ?: @{}]; event[@"content"] = content ?: @{};
    event[@"observedAt"] = @(observedAt); event[@"recalled"] = @(recalled);
    [event addEntriesFromDictionary:objc_getAssociatedObject(message, &kDY778EditContext) ?: @{}];
    NSDictionary *senderProfile = DY778ProfileFromUser(DY778Read(message, @"senderProfile"));
    if ([senderProfile[@"uid"] length] && ![senderProfile[@"uid"] isEqual:sender]) senderProfile = @{};
    if (![event[@"senderName"] length] && [senderProfile[@"name"] length]) event[@"senderName"] = senderProfile[@"name"];
    if (![event[@"senderAvatar"] length] && [senderProfile[@"avatar"] length]) event[@"senderAvatar"] = senderProfile[@"avatar"];
    NSDictionary *merged = DY778MergeEditRecord(prior, event);
    if (!merged || merged == prior || [merged isEqual:prior]) { if (newlyBound) DY778EditNotify(); return; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:merged options:0 error:nil]; if (!data) return;
    const char *save = "INSERT INTO edits(key,account,conversation,server_id,created,seen,edited_at,changes,payload) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(key) DO UPDATE SET server_id=excluded.server_id,seen=excluded.seen,edited_at=excluded.edited_at,changes=excluded.changes,payload=excluded.payload";
    statement = NULL; BOOL saved = NO;
    if (sqlite3_prepare_v2(self.database, save, -1, &statement, NULL) == SQLITE_OK) {
        DY778EditBind(statement, 1, key); DY778EditBind(statement, 2, account); DY778EditBind(statement, 3, conversation); DY778EditBind(statement, 4, identity[@"serverID"]);
        sqlite3_bind_double(statement, 5, [merged[@"createdAt"] doubleValue]); sqlite3_bind_double(statement, 6, [event[@"observedAt"] doubleValue]);
        sqlite3_bind_double(statement, 7, [merged[@"lastEditAt"] doubleValue]); sqlite3_bind_int64(statement, 8, [merged[@"changes"] longLongValue]);
        sqlite3_bind_blob(statement, 9, data.bytes, (int)data.length, SQLITE_TRANSIENT); saved = sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(self.database) > 0;
    }
    sqlite3_finalize(statement);
    if (!saved) { self.status = @"编辑历史保存失败，请检查剩余空间"; return; }
    [self publish:merged identity:identity]; binding.record = merged;
    if ([merged[@"changes"] unsignedIntegerValue]) DY778EditNotify();
    if (DY778EditShouldNotify(prior != nil, capturedEvent, [prior[@"changes"] longLongValue], [merged[@"changes"] longLongValue])) {
        NSMutableDictionary *notice = [NSMutableDictionary dictionary];
        for (NSString *field in @[@"key", @"account", @"conversation", @"senderName", @"senderAvatar", @"conversationName", @"summary", @"changes"]) if (merged[field]) notice[field] = merged[field];
        notice[@"noticeKind"] = @"edit";
        NSDictionary *version = [merged[@"versions"] lastObject];
        notice[@"noticeVersion"] = [NSString stringWithFormat:@"%@|%@|%@", merged[@"changes"], version[@"editTime"], version[@"observedAt"]];
        NSDictionary *savedNotice = [notice copy];
        dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:DY778EditDetectedNotification object:nil userInfo:@{@"record": savedNotice}]; });
    }
    if (NSDate.date.timeIntervalSince1970 - self.lastMaintenance > 60) [self maintenance];
}
- (void)remove:(NSString *)account conversation:(NSString *)conversation key:(NSString *)key {
    if (!account.length) return;
    dispatch_async(self.queue, ^{
        if (!self.database) return;
        const char *select = "SELECT key FROM edits WHERE account=? AND (?='' OR conversation=?) AND (?='' OR key=?)";
        sqlite3_stmt *statement = NULL; NSMutableSet *keys = [NSMutableSet set];
        BOOL ok = sqlite3_exec(self.database, "BEGIN IMMEDIATE", NULL, NULL, NULL) == SQLITE_OK;
        if (ok) ok = sqlite3_prepare_v2(self.database, select, -1, &statement, NULL) == SQLITE_OK;
        if (ok) {
            DY778EditBind(statement, 1, account); DY778EditBind(statement, 2, conversation); DY778EditBind(statement, 3, conversation); DY778EditBind(statement, 4, key); DY778EditBind(statement, 5, key);
            int step; while ((step = sqlite3_step(statement)) == SQLITE_ROW) [keys addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)]];
            ok = step == SQLITE_DONE;
        }
        sqlite3_finalize(statement);
        for (NSString *recordKey in keys) {
            if (!ok) break; statement = NULL;
            ok = sqlite3_prepare_v2(self.database, "INSERT OR IGNORE INTO forgotten(key,account) VALUES(?,?)", -1, &statement, NULL) == SQLITE_OK;
            if (ok) { DY778EditBind(statement, 1, recordKey); DY778EditBind(statement, 2, account); ok = sqlite3_step(statement) == SQLITE_DONE; }
            sqlite3_finalize(statement); statement = NULL;
            if (ok) ok = sqlite3_prepare_v2(self.database, "DELETE FROM edits WHERE key=? AND account=?", -1, &statement, NULL) == SQLITE_OK;
            if (ok) { DY778EditBind(statement, 1, recordKey); DY778EditBind(statement, 2, account); ok = sqlite3_step(statement) == SQLITE_DONE; }
            sqlite3_finalize(statement);
        }
        if (ok) ok = sqlite3_exec(self.database, "COMMIT", NULL, NULL, NULL) == SQLITE_OK;
        if (!ok) sqlite3_exec(self.database, "ROLLBACK", NULL, NULL, NULL);
        if (ok) for (DY778EditBinding *binding in self.bindings.allObjects) if ([keys containsObject:binding.record[@"key"]]) binding.record = nil;
        DY778EditNotify(); dispatch_async(dispatch_get_main_queue(), ^{ DY778Toast(ok ? @"编辑历史已删除" : @"删除失败，请重试"); });
    });
}
- (void)maintenance {
    if (!self.database) return; self.lastMaintenance = NSDate.date.timeIntervalSince1970;
    double days = MAX(0, DY778Number(@"edit.retentionDays")); long long limit = MAX(0, DY778Number(@"edit.maxRecords"));
    sqlite3_stmt *statement = NULL; BOOL changed = NO;
    if (days > 0 && sqlite3_prepare_v2(self.database, "DELETE FROM edits WHERE CASE WHEN changes>0 THEN edited_at ELSE seen END<?", -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_double(statement, 1, self.lastMaintenance - days * 86400); changed = sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(self.database) > 0;
    }
    sqlite3_finalize(statement); statement = NULL;
    if (limit > 0 && sqlite3_prepare_v2(self.database, "DELETE FROM edits WHERE key IN (SELECT key FROM (SELECT key,ROW_NUMBER() OVER(PARTITION BY account ORDER BY changes>0 DESC,edited_at DESC,seen DESC) AS rn FROM edits) WHERE rn>?)", -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(statement, 1, limit); if (sqlite3_step(statement) == SQLITE_DONE) changed |= sqlite3_changes(self.database) > 0;
    }
    sqlite3_finalize(statement);
    if (changed) {
        for (DY778EditBinding *binding in self.bindings.allObjects) binding.record = [self recordForKey:binding.record[@"key"] account:binding.identity[@"account"]];
        DY778EditNotify();
    }
}
@end

void DY778ObserveEditedMessage(id message, NSDictionary *content, NSDictionary *editInfo) {
    if (!message || !DY778EditCaptureEnabled()) return;
    NSDictionary *snapshot = DY778EditImmutable(content), *info = [editInfo copy];
    DY778EditStore *store = [DY778EditStore shared];
    NSTimeInterval observedAt = NSDate.date.timeIntervalSince1970;
    NSString *account = ((DY778EditBinding *)objc_getAssociatedObject(message, &kDY778EditState)).identity[@"account"];
    BOOL recalled = DY778MessageWasRecalled(message);
    dispatch_async(store.queue, ^{ @autoreleasepool { [store observe:message content:snapshot info:info observedAt:observedAt account:account recalled:recalled]; } });
}
void DY778ObserveEditContext(id viewModel) {
    if (!viewModel || !DY778EditCaptureEnabled()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        id message = DY778Read(viewModel, @"iesMessage"); if (!message) return;
        id presentation = DY778Read(viewModel, @"message");
        NSDictionary *sender = DY778ProfileFromUser(DY778Read(presentation, @"fromUser"));
        NSString *uid = DY778Identifier(DY778Read(message, @"sender"));
        NSMutableDictionary *context = [NSMutableDictionary dictionary];
        if ([sender[@"uid"] isEqual:uid]) {
            if ([sender[@"name"] length]) context[@"senderName"] = sender[@"name"];
            if ([sender[@"avatar"] length]) context[@"senderAvatar"] = sender[@"avatar"];
        }
        id conversation = DY778Read(viewModel, @"conversation");
        BOOL group = !DY778Read(conversation, @"peerUser") && ![DY778Identifier(DY778Read(conversation, @"peerUserID")) length];
        NSString *name = DY778Identifier(DY778Read(conversation, @"name"));
        if (name.length) context[@"conversationName"] = name; context[@"group"] = @(group);
        objc_setAssociatedObject(message, &kDY778EditContext, context, OBJC_ASSOCIATION_RETAIN);
        DY778ObserveEditedMessage(message, nil, nil);
    });
}
NSDictionary *DY778EditRecordForMessage(id message) {
    DY778EditBinding *binding = objc_getAssociatedObject(message, &kDY778EditState);
    NSDictionary *record = binding.record;
    return [record[@"account"] isEqual:DY778CurrentAccountID()] && DY778EditAllowed(record[@"account"], record[@"conversation"]) && [record[@"changes"] unsignedIntegerValue] ? record : nil;
}
void DY778ClearEditHistory(void) { [[DY778EditStore shared] remove:DY778CurrentAccountID() conversation:nil key:nil]; }
void DY778EditHistoryMaintenance(void) { DY778EditStore *store = [DY778EditStore shared]; dispatch_async(store.queue, ^{ [store maintenance]; }); }
NSString *DY778EditHistoryStatus(void) { return [DY778EditStore shared].status; }
void DY778InstallEditHistory(void) {
    atomic_store_explicit(&DY778EditSwitch, DY778Bool(@"edit.enabled"), memory_order_relaxed);
    [DY778EditStore shared]; static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            atomic_store_explicit(&DY778EditSwitch, DY778Bool(@"edit.enabled"), memory_order_relaxed);
            NSString *key = note.userInfo[@"key"];
            if (!key.length || [key hasPrefix:@"edit."]) { DY778EditHistoryMaintenance(); DY778EditNotify(); }
        }];
    });
}

static NSString *DY778EditDate(double time) {
    if (time <= 0) return @"未知";
    NSDateFormatter *format = [NSDateFormatter new]; format.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    format.dateFormat = @"yyyy-MM-dd HH:mm:ss"; format.timeZone = NSTimeZone.localTimeZone;
    return [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]];
}
static NSString *DY778EditVersionText(NSDictionary *version) { return [version[@"text"] length] ? version[@"text"] : (version[@"summary"] ?: @"未取得可显示的内容"); }
@interface DY778EditHistoryController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *conversation;
@property(nonatomic, copy) NSString *messageKey;
@property(nonatomic, copy) NSDictionary *detail;
@property(nonatomic, copy) NSArray *rows;
@property(nonatomic, copy) NSArray *filtered;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL loading;
@property(nonatomic) BOOL more;
- (void)reload;
@end
@implementation DY778EditHistoryController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; DY778StyleController(self);
    self.title = self.messageKey.length ? @"消息编辑历史" : (self.conversation.length ? @"此会话的编辑历史" : @"编辑历史 · 会话");
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 120; self.tableView.backgroundColor = DY778Background();
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    if (!self.messageKey.length) {
        self.search = [[UISearchController alloc] initWithSearchResultsController:nil]; self.search.obscuresBackgroundDuringPresentation = NO;
        self.search.searchResultsUpdater = self; self.search.searchBar.placeholder = self.conversation.length ? @"搜索已加载的原文与编辑版本" : @"搜索会话";
        self.navigationItem.searchController = self.search; self.definesPresentationContext = YES;
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(deleteCurrent)];
    self.refreshControl = [UIRefreshControl new]; [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    for (NSNotificationName name in @[DY778EditHistoryChangedNotification, UIApplicationDidBecomeActiveNotification]) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:name object:nil];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; DY778StyleController(self); [self reload]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)reload {
    self.rows = @[]; self.detail = nil; self.more = NO; self.loading = NO; self.generation++;
    if (![self.account isEqual:DY778CurrentAccountID()]) { [self applyFilter]; [self.refreshControl endRefreshing]; return; }
    [self loadMore];
}
- (void)loadMore {
    if (self.loading || ![self.account isEqual:DY778CurrentAccountID()]) return;
    self.loading = YES; NSUInteger generation = ++self.generation, offset = self.rows.count;
    NSString *account = self.account, *conversation = self.conversation, *key = self.messageKey;
    DY778EditStore *store = [DY778EditStore shared]; __weak typeof(self) weakSelf = self;
    dispatch_async(store.queue, ^{
        NSMutableArray *rows = [NSMutableArray array]; NSDictionary *detail = nil; sqlite3_stmt *statement = NULL;
        if (key.length) {
            detail = [store recordForKey:key account:account];
            if ([detail[@"conversation"] isEqual:conversation]) [rows addObjectsFromArray:detail[@"versions"] ?: @[]]; else detail = nil;
        } else if (conversation.length) {
            const char *sql = "SELECT payload FROM edits WHERE account=? AND conversation=? AND changes>0 ORDER BY edited_at DESC,key DESC LIMIT 100 OFFSET ?";
            if (store.database && sqlite3_prepare_v2(store.database, sql, -1, &statement, NULL) == SQLITE_OK) {
                DY778EditBind(statement, 1, account); DY778EditBind(statement, 2, conversation); sqlite3_bind_int64(statement, 3, offset);
                while (sqlite3_step(statement) == SQLITE_ROW) { NSDictionary *record = DY778EditDecode(statement, 0); if (record) [rows addObject:record]; }
            }
        } else {
            const char *sql = "SELECT conversation,COUNT(*),SUM(changes),MAX(edited_at),payload FROM edits WHERE account=? AND changes>0 GROUP BY conversation ORDER BY MAX(edited_at) DESC";
            if (store.database && sqlite3_prepare_v2(store.database, sql, -1, &statement, NULL) == SQLITE_OK) {
                DY778EditBind(statement, 1, account);
                while (sqlite3_step(statement) == SQLITE_ROW) {
                    NSDictionary *record = DY778EditDecode(statement, 4); if (!record) continue;
                    NSString *name = [record[@"conversationName"] length] ? record[@"conversationName"] : ([record[@"senderName"] length] ? record[@"senderName"] : @"未命名会话");
                    [rows addObject:@{@"conversation": [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)], @"name": name,
                        @"sender": record[@"sender"] ?: @"", @"group": record[@"group"] ?: @NO, @"messages": @(sqlite3_column_int64(statement, 1)), @"changes": @(sqlite3_column_int64(statement, 2)),
                        @"time": @(sqlite3_column_double(statement, 3)), @"summary": record[@"summary"] ?: @""}];
                }
            }
        }
        sqlite3_finalize(statement);
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self || generation != self.generation || ![account isEqual:DY778CurrentAccountID()]) return;
            self.loading = NO; self.detail = detail; self.rows = [self.rows ?: @[] arrayByAddingObjectsFromArray:rows];
            self.more = !key.length && conversation.length && rows.count == 100;
            [self.refreshControl endRefreshing]; [self applyFilter];
        });
    });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyFilter]; }
- (void)applyFilter {
    NSString *query = [self.search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *row in self.rows) {
        NSMutableString *text = [NSMutableString stringWithFormat:@"%@ %@ %@", row[@"name"] ?: @"", row[@"senderName"] ?: @"", row[@"summary"] ?: @""];
        for (NSDictionary *version in row[@"versions"]) [text appendFormat:@" %@", DY778EditVersionText(version)];
        if (!query.length || [text localizedCaseInsensitiveContainsString:query]) [filtered addObject:row];
    }
    self.filtered = filtered;
    if (!filtered.count) {
        UILabel *empty = [UILabel new]; empty.numberOfLines = 0; empty.textAlignment = NSTextAlignmentCenter; empty.textColor = UIColor.secondaryLabelColor;
        empty.text = ![self.account isEqual:DY778CurrentAccountID()] ? @"账号已切换，请返回后重新打开。" : (query.length ? @"没有匹配的记录" : (self.messageKey.length ? @"这条消息的编辑历史已删除" : @"暂无编辑历史\n开启后收到的编辑版本会显示在这里"));
        self.tableView.backgroundView = empty;
    } else self.tableView.backgroundView = nil;
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.messageKey.length && self.detail ? 2 : 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.messageKey.length && self.detail && section == 0) return 1;
    return self.filtered.count + (self.more ? 1 : 0);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.messageKey.length) return section == 0 ? @"消息与时间" : @"按收到的版本顺序";
    return [NSString stringWithFormat:self.conversation.length ? @"已加载 %lu 条编辑过的消息" : @"%lu 个会话", (unsigned long)self.filtered.count];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.messageKey.length && section == 0) return [self.detail[@"originalMissing"] boolValue] ? @"首次接收时消息已经编辑，未取得编辑前原文。" : @"发送时间是原消息时间；首次留存时间是本机开始记录的时间。";
    return @"仅记录启用后本机实际收到的版本。离线或应用被挂起期间的中间版本可能缺失；没有服务端编辑时间时显示本机发现时间。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = DY778CardBackground(); cell.textLabel.textColor = UIColor.labelColor; cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0; cell.textLabel.adjustsFontForContentSizeCategory = YES; cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    if (self.messageKey.length && self.detail && path.section == 0) {
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · 已留存 %@ 次编辑", [self.detail[@"senderName"] length] ? self.detail[@"senderName"] : @"对方", self.detail[@"changes"]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"原消息发送：%@\n首次留存：%@\n最近编辑 / 发现：%@", DY778EditDate([self.detail[@"createdAt"] doubleValue]), DY778EditDate([self.detail[@"firstObservedAt"] doubleValue]), DY778EditDate([self.detail[@"lastEditAt"] doubleValue])];
        cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell;
    }
    if ((NSUInteger)path.row >= self.filtered.count) { cell.textLabel.text = self.loading ? @"正在加载…" : @"加载更早的记录"; return cell; }
    NSDictionary *row = self.filtered[path.row];
    if (self.messageKey.length) {
        cell.textLabel.text = DY778EditVersionText(row);
        BOOL edited = [row[@"edited"] boolValue]; NSString *label = edited ? [NSString stringWithFormat:@"编辑版本 %lu", (unsigned long)path.row + ([self.detail[@"originalMissing"] boolValue] ? 1 : 0)] : @"原始消息";
        if ((NSUInteger)path.row == self.filtered.count - 1) label = [label stringByAppendingString:@" · 最新已留存版本"];
        NSString *time = edited ? ([row[@"editTime"] doubleValue] > 0 ? [@"编辑时间：" stringByAppendingString:DY778EditDate([row[@"editTime"] doubleValue])] : [@"发现时间：" stringByAppendingString:DY778EditDate([row[@"observedAt"] doubleValue])]) : [@"发送时间：" stringByAppendingString:DY778EditDate([self.detail[@"createdAt"] doubleValue])];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@\n本机接收：%@", label, time, DY778EditDate([row[@"observedAt"] doubleValue])];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (self.conversation.length) {
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · 留存 %@ 次编辑", [row[@"senderName"] length] ? row[@"senderName"] : @"对方", row[@"changes"]];
        NSString *original = [row[@"originalMissing"] boolValue] ? @"原文未取得" : DY778EditVersionText([row[@"versions"] firstObject]);
        cell.detailTextLabel.text = [NSString stringWithFormat:@"发送：%@\n最近编辑 / 发现：%@\n原文：%@\n最新：%@", DY778EditDate([row[@"createdAt"] doubleValue]), DY778EditDate([row[@"lastEditAt"] doubleValue]), original, DY778EditVersionText([row[@"versions"] lastObject])];
        cell.detailTextLabel.numberOfLines = 6; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = row[@"name"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 条消息 · 留存 %@ 次编辑\n最近：%@\n%@", row[@"messages"], row[@"changes"], DY778EditDate([row[@"time"] doubleValue]), row[@"summary"]];
        cell.detailTextLabel.numberOfLines = 4; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (![row[@"group"] boolValue] && [row[@"name"] isEqual:@"未命名会话"]) {
            __weak UITableViewCell *weakCell = cell; NSString *account = self.account;
            DY778GetLocalUserProfile(account, row[@"sender"], ^(NSDictionary *profile) { if ([account isEqual:DY778CurrentAccountID()] && [profile[@"name"] length]) weakCell.textLabel.text = profile[@"name"]; });
        }
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if (![self.account isEqual:DY778CurrentAccountID()]) return;
    if (self.messageKey.length) return;
    if ((NSUInteger)path.row >= self.filtered.count) { [self loadMore]; return; }
    NSDictionary *row = self.filtered[path.row];
    DY778PresentEditHistory(self, self.conversation.length ? self.conversation : row[@"conversation"], self.conversation.length ? row[@"key"] : nil);
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)path point:(CGPoint)point {
    if (!self.messageKey.length || path.section != 1 || (NSUInteger)path.row >= self.filtered.count) return nil;
    NSDictionary *version = self.filtered[path.row];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested) {
        return [UIMenu menuWithTitle:@"" children:@[[UIAction actionWithTitle:@"复制这个版本" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__unused UIAction *action) {
            if (![self.account isEqual:DY778CurrentAccountID()]) return; UIPasteboard.generalPasteboard.string = DY778EditVersionText(version); DY778Toast(@"已复制");
        }]]];
    }];
}
- (void)deleteConversation:(NSString *)conversation key:(NSString *)key {
    NSString *account = self.account; if (![account isEqual:DY778CurrentAccountID()]) return;
    NSString *title = key.length ? @"删除这条消息的编辑历史？" : (conversation.length ? @"删除此会话的编辑历史？" : @"清空当前账号的编辑历史？");
    DY778Confirm(self, title, @"仅删除所选范围的本地编辑版本，无法恢复。", @"删除", YES, ^{ if ([account isEqual:DY778CurrentAccountID()]) [[DY778EditStore shared] remove:account conversation:conversation key:key]; });
}
- (void)deleteCurrent { [self deleteConversation:self.conversation key:self.messageKey]; }
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (self.messageKey.length || (NSUInteger)path.row >= self.filtered.count) return nil;
    NSDictionary *row = self.filtered[path.row]; __weak typeof(self) weakSelf = self;
    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(NO); [weakSelf deleteConversation:weakSelf.conversation.length ? weakSelf.conversation : row[@"conversation"] key:weakSelf.conversation.length ? row[@"key"] : nil];
    }];
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[action]]; config.performsFirstActionWithFullSwipe = NO; return config;
}
@end
void DY778PresentEditHistory(UIViewController *source, NSString *conversation, NSString *messageKey) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778PresentEditHistory(source, conversation, messageKey); }); return; }
    DY778EditHistoryController *controller = [DY778EditHistoryController new]; controller.account = DY778CurrentAccountID(); controller.conversation = conversation; controller.messageKey = messageKey;
    DY778PresentController(source ?: DY778TopController(), controller);
}
