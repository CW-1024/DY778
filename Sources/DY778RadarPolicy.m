#include "DY778RadarPolicy.h"
#include <math.h>
#include <string.h>
bool DY778RadarNoticeReady(double now, double shownAt) {
    return isfinite(now) && isfinite(shownAt) && shownAt >= 0 && now - shownAt >= 2.0;
}
double DY778RadarInterval(double value) {
    if (!isfinite(value) || value <= 0) return 300;
    return fmin(300, fmax(30, floor(value)));
}
double DY778RadarRetryInterval(double interval, unsigned failures) {
    double delay = DY778RadarInterval(interval);
    for (unsigned i = 0; i < failures && delay < 300; i++) delay *= 2;
    return fmin(300, delay);
}
bool DY778RadarDue(double now, double lastAttempt, double interval, unsigned failures) {
    return lastAttempt <= 0 || now - lastAttempt >= DY778RadarRetryInterval(interval, failures);
}
static bool contains(const char *key, const char *const *items, size_t count) {
    if (!key || !*key) return false;
    for (size_t i = 0; i < count; i++) if (items[i] && strcmp(key, items[i]) == 0) return true;
    return false;
}
size_t DY778RadarNewItems(const char *const *current, size_t count,
                  const char *const *previous, size_t previousCount,
                  const char *const *seen, size_t seenCount,
                  bool baselineValid, bool previousComplete,
                  bool *selected, bool *gap) {
    size_t limit = count, result = 0;
    *gap = false;
    for (size_t i = 0; i < count; i++) selected[i] = false;
    if (!baselineValid) return 0;
    if (!previousComplete) {
        for (size_t i = 0; i < count; i++) {
            if (contains(current[i], previous, previousCount)) { limit = i; break; }
        }
        // 无共同锚点：记为新观察到，绝不当作确切的点赞时间。
        *gap = limit == count && count > 0;
    }
    for (size_t i = 0; i < limit; i++) {
        if (!current[i] || !*current[i] || contains(current[i], previous, previousCount) ||
            contains(current[i], seen, seenCount) || contains(current[i], current, i)) continue;
        selected[i] = true;
        result++;
    }
    return result;
}
