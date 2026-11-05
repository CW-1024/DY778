#ifndef DY778RadarPolicy_h
#define DY778RadarPolicy_h
#include <stdbool.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
bool DY778RadarNoticeReady(double now, double shownAt);
double DY778RadarInterval(double value);
double DY778RadarRetryInterval(double interval, unsigned failures);
bool DY778RadarDue(double now, double lastAttempt, double interval, unsigned failures);
size_t DY778RadarNewItems(const char *const *current, size_t count,
                  const char *const *previous, size_t previousCount,
                  const char *const *seen, size_t seenCount,
                  bool baselineValid, bool previousComplete,
                  bool *selected, bool *gap);
#ifdef __cplusplus
}
#endif
#endif
