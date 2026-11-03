#ifndef DY778_LIVE_LIKE_POLICY_H
#define DY778_LIVE_LIKE_POLICY_H
#include <stdbool.h>
#include <math.h>
#include <stddef.h>
#include <string.h>

enum { DY778LiveLikeDefaultTarget = 100, DY778LiveLikeMaximumTarget = 9999,
       DY778LiveLikeMaximumPending = 20 };

static inline unsigned DY778LiveLikeTarget(double value) {
    if (!isfinite(value) || value < 1) return DY778LiveLikeDefaultTarget;
    return value > DY778LiveLikeMaximumTarget ? DY778LiveLikeMaximumTarget : (unsigned)value;
}
static inline double DY778LiveLikeInterval(double value) {
    if (!isfinite(value) || value <= 0) return 1.0;
    return round(fmin(2.0, fmax(.6, value)) * 10.0) / 10.0;
}
static inline double DY778LiveLikePause(double value) {
    if (!isfinite(value) || value <= 0) return 1.5;
    return round(fmin(3.0, fmax(1.0, value)) * 10.0) / 10.0;
}

// Let the native single-action state reset before the next scheduled action.
// This is a local timer gap, not a server-side frequency allowance.
static inline double DY778LiveLikeNativeGap(double interval) {
    return fmin(.7, DY778LiveLikeInterval(interval) - .15);
}
static inline double DY778LiveLikeInitialDelay(double interval, double nativeGap) {
    double reset = isfinite(nativeGap) && nativeGap > 0 ? nativeGap + .15 : 0;
    return fmax(DY778LiveLikeInterval(interval), reset);
}
static inline const char *DY778LiveLikeResolveRoom(const char *const *rooms, size_t count) {
    const char *room = NULL;
    for (size_t i = 0; i < count; i++) {
        const char *candidate = rooms[i];
        if (!candidate || !*candidate || !strcmp(candidate, "0")) continue;
        if (room && strcmp(room, candidate)) return NULL;
        room = candidate;
    }
    return room;
}
static inline bool DY778LiveLikeSameAccount(const char *initial, const char *current) {
    // An unavailable identifier is not evidence that the native login failed.
    return !strcmp(initial ? initial : "", current ? current : "");
}

typedef struct {
    unsigned target, emitted, assigned, confirmed;
    double nextAction, pendingSince, interval, pause;
    bool failed;
} DY778LiveLikeProgress;

static inline bool DY778LiveLikeComplete(const DY778LiveLikeProgress *p) {
    return !p->failed && p->target > 0 && p->emitted == p->target && p->confirmed == p->target;
}
static inline bool DY778LiveLikeTimedOut(const DY778LiveLikeProgress *p, double now) {
    return p->emitted > p->confirmed && now - p->pendingSince >= 30.0;
}
static inline bool DY778LiveLikeCanEmit(const DY778LiveLikeProgress *p, double now) {
    return !p->failed && p->emitted < p->target && now >= p->nextAction &&
        p->emitted - p->confirmed < DY778LiveLikeMaximumPending && !DY778LiveLikeTimedOut(p, now);
}
static inline bool DY778LiveLikeAccept(DY778LiveLikeProgress *p, double now) {
    if (!DY778LiveLikeCanEmit(p, now)) return false;
    if (p->emitted == p->confirmed) p->pendingSince = now;
    p->emitted++;
    double delay = DY778LiveLikeInterval(p->interval);
    if (p->emitted % 20 == 0) delay = fmax(delay, DY778LiveLikePause(p->pause));
    p->nextAction = now + delay;
    return true;
}
static inline unsigned DY778LiveLikeAssign(DY778LiveLikeProgress *p, unsigned batch) {
    unsigned available = p->emitted - p->assigned;
    unsigned credited = batch < available ? batch : available;
    p->assigned += credited;
    return credited;
}
static inline bool DY778LiveLikeConfirm(DY778LiveLikeProgress *p, unsigned credit, bool success, double now) {
    if (p->failed || !credit || credit > p->assigned - p->confirmed) return false;
    if (!success) { p->failed = true; return false; }
    p->confirmed += credit;
    p->pendingSince = p->emitted > p->confirmed ? now : 0;
    return true;
}
#endif
