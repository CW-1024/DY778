#import "DY778Spark.h"
#import "DY778SparkPolicy.h"
#import "DY778SparkProjection.h"
#import <stdatomic.h>

static NSString *const DY778SparkMasterKey = @"spark.enabled";
static NSString *const DY778SparkSettingsKey = @"spark.settings";
static char DY778SparkManagerScopeKey, DY778SparkPopupBindingKey, DY778SparkValueScopeKey;
static NSHashTable *DY778SparkManagers, *DY778SparkPanels, *DY778SparkPopupViews;
static NSMutableArray *DY778SparkPopupRoutes;
static NSMutableSet *DY778SparkTouchedScopes;
static __weak id DY778SparkService, DY778SparkInjector;
static IMP DY778SparkOriginalFlame, DY778SparkOriginalChat, DY778SparkOriginalInjector, DY778SparkOriginalClientInjector;
static __thread NSUInteger DY778SparkNativeReadDepth;
static _Atomic(uint64_t) DY778SparkRevision, DY778SparkManagerGeneration;
static NSObject *DY778SparkManagerLock(void) {
    static NSObject *lock; static dispatch_once_t once; dispatch_once(&once, ^{ lock = [NSObject new]; }); return lock;
}
static NSArray *DY778SparkManagerSnapshot(void) {
    @synchronized (DY778SparkManagerLock()) { return DY778SparkManagers.allObjects ?: @[]; }
}
@interface DY778SparkPanelBinding : NSObject
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *conversation;
@property(nonatomic, weak) id nativeConversation;
@property(nonatomic, weak) id model;
@property(nonatomic, weak) id viewModel;
@property(nonatomic, weak) id context;
@property(nonatomic, copy) NSString *schema;
@property(nonatomic, copy) NSString *channel;
@property(nonatomic, copy) NSString *bundle;
@end
@implementation DY778SparkPanelBinding
@end

static BOOL DY778SparkSignature(Method method, const char *returns, const char *arguments) {
    if (!method) return NO;
    NSMethodSignature *s = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (s.methodReturnType[0] != returns[0] || s.numberOfArguments != strlen(arguments) + 2) return NO;
    for (NSUInteger i = 0; arguments[i]; i++) if ([s getArgumentTypeAtIndex:i + 2][0] != arguments[i]) return NO;
    return YES;
}
static NSString *DY778SparkConversationID(id conversation) {
    if (!conversation) return nil;
    id wrappedNative = DY778Read(conversation, @"con");
    NSString *wrapperID = DY778Identifier(DY778Read(conversation, @"conversationID")) ?: DY778Identifier(DY778Read(conversation, @"identifier"));
    NSString *nativeID = DY778Identifier(DY778Read(wrappedNative, @"identifier"));
    if (wrapperID.length && nativeID.length && ![wrapperID isEqual:nativeID]) return nil;
    NSString *identifier = DY778Identifier(DY778Read(conversation, @"conversationID")) ?:
                           DY778Identifier(DY778Read(conversation, @"identifier")) ?:
                           DY778Identifier(DY778Read(DY778Read(conversation, @"con"), @"identifier"));
    if (!identifier.length || identifier.length > 512) return nil;
    id native = DY778Read(conversation, @"con") ?: conversation;
    NSNumber *type = DY778Read(native, @"type");
    if ([type isKindOfClass:NSNumber.class] && type.unsignedIntegerValue == 2) return identifier;
    return DY778SparkSingleChatParts(identifier.UTF8String, NULL, NULL, NULL, NULL) ? identifier : nil;
}
static NSString *DY778SparkSDKAccount(id conversation) {
    id native = DY778Read(conversation, @"con") ?: conversation;
    Class model = NSClassFromString(@"TIMXOModel");
    if (!model || ![native isKindOfClass:model]) return nil;
    Ivar rootIvar = class_getInstanceVariable(model, "_r");
    const char *encoding = rootIvar ? ivar_getTypeEncoding(rootIvar) : NULL;
    if (!encoding || encoding[0] != '@') return nil;
    id root = object_getIvar(native, rootIvar);
    NSString *account = DY778Identifier(DY778Read(DY778Read(root, @"config"), @"uid"));
    return account.length && ![account isEqualToString:@"0"] ? account : nil;
}
static NSString *DY778SparkConversationAccount(id conversation) {
    NSString *account = DY778CurrentAccountID(), *identifier = DY778SparkConversationID(conversation);
    NSString *sdkAccount = DY778SparkSDKAccount(conversation);
    id native = DY778Read(conversation, @"con") ?: conversation;
    NSNumber *type = DY778Read(native, @"type"), *participant = DY778Read(native, @"isCurrentUserAParticipant");
    if ([type isKindOfClass:NSNumber.class] && type.unsignedIntegerValue == 2) {
        return DY778SparkGroupBindingMatches(identifier.UTF8String, account.UTF8String, sdkAccount.UTF8String, 2,
            [participant isKindOfClass:NSNumber.class] && participant.boolValue) ? account : nil;
    }
    if ([type isKindOfClass:NSNumber.class] && type.unsignedIntegerValue != 1) return nil;
    return DY778SparkSingleChatBindingMatches(identifier.UTF8String, account.UTF8String, sdkAccount.UTF8String, NULL) ? account : nil;
}
static BOOL DY778SparkIsGroup(id conversation) {
    id native = DY778Read(conversation, @"con") ?: conversation;
    NSNumber *type = DY778Read(native, @"type");
    return [type isKindOfClass:NSNumber.class] && type.unsignedIntegerValue == 2 && DY778SparkConversationAccount(conversation).length;
}
static id DY778SparkContextConversation(id context) {
    id wrapper = DY778Read(context, @"conversation"), native = DY778Read(context, @"con");
    NSString *wrapperID = DY778SparkConversationID(wrapper), *nativeID = DY778SparkConversationID(native);
    if (wrapperID.length && nativeID.length && ![wrapperID isEqual:nativeID]) return nil;
    NSString *current = DY778CurrentAccountID();
    for (id object in @[wrapper ?: NSNull.null, native ?: NSNull.null]) {
        NSString *owner = DY778SparkSDKAccount(object);
        if (owner.length && ![owner isEqual:current]) return nil;
    }
    return nativeID.length ? native : wrapperID.length ? wrapper : nil;
}
static NSString *DY778SparkContextPeerID(id context, id conversation) {
    NSString *account = DY778SparkConversationAccount(conversation);
    char peerBuffer[33];
    if (!DY778SparkSingleChatPeer(DY778SparkConversationID(conversation).UTF8String,
                                  account.UTF8String, peerBuffer, sizeof(peerBuffer))) return nil;
    NSString *peerID = [NSString stringWithUTF8String:peerBuffer];
    id wrapper = DY778Read(context, @"conversation");
    id peer = DY778Read(context, @"peerUser") ?: DY778Read(wrapper, @"peerUser");
    NSString *contextPeer = DY778Identifier(DY778Read(peer, @"uid")) ?: DY778Identifier(DY778Read(peer, @"userID"));
    NSString *declared = DY778Identifier(DY778Read(wrapper ?: conversation, @"peerUserID"));
    if ([contextPeer isEqual:@"0"]) contextPeer = nil;
    if ([declared isEqual:@"0"]) declared = nil;
    NSString *identifier = DY778SparkConversationID(conversation);
    if (!DY778SparkSingleChatBindingMatches(identifier.UTF8String, account.UTF8String, NULL, contextPeer.UTF8String) ||
        !DY778SparkSingleChatBindingMatches(identifier.UTF8String, account.UTF8String, NULL, declared.UTF8String)) return nil;
    return peerID;
}
static NSDictionary *DY778SparkAllSettings(void) {
    id value = [DY778Preferences() objectForKey:DY778SparkSettingsKey];
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static NSDictionary *DY778SparkOptions(NSString *account, NSString *conversation) {
    if (!account.length || !conversation.length) return @{};
    id accounts = DY778SparkAllSettings()[account];
    id options = [accounts isKindOfClass:NSDictionary.class] ? accounts[conversation] : nil;
    return [options isKindOfClass:NSDictionary.class] ? options : @{};
}
static NSDictionary *DY778SparkActiveOptions(NSString *account, NSString *conversation) {
    if (!account.length || !conversation.length || ![account isEqual:DY778CurrentAccountID()] || !DY778Bool(DY778SparkMasterKey)) return nil;
    NSDictionary *options = DY778SparkOptions(account, conversation);
    if (![options[@"enabled"] isKindOfClass:NSNumber.class] || ![options[@"enabled"] boolValue]) return nil;
    unsigned days = 0;
    if (![options[@"lit"] isKindOfClass:NSNumber.class] || ![options[@"days"] isKindOfClass:NSNumber.class] ||
        !DY778SparkParseDays([options[@"days"] stringValue].UTF8String, &days)) return nil;
    return options;
}
static BOOL DY778SparkNeedsDetailProjection(NSString *account, NSString *conversation) {
    if (!account.length || !conversation.length || ![account isEqual:DY778CurrentAccountID()]) return NO;
    NSArray *scope = @[account, conversation];
    BOOL active = DY778SparkActiveOptions(account, conversation) != nil;
    @synchronized (DY778SparkManagerLock()) {
        if (active) {
            if (!DY778SparkTouchedScopes) DY778SparkTouchedScopes = [NSMutableSet set];
            [DY778SparkTouchedScopes addObject:scope];
        }
        return active || [DY778SparkTouchedScopes containsObject:scope];
    }
}
static void DY778SparkSave(NSString *account, NSString *conversation, NSDictionary *options) {
    if (!account.length || !conversation.length || ![account isEqual:DY778CurrentAccountID()]) return;
    NSMutableDictionary *all = [DY778SparkAllSettings() mutableCopy];
    id saved = all[account];
    NSMutableDictionary *chats = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    if (options.count) chats[conversation] = options; else [chats removeObjectForKey:conversation];
    if (chats.count) all[account] = chats; else [all removeObjectForKey:account];
    DY778Set(DY778SparkSettingsKey, all);
}

static BOOL DY778SparkPanelScopeValid(DY778SparkPanelBinding *binding) {
    return binding && DY778SparkScopeMatches(binding.account.UTF8String, binding.conversation.UTF8String,
        DY778SparkConversationAccount(binding.nativeConversation).UTF8String, DY778SparkConversationID(binding.nativeConversation).UTF8String);
}

static NSString *DY778SparkURLString(id value) {
    if ([value isKindOfClass:NSString.class]) return [value length] <= 32768 ? value : nil;
    if ([value isKindOfClass:NSURL.class]) {
        NSString *string = [value absoluteString];
        return string.length <= 32768 ? string : nil;
    }
    return nil;
}
static BOOL DY778SparkMergeRoute(NSMutableDictionary *route, NSDictionary *candidate, BOOL *hasAny) {
    if (![candidate isKindOfClass:NSDictionary.class]) return YES;
    for (NSString *key in @[@"conversation_id", @"channel", @"bundle"]) {
        if (!candidate[key]) continue;
        id raw = candidate[key];
        if (raw == NSNull.null) return NO;
        NSString *value = DY778Identifier(raw);
        if (!value.length) return NO;
        if (![key isEqual:@"conversation_id"] && ![raw isKindOfClass:NSString.class]) return NO;
        *hasAny = YES;
        NSString *existing = route[key];
        if (!DY778SparkRouteFieldCompatible(existing.UTF8String, value.UTF8String)) return NO;
        route[key] = value;
    }
    return YES;
}
static BOOL DY778SparkMergeRouteURL(NSMutableDictionary *route, id source, BOOL *hasAny) {
    if (!source) return YES;
    NSString *schema = DY778SparkURLString(source);
    if (!schema.length) return NO;
    NSURLComponents *components = [NSURLComponents componentsWithString:schema];
    if (!components) return NO;
    NSMutableDictionary *fromURL = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        if (![@[@"conversation_id", @"channel", @"bundle"] containsObject:item.name]) continue;
        if (!item.value.length || fromURL[item.name]) return NO;
        fromURL[item.name] = item.value;
    }
    return DY778SparkMergeRoute(route, fromURL, hasAny);
}
static BOOL DY778SparkMergeRouteObject(NSMutableDictionary *route, id source, BOOL *hasAny) {
    if (!source || source == NSNull.null) return YES;
    if (!DY778SparkMergeRouteURL(route, DY778Read(source, @"originURL"), hasAny)) return NO;
    id schemaParams = DY778Read(source, @"schemaParams");
    if (schemaParams && !DY778SparkMergeRouteURL(route, DY778Read(schemaParams, @"originURL"), hasAny)) return NO;
    for (id queryOwner in @[source, schemaParams ?: NSNull.null]) {
        if (queryOwner == NSNull.null) continue;
        id query = DY778Read(queryOwner, @"queryItems");
        if (query && ![query isKindOfClass:NSDictionary.class]) return NO;
        if (query && !DY778SparkMergeRoute(route, query, hasAny)) return NO;
        NSMutableDictionary *fields = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"channel", @"bundle"]) {
            id value = DY778Read(queryOwner, key);
            if (value && ![value isKindOfClass:NSString.class]) return NO;
            if ([value length]) fields[key] = value;
        }
        if (!DY778SparkMergeRoute(route, fields, hasAny)) return NO;
    }
    return YES;
}
static NSDictionary *DY778SparkPopupRoute(NSString *schema) {
    NSMutableDictionary *route = [NSMutableDictionary dictionary]; BOOL hasAny = NO;
    if (!DY778SparkMergeRouteURL(route, schema, &hasAny) || route.count != 3) return nil;
    return [route copy];
}
static NSDictionary *DY778SparkPopupRouteForObject(id object, id context, NSString **schemaOut) {
    NSMutableDictionary *route = [NSMutableDictionary dictionary]; BOOL hasAny = NO;
    if (!DY778SparkMergeRouteObject(route, object, &hasAny) || !DY778SparkMergeRouteObject(route, context, &hasAny)) return nil;
    NSString *schema = DY778SparkURLString(DY778Read(object, @"originURL")) ?: DY778SparkURLString(DY778Read(context, @"originURL"));
    if (schemaOut) *schemaOut = schema;
    if (route.count != 3) return nil;
    return [route copy];
}
static BOOL DY778SparkPopupRouteIsBound(DY778SparkPanelBinding *binding, NSDictionary *route) {
    return DY778SparkPanelScopeValid(binding) && DY778SparkPopupRouteMatches(binding.account.UTF8String,
        binding.conversation.UTF8String, DY778CurrentAccountID().UTF8String, [route[@"conversation_id"] UTF8String],
        binding.channel.UTF8String, binding.bundle.UTF8String, [route[@"channel"] UTF8String], [route[@"bundle"] UTF8String]);
}
static DY778SparkPanelBinding *DY778SparkPopupScopeWithRoute(id conversation, NSString *schema, NSDictionary *route) {
    NSString *account = DY778SparkConversationAccount(conversation), *identifier = DY778SparkConversationID(conversation);
    if (!route || !account.length || ![identifier isEqual:route[@"conversation_id"]]) return nil;
    DY778SparkPanelBinding *binding = [DY778SparkPanelBinding new];
    binding.account = account; binding.conversation = identifier; binding.nativeConversation = conversation;
    binding.schema = schema; binding.channel = route[@"channel"]; binding.bundle = route[@"bundle"];
    return binding;
}
static DY778SparkPanelBinding *DY778SparkPopupScope(id conversation, NSString *schema) {
    return DY778SparkPopupScopeWithRoute(conversation, schema, DY778SparkPopupRoute(schema));
}
static void DY778SparkRememberPopupRoute(id conversation, NSString *schema) {
    DY778SparkPanelBinding *binding = DY778SparkPopupScope(conversation, schema);
    if (!binding) return;
    if (!DY778SparkPopupRoutes) DY778SparkPopupRoutes = [NSMutableArray array];
    for (DY778SparkPanelBinding *old in [DY778SparkPopupRoutes copy]) {
        if (!DY778SparkPanelScopeValid(old) || DY778SparkPopupRouteIsBound(old, DY778SparkPopupRoute(schema)))
            [DY778SparkPopupRoutes removeObjectIdenticalTo:old];
    }
    [DY778SparkPopupRoutes addObject:binding];
    if (DY778SparkPopupRoutes.count > 32) [DY778SparkPopupRoutes removeObjectAtIndex:0];
}
static DY778SparkPanelBinding *DY778SparkPopupScopeForRoute(NSString *schema, NSDictionary *route) {
    if (!NSThread.isMainThread) return nil;
    if (!route) return nil;
    for (DY778SparkPanelBinding *candidate in DY778SparkPopupRoutes.reverseObjectEnumerator)
        if (DY778SparkPopupRouteIsBound(candidate, route)) return DY778SparkPopupScopeWithRoute(candidate.nativeConversation, schema, route);
    if (![route[@"channel"] isEqual:@"im_flame_reactlynx"] ||
        ![route[@"bundle"] isEqual:@"react_popup_fire_achievement/template.js"]) return nil;
    Class utility = NSClassFromString(@"IESIMConversationUtility");
    SEL lookup = NSSelectorFromString(@"conversationForIdentifier:");
    if (!DY778SparkSignature(class_getClassMethod(utility, lookup), "@", "@")) return nil;
    id conversation = ((id (*)(id, SEL, id))objc_msgSend)(utility, lookup, route[@"conversation_id"]);
    return DY778SparkPopupScopeWithRoute(conversation, schema, route);
}
static DY778SparkPanelBinding *DY778SparkPopupScopeForSchema(NSString *schema) {
    return DY778SparkPopupScopeForRoute(schema, DY778SparkPopupRoute(schema));
}

static id DY778SparkReadNative(id service, id conversation, BOOL chat) {
    IMP original = chat ? DY778SparkOriginalChat : DY778SparkOriginalFlame;
    if (!service || !original) return nil;
    DY778SparkNativeReadDepth++;
    @try { return ((id (*)(id, SEL, id))original)(service,
        NSSelectorFromString(chat ? @"imStreakInfoChatDataModelForConversation:" : @"imStreakFlameInfoModelForConversation:"), conversation); }
    @finally { DY778SparkNativeReadDepth--; }
}
static NSString *DY778SparkLevelForConversation(id conversation, id flame, id chat) {
    id level = DY778Read(flame, @"level");
    if ([level isKindOfClass:NSString.class] && [level length] && ![level isEqual:@"disable"]) return level;
    Class cls = NSClassFromString(@"AWEIMChatListConsecutiveChatDaysHintProvider");
    SEL shared = NSSelectorFromString(@"sharedInstance"), getter = NSSelectorFromString(@"chatLevelWithConversation:");
    if (DY778SparkSignature(class_getClassMethod(cls, shared), "@", "") &&
        DY778SparkSignature(class_getInstanceMethod(cls, getter), "@", "@")) {
        id provider = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        level = ((id (*)(id, SEL, id))objc_msgSend)(provider, getter, conversation);
        if ([level isKindOfClass:NSString.class] && [level length] && ![level isEqual:@"disable"]) return level;
    }
    return DY778SparkProjectionLevel(flame, chat);
}
static NSDictionary *DY778SparkNativeDefaults(NSString *account, NSString *conversation) {
    for (id manager in DY778SparkManagerSnapshot()) {
        id native = DY778Read(manager, @"conversation");
        if (!DY778SparkScopeMatches(account.UTF8String, conversation.UTF8String,
            DY778SparkConversationAccount(native).UTF8String, DY778SparkConversationID(native).UTF8String)) continue;
        id flame = DY778SparkReadNative(DY778SparkService, native, NO);
        unsigned days = 1; id value = DY778Read(flame, @"days");
        if ([value isKindOfClass:NSNumber.class]) DY778SparkParseDays([value stringValue].UTF8String, &days);
        return @{@"days":@(days), @"lit":@([DY778Read(flame, @"state") longLongValue] == 1)};
    }
    return @{@"days":@1, @"lit":@YES};
}
static NSDictionary *DY778SparkGenerateDetail(DY778SparkPanelBinding *binding) {
    if (!DY778SparkPanelScopeValid(binding) || !DY778SparkOriginalInjector ||
        !DY778SparkNeedsDetailProjection(binding.account, binding.conversation)) return nil;
    id injector = DY778SparkInjector;
    if (!injector) injector = [NSClassFromString(@"AWEIMStreakHunterBizDataInjector") new];
    if (!injector) return nil;
    @try {
        id value = ((id (*)(id, SEL, id))DY778SparkOriginalInjector)(injector,
            NSSelectorFromString(@"achievementIMHunterServerDataWithConversation:"), binding.nativeConversation);
        value = DY778SparkProjectDetail(value, DY778SparkActiveOptions(binding.account, binding.conversation));
        id client = DY778SparkOriginalClientInjector ? ((id (*)(id, SEL, id))DY778SparkOriginalClientInjector)(injector,
            NSSelectorFromString(@"achievementIMHunterClientDataWithConversation:"), binding.nativeConversation) : nil;
        if (![value isKindOfClass:NSDictionary.class] || ![client isKindOfClass:NSDictionary.class]) return nil;
        return @{@"server":value, @"client":client};
    } @catch (__unused NSException *exception) { return nil; }
}
static DY778SparkPanelBinding *DY778SparkPopupForViewModel(id viewModel, id model) {
    if (!NSThread.isMainThread) return nil;
    NSString *schema = DY778SparkURLString(DY778Read(model, @"schema"));
    DY778SparkPanelBinding *binding = objc_getAssociatedObject(viewModel, &DY778SparkPopupBindingKey);
    if (binding && (binding.model != model || !DY778SparkPopupRouteIsBound(binding, DY778SparkPopupRoute(schema)))) binding = nil;
    if (!binding) binding = DY778SparkPopupScopeForSchema(schema);
    objc_setAssociatedObject(viewModel, &DY778SparkPopupBindingKey, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (binding) {
        binding.model = model; binding.viewModel = viewModel;
        id context = DY778Read(DY778Read(viewModel, @"context"), @"bdxContext");
        binding.context = context;
        if (context) objc_setAssociatedObject(context, &DY778SparkPopupBindingKey, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!DY778SparkPanels) DY778SparkPanels = [NSHashTable weakObjectsHashTable];
        [DY778SparkPanels addObject:viewModel];
    }
    return binding;
}
static DY778SparkPanelBinding *DY778SparkPopupForBDX(id view) {
    if (!NSThread.isMainThread) return nil;
    id params = DY778Read(view, @"params"), context = DY778Read(params, @"context"); NSString *schema = nil;
    NSDictionary *route = DY778SparkPopupRouteForObject(params, context, &schema);
    DY778SparkPanelBinding *binding = objc_getAssociatedObject(view, &DY778SparkPopupBindingKey);
    if (binding && (binding.model != params || binding.context != context || !DY778SparkPopupRouteIsBound(binding, route))) binding = nil;
    if (!binding) binding = DY778SparkPopupScopeForRoute(schema, route);
    objc_setAssociatedObject(view, &DY778SparkPopupBindingKey, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (binding) {
        binding.model = params; binding.context = context;
        if (!DY778SparkPopupViews) DY778SparkPopupViews = [NSHashTable weakObjectsHashTable];
        [DY778SparkPopupViews addObject:view];
    }
    return binding;
}
static id DY778SparkValueDictionary(id value) {
    if ([value isKindOfClass:NSDictionary.class]) return value;
    if ([value isKindOfClass:NSClassFromString(@"LynxTemplateData")]) return DY778Read(value, @"dictionary");
    if ([value isKindOfClass:NSString.class] && [value length] < 2097152)
        return [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    return nil;
}
static BOOL DY778SparkValueMatchesScope(id value, DY778SparkPanelBinding *binding) {
    NSDictionary *stamp = objc_getAssociatedObject(value, &DY778SparkValueScopeKey);
    if (stamp && (!binding || !DY778SparkScopeMatches([stamp[@"account"] UTF8String], [stamp[@"conversation"] UTF8String],
        binding.account.UTF8String, binding.conversation.UTF8String))) return NO;
    if (!binding) return YES;
    id data = DY778SparkValueDictionary(value);
    if (![data isKindOfClass:NSDictionary.class]) return YES;
    id client = data[@"__clientData"] ?: data;
    id info = [client isKindOfClass:NSDictionary.class] ? client[@"conversation_info"] : nil;
    id identifier = [info isKindOfClass:NSDictionary.class] ? info[@"conversation_id"] : nil;
    return !identifier || ([identifier isKindOfClass:NSString.class] && [identifier isEqual:binding.conversation]);
}
static id DY778SparkStampValue(id value, DY778SparkPanelBinding *binding) {
    if (value && binding.account.length && binding.conversation.length)
        objc_setAssociatedObject(value, &DY778SparkValueScopeKey,
            @{@"account":binding.account, @"conversation":binding.conversation}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return value;
}
static NSDictionary *DY778SparkProjectContainer(NSDictionary *data, DY778SparkPanelBinding *binding) {
    if (![data isKindOfClass:NSDictionary.class] || !DY778SparkPanelScopeValid(binding)) return data;
    NSDictionary *generated = DY778SparkGenerateDetail(binding);
    if (!generated) return data;
    NSDictionary *result = DY778SparkMergeDetailEnvelope(data, generated[@"server"], generated[@"client"]);
    return result != data ? DY778SparkStampValue(result, binding) : result;
}
static id DY778SparkProjectValue(id value, DY778SparkPanelBinding *binding) {
    if (!DY778SparkPanelScopeValid(binding) || !DY778SparkValueMatchesScope(value, binding)) return value;
    if ([value isKindOfClass:NSDictionary.class]) return DY778SparkProjectContainer(value, binding);
    if ([value isKindOfClass:NSString.class] && [value length] < 2097152) {
        id parsed = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        id visible = DY778SparkProjectContainer(parsed, binding);
        if (visible != parsed && [NSJSONSerialization isValidJSONObject:visible]) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:visible options:0 error:NULL];
            return data ? DY778SparkStampValue([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], binding) : value;
        }
    } else if ([value isKindOfClass:NSClassFromString(@"LynxTemplateData")]) {
        id dictionary = DY778Read(value, @"dictionary"), visible = DY778SparkProjectContainer(dictionary, binding);
        if (visible != dictionary) {
            id copy = DY778Read(value, @"deepClone"); SEL update = NSSelectorFromString(@"updateWithDictionary:");
            if (copy && copy != value && DY778SparkSignature(class_getInstanceMethod([copy class], update), "v", "@")) {
                ((void (*)(id, SEL, id))objc_msgSend)(copy, update, visible); return DY778SparkStampValue(copy, binding);
            }
        }
    }
    return value;
}
static void DY778SparkRefreshViews(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778SparkRefreshViews(); }); return; }
    atomic_fetch_add_explicit(&DY778SparkRevision, 1, memory_order_acq_rel);
    SEL update = NSSelectorFromString(@"imStreakDataDidUpdateWithConversation:");
    for (id manager in DY778SparkManagerSnapshot()) {
        id conversation = DY778Read(manager, @"conversation");
        if (!DY778SparkConversationAccount(conversation).length ||
            !DY778SparkSignature(class_getInstanceMethod([manager class], update), "v", "@")) continue;
        ((void (*)(id, SEL, id))objc_msgSend)(manager, update, conversation);
    }
    SEL reload = NSSelectorFromString(@"containerStartLoadingWithType:");
    for (id viewModel in DY778SparkPanels.allObjects) {
        DY778SparkPanelBinding *binding = DY778SparkPopupForViewModel(viewModel, DY778Read(viewModel, @"dynamicPatchModel"));
        if (DY778SparkPanelScopeValid(binding) && DY778SparkSignature(class_getInstanceMethod([viewModel class], reload), "v", "q"))
            ((void (*)(id, SEL, long long))objc_msgSend)(viewModel, reload, 6);
    }
    SEL bdxUpdate = NSSelectorFromString(@"updateData:processorName:");
    for (id view in DY778SparkPopupViews.allObjects) {
        DY778SparkPanelBinding *binding = DY778SparkPopupForBDX(view);
        NSDictionary *generated = DY778SparkGenerateDetail(binding);
        if (!generated || !DY778SparkSignature(class_getInstanceMethod([view class], bdxUpdate), "v", "@@")) continue;
        id current = DY778Read(view, @"getCurrentData");
        id visible = DY778SparkProjectValue(current, binding);
        if (visible != current) ((void (*)(id, SEL, id, id))objc_msgSend)(view, bdxUpdate, visible, nil);
    }
}
static void DY778SparkInstallNativeModels(void) {
    Class service = NSClassFromString(@"_TtC15AWEIMGrowthImpl23StreakModuleServiceImpl");
    NSArray *names = @[@"imStreakFlameInfoModelForConversation:", @"imStreakInfoChatDataModelForConversation:"];
    static BOOL installed[2];
    for (NSUInteger index = 0; index < names.count; index++) {
        if (installed[index]) continue;
        SEL selector = NSSelectorFromString(names[index]); Method method = class_getInstanceMethod(service, selector);
        if (!DY778SparkSignature(method, "@", "@")) continue;
        IMP original = method_getImplementation(method);
        if (index) DY778SparkOriginalChat = original; else DY778SparkOriginalFlame = original;
        IMP replacement = imp_implementationWithBlock(^id(id owner, id conversation) {
            BOOL nested = DY778SparkNativeReadDepth > 0;
            id native = DY778SparkReadNative(owner, conversation, index != 0);
            if (nested) return native;
            DY778SparkService = owner;
            NSString *account = DY778SparkConversationAccount(conversation), *identifier = DY778SparkConversationID(conversation);
            NSDictionary *options = DY778SparkActiveOptions(account, identifier);
            if (!options) return native;
            DY778SparkNeedsDetailProjection(account, identifier);
            id chat = index ? native : DY778SparkReadNative(owner, conversation, YES);
            id flame = index ? DY778SparkReadNative(owner, conversation, NO) : native;
            id progress = DY778Read(DY778Read(chat, @"consecutiveCountInfoModel"), @"consecutiveCount");
            if (!flame && (![progress isKindOfClass:NSNumber.class] || [progress longLongValue] <= 0)) return native;
            NSString *level = DY778SparkLevelForConversation(conversation, flame, chat);
            id visible = index ? DY778SparkProjectChatModel(chat, flame, options, level) :
                DY778SparkProjectFlameModel(flame, options, level);
            return visible;
        });
        class_replaceMethod(service, selector, replacement, method_getTypeEncoding(method)); installed[index] = YES;
    }
    DY778RecordHook(@"spark.nativeFlameSource", installed[0]);
    DY778RecordHook(@"spark.nativeChatSource", installed[1]);
}
static NSMethodSignature *DY778SparkBlockSignature(id block) {
    if (!block || ![NSStringFromClass(object_getClass(block)) containsString:@"Block"]) return nil;
    struct BlockLayout { void *isa; int flags; int reserved; void *invoke; const void *descriptor; };
    const struct BlockLayout *layout = (__bridge const void *)block;
    if (!(layout->flags & (1 << 30)) || !layout->descriptor) return nil;
    const uint8_t *cursor = layout->descriptor; cursor += 2 * sizeof(unsigned long);
    if (layout->flags & (1 << 25)) cursor += 2 * sizeof(void *);
    const char *signature = *(const char *const *)cursor;
    return signature ? [NSMethodSignature signatureWithObjCTypes:signature] : nil;
}
static void DY778SparkTrackManager(id manager, id conversation) {
    NSString *account = DY778SparkConversationAccount(conversation), *identifier = DY778SparkConversationID(conversation);
    uint64_t generation = atomic_fetch_add_explicit(&DY778SparkManagerGeneration, 1, memory_order_acq_rel) + 1;
    NSDictionary *ticket = @{@"account":account ?: @"", @"conversation":identifier ?: @"", @"generation":@(generation)};
    objc_setAssociatedObject(manager, &DY778SparkManagerScopeKey, ticket, OBJC_ASSOCIATION_RETAIN);
    @synchronized (DY778SparkManagerLock()) {
        if (!DY778SparkManagers) DY778SparkManagers = [NSHashTable weakObjectsHashTable];
        [DY778SparkManagers addObject:manager];
    }
}
static void DY778SparkInstallManagers(void) {
    Class cls = NSClassFromString(@"_TtC15AWEIMGrowthImpl20StreakDisplayManager");
    static BOOL setup[2], attributed[2];
    NSArray *names = @[@"setupWithConversation:", @"setupWithConversation:peerUser:"];
    for (NSUInteger i = 0; i < names.count; i++) {
        if (setup[i]) continue;
        SEL selector = NSSelectorFromString(names[i]); Method method = class_getInstanceMethod(cls, selector);
        if (!DY778SparkSignature(method, "v", i ? "@@" : "@")) continue;
        IMP original = method_getImplementation(method), replacement;
        if (i) replacement = imp_implementationWithBlock(^(id manager, id conversation, id peer) {
            DY778SparkTrackManager(manager, conversation);
            ((void (*)(id, SEL, id, id))original)(manager, selector, conversation, peer);
        });
        else replacement = imp_implementationWithBlock(^(id manager, id conversation) {
            DY778SparkTrackManager(manager, conversation);
            ((void (*)(id, SEL, id))original)(manager, selector, conversation);
        });
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method)); setup[i] = YES;
    }
    NSArray *callbacks = @[@"getStreakAttributedStringWithCompletion:", @"getStreakYYAttributedStringWithCompletion:"];
    for (NSUInteger i = 0; i < callbacks.count; i++) {
        if (attributed[i]) continue;
        SEL selector = NSSelectorFromString(callbacks[i]); Method method = class_getInstanceMethod(cls, selector);
        if (!DY778SparkSignature(method, "v", "@")) continue;
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(id manager, id completion) {
            NSMethodSignature *signature = DY778SparkBlockSignature(completion);
            NSDictionary *ticket = objc_getAssociatedObject(manager, &DY778SparkManagerScopeKey);
            if (!ticket || !signature || signature.numberOfArguments != 3 || signature.methodReturnType[0] != 'v' ||
                [signature getArgumentTypeAtIndex:1][0] != '@' || strcmp([signature getArgumentTypeAtIndex:2], @encode(CGSize))) {
                ((void (*)(id, SEL, id))original)(manager, selector, completion); return;
            }
            uint64_t revision = atomic_load_explicit(&DY778SparkRevision, memory_order_acquire);
            __weak id weakManager = manager;
            void (^wrapped)(id, CGSize) = ^(id result, CGSize size) {
                id owner = weakManager, current = DY778Read(owner, @"conversation");
                NSDictionary *latest = objc_getAssociatedObject(owner, &DY778SparkManagerScopeKey);
                BOOL same = DY778SparkScopeMatches([ticket[@"account"] UTF8String],
                    [ticket[@"conversation"] UTF8String], DY778SparkConversationAccount(current).UTF8String,
                    DY778SparkConversationID(current).UTF8String);
                if (!DY778SparkDeliveryIsCurrent([ticket[@"generation"] unsignedLongLongValue], [latest[@"generation"] unsignedLongLongValue],
                    revision, atomic_load_explicit(&DY778SparkRevision, memory_order_acquire), same)) return;
                ((void (^)(id, CGSize))completion)(result, size);
            };
            ((void (*)(id, SEL, id))original)(manager, selector, wrapped);
        });
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method)); attributed[i] = YES;
    }
    DY778RecordHook(@"spark.nativeManagerScope", setup[0] && setup[1]);
    DY778RecordHook(@"spark.nativeDeliveryScope", attributed[0] && attributed[1]);
}
static void DY778SparkInstallDetails(void) {
    static BOOL injectorInstalled, routeInstalled, hunterInstalled[2], initialInstalled[2], updateInstalled;
    static BOOL injectionEndInstalled;
    Class injector = NSClassFromString(@"AWEIMStreakHunterBizDataInjector");
    SEL clientInject = NSSelectorFromString(@"achievementIMHunterClientDataWithConversation:");
    Method clientMethod = class_getInstanceMethod(injector, clientInject);
    if (!DY778SparkOriginalClientInjector && DY778SparkSignature(clientMethod, "@", "@"))
        DY778SparkOriginalClientInjector = method_getImplementation(clientMethod);
    SEL inject = NSSelectorFromString(@"achievementIMHunterServerDataWithConversation:");
    Method method = class_getInstanceMethod(injector, inject);
    if (!injectorInstalled && DY778SparkSignature(method, "@", "@")) {
        DY778SparkOriginalInjector = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^id(id owner, id conversation) {
            DY778SparkInjector = owner;
            return ((id (*)(id, SEL, id))DY778SparkOriginalInjector)(owner, inject, conversation);
        });
        class_replaceMethod(injector, inject, replacement, method_getTypeEncoding(method)); injectorInstalled = YES;
    }
    Class param = NSClassFromString(@"IESIMOpenHunterContainerParamModel");
    SEL setter = NSSelectorFromString(@"setConversation:"); method = class_getInstanceMethod(param, setter);
    if (!routeInstalled && DY778SparkSignature(method, "v", "@")) {
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(id model, id conversation) {
            ((void (*)(id, SEL, id))original)(model, setter, conversation);
            if (NSThread.isMainThread) DY778SparkRememberPopupRoute(conversation, DY778Read(model, @"schema"));
        });
        class_replaceMethod(param, setter, replacement, method_getTypeEncoding(method)); routeInstalled = YES;
    }
    Class hunter = NSClassFromString(@"HunterContainerViewModel");
    NSArray *names = @[@"getContainerData", @"getUpdatedContainerDataWithDynamicPatchModel:"];
    for (NSUInteger i = 0; i < names.count; i++) {
        if (hunterInstalled[i]) continue;
        SEL selector = NSSelectorFromString(names[i]); method = class_getInstanceMethod(hunter, selector);
        if (!DY778SparkSignature(method, "@", i ? "@" : "")) continue;
        IMP original = method_getImplementation(method), replacement;
        if (i) replacement = imp_implementationWithBlock(^id(id viewModel, id model) {
            id data = ((id (*)(id, SEL, id))original)(viewModel, selector, model);
            return DY778SparkProjectValue(data, DY778SparkPopupForViewModel(viewModel, model));
        });
        else replacement = imp_implementationWithBlock(^id(id viewModel) {
            id data = ((id (*)(id, SEL))original)(viewModel, selector);
            return DY778SparkProjectValue(data, DY778SparkPopupForViewModel(viewModel, DY778Read(viewModel, @"dynamicPatchModel")));
        });
        class_replaceMethod(hunter, selector, replacement, method_getTypeEncoding(method)); hunterInstalled[i] = YES;
    }
    Class plugin = NSClassFromString(@"IESIMHunterDataInjectionPlugin");
    SEL processEnd = NSSelectorFromString(@"onHunterProcessEnd:"); method = class_getInstanceMethod(plugin, processEnd);
    if (!injectionEndInstalled && DY778SparkSignature(method, "v", "@")) {
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(id owner, id argument) {
            ((void (*)(id, SEL, id))original)(owner, processEnd, argument);
            if (!NSThread.isMainThread) return;
            id container = DY778Read(owner, @"hunterContainerView"), model = DY778Read(container, @"dynamicPatchModel");
            NSString *schema = DY778SparkURLString(DY778Read(model, @"schema"));
            DY778SparkPanelBinding *binding = DY778SparkPopupScopeForSchema(schema);
            if (!binding) return;
            id context = DY778Read(DY778Read(owner, @"hunterContext"), @"bdxContext");
            id data = DY778Read(context, @"initialData"), visible = DY778SparkProjectValue(data, binding);
            if (context) objc_setAssociatedObject(context, &DY778SparkPopupBindingKey, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (visible != data) DY778Write(context, @"initialData", visible);
        });
        class_replaceMethod(plugin, processEnd, replacement, method_getTypeEncoding(method)); injectionEndInstalled = YES;
    }
    Class bdx = NSClassFromString(@"BDXLynxView");
    NSArray *initial = @[@"getNewInitialData", @"p_generateInitData_deprecated"];
    for (NSUInteger i = 0; i < initial.count; i++) {
        if (initialInstalled[i]) continue;
        SEL selector = NSSelectorFromString(initial[i]); method = class_getInstanceMethod(bdx, selector);
        if (!DY778SparkSignature(method, "@", "")) continue;
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^id(id view) {
            id data = ((id (*)(id, SEL))original)(view, selector);
            DY778SparkPanelBinding *binding = DY778SparkPopupForBDX(view);
            return DY778SparkProjectValue(data, binding);
        });
        class_replaceMethod(bdx, selector, replacement, method_getTypeEncoding(method)); initialInstalled[i] = YES;
    }
    SEL update = NSSelectorFromString(@"updateData:processorName:"); method = class_getInstanceMethod(bdx, update);
    if (!updateInstalled && DY778SparkSignature(method, "v", "@@")) {
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(id view, id data, id processor) {
            DY778SparkPanelBinding *binding = DY778SparkPopupForBDX(view);
            if (!DY778SparkValueMatchesScope(data, binding)) return;
            id visible = DY778SparkProjectValue(data, binding);
            ((void (*)(id, SEL, id, id))original)(view, update, visible, processor);
        });
        class_replaceMethod(bdx, update, replacement, method_getTypeEncoding(method)); updateInstalled = YES;
    }
    DY778RecordHook(@"spark.nativeDetailSource", injectorInstalled);
    DY778RecordHook(@"spark.nativeDetailClientSource", DY778SparkOriginalClientInjector != NULL);
    DY778RecordHook(@"spark.detailRoute", routeInstalled);
    DY778RecordHook(@"spark.detailContainer", hunterInstalled[0] && hunterInstalled[1]);
    DY778RecordHook(@"spark.detailFinalInjection", injectionEndInstalled);
    DY778RecordHook(@"spark.detailGeneratedData", initialInstalled[0] && initialInstalled[1]);
    DY778RecordHook(@"spark.detailUpdate", updateInstalled);
}
void DY778InstallSpark(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallSpark(); }); return; }
    [DY778Preferences() registerDefaults:@{DY778SparkMasterKey:@NO, DY778SparkSettingsKey:@{}}];
    DY778SparkInstallNativeModels(); DY778SparkInstallManagers(); DY778SparkInstallDetails();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSString *key = note.userInfo[@"key"];
            if (!key.length || [key hasPrefix:@"spark."]) DY778SparkRefreshViews();
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { DY778SparkRefreshViews(); }];
    });
    DY778InstallSparkMenu();
}

@interface DY778SparkController : UITableViewController
@property(nonatomic, copy) NSString *account;
@property(nonatomic, copy) NSString *conversation;
@property(nonatomic, copy) NSString *personName;
@end

static UITableViewCell *DY778SparkCell(NSString *title, NSString *subtitle, BOOL arrow) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = DY778CardBackground();
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = title; content.secondaryText = subtitle;
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    content.textProperties.color = UIColor.labelColor;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(14, 20, 14, 20);
    cell.contentConfiguration = content;
    cell.accessoryType = arrow ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}
@implementation DY778SparkController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = self.conversation.length ? @"自定义火花" : @"聊天火花";
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 64;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:DY778PreferencesChangedNotification object:nil];
    [self refresh];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)refresh { DY778StyleController(self); [self.tableView reloadData]; }
- (BOOL)validAccount {
    if (!self.account.length || ![self.account isEqual:DY778CurrentAccountID()]) {
        DY778Toast(@"账号已变化，请重新打开火花设置"); return NO;
    }
    return YES;
}
- (NSDictionary *)options { return DY778SparkOptions(self.account, self.conversation); }
- (NSMutableDictionary *)editableOptions {
    NSMutableDictionary *options = [self.options mutableCopy];
    NSDictionary *defaults = DY778SparkNativeDefaults(self.account, self.conversation);
    if (![options[@"days"] isKindOfClass:NSNumber.class]) options[@"days"] = defaults[@"days"];
    if (![options[@"lit"] isKindOfClass:NSNumber.class]) options[@"lit"] = defaults[@"lit"];
    return options;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.conversation.length ? 3 : 1;
    return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? (self.personName.length ? self.personName : @"显示设置") : @"恢复原状";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"恢复后使用抖音原始显示，并同步已适配页面；不会影响真实火花、聊天记录或对方看到的内容。详情未更新时，可关闭后重新进入。";
    if (!self.conversation.length) return @"开启后，在聊天右上角信息页选择“自定义火花”，分别设置单聊或群聊的天数和点亮状态。沿用已有的原生火花入口和样式，仅改变本机显示，不增加真实天数或奖励。";
    return DY778Bool(DY778SparkMasterKey) ? @"仅对此聊天生效，支持已点亮、已熄灭和点亮中的原生火花入口。沿用抖音图标、配色与布局，同步已适配的聊天、列表和详情；详情未更新时，可关闭后重新进入。" : @"总开关目前关闭，下面的设置会保留。请先在 DY778 → 聊天火花开启总开关。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 1) return DY778SparkCell(self.conversation.length ? @"恢复此聊天原状" : @"恢复当前账号全部火花", @"清除对应的自定义显示设置", NO);
    if (path.row == 0) {
        UITableViewCell *cell = DY778SparkCell(self.conversation.length ? @"启用此聊天" : @"启用火花自定义", @"只修改本机显示", NO);
        UISwitch *toggle = [UISwitch new]; toggle.onTintColor = DY778Accent();
        toggle.on = self.conversation.length ? [self.options[@"enabled"] boolValue] : DY778Bool(DY778SparkMasterKey);
        [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; return cell;
    }
    if (path.row == 1) return DY778SparkCell(@"火花状态", [self.editableOptions[@"lit"] boolValue] ? @"点亮" : @"熄灭", YES);
    return DY778SparkCell(@"显示天数", [NSString stringWithFormat:@"%@ 天", self.editableOptions[@"days"]], YES);
}
- (void)toggle:(UISwitch *)toggle {
    if (![self validAccount]) { [self refresh]; return; }
    if (!self.conversation.length) DY778Set(DY778SparkMasterKey, @(toggle.on));
    else { NSMutableDictionary *options = self.editableOptions; options[@"enabled"] = @(toggle.on); DY778SparkSave(self.account, self.conversation, options); }
    DY778Toast(!toggle.on ? @"已恢复抖音原始显示" : self.conversation.length && !DY778Bool(DY778SparkMasterKey) ?
               @"设置已保存，开启总开关后生效" : @"已启用火花自定义显示");
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (![self validAccount]) return;
    if (path.section == 1) {
        DY778Confirm(self, @"恢复火花原状？", self.conversation.length ? @"将清除此聊天的自定义天数和状态，并恢复抖音原始显示。" : @"将清除当前账号所有聊天的火花自定义显示，其他账号的设置不受影响。", @"恢复原状", YES, ^{
            if (![self validAccount]) return;
            if (self.conversation.length) {
                DY778SparkSave(self.account, self.conversation, nil); DY778SparkRefreshViews(); [self refresh];
                DY778Toast(@"已恢复此聊天的火花显示");
            } else { DY778RestoreSparkForAccount(self.account); [self refresh]; }
        }); return;
    }
    if (!self.conversation.length || path.row == 0) return;
    if (path.row == 1) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"火花状态" message:@"仅改变本机显示" preferredStyle:UIAlertControllerStyleActionSheet];
        sheet.overrideUserInterfaceStyle = DY778InterfaceStyle(); sheet.view.tintColor = DY778Accent();
        for (NSNumber *lit in @[@YES, @NO]) [sheet addAction:[UIAlertAction actionWithTitle:lit.boolValue ? @"点亮" : @"熄灭" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            if (![self validAccount]) return;
            NSMutableDictionary *options = self.editableOptions; options[@"lit"] = lit; DY778SparkSave(self.account, self.conversation, options);
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:path];
        sheet.popoverPresentationController.sourceRect = [tableView cellForRowAtIndexPath:path].bounds;
        [self presentViewController:sheet animated:YES completion:nil]; return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"显示天数" message:@"输入 1–99999 的整数，仅用于本机展示。" preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = DY778InterfaceStyle(); alert.view.tintColor = DY778Accent();
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.keyboardType = UIKeyboardTypeNumberPad; field.text = [self.editableOptions[@"days"] stringValue]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        if (![self validAccount]) return;
        unsigned days = 0;
        if (!DY778SparkParseDays(alert.textFields.firstObject.text.UTF8String, &days)) { DY778Toast(@"请输入 1–99999 的整数，原设置已保留"); return; }
        NSMutableDictionary *options = self.editableOptions; options[@"days"] = @(days); DY778SparkSave(self.account, self.conversation, options);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

UIViewController *DY778SparkSettingsController(void) {
    DY778SparkController *controller = [DY778SparkController new]; controller.account = DY778CurrentAccountID(); return controller;
}
@protocol DY778SparkChatItemInitializable <NSObject>
- (instancetype)initWithIdentifier:(NSString *)identifier;
@end
void DY778SparkAppendChatItem(id provider, NSMutableArray *items) {
    id context = DY778Read(provider, @"context");
    id conversation = DY778SparkContextConversation(context);
    NSString *identifier = DY778SparkConversationID(conversation), *account = DY778SparkConversationAccount(conversation);
    NSString *peerID = DY778SparkContextPeerID(context, conversation);
    BOOL group = DY778SparkIsGroup(conversation);
    BOOL conversationMatched = identifier.length > 0;
    BOOL accountMatched = account.length > 0 && [account isEqual:DY778CurrentAccountID()];
    BOOL peerMatched = group || peerID.length > 0;
    DY778RecordHook(@"spark.chatEntry.conversation", conversationMatched);
    DY778RecordHook(@"spark.chatEntry.account", accountMatched);
    DY778RecordHook(@"spark.chatEntry.peer", peerMatched);
    DY778RecordHook(@"spark.chatEntry.group", group);
    DY778RecordHook(@"spark.chatEntry.itemModel", NO);
    DY778RecordHook(@"spark.chatEntry.inserted", NO);
    if (!conversationMatched || !accountMatched || !peerMatched) return;
    for (id existing in items) if ([DY778Read(existing, @"identifier") isEqual:@"com.dy778.spark-settings"]) {
        DY778RecordHook(@"spark.chatEntry.itemModel", YES);
        DY778RecordHook(@"spark.chatEntry.inserted", YES); return;
    }
    Class cls = NSClassFromString(@"IESIMChatSettingsItemInfoViewModel"); SEL initializer = NSSelectorFromString(@"initWithIdentifier:");
    BOOL modelSupported = DY778SparkSignature(class_getInstanceMethod(cls, initializer), "@", "@");
    DY778RecordHook(@"spark.chatEntry.itemModel", modelSupported);
    if (!modelSupported) return;
    id item = [(id<DY778SparkChatItemInitializable>)[cls alloc] initWithIdentifier:@"com.dy778.spark-settings"];
    __weak id weakProvider = provider;
    dispatch_block_t open = ^{
        id currentContext = DY778Read(weakProvider, @"context");
        id currentConversation = DY778SparkContextConversation(currentContext);
        if (!DY778SparkScopeMatches(account.UTF8String, identifier.UTF8String, DY778CurrentAccountID().UTF8String,
                                    DY778SparkConversationID(currentConversation).UTF8String) ||
            ![account isEqual:DY778SparkConversationAccount(currentConversation)] ||
            (group ? !DY778SparkIsGroup(currentConversation) : ![peerID isEqual:DY778SparkContextPeerID(currentContext, currentConversation)])) {
            DY778Toast(@"会话信息已变化，请重新打开聊天信息页"); return;
        }
        DY778SparkController *controller = [DY778SparkController new]; controller.account = account; controller.conversation = identifier;
        id name = group ? DY778Read(currentConversation, @"name") : DY778Read(DY778Read(currentContext, @"peerUser"), @"nickname");
        if ([name isKindOfClass:NSString.class]) controller.personName = name;
        UIViewController *source = DY778Read(currentContext, @"hostViewController");
        DY778PresentController([source isKindOfClass:UIViewController.class] ? source : DY778TopController(), controller);
    };
    if (item && DY778Write(item, @"title", @"自定义火花") && DY778Write(item, @"subtitle", @"天数与点亮状态 · 仅本机显示") && DY778Write(item, @"onClicked", open)) {
        DY778Write(item, @"disableArrow", @NO); [items addObject:item];
        DY778RecordHook(@"spark.chatEntry.inserted", YES);
    }
}

void DY778ResetSpark(void) {
    DY778Set(DY778SparkMasterKey, @NO); DY778Set(DY778SparkSettingsKey, @{}); DY778SparkRefreshViews();
}
BOOL DY778SparkHasCustomizationsForAccount(NSString *account) {
    if (!account.length || ![account isEqual:DY778CurrentAccountID()]) return NO;
    id chats = DY778SparkAllSettings()[account];
    return [chats isKindOfClass:NSDictionary.class] && [chats count] > 0;
}
void DY778RestoreSparkForAccount(NSString *account) {
    if (!NSThread.isMainThread) {
        NSString *captured = [account copy]; dispatch_async(dispatch_get_main_queue(), ^{ DY778RestoreSparkForAccount(captured); }); return;
    }
    if (!account.length || ![account isEqual:DY778CurrentAccountID()]) {
        DY778Toast(@"账号已变化，请重新打开当前页面"); return;
    }
    NSMutableDictionary *all = [DY778SparkAllSettings() mutableCopy];
    [all removeObjectForKey:account]; DY778Set(DY778SparkSettingsKey, all);
    DY778SparkRefreshViews();
    DY778Toast(@"已恢复当前账号的火花显示");
}
