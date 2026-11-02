#ifndef DY778_PLAYBACK_POLICY_H
#define DY778_PLAYBACK_POLICY_H
#include <math.h>
#include <stdio.h>

typedef struct { double before; int active; } DY778PressSession;
static inline int DY778DefaultRateAllowed(int enabled, int video, int visible, int pressing) {
    return enabled && video && visible && !pressing;
}
static inline double DY778PlaybackRate(double value) {
    if (!isfinite(value)) return 2;
    return round((value < 1 ? 1 : value > 3 ? 3 : value) * 100) / 100;
}
static inline void DY778PlaybackRateLabel(char *buffer, size_t size, double rate) {
    int hundredths = (int)lround(DY778PlaybackRate(rate) * 100);
    int whole = hundredths / 100, fraction = hundredths % 100;
    if (!fraction) snprintf(buffer, size, "%dx", whole);
    else if (!(fraction % 10)) snprintf(buffer, size, "%d.%dx", whole, fraction / 10);
    else snprintf(buffer, size, "%d.%02dx", whole, fraction);
}
static inline int DY778PressBegin(DY778PressSession *session, int enabled, double current) {
    if (!enabled || session->active || !isfinite(current) || current < .5 || current > 8) return 0;
    session->before = current; session->active = 1; return 1;
}
static inline int DY778PressEnd(DY778PressSession *session, double *restore) {
    if (!session->active) return 0;
    *restore = session->before; session->active = 0; return 1;
}

// A previous swizzle may invoke the selector again. Track the individual hook,
// allowing a legitimate subclass -> superclass call with the same selector.
typedef struct DY778PlaybackFrame {
    const void *object;
    const void *hook;
    struct DY778PlaybackFrame *previous;
} DY778PlaybackFrame;
static inline int DY778PlaybackFrameContains(const DY778PlaybackFrame *frame, const void *object, const void *hook) {
    for (; frame; frame = frame->previous)
        if (frame->object == object && frame->hook == hook) return 1;
    return 0;
}
#endif
