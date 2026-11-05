#import "DY778Spark.h"
#import <string.h>

static NSString *const DY778SparkRestoreMenuIdentifier = @"dy778.spark.restore-display";
static char DY778SparkRestoreMenuMarker;
static void (*DY778SparkMenuOriginalShow)(id, SEL, id);

static BOOL DY778SparkMenuSignature(Method method, char result, const char *arguments) {
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.methodReturnType[0] != result || signature.numberOfArguments != strlen(arguments) + 2) return NO;
    for (NSUInteger i = 0; arguments[i]; i++) {
        if ([signature getArgumentTypeAtIndex:i + 2][0] != arguments[i]) return NO;
    }
    return YES;
}

static BOOL DY778SparkMenuSetObject(id object, NSString *name, id value) {
    SEL selector = NSSelectorFromString(name);
    if (!DY778SparkMenuSignature(class_getInstanceMethod(object_getClass(object), selector), 'v', "@")) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
    return YES;
}

static UIViewController *DY778SparkMenuSource(id component) {
    id source = DY778Read(DY778Read(component, @"context"), @"hostViewController");
    if (![source isKindOfClass:UIViewController.class]) return nil;
    UIViewController *controller = source;
    return controller.isViewLoaded && controller.view.window ? controller : nil;
}

static UIColor *DY778SparkMenuTitleColor(id component) {
    SEL selector = NSSelectorFromString(@"__buttonTitleColor");
    if (!DY778SparkMenuSignature(class_getInstanceMethod(object_getClass(component), selector), '@', "")) return nil;
    id color = ((id (*)(id, SEL))objc_msgSend)(component, selector);
    return [color isKindOfClass:UIColor.class] ? color : nil;
}

static UIImage *DY778SparkMenuImage(NSArray *items) {
    for (id item in items) {
        id title = DY778Read(item, @"title");
        if (![title isKindOfClass:NSString.class] || ![title containsString:@"火花"]) continue;
        id image = DY778Read(item, @"image");
        if ([image isKindOfClass:UIImage.class]) return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }

    Class imageClass = UIImage.class;
    SEL selector = NSSelectorFromString(@"dux_iconNamed:size:color:");
    Method method = class_getClassMethod(imageClass, selector);
    if (method) {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        BOOL valid = signature.methodReturnType[0] == '@' && signature.numberOfArguments == 5;
        valid = valid && [signature getArgumentTypeAtIndex:2][0] == '@' &&
            strcmp([signature getArgumentTypeAtIndex:3], @encode(CGSize)) == 0 &&
            [signature getArgumentTypeAtIndex:4][0] == '@';
        if (valid) {
            id image = ((id (*)(id, SEL, id, CGSize, id))objc_msgSend)(imageClass, selector,
                @"ic_fire_outlined_20", CGSizeMake(24, 24), @"TextReverse");
            if ([image isKindOfClass:UIImage.class]) return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
    }
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    return [[UIImage systemImageNamed:@"arrow.counterclockwise" withConfiguration:configuration]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static void DY778SparkMenuRestore(UIViewController *source, NSString *account) {
    if (!NSThread.isMainThread || !account.length || ![account isEqual:DY778CurrentAccountID()]) {
        DY778Toast(@"账号已切换，请重新打开菜单");
        return;
    }
    if (!source || !source.isViewLoaded || !source.view.window) return;
    if (!DY778SparkHasCustomizationsForAccount(account)) {
        DY778RestoreSparkForAccount(account);
        return;
    }
    DY778Confirm(source, @"恢复火花显示？",
        @"清除当前账号所有聊天的火花自定义，恢复抖音原始显示；不会更改真实火花或其他账号配置。",
        @"恢复显示", YES, ^{
            if (![account isEqual:DY778CurrentAccountID()]) {
                DY778Toast(@"账号已切换，请重新打开菜单");
                return;
            }
            if (!DY778SparkHasCustomizationsForAccount(account)) {
                DY778Toast(@"当前账号暂无自定义火花，无需恢复");
                return;
            }
            DY778RestoreSparkForAccount(account);
        });
}

static NSArray *DY778SparkMenuItems(id component, NSArray *items) {
    NSString *account = DY778CurrentAccountID();
    UIViewController *source = DY778SparkMenuSource(component);
    if (!account.length || !source ||
        (!DY778Bool(@"spark.enabled") && !DY778SparkHasCustomizationsForAccount(account))) return items;

    Class modelClass = NSClassFromString(@"AWEIMMessageTabNaviPlusButtonModel");
    if (!modelClass) return items;
    UIImage *image = DY778SparkMenuImage(items);
    if (!image) return items;
    id model = [[modelClass alloc] init];
    if (!model) return items;
    __weak UIViewController *weakSource = source;
    dispatch_block_t handler = ^{
        DY778SparkMenuRestore(weakSource, account);
    };
    if (!DY778SparkMenuSetObject(model, @"setTitle:", @"恢复火花显示") ||
        !DY778SparkMenuSetObject(model, @"setImage:", image) ||
        !DY778SparkMenuSetObject(model, @"setTitleColor:", DY778SparkMenuTitleColor(component)) ||
        !DY778SparkMenuSetObject(model, @"setHandler:", handler) ||
        !DY778SparkMenuSetObject(model, @"setIdentifier:", DY778SparkRestoreMenuIdentifier)) return items;
    objc_setAssociatedObject(model, &DY778SparkRestoreMenuMarker, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:items.count + 1];
    for (id item in items) {
        if (!objc_getAssociatedObject(item, &DY778SparkRestoreMenuMarker)) [result addObject:item];
    }
    [result addObject:model];
    return [result copy];
}

static void DY778SparkMenuShow(id component, SEL selector, id items) {
    if (!DY778SparkMenuOriginalShow) return;
    id displayedItems = items;
    if (NSThread.isMainThread && [items isKindOfClass:NSArray.class] && [items count] > 0) {
        @try { displayedItems = DY778SparkMenuItems(component, items); }
        @catch (__unused NSException *exception) { displayedItems = items; }
    }
    DY778SparkMenuOriginalShow(component, selector, displayedItems);
}

void DY778InstallSparkMenu(void) {
    static BOOL installed;
    if (installed) return;
    Class component = NSClassFromString(@"AWEIMMessageTabPlusButtonComponent");
    SEL selector = NSSelectorFromString(@"p_showBarPlusList:");
    if (DY778SparkMenuSignature(class_getInstanceMethod(component, selector), 'v', "@")) {
        installed = DY778Hook(component, selector, (IMP)DY778SparkMenuShow, (IMP *)&DY778SparkMenuOriginalShow);
    }
    DY778RecordHook(@"spark.message-menu", installed);
}
