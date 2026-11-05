#ifndef DY778_DISPLAY_STATS_POLICY_H
#define DY778_DISPLAY_STATS_POLICY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define DY778_DISPLAY_STATS_MAX UINT64_C(999999999)

typedef enum {
    DY778DisplayStatsInvalid = -1,
    DY778DisplayStatsOriginal = 0,
    DY778DisplayStatsCustom = 1
} DY778DisplayStatsInput;

static inline DY778DisplayStatsInput DY778DisplayStatsParse(const char *text, uint64_t *result) {
    if (!text) return DY778DisplayStatsInvalid;
    if (!*text) return DY778DisplayStatsOriginal;
    uint64_t value = 0;
    size_t length = 0;
    for (const unsigned char *cursor = (const unsigned char *)text; *cursor; cursor++) {
        if (++length > 32 || *cursor < '0' || *cursor > '9') return DY778DisplayStatsInvalid;
        unsigned digit = *cursor - '0';
        if (value > (DY778_DISPLAY_STATS_MAX - digit) / 10) return DY778DisplayStatsInvalid;
        value = value * 10 + digit;
    }
    if (result) *result = value;
    return DY778DisplayStatsCustom;
}

static inline bool DY778DisplayStatsSameAccount(bool enabled, const char *owner, const char *account) {
    return enabled && owner && account && *owner && *account && strcmp(owner, account) == 0;
}

static inline DY778DisplayStatsInput DY778DisplayStatsResolve(bool enabled, bool sameAccount,
        bool useOriginal, const char *itemValue, const char *commonValue, uint64_t *result) {
    if (!enabled || !sameAccount || useOriginal) return DY778DisplayStatsOriginal;
    if (itemValue && *itemValue) return DY778DisplayStatsParse(itemValue, result);
    return commonValue ? DY778DisplayStatsParse(commonValue, result) : DY778DisplayStatsOriginal;
}

static inline bool DY778DisplayStatsEditorMatches(const char *account, const char *expectedAccount,
        const char *item, const char *expectedItem) {
    if (!DY778DisplayStatsSameAccount(true, account, expectedAccount)) return false;
    if (!expectedItem || !*expectedItem) return !item || !*item;
    return item && strcmp(item, expectedItem) == 0;
}

static inline bool DY778DisplayStatsEditorSessionValid(bool invalidated,
        const char *account, const char *expectedAccount) {
    return !invalidated && DY778DisplayStatsSameAccount(true, account, expectedAccount);
}

static inline bool DY778DisplayStatsShouldResetOnPull(bool enabled, bool insideUserDrag,
        unsigned long long refreshType, bool ownHomepage, bool sameAccount, size_t accountConfigCount) {
    return enabled && insideUserDrag && refreshType == 0 && ownHomepage && sameAccount && accountConfigCount > 0;
}

static inline bool DY778DisplayStatsWorkShowsPlays(const char *iconName) {
    return iconName && (!strcmp(iconName, "icon_home_viewnum") || !strcmp(iconName, "profile_video_HD"));
}

typedef enum {
    DY778DisplayStatsLabelKeepNative,
    DY778DisplayStatsLabelRestoreSaved,
    DY778DisplayStatsLabelRestoreCurrent,
    DY778DisplayStatsLabelAwaitNative
} DY778DisplayStatsLabelRecovery;

static inline DY778DisplayStatsLabelRecovery DY778DisplayStatsRecoverLabel(bool isApplied,
        bool sameVideo, bool hasCurrentOriginal) {
    if (!isApplied) return DY778DisplayStatsLabelKeepNative;
    if (sameVideo) return DY778DisplayStatsLabelRestoreSaved;
    return hasCurrentOriginal ? DY778DisplayStatsLabelRestoreCurrent : DY778DisplayStatsLabelAwaitNative;
}

static inline bool DY778DisplayStatsPraiseRange(const char *text, const char *original,
        size_t *offset, size_t *length) {
    if (!text || !original || !*original) return false;
    const char *prefix = "共获得 ", *suffix = " 个赞", *match = NULL, *cursor = text;
    while ((cursor = strstr(cursor, prefix))) { match = cursor; cursor++; }
    if (!match) return false;
    const char *start = match + strlen(prefix);
    size_t countLength = strlen(original);
    if (strncmp(start, original, countLength) || strcmp(start + countLength, suffix)) return false;
    if (offset) *offset = (size_t)(start - text);
    if (length) *length = countLength;
    return true;
}

#endif
