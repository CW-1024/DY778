#ifndef DY778_SPEED_LOCK_POLICY_H
#define DY778_SPEED_LOCK_POLICY_H
#include <math.h>

typedef struct {
    double before;
    double rate;
    int locked;
} DY778SpeedLockState;

static inline int DY778SpeedValid(double value) {
    return isfinite(value) && value >= .5 && value <= 8;
}
static inline int DY778SpeedLockGeometry(int sameWindow, double width, double height,
                                         double originalWidth, double originalHeight) {
    return sameWindow && isfinite(width) && isfinite(height) && width > 0 && height > 0 &&
        width == originalWidth && height == originalHeight;
}
static inline int DY778SpeedLockDeferred(unsigned long long generation, unsigned long long expected, int pressing) {
    return generation == expected && !pressing;
}
static inline int DY778SpeedLockSlide(double dx, double dy, double threshold, double height, int nativeArea) {
    if (!isfinite(dx) || !isfinite(dy) || !isfinite(height) || height <= 0 || dy > height) return 0;
    if (!isfinite(threshold) || threshold < 24 || threshold > height * .5) threshold = fmin(96, height * .25);
    return dy >= 24 && dy > fabs(dx) && (dy >= threshold || nativeArea);
}
static inline int DY778SpeedLockComplete(DY778SpeedLockState *state, int ended, int armed,
                                         double before, double configured, double *result) {
    if (!state || !result || !DY778SpeedValid(before) || !DY778SpeedValid(configured)) return 0;
    if (state->locked && (!DY778SpeedValid(state->before) || !DY778SpeedValid(state->rate))) return 0;
    if (!ended || !armed) { *result = state->locked ? state->rate : before; return 0; }
    if (state->locked) { *result = state->before; state->locked = 0; return -1; }
    state->before = before; state->rate = configured; state->locked = 1; *result = configured; return 1;
}
static inline double DY778SpeedLockPriority(DY778SpeedLockState state, int pressing, double pressRate,
                                           int settling, double settledRate, double requested) {
    if (settling && DY778SpeedValid(settledRate)) return settledRate;
    if (pressing && DY778SpeedValid(pressRate)) return pressRate;
    if (state.locked && DY778SpeedValid(state.rate)) return state.rate;
    return requested;
}
#endif
