#ifndef DY778_LIST_CLEAR_POLICY_H
#define DY778_LIST_CLEAR_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define DY778_LIST_CLEAR_BATCH 20u
#define DY778_LIST_CLEAR_MAX_ITEMS 30000u
#define DY778_LIST_CLEAR_MAX_PAGES 2500u

static inline const char *DY778ListClearEndpoint(unsigned int kind) {
    switch (kind) {
        case 0: return "/aweme/v1/familiar/recommend/batch/cancel";
        case 1: return "/aweme/v1/aweme/cancel/collect/multi";
        case 2: return "/aweme/v1/aweme/cancel/item/digg/multi";
        default: return NULL;
    }
}
static inline bool DY778ListClearMatchesPath(const char *path, unsigned int kind) {
    const char *expected = DY778ListClearEndpoint(kind);
    if (!path || !expected) return false;
    size_t length = strlen(path), expectedLength = strlen(expected);
    if (length == expectedLength + 1 && path[length - 1] == '/') --length;
    return length == expectedLength && memcmp(path, expected, length) == 0;
}
static inline bool DY778ListClearVerifiedReceipt(bool submitted, bool requestMatched, bool modelMatched,
                                                bool statusPresent, int64_t statusCode, bool hasError,
                                                bool failedIDsValid, bool failuresAreSubmittedIDs) {
    return submitted && requestMatched && modelMatched && statusPresent && statusCode == 0 &&
        !hasError && failedIDsValid && failuresAreSubmittedIDs;
}

static inline int DY778ListClearKindForProfileTab(int64_t tabType) {
    if (tabType == 33) return 0;
    if (tabType == 16) return 1;
    if (tabType == 2) return 2;
    return -1;
}
static inline bool DY778ListClearEligibleProfile(bool homeClass, bool detailClass, bool homeMarker, bool detailMarker, bool sameAccount) {
    return sameAccount && ((homeClass && homeMarker) || (detailClass && detailMarker));
}
static inline bool DY778ListClearPrimaryTabIndex(bool primaryContainer, size_t index, size_t viewCount, size_t modelCount) {
    return primaryContainer && viewCount > 0 && index < viewCount && index < modelCount;
}

typedef struct {
    uint64_t generation, ticket;
    size_t total, confirmed, pages, emptyPages;
    bool active, waiting, removing;
} DY778ListClearState;

typedef enum {
    DY778ListClearContinue,
    DY778ListClearComplete,
    DY778ListClearPartial,
    DY778ListClearInvalid,
    DY778ListClearLimit,
    DY778ListClearNoProgress
} DY778ListClearDecision;

static inline void DY778ListClearBegin(DY778ListClearState *s) {
    uint64_t next = s->generation + 1;
    *s = (DY778ListClearState){.generation = next, .active = true};
}
static inline void DY778ListClearStop(DY778ListClearState *s) {
    s->active = false; s->waiting = false; ++s->generation;
}
static inline uint64_t DY778ListClearIssue(DY778ListClearState *s) {
    if (!s->active || s->waiting) return 0;
    s->waiting = true; return ++s->ticket;
}
static inline bool DY778ListClearIsCurrent(const DY778ListClearState *s, uint64_t generation, uint64_t ticket) {
    return s->active && s->waiting && s->generation == generation && s->ticket == ticket;
}
static inline bool DY778ListClearConsume(DY778ListClearState *s, uint64_t generation, uint64_t ticket) {
    if (!DY778ListClearIsCurrent(s, generation, ticket)) return false;
    s->waiting = false; return true;
}
static inline DY778ListClearDecision DY778ListClearPage(DY778ListClearState *s, size_t fresh, bool more, bool advanced) {
    if (!s->active || s->removing) return DY778ListClearInvalid;
    if (fresh > DY778_LIST_CLEAR_MAX_ITEMS - s->total || ++s->pages > DY778_LIST_CLEAR_MAX_PAGES)
        return DY778ListClearLimit;
    s->total += fresh; s->emptyPages = fresh ? 0 : s->emptyPages + 1;
    if (more && (!advanced || s->emptyPages >= 3)) return DY778ListClearNoProgress;
    return more ? DY778ListClearContinue : DY778ListClearComplete;
}
static inline DY778ListClearDecision DY778ListClearBatchResult(DY778ListClearState *s, size_t submitted, size_t failed, bool verified) {
    if (!s->active || !s->removing || !verified || submitted == 0 || submitted > DY778_LIST_CLEAR_BATCH ||
        failed > submitted || s->confirmed > s->total || submitted > s->total - s->confirmed)
        return DY778ListClearInvalid;
    s->confirmed += submitted - failed;
    if (failed) return DY778ListClearPartial;
    return s->confirmed == s->total ? DY778ListClearComplete : DY778ListClearContinue;
}
#endif
