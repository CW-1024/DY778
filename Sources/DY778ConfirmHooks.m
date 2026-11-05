#import "DY778ConfirmCore.h"

#import "DY778ConfirmPrompt.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <stdatomic.h>
#import <string.h>

typedef NS_ENUM(NSUInteger, DY778ConfirmShape) {
    DY778ConfirmShapeV, DY778ConfirmShapeO, DY778ConfirmShapeOO, DY778ConfirmShapeOOO, DY778ConfirmShapeOOOO, DY778ConfirmShapeOOOOO, DY778ConfirmShapeOOOOOOO,
    DY778ConfirmShapeB, DY778ConfirmShapeQ, DY778ConfirmShapeS, DY778ConfirmShapeP, DY778ConfirmShapeBO, DY778ConfirmShapeBOBO, DY778ConfirmShapeOOBO,
    DY778ConfirmShapeOBO, DY778ConfirmShapeOOQO, DY778ConfirmShapeOQQO, DY778ConfirmShapeF7, DY778ConfirmShapeF9, DY778ConfirmShapeF11,
    DY778ConfirmShapeOOOIOO, DY778ConfirmShapeOOOIBOO, DY778ConfirmShapeOOOIOOOO, DY778ConfirmShapeOOOOOIBOOO
};
typedef struct {
    const char *className;
    const char *selectorName;
    DY778ConfirmShape shape;
    DY778ConfirmActionType action;
    DY778ConfirmIntent intent;
    NSInteger subject;
    NSInteger completion;
} DY778ConfirmHook;

static const DY778ConfirmHook DY778ConfirmHooks[] = {
#define DY778Confirm_HOOK(cls, sel, shape, action, intent, subject, completion) \
    {cls, sel, DY778ConfirmShape##shape, DY778ConfirmAction##action, DY778ConfirmIntent##intent, subject, completion},
#include "DY778ConfirmHookList.h"
#undef DY778Confirm_HOOK
};

static const char *DY778ConfirmShapeTypes(DY778ConfirmShape shape) {
    switch (shape) {
        case DY778ConfirmShapeV: return "";
        case DY778ConfirmShapeO: return "@";
        case DY778ConfirmShapeOO: return "@@";
        case DY778ConfirmShapeOOO: return "@@@";
        case DY778ConfirmShapeOOOO: return "@@@@";
        case DY778ConfirmShapeOOOOO: return "@@@@@";
        case DY778ConfirmShapeOOOOOOO: return "@@@@@@@";
        case DY778ConfirmShapeB: return "B";
        case DY778ConfirmShapeQ: return "Q";
        case DY778ConfirmShapeS: return "q";
        case DY778ConfirmShapeP: return "P";
        case DY778ConfirmShapeBO: return "B@";
        case DY778ConfirmShapeBOBO: return "B@B@";
        case DY778ConfirmShapeOOBO: return "@@B@";
        case DY778ConfirmShapeOBO: return "@B@";
        case DY778ConfirmShapeOOQO: return "@@Q@";
        case DY778ConfirmShapeOQQO: return "@QQ@";
        case DY778ConfirmShapeF7: return "@@@@@@d";
        case DY778ConfirmShapeF9: return "@@@@@@dB@";
        case DY778ConfirmShapeF11: return "@@@@@@@dB@B";
        case DY778ConfirmShapeOOOIOO: return "@@@i@@";
        case DY778ConfirmShapeOOOIBOO: return "@@@iB@@";
        case DY778ConfirmShapeOOOIOOOO: return "@@@i@@@@";
        case DY778ConfirmShapeOOOOOIBOOO: return "@@@@@iB@@@";
    }
    return NULL;
}
static BOOL DY778ConfirmMatches(Method method, DY778ConfirmShape shape) {
    if (!method) return NO;
    const char *types = DY778ConfirmShapeTypes(shape);
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (!types || signature.methodReturnType[0] != 'v' || signature.numberOfArguments != strlen(types) + 2) return NO;
    for (NSUInteger i = 0; types[i]; i++) {
        const char *actual = [signature getArgumentTypeAtIndex:i + 2];
        if (types[i] == 'P') {
            if (strcmp(actual, @encode(CGPoint)) != 0) return NO;
        } else if (actual[0] != types[i]) return NO;
    }
    return YES;
}

static BOOL DY778ConfirmIsBlock(id object) {
    Class cls = NSClassFromString(@"NSBlock");
    return cls && [object isKindOfClass:cls];
}

static id DY778ConfirmBox(id object) {
    return DY778ConfirmIsBlock(object) ? [object copy] : object ?: NSNull.null;
}
static id DY778ConfirmArg(NSArray *arguments, NSInteger index) {
    if (index < 0 || index >= (NSInteger)arguments.count) return nil;
    return arguments[index] == NSNull.null ? nil : arguments[index];
}

struct DY778ConfirmBlockLayout {
    void *isa;
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    void *descriptor;
};
static NSMethodSignature *DY778ConfirmBlockSignature(id block) {
    if (!DY778ConfirmIsBlock(block)) return nil;
    struct DY778ConfirmBlockLayout *layout = (__bridge void *)block;
    if (!(layout->flags & (1 << 30))) return nil;
    uint8_t *descriptor = (uint8_t *)layout->descriptor + 2 * sizeof(unsigned long);
    if (layout->flags & (1 << 25)) descriptor += 2 * sizeof(void *);
    const char *signature = *(const char **)descriptor;
    return signature ? [NSMethodSignature signatureWithObjCTypes:signature] : nil;
}

static dispatch_block_t DY778ConfirmCancelHandler(id callback, const DY778ConfirmHook *hook, id subject) {
    NSMethodSignature *signature = DY778ConfirmBlockSignature(callback);
    if (!signature || signature.methodReturnType[0] != 'v') return nil;
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled
        userInfo:@{NSLocalizedDescriptionKey: @"已取消本次操作"}];
    if (signature.numberOfArguments == 3 && [signature getArgumentTypeAtIndex:2][0] == '@') {
        if ([signature getArgumentTypeAtIndex:1][0] == '@') {
            return ^{ ((void (^)(id, NSError *))callback)(nil, error); };
        }
        if ([signature getArgumentTypeAtIndex:1][0] == 'B') {
            return ^{ ((void (^)(BOOL, NSError *))callback)(NO, error); };
        }
        if (hook->action == DY778ConfirmActionFollow) {
            NSNumber *status = DY778ConfirmRead(subject, @"followStatus") ?: DY778ConfirmRead(DY778ConfirmRead(subject, @"followInfo"), @"followStatus");
            long long previous = [status isKindOfClass:NSNumber.class] ? status.longLongValue :
                (hook->intent == DY778ConfirmIntentRemove ? 1 : 0);
            switch ([signature getArgumentTypeAtIndex:1][0]) {
                case 'q': return ^{ ((void (^)(long long, NSError *))callback)(previous, error); };
                case 'Q': return ^{ ((void (^)(unsigned long long, NSError *))callback)((unsigned long long)previous, error); };
                case 'i': return ^{ ((void (^)(int, NSError *))callback)((int)previous, error); };
                case 'I': return ^{ ((void (^)(unsigned int, NSError *))callback)((unsigned int)previous, error); };
            }
        }
    }
    return nil;
}

static dispatch_block_t DY778ConfirmUnfollowOperation(const DY778ConfirmHook *hook, id owner, NSArray *arguments) {
    if (hook->action != DY778ConfirmActionFollow || hook->intent == DY778ConfirmIntentAdd) return nil;
    if (strcmp(hook->className, "AWEProfileFollowAreaFollowComponent") == 0 &&
        strcmp(hook->selectorName, "handleFollowEventWithHeaderContext:enterMethod:fromTopButton:completion:") == 0) {
        SEL selector = NSSelectorFromString(@"handleUnfollowEventWithHeaderContext:fromRemoveMate:completion:");
        if (!DY778ConfirmMatches(class_getInstanceMethod([owner class], selector), DY778ConfirmShapeOBO)) return nil;
        id context = DY778ConfirmArg(arguments, 0);
        id completion = DY778ConfirmArg(arguments, 3);
        return ^{
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(owner, selector, context, NO, completion);
        };
    }
    if (strcmp(hook->className, "AWEProfileFollowAreaFollowActionCoordinator") == 0 &&
        strcmp(hook->selectorName, "p_unfollowFromRemoveMate:completion:") == 0) {
        SEL selector = NSSelectorFromString(@"p_startUnfollowFromRemoveMate:completion:");
        if (!DY778ConfirmMatches(class_getInstanceMethod([owner class], selector), DY778ConfirmShapeBO)) return nil;
        BOOL fromRemoveMate = [DY778ConfirmArg(arguments, 0) boolValue];
        id completion = DY778ConfirmArg(arguments, 1);
        return ^{
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(owner, selector, fromRemoveMate, completion);
        };
    }
    if (strcmp(hook->className, "AWEProfileHeaderFollowAreaCell") == 0 &&
        strcmp(hook->selectorName, "relationBtnClicked:") == 0) {
        id relation = DY778ConfirmRead(owner, @"relationView");
        id machine = DY778ConfirmRead(relation, @"relationBtnStateMachine");
        id state = DY778ConfirmRead(machine, @"currentState");
        id context = DY778ConfirmRead(state, @"context");
        NSString *userID = DY778ConfirmRead(DY778ConfirmRead(DY778ConfirmRead(owner, @"context"), @"userModel"), @"userID");
        if (![userID isKindOfClass:NSString.class] || !userID.length ||
            ![userID isEqual:DY778ConfirmRead(DY778ConfirmRead(DY778ConfirmRead(context, @"followContext"), @"user"), @"userID")]) return nil;
        SEL unfollow = NSSelectorFromString(@"unfollowUser");
        SEL doubleCheck = NSSelectorFromString(@"setEnableDoubleCheckAlert:");
        if (!DY778ConfirmMatches(class_getInstanceMethod([state class], unfollow), DY778ConfirmShapeV) ||
            !DY778ConfirmMatches(class_getInstanceMethod([context class], doubleCheck), DY778ConfirmShapeB)) return nil;
        return ^{
            if (DY778ConfirmRead(owner, @"relationView") != relation || DY778ConfirmRead(machine, @"currentState") != state ||
                DY778ConfirmRead(state, @"context") != context ||
                ![userID isEqual:DY778ConfirmRead(DY778ConfirmRead(DY778ConfirmRead(context, @"followContext"), @"user"), @"userID")]) {
                [DY778ConfirmPrompt showStaleNotice];
                return;
            }
            BOOL originalDoubleCheck = [DY778ConfirmRead(context, @"enableDoubleCheckAlert") boolValue];
            ((void (*)(id, SEL, BOOL))objc_msgSend)(context, doubleCheck, NO);
            @try {
                ((void (*)(id, SEL))objc_msgSend)(state, unfollow);
            } @finally {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(context, doubleCheck, originalDoubleCheck);
            }
        };
    }
    if (strcmp(hook->className, "IESLiveUserCardStore") == 0 &&
        strcmp(hook->selectorName, "actionUnFollow:") == 0) {
        SEL selector = NSSelectorFromString(@"unfollowUser");
        if (!DY778ConfirmMatches(class_getInstanceMethod([owner class], selector), DY778ConfirmShapeV)) return nil;
        return ^{ ((void (*)(id, SEL))objc_msgSend)(owner, selector); };
    }
    if (strcmp(hook->className, "IESLiveUserCardFollowButton") == 0 &&
        strcmp(hook->selectorName, "cancelFollow") == 0) {
        id store = DY778ConfirmRead(owner, @"store");
        SEL selector = NSSelectorFromString(@"unfollowUser");
        if (!DY778ConfirmMatches(class_getInstanceMethod([store class], selector), DY778ConfirmShapeV)) return nil;
        return ^{
            if (DY778ConfirmRead(owner, @"store") != store) {
                [DY778ConfirmPrompt showStaleNotice];
                return;
            }
            ((void (*)(id, SEL))objc_msgSend)(store, selector);
        };
    }
    return nil;
}

static void DY778ConfirmGate(const DY778ConfirmHook *hook, id owner, NSArray *arguments, dispatch_block_t operation) {
    id subject = DY778ConfirmArg(arguments, hook->subject);
    if (!DY778ConfirmEnabled(hook->action)) {
        operation();
        return;
    }
    dispatch_block_t confirmedUnfollow = DY778ConfirmUnfollowOperation(hook, owner, arguments);
    if (DY778ConfirmIsReplaying(hook->action)) {
        DY778ConfirmGuard(hook->action, hook->intent, owner, subject, operation, nil, confirmedUnfollow);
        return;
    }
    id callback = hook->completion == -2 ? DY778ConfirmRead(subject, @"completionBlock") : DY778ConfirmArg(arguments, hook->completion);
    dispatch_block_t cancellation = callback ? DY778ConfirmCancelHandler(callback, hook, subject) : nil;
    if (callback && !cancellation) {
        NSLog(@"[DY778] Unsupported completion: %s %s", hook->className, hook->selectorName);
    }
    DY778ConfirmGuard(hook->action, hook->intent, owner, subject, operation, cancellation, confirmedUnfollow);
}

static IMP DY778ConfirmReplacement(const DY778ConfirmHook *hook, SEL selector, IMP original) {
#define ARG(n) DY778ConfirmArg(args, n)
#define GATE(...) DY778ConfirmGate(hook, owner, args, ^{ __VA_ARGS__; })
    switch (hook->shape) {
        case DY778ConfirmShapeV: return imp_implementationWithBlock(^(id owner) {
            NSArray *args = @[];
            GATE(((void (*)(id, SEL))original)(owner, selector));
        });
        case DY778ConfirmShapeO: return imp_implementationWithBlock(^(id owner, id a) {
            NSArray *args = @[DY778ConfirmBox(a)];
            GATE(((void (*)(id, SEL, id))original)(owner, selector, ARG(0)));
        });
        case DY778ConfirmShapeOO: return imp_implementationWithBlock(^(id owner, id a, id b) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b)];
            GATE(((void (*)(id, SEL, id, id))original)(owner, selector, ARG(0), ARG(1)));
        });
        case DY778ConfirmShapeOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c)];
            GATE(((void (*)(id, SEL, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2)));
        });
        case DY778ConfirmShapeOOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c), DY778ConfirmBox(d)];
            GATE(((void (*)(id, SEL, id, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3)));
        });
        case DY778ConfirmShapeOOOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c), DY778ConfirmBox(d), DY778ConfirmBox(e)];
            GATE(((void (*)(id, SEL, id, id, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4)));
        });
        case DY778ConfirmShapeOOOOOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e, id f, id g) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c), DY778ConfirmBox(d), DY778ConfirmBox(e), DY778ConfirmBox(f), DY778ConfirmBox(g)];
            GATE(((void (*)(id, SEL, id, id, id, id, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), ARG(6)));
        });
        case DY778ConfirmShapeOOOIOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, int secret, id e, id f) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c), @(secret), DY778ConfirmBox(e), DY778ConfirmBox(f)];
            GATE(((void (*)(id, SEL, id, id, id, int, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), secret, ARG(4), ARG(5)));
        });
        case DY778ConfirmShapeOOOIBOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, int secret, BOOL fifa, id f, id g) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c), @(secret), @(fifa), DY778ConfirmBox(f), DY778ConfirmBox(g)];
            GATE(((void (*)(id, SEL, id, id, id, int, BOOL, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), secret, fifa, ARG(5), ARG(6)));
        });
        case DY778ConfirmShapeOOOIOOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, int secret, id e, id f, id g, id h) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c), @(secret), DY778ConfirmBox(e), DY778ConfirmBox(f), DY778ConfirmBox(g), DY778ConfirmBox(h)];
            GATE(((void (*)(id, SEL, id, id, id, int, id, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), secret, ARG(4), ARG(5), ARG(6), ARG(7)));
        });
        case DY778ConfirmShapeOOOOOIBOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e, int secret, BOOL fifa, id h, id i, id j) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c), DY778ConfirmBox(d), DY778ConfirmBox(e), @(secret), @(fifa), DY778ConfirmBox(h), DY778ConfirmBox(i), DY778ConfirmBox(j)];
            GATE(((void (*)(id, SEL, id, id, id, id, id, int, BOOL, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), secret, fifa, ARG(7), ARG(8), ARG(9)));
        });
        case DY778ConfirmShapeB: return imp_implementationWithBlock(^(id owner, BOOL a) {
            NSArray *args = @[@(a)];
            GATE(((void (*)(id, SEL, BOOL))original)(owner, selector, a));
        });
        case DY778ConfirmShapeQ: return imp_implementationWithBlock(^(id owner, unsigned long long a) {
            NSArray *args = @[@(a)];
            GATE(((void (*)(id, SEL, unsigned long long))original)(owner, selector, a));
        });
        case DY778ConfirmShapeS: return imp_implementationWithBlock(^(id owner, long long a) {
            NSArray *args = @[@(a)];
            GATE(((void (*)(id, SEL, long long))original)(owner, selector, a));
        });
        case DY778ConfirmShapeP: return imp_implementationWithBlock(^(id owner, CGPoint a) {
            NSArray *args = @[];
            GATE(((void (*)(id, SEL, CGPoint))original)(owner, selector, a));
        });
        case DY778ConfirmShapeBO: return imp_implementationWithBlock(^(id owner, BOOL a, id b) {
            NSArray *args = @[@(a), DY778ConfirmBox(b)];
            GATE(((void (*)(id, SEL, BOOL, id))original)(owner, selector, a, ARG(1)));
        });
        case DY778ConfirmShapeBOBO: return imp_implementationWithBlock(^(id owner, BOOL a, id b, BOOL c, id d) {
            NSArray *args = @[@(a), DY778ConfirmBox(b), @(c), DY778ConfirmBox(d)];
            GATE(((void (*)(id, SEL, BOOL, id, BOOL, id))original)(owner, selector, a, ARG(1), c, ARG(3)));
        });
        case DY778ConfirmShapeOOBO: return imp_implementationWithBlock(^(id owner, id a, id b, BOOL c, id d) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), @(c), DY778ConfirmBox(d)];
            GATE(((void (*)(id, SEL, id, id, BOOL, id))original)(owner, selector, ARG(0), ARG(1), c, ARG(3)));
        });
        case DY778ConfirmShapeOBO: return imp_implementationWithBlock(^(id owner, id a, BOOL b, id c) {
            NSArray *args = @[DY778ConfirmBox(a), @(b), DY778ConfirmBox(c)];
            GATE(((void (*)(id, SEL, id, BOOL, id))original)(owner, selector, ARG(0), b, ARG(2)));
        });
        case DY778ConfirmShapeOOQO: return imp_implementationWithBlock(^(id owner, id a, id b, unsigned long long c, id d) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), @(c), DY778ConfirmBox(d)];
            GATE(((void (*)(id, SEL, id, id, unsigned long long, id))original)(owner, selector, ARG(0), ARG(1), c, ARG(3)));
        });
        case DY778ConfirmShapeOQQO: return imp_implementationWithBlock(^(id owner, id a, unsigned long long b, unsigned long long c, id d) {
            NSArray *args = @[DY778ConfirmBox(a), @(b), @(c), DY778ConfirmBox(d)];
            GATE(((void (*)(id, SEL, id, unsigned long long, unsigned long long, id))original)(owner, selector, ARG(0), b, c, ARG(3)));
        });
        case DY778ConfirmShapeF7: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e, id f, double padding) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c), DY778ConfirmBox(d), DY778ConfirmBox(e), DY778ConfirmBox(f), @(padding)];
            GATE(((void (*)(id, SEL, id, id, id, id, id, id, double))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), padding));
        });
        case DY778ConfirmShapeF9: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e, id f, double padding, BOOL force, id view) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c), DY778ConfirmBox(d), DY778ConfirmBox(e), DY778ConfirmBox(f), @(padding), @(force), DY778ConfirmBox(view)];
            GATE(((void (*)(id, SEL, id, id, id, id, id, id, double, BOOL, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), padding, force, ARG(8)));
        });
        case DY778ConfirmShapeF11: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e, id f, id g, double padding, BOOL force, id view, BOOL block) {
            NSArray *args = @[DY778ConfirmBox(a), DY778ConfirmBox(b), DY778ConfirmBox(c), DY778ConfirmBox(d), DY778ConfirmBox(e), DY778ConfirmBox(f), DY778ConfirmBox(g), @(padding), @(force), DY778ConfirmBox(view), @(block)];
            GATE(((void (*)(id, SEL, id, id, id, id, id, id, id, double, BOOL, id, BOOL))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), ARG(6), padding, force, ARG(9), block));
        });
    }
#undef GATE
#undef ARG
    return NULL;
}

static BOOL DY778ConfirmFeedAction(id button, DY778ConfirmActionType *action) {
    for (NSString *key in @[@"accessibilityLabel", @"accessibilityIdentifier", @"imageNameString"]) {
        id text = DY778ConfirmRead(button, key);
        if (![text isKindOfClass:NSString.class]) continue;
        NSString *lower = [text lowercaseString];
        if ([text containsString:@"收藏"] || [lower containsString:@"favorite"] || [lower containsString:@"collect"]) {
            *action = DY778ConfirmActionFavorite; return YES;
        }
        if ([text containsString:@"点赞"] || [lower containsString:@"digg"] || [lower containsString:@"icon_like"]) {
            *action = DY778ConfirmActionLike; return YES;
        }
    }
    return NO;
}

static void DY778ConfirmInstallFeedButtonHook(void) {
    static BOOL installed[2];
    NSArray *classes = @[@"AWEFeedVideoButton", @"AWEFeedRelatedVideoCardInteractionButton"];
    for (NSUInteger index = 0; index < classes.count; index++) {
        if (installed[index]) continue;
        Class cls = NSClassFromString(classes[index]);
        SEL selector = NSSelectorFromString(@"touchUpInsideBlock");
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) continue;
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.methodReturnType[0] != '@' || signature.numberOfArguments != 2) continue;
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^id(id owner) {
            id callback = ((id (*)(id, SEL))original)(owner, selector);
            NSMethodSignature *blockSignature = DY778ConfirmBlockSignature(callback);
            if (!blockSignature || blockSignature.methodReturnType[0] != 'v' || blockSignature.numberOfArguments != 1) return callback;
            dispatch_block_t block = [callback copy];
            __weak id weakOwner = owner;
            return [^{
                id button = weakOwner;
                if (!button) return;
                DY778ConfirmActionType action;
                if (!DY778ConfirmFeedAction(button, &action) || !DY778ConfirmEnabled(action)) { block(); return; }
                DY778ConfirmGuard(action, DY778ConfirmIntentToggle, button, nil, ^{
                    if (((id (*)(id, SEL))original)(button, selector) != block) {
                        [DY778ConfirmPrompt showStaleNotice];
                        return;
                    }
                    block();
                }, nil, nil);
            } copy];
        });
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
        installed[index] = YES;
    }
}

void DY778InstallConfirmationHooks(void) {
    static BOOL installed[sizeof(DY778ConfirmHooks) / sizeof(DY778ConfirmHooks[0])];
    NSUInteger added = 0;
    for (NSUInteger i = 0; i < sizeof(DY778ConfirmHooks) / sizeof(DY778ConfirmHooks[0]); i++) {
        if (installed[i]) continue;
        const DY778ConfirmHook *hook = &DY778ConfirmHooks[i];
        Class cls = NSClassFromString(@(hook->className));
        if (!cls) continue;
        BOOL isClassMethod = hook->selectorName[0] == '+';
        if (isClassMethod) cls = object_getClass(cls);
        SEL selector = sel_registerName(hook->selectorName + (isClassMethod ? 1 : 0));
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) continue;
        if (!DY778ConfirmMatches(method, hook->shape)) {
            installed[i] = YES;
            NSLog(@"[DY778] Signature mismatch: %s %s", hook->className, hook->selectorName);
            continue;
        }
        IMP replacement = DY778ConfirmReplacement(hook, selector, method_getImplementation(method));
        if (!replacement) continue;
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
        installed[i] = YES;
        added++;
    }
    DY778ConfirmInstallFeedButtonHook();
    if (added) NSLog(@"[DY778] Installed %lu action hooks", (unsigned long)added);
}
