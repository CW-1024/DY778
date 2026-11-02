#ifndef DY778_RECALL_POLICY_H
#define DY778_RECALL_POLICY_H
#include <stdbool.h>
typedef struct { bool persist; bool notify; } DY778RecallDecision;
static inline DY778RecallDecision DY778RecallDecide(bool enabled, bool hasPrevious, bool samePayload,
                                               bool previousRecalled, bool recalled,
                                               bool previousAvailable, bool available) {
    DY778RecallDecision result = { false, false };
    if (!enabled) return result;
    result.persist = !hasPrevious || !samePayload || previousRecalled != recalled;
    result.notify = (!previousRecalled && recalled) || (recalled && !previousAvailable && available);
    return result;
}
static inline bool DY778RecallShouldNormalizeBubbleSkin(bool recalled, bool enabled, bool ordinaryText, bool hasSkin) {
    return recalled && enabled && ordinaryText && hasSkin;
}
static inline bool DY778RecallDisplayState(bool enabled, bool original, bool recorded, bool available) {
    return enabled && recorded && available ? false : original;
}
static inline bool DY778RecallShouldRestore(bool enabled, bool recalled, bool available, bool systemNotice,
                                          bool mutationInProgress, bool sameMessage, unsigned long revision,
                                          unsigned long renderedRevision) {
    return enabled && recalled && available && !systemNotice && !mutationInProgress && revision > 0 && (!sameMessage || revision != renderedRevision);
}
static inline bool DY778RecallShouldHydrate(bool storedAvailable, bool currentAvailable, bool storedRecalled, bool currentRecalled) {
    return storedAvailable && (!currentAvailable || storedRecalled || currentRecalled);
}
#endif
