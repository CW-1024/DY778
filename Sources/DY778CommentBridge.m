#import "DY778CommentBridge.h"
#import "DY778CommentBridgePolicy.h"
#import <objc/runtime.h>

static Class DY778CommentBaseClass(id component) {
    Class base = NSClassFromString(@"_TtCV28AWECommentPanelListSwiftImpl6NEWAPI24CommentCellBaseComponent");
    if (!base || ![component isKindOfClass:base]) return Nil;
    for (NSString *name in @[@"_TtCV28AWECommentPanelListSwiftImpl6NEWAPI24CommentCellLikeComponent",
                             @"_TtCV28AWECommentPanelListSwiftImpl6NEWAPI27CommentCellOldLikeComponent",
                             @"_TtCV28AWECommentPanelListSwiftImpl6NEWAPI27CommentCellDislikeComponent"]) {
        Class cls = NSClassFromString(name);
        if (cls && [component isKindOfClass:cls]) return base;
    }
    return Nil;
}

static Ivar DY778CommentVerifiedSlot(id object, Class declaring, const char *name,
                                     BOOL reference, size_t size, size_t alignment) {
    if (!object || !declaring || ![object isKindOfClass:declaring]) return NULL;
    Ivar ivar = class_getInstanceVariable(declaring, name);
    if (!ivar || !DY778CommentSlotValid(ivar_getOffset(ivar), class_getInstanceSize(object_getClass(object)), size, alignment)) return NULL;
    const char *encoding = ivar_getTypeEncoding(ivar);
    if (encoding && *encoding) {
        if (reference ? encoding[0] != '@' : (encoding[0] != 'B' && encoding[0] != 'c')) return NULL;
    } else {
        NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (![version isKindOfClass:NSString.class] || !DY778CommentVerifiedVersion(version.UTF8String)) return NULL;
    }
    return ivar;
}

static id DY778CommentObject(id object, Class declaring, const char *name, Class expected) {
    if (!expected) return nil;
    Ivar ivar = DY778CommentVerifiedSlot(object, declaring, name, YES, sizeof(id), _Alignof(id));
    if (!ivar) return nil;
    id value = object_getIvar(object, ivar);
    return [value isKindOfClass:expected] ? value : nil;
}

id DY778CommentBindingToken(id component) {
    Class base = DY778CommentBaseClass(component);
    Class contextClass = NSClassFromString(@"_TtC28AWECommentPanelListSwiftImpl27CommentCellComponentContext");
    return base ? DY778CommentObject(component, base, "context", contextClass) : nil;
}

id DY778CommentBoundModel(id component) {
    Class base = DY778CommentBaseClass(component);
    if (!base) return nil;
    Class modelClass = NSClassFromString(@"AWECommentModel");
    id context = DY778CommentBindingToken(component);
    Class contextClass = NSClassFromString(@"_TtC28AWECommentPanelListSwiftImpl27CommentCellComponentContext");
    id model = DY778CommentObject(context, contextClass, "commentModel", modelClass);
    return model ?: DY778CommentObject(component, base, "data", modelClass);
}

NSNumber *DY778CommentBindingVisible(id component) {
    id context = DY778CommentBindingToken(component);
    Class cls = NSClassFromString(@"_TtC28AWECommentPanelListSwiftImpl27CommentCellComponentContext");
    Ivar ivar = DY778CommentVerifiedSlot(context, cls, "visible", NO, 1, 1);
    if (!ivar) return nil;
    unsigned char flag = 0;
    memcpy(&flag, (const unsigned char *)(__bridge const void *)context + ivar_getOffset(ivar), 1);
    return flag <= 1 ? @(flag != 0) : nil;
}
