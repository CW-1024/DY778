#ifndef DY778_LIVE_INFO_POLICY_H
#define DY778_LIVE_INFO_POLICY_H
#include <math.h>
#include <stdio.h>
#include <stdbool.h>
static inline void DY778LiveViewerCountLabel(char *buffer, size_t size, long long count, bool compact) {
    if (count < 0) count = 0;
    if (!compact || count < 10000) { snprintf(buffer,size,"%lld",count); return; }
    double value = (double)count / 10000.0;
    const char *units[] = {"万", "亿"};
    unsigned unit = 0;
    while (value >= 9999.95 && unit < 1) { value /= 10000.0; unit++; }
    value = round(value * 10.0) / 10.0;
    snprintf(buffer,size,value == floor(value) ? "%.0f%s" : "%.1f%s",value,units[unit]);
}
static inline double DY778LiveTimestamp(double value) {
    if (!isfinite(value) || value <= 0) return 0;
    if (value > 1e17) value /= 1e9;
    else if (value > 1e14) value /= 1e6;
    else if (value > 1e11) value /= 1e3;
    return value >= 1e9 && value < 1e11 ? value : 0;
}
static inline double DY778LiveElapsed(double start, double now) {
    start = DY778LiveTimestamp(start);
    if (!start || !isfinite(now) || start > now + 5 || now-start > 366*86400) return -1;
    return fmax(0, now-start);
}
static inline void DY778LiveDurationLabel(char *buffer, size_t size, double elapsed) {
    if (!isfinite(elapsed) || elapsed < 0 || elapsed > 366*86400) { if (size) buffer[0]=0; return; }
    unsigned long long seconds=(unsigned long long)elapsed;
    snprintf(buffer,size,"%02llu:%02llu:%02llu",seconds/3600,(seconds/60)%60,seconds%60);
}
static inline double DY778LiveRefreshInterval(double value) { return isfinite(value) ? fmin(10,fmax(2,round(value))) : 3; }
static inline double DY778LivePosition(double value) { return isfinite(value) ? fmin(1,fmax(0,value)) : .5; }
static inline bool DY778LiveCapsuleStack(double minimumY, double maximumY, double anchorTop, double anchorBottom,
                                         double firstHeight, double secondHeight, double *top, double *secondTop) {
    if (!top || !secondTop || !isfinite(minimumY) || !isfinite(maximumY) || !isfinite(anchorTop) || !isfinite(anchorBottom) ||
        !isfinite(firstHeight) || !isfinite(secondHeight) || maximumY<=minimumY || anchorBottom<anchorTop || firstHeight<0 || secondHeight<0) return false;
    double total=firstHeight+secondHeight+(firstHeight>0 && secondHeight>0 ? 6 : 0);
    if (total<=0 || total>maximumY-minimumY) return false;
    double y=anchorTop-8-total;
    if (y<minimumY || y+total>maximumY) y=anchorBottom+8;
    if (y<minimumY || y+total>maximumY) return false;
    *top=y; *secondTop=y+(firstHeight>0 ? firstHeight+(secondHeight>0 ? 6 : 0) : 0);
    return true;
}
#endif
