#import "DY778EditContent.h"
#import "DY778EditPolicy.h"
#import "DY778RecallContent.h"

NSString *DY778EditableText(id content) {
    if (![content isKindOfClass:NSDictionary.class]) return @"";
    for (NSString *key in @[@"text", @"text_content", @"rich_text", @"content"]) {
        id value = content[key];
        if (![value isKindOfClass:NSString.class] || ![value length] || [value isEqual:@"Recall Content Hided"]) continue;
        if ([value hasPrefix:@"{"] || [value hasPrefix:@"["]) {
            id decoded = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if ([decoded isKindOfClass:NSDictionary.class] && decoded != content) {
                id text = decoded[@"text"] ?: decoded[@"text_content"];
                if ([text isKindOfClass:NSString.class]) return text;
            }
            continue;
        }
        return value;
    }
    return @"";
}
NSDictionary *DY778MergeEditRecord(NSDictionary *previous, NSDictionary *event) {
    NSDictionary *body = event[@"content"];
    BOOL available = [body isKindOfClass:NSDictionary.class] && body.count && ![body[@"text"] isEqual:@"Recall Content Hided"] && !DY778RecallContentIsNotice(body);
    NSDictionary *last = [previous[@"versions"] lastObject];
    NSString *text = DY778EditableText(body), *oldText = DY778EditableText(last[@"content"]);
    BOOL same = text.length && oldText.length ? [text isEqual:oldText] : [body isEqual:last[@"content"]];
    DY778EditDecision decision = DY778DecideEdit(available && ![event[@"recalled"] boolValue], previous != nil,
        [event[@"edited"] boolValue], same, [previous[@"revisionTime"] doubleValue], [event[@"editTime"] doubleValue],
        [previous[@"revisionCount"] longLongValue], [event[@"editCount"] longLongValue]);
    if (decision == DY778EditIgnore && !previous) return nil;
    NSMutableDictionary *result = previous ? [previous mutableCopy] : [NSMutableDictionary dictionary];
    for (NSString *key in @[@"key", @"account", @"conversation", @"messageID", @"serverID", @"sender", @"createdAt", @"senderName", @"senderAvatar", @"conversationName", @"group"])
        if (event[key] && (![event[key] isKindOfClass:NSString.class] || [event[key] length])) {
            if ([key isEqual:@"createdAt"] && ([result[key] doubleValue] > 0 || [event[key] doubleValue] <= 0)) continue;
            result[key] = event[key];
        }
    if (decision == DY778EditIgnore) return [result isEqual:previous] ? previous : result;
    BOOL firstEdited = decision == DY778EditFirstSeenEdited;
    if (!previous) { result[@"firstObservedAt"] = event[@"observedAt"] ?: @0; result[@"originalMissing"] = @(firstEdited); }
    double editTime = [event[@"editTime"] doubleValue];
    NSMutableArray *versions = [previous[@"versions"] mutableCopy] ?: [NSMutableArray array];
    BOOL edited = decision != DY778EditBaseline;
    NSDictionary *version = @{@"content": body, @"text": text, @"summary": DY778RecallSummary(@{@"content": body, @"available": @YES}),
        @"edited": @(edited), @"editTime": @(edited ? editTime : 0), @"observedAt": event[@"observedAt"] ?: @0,
        @"editor": event[@"editor"] ?: @"", @"serverCount": event[@"editCount"] ?: @0};
    [versions addObject:version]; result[@"versions"] = versions;
    result[@"revisionTime"] = @(editTime); result[@"revisionCount"] = event[@"editCount"] ?: @0;
    result[@"changes"] = @([previous[@"changes"] unsignedIntegerValue] + (edited ? 1 : 0));
    result[@"lastEditAt"] = edited ? @(editTime > 0 ? editTime : [event[@"observedAt"] doubleValue]) : @0;
    result[@"summary"] = version[@"summary"];
    return result;
}
