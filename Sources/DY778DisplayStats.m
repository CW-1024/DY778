#import "DY778DisplayStats.h"
#import "DY778DisplayStatsPolicy.h"
#import "DY778Core.h"
#import "DY778RadarUI.h"

static NSString *const DY778StatsEnabledKey = @"displayStats.enabled";
static NSString *const DY778StatsAccountsKey = @"displayStats.accounts";
static NSHashTable *DY778StatsDisplays;
static BOOL DY778StatsRefreshQueued;
static NSMutableDictionary *DY778StatsKnownVideos;
static void DY778StatsRefreshDisplays(void);
static void DY778StatsBindProfile(id section, id cell);
static void DY778StatsBindLegacyProfile(id view);
static void DY778StatsObserveVideo(id model);
static UIViewController *DY778StatsVideosController(void);
static void DY778StatsEditField(UIViewController *presenter, NSString *account, NSString *section,
    NSString *videoID, NSString *field, NSString *title, BOOL (^guard)(void), dispatch_block_t changed);
static char DY778StatsRelationTypesKey;
static const char *DY778StatsCommentHeaderClass = "_TtC28AWECommentPanelListSwiftImpl36CommentVCHeaderCommentCountComponent";
static void DY778StatsRefreshCommentHeader(UIView *header);
static void DY778StatsRefreshCommentButton(id element);

static BOOL DY778StatsFlag(id value) {
    return ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) && [value boolValue];
}

static NSDictionary *DY778StatsAccountConfig(NSString *account) {
    id accounts = [DY778Preferences() objectForKey:DY778StatsAccountsKey];
    id config = account.length && [accounts isKindOfClass:NSDictionary.class] ? accounts[account] : nil;
    return [config isKindOfClass:NSDictionary.class] ? config : @{};
}

static NSString *DY778StatsValueString(id value) {
    return [value isKindOfClass:NSString.class] ? value : [value isKindOfClass:NSNumber.class] ? [value stringValue] : nil;
}

static BOOL DY778StatsSaveConfig(NSString *account, NSDictionary *config) {
    if (!DY778DisplayStatsSameAccount(YES, account.UTF8String, DY778CurrentAccountID().UTF8String)) return NO;
    id saved = [DY778Preferences() objectForKey:DY778StatsAccountsKey];
    NSMutableDictionary *accounts = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    if (config.count) accounts[account] = config; else [accounts removeObjectForKey:account];
    DY778Set(DY778StatsAccountsKey, accounts.count ? accounts : nil);
    DY778StatsRefreshDisplays();
    return YES;
}

static BOOL DY778StatsEnabledForOwner(NSString *owner) {
    return DY778DisplayStatsSameAccount(DY778Bool(DY778StatsEnabledKey), owner.UTF8String, DY778CurrentAccountID().UTF8String);
}

static NSDictionary *DY778StatsVideoEntry(NSString *account, NSString *videoID) {
    id entries = DY778StatsAccountConfig(account)[@"videos"];
    id entry = [entries isKindOfClass:NSDictionary.class] && videoID.length ? entries[videoID] : nil;
    return [entry isKindOfClass:NSDictionary.class] ? entry : @{};
}

static NSNumber *DY778StatsNumber(NSString *section, NSString *field, NSString *owner) {
    NSString *account = DY778CurrentAccountID();
    if (!DY778DisplayStatsSameAccount(DY778Bool(DY778StatsEnabledKey), owner.UTF8String, account.UTF8String)) return nil;
    NSDictionary *config = DY778StatsAccountConfig(account);
    id values = config[section];
    id value = [values isKindOfClass:NSDictionary.class] ? values[field] : nil;
    if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class]) return nil;
    NSString *text = [value isKindOfClass:NSString.class] ? value : [value stringValue];
    uint64_t number = 0;
    return DY778DisplayStatsParse(text.UTF8String, &number) == DY778DisplayStatsCustom ? @(number) : nil;
}

static BOOL DY778StatsMethod(Class cls, SEL selector, char result, const char *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    size_t count = strlen(arguments);
    if (signature.numberOfArguments != count + 2 || signature.methodReturnType[0] != result) return NO;
    for (size_t i = 0; i < count; i++) {
        char actual = [signature getArgumentTypeAtIndex:i + 2][0];
        if (actual != arguments[i] && !(arguments[i] == 'B' && actual == 'c')) return NO;
    }
    return YES;
}

static void DY778StatsTrack(id object) {
    if (object && NSThread.isMainThread) [DY778StatsDisplays addObject:object];
}

static NSString *DY778StatsContextOwner(id context) {
    if (![DY778Read(context, @"isCurrentUser") boolValue]) return nil;
    NSString *owner = DY778Identifier(DY778Read(DY778Read(context, @"userModel"), @"userID"));
    if (!owner.length) owner = DY778Identifier(DY778Read(context, @"userId"));
    return owner;
}

static NSString *DY778StatsProfileField(id component, id item) {
    NSString *name = NSStringFromClass([component class]);
    if ([name isEqualToString:@"AWEProfileSocialStatisticPraiseComponent"]) return @"praise";
    if ([name isEqualToString:@"AWEProfileSocialStatisticFansComponent"]) return @"fans";
    if ([name isEqualToString:@"AWEProfileSocialStatisticFollowComponent"]) return @"follow";
    if ([name isEqualToString:@"AWEProfileSocialStatisticMutualComponent"]) return @"mutual";
    if ([name isEqualToString:@"AWEProfileSocialStatisticFriendComponent"]) {
        for (NSString *key in @[@"title", @"name", @"text"])
            if ([DY778Read(item, key) isEqual:@"互关"]) return @"mutual";
    }
    return nil;
}

static id (*DY778StatsOriginalProfileCount)(id, SEL, id);
static void (*DY778StatsOriginalProfileApply)(id, SEL, id, long long, id, id);

static id DY778StatsProfileComponent(id section, id item) {
    id identifier = DY778Read(item, @"modelID");
    id components = DY778Read(section, @"components");
    return [identifier isKindOfClass:NSNumber.class] && [components isKindOfClass:NSDictionary.class] ? components[identifier] : nil;
}

static id DY778StatsProfileCount(id self, SEL selector, id item) {
    id raw = DY778StatsOriginalProfileCount(self, selector, item);
    DY778StatsTrack(self);
    id component = DY778StatsProfileComponent(self, item);
    NSString *field = DY778StatsProfileField(component, item);
    NSNumber *number = field ? DY778StatsNumber(@"profile", field, DY778StatsContextOwner(DY778Read(component, @"context"))) : nil;
    return number ?: raw;
}

static void DY778StatsProfileApply(id self, SEL selector, id text, long long itemID, id cell, id component) {
    DY778StatsTrack(self);
    id item = nil;
    SEL itemSelector = NSSelectorFromString(@"p_itemForItemId:");
    if (DY778StatsMethod([self class], itemSelector, '@', "q"))
        item = ((id (*)(id, SEL, long long))objc_msgSend)(self, itemSelector, itemID);
    NSString *field = DY778StatsProfileField(component, item);
    NSNumber *number = field ? DY778StatsNumber(@"profile", field, DY778StatsContextOwner(DY778Read(component, @"context"))) : nil;
    DY778StatsOriginalProfileApply(self, selector, number ? number.stringValue : text, itemID, cell, component);
    DY778StatsBindProfile(self, cell);
}

static void (*DY778StatsOriginalProfileConfig)(id, SEL, id, long long, id);
static void DY778StatsProfileConfig(id self, SEL selector, id cell, long long index, id model) {
    DY778StatsOriginalProfileConfig(self, selector, cell, index, model);
    DY778StatsTrack(self);
    DY778StatsBindProfile(self, cell);
}

typedef struct {
    const char *selector;
    const char *field;
    const char *property;
    IMP original;
} DY778StatsLegacyProfileHook;

static DY778StatsLegacyProfileHook DY778StatsLegacyProfiles[] = {
    {"updatePraiseLabel:isLoaded:", "praise", "praiseCount", NULL},
    {"updateFollowLabel:isLoaded:", "follow", "followingCount", NULL},
    {"updateFansLabel:isLoaded:", "fans", "fansCount", NULL},
    {"updateFriendsLabel:isLoaded:", "mutual", "friendCount", NULL}
};

static NSString *DY778StatsLegacyOwner(id view) {
    id config = DY778Read(view, @"config");
    if (![DY778Read(config, @"isCurrentUser") boolValue]) return nil;
    NSString *owner = DY778StatsContextOwner(DY778Read(config, @"context"));
    return owner.length ? owner : DY778Identifier(DY778Read(DY778Read(config, @"currentUser"), @"userID"));
}

static void DY778StatsLegacyLabel(id self, SEL selector, id count, BOOL loaded) {
    for (NSUInteger i = 0; i < sizeof(DY778StatsLegacyProfiles) / sizeof(DY778StatsLegacyProfiles[0]); i++) {
        DY778StatsLegacyProfileHook *hook = &DY778StatsLegacyProfiles[i];
        if (!hook->original || selector != sel_registerName(hook->selector)) continue;
        DY778StatsTrack(self);
        NSString *field = @(hook->field);
        if ([field isEqualToString:@"mutual"] && ![DY778Read(DY778Read(self, @"config"), @"friendPrefixTitle") isEqual:@"互关"])
            field = nil;
        NSNumber *number = field ? DY778StatsNumber(@"profile", field, DY778StatsLegacyOwner(self)) : nil;
        @try { ((void (*)(id, SEL, id, BOOL))hook->original)(self, selector, number ?: count, number ? YES : loaded); }
        @finally {
            if (number) DY778Write(self, @(hook->property), count);
        }
        DY778StatsBindLegacyProfile(self);
        return;
    }
}

static NSString *DY778StatsVideoOwner(id model) {
    Class cls = NSClassFromString(@"AWEAwemeModel");
    if (!cls || ![model isKindOfClass:cls] || [DY778Read(model, @"awemeType") integerValue] == 101) return nil;
    return DY778Identifier(DY778Read(DY778Read(model, @"author"), @"userID"));
}

static id DY778StatsVideoModel(id object) {
    Class cls = NSClassFromString(@"AWEAwemeModel");
    if (cls && [object isKindOfClass:cls]) return object;
    for (NSString *key in @[@"model", @"awemeModel", @"data"]) {
        id model = DY778Read(object, key);
        if (cls && [model isKindOfClass:cls]) return model;
    }
    for (NSString *key in @[@"viewModel", @"element"]) {
        id model = DY778Read(DY778Read(object, key), @"model");
        if (cls && [model isKindOfClass:cls]) return model;
    }
    return nil;
}

static NSNumber *DY778StatsVideoNumber(id model, NSString *field) {
    NSString *owner = DY778StatsVideoOwner(model), *account = DY778CurrentAccountID();
    NSString *videoID = DY778Identifier(DY778Read(model, @"itemID"));
    BOOL sameAccount = DY778DisplayStatsSameAccount(YES, owner.UTF8String, account.UTF8String);
    NSDictionary *config = sameAccount ? DY778StatsAccountConfig(account) : @{};
    NSDictionary *entry = DY778StatsVideoEntry(account, videoID);
    id common = config[@"video"], specific = entry[@"values"];
    NSString *commonValue = [common isKindOfClass:NSDictionary.class] ? DY778StatsValueString(common[field]) : nil;
    NSString *itemValue = [specific isKindOfClass:NSDictionary.class] ? DY778StatsValueString(specific[field]) : nil;
    uint64_t value = 0;
    DY778DisplayStatsInput resolved = DY778DisplayStatsResolve(DY778Bool(DY778StatsEnabledKey),
        sameAccount, DY778StatsFlag(entry[@"original"]), itemValue.UTF8String, commonValue.UTF8String, &value);
    return resolved == DY778DisplayStatsCustom ? @(value) : nil;
}

static id (*DY778StatsOriginalStatistics)(id, SEL);
typedef struct DY778StatsRenderFrame {
    void *model;
    void *statistics;
    struct DY778StatsRenderFrame *previous;
} DY778StatsRenderFrame;
static __thread DY778StatsRenderFrame *DY778StatsRenderScope;

static id DY778StatsStatistics(id self, SEL selector) {
    DY778StatsRenderFrame *frame = DY778StatsRenderScope;
    if (frame && frame->model == (__bridge void *)self && frame->statistics)
        return (__bridge id)frame->statistics;
    return DY778StatsOriginalStatistics(self, selector);
}

static id DY778StatsVideoSnapshot(id model) {
    if (!DY778StatsOriginalStatistics) return nil;
    NSString *owner = DY778StatsVideoOwner(model);
    if (!owner.length) return nil;
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *field in @[@"diggCount", @"commentCount", @"favoriteCount", @"shareCount", @"playCount"]) {
        NSNumber *number = DY778StatsVideoNumber(model, field);
        if (number) values[field] = number;
    }
    if (!values.count) return nil;
    id raw = DY778StatsOriginalStatistics(model, @selector(statistics));
    if (![raw respondsToSelector:@selector(copyWithZone:)]) return nil;
    id snapshot = nil;
    @try {
        snapshot = [raw copy];
        if (!snapshot || snapshot == raw) return nil;
        for (NSString *field in values) if (!DY778Write(snapshot, field, values[field])) return nil;
    } @catch (__unused NSException *exception) { return nil; }
    return snapshot;
}

static void DY778StatsRender(id model, dispatch_block_t render) {
    if (!NSThread.isMainThread || !model) { render(); return; }
    DY778StatsObserveVideo(model);
    __attribute__((objc_precise_lifetime)) id heldModel = model;
    __attribute__((objc_precise_lifetime)) id snapshot = DY778StatsVideoSnapshot(heldModel);
    DY778StatsRenderFrame frame = {(__bridge void *)heldModel, (__bridge void *)snapshot, DY778StatsRenderScope};
    DY778StatsRenderScope = &frame;
    @try { render(); }
    @finally { DY778StatsRenderScope = frame.previous; }
}

typedef struct {
    const char *className;
    const char *selector;
    const char *field;
    IMP original;
} DY778StatsVideoHook;

static DY778StatsVideoHook DY778StatsVideoUpdates[] = {
    {"AWEPlayInteractionLikeViewSubElement", "updateDiggCount", "diggCount", NULL},
    {"AWEPlayInteractionFavoriteElement", "updateFavoriteCount", "favoriteCount", NULL},
    {"AWEPlayInteractionCommentElement", "updateCommentCount", "commentCount", NULL},
    {"AWEPlayInteractionStandardCommentElement", "updateCommentCount", "commentCount", NULL},
    {"AWEPlayInteractionShareElement", "updateShareButton", "shareCount", NULL},
    {"AWEMVCardDiggResource", "updateLikeString", NULL, NULL}
};
static DY778StatsVideoHook DY778StatsVideoFormatters[] = {
    {"AWEPlayInteractionFavoriteElement", "showStringFromNumber:", "favoriteCount", NULL},
    {"AWEPlayInteractionCommentElement", "showStringFromNumber:", "commentCount", NULL},
    {"AWEPlayInteractionStandardCommentElement", "showStringFromNumber:", "commentCount", NULL},
    {"AWEPlayInteractionShareElement", "showStringFromNumber:", "shareCount", NULL}
};

static DY778StatsVideoHook *DY778StatsFindVideoHook(id object, SEL selector, DY778StatsVideoHook *hooks, NSUInteger count) {
    for (Class cls = [object class]; cls; cls = class_getSuperclass(cls))
        for (NSUInteger i = 0; i < count; i++)
            if (hooks[i].original && cls == objc_getClass(hooks[i].className) && selector == sel_registerName(hooks[i].selector)) return &hooks[i];
    return NULL;
}

static void DY778StatsVideoUpdate(id self, SEL selector) {
    DY778StatsVideoHook *hook = DY778StatsFindVideoHook(self, selector, DY778StatsVideoUpdates, sizeof(DY778StatsVideoUpdates) / sizeof(DY778StatsVideoUpdates[0]));
    if (!hook) return;
    DY778StatsTrack(self);
    if (hook->field && !strcmp(hook->field, "commentCount")) {
        ((void (*)(id, SEL))hook->original)(self, selector);
        DY778StatsObserveVideo(DY778StatsVideoModel(self));
        DY778StatsRefreshCommentButton(self);
        return;
    }
    DY778StatsRender(DY778StatsVideoModel(self), ^{ ((void (*)(id, SEL))hook->original)(self, selector); });
}

static id DY778StatsVideoFormat(id self, SEL selector, id count) {
    DY778StatsVideoHook *hook = DY778StatsFindVideoHook(self, selector, DY778StatsVideoFormatters, sizeof(DY778StatsVideoFormatters) / sizeof(DY778StatsVideoFormatters[0]));
    if (!hook) return count;
    DY778StatsTrack(self);
    NSNumber *number = DY778StatsVideoNumber(DY778StatsVideoModel(self), @(hook->field));
    return ((id (*)(id, SEL, id))hook->original)(self, selector, number ?: count);
}

static void DY778StatsRefreshCommentButton(id element) {
    if (!NSThread.isMainThread) return;
    NSNumber *number = DY778StatsVideoNumber(DY778StatsVideoModel(element), @"commentCount");
    id button = DY778Read(element, @"commentButton");
    NSString *text = DY778Read(button, @"labelString");
    if (!number || ![button isKindOfClass:UIControl.class] || ![text isKindOfClass:NSString.class] || !text.length || DY778StatsFlag(DY778Read(button, @"guideAnimating"))) return;
    static NSRegularExpression *numeric;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ numeric = [NSRegularExpression regularExpressionWithPattern:@"^[0-9][0-9,.]*(?:万|亿|[kKwW])?\\+?$" options:0 error:nil]; });
    BOOL isCount = [numeric firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
    id defaultTitle = DY778Read(element, @"commentButtonLabelString");
    if (!isCount && ![text isEqual:defaultTitle]) return;
    SEL formatter = NSSelectorFromString(@"showStringFromNumber:"), setter = NSSelectorFromString(@"setLabelString:");
    if (!DY778StatsMethod([element class], formatter, '@', "@") || !DY778StatsMethod([button class], setter, 'v', "@")) return;
    id display = ((id (*)(id, SEL, id))objc_msgSend)(element, formatter, number);
    if ([display isKindOfClass:NSString.class]) ((void (*)(id, SEL, id))objc_msgSend)(button, setter, display);
}

typedef struct DY778StatsWorkFrame {
    void *context;
    void *model;
    struct DY778StatsWorkFrame *previous;
} DY778StatsWorkFrame;
static __thread DY778StatsWorkFrame *DY778StatsWorkScope;
static id (*DY778StatsOriginalWorkFormat)(id, SEL, long long);
static id DY778StatsWorkFormat(id self, SEL selector, long long count) {
    DY778StatsWorkFrame *frame = DY778StatsWorkScope;
    if (NSThread.isMainThread && frame) {
        NSString *icon = DY778Read((__bridge id)frame->context, @"imageName");
        if ([icon isKindOfClass:NSString.class] && DY778DisplayStatsWorkShowsPlays(icon.UTF8String)) {
            NSNumber *number = DY778StatsVideoNumber((__bridge id)frame->model, @"playCount");
            if (number) count = number.longLongValue;
        }
    }
    return DY778StatsOriginalWorkFormat(self, selector, count);
}

static void (*DY778StatsOriginalWorkContent)(id, SEL, id);
static void DY778StatsWorkContent(id self, SEL selector, id model) {
    DY778StatsTrack(self);
    DY778StatsWorkFrame frame = {(__bridge void *)self, (__bridge void *)model, DY778StatsWorkScope};
    DY778StatsWorkScope = &frame;
    @try { DY778StatsRender(model, ^{ DY778StatsOriginalWorkContent(self, selector, model); }); }
    @finally { DY778StatsWorkScope = frame.previous; }
}

static id (*DY778StatsOriginalPlayDescription)(id, SEL, id, id);
static id DY778StatsPlayDescription(id self, SEL selector, id count, id model) {
    DY778StatsTrack(self); DY778StatsObserveVideo(model);
    NSNumber *number = NSThread.isMainThread ? DY778StatsVideoNumber(model, @"playCount") : nil;
    return DY778StatsOriginalPlayDescription(self, selector, number ? number.stringValue : count, model);
}
static void DY778StatsRefreshPlayView(id view) {
    if (!DY778StatsOriginalPlayDescription) return;
    id model = DY778StatsVideoModel(view), rawCount = DY778Read(view, @"playCount"), label = DY778Read(view, @"playCountLabel");
    if (!model || ![rawCount isKindOfClass:NSString.class] || ![label isKindOfClass:UILabel.class]) return;
    id text = DY778StatsPlayDescription(view, NSSelectorFromString(@"playCountDescWithPlayCount:forModel:"), rawCount, model);
    if ([text isKindOfClass:NSString.class] && ![((UILabel *)label).text isEqual:text]) {
        ((UILabel *)label).text = text;
        if ([view isKindOfClass:UIView.class]) [(UIView *)view setNeedsLayout];
    }
}

static id (*DY778StatsOriginalCardDiggString)(id, SEL, id);
static id DY778StatsCardDiggString(id self, SEL selector, id model) {
    __block id value = nil;
    DY778StatsTrack(self);
    DY778StatsRender(model, ^{ value = DY778StatsOriginalCardDiggString(self, selector, model); });
    return value;
}

static void (*DY778StatsOriginalCellDigg)(id, SEL, long long);
static void DY778StatsCellDigg(id self, SEL selector, long long count) {
    DY778StatsTrack(self);
    id model = DY778StatsVideoModel(self);
    DY778StatsObserveVideo(model);
    NSNumber *number = DY778StatsVideoNumber(model, @"diggCount");
    DY778StatsOriginalCellDigg(self, selector, number ? number.longLongValue : count);
}

static void DY778StatsRefreshProfile(id section) {
    if (!DY778StatsOriginalProfileCount || !DY778StatsOriginalProfileApply) return;
    id cell = DY778Read(section, @"currentCell");
    id components = DY778Read(section, @"components");
    SEL itemSelector = NSSelectorFromString(@"p_itemForItemId:");
    if (!cell || ![components isKindOfClass:NSDictionary.class] || !DY778StatsMethod([section class], itemSelector, '@', "q")) return;
    for (id identifier in [components allKeys]) {
        if (![identifier isKindOfClass:NSNumber.class]) continue;
        id component = components[identifier];
        id item = ((id (*)(id, SEL, long long))objc_msgSend)(section, itemSelector, [identifier longLongValue]);
        if (!item || !DY778StatsProfileField(component, item)) continue;
        id raw = DY778StatsOriginalProfileCount(section, NSSelectorFromString(@"p_displayCountForItem:"), item);
        if (![raw respondsToSelector:@selector(stringValue)]) continue;
        DY778StatsProfileApply(section, NSSelectorFromString(@"p_applyDisplayText:itemId:cell:component:"), [raw stringValue], [identifier longLongValue], cell, component);
    }
}

static void DY778StatsRefreshDisplays(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778StatsRefreshDisplays(); }); return; }
    if (DY778StatsRefreshQueued) return;
    DY778StatsRefreshQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        DY778StatsRefreshQueued = NO;
        for (id object in DY778StatsDisplays.allObjects) {
            @try {
                NSString *name = NSStringFromClass([object class]);
                if ([name isEqualToString:@"AWEProfileHeaderSocialStatisticSectionControllerV2"]) {
                    DY778StatsRefreshProfile(object); continue;
                }
                if ([object isKindOfClass:NSClassFromString(@"AWEFollowListContainerViewController")]) {
                    SEL selector = NSSelectorFromString(@"__updateCountWithType:");
                    NSSet *types = objc_getAssociatedObject(object, &DY778StatsRelationTypesKey);
                    if (DY778StatsMethod([object class], selector, 'v', "Q"))
                        for (NSNumber *type in types.allObjects) ((void (*)(id, SEL, unsigned long long))objc_msgSend)(object, selector, type.unsignedLongLongValue);
                    continue;
                }
                if ([object isKindOfClass:objc_getClass(DY778StatsCommentHeaderClass)]) { DY778StatsRefreshCommentHeader(object); continue; }
                if ([object isKindOfClass:NSClassFromString(@"AWEFeedBottomBarVideoAnalysisEntranceViewV2")]) { DY778StatsRefreshPlayView(object); continue; }
                if ([object isKindOfClass:NSClassFromString(@"AWEProfileSocialStatisticView")]) {
                    SEL selector = NSSelectorFromString(@"p_updateSocialStatisticContent:");
                    if (DY778StatsMethod([object class], selector, 'v', "B")) ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, NO);
                    continue;
                }
                if ([object isKindOfClass:NSClassFromString(@"AWEUserWorkCellContext")]) {
                    id model = DY778Read(object, @"data");
                    if (model && DY778StatsOriginalWorkContent) DY778StatsWorkContent(object, NSSelectorFromString(@"__updateAccessibilityLabelAndLeftBottomContent:"), model);
                    continue;
                }
                if ([object isKindOfClass:NSClassFromString(@"AWEDetailAwemeCollectionViewCell")]) {
                    id model = DY778StatsVideoModel(object);
                    id statistics = model && DY778StatsOriginalStatistics ? DY778StatsOriginalStatistics(model, @selector(statistics)) : nil;
                    id count = DY778Read(statistics, @"diggCount");
                    if ([count respondsToSelector:@selector(longLongValue)] && DY778StatsOriginalCellDigg)
                        DY778StatsCellDigg(object, NSSelectorFromString(@"updateDiggWithCount:"), [count longLongValue]);
                    continue;
                }
                for (NSUInteger i = 0; i < sizeof(DY778StatsVideoUpdates) / sizeof(DY778StatsVideoUpdates[0]); i++) {
                    DY778StatsVideoHook *hook = &DY778StatsVideoUpdates[i];
                    if (hook->original && [object isKindOfClass:objc_getClass(hook->className)]) {
                        DY778StatsVideoUpdate(object, sel_registerName(hook->selector)); break;
                    }
                }
            } @catch (__unused NSException *exception) { }
        }
    });
}

typedef struct DY778StatsPraiseFrame {
    const char *original;
    const char *display;
    struct DY778StatsPraiseFrame *previous;
} DY778StatsPraiseFrame;
static __thread DY778StatsPraiseFrame *DY778StatsPraiseScope;
static void (*DY778StatsOriginalPraiseClick)(id, SEL, id);
static void (*DY778StatsOriginalAlertMessage)(id, SEL, id);
static id (*DY778StatsOriginalAlertDialog)(id, SEL, id, id, id, id);

static id DY778StatsPraiseText(id text) {
    DY778StatsPraiseFrame *frame = DY778StatsPraiseScope;
    if (!frame || ![text isKindOfClass:NSString.class]) return text;
    const char *bytes = [text UTF8String];
    size_t offset = 0, length = 0;
    if (!DY778DisplayStatsPraiseRange(bytes, frame->original, &offset, &length)) return text;
    NSString *prefix = [[NSString alloc] initWithBytes:bytes length:offset encoding:NSUTF8StringEncoding];
    NSString *suffix = [NSString stringWithUTF8String:bytes + offset + length];
    return prefix && suffix ? [NSString stringWithFormat:@"%@%s%@", prefix, frame->display, suffix] : text;
}

static void DY778StatsPraiseClick(id self, SEL selector, id user) {
    NSString *owner = DY778Identifier(DY778Read(user, @"userID"));
    NSNumber *number = DY778StatsNumber(@"profile", @"praise", owner);
    __attribute__((objc_precise_lifetime)) NSString *original = DY778StatsValueString(DY778Read(user, @"favoritedCount"));
    __attribute__((objc_precise_lifetime)) NSString *display = number.stringValue;
    if (!NSThread.isMainThread || !number || !original.length) { DY778StatsOriginalPraiseClick(self, selector, user); return; }
    DY778StatsPraiseFrame frame = {original.UTF8String, display.UTF8String, DY778StatsPraiseScope};
    DY778StatsPraiseScope = &frame;
    @try { DY778StatsOriginalPraiseClick(self, selector, user); }
    @finally { DY778StatsPraiseScope = frame.previous; }
}

static void DY778StatsAlertMessage(id self, SEL selector, id message) {
    DY778StatsOriginalAlertMessage(self, selector, DY778StatsPraiseText(message));
}

static id DY778StatsAlertDialog(id self, SEL selector, id image, id heading, id body, id actions) {
    return DY778StatsOriginalAlertDialog(self, selector, image, DY778StatsPraiseText(heading), body, actions);
}

static id (*DY778StatsOriginalRelationTitle)(id, SEL, unsigned long long);
static id DY778StatsRelationTitle(id self, SEL selector, unsigned long long type) {
    id raw = DY778StatsOriginalRelationTitle(self, selector, type);
    if (!NSThread.isMainThread || ![raw isKindOfClass:NSString.class]) return raw;
    NSString *prefix = nil, *field = nil;
    for (NSArray *item in @[@[@"关注 ", @"follow"], @[@"粉丝 ", @"fans"], @[@"互关 ", @"mutual"]]) {
        if ([raw hasPrefix:item[0]] && [raw length] > [item[0] length]) { prefix = item[0]; field = item[1]; break; }
    }
    if (!field) return raw;
    DY778StatsTrack(self);
    NSMutableSet *types = objc_getAssociatedObject(self, &DY778StatsRelationTypesKey);
    if (!types) { types = [NSMutableSet set]; objc_setAssociatedObject(self, &DY778StatsRelationTypesKey, types, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    [types addObject:@(type)];
    id context = DY778Read(DY778Read(self, @"viewModel"), @"pageContext") ?: DY778Read(self, @"pageContext");
    if (!DY778StatsFlag(DY778Read(context, @"isMine"))) return raw;
    NSNumber *number = DY778StatsNumber(@"profile", field, DY778Identifier(DY778Read(context, @"userID")));
    if (!number) return raw;
    SEL formatter = NSSelectorFromString([field isEqual:@"fans"] ? @"formatedLimitNumberString:" : @"__formatedNumberString:");
    if (!DY778StatsMethod([self class], formatter, '@', "q")) return raw;
    id formatted = ((id (*)(id, SEL, long long))objc_msgSend)(self, formatter, number.longLongValue);
    return [formatted isKindOfClass:NSString.class] ? [prefix stringByAppendingString:formatted] : raw;
}

@interface DY778StatsCommentLabelState : NSObject
@property(nonatomic, copy) NSString *owner;
@property(nonatomic, copy) NSString *videoID;
@property(nonatomic, copy) NSString *rawText;
@property(nonatomic, copy) NSAttributedString *rawAttributed;
@property(nonatomic, copy) NSString *appliedText;
@end
@implementation DY778StatsCommentLabelState
@end
static char DY778StatsCommentLabelKey;
static char DY778StatsCommentUpdatingKey;
static void (*DY778StatsOriginalCommentHeaderLayout)(id, SEL);

static id DY778StatsCommentHeaderModel(UIView *header) {
    Class containerClass = NSClassFromString(@"AWECommentContainerViewController");
    UIResponder *responder = header;
    for (NSUInteger depth = 0; responder && depth < 40; depth++, responder = responder.nextResponder) {
        if (![responder isKindOfClass:UIViewController.class]) continue;
        UIViewController *controller = (UIViewController *)responder;
        for (NSUInteger up = 0; controller && up < 12; up++, controller = controller.parentViewController)
            if (containerClass && [controller isKindOfClass:containerClass]) return DY778StatsVideoModel(controller);
    }
    return nil;
}
static NSRange DY778StatsCommentNumberRange(NSString *text) {
    static NSArray<NSRegularExpression *> *patterns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        patterns = @[[NSRegularExpression regularExpressionWithPattern:@"^([0-9][0-9,.]*(?:万|亿|[kKwW])?)\\s*(?:条)?评论$" options:0 error:nil],
            [NSRegularExpression regularExpressionWithPattern:@"^(?:全部)?评论\\s*[（(]?\\s*([0-9][0-9,.]*(?:万|亿|[kKwW])?)\\s*[）)]?$" options:0 error:nil]];
    });
    for (NSRegularExpression *pattern in patterns) {
        NSTextCheckingResult *match = [pattern firstMatchInString:text ?: @"" options:0 range:NSMakeRange(0, text.length)];
        if (match.numberOfRanges > 1) return [match rangeAtIndex:1];
    }
    return NSMakeRange(NSNotFound, 0);
}
static void DY778StatsRefreshCommentHeader(UIView *header) {
    if (!NSThread.isMainThread || [objc_getAssociatedObject(header, &DY778StatsCommentUpdatingKey) boolValue]) return;
    objc_setAssociatedObject(header, &DY778StatsCommentUpdatingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        id model = DY778StatsCommentHeaderModel(header);
        NSString *owner = DY778StatsVideoOwner(model), *videoID = DY778Identifier(DY778Read(model, @"itemID"));
        NSNumber *number = DY778StatsVideoNumber(model, @"commentCount");
        NSMutableArray<UIView *> *views = [NSMutableArray arrayWithArray:header.subviews];
        for (NSUInteger index = 0; index < views.count && index < 32; index++) {
            UIView *view = views[index];
            if (![view isKindOfClass:UILabel.class]) { if (views.count < 32) [views addObjectsFromArray:view.subviews]; continue; }
            UILabel *label = (UILabel *)view;
            DY778StatsCommentLabelState *state = objc_getAssociatedObject(label, &DY778StatsCommentLabelKey);
            BOOL isApplied = state && [label.text isEqualToString:state.appliedText];
            BOOL sameVideo = state && [state.owner isEqualToString:owner] && [state.videoID isEqualToString:videoID];
            if (!number || (isApplied && !sameVideo)) {
                NSString *currentOriginal = nil;
                NSRange currentRange = DY778StatsCommentNumberRange(label.text);
                if (isApplied && !sameVideo && owner.length && videoID.length && DY778StatsOriginalStatistics && currentRange.location != NSNotFound) {
                    id statistics = DY778StatsOriginalStatistics(model, @selector(statistics));
                    NSString *candidate = DY778StatsValueString(DY778Read(statistics, @"commentCount"));
                    uint64_t count = 0;
                    if (DY778DisplayStatsParse(candidate.UTF8String, &count) == DY778DisplayStatsCustom) currentOriginal = @(count).stringValue;
                }
                DY778DisplayStatsLabelRecovery recovery = DY778DisplayStatsRecoverLabel(isApplied, sameVideo, currentOriginal != nil);
                if (recovery == DY778DisplayStatsLabelAwaitNative) continue;
                if (recovery == DY778DisplayStatsLabelRestoreSaved) {
                    if (state.rawAttributed) label.attributedText = state.rawAttributed; else label.text = state.rawText;
                } else if (recovery == DY778DisplayStatsLabelRestoreCurrent) {
                    NSAttributedString *currentAttributed = label.attributedText;
                    if (currentAttributed && [currentAttributed.string isEqualToString:label.text]) {
                        NSMutableAttributedString *styled = [currentAttributed mutableCopy];
                        [styled replaceCharactersInRange:currentRange withString:currentOriginal]; label.attributedText = styled;
                    } else label.text = [label.text stringByReplacingCharactersInRange:currentRange withString:currentOriginal];
                }
                objc_setAssociatedObject(label, &DY778StatsCommentLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                state = nil; isApplied = NO; sameVideo = NO;
                if (!number) continue;
            }
            NSString *raw = isApplied && sameVideo ? state.rawText : label.text;
            NSAttributedString *attributed = isApplied && sameVideo ? state.rawAttributed : label.attributedText;
            NSRange range = DY778StatsCommentNumberRange(raw);
            if (range.location == NSNotFound) continue;
            NSString *updated = [raw stringByReplacingCharactersInRange:range withString:number.stringValue];
            if (!state || !isApplied || !sameVideo) {
                state = [DY778StatsCommentLabelState new]; state.owner = owner; state.videoID = videoID;
                state.rawText = raw; state.rawAttributed = attributed;
            }
            state.appliedText = updated;
            objc_setAssociatedObject(label, &DY778StatsCommentLabelKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if ([label.text isEqualToString:updated]) continue;
            if (attributed && [attributed.string isEqualToString:raw]) {
                NSMutableAttributedString *styled = [attributed mutableCopy];
                [styled replaceCharactersInRange:range withString:number.stringValue]; label.attributedText = styled;
            } else label.text = updated;
        }
    } @finally { objc_setAssociatedObject(header, &DY778StatsCommentUpdatingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}
static void DY778StatsCommentHeaderLayout(id self, SEL selector) {
    DY778StatsOriginalCommentHeaderLayout(self, selector);
    DY778StatsTrack(self); DY778StatsRefreshCommentHeader(self);
}

typedef struct DY778StatsPullFrame {
    void *component;
    BOOL restored;
    struct DY778StatsPullFrame *previous;
} DY778StatsPullFrame;
static __thread DY778StatsPullFrame *DY778StatsPullScope;
static void (*DY778StatsOriginalPullEnd)(id, SEL, id, CGPoint, CGPoint *);
static void (*DY778StatsOriginalProfileRefresh)(id, SEL, unsigned long long, id);

static void DY778StatsPullEnd(id self, SEL selector, id scrollView, CGPoint velocity, CGPoint *targetOffset) {
    BOOL userDrag = NSThread.isMainThread && [scrollView isKindOfClass:UIScrollView.class] &&
        (((UIScrollView *)scrollView).dragging || ((UIScrollView *)scrollView).panGestureRecognizer.state == UIGestureRecognizerStateEnded);
    if (!userDrag) { DY778StatsOriginalPullEnd(self, selector, scrollView, velocity, targetOffset); return; }
    DY778StatsPullFrame frame = {(__bridge void *)self, NO, DY778StatsPullScope};
    DY778StatsPullScope = &frame;
    @try { DY778StatsOriginalPullEnd(self, selector, scrollView, velocity, targetOffset); }
    @finally { DY778StatsPullScope = frame.previous; }
}
static void DY778StatsProfileRefresh(id self, SEL selector, unsigned long long type, id completion) {
    DY778StatsPullFrame *frame = DY778StatsPullScope;
    if (NSThread.isMainThread && frame && !frame->restored && frame->component == (__bridge void *)self) {
        id context = DY778Read(self, @"context");
        NSString *owner = DY778Identifier(DY778Read(context, @"userID")), *account = DY778CurrentAccountID();
        NSDictionary *config = DY778StatsAccountConfig(account);
        BOOL ownHomepage = DY778StatsFlag(DY778Read(context, @"isCurrentUser")) && DY778StatsFlag(DY778Read(context, @"isFromHomePage"));
        if (DY778DisplayStatsShouldResetOnPull(DY778Bool(DY778StatsEnabledKey), YES, type, ownHomepage,
                DY778DisplayStatsSameAccount(YES, owner.UTF8String, account.UTF8String), config.count) && DY778StatsSaveConfig(account, @{})) {
            frame->restored = YES;
            DY778Toast(@"已恢复当前账号的全部数字");
        }
    }
    DY778StatsOriginalProfileRefresh(self, selector, type, completion);
}

static void DY778StatsInstallHook(const char *className, const char *name, char result, const char *arguments, IMP replacement, IMP *original) {
    if (*original) return;
    Class cls = objc_getClass(className);
    SEL selector = sel_registerName(name);
    BOOL installed = DY778StatsMethod(cls, selector, result, arguments) && DY778Hook(cls, selector, replacement, original);
    DY778RecordHook([NSString stringWithFormat:@"displayStats.%s.%s", className, name], installed);
}

void DY778InstallDisplayStats(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallDisplayStats(); }); return; }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DY778StatsDisplays = [NSHashTable weakObjectsHashTable];
        DY778StatsKnownVideos = [NSMutableDictionary dictionary];
        for (NSNotificationName name in @[DY778PreferencesChangedNotification, UIApplicationDidBecomeActiveNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { DY778StatsRefreshDisplays(); }];
    });
    DY778StatsInstallHook("AWEProfileHeaderSocialStatisticSectionControllerV2", "p_displayCountForItem:", '@', "@", (IMP)DY778StatsProfileCount, (IMP *)&DY778StatsOriginalProfileCount);
    DY778StatsInstallHook("AWEProfileHeaderSocialStatisticSectionControllerV2", "p_applyDisplayText:itemId:cell:component:", 'v', "@q@@", (IMP)DY778StatsProfileApply, (IMP *)&DY778StatsOriginalProfileApply);
    DY778StatsInstallHook("AWEProfileHeaderSocialStatisticSectionControllerV2", "configCell:index:model:", 'v', "@q@", (IMP)DY778StatsProfileConfig, (IMP *)&DY778StatsOriginalProfileConfig);
    DY778StatsInstallHook("AWEProfileCommonComponent", "didTapPraiseButton:", 'v', "@", (IMP)DY778StatsPraiseClick, (IMP *)&DY778StatsOriginalPraiseClick);
    DY778StatsInstallHook("AWEUIAlertView", "setMessage:", 'v', "@", (IMP)DY778StatsAlertMessage, (IMP *)&DY778StatsOriginalAlertMessage);
    DY778StatsInstallHook("AWEFollowListContainerViewController", "__titleWithType:", '@', "Q", (IMP)DY778StatsRelationTitle, (IMP *)&DY778StatsOriginalRelationTitle);
    DY778StatsInstallHook("AWEFeedBottomBarVideoAnalysisEntranceViewV2", "playCountDescWithPlayCount:forModel:", '@', "@@", (IMP)DY778StatsPlayDescription, (IMP *)&DY778StatsOriginalPlayDescription);
    DY778StatsInstallHook("AWEProfilePullRefreshComponent", "scrollViewWillEndDraggingWithScrollView:withVelocity:targetContentOffset:", 'v', "@{N", (IMP)DY778StatsPullEnd, (IMP *)&DY778StatsOriginalPullEnd);
    DY778StatsInstallHook("AWEProfilePullRefreshComponent", "refreshWithType:completion:", 'v', "Q@", (IMP)DY778StatsProfileRefresh, (IMP *)&DY778StatsOriginalProfileRefresh);
    DY778StatsInstallHook(DY778StatsCommentHeaderClass, "layoutSubviews", 'v', "", (IMP)DY778StatsCommentHeaderLayout, (IMP *)&DY778StatsOriginalCommentHeaderLayout);
    if (!DY778StatsOriginalWorkFormat) {
        Class meta = object_getClass(objc_getClass("AWEProfileUtilities"));
        SEL selector = NSSelectorFromString(@"adaptedDUXShowStringWithFromNumber:");
        BOOL installed = DY778StatsMethod(meta, selector, '@', "q") && DY778Hook(meta, selector, (IMP)DY778StatsWorkFormat, (IMP *)&DY778StatsOriginalWorkFormat);
        DY778RecordHook(@"displayStats.AWEProfileUtilities.workPlayCount", installed);
    }
    if (!DY778StatsOriginalAlertDialog) {
        Class meta = object_getClass(objc_getClass("DUXAlertDialog"));
        SEL selector = NSSelectorFromString(@"dialogWithImage:heading:body:actions:");
        BOOL installed = DY778StatsMethod(meta, selector, '@', "@@@@") && DY778Hook(meta, selector, (IMP)DY778StatsAlertDialog, (IMP *)&DY778StatsOriginalAlertDialog);
        DY778RecordHook(@"displayStats.DUXAlertDialog.praise", installed);
    }
    for (NSUInteger i = 0; i < sizeof(DY778StatsLegacyProfiles) / sizeof(DY778StatsLegacyProfiles[0]); i++) {
        DY778StatsLegacyProfileHook *hook = &DY778StatsLegacyProfiles[i];
        DY778StatsInstallHook("AWEProfileSocialStatisticView", hook->selector, 'v', "@B", (IMP)DY778StatsLegacyLabel, &hook->original);
    }
    DY778StatsInstallHook("AWEAwemeModel", "statistics", '@', "", (IMP)DY778StatsStatistics, (IMP *)&DY778StatsOriginalStatistics);
    for (NSUInteger i = 0; i < sizeof(DY778StatsVideoUpdates) / sizeof(DY778StatsVideoUpdates[0]); i++) {
        DY778StatsVideoHook *hook = &DY778StatsVideoUpdates[i];
        DY778StatsInstallHook(hook->className, hook->selector, 'v', "", (IMP)DY778StatsVideoUpdate, &hook->original);
    }
    for (NSUInteger i = 0; i < sizeof(DY778StatsVideoFormatters) / sizeof(DY778StatsVideoFormatters[0]); i++) {
        DY778StatsVideoHook *hook = &DY778StatsVideoFormatters[i];
        DY778StatsInstallHook(hook->className, hook->selector, '@', "@", (IMP)DY778StatsVideoFormat, &hook->original);
    }
    DY778StatsInstallHook("AWEUserWorkCellContext", "__updateAccessibilityLabelAndLeftBottomContent:", 'v', "@", (IMP)DY778StatsWorkContent, (IMP *)&DY778StatsOriginalWorkContent);
    DY778StatsInstallHook("AWEMVCardDiggResource", "likeStringWithAwemeModel:", '@', "@", (IMP)DY778StatsCardDiggString, (IMP *)&DY778StatsOriginalCardDiggString);
    DY778StatsInstallHook("AWEDetailAwemeCollectionViewCell", "updateDiggWithCount:", 'v', "q", (IMP)DY778StatsCellDigg, (IMP *)&DY778StatsOriginalCellDigg);
}

void DY778ResetDisplayStats(void) {
    DY778Set(DY778StatsEnabledKey, @NO);
    DY778Set(DY778StatsAccountsKey, nil);
    DY778StatsRefreshDisplays();
}

static NSArray<NSString *> *DY778StatsVideoFields(void) {
    return @[@"diggCount", @"commentCount", @"favoriteCount", @"shareCount", @"playCount"];
}
static NSString *DY778StatsTitle(NSString *field) {
    return @{@"praise": @"获赞数", @"mutual": @"互关数", @"follow": @"关注数", @"fans": @"粉丝数",
        @"diggCount": @"点赞数", @"commentCount": @"评论数", @"favoriteCount": @"收藏数", @"shareCount": @"分享数", @"playCount": @"播放数"}[field] ?: @"显示数字";
}
static void DY778StatsObserveVideo(id model) {
    if (!NSThread.isMainThread) return;
    NSString *account = DY778CurrentAccountID(), *owner = DY778StatsVideoOwner(model);
    NSString *videoID = DY778Identifier(DY778Read(model, @"itemID"));
    if (!DY778DisplayStatsSameAccount(YES, owner.UTF8String, account.UTF8String) || !videoID.length || [videoID isEqual:@"0"]) return;
    NSMutableDictionary *videos = DY778StatsKnownVideos[account];
    if (!videos) { videos = [NSMutableDictionary dictionary]; DY778StatsKnownVideos[account] = videos; }
    NSString *title = DY778Read(model, @"descriptionString");
    if (![title isKindOfClass:NSString.class] || !title.length) title = @"未命名作品";
    if (title.length > 120) title = [title substringWithRange:[title rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 120)]];
    videos[videoID] = @{@"title": title, @"time": @(NSDate.date.timeIntervalSince1970)};
    if (videos.count > 500) {
        NSString *oldest = [[videos allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [videos[a][@"time"] compare:videos[b][@"time"]];
        }].firstObject;
        if (oldest) [videos removeObjectForKey:oldest];
    }
}
static NSString *DY778StatsVideoTitle(NSString *account, NSString *videoID) {
    NSString *title = DY778StatsKnownVideos[account][videoID][@"title"];
    if (![title isKindOfClass:NSString.class] || !title.length) title = DY778StatsVideoEntry(account, videoID)[@"title"];
    return [title isKindOfClass:NSString.class] && title.length ? title : @"本人作品";
}
static BOOL DY778StatsSaveVideoEntry(NSString *account, NSString *videoID, NSDictionary *entry) {
    if (!videoID.length) return NO;
    NSMutableDictionary *config = [DY778StatsAccountConfig(account) mutableCopy];
    id old = config[@"videos"];
    NSMutableDictionary *videos = [old isKindOfClass:NSDictionary.class] ? [old mutableCopy] : [NSMutableDictionary dictionary];
    if (entry.count) videos[videoID] = entry; else [videos removeObjectForKey:videoID];
    if (videos.count) config[@"videos"] = videos; else [config removeObjectForKey:@"videos"];
    return DY778StatsSaveConfig(account, config);
}

@interface DY778StatsVideoController : DY778RadarTableController
@property(nonatomic, copy) NSString *accountID;
@property(nonatomic, copy) NSString *videoID;
@property(nonatomic, copy) BOOL (^sourceGuard)(void);
@property(nonatomic) BOOL sessionInvalidated;
- (BOOL)accountIsCurrent;
@end

static BOOL DY778StatsCheckEditor(UIViewController *presenter, NSString *account, BOOL (^guard)(void)) {
    if (DY778DisplayStatsSameAccount(YES, account.UTF8String, DY778CurrentAccountID().UTF8String) && (!guard || guard())) return YES;
    DY778ShowNotice(presenter, @"页面状态已变化", @"当前账号或作品已发生变化，请返回后重新打开要编辑的数字。");
    return NO;
}
static void DY778StatsOpenVideoEditor(UIViewController *presenter, NSString *account, NSString *videoID, BOOL (^guard)(void)) {
    if (!DY778StatsCheckEditor(presenter, account, guard)) return;
    DY778StatsVideoController *controller = [DY778StatsVideoController new];
    controller.accountID = account; controller.videoID = videoID; controller.sourceGuard = guard;
    DY778PresentController(presenter, controller);
}
static void DY778StatsEditField(UIViewController *presenter, NSString *account, NSString *section,
        NSString *videoID, NSString *field, NSString *title, BOOL (^guard)(void), dispatch_block_t changed) {
    if (!presenter || [presenter isKindOfClass:UIAlertController.class] || presenter.presentedViewController || !DY778StatsCheckEditor(presenter, account, guard)) return;
    NSDictionary *config = DY778StatsAccountConfig(account), *entry = DY778StatsVideoEntry(account, videoID);
    id values = videoID.length ? entry[@"values"] : config[section];
    NSString *previous = [values isKindOfClass:NSDictionary.class] ? DY778StatsValueString(values[field]) : nil;
    NSString *message = videoID.length ? @"输入 0–999999999 的整数。留空跟随通用设置；保存后启用此作品的自定义数字。" : @"输入 0–999999999 的整数；留空使用原值。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778InterfaceStyle(); alert.view.tintColor = DY778Accent();
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeNumberPad; textField.text = previous;
        textField.placeholder = videoID.length ? @"留空跟随通用设置" : @"留空使用原值";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        if (!DY778StatsCheckEditor(presenter, account, guard)) return;
        NSString *text = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        uint64_t number = 0;
        DY778DisplayStatsInput result = DY778DisplayStatsParse(text.UTF8String, &number);
        if (result == DY778DisplayStatsInvalid) { DY778Toast(@"请输入 0–999999999 的整数"); return; }
        BOOL saved = NO;
        if (videoID.length) {
            NSMutableDictionary *updated = [DY778StatsVideoEntry(account, videoID) mutableCopy];
            id oldValues = updated[@"values"];
            NSMutableDictionary *newValues = [oldValues isKindOfClass:NSDictionary.class] ? [oldValues mutableCopy] : [NSMutableDictionary dictionary];
            if (result == DY778DisplayStatsCustom) newValues[field] = @(number).stringValue; else [newValues removeObjectForKey:field];
            updated[@"values"] = newValues; updated[@"original"] = @NO; updated[@"title"] = DY778StatsVideoTitle(account, videoID);
            saved = DY778StatsSaveVideoEntry(account, videoID, updated);
        } else {
            NSMutableDictionary *updated = [DY778StatsAccountConfig(account) mutableCopy];
            id oldValues = updated[section];
            NSMutableDictionary *newValues = [oldValues isKindOfClass:NSDictionary.class] ? [oldValues mutableCopy] : [NSMutableDictionary dictionary];
            if (result == DY778DisplayStatsCustom) newValues[field] = @(number).stringValue; else [newValues removeObjectForKey:field];
            updated[section] = newValues; saved = DY778StatsSaveConfig(account, updated);
        }
        if (!saved) return;
        if (changed) changed();
        DY778Toast(result == DY778DisplayStatsCustom ? @"显示数字已更新" : videoID.length ? @"此项已跟随通用设置" : @"此项已恢复原值");
    }]];
    if (videoID.length && ![presenter isKindOfClass:DY778StatsVideoController.class]) [alert addAction:[UIAlertAction actionWithTitle:@"编辑此作品全部数字" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_block_t open = ^{ DY778StatsOpenVideoEditor(presenter, account, videoID, guard); };
            if (presenter.presentedViewController == weakAlert) [presenter dismissViewControllerAnimated:YES completion:open];
            else if (!presenter.presentedViewController) open();
        });
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface DY778StatsEditGestureTarget : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) id source;
@property(nonatomic, weak) UIView *view;
@property(nonatomic, weak) UIView *numberView;
@property(nonatomic, weak) UIView *titleView;
@property(nonatomic, copy) NSString *field;
@property(nonatomic, strong) NSNumber *itemID;
@property(nonatomic) BOOL legacy;
- (NSString *)owner;
- (BOOL)isEligible;
- (void)longPress:(UILongPressGestureRecognizer *)gesture;
@end

static char DY778StatsGestureKey;
static NSString *DY778StatsGestureOwner(id source, UIView *view, NSString *field, NSNumber *itemID, BOOL legacy) {
    if (!source || !view) return nil;
    if (legacy) {
        NSString *containerKey = @{@"praise": @"praiseContainerView", @"follow": @"followContainerView", @"fans": @"fansContainerView", @"mutual": @"friendContainerView"}[field];
        if (DY778Read(source, containerKey) != view) return nil;
        return DY778StatsLegacyOwner(source);
    }
    id cell = DY778Read(source, @"currentCell"), statisticView = DY778Read(cell, @"socialStatisticView");
    id containers = DY778Read(statisticView, @"itemContainers"), components = DY778Read(source, @"components");
    if (![containers isKindOfClass:NSDictionary.class] || containers[itemID] != view || ![components isKindOfClass:NSDictionary.class]) return nil;
    id component = components[itemID], item = nil;
    SEL selector = NSSelectorFromString(@"p_itemForItemId:");
    if (DY778StatsMethod([source class], selector, '@', "q")) item = ((id (*)(id, SEL, long long))objc_msgSend)(source, selector, itemID.longLongValue);
    if (![DY778StatsProfileField(component, item) isEqual:field]) return nil;
    return DY778StatsContextOwner(DY778Read(component, @"context"));
}

@implementation DY778StatsEditGestureTarget
- (NSString *)owner { return DY778StatsGestureOwner(self.source, self.view, self.field, self.itemID, self.legacy); }
- (BOOL)isEligible {
    return self.view.window && !self.view.hidden && self.view.alpha > .01 && DY778StatsEnabledForOwner(self.owner);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (![self isEligible]) return NO;
    UIView *container = self.view;
    CGRect region = self.numberView ? [self.numberView convertRect:self.numberView.bounds toView:container] : container.bounds;
    if (self.titleView && !self.titleView.hidden && self.titleView.alpha > .01)
        region = CGRectUnion(region, [self.titleView convertRect:self.titleView.bounds toView:container]);
    region = CGRectIntersection(CGRectInset(region, -4, -3), container.bounds);
    return !CGRectIsNull(region) && CGRectContainsPoint(region, [touch locationInView:container]);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture { return [self isEligible]; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
- (void)longPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || ![self isEligible]) return;
    NSString *account = self.owner, *field = self.field;
    NSNumber *itemID = self.itemID;
    BOOL legacy = self.legacy;
    __weak id weakSource = self.source;
    __weak UIView *weakView = self.view;
    BOOL (^guard)(void) = ^BOOL {
        id source = weakSource; UIView *view = weakView;
        NSString *owner = DY778StatsGestureOwner(source, view, field, itemID, legacy);
        return DY778DisplayStatsEditorMatches(owner.UTF8String, account.UTF8String, NULL, NULL) && DY778StatsEnabledForOwner(owner);
    };
    UIViewController *presenter = DY778TopController();
    DY778StatsEditField(presenter, account, @"profile", nil, field, DY778StatsTitle(field), guard, nil);
}
@end

static void DY778StatsBindGesture(UIView *view, UIView *numberView, UIView *titleView, id source, NSString *field, NSNumber *itemID, BOOL legacy) {
    if (!NSThread.isMainThread || ![view isKindOfClass:UIView.class] || !view.userInteractionEnabled || !field.length) return;
    DY778StatsEditGestureTarget *target = objc_getAssociatedObject(view, &DY778StatsGestureKey);
    if (!target) {
        target = [DY778StatsEditGestureTarget new];
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:@selector(longPress:)];
        gesture.minimumPressDuration = .55; gesture.allowableMovement = 9; gesture.numberOfTouchesRequired = 1;
        gesture.cancelsTouchesInView = YES; gesture.delaysTouchesBegan = NO; gesture.delaysTouchesEnded = NO; gesture.delegate = target;
        [view addGestureRecognizer:gesture];
        objc_setAssociatedObject(view, &DY778StatsGestureKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    target.source = source; target.view = view; target.numberView = numberView; target.titleView = titleView; target.field = field;
    target.itemID = itemID; target.legacy = legacy;
}
static void DY778StatsBindProfile(id section, id cell) {
    if (!NSThread.isMainThread || !cell) return;
    id view = DY778Read(cell, @"socialStatisticView"), containers = DY778Read(view, @"itemContainers");
    id labels = DY778Read(view, @"countLabels"), titles = DY778Read(view, @"titleLabels"), components = DY778Read(section, @"components");
    if (![containers isKindOfClass:NSDictionary.class] || ![labels isKindOfClass:NSDictionary.class] || ![components isKindOfClass:NSDictionary.class]) return;
    SEL selector = NSSelectorFromString(@"p_itemForItemId:");
    if (!DY778StatsMethod([section class], selector, '@', "q")) return;
    for (id identifier in containers) {
        if (![identifier isKindOfClass:NSNumber.class]) continue;
        id item = ((id (*)(id, SEL, long long))objc_msgSend)(section, selector, [identifier longLongValue]);
        NSString *field = DY778StatsProfileField(components[identifier], item);
        id label = labels[identifier];
        id title = [titles isKindOfClass:NSDictionary.class] ? titles[identifier] : nil;
        if ([label isKindOfClass:UIView.class]) DY778StatsBindGesture(containers[identifier], label, [title isKindOfClass:UIView.class] ? title : nil, section, field, identifier, NO);
    }
}
static void DY778StatsBindLegacyProfile(id view) {
    for (NSArray *item in @[@[@"praise", @"praiseContainerView", @"praiseLabel", @"praisePrefixBtn"], @[@"follow", @"followContainerView", @"followLabel", @"followPrefixBtn"],
            @[@"fans", @"fansContainerView", @"fansLabel", @"fansPrefixBtn"], @[@"mutual", @"friendContainerView", @"friendLabel", @"friendPrefixBtn"]]) {
        if ([item[0] isEqual:@"mutual"] && ![DY778Read(DY778Read(view, @"config"), @"friendPrefixTitle") isEqual:@"互关"]) continue;
        id label = DY778Read(view, item[2]), title = DY778Read(view, item[3]);
        if ([label isKindOfClass:UIView.class]) DY778StatsBindGesture(DY778Read(view, item[1]), label, [title isKindOfClass:UIView.class] ? title : nil, view, item[0], nil, YES);
    }
}

@implementation DY778StatsVideoController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"此作品的显示数字"; }
- (BOOL)accountIsCurrent {
    if (!DY778DisplayStatsEditorSessionValid(self.sessionInvalidated, DY778CurrentAccountID().UTF8String, self.accountID.UTF8String)) self.sessionInvalidated = YES;
    return !self.sessionInvalidated;
}
- (void)refresh {
    if (![self accountIsCurrent] && [self.presentedViewController isKindOfClass:UIAlertController.class]) {
        for (UITextField *field in ((UIAlertController *)self.presentedViewController).textFields) field.text = nil;
        [self dismissViewControllerAnimated:NO completion:nil];
    }
    [super refresh];
}
- (void)updateTheme { [super updateTheme]; if (self.isViewLoaded && ![self accountIsCurrent]) [self refresh]; }
- (BOOL)validate {
    if (![self accountIsCurrent]) {
        [self refresh];
        DY778ShowNotice(self, @"账号信息已变化", @"此编辑页已失效，请返回后重新打开当前账号的作品。");
        return NO;
    }
    return DY778StatsCheckEditor(self, self.accountID, self.sourceGuard);
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return [self accountIsCurrent] ? 3 : 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return ![self accountIsCurrent] || section == 0 ? 1 : section == 1 ? 5 : 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return [self accountIsCurrent] && section == 1 ? DY778StatsVideoTitle(self.accountID, self.videoID) : nil; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (![self accountIsCurrent]) return nil;
    if (section == 0) return @"开启后，此作品直接显示真实数字，忽略单独设置及通用值。其他作品不受影响。";
    if (section == 1) return @"单独设置优先于通用值。留空跟随通用设置；修改任一项会启用此作品的自定义数字。数字仅在原生已有的位置显示。";
    return @"“跟随通用设置”会删除此作品的单独配置；“恢复原始数字”还会让此作品忽略通用值。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (![self accountIsCurrent]) {
        UITableViewCell *cell = DY778RadarCell(@"账号信息已变化", @"请返回后重新打开当前账号的作品。", @"person.crop.circle", NO);
        cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell;
    }
    NSDictionary *entry = DY778StatsVideoEntry(self.accountID, self.videoID);
    if (path.section == 0) {
        UITableViewCell *cell = DY778RadarCell(@"此作品使用原始数字", nil, @"arrow.counterclockwise", NO);
        UISwitch *toggle = [UISwitch new]; toggle.onTintColor = DY778Accent(); toggle.on = DY778StatsFlag(entry[@"original"]);
        [toggle addTarget:self action:@selector(originalChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell;
    }
    if (path.section == 2) return DY778RadarCell(path.row == 0 ? @"跟随通用设置" : @"清除并恢复原始数字", nil, path.row == 0 ? @"arrow.uturn.backward" : @"arrow.counterclockwise", NO);
    NSString *field = DY778StatsVideoFields()[path.row];
    id values = entry[@"values"];
    NSString *value = [values isKindOfClass:NSDictionary.class] ? DY778StatsValueString(values[field]) : nil;
    NSString *subtitle = value.length ? value : @"跟随通用设置";
    if (DY778StatsFlag(entry[@"original"])) subtitle = [subtitle stringByAppendingString:@" · 当前显示原值"];
    return DY778RadarCell(DY778StatsTitle(field), subtitle, nil, YES);
}
- (void)originalChanged:(UISwitch *)toggle {
    if (![self validate]) { [self refresh]; return; }
    NSMutableDictionary *entry = [DY778StatsVideoEntry(self.accountID, self.videoID) mutableCopy];
    entry[@"original"] = @(toggle.on); entry[@"title"] = DY778StatsVideoTitle(self.accountID, self.videoID);
    DY778StatsSaveVideoEntry(self.accountID, self.videoID, entry); [self refresh];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0 || ![self validate]) return;
    if (path.section == 1) {
        NSString *field = DY778StatsVideoFields()[path.row];
        __weak typeof(self) weakSelf = self;
        BOOL (^guard)(void) = ^BOOL {
            DY778StatsVideoController *editor = weakSelf;
            return [editor accountIsCurrent] && (!editor.sourceGuard || editor.sourceGuard());
        };
        DY778StatsEditField(self, self.accountID, @"video", self.videoID, field, DY778StatsTitle(field), guard, ^{ [weakSelf refresh]; });
        return;
    }
    BOOL original = path.row == 1;
    DY778Confirm(self, original ? @"此作品恢复原始数字？" : @"此作品跟随通用设置？",
        original ? @"将清除此作品的单独数字，并忽略通用值，恢复真实显示。" : @"将删除此作品的单独配置，改用通用值；未设置通用值的项目显示原值。",
        original ? @"恢复原始数字" : @"跟随通用设置", YES, ^{
            if (![self validate]) return;
            NSDictionary *entry = original ? @{@"original": @YES, @"title": DY778StatsVideoTitle(self.accountID, self.videoID)} : @{};
            DY778StatsSaveVideoEntry(self.accountID, self.videoID, entry); [self refresh];
            DY778Toast(original ? @"此作品已恢复原始数字" : @"此作品已跟随通用设置");
        });
}
@end

@interface DY778StatsVideoListController : DY778RadarTableController
@property(nonatomic, copy) NSString *accountID;
@property(nonatomic, copy) NSArray<NSString *> *videoIDs;
@end
@implementation DY778StatsVideoListController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"按作品单独设置"; }
- (BOOL)accountIsCurrent { return DY778DisplayStatsSameAccount(YES, self.accountID.UTF8String, DY778CurrentAccountID().UTF8String); }
- (void)updateTheme { [super updateTheme]; if (self.isViewLoaded && ![self accountIsCurrent]) [self refresh]; }
- (void)refresh {
    self.videoIDs = @[];
    self.accountID = DY778CurrentAccountID();
    if (!self.accountID.length) { [super refresh]; return; }
    id saved = DY778StatsAccountConfig(self.accountID)[@"videos"];
    NSMutableSet *ids = [NSMutableSet setWithArray:[saved isKindOfClass:NSDictionary.class] ? [saved allKeys] : @[]];
    [ids addObjectsFromArray:[DY778StatsKnownVideos[self.accountID] allKeys] ?: @[]];
    NSMutableArray *valid = [NSMutableArray array];
    for (id key in ids) if ([key isKindOfClass:NSString.class] && [key length]) [valid addObject:key];
    self.videoIDs = [valid sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSNumber *first = DY778StatsKnownVideos[self.accountID][a][@"time"] ?: @0;
        NSNumber *second = DY778StatsKnownVideos[self.accountID][b][@"time"] ?: @0;
        NSComparisonResult time = [second compare:first]; return time == NSOrderedSame ? [a compare:b] : time;
    }];
    [super refresh];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self accountIsCurrent] ? MAX((NSUInteger)1, self.videoIDs.count) : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"这里列出本次打开过的本人作品和已保存配置的作品。点选作品即可设置其显示数字。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (![self accountIsCurrent]) {
        UITableViewCell *cell = DY778RadarCell(@"账号信息已变化", @"请返回后重新进入，查看当前账号的作品。", @"person.crop.circle", NO);
        cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell;
    }
    if (path.row >= (NSInteger)self.videoIDs.count) {
        UITableViewCell *cell = DY778RadarCell(@"暂无可设置的作品", @"先打开自己的作品，再返回此处进行设置。", @"play.rectangle", NO);
        cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell;
    }
    NSString *videoID = self.videoIDs[path.row];
    NSDictionary *entry = DY778StatsVideoEntry(self.accountID, videoID);
    id values = entry[@"values"];
    NSString *state = DY778StatsFlag(entry[@"original"]) ? @"使用原始数字" : [values isKindOfClass:NSDictionary.class] && [values count] ? @"已单独设置" : @"跟随通用设置";
    return DY778RadarCell(DY778StatsVideoTitle(self.accountID, videoID), [NSString stringWithFormat:@"%@ · %@", state, videoID], @"play.rectangle", YES);
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (![self accountIsCurrent]) { [self refresh]; return; }
    if (path.row >= (NSInteger)self.videoIDs.count) return;
    DY778StatsOpenVideoEditor(self, self.accountID, self.videoIDs[path.row], nil);
}
@end
static UIViewController *DY778StatsVideosController(void) {
    DY778StatsVideoListController *controller = [DY778StatsVideoListController new];
    controller.accountID = DY778CurrentAccountID(); return controller;
}

@interface DY778DisplayStatsSettingsController : DY778RadarTableController
@property(nonatomic, copy) NSString *accountID;
@end

@implementation DY778DisplayStatsSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"数字自定义";
    self.accountID = DY778CurrentAccountID();
}
- (void)refresh {
    self.accountID = DY778CurrentAccountID();
    [super refresh];
}
- (BOOL)validateAccount:(NSString *)account {
    if (account.length && [account isEqualToString:DY778CurrentAccountID()]) return YES;
    DY778ShowNotice(self, @"账号信息已变化", @"请返回后重新进入，再设置当前账号的显示数字。");
    return NO;
}
- (void)saveConfig:(NSDictionary *)config account:(NSString *)account {
    if (![self validateAccount:account]) return;
    DY778StatsSaveConfig(account, config);
    [self refresh];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 1 ? 4 : section == 2 ? 6 : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? @"个人主页" : section == 2 ? @"本人作品" : nil;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"开启后，已填写的主页和本人作品数字直接生效。仅改变本机显示，不修改真实数据；不同账号分别保存。";
    if (section == 1) return @"也可长按本人主页的数字或其下方文字编辑。留空沿用原值，支持 0–999999999 的整数，样式沿用抖音界面。";
    if (section == 2) return @"通用值用于本人作品；单作品设置优先。点进“按作品单独设置”可分别修改，留空跟随通用值。";
    return @"关闭总开关会恢复原值并保留设置。启用时，下拉刷新“我”页或点“恢复当前账号原状”，会清除当前账号的全部主页、作品通用及单作品数字设置，恢复真实显示；总开关保持原状态。";
}
- (NSArray<NSString *> *)fieldsForSection:(NSInteger)section {
    return section == 1 ? @[@"praise", @"mutual", @"follow", @"fans"] : @[@"diggCount", @"commentCount", @"favoriteCount", @"shareCount", @"playCount"];
}
- (NSArray<NSString *> *)titlesForSection:(NSInteger)section {
    return section == 1 ? @[@"获赞数", @"互关数", @"关注数", @"粉丝数"] : @[@"点赞数", @"评论数", @"收藏数", @"分享数", @"播放数"];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *config = DY778StatsAccountConfig(self.accountID);
    if (path.section == 3) return DY778RadarCell(@"恢复当前账号原状", @"清除当前账号的数字设置并恢复真实显示", @"arrow.counterclockwise", NO);
    if (path.section == 0) {
        UITableViewCell *cell = DY778RadarCell(@"启用数字自定义", nil, @"number.circle", NO);
        UISwitch *toggle = [UISwitch new]; toggle.onTintColor = DY778Accent();
        toggle.on = DY778Bool(DY778StatsEnabledKey);
        toggle.enabled = self.accountID.length > 0;
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (path.section == 2 && path.row == 0) return DY778RadarCell(@"按作品单独设置", @"为不同作品设置数字，或让某一作品恢复原始显示", @"rectangle.stack", YES);
    NSString *section = path.section == 1 ? @"profile" : @"video";
    NSInteger index = path.row - (path.section == 1 ? 0 : 1);
    NSString *field = [self fieldsForSection:path.section][index];
    id values = config[section];
    id value = [values isKindOfClass:NSDictionary.class] ? values[field] : nil;
    NSString *subtitle = [value isKindOfClass:NSString.class] ? value : [value isKindOfClass:NSNumber.class] ? [value stringValue] : @"跟随原值";
    NSString *title = [self titlesForSection:path.section][index];
    if (path.section == 2) title = [@"通用" stringByAppendingString:title];
    return DY778RadarCell(title, subtitle, nil, YES);
}
- (void)toggleChanged:(UISwitch *)toggle {
    if (![self validateAccount:self.accountID]) { [self refresh]; return; }
    DY778Set(DY778StatsEnabledKey, @(toggle.on));
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0) return;
    NSString *account = self.accountID;
    if (![self validateAccount:account]) return;
    if (path.section == 3) {
        DY778Confirm(self, @"恢复当前账号原状？", @"将清除当前账号的主页及全部作品数字设置，恢复真实显示。总开关保持原状态，其他账号不受影响。", @"恢复原状", YES, ^{
            if (![self validateAccount:account]) return;
            [self saveConfig:@{} account:account];
            DY778Toast(@"已恢复当前账号的原始显示");
        });
        return;
    }
    if (path.section == 2 && path.row == 0) { DY778PresentController(self, DY778StatsVideosController()); return; }
    NSString *section = path.section == 1 ? @"profile" : @"video";
    NSInteger index = path.row - (path.section == 1 ? 0 : 1);
    NSString *field = [self fieldsForSection:path.section][index];
    NSString *title = [self titlesForSection:path.section][index];
    DY778StatsEditField(self, account, section, nil, field, title, nil, ^{ [self refresh]; });
}
@end

UIViewController *DY778DisplayStatsController(void) { return [DY778DisplayStatsSettingsController new]; }
