#ifndef DY778_APP_TARGET_H
#define DY778_APP_TARGET_H
#include <string.h>

static inline int DY778AppTargetMatches(const char *bundleID, const char *executable) {
    if (bundleID && (!strcmp(bundleID, "com.ss.iphone.ugc.Aweme") ||
                     !strcmp(bundleID, "com.ss.iphone.ugc.aweme.lite"))) return 1;
    return executable && (!strcmp(executable, "Aweme") || !strcmp(executable, "AwemeHM"));
}
#endif
