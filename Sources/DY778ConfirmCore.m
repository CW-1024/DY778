#import "DY778ConfirmCore.h"
#import "DY778ConfirmPrompt.h"
#import "DY778CommentBridge.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString *const DY778ConfirmLikeEnabledKey = @"confirm.like";
NSString *const DY778ConfirmFavoriteEnabledKey = @"confirm.favorite";
NSString *const DY778ConfirmFollowEnabledKey = @"confirm.follow";
NSString *const DY778ConfirmCommentLikeEnabledKey = @"confirm.commentLike";
NSString *const DY778ConfirmCommentDislikeEnabledKey = @"confirm.commentDislike";
NSNotificationName const DY778ConfirmThemeDidChangeNotification = @"DY778ConfirmThemeDidChange";

static __thread NSUInteger DY778ConfirmReplayDepth[DY778ConfirmActionCount];
static __thread DY778ConfirmIntent DY778ConfirmReplayIntent[DY778ConfirmActionCount];

void DY778ConfirmEnsureDefaults(void) {
    [DY778Preferences() registerDefaults:@{
        DY778ConfirmLikeEnabledKey: @NO, DY778ConfirmFavoriteEnabledKey: @NO, DY778ConfirmFollowEnabledKey: @NO,
        DY778ConfirmCommentLikeEnabledKey: @NO, DY778ConfirmCommentDislikeEnabledKey: @NO
    }];
}

BOOL DY778ConfirmEnabled(DY778ConfirmActionType action) {
    NSString *key;
    switch (action) {
        case DY778ConfirmActionLike: key = DY778ConfirmLikeEnabledKey; break;
        case DY778ConfirmActionFavorite: key = DY778ConfirmFavoriteEnabledKey; break;
        case DY778ConfirmActionFollow: key = DY778ConfirmFollowEnabledKey; break;
        case DY778ConfirmActionCommentLike: key = DY778ConfirmCommentLikeEnabledKey; break;
        case DY778ConfirmActionCommentDislike: key = DY778ConfirmCommentDislikeEnabledKey; break;
        default: return NO;
    }
    return [DY778Preferences() boolForKey:key];
}

BOOL DY778ConfirmIsReplaying(DY778ConfirmActionType action) {
    return action < DY778ConfirmActionCount && DY778ConfirmReplayDepth[action] > 0;
}

id DY778ConfirmRead(id object, NSString *key) {
    if (!object || ![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

UIWindow *DY778ConfirmActiveWindow(void) { return DY778ActiveWindow(); }
UIColor *DY778ConfirmAccent(DY778ConfirmActionType action) { return DY778Accent(); }
UIUserInterfaceStyle DY778ConfirmUserInterfaceStyle(void) { return DY778InterfaceStyle(); }
static NSString *DY778ConfirmString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}

static BOOL DY778ConfirmIsCommentAction(DY778ConfirmActionType action) {
    return action == DY778ConfirmActionCommentLike || action == DY778ConfirmActionCommentDislike;
}

static UIView *DY778ConfirmSourceView(id owner) {
    if ([owner isKindOfClass:UIView.class]) return owner;
    id view = DY778ConfirmRead(owner, @"view");
    if ([view isKindOfClass:UIView.class]) return view;
    for (NSUInteger i = 0; owner && i < 16; i++) {
        view = DY778ConfirmRead(DY778ConfirmRead(owner, @"rl_cachedVirtualView"), @"renderedView");
        if ([view isKindOfClass:UIView.class]) return view;
        view = DY778ConfirmRead(DY778ConfirmRead(owner, @"delegate"), @"mountedView");
        if ([view isKindOfClass:UIView.class]) return view;
        owner = DY778ConfirmRead(owner, @"rl_superComponent");
    }
    return nil;
}

static id DY778ConfirmFindModel(id root, DY778ConfirmActionType action, NSUInteger depth, NSHashTable *visited) {
    if (!root || depth > 4 || [visited containsObject:root]) return nil;
    [visited addObject:root];
    if (action == DY778ConfirmActionFollow) {
        Class profileCell = NSClassFromString(@"AWEProfileHeaderFollowAreaCell");
        if (profileCell && [root isKindOfClass:profileCell]) {
            id context = DY778ConfirmRead(root, @"context");
            return DY778ConfirmRead(context, @"userModel") ?: DY778ConfirmRead(DY778ConfirmRead(root, @"relationView"), @"userModel") ?: context;
        }
        id userModel = DY778ConfirmRead(root, @"userModel");
        if (userModel && (DY778ConfirmRead(userModel, @"userID") || DY778ConfirmRead(userModel, @"userId") ||
                          DY778ConfirmRead(userModel, @"secUserID") || DY778ConfirmRead(userModel, @"uid"))) {
            return userModel;
        }
        if (DY778ConfirmRead(root, @"userID") || DY778ConfirmRead(root, @"userIDStr") || DY778ConfirmRead(root, @"userId") ||
            DY778ConfirmRead(root, @"secUserID") || DY778ConfirmRead(root, @"secUserId") || DY778ConfirmRead(root, @"uid")) return root;
    } else if (DY778ConfirmIsCommentAction(action)) {
        if (DY778ConfirmRead(root, @"commentID")) return root;
    } else if (DY778ConfirmRead(root, @"userDigged") || DY778ConfirmRead(root, @"userFavorited") || DY778ConfirmRead(root, @"isCollected") ||
               DY778ConfirmRead(root, @"commentID") || DY778ConfirmRead(root, @"roomID")) {
        return root;
    }
    NSArray *keys = action == DY778ConfirmActionFollow ?
        @[@"userModel", @"followContext", @"headerContext", @"context", @"relationView",
          @"currentOwner", @"currentUser", @"user", @"userProfile", @"viewModel", @"store",
          @"realShowAuthor", @"author", @"owner", @"model", @"aweme", @"awemeModel", @"room", @"data"] :
        DY778ConfirmIsCommentAction(action) ?
        @[@"commentModel", @"comment", @"detailModel", @"model", @"viewModel", @"cellModel", @"data", @"context"] :
        @[@"aweme", @"awemeModel", @"model", @"viewModel", @"interactor", @"context",
          @"cellModel", @"room", @"store", @"data", @"comment"];
    for (NSString *key in keys) {
        id model = DY778ConfirmFindModel(DY778ConfirmRead(root, key), action, depth + 1, visited);
        if (model) return model;
    }
    return nil;
}

static id DY778ConfirmModel(id root, DY778ConfirmActionType action) {
    id bound = DY778ConfirmIsCommentAction(action) ? DY778CommentBoundModel(root) : nil;
    if (bound) return bound;
    id model = DY778ConfirmFindModel(root, action, 0, [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality]);
    if (model) return model;
    if (DY778ConfirmIsCommentAction(action)) {
        id component = root;
        for (NSUInteger i = 0; component && i < 16; i++) {
            UIView *view = DY778ConfirmSourceView(component);
            for (NSUInteger j = 0; view && j < 24; j++, view = view.superview) {
                model = DY778ConfirmFindModel(view, action, 0, [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality]);
                if (model) return model;
                if ([view isKindOfClass:UITableViewCell.class] || [view isKindOfClass:UICollectionViewCell.class]) break;
            }
            component = DY778ConfirmRead(component, @"rl_superComponent");
        }
    }
    UIResponder *responder = DY778ConfirmIsCommentAction(action) ? DY778ConfirmSourceView(root) : nil;
    if (!responder && [root isKindOfClass:UIResponder.class]) responder = [root nextResponder];
    for (NSUInteger i = 0; responder && i < 24; i++, responder = responder.nextResponder) {
        model = DY778ConfirmFindModel(responder, action, 0, [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality]);
        if (model) return model;
    }
    return nil;
}

static NSString *DY778ConfirmIdentity(id model) {
    for (NSString *key in @[@"commentID", @"userID", @"userIDStr", @"userId", @"secUserID", @"secUserId", @"uid", @"itemID", @"roomID", @"aid"]) {
        NSString *value = DY778ConfirmString(DY778ConfirmRead(model, key));
        if (value.length) return [key stringByAppendingFormat:@":%@", value];
    }
    if ([model isKindOfClass:NSString.class] || [model isKindOfClass:NSNumber.class]) return DY778ConfirmString(model);
    return model ? [NSString stringWithFormat:@"%p", model] : nil;
}

static NSNumber *DY778ConfirmFollowState(long long status) {
    switch (status) {
        case 0: return @NO;
        case 1: case 2: case 4: return @YES;
        default: return nil;
    }
}

static NSNumber *DY778ConfirmState(id model, DY778ConfirmActionType action) {
    if (action == DY778ConfirmActionFollow) {
        id shouldFollow = DY778ConfirmRead(model, @"shouldFollowWhenTappedFollowButton");
        if ([shouldFollow isKindOfClass:NSNumber.class]) return @(![shouldFollow boolValue]);
        id following = DY778ConfirmRead(model, @"following");
        if ([following isKindOfClass:NSNumber.class]) return @([following boolValue]);
        id followInfo = DY778ConfirmRead(model, @"followInfo");
        id status = DY778ConfirmRead(model, @"followStatus") ?: DY778ConfirmRead(followInfo, @"followStatus");
        if ([status isKindOfClass:NSNumber.class]) {
            return DY778ConfirmFollowState([status longLongValue]);
        }
        return nil;
    }
    NSArray *keys = action == DY778ConfirmActionCommentDislike ? @[@"userBuried"] :
                    action == DY778ConfirmActionCommentLike ? @[@"userDigged", @"isLiked", @"isDigged", @"liked"] :
                    action == DY778ConfirmActionLike ? @[@"userDigged", @"isLiked"] :
                    @[@"userFavorited", @"isCollected", @"collectStatus", @"isFavorite"];
    for (NSString *key in keys) {
        id value = DY778ConfirmRead(model, key);
        if ([value isKindOfClass:NSNumber.class]) return value;
    }
    return nil;
}

static NSNumber *DY778ConfirmActionState(id owner, id model, DY778ConfirmActionType action) {
    if (action == DY778ConfirmActionFollow) {
        Class component = NSClassFromString(@"AWEProfileFollowAreaFollowComponent");
        id context = DY778ConfirmRead(owner, @"headerContext");
        SEL effectiveStatus = NSSelectorFromString(@"effectiveFollowStatusWithHeaderContext:");
        Method method = class_getClassMethod(component, effectiveStatus);
        if (context && method && [owner isKindOfClass:component]) {
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if (signature.numberOfArguments == 3 && signature.methodReturnType[0] == 'q' &&
                [signature getArgumentTypeAtIndex:2][0] == '@') {
                NSNumber *state = DY778ConfirmFollowState(((long long (*)(id, SEL, id))objc_msgSend)(component, effectiveStatus, context));
                if (state) return state;
            }
        }
        NSNumber *visibleState = DY778ConfirmState(DY778ConfirmRead(owner, @"relationView"), action);
        if (visibleState) return visibleState;
        return DY778ConfirmState(model, action) ?: DY778ConfirmState(owner, action);
    }
    return DY778ConfirmState(model, action) ?: DY778ConfirmState(owner, action);
}

static BOOL DY778ConfirmEqual(id a, id b) { return a == b || [a isEqual:b]; }

@interface DY778ConfirmRequestTicket : NSObject
@property(nonatomic) DY778ConfirmActionType action;
@property(nonatomic) DY778ConfirmIntent intent;
@property(nonatomic) NSTimeInterval deadline;
@property(nonatomic) BOOL consumed;
@property(nonatomic, copy) NSString *identity;
@end
@implementation DY778ConfirmRequestTicket
@end

static char DY778ConfirmTicketKey;
static void DY778ConfirmMarkRequest(id request, id owner, DY778ConfirmActionType action, DY778ConfirmIntent intent, BOOL replace) {
    if (!request) return;
    NSString *cls = NSStringFromClass([request class]);
    if (![@[@"AWEInteractionDiggConfig", @"AWEInteractionToggleFavoriteAwemeConfig", @"AWEUserRelationContext", @"IESLiveUserFollowModel"] containsObject:cls]) return;
    if (!replace && objc_getAssociatedObject(request, &DY778ConfirmTicketKey)) return;
    NSString *identity = DY778ConfirmIdentity(DY778ConfirmModel(request, action) ?: DY778ConfirmModel(owner, action));
    if (!identity) return;
    DY778ConfirmRequestTicket *ticket = [DY778ConfirmRequestTicket new];
    ticket.action = action;
    ticket.intent = intent;
    ticket.deadline = NSProcessInfo.processInfo.systemUptime + 30;
    ticket.identity = identity;
    objc_setAssociatedObject(request, &DY778ConfirmTicketKey, ticket, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DY778ConfirmRunApproved(DY778ConfirmActionType action, DY778ConfirmIntent intent,
                               dispatch_block_t operation, dispatch_block_t confirmedUnfollow) {
    BOOL unfollow = action == DY778ConfirmActionFollow && intent == DY778ConfirmIntentRemove;
    DY778ConfirmIntent previousIntent = DY778ConfirmReplayIntent[action];
    DY778ConfirmReplayDepth[action]++;
    DY778ConfirmReplayIntent[action] = intent;
    @try {
        if (unfollow && confirmedUnfollow) confirmedUnfollow();
        else operation();
    } @finally {
        DY778ConfirmReplayIntent[action] = previousIntent;
        DY778ConfirmReplayDepth[action]--;
    }
}

void DY778ConfirmGuard(DY778ConfirmActionType action, DY778ConfirmIntent intent, id owner, id subject,
                 dispatch_block_t operation, dispatch_block_t cancellation, dispatch_block_t confirmedUnfollow) {
    if (!operation) return;
    if (!DY778ConfirmEnabled(action)) {
        operation();
        return;
    }
    if (DY778ConfirmIsReplaying(action)) {
        DY778ConfirmIntent approvedIntent = intent == DY778ConfirmIntentToggle ? DY778ConfirmReplayIntent[action] : intent;
        DY778ConfirmMarkRequest(subject, owner, action, approvedIntent, NO);
        operation();
        return;
    }
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DY778ConfirmGuard(action, intent, owner, subject, operation, cancellation, confirmedUnfollow);
        });
        return;
    }
    DY778ConfirmRequestTicket *ticket = subject ? objc_getAssociatedObject(subject, &DY778ConfirmTicketKey) : nil;
    if (ticket && !ticket.consumed && ticket.action == action &&
        (action != DY778ConfirmActionFollow || ticket.intent == intent || intent == DY778ConfirmIntentToggle) &&
        ticket.deadline >= NSProcessInfo.processInfo.systemUptime &&
        DY778ConfirmEqual(ticket.identity, DY778ConfirmIdentity(DY778ConfirmModel(subject, action) ?: DY778ConfirmModel(owner, action)))) {
        ticket.consumed = YES;
        DY778ConfirmRunApproved(action, ticket.intent, operation, confirmedUnfollow);
        return;
    }
    id root = subject ?: owner;
    BOOL scalarSubject = [subject isKindOfClass:NSString.class] || [subject isKindOfClass:NSNumber.class];
    id model = scalarSubject ? subject : DY778ConfirmModel(root, action) ?: DY778ConfirmModel(owner, action);
    NSString *identity = DY778ConfirmIdentity(model);
    NSString *ownerIdentity = DY778ConfirmIdentity(DY778ConfirmModel(owner, action));
    NSNumber *state = DY778ConfirmActionState(owner, model, action);
    BOOL commentAction = DY778ConfirmIsCommentAction(action);
    if (commentAction && (!identity.length || (intent == DY778ConfirmIntentToggle && !state))) {
        if (cancellation) cancellation();
        DY778RecordHook(@"评论赞踩状态", NO);
        NSLog(@"[DY778] Comment binding unavailable: %@ (identity=%d, state=%d)", NSStringFromClass([owner class]), identity.length > 0, state != nil);
        DY778Toast(@"暂未读取到评论状态，请稍后重试");
        return;
    }
    if (commentAction) DY778RecordHook(@"评论赞踩状态", YES);
    id binding = commentAction ? DY778CommentBindingToken(owner) : nil;
    NSNumber *bindingVisible = binding ? DY778CommentBindingVisible(owner) : nil;
    NSString *account = DY778CurrentAccountID();
    DY778ConfirmActionType oppositeAction = action == DY778ConfirmActionCommentLike ? DY778ConfirmActionCommentDislike : DY778ConfirmActionCommentLike;
    NSNumber *oppositeState = commentAction ? DY778ConfirmState(model, oppositeAction) : nil;
    UIView *sourceView = DY778ConfirmSourceView(owner);
    UIWindow *sourceWindow = sourceView.window;
    DY778ConfirmIntent effectiveIntent = intent;
    if (intent == DY778ConfirmIntentToggle && state) {
        effectiveIntent = state.boolValue ? DY778ConfirmIntentRemove : DY778ConfirmIntentAdd;
    }
    NSString *name = action == DY778ConfirmActionFollow ?
        DY778ConfirmString(DY778ConfirmRead(model, @"nickname") ?: DY778ConfirmRead(model, @"nickName")) : nil;
    BOOL isComment = commentAction || DY778ConfirmRead(model, @"commentID") != nil;
    [DY778ConfirmPrompt presentForAction:action intent:effectiveIntent name:name isComment:isComment
                         decision:^(BOOL confirmed) {
        if (!confirmed) {
            if (cancellation) cancellation();
            return;
        }
        id current = scalarSubject ? subject : DY778ConfirmModel(root, action) ?: DY778ConfirmModel(owner, action);
        BOOL valid = UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
                     DY778ConfirmEqual(account, DY778CurrentAccountID()) &&
                     (!binding || DY778CommentBindingToken(owner) == binding) &&
                     (!bindingVisible.boolValue || [DY778CommentBindingVisible(owner) boolValue]) &&
                     DY778ConfirmEqual(identity, DY778ConfirmIdentity(current)) &&
                     DY778ConfirmEqual(ownerIdentity, DY778ConfirmIdentity(DY778ConfirmModel(owner, action))) &&
                     DY778ConfirmEqual(state, DY778ConfirmActionState(owner, current, action)) &&
                     (!commentAction || DY778ConfirmEqual(oppositeState, DY778ConfirmState(current, oppositeAction))) &&
                     (!sourceWindow || (DY778ConfirmSourceView(owner) == sourceView && sourceView.window == sourceWindow));
        if (!valid) {
            if (cancellation) cancellation();
            [DY778ConfirmPrompt showStaleNotice];
            return;
        }
        DY778ConfirmMarkRequest(subject, owner, action, effectiveIntent, YES);
        DY778ConfirmRunApproved(action, effectiveIntent, operation, confirmedUnfollow);
    }];
}
