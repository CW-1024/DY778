#ifndef DY778_LUCKY_POLICY_H
#define DY778_LUCKY_POLICY_H
#include <stdbool.h>
#include <string.h>
#include <math.h>
static inline bool DY778LuckyRequestExpired(double openedAt, double now) {
    return !isfinite(openedAt) || !isfinite(now) || openedAt <= 0 || now < openedAt || now - openedAt >= 40;
}
static inline bool DY778LuckyShouldRefreshParticipation(unsigned count, double last, double now) {
    return count < 2 && isfinite(now) && (count == 0 || (isfinite(last) && now - last >= 2.5));
}
typedef enum { DY778LuckyButtonUnknown, DY778LuckyButtonJoin, DY778LuckyButtonSubmitted } DY778LuckyButtonKind;
static inline DY778LuckyButtonKind DY778LuckyClassifyButton(const char *text) {
    if (!text) return DY778LuckyButtonUnknown;
    const char *join[] = {"参与福袋","一键参与福袋","立即参与福袋","免费参与福袋","参与","立即参与","一键参与","免费参与","参与抽奖","立即参与抽奖","免费立即参与抽奖"};
    for (unsigned i = 0; i < sizeof(join)/sizeof(*join); i++) if (!strcmp(text,join[i])) return DY778LuckyButtonJoin;
    const char *submitted[] = {"已参与","参与成功","已参与福袋","等待开奖","报名成功"};
    for (unsigned i = 0; i < sizeof(submitted)/sizeof(*submitted); i++) if (!strcmp(text,submitted[i])) return DY778LuckyButtonSubmitted;
    return DY778LuckyButtonUnknown;
}
static inline bool DY778LuckyCanActivate(bool roomValid, bool visible, bool enabled, unsigned matches,
    bool alreadySubmitted, bool conditionsPending, DY778LuckyButtonKind kind) {
    return roomValid && visible && enabled && matches == 1 && !alreadySubmitted && !conditionsPending && kind == DY778LuckyButtonJoin;
}
typedef enum {
    DY778LuckyPlanNone = 0,
    DY778LuckyPlanOpen = 1 << 0,
    DY778LuckyPlanPhrase = 1 << 1,
    DY778LuckyPlanJoin = 1 << 2,
    DY778LuckyPlanManual = 1 << 3
} DY778LuckyPlan;
typedef enum {
    DY778LuckyConditionIgnore, DY778LuckyConditionPhrase, DY778LuckyConditionFans, DY778LuckyConditionManual
} DY778LuckyConditionKind;
static inline bool DY778LuckyFanEligible(bool known, bool member, bool active, long long level, long long required) {
    return known && member && active && level >= (required > 0 ? required : 0);
}
static inline bool DY778LuckyEligibilityFresh(bool sameContext, double checkedAt, double now) {
    return sameContext && checkedAt > 0 && now >= checkedAt && now - checkedAt < 30;
}
typedef enum {
    DY778LuckyEligibilityNoticeNone, DY778LuckyEligibilityNoticeFans,
    DY778LuckyEligibilityNoticeUnknown, DY778LuckyEligibilityNoticeRestricted
} DY778LuckyEligibilityNotice;
static inline DY778LuckyEligibilityNotice DY778LuckyFanNotice(bool requiresFans, bool pending,
    bool checked, bool known, bool restricted, bool unmet, bool unknownLevel) {
    if (!requiresFans || pending || !checked) return DY778LuckyEligibilityNoticeNone;
    if (restricted) return DY778LuckyEligibilityNoticeRestricted;
    if (!known || unknownLevel) return DY778LuckyEligibilityNoticeUnknown;
    return unmet ? DY778LuckyEligibilityNoticeFans : DY778LuckyEligibilityNoticeNone;
}
typedef enum { DY778LuckyRouteOriginal, DY778LuckyRouteCancel, DY778LuckyRouteQuiet } DY778LuckyRouteAction;
static inline DY778LuckyRouteAction DY778LuckyRoutePolicy(bool tagged, bool sameRequest,
    bool requestValid, bool occupied) {
    if (!tagged) return DY778LuckyRouteOriginal;
    return sameRequest && requestValid && !occupied ? DY778LuckyRouteQuiet : DY778LuckyRouteCancel;
}
static inline bool DY778LuckyConditionIsInstruction(const char *text) {
    if (!text) return false;
    const char *labels[] = {"手动参与", "点击参与", "参与福袋", "点击参与福袋", "无需额外条件"};
    for (unsigned i = 0; i < sizeof(labels)/sizeof(*labels); i++) if (!strcmp(text, labels[i])) return true;
    return false;
}
static inline DY778LuckyConditionKind DY778LuckyClassifyCondition(int type, bool validPhrase,
    bool hasText, bool paid, bool fans, bool explicitAction, bool instruction) {
    if (fans) return DY778LuckyConditionFans;
    if (paid || explicitAction) return DY778LuckyConditionManual;
    if (type == 3 && validPhrase) return DY778LuckyConditionPhrase;
    if (instruction) return DY778LuckyConditionIgnore;
    return hasText || type != 0 ? DY778LuckyConditionManual : DY778LuckyConditionIgnore;
}
static inline unsigned DY778LuckyParticipationPlan(bool enabled, bool currentRoom, bool stopped,
    bool hasPhrase, bool phraseAuthorized, bool phraseAlreadySubmitted, bool extraConditions, bool autoJoin) {
    if (!enabled || !currentRoom || stopped) return DY778LuckyPlanNone;
    unsigned plan = DY778LuckyPlanOpen;
    if (!extraConditions && hasPhrase && phraseAuthorized && !phraseAlreadySubmitted) plan |= DY778LuckyPlanPhrase;
    if (extraConditions || (hasPhrase && !phraseAuthorized) || !autoJoin) plan |= DY778LuckyPlanManual;
    else plan |= DY778LuckyPlanJoin;
    return plan;
}
#endif
