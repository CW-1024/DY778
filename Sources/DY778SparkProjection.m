#import "DY778SparkProjection.h"
#import "DY778SparkPolicy.h"

static id DY778SparkModelRead(id model, NSString *key) {
    @try { return [model valueForKey:key]; } @catch (__unused NSException *exception) { return nil; }
}
static BOOL DY778SparkModelWrite(id model, NSString *key, id value) {
    NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
    if (![model respondsToSelector:NSSelectorFromString(setter)]) return NO;
    @try { [model setValue:value forKey:key]; return YES; } @catch (__unused NSException *exception) { return NO; }
}
static BOOL DY778SparkProjectionOptions(NSDictionary *options) {
    if (![options isKindOfClass:[NSDictionary class]]) return NO;
    id days = [options objectForKey:@"days"], lit = [options objectForKey:@"lit"];
    unsigned parsed = 0;
    return [lit isKindOfClass:[NSNumber class]] && [days isKindOfClass:[NSNumber class]] &&
        DY778SparkParseDays([[days stringValue] UTF8String], &parsed);
}
static id DY778SparkDetachedModel(id model, NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls || (model && ![model isKindOfClass:cls])) return nil;
    @try {
        if (!model) return [cls new];
        if (![model respondsToSelector:@selector(copyWithZone:)]) return nil;
        id copy = [model copy];
        return copy != model && [copy isKindOfClass:cls] ? copy : nil;
    } @catch (__unused NSException *exception) { return nil; }
}
static BOOL DY778SparkColoredLevel(id value) {
    if (![value isKindOfClass:[NSString class]] || ![value length]) return NO;
    for (NSString *dim in @[@"disable", @"gray", @"recover_normal", @"to_recover", @"guide"])
        if ([value isEqual:dim]) return NO;
    return YES;
}
NSString *DY778SparkProjectionLevel(id flame, id chatData) {
    id value = DY778SparkModelRead(flame, @"level");
    if (DY778SparkColoredLevel(value)) return value;
    id infos = DY778SparkModelRead(chatData, @"flameInfosModelArray");
    if ([infos isKindOfClass:[NSArray class]]) for (id info in infos) {
        value = DY778SparkModelRead(info, @"level");
        if (DY778SparkColoredLevel(value)) return value;
    }
    return @"normal";
}
id DY778SparkProjectFlameModel(id flame, NSDictionary *options, NSString *level) {
    if (!DY778SparkProjectionOptions(options)) return flame;
    id copy = DY778SparkDetachedModel(flame, @"AWEIMCodeGenStreakInfoModel");
    if (!copy) return flame;
    NSNumber *days = [options objectForKey:@"days"];
    BOOL lit = [[options objectForKey:@"lit"] boolValue];
    NSDictionary *fields = @{@"days":days, @"realDays":days, @"text":[days stringValue],
        @"simplifyText":[days stringValue], @"state":@(DY778SparkNativeDisplayState(lit)),
        @"level":lit ? (DY778SparkColoredLevel(level) ? level : @"normal") : @"gray",
        @"bizState":@0,
        @"recoverDays":@0, @"recoverNeedDays":@0, @"recoverDdl":@0, @"textStylesArray":@[]};
    for (NSString *key in fields) if (!DY778SparkModelWrite(copy, key, [fields objectForKey:key])) return flame;
    if (!flame) {
        if (!DY778SparkModelWrite(copy, @"start", @0) || !DY778SparkModelWrite(copy, @"end", @4102444800LL)) return flame;
    }
    return copy;
}
id DY778SparkProjectChatModel(id chatData, id nativeFlame, NSDictionary *options, NSString *level) {
    if (!DY778SparkProjectionOptions(options)) return chatData;
    id copy = DY778SparkDetachedModel(chatData, @"AWEIMCodeGenStreakInfoChatDataModel");
    if (!copy) return chatData;
    if (!chatData && !DY778SparkModelWrite(copy, @"expireTime", @4102444800LL)) return chatData;
    if (!DY778SparkColoredLevel(level)) level = DY778SparkProjectionLevel(nativeFlame, chatData);
    id source = DY778SparkModelRead(chatData, @"flameInfosModelArray");
    if (source && ![source isKindOfClass:[NSArray class]]) return chatData;
    NSMutableArray *infos = [NSMutableArray array];
    for (id info in source) {
        id projected = DY778SparkProjectFlameModel(info, options, level);
        if (projected == info) return chatData;
        [infos addObject:projected];
    }
    id fallback = DY778SparkProjectFlameModel(nativeFlame, options, level);
    if (!fallback || (nativeFlame && fallback == nativeFlame)) return chatData;
    [infos addObject:fallback];
    id nativeCount = DY778SparkModelRead(chatData, @"consecutiveCountInfoModel");
    id count = DY778SparkDetachedModel(nativeCount, @"AWEIMCodeGenConsecutiveCountInfoModel");
    if (!count || !DY778SparkModelWrite(count, @"consecutiveCount", [options objectForKey:@"days"])) return chatData;
    if (!nativeCount && !DY778SparkModelWrite(count, @"expireTime", @4102444800LL)) return chatData;
    if (!DY778SparkModelWrite(copy, @"flameInfosModelArray", infos) ||
        !DY778SparkModelWrite(copy, @"consecutiveCountInfoModel", count) ||
        !DY778SparkModelWrite(copy, @"disableConsecutiveChat", @(NO))) return chatData;
    return copy;
}
NSDictionary *DY778SparkProjectDetail(NSDictionary *data, NSDictionary *options) {
    if (![data isKindOfClass:[NSDictionary class]] || !DY778SparkProjectionOptions(options)) return data;
    id flame = [data objectForKey:@"flame"];
    if (![flame isKindOfClass:[NSDictionary class]]) return data;
    NSMutableDictionary *visible = [flame mutableCopy];
    [visible setObject:@(DY778SparkDetailDisplayState([[options objectForKey:@"lit"] boolValue])) forKey:@"state"];
    [visible setObject:[options objectForKey:@"days"] forKey:@"consecutive_days"];
    [visible removeObjectForKey:@"relight_days"];
    NSMutableDictionary *result = [data mutableCopy];
    [result setObject:visible forKey:@"flame"];
    return result;
}
static NSDictionary *DY778SparkMergeFlameFields(NSDictionary *flame, NSDictionary *source) {
    if (![flame isKindOfClass:[NSDictionary class]] || ![source isKindOfClass:[NSDictionary class]] ||
        ![[source objectForKey:@"state"] isKindOfClass:[NSNumber class]] ||
        ![[source objectForKey:@"consecutive_days"] isKindOfClass:[NSNumber class]]) return flame;
    NSMutableDictionary *copy = nil;
    for (NSString *key in @[@"state", @"consecutive_days", @"relight_days"]) {
        id old = [flame objectForKey:key], value = [source objectForKey:key];
        if ((!old && !value) || [old isEqual:value]) continue;
        if (!copy) copy = [flame mutableCopy];
        if (value) [copy setObject:value forKey:key]; else [copy removeObjectForKey:key];
    }
    return copy ?: flame;
}
static NSDictionary *DY778SparkMergeKnownFields(NSDictionary *data, NSDictionary *source, NSArray *keys) {
    if (![data isKindOfClass:[NSDictionary class]] || ![source isKindOfClass:[NSDictionary class]]) return data;
    NSMutableDictionary *copy = nil;
    for (NSString *key in keys) {
        id old = [data objectForKey:key], value = [source objectForKey:key];
        if ([key isEqual:@"flame"]) value = DY778SparkMergeFlameFields(old, value);
        if ([key isEqual:@"a:pet_elf_parenting"]) {
            id color = [value isKindOfClass:[NSDictionary class]] ? [value objectForKey:@"color"] : nil;
            if (![old isKindOfClass:[NSDictionary class]] || ![value isKindOfClass:[NSDictionary class]] ||
                (color && ![color isKindOfClass:[NSString class]]) || [[old objectForKey:@"color"] isEqual:color] ||
                (!color && ![old objectForKey:@"color"])) continue;
            NSMutableDictionary *parenting = [old mutableCopy];
            if (color) [parenting setObject:color forKey:@"color"]; else [parenting removeObjectForKey:@"color"];
            value = parenting;
        }
        if (!old || [old isEqual:value]) continue;
        if (!copy) copy = [data mutableCopy];
        if (value) [copy setObject:value forKey:key]; else [copy removeObjectForKey:key];
    }
    return copy ?: data;
}
static NSString *DY778SparkLegacyDays(NSString *value, NSNumber *days) {
    if (![value isKindOfClass:[NSString class]] || ![days isKindOfClass:[NSNumber class]] || [days longLongValue] < 0) return value;
    NSMutableArray *segments = [[value componentsSeparatedByString:@"|"] mutableCopy];
    if ([segments count] < 1 || [segments count] > 3) return value;
    NSMutableArray *parts = [[[segments objectAtIndex:0] componentsSeparatedByString:@":"] mutableCopy];
    if ([parts count] != 3 && [parts count] != 5) return value;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    for (NSString *part in parts) if (![part length] || [part rangeOfCharacterFromSet:invalid].location != NSNotFound) return value;
    [parts replaceObjectAtIndex:0 withObject:[days stringValue]];
    [segments replaceObjectAtIndex:0 withObject:[parts componentsJoinedByString:@":"]];
    return [segments componentsJoinedByString:@"|"];
}
static NSDictionary *DY778SparkMergeClientFields(NSDictionary *data, NSDictionary *source, NSNumber *days) {
    if (![data isKindOfClass:[NSDictionary class]]) return data;
    NSArray *keys = @[@"a:consecutive_chat_data", @"streak_status", @"a:pet_elf_parenting"];
    NSDictionary *visible = DY778SparkMergeKnownFields(data, source, keys);
    id biz = [data objectForKey:@"biz_ext"];
    id visibleBiz = DY778SparkMergeKnownFields(biz, source, keys);
    if (visibleBiz != biz) { NSMutableDictionary *copy = [visible mutableCopy]; [copy setObject:visibleBiz forKey:@"biz_ext"]; visible = copy; }
    id info = [data objectForKey:@"conversation_info"];
    if ([info isKindOfClass:[NSDictionary class]]) {
        id ext = [info objectForKey:@"conversation_core_ext"];
        id visibleExt = DY778SparkMergeKnownFields(ext, source, @[@"a:consecutive_chat_data"]);
        if ([visibleExt isKindOfClass:[NSDictionary class]]) {
            id legacy = [visibleExt objectForKey:@"a:consecutive_chat"], visibleLegacy = DY778SparkLegacyDays(legacy, days);
            if (visibleLegacy != legacy && ![visibleLegacy isEqual:legacy]) {
                NSMutableDictionary *extCopy = [visibleExt mutableCopy]; [extCopy setObject:visibleLegacy forKey:@"a:consecutive_chat"]; visibleExt = extCopy;
            }
        }
        if (visibleExt != ext) {
            NSMutableDictionary *infoCopy = [info mutableCopy]; [infoCopy setObject:visibleExt forKey:@"conversation_core_ext"];
            NSMutableDictionary *copy = [visible mutableCopy]; [copy setObject:infoCopy forKey:@"conversation_info"]; visible = copy;
        }
    }
    return visible;
}
NSDictionary *DY778SparkMergeDetailEnvelope(NSDictionary *data, NSDictionary *server, NSDictionary *client) {
    if (![data isKindOfClass:[NSDictionary class]]) return data;
    NSMutableDictionary *copy = nil;
    id flame = [server isKindOfClass:[NSDictionary class]] ? [server objectForKey:@"flame"] : nil;
    NSNumber *days = [flame isKindOfClass:[NSDictionary class]] ? [flame objectForKey:@"consecutive_days"] : nil;
    for (NSString *key in @[@"__serverData", @"__serverDataExtra", @"__clientData"]) {
        id value = [data objectForKey:key];
        id visible = [key isEqual:@"__clientData"] ? DY778SparkMergeClientFields(value, client, days) : DY778SparkMergeKnownFields(value, server, @[@"flame"]);
        if (visible != value) { if (!copy) copy = [data mutableCopy]; [copy setObject:visible forKey:key]; }
    }
    return DY778SparkMergeClientFields(DY778SparkMergeKnownFields(copy ?: data, server, @[@"flame"]), client, days);
}
