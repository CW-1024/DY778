#ifndef DY778_EDIT_POLICY_H
#define DY778_EDIT_POLICY_H
#include <stdbool.h>
typedef enum { DY778EditIgnore, DY778EditBaseline, DY778EditFirstSeenEdited, DY778EditAppend } DY778EditDecision;
static inline DY778EditDecision DY778DecideEdit(bool valid, bool previous, bool edited, bool same,
    double previousTime, double currentTime, long long previousCount, long long currentCount) {
    if (!valid) return DY778EditIgnore;
    if (!previous) return edited ? DY778EditFirstSeenEdited : DY778EditBaseline;
    if (!edited) return DY778EditIgnore;
    if (currentTime > 0 && previousTime > currentTime) return DY778EditIgnore;
    if (currentCount > 0 && previousCount > currentCount) return DY778EditIgnore;
    bool newer = currentTime > previousTime || currentCount > previousCount;
    // A revision identity is authoritative even when the text was edited back.
    if (same) return DY778EditIgnore; // Metadata can arrive before the new body.
    if (newer) return DY778EditAppend;
    if (same || previousTime > 0 || previousCount > 0) return DY778EditIgnore;
    return DY778EditAppend; // Explicit edit with no usable server revision; label observation time.
}
static inline bool DY778EditShouldNotify(bool hadPrevious, bool hadCapturedVersion, long long previousChanges, long long currentChanges) {
    return hadPrevious && hadCapturedVersion && currentChanges > previousChanges;
}
#endif
