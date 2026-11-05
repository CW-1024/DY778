#import "DY778LiveInfo.h"
#import <QuartzCore/QuartzCore.h>

BOOL DY778LiveRoomAPIAvailable(Class cls) {
    Method initialize = class_getInstanceMethod(cls, @selector(initWithRoomID:));
    Method fetch = class_getInstanceMethod(cls, @selector(fetchRoomInfoWithRoomID:completion:));
    if (!initialize || !fetch) return NO;
    NSMethodSignature *a = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(initialize)];
    NSMethodSignature *b = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(fetch)];
    return a.numberOfArguments == 3 && a.methodReturnType[0] == '@' && [a getArgumentTypeAtIndex:2][0] == '@' &&
        b.numberOfArguments == 4 && b.methodReturnType[0] == 'v' && [b getArgumentTypeAtIndex:2][0] == '@' &&
        !strcmp([b getArgumentTypeAtIndex:3], "@?");
}

NSString *DY778LiveRoomIdentifier(id room) {
    for (NSString *key in @[@"roomID", @"idStr", @"id_str", @"id"]) {
        NSString *value = DY778Identifier(DY778Read(room,key));
        if (value.length && ![value isEqual:@"0"] && [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound) return value;
    } return nil;
}
double DY778LiveRoomStart(id room, NSString *roomID, NSUInteger depth) {
    if (!room || depth > 5) return 0;
    if ([room isKindOfClass:NSString.class] || [room isKindOfClass:NSData.class]) {
        NSData *data = [room isKindOfClass:NSString.class] ? [room dataUsingEncoding:NSUTF8StringEncoding] : room;
        if (data.length > 1024*1024) return 0;
        room = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; if (!room) return 0;
    }
    NSString *identifier = DY778LiveRoomIdentifier(room);
    if (identifier.length && roomID.length && ![identifier isEqual:roomID]) return 0;
    if (identifier.length) for (NSString *key in @[@"startTime",@"start_time",@"liveStartTime",@"createTime",@"create_time"]) {
        id value = DY778Read(room,key); double time = [value respondsToSelector:@selector(doubleValue)] ? DY778LiveTimestamp([value doubleValue]) : 0;
        if (DY778LiveElapsed(time,NSDate.date.timeIntervalSince1970) >= 0) return time;
    }
    if ([room isKindOfClass:NSArray.class]) for (id item in room) { double time = DY778LiveRoomStart(item,roomID,depth+1); if (time) return time; }
    for (NSString *key in @[@"rawRoom",@"room",@"roomModel",@"rawHTSLiveRoomModel",@"rawDataRoomModel",@"data",@"room_info",@"roomInfo",@"liveRoom",@"rooms"] ) {
        id nested = DY778Read(room,key); if (!nested || nested == room) continue;
        double time = DY778LiveRoomStart(nested,roomID,depth+1); if (time) return time;
    } return 0;
}
NSString *DY778LiveElapsedDigits(double start) {
    char label[40]; DY778LiveDurationLabel(label,sizeof(label),DY778LiveElapsed(start,NSDate.date.timeIntervalSince1970));
    return label[0] ? [NSString stringWithUTF8String:label] : nil;
}
NSString *DY778LiveElapsedText(double start) {
    NSString *digits = DY778LiveElapsedDigits(start);
    return digits.length ? [@"开播 " stringByAppendingString:digits] : nil;
}
@implementation DY778LiveCapsule
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO; self.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:.64];
        self.layer.cornerRadius=14; self.layer.cornerCurve=kCACornerCurveContinuous;
        _label=[UILabel new]; _label.textColor=UIColor.whiteColor; _label.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
        _label.textAlignment=NSTextAlignmentCenter;
        _label.numberOfLines=1; _label.adjustsFontSizeToFitWidth=YES; _label.minimumScaleFactor=.8;
        _symbol=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.2.fill"
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold]]];
        _symbol.tintColor=UIColor.whiteColor; _symbol.contentMode=UIViewContentModeScaleAspectFit;
        [self addSubview:_symbol]; [self addSubview:_label]; self.isAccessibilityElement=YES;
    } return self;
}
- (void)setViewerCountString:(NSString *)text {
    if ([self.label.text isEqualToString:text]) return;
    self.label.text=text;
    self.accessibilityLabel=[NSString stringWithFormat:@"在线人数 %@",text];
    [self invalidateIntrinsicContentSize]; [self setNeedsLayout];
}
- (void)setElapsedString:(NSString *)text {
    if (!self.clock) {
        self.clock=YES;
        self.symbol.image=[UIImage systemImageNamed:@"clock" withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold]];
    }
    if ([self.label.text isEqualToString:text]) return;
    self.label.text=text;
    self.accessibilityLabel=[NSString stringWithFormat:@"开播时长 %@",text];
    [self invalidateIntrinsicContentSize]; [self setNeedsLayout];
}
- (CGSize)intrinsicContentSize {
    CGSize size=[self.label sizeThatFits:CGSizeMake(260,20)];
    return CGSizeMake(MIN(294,MAX(18,ceil(size.width))+34),28);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.symbol.frame=CGRectMake(8,(self.bounds.size.height-12)/2,12,12);
    self.label.frame=CGRectMake(24,1,MAX(1,self.bounds.size.width-34),self.bounds.size.height-2);
    self.layer.cornerRadius=self.bounds.size.height/2;
}
@end
