#import "DY778FansModel.h"
#import "DY778FansPolicy.h"

static NSString *DY778FansTrim(NSString *text) { return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
BOOL DY778FansShareURL(NSURL *url) {
    if (![url.scheme.lowercaseString isEqual:@"https"] || url.user.length || url.password.length || (url.port && url.port.integerValue != 443)) return NO;
    NSString *host = url.host.lowercaseString;
    for (NSString *domain in @[@"douyin.com", @"iesdouyin.com", @"amemv.com"]) {
        if ([host isEqual:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]) return YES;
    }
    return NO;
}
static NSDictionary *DY778FansURLTarget(NSURL *url) {
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in parts.queryItems) if (item.value.length) query[item.name] = item.value;
    NSArray *path = [parts.path componentsSeparatedByString:@"/"];
    for (NSUInteger i = 0; i + 1 < path.count; i++) {
        NSString *kind = path[i], *value = path[i + 1];
        if (([kind isEqual:@"video"] || [kind isEqual:@"note"] || [kind isEqual:@"slides"]) && DY778FansUID(value)) return @{@"kind": @"video", @"value": value};
        if ([kind isEqual:@"user"]) {
            if (DY778FansSecUID(value)) return @{@"kind": @"secUID", @"value": value};
            if (DY778FansUID(value)) return @{@"kind": @"uid", @"value": value};
        }
    }
    for (NSString *key in @[@"modal_id", @"aweme_id", @"item_id"]) if (DY778FansUID(query[key])) return @{@"kind": @"video", @"value": query[key]};
    for (NSString *key in @[@"sec_uid", @"sec_user_id"]) if (DY778FansSecUID(query[key])) return @{@"kind": @"secUID", @"value": query[key]};
    if (DY778FansUID(query[@"user_id"])) return @{@"kind": @"uid", @"value": query[@"user_id"]};
    return @{@"kind": @"url", @"value": url.absoluteString};
}
NSDictionary *DY778FansParseInput(NSString *input, DY778FansInputMode mode, NSError **error) {
    NSString *text = [input isKindOfClass:NSString.class] ? DY778FansTrim(input) : @"";
    if (!text.length || text.length > 8192) { if (error) *error = DY778FansError(400, @"请输入分享链接、抖音号或 UID。"); return nil; }
    if (mode == DY778FansInputUID || [text.lowercaseString hasPrefix:@"uid:"]) {
        NSString *uid = [text.lowercaseString hasPrefix:@"uid:"] ? DY778FansTrim([text substringFromIndex:4]) : text;
        if (DY778FansUID(uid)) return @{@"kind": @"uid", @"value": uid};
        if (error) *error = DY778FansError(400, @"UID 应为纯数字；主页显示的抖音号请使用“抖音号”模式。"); return nil;
    }
    if ([text.lowercaseString hasPrefix:@"sec_uid:"]) text = DY778FansTrim([text substringFromIndex:8]);
    if (DY778FansSecUID(text)) return @{@"kind": @"secUID", @"value": text};
    if (mode != DY778FansInputHandle) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"https?://[^\\s<>\\\"，。]+" options:NSRegularExpressionCaseInsensitive error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (match) {
            NSString *link = [[text substringWithRange:match.range] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@".,;!?)）】〕}]"]];
            NSURLComponents *parts = [NSURLComponents componentsWithString:link];
            if ([parts.scheme.lowercaseString isEqual:@"http"]) parts.scheme = @"https";
            if (DY778FansShareURL(parts.URL)) return DY778FansURLTarget(parts.URL);
            if (error) *error = DY778FansError(400, @"请使用抖音作品或用户主页的分享链接。"); return nil;
        }
    }
    if ([text hasPrefix:@"抖音号："] || [text hasPrefix:@"抖音号:"]) text = DY778FansTrim([text substringFromIndex:4]);
    if ([text hasPrefix:@"@"]) text = [text substringFromIndex:1];
    if (DY778FansASCIIHandle(text.UTF8String, [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding])) return @{@"kind": @"handle", @"value": text};
    if (error) *error = DY778FansError(400, @"无法识别输入，请粘贴完整分享内容，或输入准确的抖音号。");
    return nil;
}
NSString *DY778FansImageURL(id object) {
    if ([object isKindOfClass:NSURL.class]) object = [object absoluteString];
    if ([object isKindOfClass:NSString.class]) {
        NSURL *url = [NSURL URLWithString:object];
        return [url.scheme.lowercaseString isEqual:@"https"] && url.host.length && [object length] <= 4096 ? object : @"";
    }
    id list = [object isKindOfClass:NSArray.class] ? object : DY778FansFirst(object, @[@"url_list", @"urlListArray", @"originURLList", @"URLList", @"urlList"]);
    if ([list isKindOfClass:NSArray.class]) for (id item in list) {
        if (![item isKindOfClass:NSString.class]) continue;
        NSString *url = DY778FansImageURL(item); if (url.length) return url;
    }
    return @"";
}
NSDictionary *DY778FansPerson(id object) {
    if (!object) return nil;
    id nested = DY778FansFirst(object, @[@"user", @"user_info", @"userInfo"]); if (nested) object = nested;
    if ([DY778FansString(DY778FansFirst(object,@[@"secUID",@"sec_uid",@"sec_user_id",@"secUserID",@"secUid"])) isEqual:@"111111"]) return nil;
    NSString *uid = @"", *sec = @"";
    for (NSString *key in @[@"uid", @"userID", @"id_str", @"idStr", @"id_p", @"id"]) {
        NSString *value = DY778FansString(DY778FansRead(object, key)); if (DY778FansUID(value)) { uid = value; break; }
    }
    for (NSString *key in @[@"secUID", @"sec_uid", @"sec_user_id", @"secUserID", @"secUid"]) {
        NSString *value = DY778FansString(DY778FansRead(object, key)); if (DY778FansSecUID(value)) { sec = value; break; }
    }
    if ((!uid.length && !sec.length) || [uid isEqual:@"111111"] || [sec isEqual:@"111111"] || [DY778FansRead(object,@"is_anonymous") boolValue]) return nil;
    NSString *handle = @"";
    for (NSString *key in @[@"handle", @"unique_id", @"uniqueIDForShow", @"uniqueID", @"display_id", @"customID", @"short_id", @"shortID", @"shortId"]) {
        NSString *value = DY778FansTrim(DY778FansString(DY778FansRead(object, key)));
        if (value.length && ![value isEqual:@"0"]) { handle = value; break; }
    }
    if (!handle.length) {
        NSString *display = DY778FansTrim(DY778FansString(DY778FansCall(object, @"uniqueIDForShow", @[])));
        if (display.length && ![display isEqual:@"0"]) handle = display;
    }
    NSString *avatar = DY778FansImageURL(DY778FansFirst(object, @[@"avatarURL", @"avatar_medium", @"avatarMedium", @"avatar_thumb", @"avatarThumb"]));
    NSString *room = DY778FansString(DY778FansFirst(object, @[@"roomID", @"room_id", @"roomId"]));
    if (!DY778FansUID(room)) {
        id details = DY778FansFirst(object, @[@"roomDict", @"room_data", @"roomData", @"roomDataInfo"]);
        if ([details isKindOfClass:NSString.class] && [details length] < 131072) details = [NSJSONSerialization JSONObjectWithData:[details dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        room = DY778FansString(DY778FansFirst(details, @[@"id_str", @"id", @"id_p", @"room_id", @"roomID"]));
    }
    NSMutableDictionary *person = [@{@"uid": uid, @"secUID": sec, @"name": DY778FansString(DY778FansFirst(object, @[@"name", @"nickname", @"nickName"])), @"handle": handle, @"avatarURL": avatar, @"roomID": DY778FansUID(room) ? room : @"0", @"signature": DY778FansString(DY778FansFirst(object,@[@"signature",@"bio"])), @"ipLocation": DY778FansString(DY778FansFirst(object,@[@"ip_location",@"ipLocation"]))} mutableCopy];
    NSDictionary *keys = @{@"followers":@[@"followers",@"follower_count",@"followerCount"], @"following":@[@"following",@"following_count",@"followingCount"], @"likes":@[@"likes",@"total_favorited",@"totalFavorited"], @"works":@[@"works",@"aweme_count",@"awemeCount"]};
    for (NSString *key in keys) { NSNumber *value = DY778FansInteger(DY778FansFirst(object,keys[key])); if (value) person[key] = value; }
    return person;
}
BOOL DY778FansHandleMatches(id object, NSString *handle) {
    if (!handle.length) return NO;
    NSDictionary *person = DY778FansPerson(object);
    if (!person) return NO;
    if ([DY778FansString(person[@"handle"]) caseInsensitiveCompare:handle] == NSOrderedSame) return YES;
    for (NSString *key in @[@"short_id", @"shortID", @"shortId", @"customID", @"unique_id", @"uniqueIDForShow", @"uniqueID"]) {
        NSString *value = DY778FansTrim(DY778FansString(DY778FansRead(object, key)));
        if (value.length && ![value isEqual:@"0"] && [value caseInsensitiveCompare:handle] == NSOrderedSame) return YES;
    }
    return NO;
}
static void DY778FansCollectSearchPeople(id value, NSMutableDictionary *people, NSUInteger depth, NSUInteger *budget) {
    if (!value || depth > 6 || !*budget) return;
    (*budget)--;
    if ([value isKindOfClass:NSArray.class]) {
        for (id item in value) { if (!*budget) break; DY778FansCollectSearchPeople(item, people, depth + 1, budget); }
        return;
    }
    NSDictionary *person = DY778FansPerson(value);
    if (person) {
        NSString *key = [person[@"uid"] length] ? person[@"uid"] : person[@"secUID"];
        if (key.length) people[key] = @{ @"person": person, @"raw": DY778FansFirst(value, @[@"userInfo", @"user_info", @"user"]) ?: value };
    }
    for (NSString *key in @[@"user_list", @"users", @"data", @"items", @"user_info", @"userInfo", @"user"]) {
        if (!*budget) break; DY778FansCollectSearchPeople(DY778FansRead(value, key), people, depth + 1, budget);
    }
}
NSArray<NSDictionary *> *DY778FansSearchPeople(id response) {
    NSMutableDictionary *people = [NSMutableDictionary dictionary]; NSUInteger budget = 800;
    DY778FansCollectSearchPeople(response, people, 0, &budget); return people.allValues;
}
BOOL DY778FansSamePerson(NSDictionary *expected, NSDictionary *actual) {
    if (!expected || !actual) return NO;
    if ([actual[@"uid"] isEqual:@"111111"] || [actual[@"secUID"] isEqual:@"111111"]) return NO;
    BOOL uid = DY778FansUID(expected[@"uid"]) && DY778FansUID(actual[@"uid"]);
    BOOL sec = DY778FansSecUID(expected[@"secUID"]) && DY778FansSecUID(actual[@"secUID"]);
    if (uid && ![expected[@"uid"] isEqual:actual[@"uid"]]) return NO;
    if (sec && ![expected[@"secUID"] isEqual:actual[@"secUID"]]) return NO;
    return uid || sec;
}
NSString *DY778FansPersonName(NSDictionary *person) {
    for (NSString *key in @[@"name", @"handle", @"uid", @"secUID"]) if (DY778FansString(person[key]).length) return person[key];
    return @"用户";
}
static NSDictionary *DY778FansClub(id raw) {
    if (!raw) return nil;
    NSNumber *level = DY778FansInteger(DY778FansRead(raw, @"level"));
    NSString *anchor = DY778FansString(DY778FansFirst(raw, @[@"anchor_id", @"anchorId", @"anchorID"]));
    NSString *name = DY778FansString(DY778FansFirst(raw, @[@"club_name", @"clubName"]));
    if ((!DY778FansUID(anchor) && !name.length) || (level && level.integerValue > 1000)) return nil;
    if ((!level || !level.integerValue) && !name.length) return nil;
    NSMutableDictionary *club = [@{@"anchorUID": DY778FansUID(anchor) ? anchor : @"", @"clubName": name, @"anchorName": @"", @"avatarURL": @""} mutableCopy];
    if (level) club[@"level"] = level;
    NSNumber *status = DY778FansInteger(DY778FansFirst(raw, @[@"user_fans_club_status", @"userFansClubStatus"]));
    if (status) club[@"status"] = status;
    return club;
}
@implementation DY778FansResult
+ (instancetype)fromUser:(id)user target:(NSDictionary *)target error:(NSError **)error {
    return [self fromUser:user target:target anchor:nil error:error];
}
+ (instancetype)fromUser:(id)user target:(NSDictionary *)target anchor:(NSDictionary *)anchor error:(NSError **)error {
    NSDictionary *identity = DY778FansPerson(user);
    if (!DY778FansSamePerson(target, identity)) { if (error) *error = DY778FansError(409, @"返回的用户与查询对象不一致，已忽略这次结果。"); return nil; }
    DY778FansResult *result = [self new];
    NSMutableDictionary *person = [target mutableCopy];
    for (NSString *key in identity) if (DY778FansString(identity[key]).length) person[key] = identity[key];
    result.person = person; result.anchor = anchor; result.date = NSDate.date;
    id grade = DY778FansFirst(user, @[@"pay_grade", @"payGrade"]);
    if (DY778FansRead(user, @"hasPayGrade") && ![DY778FansRead(user, @"hasPayGrade") boolValue]) grade = nil;
    NSNumber *level = DY778FansInteger(DY778FansRead(grade, @"level"));
    if (level && level.integerValue <= 1000) result.level = level;
    NSNumber *minimum = DY778FansInteger(DY778FansFirst(grade, @[@"this_grade_min_diamond", @"thisGradeMinDiamond"]));
    NSNumber *maximum = DY778FansInteger(DY778FansFirst(grade, @[@"this_grade_max_diamond", @"thisGradeMaxDiamond"]));
    if (result.level && minimum && maximum && maximum.longLongValue > minimum.longLongValue) { result.minimum = minimum; result.maximum = maximum; }
    id fans = DY778FansFirst(user, @[@"fans_club", @"fansClub"]);
    if (DY778FansRead(user, @"hasFansClub") && ![DY778FansRead(user, @"hasFansClub") boolValue]) fans = nil;
    NSMutableArray *rawClubs = [NSMutableArray array];
    BOOL currentPresent = !DY778FansRead(fans, @"hasData_p") || [DY778FansRead(fans, @"hasData_p") boolValue];
    id current = currentPresent ? ([fans isKindOfClass:NSDictionary.class] ? DY778FansRead(fans, @"data") : DY778FansRead(fans, @"data_p")) : nil;
    if (current) [rawClubs addObject:current];
    id preferred = DY778FansFirst(fans, @[@"prefer_data", @"preferData"]);
    if ([preferred isKindOfClass:NSDictionary.class]) [rawClubs addObjectsFromArray:[preferred allValues]];
    else if (DY778FansHas(preferred, @"enumerateKeysAndObjectsUsingBlock:", "v", "@")) {
        void (^each)(int32_t, id, BOOL *) = ^(int32_t key, id value, BOOL *stop) {
            if (value) [rawClubs addObject:value]; if (rawClubs.count >= 300) *stop = YES;
        };
        DY778FansCall(preferred, @"enumerateKeysAndObjectsUsingBlock:", @[each]);
    }
    NSMutableDictionary *clubs = [NSMutableDictionary dictionary];
    for (id raw in rawClubs) {
        NSDictionary *club = DY778FansClub(raw); if (!club) continue;
        if (raw == current && anchor && DY778FansUID(anchor[@"uid"]) && DY778FansUID(anchor[@"roomID"]) && ![club[@"anchorUID"] length] && [club[@"level"] integerValue] > 0) {
            NSMutableDictionary *contextual = [club mutableCopy]; contextual[@"anchorUID"] = anchor[@"uid"]; contextual[@"anchorName"] = DY778FansPersonName(anchor); contextual[@"avatarURL"] = anchor[@"avatarURL"] ?: @""; club = contextual;
        }
        NSString *key = [club[@"anchorUID"] length] ? club[@"anchorUID"] : [@"name:" stringByAppendingString:club[@"clubName"]];
        NSDictionary *old = clubs[key];
        if (!old || [club[@"level"] integerValue] > [old[@"level"] integerValue]) clubs[key] = club;
    }
    result.clubs = [clubs.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [@( [b[@"level"] integerValue]) compare:@([a[@"level"] integerValue])];
        return order == NSOrderedSame ? [a[@"clubName"] compare:b[@"clubName"]] : order;
    }];
    result.source = @"抖音直播服务";
    result.diagnostic = [NSString stringWithFormat:@"pay_grade=%@; fans_club=%@; current_badge=%@; preferred_map=%@; records=%lu; recognized=%lu", grade ? @"present" : @"absent", fans ? @"present" : @"absent", current ? @"present" : @"absent", preferred ? NSStringFromClass([preferred class]) : @"absent", (unsigned long)rawClubs.count, (unsigned long)result.clubs.count];
    NSNumber *badgeLevel = DY778FansInteger(DY778FansRead(current, @"level"));
    NSString *badgeName = DY778FansString(DY778FansFirst(current, @[@"club_name", @"clubName"]));
    NSString *badgeAnchor = DY778FansString(DY778FansFirst(current, @[@"anchor_id", @"anchorId", @"anchorID"]));
    NSNumber *badgeStatus = DY778FansInteger(DY778FansFirst(current, @[@"user_fans_club_status", @"userFansClubStatus"]));
    result.diagnostic = [result.diagnostic stringByAppendingFormat:@"; badge_type=%@; badge_level=%@; badge_name=%@; badge_anchor=%@; badge_status=%@; preferred_entries=%lu",
        current ? NSStringFromClass([current class]) : @"absent", badgeLevel ? badgeLevel.stringValue : @"absent",
        badgeName.length ? @"present" : @"empty", DY778FansUID(badgeAnchor) ? @"present" : @"empty", badgeStatus ? badgeStatus.stringValue : @"absent",
        (unsigned long)(rawClubs.count - (current ? 1 : 0))];
    result.notice = result.clubs.count ? @"已取得本次可查询的灯牌。" : @"暂未取得可确认的灯牌，不代表未加入。";
    return result;
}
+ (instancetype)fromProfileResponse:(id)response target:(NSDictionary *)target anchor:(NSDictionary *)anchor error:(NSError **)error {
    id data = DY778FansRead(response,@"data") ?: response;
    id raw = DY778FansFirst(data,@[@"user_data",@"userData",@"user"]);
    DY778FansResult *result = raw ? [self fromUser:raw target:target anchor:anchor error:nil] : nil;
    id profile = DY778FansFirst(data,@[@"user_profile",@"userProfile"]);
    id base = DY778FansFirst(profile,@[@"base_info",@"baseInfo"]) ?: profile;
    NSDictionary *identity = DY778FansPerson(base);
    if (DY778FansSamePerson(target,identity)) {
        NSMutableDictionary *combined = [identity mutableCopy];
        id fans = DY778FansFirst(profile,@[@"fans_club",@"fansClub"]); if (fans) combined[@"fans_club"] = fans;
        id grade = DY778FansFirst(profile,@[@"pay_grade",@"payGrade"]); if (grade) combined[@"pay_grade"] = grade;
        DY778FansResult *card = [self fromUser:combined target:target anchor:anchor error:nil];
        if (!result) result = card;
        else {
            if (!result.level && card.level) { result.level = card.level; result.minimum = card.minimum; result.maximum = card.maximum; }
            NSMutableDictionary *clubs = [NSMutableDictionary dictionary];
            for (NSDictionary *club in [result.clubs arrayByAddingObjectsFromArray:card.clubs ?: @[]]) {
                NSString *key = [club[@"anchorUID"] length] ? club[@"anchorUID"] : [@"name:" stringByAppendingString:club[@"clubName"]];
                clubs[key] = club;
            }
            result.clubs = clubs.allValues;
        }
    }
    if (!result && error) *error = DY778FansError(409,@"暂未取得对应用户的资料，请稍后重试。");
    return result;
}
- (NSString *)shareText {
    NSMutableArray *lines = [NSMutableArray arrayWithObjects:DY778FansPersonName(self.person), [@"UID：" stringByAppendingString:DY778FansString(self.person[@"uid"])], nil];
    if ([self.person[@"handle"] length]) [lines addObject:[@"抖音号：" stringByAppendingString:self.person[@"handle"]]];
    [lines addObject:self.level ? [NSString stringWithFormat:@"消费等级：Lv.%@", self.level] : @"消费等级：未返回"];
    if (self.minimum && self.maximum) [lines addObject:[NSString stringWithFormat:@"等级钻石区间：%@–%@（非实际消费金额）", self.minimum, self.maximum]];
    for (NSDictionary *club in self.clubs) {
        NSString *name = [club[@"anchorName"] length] ? club[@"anchorName"] : [club[@"clubName"] length] ? club[@"clubName"] : club[@"anchorUID"];
        [lines addObject:[NSString stringWithFormat:@"%@ · 灯牌 %@", name, club[@"level"] ? [@"Lv." stringByAppendingString:[club[@"level"] stringValue]] : @"未返回"]];
    }
    if (self.notice.length) [lines addObject:self.notice];

    NSDateFormatter *format = [NSDateFormatter new]; format.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    if (self.date) [lines addObject:[@"查询时间：" stringByAppendingString:[format stringFromDate:self.date]]];
    return [lines componentsJoinedByString:@"\n"];
}
@end
