#ifndef DY778_LUCKY_CLOCK_H
#define DY778_LUCKY_CLOCK_H
#include <math.h>
#include <stdbool.h>
static inline double DY778LuckyEpochSeconds(double value) {
    if (!isfinite(value) || value <= 0) return -1;
    return value > 100000000000.0 ? value / 1000.0 : value;
}
static inline double DY778LuckyServerRemaining(double draw, double current) {
    draw = DY778LuckyEpochSeconds(draw); current = DY778LuckyEpochSeconds(current);
    if (draw < 0 || current < 0 || draw < current) return -1;
    double delta = draw - current;
    return delta <= 86400 ? delta : -1;
}
static inline double DY778LuckyDurationSeconds(double raw, double reference) {
    if (!isfinite(raw) || raw < 0) return -1;
    if (raw == 0) return 0;
    double seconds = raw, milliseconds = raw / 1000.0;
    if (isfinite(reference) && reference >= 0) {
        double selected = fabs(seconds - reference) <= fabs(milliseconds - reference) ? seconds : milliseconds;
        return selected <= 86400 && fabs(selected - reference) <= fmax(3, reference * 0.2) ? selected : -1;
    }
    return -1;
}
static inline double DY778LuckyStoreDurationSeconds(double raw) {
    if (!isfinite(raw) || raw < 0) return -1;
    double seconds = raw / 1000.0;
    return seconds <= 86400 ? seconds : -1;
}
static inline double DY778LuckyClockRemaining(double seconds, double sampledAt, double now) {
    if (!isfinite(seconds) || seconds < 0 || !isfinite(sampledAt) || !isfinite(now)) return -1;
    return fmax(0, seconds - fmax(0, now - sampledAt));
}
#endif
