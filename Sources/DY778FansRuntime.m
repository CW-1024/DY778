#import "DY778FansRuntime.h"
#import "DY778FansPolicy.h"
#import <string.h>
#import <CoreFoundation/CoreFoundation.h>

NSString * const DY778FansName = @"星牌查询";
NSString * const DY778FansVersion = @"1.0-3";
NSString * const DY778FansPreferencesChanged = @"DY778Fans.PreferencesChanged";

id DY778FansRead(id object, NSString *key) {
    if (!object || object == NSNull.null) return nil;
    @try {
        id value;
        if ([object isKindOfClass:NSDictionary.class]) value = object[key];
        else if ([object respondsToSelector:NSSelectorFromString(key)]) value = [object valueForKey:key];
        return value == NSNull.null ? nil : value;
    } @catch (__unused NSException *exception) { return nil; }
}
id DY778FansFirst(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) { id value = DY778FansRead(object, key); if (value) return value; }
    return nil;
}
BOOL DY778FansSet(id object, NSString *key, id value) {
    if (!object) return NO;
    @try { [object setValue:value forKey:key]; return YES; }
    @catch (__unused NSException *exception) { return NO; }
}
BOOL DY778FansHas(id object, NSString *selector, const char *returns, const char *arguments) {
    NSMethodSignature *signature = [object methodSignatureForSelector:NSSelectorFromString(selector)];
    if (!signature || signature.numberOfArguments != strlen(arguments) + 2 || !strchr(returns, signature.methodReturnType[0])) return NO;
    for (NSUInteger i = 0; arguments[i]; i++) if ([signature getArgumentTypeAtIndex:i + 2][0] != arguments[i]) return NO;
    return YES;
}
// 按宿主的方法签名传递对象与标量。
id DY778FansCall(id object, NSString *selector, NSArray *arguments) {
    SEL sel = NSSelectorFromString(selector);
    if (![object respondsToSelector:sel]) return nil;
    NSMethodSignature *signature = [object methodSignatureForSelector:sel];
    if (!signature || signature.numberOfArguments != arguments.count + 2) return nil;
    @try {
        NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature]; call.target = object; call.selector = sel;
        for (NSUInteger i = 0; i < arguments.count; i++) {
            id value = arguments[i] == NSNull.null ? nil : arguments[i];
            switch ([signature getArgumentTypeAtIndex:i + 2][0]) {
                case '@': case '#': { id v = value; [call setArgument:&v atIndex:i + 2]; break; }
                case 'B': case 'c': { BOOL v = [value boolValue]; [call setArgument:&v atIndex:i + 2]; break; }
                case 'q': { long long v = [value longLongValue]; [call setArgument:&v atIndex:i + 2]; break; }
                case 'Q': { unsigned long long v = [value unsignedLongLongValue]; [call setArgument:&v atIndex:i + 2]; break; }
                case 'i': { int v = [value intValue]; [call setArgument:&v atIndex:i + 2]; break; }
                case 'I': { unsigned int v = [value unsignedIntValue]; [call setArgument:&v atIndex:i + 2]; break; }
                case 'd': { double v = [value doubleValue]; [call setArgument:&v atIndex:i + 2]; break; }
                default: return nil;
            }
        }
        [call retainArguments]; [call invoke];
        switch (signature.methodReturnType[0]) {
            case '@': case '#': { __unsafe_unretained id v = nil; [call getReturnValue:&v]; return v; }
            case 'B': case 'c': { BOOL v = NO; [call getReturnValue:&v]; return @(v); }
            case 'q': { long long v = 0; [call getReturnValue:&v]; return @(v); }
            case 'Q': { unsigned long long v = 0; [call getReturnValue:&v]; return @(v); }
            case 'i': { int v = 0; [call getReturnValue:&v]; return @(v); }
            case 'I': { unsigned int v = 0; [call getReturnValue:&v]; return @(v); }
            default: return nil;
        }
    } @catch (__unused NSException *exception) { return nil; }
}
NSString *DY778FansString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) return [value stringValue];
    return @"";
}
NSNumber *DY778FansInteger(id value) {
    NSString *text = DY778FansString(value); uint64_t number = 0;
    if (!DY778FansParseUnsigned(text.UTF8String, [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding], INT64_MAX, &number)) return nil;
    return @((long long)number);
}
BOOL DY778FansUID(NSString *text) {
    return [text isKindOfClass:NSString.class] && DY778FansASCIIUID(text.UTF8String, [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}
BOOL DY778FansSecUID(NSString *text) {
    return [text isKindOfClass:NSString.class] && DY778FansASCIISECUid(text.UTF8String, [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}
BOOL DY778FansEnabled(NSString *key) { return DY778Bool(@"fans.enabled"); }
NSError *DY778FansError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"DY778Fans" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"暂时无法查询"}];
}
NSString *DY778FansAccount(void) {
    return DY778CurrentAccountID() ?: @"";
}
