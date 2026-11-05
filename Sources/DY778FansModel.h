#import "DY778FansRuntime.h"

typedef NS_ENUM(NSInteger, DY778FansInputMode) { DY778FansInputAutomatic, DY778FansInputHandle, DY778FansInputUID };
NSDictionary *DY778FansParseInput(NSString *input, DY778FansInputMode mode, NSError **error);
BOOL DY778FansShareURL(NSURL *url);
NSString *DY778FansImageURL(id object);
NSDictionary *DY778FansPerson(id object);
BOOL DY778FansSamePerson(NSDictionary *expected, NSDictionary *actual);
NSString *DY778FansPersonName(NSDictionary *person);
BOOL DY778FansHandleMatches(id object, NSString *handle);
NSArray<NSDictionary *> *DY778FansSearchPeople(id response);

@interface DY778FansResult : NSObject
@property(nonatomic, copy) NSDictionary *person;
@property(nonatomic, copy) NSDictionary *anchor;
@property(nonatomic, strong) NSNumber *level;
@property(nonatomic, strong) NSNumber *minimum;
@property(nonatomic, strong) NSNumber *maximum;
@property(nonatomic, copy) NSArray<NSDictionary *> *clubs;
@property(nonatomic, strong) NSDate *date;
@property(nonatomic, copy) NSString *notice;
@property(nonatomic, copy) NSString *source;
@property(nonatomic, copy) NSString *diagnostic;
+ (instancetype)fromUser:(id)user target:(NSDictionary *)target error:(NSError **)error;
+ (instancetype)fromUser:(id)user target:(NSDictionary *)target anchor:(NSDictionary *)anchor error:(NSError **)error;
+ (instancetype)fromProfileResponse:(id)response target:(NSDictionary *)target anchor:(NSDictionary *)anchor error:(NSError **)error;
- (NSString *)shareText;
@end
