#import "DY778RadarModel.h"
#import "DY778RadarPolicy.h"
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>
NSString *const DY778RadarVersion = @"1.0-3";
NSString *const DY778RadarName = @"特别关注";
NSNotificationName const DY778RadarStoreChanged = @"DY778Radar.StoreChanged";
NSNotificationName const DY778RadarThemeChanged = @"DY778Radar.ThemeChanged";
NSUInteger const DY778RadarSignatureLimit = 2048;

NSString *DY778RadarSignatureText(id value) {
    if (![value isKindOfClass:NSString.class]) return @"暂未读取";
    return [value length] ? value : @"（空简介）";
}

id DY778RadarRead(id object, NSString *key) {
    if (!object || object == NSNull.null) return nil;
    if ([object isKindOfClass:NSDictionary.class]) {
        id value = object[key];
        return value == NSNull.null ? nil : value;
    }
    if (![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try { return [object valueForKey:key]; } @catch (__unused NSException *exception) { return nil; }
}
id DY778RadarFirst(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) { id value = DY778RadarRead(object, key); if (value) return value; }
    return nil;
}
NSString *DY778RadarString(id value) {
    NSString *text = [value isKindOfClass:NSString.class] ? value :
        [value isKindOfClass:NSNumber.class] ? [value stringValue] : @"";
    return text.length > 8192 ? [text substringToIndex:8192] : text;
}
NSNumber *DY778RadarCount(id value) {
    if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class]) return nil;
    NSString *text = DY778RadarString(value);
    if (!text.length || text.length > 16 || [text rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) return nil;
    long long number = text.longLongValue;
    return number >= 0 && number <= 9007199254740991LL ? @(number) : nil;
}
BOOL DY778RadarIdentifier(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > 80) return NO;
    return [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location == NSNotFound;
}
BOOL DY778RadarSet(id object, NSString *key, id value) {
    if (!object) return NO;
    @try { [object setValue:value forKey:key]; return YES; } @catch (__unused NSException *exception) { return NO; }
}
BOOL DY778RadarHasMethod(id receiver, NSString *selector, const char *returns, const char *arguments) {
    NSMethodSignature *s = [receiver methodSignatureForSelector:NSSelectorFromString(selector)];
    if (!s || s.numberOfArguments != strlen(arguments) + 2 || !strchr(returns, s.methodReturnType[0])) return NO;
    for (NSUInteger i = 0; arguments[i]; i++) if ([s getArgumentTypeAtIndex:i + 2][0] != arguments[i]) return NO;
    return YES;
}
// 动态调用仅限已支持的 Objective-C ABI 类型。
id DY778RadarCall(id receiver, NSString *selector, NSArray *arguments) {
    SEL sel = NSSelectorFromString(selector);
    if (!receiver || ![receiver respondsToSelector:sel]) return nil;
    NSMethodSignature *s = [receiver methodSignatureForSelector:sel];
    if (!s || s.numberOfArguments != arguments.count + 2) return nil;
    @try {
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:s];
        inv.target = receiver; inv.selector = sel;
        for (NSUInteger i = 0; i < arguments.count; i++) {
            id arg = arguments[i] == NSNull.null ? nil : arguments[i];
            const char *type = [s getArgumentTypeAtIndex:i + 2];
            switch (type[0]) {
                case '@': case '#': { id v = arg; [inv setArgument:&v atIndex:i + 2]; break; }
                case 'B': case 'c': { BOOL v = [arg boolValue]; [inv setArgument:&v atIndex:i + 2]; break; }
                case 'i': { int v = [arg intValue]; [inv setArgument:&v atIndex:i + 2]; break; }
                case 'I': { unsigned int v = [arg unsignedIntValue]; [inv setArgument:&v atIndex:i + 2]; break; }
                case 'q': { long long v = [arg longLongValue]; [inv setArgument:&v atIndex:i + 2]; break; }
                case 'Q': { unsigned long long v = [arg unsignedLongLongValue]; [inv setArgument:&v atIndex:i + 2]; break; }
                case 'd': { double v = [arg doubleValue]; [inv setArgument:&v atIndex:i + 2]; break; }
                default: return nil;
            }
        }
        [inv retainArguments];
        [inv invoke];
        switch (s.methodReturnType[0]) {
            case '@': case '#': { __unsafe_unretained id v = nil; [inv getReturnValue:&v]; return v; }
            case 'B': case 'c': { BOOL v = NO; [inv getReturnValue:&v]; return @(v); }
            case 'i': { int v = 0; [inv getReturnValue:&v]; return @(v); }
            case 'I': { unsigned int v = 0; [inv getReturnValue:&v]; return @(v); }
            case 'q': { long long v = 0; [inv getReturnValue:&v]; return @(v); }
            case 'Q': { unsigned long long v = 0; [inv getReturnValue:&v]; return @(v); }
            default: return nil;
        }
    } @catch (__unused NSException *exception) { return nil; }
}
static NSString *DY778RadarURL(id model) {
    if ([model isKindOfClass:NSURL.class]) model = [model absoluteString];
    if ([model isKindOfClass:NSString.class]) {
        NSURL *url = [NSURL URLWithString:model];
        return [url.scheme isEqual:@"https"] && url.host.length && [model length] <= 2048 ? model : @"";
    }
    id list = [model isKindOfClass:NSArray.class] ? model : DY778RadarFirst(model, @[@"url_list", @"URLList"]);
    if (![list isKindOfClass:NSArray.class]) return @"";
    for (id raw in list) { NSString *url = DY778RadarURL(raw); if (url.length) return url; }
    return @"";
}
NSString *DY778RadarDisplayName(NSDictionary *person) {
    for (NSString *key in @[@"note", @"remark", @"name", @"handle", @"uid"]) {
        NSString *text = [DY778RadarString(person[key]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) return text;
    }
    return @"关注对象";
}
NSString *DY778RadarPersonSearchText(NSDictionary *person) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in @[@"note", @"remark", @"name", @"handle"]) if (DY778RadarString(person[key]).length) [parts addObject:person[key]];
    return [parts componentsJoinedByString:@" "];
}
NSDictionary *DY778RadarProfile(id value) {
    id nested = DY778RadarFirst(value, @[@"user", @"user_info", @"userInfo"]);
    if (nested) value = nested;
    NSString *uid = DY778RadarString(DY778RadarFirst(value, @[@"uid", @"userID"]));
    if (!DY778RadarIdentifier(uid) || [uid isEqualToString:@"0"]) return nil;
    NSString *handle = @"";
    for (NSString *key in @[@"unique_id", @"uniqueIDForShow", @"uniqueID", @"userUniqueId", @"customID", @"short_id", @"shortID"]) {
        NSString *candidate = DY778RadarString(DY778RadarRead(value, key));
        if (candidate.length && ![candidate isEqualToString:@"0"]) { handle = candidate; break; }
    }
    if (handle.length > 64) handle = [handle substringToIndex:64];
    NSString *name = DY778RadarString(DY778RadarFirst(value, @[@"nickname", @"name"]));
    if (name.length > 120) name = [name substringToIndex:120];
    NSMutableDictionary *result = [@{@"uid": uid, @"secUID": DY778RadarString(DY778RadarFirst(value, @[@"sec_uid", @"secUserID"])),
        @"handle": handle, @"name": name.length ? name : (handle.length ? handle : uid),
        @"avatar": DY778RadarURL(DY778RadarFirst(value, @[@"avatar_thumb", @"avatarThumb", @"avatarSmallStrUrl", @"avatarURLSmall"]))} mutableCopy];
    id remark = DY778RadarFirst(value, @[@"alias", @"remark_name", @"remark"]);
    if ([remark isKindOfClass:NSString.class]) result[@"remark"] = [remark length] > 120 ? [remark substringToIndex:120] : remark;
    // 只有明确的空串才表示已清空；有效文本按原样比较。
    id signature = DY778RadarRead(value, @"signature");
    if ([signature isKindOfClass:NSString.class] && [signature length] <= DY778RadarSignatureLimit)
        result[@"signature"] = [signature copy];
    for (NSString *key in @[@"avatar_medium", @"avatarMedium", @"avatar_thumb", @"avatarThumb", @"avatarURLSmall", @"avatarSmallStrUrl", @"avatarStrUrls", @"avatarURLList", @"avatarURL", @"avatarLarger", @"avatar"])
        if (DY778RadarURL(DY778RadarRead(value, key)).length) { result[@"avatar"] = DY778RadarURL(DY778RadarRead(value, key)); break; }
    NSDictionary *mapping = @{@"received": @[@"total_favorited", @"favoritedCount"],
        @"following": @[@"following_count", @"followingCount"], @"followers": @[@"follower_count", @"followerCount"],
        @"likes": @[@"favoriting_count", @"favoritingCount"]};
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSString *key in mapping) {
        for (NSString *field in mapping[key]) { NSNumber *n = DY778RadarCount(DY778RadarRead(value, field)); if (n) { counts[key] = n; break; } }
    }
    NSMutableArray *hidden = [NSMutableArray array];
    if ([DY778RadarCount(DY778RadarFirst(value, @[@"hide_total_favorited", @"hideTotalFavorited"])) boolValue]) { [counts removeObjectForKey:@"received"]; [hidden addObject:@"received"]; }
    result[@"counts"] = counts;
    id visible = DY778RadarFirst(value, @[@"show_favorite_list", @"showFavoriteList"]);
    if ([visible isKindOfClass:NSNumber.class]) result[@"likesVisible"] = @([visible boolValue]);
    id tab = DY778RadarFirst(value, @[@"tab_settings", @"tabSetting"]);
    if ([DY778RadarCount(DY778RadarFirst(tab, @[@"hide_like_tab", @"hideLikeTab"])) boolValue]) result[@"likesVisible"] = @NO;
    if (result[@"likesVisible"] && ![result[@"likesVisible"] boolValue] && [counts[@"likes"] longLongValue] == 0) { [counts removeObjectForKey:@"likes"]; [hidden addObject:@"likes"]; }
    result[@"hiddenMetrics"] = hidden;
    return result;
}
NSDictionary *DY778RadarVideo(id value) {
    NSString *vid = DY778RadarString(DY778RadarFirst(value, @[@"aweme_id", @"itemID"]));
    if (!DY778RadarIdentifier(vid)) return nil;
    NSDictionary *author = DY778RadarProfile(DY778RadarRead(value, @"author")) ?: @{};
    id video = DY778RadarRead(value, @"video");
    NSString *caption = DY778RadarString(DY778RadarFirst(value, @[@"desc", @"descriptionString"]));
    if (caption.length > 2500) caption = [[caption substringToIndex:2500] stringByAppendingString:@"…"];
    return @{@"id": vid, @"text": caption,
        @"author": DY778RadarString(author[@"name"]), @"authorAvatar": DY778RadarString(author[@"avatar"]), @"authorHandle": DY778RadarString(author[@"handle"]),
        @"authorUID": DY778RadarString(author[@"uid"]), @"authorSecUID": DY778RadarString(author[@"secUID"]),
        @"publishedAt": DY778RadarCount(DY778RadarFirst(value, @[@"create_time", @"createTime"])) ?: @0,
        @"url": [@"https://www.douyin.com/video/" stringByAppendingString:vid],
        @"cover": DY778RadarURL(DY778RadarFirst(video, @[@"cover", @"origin_cover"])),
        @"type": DY778RadarCount(DY778RadarFirst(value, @[@"aweme_type", @"awemeType"])) ?: @0};
}
NSString *DY778RadarMetricName(NSString *key) {
    return (@{@"received": @"获赞", @"following": @"关注", @"followers": @"粉丝", @"likes": @"喜欢"})[key] ?: key;
}
NSArray<NSDictionary *> *DY778RadarChanges(NSDictionary *previous, NSDictionary *current) {
    NSMutableArray *changes = [NSMutableArray array];
    for (NSString *key in @[@"received", @"following", @"followers", @"likes"]) {
        NSNumber *before = DY778RadarCount(previous[key]), *after = DY778RadarCount(current[key]);
        if (before && after && ![before isEqualToNumber:after])
            [changes addObject:@{@"key": key, @"before": before, @"after": after, @"delta": @(after.longLongValue - before.longLongValue)}];
    }
    return changes;
}
NSDictionary *DY778RadarCompareLikes(NSDictionary *previous, NSArray<NSDictionary *> *videos, BOOL complete) {
    NSArray *old = [previous[@"head"] isKindOfClass:NSArray.class] ? previous[@"head"] : @[];
    NSArray *seen = [previous[@"seen"] isKindOfClass:NSArray.class] ? previous[@"seen"] : @[];
    NSArray *ids = [videos valueForKey:@"id"];
    NSUInteger count = ids.count;
    const char **cur = calloc(MAX(count, 1), sizeof(char *));
    const char **prior = calloc(MAX(old.count, 1), sizeof(char *));
    const char **known = calloc(MAX(seen.count, 1), sizeof(char *));
    bool *selected = calloc(MAX(count, 1), sizeof(bool));
    if (!cur || !prior || !known || !selected) { free(cur); free(prior); free(known); free(selected); return @{}; }
    for (NSUInteger i = 0; i < count; i++) cur[i] = DY778RadarString(ids[i]).UTF8String;
    for (NSUInteger i = 0; i < old.count; i++) prior[i] = DY778RadarString(old[i]).UTF8String;
    for (NSUInteger i = 0; i < seen.count; i++) known[i] = DY778RadarString(seen[i]).UTF8String;
    bool gap = false;
    DY778RadarNewItems(cur, count, prior, old.count, known, seen.count, [previous[@"valid"] boolValue], [previous[@"complete"] boolValue], selected, &gap);
    NSMutableArray *fresh = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) if (selected[i]) [fresh addObject:videos[i]];
    free(cur); free(prior); free(known); free(selected);
    NSMutableOrderedSet *recent = [NSMutableOrderedSet orderedSetWithArray:ids];
    [recent addObjectsFromArray:seen];
    NSArray *recentIDs = recent.array;
    if (recentIDs.count > 300) recentIDs = [recentIDs subarrayWithRange:NSMakeRange(0, 300)];
    return @{@"new": fresh, @"gap": @(gap), @"snapshot": @{@"head": ids, @"seen": recentIDs, @"complete": @(complete), @"valid": @YES}};
}
NSString *DY778RadarDateText(NSTimeInterval timestamp) {
    if (timestamp <= 0) return @"尚未检测";
    NSDateFormatter *f = [NSDateFormatter new]; f.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss"; return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}
NSError *DY778RadarError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"DY778Radar" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}
