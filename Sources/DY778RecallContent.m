#import "DY778RecallContent.h"
#import "DY778ArchivePolicy.h"
#import <objc/runtime.h>
#import "DY778ArchiveStorage.h"
#import <objc/message.h>
#import <math.h>

static BOOL DY778HostIdentifiesRecallNotice(id type) {
    if ([type longLongValue] != 40001) return NO;
    static NSSet *systemTypes; static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"AWEIMMessage"); SEL selector = NSSelectorFromString(@"notUserGeneratedMessageTypes"); Method method = class_getClassMethod(cls, selector); char returned[8] = {0};
        if (method) method_getReturnType(method, returned, sizeof(returned));
        if (!method || method_getNumberOfArguments(method) != 2 || returned[0] != '@') return;
        @try {
            id values = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
            if ([values isKindOfClass:NSSet.class]) systemTypes = [values copy];
            else if ([values isKindOfClass:NSArray.class]) systemTypes = [NSSet setWithArray:values];
        } @catch (__unused NSException *exception) { }
    });
    return [systemTypes containsObject:@40001] || [systemTypes containsObject:@"40001"];
}

static NSString *DY778ContentString(id value) {
    return [value isKindOfClass:NSString.class] ? value : ([value isKindOfClass:NSNumber.class] ? [value stringValue] : @"");
}
static NSString *DY778MediaIdentity(NSDictionary *media) {
    for (NSString *key in @[@"remoteURL", @"cachedPath", @"sourcePath"]) {
        NSString *value = DY778ContentString(media[key]); if (value.length) return value;
    }
    return @"";
}
static BOOL DY778ContainsAny(NSString *text, NSArray *words) {
    for (NSString *word in words) if ([text containsString:word]) return YES;
    return NO;
}
static NSString *DY778ValueForKeys(NSDictionary *node, NSArray *keys) {
    for (NSString *key in keys) { NSString *value = DY778ContentString(node[key]); if (value.length && ![value isEqual:@"Recall Content Hided"]) return value; }
    return @"";
}
static id DY778UnpackContent(id node) {
    if (![node isKindOfClass:NSString.class] || [node length] > 1024 * 1024) return node;
    NSString *text = [node stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![text hasPrefix:@"{"] && ![text hasPrefix:@"["]) return node;
    id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    return [parsed isKindOfClass:NSDictionary.class] || [parsed isKindOfClass:NSArray.class] ? parsed : node;
}
NSString *DY778RecallMessageKind(NSString *className) {
    if (![className isKindOfClass:NSString.class] || ![className hasPrefix:@"AWEIM"]) return @"";
    if ([className containsString:@"AudioMessage"]) return @"audio";
    if ([className containsString:@"ImageMessage"]) return @"image";
    if ([className containsString:@"VideoMessage"] && ![className containsString:@"Share"] && ![className containsString:@"Feed"]) return @"video";
    if ([className isEqual:@"AWEIMShareLocationMessage"]) return @"location";
    return @"";
}
static BOOL DY778HasContentValue(NSDictionary *node, NSArray *keys) {
    for (NSString *key in keys) {
        id value = node[key];
        if ([value isKindOfClass:NSString.class] && [value length]) return YES;
        if (([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) && [value count]) return YES;
    }
    return NO;
}
static NSString *DY778NodeKind(NSDictionary *node, NSString *inherited) {
    if (DY778ValueForKeys(node, @[@"recall_user_id", @"recallUserID", @"recalled_message_id", @"recall_message_id", @"custom_recall_text", @"customRecallText"]).length) return @"recall-notice";
    if ([@[@"image", @"audio", @"video", @"location"] containsObject:inherited]) return inherited;
    if (DY778ValueForKeys(node, @[@"room_id", @"roomId", @"roomID", @"room_owner_id"]).length) return @"live";
    if (DY778ValueForKeys(node, @[@"product_id", @"productId", @"promotion_id", @"promotionId", @"chatGoodsSchema"]).length) return @"goods";
    if (DY778ValueForKeys(node, @[@"sticker_type", @"stickerType", @"sticker_id", @"stickerID", @"giphy_name", @"giphyName", @"emoji_type", @"emojiType", @"animate_url", @"animateURL"]).length || node[@"giphy_url"] || node[@"giphyURL"]) return @"sticker";
    if (DY778HasContentValue(node, @[@"res_origin_url_list", @"resOriginUrlList", @"res_thumb_url_list", @"resThumbUrlList", @"res_medium_url_list", @"resMediumUrlList", @"res_large_url_list", @"resLargeUrlList", @"res_long_url_list", @"resLongUrlList", @"res_still_url_list", @"resStillUrlList"])) return @"image";
    BOOL resource = DY778HasContentValue(node, @[@"resource_url", @"resourceUrl"]);
    NSString *contentType = DY778ValueForKeys(node, @[@"content_type", @"contentType"]).lowercaseString;
    BOOL dimensions = (node[@"cover_width"] || node[@"coverWidth"]) && (node[@"cover_height"] || node[@"coverHeight"]);
    if ([contentType hasPrefix:@"audio/"] || [@[@"audio", @"voice"] containsObject:contentType] ||
        (resource && (node[@"average_power_arr"] || node[@"averagePowerArr"] || (node[@"duration"] && !dimensions)))) return @"audio";
    if (resource && dimensions) return @"image";
    NSString *workID = DY778ValueForKeys(node, @[@"aweme_id", @"awemeID", @"itemId", @"item_id"]);
    if (workID.length && ![workID isEqual:@"0"]) return @"work";
    id latitude = node[@"latitude"], longitude = node[@"longitude"] ?: node[@"lng"];
    if ([latitude respondsToSelector:@selector(doubleValue)] && [longitude respondsToSelector:@selector(doubleValue)]) {
        double lat = [latitude doubleValue], lon = [longitude doubleValue];
        BOOL described = DY778HasContentValue(node, @[@"cover_resource_url", @"coverResourceUrl", @"poi_name", @"poiName", @"poi_address", @"poiAddress"]);
        if (described && isfinite(lat) && isfinite(lon) && fabs(lat) <= 90 && fabs(lon) <= 180) return @"location";
    }
    return inherited ?: @"";
}
static NSString *DY778KindForURL(NSString *path, NSString *context, NSURL *url) {
    NSString *all = [NSString stringWithFormat:@"%@ %@", path.lowercaseString, url.pathExtension.lowercaseString];
    if (DY778ContainsAny(all, @[@"avatar", @"portrait"])) return nil;
    if (DY778ContainsAny(all, @[@"cover", @"thumb", @"display_icon", @"displayicon", @"static_url", @"staticurl"])) return @"image";
    if ([@[@"image", @"audio", @"video"] containsObject:context] && DY778ContainsAny(path.lowercaseString, @[@"resource", @"res_", @"resorigin", @"resmedium", @"reslarge", @"reslong", @"resstill"])) return context;
    if (DY778ContainsAny(all, @[@"audio", @"voice", @"mp3", @"m4a", @"aac", @"wav", @"amr", @"opus"])) return @"audio";
    if (DY778ContainsAny(all, @[@"video", @"play_addr", @"playurl", @"play_url", @"mp4", @"mov", @"m3u8"])) return @"video";
    if (DY778ContainsAny(all, @[@"image", @"photo", @"giphy", @"sticker", @"emoji", @"animate", @"jpg", @"jpeg", @"png", @"gif", @"webp", @"heic"])) return @"image";
    if (DY778ContainsAny(all, @[@"file_url", @"fileurl", @"download_url"])) return @"file";
    if ([@[@"sticker", @"goods", @"live"] containsObject:context]) return @"image";
    return nil;
}
static BOOL DY778UnrelatedMediaPath(NSString *path) {
    return DY778ContainsAny(path.lowercaseString, @[@".author", @".user", @".avatar", @".portrait", @".music", @".quote", @".reply", @".refer", @".comment", @".emoji_icon", @".blur", @".gaussian"]);
}
static NSInteger DY778MediaQuality(NSString *path) {
    NSString *p = path.lowercaseString;
    if (DY778ContainsAny(p, @[@"origin", @"original", @"large", @"high_quality"])) return 600;
    if (DY778ContainsAny(p, @[@"thumb", @"small", @"preview"])) return 100;
    if (DY778ContainsAny(p, @[@"dynamic", @"animate"])) return 200;
    if (DY778ContainsAny(p, @[@"cover", @"poster"])) return 500;
    if (DY778ContainsAny(p, @[@"image", @"photo"])) return 400;
    return 300;
}
static void DY778WalkContent(id raw, NSString *path, NSString *inherited, NSMutableDictionary *presentation,
                           NSMutableArray *media, NSMutableSet *seen, NSUInteger depth, NSUInteger *budget) {
    if (depth > 22 || !*budget || DY778UnrelatedMediaPath(path)) return; (*budget)--;
    id node = DY778UnpackContent(raw);
    if ([node isKindOfClass:NSDictionary.class]) {
        NSString *kind = DY778NodeKind(node, inherited);
        NSDictionary *authorNode = [node[@"author"] isKindOfClass:NSDictionary.class] ? node[@"author"] : nil;
        NSString *authorName = DY778ValueForKeys(authorNode, @[@"nickname", @"name"]);
        if (authorName.length && ![presentation[@"author"] length]) presentation[@"author"] = authorName;
        if (kind.length && (![presentation[@"kind"] length] || [kind isEqual:@"recall-notice"])) presentation[@"kind"] = kind;
        if ([@[@"image", @"audio", @"video"] containsObject:kind] && DY778ValueForKeys(node, @[@"res_secret_key", @"resSecretKey", @"skey", @"tkey"]).length) presentation[@"encrypted"] = @YES;
        if ([kind isEqual:@"audio"]) {
            NSString *transcript = DY778ValueForKeys(node, @[@"audio_text", @"audioText"]);
            if (transcript.length && ![presentation[@"transcript"] length]) presentation[@"transcript"] = transcript;
        }
        NSString *title = DY778ValueForKeys(node, @[@"display_name", @"displayName", @"giphy_name", @"giphyName", @"contentTitle", @"content_title", @"awemeTitle", @"room_description", @"roomDescription", @"title", @"title_text", @"contentName", @"name"]);
        NSString *text = DY778ValueForKeys(node, @[@"text", @"text_content", @"description", @"desc", @"display_content", @"hint_content", @"hintContent"]);
        if (title.length && ![presentation[@"title"] length]) presentation[@"title"] = title;
        if (text.length && ![presentation[@"text"] length] && !DY778ContainsAny(path.lowercaseString, @[@"user", @"author", @"quote", @"reply"])) presentation[@"text"] = text;
        NSString *author = DY778ValueForKeys(node, @[@"room_owner_name", @"roomOwnerName", @"author_name", @"authorName"]);
        if (author.length && ![presentation[@"author"] length]) presentation[@"author"] = author;
        NSString *price = DY778ValueForKeys(node, @[@"price_desc", @"priceDesc", @"display_price", @"price_text"]);
        if (price.length) presentation[@"detail"] = price;
        NSString *identifier = DY778ValueForKeys(node, [kind isEqual:@"work"] ? @[@"aweme_id", @"awemeID", @"itemId", @"item_id"] : ([kind isEqual:@"live"] ? @[@"room_id", @"roomId", @"roomID"] : @[]));
        if (identifier.length && ![presentation[@"id"] length]) presentation[@"id"] = identifier;
        NSString *recallTarget = DY778ValueForKeys(node, @[@"recall_message_id", @"recalled_message_id", @"recalledMessageID", @"recalled_msg_id", @"recall_server_message_id"]);
        if (!recallTarget.length && [kind isEqual:@"recall-notice"]) recallTarget = DY778ValueForKeys(node, @[@"message_id", @"messageID", @"server_message_id"]);
        if (recallTarget.length) presentation[@"recallTargetID"] = recallTarget;
        // 动态表情优先，保持媒体顺序稳定。
        NSArray *keys = [[node allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            BOOL aa = [a isKindOfClass:NSString.class] && [[a lowercaseString] containsString:@"animate"];
            BOOL ba = [b isKindOfClass:NSString.class] && [[b lowercaseString] containsString:@"animate"];
            return aa != ba ? (aa ? NSOrderedAscending : NSOrderedDescending) : [[a description] compare:[b description]];
        }];
        for (id key in keys) if ([key isKindOfClass:NSString.class]) DY778WalkContent(node[key], [path stringByAppendingFormat:@".%@", key], kind, presentation, media, seen, depth + 1, budget);
    } else if ([node isKindOfClass:NSArray.class]) {
        for (id item in node) DY778WalkContent(item, path, inherited, presentation, media, seen, depth + 1, budget);
    } else if ([node isKindOfClass:NSString.class] && media.count < 32) {
        NSURL *url = [NSURL URLWithString:node];
        if (![@[@"http", @"https"] containsObject:url.scheme.lowercaseString] || !url.host.length || [seen containsObject:node]) return;
        NSString *lower = path.lowercaseString;
        if (!DY778ContainsAny(lower, @[@"url", @"play_addr", @"src", @"cover", @"image", @"icon"])) return;
        NSString *kind = DY778KindForURL(path, inherited, url); if (!kind.length) return;
        [seen addObject:node];
        BOOL cover = DY778ContainsAny(lower, @[@"cover", @"thumb", @"static", @"displayicon", @"display_icon"]);
        NSString *name = [inherited isEqual:@"sticker"] ? (cover ? @"表情预览" : @"表情") : (cover ? @"封面" : @{@"image": @"图片", @"audio": @"语音", @"video": @"视频", @"file": @"文件"}[kind]);
        NSMutableDictionary *item = [@{@"kind": kind, @"name": name ?: @"附件", @"remoteURL": node, @"cover": @(cover), @"role": cover ? @"cover" : kind, @"quality": @(DY778MediaQuality(path)), @"field": path} mutableCopy];
        if ([presentation[@"encrypted"] boolValue]) item[@"encrypted"] = @YES;
        if ([@[@"work", @"live", @"goods"] containsObject:inherited]) item[@"shared"] = @YES;
        if ([inherited isEqual:@"sticker"]) item[@"sticker"] = @YES;
        [media addObject:item];
    }
}
static NSDictionary *DY778ExtractPresentationForKind(id content, NSString *kind) {
    NSMutableDictionary *presentation = [NSMutableDictionary dictionary]; NSMutableArray *media = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set]; NSUInteger budget = 4096;
    if (kind.length) presentation[@"kind"] = kind;
    DY778WalkContent(content, @"content", kind ?: @"", presentation, media, seen, 0, &budget);
    if (media.count) presentation[@"media"] = media;
    return presentation;
}
static NSDictionary *DY778ExtractPresentation(id content) { return DY778ExtractPresentationForKind(content, @""); }
NSArray *DY778RecallMediaFromContent(id content) { return DY778ExtractPresentation(content)[@"media"] ?: @[]; }
BOOL DY778RecallContentIsNotice(id content) { return [DY778ExtractPresentation(content)[@"kind"] isEqual:@"recall-notice"]; }
// 仅解析消息正文中的评论，排除引用消息。
static NSDictionary *DY778CommentInContent(id raw, NSUInteger depth, BOOL commentObject) {
    if (depth > 6) return nil;
    id node = DY778UnpackContent(raw); if (![node isKindOfClass:NSDictionary.class]) return nil;
    NSString *identifier = DY778ValueForKeys(node, @[@"commentID", @"comment_id", @"cid"]);
    NSString *text = DY778ValueForKeys(node, @[@"comment", @"comment_text", @"commentText"]);
    if (!text.length && commentObject) text = DY778ValueForKeys(node, @[@"text"]);
    BOOL transcript = NO;
    if (!text.length && (identifier.length || commentObject)) {
        text = DY778ValueForKeys(node, @[@"audioText", @"audio_text"]); transcript = text.length > 0;
    }
    if (text.length) return @{@"text": text, @"id": identifier,
        @"author": DY778ValueForKeys(node, @[@"commentUserName", @"comment_user_name"]),
        @"authorID": DY778ValueForKeys(node, @[@"commentSecUid", @"comment_sec_uid"]), @"transcript": @(transcript)};
    for (NSString *field in @[@"comment", @"comment_info", @"commentInfo", @"content", @"data"]) {
        NSDictionary *found = DY778CommentInContent(node[field], depth + 1, [field hasPrefix:@"comment"]);
        if (found) return found;
    }
    return nil;
}
NSDictionary *DY778RecallCommentFromContent(id content) { return DY778CommentInContent(content, 0, NO); }
NSDictionary *DY778MergeCapturedComment(NSDictionary *previous, NSDictionary *candidate) {
    if (![previous isKindOfClass:NSDictionary.class]) previous = nil;
    if (![candidate isKindOfClass:NSDictionary.class]) candidate = nil;
    NSString *savedText = [previous[@"text"] isKindOfClass:NSString.class] ? previous[@"text"] : @"";
    NSString *newText = [candidate[@"text"] isKindOfClass:NSString.class] ? candidate[@"text"] : @"";
    if (!savedText.length) return newText.length ? [candidate copy] : nil;
    // 后续删除提示不能覆盖首次评论。
    NSMutableDictionary *result = [previous mutableCopy];
    if ([DY778ContentString(previous[@"id"]) length] && [DY778ContentString(candidate[@"id"]) length] && ![previous[@"id"] isEqual:candidate[@"id"]]) return previous;
    for (NSString *key in @[@"author", @"id", @"authorID"]) {
        if (!DY778ContentString(result[key]).length && [candidate[key] isKindOfClass:NSString.class] && [candidate[key] length]) result[key] = candidate[key];
    }
    return [result copy];
}
NSDictionary *DY778RecallEnrichRecord(NSDictionary *record) {
    if (![record isKindOfClass:NSDictionary.class]) return @{};
    if ([record[@"presentationVersion"] integerValue] == 8) return record;
    NSMutableDictionary *result = [record mutableCopy];
    NSDictionary *comment = DY778MergeCapturedComment(record[@"comment"], DY778RecallCommentFromContent(record[@"content"]));
    if (comment) result[@"comment"] = comment;
    NSString *declaredKind = DY778RecallMessageKind(record[@"presentationClass"]);
    NSMutableDictionary *presentation = [DY778ExtractPresentationForKind(record[@"content"], declaredKind) mutableCopy];
    NSDictionary *native = [record[@"card"] isKindOfClass:NSDictionary.class] ? record[@"card"] : @{};
    for (NSString *key in native) {
        if ([key isEqual:@"kind"] && (declaredKind.length || [native[key] isEqual:@"location"])) continue;
        if ([DY778ContentString(native[key]) length]) presentation[key] = native[key];
    }
    NSMutableArray *media = [NSMutableArray array]; NSMutableSet *seen = [NSMutableSet set];
    for (NSArray *items in @[presentation[@"media"] ?: @[], record[@"media"] ?: @[]]) for (NSDictionary * __strong item in items) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        if ([item[@"cachedPath"] isKindOfClass:NSString.class] || [item[@"sourcePath"] isKindOfClass:NSString.class]) {
            NSMutableDictionary *relocated = [item mutableCopy];
            for (NSString *key in @[@"cachedPath", @"sourcePath"]) if ([item[key] isKindOfClass:NSString.class]) relocated[key] = DY778ArchiveMediaPath(item[key]);
            item = relocated;
        }
        NSString *identity = DY778MediaIdentity(item);
        if (DY778UnrelatedMediaPath(DY778ContentString(item[@"field"]))) continue;
        if (identity.length && [seen containsObject:identity]) {
            NSUInteger index = [media indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger i, BOOL *stop) { return [DY778MediaIdentity(candidate) isEqual:identity]; }];
            if (index != NSNotFound) {
                NSMutableDictionary *merged = [media[index] mutableCopy];
                for (NSString *key in item) if (!merged[key] || [key isEqual:@"cachedPath"] || [key isEqual:@"sourcePath"] ||
                    ([key isEqual:@"encrypted"] && [item[key] boolValue]) ||
                    ([item[@"native"] boolValue] && [@[@"kind", @"name", @"field"] containsObject:key]) ||
                    ([key isEqual:@"quality"] && [item[key] integerValue] > [merged[key] integerValue])) merged[key] = item[key];
                media[index] = merged;
            }
            continue;
        }
        if (identity.length) [seen addObject:identity]; [media addObject:item];
    }
    [presentation removeObjectForKey:@"media"];
    BOOL direct = [@[@"image", @"audio", @"video"] containsObject:presentation[@"kind"]];
    BOOL encrypted = [presentation[@"encrypted"] boolValue] || (declaredKind.length && [DY778ContentString(record[@"presentationClass"]) containsString:@"Encrypt"]);
    if (direct) for (NSUInteger i = 0; i < media.count; i++) {
        NSMutableDictionary *item = [media[i] mutableCopy];
        if ([item[@"kind"] isEqual:@"file"]) item[@"kind"] = presentation[@"kind"];
        if (encrypted && [item[@"remoteURL"] length]) item[@"encrypted"] = @YES;
        media[i] = item;
    }
    if ([record[@"share"] count] && ![presentation[@"kind"] length]) presentation[@"kind"] = @"work";
    if (![presentation[@"kind"] length]) {
        for (NSDictionary *item in media) if ([@[@"image", @"audio", @"video"] containsObject:item[@"kind"]] && ![item[@"cover"] boolValue] && ![item[@"shared"] boolValue]) { presentation[@"kind"] = item[@"kind"]; break; }
    }
    if ([@[@"image", @"audio", @"video", @"location"] containsObject:presentation[@"kind"]]) [result removeObjectForKey:@"share"];
    if ([presentation[@"kind"] isEqual:@"work"]) {
        NSMutableDictionary *share = [record[@"share"] isKindOfClass:NSDictionary.class] ? [record[@"share"] mutableCopy] : [NSMutableDictionary dictionary];
        for (NSString *field in @[@"id", @"title", @"author"]) if (![DY778ContentString(share[field]) length] && [DY778ContentString(presentation[field]) length]) share[field] = presentation[field];
        if (share.count) result[@"share"] = share;
    }
    if ([presentation[@"kind"] isEqual:@"recall-notice"] || [record[@"systemRecallNotice"] boolValue] ||
        ([record[@"type"] longLongValue] == 60001 && [record[@"presentationClass"] isEqual:@"AWEIMRecallMessage"]) || DY778HostIdentifiesRecallNotice(record[@"type"])) {
        presentation[@"kind"] = @"recall-notice";
        result[@"systemRecallNotice"] = @YES;
        result[@"available"] = @NO;
        if ([presentation[@"recallTargetID"] length]) result[@"recallTargetID"] = presentation[@"recallTargetID"];
    }
    result[@"card"] = presentation; result[@"media"] = media; result[@"presentationVersion"] = @8;
    return result;
}
NSString *DY778RecallWorkIdentifier(NSDictionary *record) {
    record = DY778RecallEnrichRecord(record);
    if ([record[@"systemRecallNotice"] boolValue]) return @"";
    NSDictionary *share = [record[@"share"] isKindOfClass:NSDictionary.class] ? record[@"share"] : @{};
    NSString *identifier = DY778ContentString(share[@"id"]);
    if (!identifier.length && [record[@"card"][@"kind"] isEqual:@"work"]) identifier = DY778ContentString(record[@"card"][@"id"]);
    if (!identifier.length || identifier.length > 40 || [identifier isEqual:@"0"]) return @"";
    for (NSUInteger i = 0; i < identifier.length; i++) { unichar c = [identifier characterAtIndex:i]; if (c < '0' || c > '9') return @""; }
    return identifier;
}
NSString *DY778RecallSummary(NSDictionary *record) {
    record = DY778RecallEnrichRecord(record);
    NSString *comment = DY778ContentString(record[@"comment"][@"text"]);
    NSString *sharedTitle = DY778ContentString(record[@"share"][@"title"]);
    if (comment.length) return [NSString stringWithFormat:@"评论：%@%@", comment, sharedTitle.length ? [@"\n分享作品：" stringByAppendingString:sharedTitle] : @""];
    if (sharedTitle.length) return [@"分享作品 · " stringByAppendingString:sharedTitle];
    NSDictionary *card = record[@"card"]; NSString *kind = card[@"kind"], *title = card[@"title"], *text = card[@"text"];
    if ([kind isEqual:@"recall-notice"]) return @"撤回提示 · 原始消息请查看对应记录";
    NSString *mediaLabel = @{@"image": @"图片消息", @"audio": @"语音消息", @"video": @"视频消息"}[kind ?: @""];
    if (mediaLabel) return [card[@"transcript"] length] ? [NSString stringWithFormat:@"%@\n转写：%@", mediaLabel, card[@"transcript"]] : mediaLabel;
    NSString *label = @{@"sticker": @"表情", @"work": @"分享作品", @"goods": @"商品", @"live": @"直播", @"location": @"位置"}[kind ?: @""];
    if (label) { NSString *detail = title.length ? title : text; return detail.length ? [NSString stringWithFormat:@"%@ · %@", label, detail] : label; }
    if (text.length) return text; if (title.length) return title;
    NSDictionary *content = [record[@"content"] isKindOfClass:NSDictionary.class] ? record[@"content"] : @{};
    NSString *plain = DY778ValueForKeys(content, @[@"text", @"content", @"title", @"display_content"]);
    if (plain.length && ![plain hasPrefix:@"{"]) return plain;
    NSDictionary *media = [record[@"media"] firstObject];
    NSString *name = @{@"image": @"图片消息", @"audio": @"语音消息", @"video": @"视频消息", @"file": @"文件消息"}[media[@"kind"] ?: @""];
    return name ?: ([record[@"available"] boolValue] ? @"未识别的消息" : @"未取得撤回前的内容");
}

BOOL DY778RecallRecordShouldHide(NSDictionary *record) {
    record = DY778RecallEnrichRecord(record);
    if ([record[@"systemRecallNotice"] boolValue]) return YES;
    if ([record[@"media"] count] || DY778RecallWorkIdentifier(record).length) return NO;
    NSString *summary = DY778RecallSummary(record);
    return [summary isEqual:@"未识别的消息"] || [summary isEqual:@"未取得撤回前的内容"];
}
NSArray *DY778RecallPreviewCandidates(NSDictionary *record) {
    record = DY778RecallEnrichRecord(record);
    NSMutableArray *images = [NSMutableArray array];
    BOOL work = DY778RecallWorkIdentifier(record).length > 0 || [record[@"card"][@"kind"] isEqual:@"work"];
    for (NSDictionary *item in record[@"media"]) {
        if (![item[@"kind"] isEqual:@"image"] || DY778UnrelatedMediaPath(DY778ContentString(item[@"field"]))) continue;
        // Legacy unclassified images must not displace a positively identified cover.
        if (work && [item[@"sticker"] boolValue]) continue;
        [images addObject:item];
    }
    [images sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger qa = [a[@"quality"] integerValue], qb = [b[@"quality"] integerValue];
        if (!qa) qa = [a[@"cover"] boolValue] || [DY778ContentString(a[@"name"]) containsString:@"封面"] ? 500 : 50;
        if (!qb) qb = [b[@"cover"] boolValue] || [DY778ContentString(b[@"name"]) containsString:@"封面"] ? 500 : 50;
        return qa == qb ? NSOrderedSame : (qa > qb ? NSOrderedAscending : NSOrderedDescending);
    }];
    return images;
}
NSDictionary *DY778RecallPrimaryMedia(NSDictionary *record) {
    record = DY778RecallEnrichRecord(record);
    NSString *kind = record[@"card"][@"kind"];
    BOOL direct = [@[@"image", @"audio", @"video"] containsObject:kind ?: @""];
    NSDictionary *selected = nil; NSInteger best = NSIntegerMin;
    for (NSDictionary *item in record[@"media"]) {
        if (!DY778ArchiveMediaSelectable(kind.UTF8String, [DY778ContentString(item[@"kind"]) UTF8String],
            direct, [item[@"cover"] boolValue], [item[@"shared"] boolValue])) continue;
        BOOL local = NO;
        for (NSString *key in @[@"sourcePath", @"cachedPath"]) {
            NSString *path = [item[key] isKindOfClass:NSString.class] ? item[key] : nil;
            if (path.length && [NSFileManager.defaultManager isReadableFileAtPath:path]) local = YES;
        }
        NSInteger score = (local ? 100000 : 0) + (![item[@"encrypted"] boolValue] ? 10000 : 0) + [item[@"quality"] integerValue];
        if (!selected || score > best) { selected = item; best = score; }
    }
    return selected;
}
