#import "DY778RadarModel.h"
NS_ASSUME_NONNULL_BEGIN
@interface DY778RadarStore : NSObject
@property(nonatomic, readonly, copy) NSString *accountID;
@property(nonatomic, readonly, copy) NSArray<NSDictionary *> *targets;
@property(nonatomic, readonly, copy) NSArray<NSDictionary *> *records;
@property(nonatomic, readonly, copy) NSDictionary *options;
@property(nonatomic, readonly, copy) NSString *storageError;
+ (instancetype)shared;
- (instancetype)initWithDirectory:(NSURL *)directory;
- (void)activateAccount:(NSString *)accountID;
- (void)setOption:(NSString *)key value:(id)value;
- (BOOL)addProfiles:(NSArray<NSDictionary *> *)profiles error:(NSError * _Nullable *)error;
- (nullable NSDictionary *)target:(NSString *)uid;
- (void)updateTarget:(NSString *)uid values:(NSDictionary *)values;
- (void)removeTarget:(NSString *)uid;
- (void)resetBaseline:(NSString *)uid;
- (NSArray<NSDictionary *> *)applyProfile:(NSDictionary *)profile forUID:(NSString *)uid;
- (NSArray<NSDictionary *> *)applyLikes:(NSArray<NSDictionary *> *)videos complete:(BOOL)complete forUID:(NSString *)uid;
- (void)markLikesUnavailable:(NSString *)uid;
- (void)deleteRecord:(NSString *)recordID;
- (void)clearRecords;
- (void)prune;
- (void)save;
- (void)flush;
- (NSUInteger)storageBytes;
@end
NS_ASSUME_NONNULL_END
